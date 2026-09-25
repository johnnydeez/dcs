-- Stage 3b: plan the fixed ground targets of both coalitions: everything on the ground
-- worth attacking that doesn't move and isn't a SAM site — garrisons, armor and artillery
-- at the front, depots, headquarters and communications behind it, parked aircraft and
-- fuel storage at airfields. Mobile targets are a separate, later stage.
-- Reads plan.world, plan.territory, plan.base_defenses (units already standing at each
-- airfield), plan.sam_sites (zones already used) + data/fixed_ground_target_recipes.lua,
-- data/fixed_ground_target_density.lua and COALITION_FIXED_GROUND_TARGET_ROSTER.
-- Writes plan.fixed_ground_targets. Spawns nothing.
--
-- Per coalition, three passes, in the same shape as the SAM stage:
--   1. minimum    FIXED_GROUND_TARGET_DENSITY[coalition].minimum sites of each kind,
--                 in the candidates that fit best
--   2. zones      every free zone the coalition holds: chance by echelon → a kind that
--                 fits the zone's classes (data/zones.lua)
--   3. airfields  every base it holds: parked aircraft and fuel storage by base class
-- Each site is laid out from its recipe: units go in one DCS group (the site id), the
-- rest are static objects.
--
-- plan.fixed_ground_targets = {
--   sites          = { { id, kind, label, coalition, location, zone | base, area, cluster,
--                        echelon, pos, value, mission_types, success, group_ids,
--                        static_object_ids, critical_names, units, static_objects } },
--   groups         = { spawn-ready, same shape as base defenses / SAM sites:
--                      { id, side, skill, purpose, site, pos, units = { { type, x, z, heading_deg } } } },
--   static_objects = { { id, coalition, type, category, shape_name, x, z, heading_deg, site } },
--   zones_used     = { [zone name] = site id },
--   parking_used   = { [base] = { [parking terminal index] = site id } },
--   summary        = { red = { zones_free, sites, by_kind, left_free }, blue = … },
-- }
-- Ids: TGT_<CODE>_<kind>_<n> (e.g. TGT_OLEN_parked_aircraft_1), CODE from the zone's or
-- base's airbase. The id is the DCS group name (units <id>_<n>); static objects are
-- named <id>_static_<n>.

PlanFixedGroundTargets = {}

local COALITIONS   = { "red", "blue" }
local ECHELONS     = { "front", "mid", "rear" }
local IS_ECHELON   = { front = true, mid = true, rear = true }
local LOCATIONS    = { zone = true, parking_spot = true, airfield_ground = true }
local FORMS        = { unit = true, static_object = true }
local PLACE_ORDER  = { "centre", "middle", "outer" }
local TRIES_OBJECT = 40
local TRIES_SITE   = 80
local ZONE_REACH_M = 5000   -- zones this close to an airfield stay clear of its targets
local AIRFIELD_CLEARANCE_M = 40   -- airfield targets keep this far from units standing there

-- Class values tools/miz_zones.py writes into data/zones.lua (keep in step with it).
local ZONE_CLASS_VALUES = {}
for class, values in pairs({
    size                  = { "small", "medium", "large" },
    airfield_distance     = { "at_airfield", "near_airfield", "remote" },
    ground                = { "flat", "uneven", "steep" },
    terrain               = { "high_ground", "level", "low_ground" },
    road_access           = { "road_in_zone", "road_nearby", "no_road" },
    railway_access        = { "railway_nearby", "no_railway" },
    water                 = { "waterside", "near_water", "inland" },
    radar_view            = { "open", "partial", "masked" },
    settlement            = { "town", "village", "none" },
    prepared_sam_position = { "revetments", "none" },
}) do
    ZONE_CLASS_VALUES[class] = {}
    for _, v in ipairs(values) do ZONE_CLASS_VALUES[class][v] = true end
end

-- Parking terminal types (DCS Term_Type, see gather.lua) each kind of aircraft may use.
local TERMINALS_LARGE      = { [104] = true }
local TERMINALS_AIRPLANE   = { [68] = true, [72] = true, [104] = true }
local TERMINALS_HELICOPTER = { [40] = true, [72] = true, [104] = true }

-- Static-object category for a parked vehicle, from its pool category (the ME's spelling).
local VEHICLE_STATIC_CATEGORY = { AirDefence = "Air Defence" }

local function round(v) return math.floor(v + 0.5) end

-- 4-letter code of an airbase for ids (data/airbase_codes.lua), derived if missing.
local function codeFor(base)
    return AIRBASE_CODE[base] or base:gsub("%W", ""):upper():sub(1, 4)
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

-- ── data checks ─────────────────────────────────────────────────

local function typeKnown(form, t)
    if form == "unit" then return UNIT_POOL.ground[t] ~= nil end
    return UNIT_POOL.static[t] ~= nil or UNIT_POOL.ground[t] ~= nil
        or UNIT_POOL.plane[t] ~= nil or UNIT_POOL.helicopter[t] ~= nil
end

local function isAircraft(t) return UNIT_POOL.plane[t] ~= nil or UNIT_POOL.helicopter[t] ~= nil end

function PlanFixedGroundTargets.validate()
    local problems = {}
    local function bad(msg) problems[#problems + 1] = msg end
    local ROSTER = COALITION_FIXED_GROUND_TARGET_ROSTER or {}

    local function checkRole(where, role, form, aircraftOnly)
        for _, c in ipairs(COALITIONS) do
            local list = ROSTER[c] and ROSTER[c][role]
            if not list or #list == 0 then
                bad(string.format("%s: role '%s' has no %s roster", where, tostring(role), c))
            else
                for _, e in ipairs(list) do
                    if not typeKnown(form, e[1]) then
                        bad(string.format("roster %s.%s: '%s' is not a known %s type", c, role, tostring(e[1]),
                            form == "unit" and "ground unit" or "static object"))
                    elseif aircraftOnly and not isAircraft(e[1]) then
                        bad(string.format("roster %s.%s: '%s' is not an aircraft", c, role, tostring(e[1])))
                    end
                    if type(e[2]) ~= "number" or e[2] <= 0 then
                        bad(string.format("roster %s.%s: '%s' needs a positive weight", c, role, tostring(e[1])))
                    end
                end
            end
        end
    end

    local function checkClasses(where, spec)
        for class, values in pairs(spec or {}) do
            local known = ZONE_CLASS_VALUES[class]
            if not known then
                bad(string.format("%s: '%s' is not a zone class", where, tostring(class)))
            elseif type(values) ~= "table" or #values == 0 then
                bad(string.format("%s.%s needs a list of values", where, class))
            else
                for _, v in ipairs(values) do
                    if not known[v] then bad(string.format("%s.%s: '%s' is not a %s value", where, class, tostring(v), class)) end
                end
            end
        end
    end

    for kind, r in pairs(FIXED_GROUND_TARGET_RECIPE) do
        local where = "recipe '" .. kind .. "'"
        if type(r.label) ~= "string" then bad(where .. " needs a label") end
        if not LOCATIONS[r.location] then bad(where .. ": unknown location '" .. tostring(r.location) .. "'") end
        if type(r.echelons) ~= "table" or #r.echelons == 0 then bad(where .. " needs echelons") end
        for _, e in ipairs(r.echelons or {}) do
            if not IS_ECHELON[e] then bad(where .. ": unknown echelon '" .. tostring(e) .. "'") end
        end
        if type(r.value) ~= "number" then bad(where .. " needs a value") end
        if type(r.mission_types) ~= "table" or #r.mission_types == 0 then bad(where .. " needs mission_types") end
        local f = r.success and r.success.critical_fraction
        if type(f) ~= "number" or f <= 0 or f > 1 then bad(where .. ": success.critical_fraction must be in (0, 1]") end

        if r.location == "parking_spot" then
            if type(r.aircraft) ~= "table" or #r.aircraft ~= 2 or r.aircraft[1] > r.aircraft[2] then
                bad(where .. ": aircraft must be { min, max }")
            end
            for class, roles in pairs(r.aircraft_roles_by_base_class or {}) do
                if not BASE_DEFENSE_LEVEL[class] then bad(where .. ": unknown base class '" .. tostring(class) .. "'") end
                for _, e in ipairs(roles) do checkRole(where, e[1], "static_object", true) end
            end
        else
            if type(r.footprint_m) ~= "number" or type(r.unit_spacing) ~= "number" then
                bad(where .. " needs footprint_m and unit_spacing")
            end
            if type(r.parts) ~= "table" or #r.parts == 0 then bad(where .. " needs parts") end
            local critical = false
            for _, part in ipairs(r.parts or {}) do
                local pw = string.format("%s part '%s'", where, tostring(part[1]))
                if type(part[2]) ~= "number" or type(part[3]) ~= "number" or part[2] > part[3] then
                    bad(pw .. ": needs min <= max")
                end
                if not FIXED_GROUND_TARGET_PLACE[part[4]] then bad(pw .. ": unknown place '" .. tostring(part[4]) .. "'") end
                if not FORMS[part.form] then bad(pw .. ": form must be unit or static_object") end
                if part.critical then critical = true end
                checkRole(where, part[1], part.form)
            end
            if not critical then bad(where .. " has no critical part") end
            if r.location == "zone" then
                checkClasses(where .. ".requires", r.requires)
                checkClasses(where .. ".prefers", r.prefers)
            elseif r.location == "airfield_ground" then
                if type(r.anchors) ~= "table" or not next(r.anchors) then bad(where .. " needs anchors") end
                for k, s in pairs(r.anchors or {}) do
                    if type(s) ~= "table" or #s ~= 3 or s[2] > s[3] then
                        bad(string.format("%s anchor '%s' must be { weight, min_m, max_m }", where, k))
                    end
                end
            end
        end
    end

    checkClasses("FIXED_GROUND_TARGET_EXCLUDED_ZONE_CLASSES", FIXED_GROUND_TARGET_EXCLUDED_ZONE_CLASSES)

    for _, c in ipairs(COALITIONS) do
        local d = FIXED_GROUND_TARGET_DENSITY[c]
        local where = "FIXED_GROUND_TARGET_DENSITY." .. c
        if not d then
            bad(where .. " is missing")
        else
            for _, e in ipairs(ECHELONS) do
                if type((d.zone_chance or {})[e]) ~= "number" then bad(where .. ".zone_chance needs " .. e) end
                for _, k in ipairs((d.zone_kinds or {})[e] or {}) do
                    local r = FIXED_GROUND_TARGET_RECIPE[k[1]]
                    if not r then
                        bad(string.format("%s.zone_kinds.%s: unknown kind '%s'", where, e, tostring(k[1])))
                    elseif r.location ~= "zone" then
                        bad(string.format("%s.zone_kinds.%s: '%s' is not a zone kind", where, e, k[1]))
                    else
                        local ok = false
                        for _, re in ipairs(r.echelons) do if re == e then ok = true end end
                        if not ok then bad(string.format("%s.zone_kinds.%s: '%s' never goes at the %s", where, e, k[1], e)) end
                    end
                    if type(k[2]) ~= "number" or k[2] <= 0 then bad(string.format("%s.zone_kinds.%s: '%s' needs a positive weight", where, e, tostring(k[1]))) end
                end
            end
            for kind, byClass in pairs(d.airfield_chance or {}) do
                local r = FIXED_GROUND_TARGET_RECIPE[kind]
                if not r or r.location == "zone" then bad(string.format("%s.airfield_chance: '%s' is not an airfield kind", where, kind)) end
                for class in pairs(byClass) do
                    if not BASE_DEFENSE_LEVEL[class] then bad(string.format("%s.airfield_chance.%s: unknown base class '%s'", where, kind, class)) end
                end
            end
            for _, list in ipairs({ "minimum", "max_per_kind" }) do
                for kind, n in pairs(d[list] or {}) do
                    if not FIXED_GROUND_TARGET_RECIPE[kind] then bad(string.format("%s.%s: unknown kind '%s'", where, list, kind)) end
                    if type(n) ~= "number" or n < 0 then bad(string.format("%s.%s.%s needs a count", where, list, kind)) end
                end
            end
        end
    end
    return problems
end

local _problems
function PlanFixedGroundTargets.checkData()
    if not _problems then
        _problems = PlanFixedGroundTargets.validate()
        for _, p in ipairs(_problems) do Log.error("fixed ground targets data: " .. p) end
        if #_problems == 0 then Log.info("fixed ground targets data: OK") end
    end
    return _problems
end

-- ── candidates ──────────────────────────────────────────────────

local function echelonOf(km)
    if not km then return "rear" end
    if km <= CONFIG.ECHELON_FRONT_KM then return "front" end
    if km <= CONFIG.ECHELON_MID_KM then return "mid" end
    return "rear"
end

-- True if the zone has a class in FIXED_GROUND_TARGET_EXCLUDED_ZONE_CLASSES.
local function zoneExcluded(zone)
    for class, values in pairs(FIXED_GROUND_TARGET_EXCLUDED_ZONE_CLASSES or {}) do
        for _, v in ipairs(values) do
            if zone[class] == v then return true end
        end
    end
    return false
end

-- This coalition's zones that no SAM site uses and no exclusion rules out:
-- { zone, echelon, threat, area }. threat = direction of the nearest enemy base
-- (radians, atan2(dz, dx)). Counts excluded zones in ctx.sum.zones_excluded.
local function freeZones(ctx)
    local plan, list = ctx.plan, {}
    local samUsed = plan.sam_sites and plan.sam_sites.zones_used or {}
    for _, name in ipairs(plan.world.zone_list) do
        local tz = plan.territory.zones[name]
        local zone = plan.world.zones[name]
        if not tz or tz.side ~= ctx.coalition or samUsed[name] then
            -- not this coalition's, or a SAM site stands in it
        elseif zoneExcluded(zone) then
            ctx.sum.zones_excluded = ctx.sum.zones_excluded + 1
        else
            local enemy, enemyD
            for base, b in pairs(plan.territory.bases) do
                if b.side ~= ctx.coalition then
                    local d = Util.dist(zone.pos, plan.world.airbases[base].pos)
                    if not enemyD or d < enemyD then enemy, enemyD = base, d end
                end
            end
            local threat = 0
            if enemy then
                local e = plan.world.airbases[enemy].pos
                threat = math.atan2(e.z - zone.pos.z, e.x - zone.pos.x)
            end
            list[#list + 1] = { zone = zone, echelon = echelonOf(enemyD and enemyD / 1000),
                                threat = threat, area = zone.base }
        end
    end
    return list
end

-- This coalition's bases: { name, class, echelon, code, kinds = {} }, sorted by name.
local function heldBases(ctx)
    local list = {}
    for _, name in ipairs(sortedKeys(ctx.plan.territory.bases)) do
        local b = ctx.plan.territory.bases[name]
        if b.side == ctx.coalition then
            list[#list + 1] = { name = name, class = AIRBASE_CLASS[name] or "strip", echelon = b.echelon,
                                cluster = b.cluster, code = codeFor(name), kinds = {}, tried = {} }
        end
    end
    return list
end

local function listHas(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

-- True if the zone has every class the recipe requires, at an echelon it may go.
local function zoneFits(recipe, cand)
    if recipe.location ~= "zone" or not listHas(recipe.echelons, cand.echelon) then return false end
    local r = Placement.zoneRadius(cand.zone)
    if r <= 0 then return false end
    for class, allowed in pairs(recipe.requires or {}) do
        if not listHas(allowed, cand.zone[class]) then return false end
    end
    return true
end

-- How many of the recipe's preferred classes the zone has.
local function preferenceCount(recipe, zone)
    local n = 0
    for class, wanted in pairs(recipe.prefers or {}) do
        if listHas(wanted, zone[class]) then n = n + 1 end
    end
    return n
end

local function kindAtCap(ctx, kind)
    local cap = ctx.density.max_per_kind and ctx.density.max_per_kind[kind]
    return cap ~= nil and (ctx.sum.by_kind[kind] or 0) >= cap
end

-- Why a zone can't take another site of this coalition, or nil.
local function zoneBlocked(ctx, cand)
    if cand.used then return "used" end
    if (ctx.per_area[cand.area] or 0) >= FIXED_GROUND_TARGET_MAX_PER_AREA then return "area full" end
    local minM = FIXED_GROUND_TARGET_MIN_SPACING_KM * 1000
    for _, p in ipairs(ctx.zone_sites) do
        if Util.dist(p, cand.zone.pos) < minM then return "spacing" end
    end
    return nil
end

-- ── layout ──────────────────────────────────────────────────────

local function annulusPoint(centre, radius, fracs)
    local r1, r2 = radius * fracs[1], radius * fracs[2]
    local d = math.sqrt(r1 * r1 + math.random() * (r2 * r2 - r1 * r1))
    local a = math.random() * 2 * math.pi
    return { x = centre.x + d * math.cos(a), z = centre.z + d * math.sin(a) }
end

-- Zones were surveyed as open, so a zone object may fall back to checking only the
-- point itself; at an airfield nothing relaxes beyond half spacing.
local ZONE_STEPS     = { { 1, Placement.isClear }, { 0.5, Placement.isClear },
                         { 1, Placement.isClearRoad }, { 0.5, Placement.isClearRoad } }
local AIRFIELD_STEPS = { { 1, Placement.isClear }, { 0.5, Placement.isClear } }

-- One object `spacing` m from everything in `occupied` (and at least `keep` m from any
-- occupied point that has one). Returns the point or nil.
local function placeOne(view, centre, radius, fracs, spacing, occupied, steps, rejects)
    for _, step in ipairs(steps) do
        local sp2 = (spacing * step[1]) ^ 2
        local p, rj = Placement.findClear(view, function() return annulusPoint(centre, radius, fracs) end,
            TRIES_OBJECT, function(q)
                for _, o in ipairs(occupied) do
                    local dx, dz = q.x - o.x, q.z - o.z
                    if dx * dx + dz * dz < math.max(sp2, (o.keep or 0) ^ 2) then return false, "spacing" end
                end
                return true
            end, step[2])
        for k, v in pairs(rj) do rejects[k] = (rejects[k] or 0) + v end
        if p then return p end
    end
    return nil
end

-- Lays out a recipe's parts around centre. Units face `heading` (radians) give or take
-- ~35° when given; static objects face anywhere. Returns the objects
-- { part, type, x, z, heading_deg }, or nil and why when a critical part found no room.
local function layoutParts(ctx, recipe, view, centre, radius, steps, occupied, heading)
    local roster = COALITION_FIXED_GROUND_TARGET_ROSTER[ctx.coalition]
    local objects, missing = {}, 0
    for _, place in ipairs(PLACE_ORDER) do
        for _, part in ipairs(recipe.parts) do
            if part[4] == place then
                local n = math.random(part[2], part[3])
                local fixedType = part.same_type and Util.weightedPick(roster[part[1]]) or nil
                local placed = 0
                for _ = 1, n do
                    local t = fixedType or Util.weightedPick(roster[part[1]])
                    local p = placeOne(view, centre, radius, FIXED_GROUND_TARGET_PLACE[place],
                        part.spacing_m or recipe.unit_spacing, occupied, steps, ctx.sum.rejects)
                    if p then
                        local h = (part.form == "unit" and heading) and heading + (math.random() - 0.5) * 1.2
                                  or math.random() * 2 * math.pi
                        local o = { part = part, type = t, x = round(p.x), z = round(p.z),
                                    heading_deg = round(math.deg(h)) % 360 }
                        objects[#objects + 1] = o
                        occupied[#occupied + 1] = o
                        placed = placed + 1
                    else
                        missing = missing + 1
                    end
                end
                if part.critical and part[2] > 0 and placed == 0 then
                    return nil, "no room for " .. part[1]
                end
            end
        end
    end
    return objects, nil, missing
end

-- Static-object category and shape for a type (structure, parked vehicle or aircraft).
local function staticCategory(t)
    local s = UNIT_POOL.static[t]
    if s then return s.category, s.shape_name end
    if UNIT_POOL.plane[t] then return "Planes" end
    if UNIT_POOL.helicopter[t] then return "Helicopters" end
    local g = UNIT_POOL.ground[t]
    return g and (VEHICLE_STATIC_CATEGORY[g.cat] or g.cat) or nil
end

-- Turns laid-out objects into the site record, its DCS group (if it has units) and its
-- static objects, and books it. info = { kind, code, location, zone | base, area,
-- cluster, echelon, pos }.
local function assembleSite(ctx, info, objects)
    local out, sum, coalition = ctx.out, ctx.sum, ctx.coalition
    local recipe = FIXED_GROUND_TARGET_RECIPE[info.kind]
    local code = info.code
    local key  = code .. "|" .. info.kind
    ctx.ids[key] = (ctx.ids[key] or 0) + 1
    local id = string.format("TGT_%s_%s_%d", code, info.kind, ctx.ids[key])

    local units, staticIds, critical = {}, {}, {}
    for _, o in ipairs(objects) do
        if o.part.form == "unit" then
            units[#units + 1] = { type = o.type, x = o.x, z = o.z, heading_deg = o.heading_deg }
            if o.part.critical then critical[#critical + 1] = id .. "_" .. #units end
        else
            local name = string.format("%s_static_%d", id, #staticIds + 1)
            local category, shape = staticCategory(o.type)
            out.static_objects[#out.static_objects + 1] = {
                id = name, coalition = coalition, type = o.type, category = category, shape_name = shape,
                x = o.x, z = o.z, heading_deg = o.heading_deg, site = id }
            staticIds[#staticIds + 1] = name
            if o.part.critical then critical[#critical + 1] = name end
        end
    end
    local pos = Util.withLatLon({ x = round(info.pos.x), z = round(info.pos.z) })
    if #units > 0 then
        out.groups[#out.groups + 1] = { id = id, side = coalition, skill = FIXED_GROUND_TARGET_SKILL,
            purpose = "fixed_ground_target", site = id, pos = pos, units = units }
    end
    local site = {
        id = id, kind = info.kind, label = recipe.label, coalition = coalition, location = info.location,
        zone = info.zone, base = info.base, area = info.area, cluster = info.cluster, echelon = info.echelon,
        pos = pos, value = recipe.value, mission_types = recipe.mission_types, success = recipe.success,
        group_ids = #units > 0 and { id } or {}, static_object_ids = staticIds, critical_names = critical,
        units = #units, static_objects = #staticIds,
    }
    out.sites[#out.sites + 1] = site
    sum.sites = sum.sites + 1
    sum.by_kind[info.kind] = (sum.by_kind[info.kind] or 0) + 1
    Log.info(string.format("  %-34s %-4s %-21s %-5s %-24s %2d units, %2d static objects",
        id, coalition:upper(), recipe.label, info.echelon, info.zone or info.base, #units, #staticIds))
    return site
end

-- ── site builders ───────────────────────────────────────────────

local function buildZoneSite(ctx, cand, kind)
    local recipe = FIXED_GROUND_TARGET_RECIPE[kind]
    local zone   = cand.zone
    local radius = math.min(Placement.zoneRadius(zone), recipe.footprint_m)
    -- the zone's nearest airfield still keeps its runways and parking clear
    local ab   = ctx.plan.world.airbases[zone.base]
    local view = { runways = ab and ab.runways, parking = ab and ab.parking }
    local objects, why = layoutParts(ctx, recipe, view, zone.pos, radius, ZONE_STEPS, {}, cand.threat)
    cand.used = true   -- tried: a zone too cramped for this kind isn't retried
    if not objects then
        Log.warn(string.format("  %s: %s dropped (%s)", zone.name, recipe.label, why))
        return nil
    end
    local site = assembleSite(ctx, { kind = kind, code = codeFor(zone.base), location = "zone",
        zone = zone.name, area = cand.area, cluster = zone.cluster, echelon = cand.echelon, pos = zone.pos }, objects)
    ctx.out.zones_used[zone.name] = site.id
    ctx.zone_sites[#ctx.zone_sites + 1] = zone.pos
    ctx.per_area[cand.area] = (ctx.per_area[cand.area] or 0) + 1
    return site
end

local function zonesNear(world, pos)
    local out = {}
    for _, name in ipairs(world.zone_list) do
        local z = world.zones[name]
        if Util.dist(z.pos, pos) <= ZONE_REACH_M then out[#out + 1] = z end
    end
    return out
end

-- The placement view of a base, built on first use: geometry, anchors, and every unit
-- already standing there (base defenses, then targets as they are placed).
local function baseView(ctx, b)
    if b.view then return end
    local world = ctx.plan.world
    local wab = world.airbases[b.name]
    b.view = { anchor = wab.anchor, runways = wab.runways, parking = wab.parking,
               forested = FORESTED_AIRFIELDS[b.name] == true, zones = zonesNear(world, wab.pos) }
    b.anchors = Placement.buildAnchors(b.view, AIRBASE_FOOTPRINT[b.name])
    b.occupied = {}
    for _, g in ipairs(ctx.plan.base_defenses and ctx.plan.base_defenses.groups or {}) do
        if g.base == b.name then
            for _, u in ipairs(g.units) do
                b.occupied[#b.occupied + 1] = { x = u.x, z = u.z, keep = AIRFIELD_CLEARANCE_M }
            end
        end
    end
end

local function buildAirfieldGroundSite(ctx, b, kind)
    local recipe = FIXED_GROUND_TARGET_RECIPE[kind]
    baseView(ctx, b)
    local keep2 = (recipe.footprint_m + AIRFIELD_CLEARANCE_M) ^ 2
    local centre = Placement.findClear(b.view, function()
        local p = Placement.pickAnchorPoint(b.anchors, recipe.anchors)
        return p
    end, TRIES_SITE, function(q)
        for _, o in ipairs(b.occupied) do
            if (q.x - o.x) ^ 2 + (q.z - o.z) ^ 2 < keep2 then return false, "occupied" end
        end
        return true
    end)
    if not centre then
        Log.info(string.format("  %s: no open ground for %s", b.name, recipe.label))
        return nil
    end
    local objects, why = layoutParts(ctx, recipe, b.view, centre, recipe.footprint_m, AIRFIELD_STEPS, b.occupied, nil)
    if not objects then
        Log.info(string.format("  %s: %s dropped (%s)", b.name, recipe.label, why))
        return nil
    end
    local site = assembleSite(ctx, { kind = kind, code = b.code, location = "airfield_ground", base = b.name,
        area = b.name, cluster = b.cluster, echelon = b.echelon, pos = centre }, objects)
    b.kinds[kind] = true
    return site
end

-- Heading (radians) from a parking spot toward the nearest point of the nearest runway's
-- centreline: parked aircraft face the taxiway side rather than a random way.
local function noseTowardRunway(runways, x, z)
    local best, bestD2
    for _, rw in ipairs(runways or {}) do
        local h = math.rad(rw.heading_deg)
        local along = (x - rw.x) * math.cos(h) + (z - rw.z) * math.sin(h)
        along = math.max(-rw.length / 2, math.min(rw.length / 2, along))
        local px, pz = rw.x + along * math.cos(h), rw.z + along * math.sin(h)
        local d2 = (px - x) ^ 2 + (pz - z) ^ 2
        if not bestD2 or d2 < bestD2 then best, bestD2 = { x = px, z = pz }, d2 end
    end
    if not best or bestD2 < 1 then return math.random() * 2 * math.pi end
    return math.atan2(best.z - z, best.x - x)
end

local function buildParkingSite(ctx, b, kind)
    local recipe = FIXED_GROUND_TARGET_RECIPE[kind]
    local roles  = recipe.aircraft_roles_by_base_class[b.class]
    local wab    = ctx.plan.world.airbases[b.name]
    local spots  = wab.parking or {}
    if not roles or #spots == 0 then return nil end
    local used = ctx.out.parking_used[b.name] or {}
    local usedCount = 0
    for _ in pairs(used) do usedCount = usedCount + 1 end
    local room = math.floor(#spots * FIXED_GROUND_TARGET_PARKING_SHARE_MAX) - usedCount
    if room <= 0 then return nil end

    -- One aircraft type for the whole group, so it reads as a squadron: roles are tried in
    -- weighted order until one's type has a free spot it fits.
    local roster = COALITION_FIXED_GROUND_TARGET_ROSTER[ctx.coalition]
    local order, pool = {}, {}
    for i, e in ipairs(roles) do pool[i] = e end
    while #pool > 0 do
        local role = Util.weightedPick(pool)
        order[#order + 1] = role
        for i, e in ipairs(pool) do
            if e[1] == role then table.remove(pool, i) break end
        end
    end
    local t, fitting
    for _, role in ipairs(order) do
        t = Util.weightedPick(roster[role])
        local allowed = UNIT_POOL.helicopter[t] and TERMINALS_HELICOPTER
                        or (UNIT_POOL.plane[t].large_parking and TERMINALS_LARGE or TERMINALS_AIRPLANE)
        fitting = {}
        for k, s in ipairs(spots) do
            if not used[s[4] or k] and (s[3] == nil or allowed[s[3]]) then fitting[#fitting + 1] = k end
        end
        if #fitting > 0 then break end
    end
    if #fitting == 0 then return nil end

    -- Parked together: the seed is the fitting spot with the most fitting neighbours within
    -- reach (ties at random), and the group fills its nearest neighbours outward.
    local reach2 = FIXED_GROUND_TARGET_PARKED_AIRCRAFT_REACH_M ^ 2
    local function d2(a, b2) return (spots[a][1] - spots[b2][1]) ^ 2 + (spots[a][2] - spots[b2][2]) ^ 2 end
    local seed, seedScore
    for _, a in ipairs(fitting) do
        local n = 0
        for _, c in ipairs(fitting) do
            if d2(a, c) <= reach2 then n = n + 1 end
        end
        local score = n + math.random() * 0.5
        if not seedScore or score > seedScore then seed, seedScore = a, score end
    end
    local line = {}
    for _, c in ipairs(fitting) do
        if d2(seed, c) <= reach2 then line[#line + 1] = c end
    end
    table.sort(line, function(a, c) return d2(seed, a) < d2(seed, c) end)

    local part = { "parked_aircraft", form = "static_object", critical = true }
    local objects, taken = {}, {}
    local sx, sz = 0, 0
    for i = 1, math.min(math.random(recipe.aircraft[1], recipe.aircraft[2]), room, #line) do
        local k = line[i]
        local s = spots[k]
        taken[#taken + 1] = s[4] or k
        objects[#objects + 1] = { part = part, type = t, x = s[1], z = s[2],
            heading_deg = round(math.deg(noseTowardRunway(wab.runways, s[1], s[2]))) % 360 }
        sx, sz = sx + s[1], sz + s[2]
    end

    local site = assembleSite(ctx, { kind = kind, code = b.code, location = "parking_spot", base = b.name,
        area = b.name, cluster = b.cluster, echelon = b.echelon,
        pos = { x = sx / #objects, z = sz / #objects } }, objects)
    ctx.out.parking_used[b.name] = used
    for _, key in ipairs(taken) do used[key] = site.id end
    b.kinds[kind] = true
    return site
end

local function buildAirfieldSite(ctx, b, kind)
    if FIXED_GROUND_TARGET_RECIPE[kind].location == "parking_spot" then
        return buildParkingSite(ctx, b, kind)
    end
    return buildAirfieldGroundSite(ctx, b, kind)
end

-- ── passes ──────────────────────────────────────────────────────

-- FIXED_GROUND_TARGET_DENSITY[coalition].minimum, before the random passes. Zone kinds
-- go in the zone that fits best: most preferred classes, then an area without a target
-- yet, then chance. Airfield kinds go to the base most likely to have one anyway.
local function placeMinimumSites(ctx, zones, bases)
    local mins = ctx.density.minimum or {}
    for _, kind in ipairs(sortedKeys(mins)) do
        local recipe = FIXED_GROUND_TARGET_RECIPE[kind]
        while (ctx.sum.by_kind[kind] or 0) < mins[kind] do
            local best, bestScore
            if recipe.location == "zone" then
                for _, c in ipairs(zones) do
                    if not zoneBlocked(ctx, c) and zoneFits(recipe, c) then
                        local score = ((ctx.per_area[c.area] or 0) > 0 and 1e6 or 0)
                                    - preferenceCount(recipe, c.zone) * 1e3 + math.random()
                        if not bestScore or score < bestScore then best, bestScore = c, score end
                    end
                end
                if best then buildZoneSite(ctx, best, kind) end
            else
                local chance = ctx.density.airfield_chance and ctx.density.airfield_chance[kind] or {}
                for _, b in ipairs(bases) do
                    local p = chance[b.class] or 0
                    if p > 0 and not b.kinds[kind] and not b.tried[kind] then
                        local score = -p + math.random() * 0.01
                        if not bestScore or score < bestScore then best, bestScore = b, score end
                    end
                end
                if best then
                    best.tried[kind] = true
                    buildAirfieldSite(ctx, best, kind)
                end
            end
            if not best then
                Log.warn(string.format("  %s: only %d of %d %s — nothing else fits",
                    ctx.coalition:upper(), ctx.sum.by_kind[kind] or 0, mins[kind], recipe.label))
                break
            end
        end
    end
end

-- Every free zone: chance by echelon, then a kind that fits it, weighted up by the
-- classes it prefers.
local function fillZones(ctx, zones)
    local left = ctx.sum.left_free
    local order = {}
    for i = 1, #zones do order[i] = zones[i] end
    Util.shuffle(order)
    for _, c in ipairs(order) do
        local blocked = zoneBlocked(ctx, c)
        if blocked then
            if blocked ~= "used" then left[blocked] = (left[blocked] or 0) + 1 end
        elseif math.random() > ctx.density.zone_chance[c.echelon] then
            left["chance"] = (left["chance"] or 0) + 1
        else
            local choices = {}
            for _, e in ipairs(ctx.density.zone_kinds[c.echelon] or {}) do
                local recipe = FIXED_GROUND_TARGET_RECIPE[e[1]]
                if zoneFits(recipe, c) and not kindAtCap(ctx, e[1]) then
                    choices[#choices + 1] = { e[1], e[2] * (1 + FIXED_GROUND_TARGET_PREFERENCE_BONUS
                                                             * preferenceCount(recipe, c.zone)) }
                end
            end
            if #choices == 0 then
                left["nothing fits"] = (left["nothing fits"] or 0) + 1
            else
                buildZoneSite(ctx, c, Util.weightedPick(choices))
            end
        end
    end
end

-- Every held base: each airfield kind by its chance for the base's class.
local function fillAirfields(ctx, bases)
    local kinds = sortedKeys(ctx.density.airfield_chance)
    for _, b in ipairs(bases) do
        for _, kind in ipairs(kinds) do
            local p = ctx.density.airfield_chance[kind][b.class] or 0
            if not b.kinds[kind] and not kindAtCap(ctx, kind) and math.random() < p then
                buildAirfieldSite(ctx, b, kind)
            end
        end
    end
end

-- ── stage ───────────────────────────────────────────────────────

function PlanFixedGroundTargets.run(plan)
    Log.info("--- Stage 3b: fixed ground targets ---")
    local out = { sites = {}, groups = {}, static_objects = {}, zones_used = {}, parking_used = {}, summary = {} }
    plan.fixed_ground_targets = out
    if #PlanFixedGroundTargets.checkData() > 0 then
        out.problems = _problems
        return plan
    end

    local ids = {}   -- "OLEN|fuel_depot" → last n
    for _, coalition in ipairs(COALITIONS) do
        local sum = { zones_free = 0, zones_excluded = 0, sites = 0, by_kind = {}, left_free = {}, rejects = {} }
        out.summary[coalition] = sum
        local ctx = { plan = plan, out = out, sum = sum, ids = ids, coalition = coalition,
                      density = FIXED_GROUND_TARGET_DENSITY[coalition], per_area = {}, zone_sites = {} }
        local zones = freeZones(ctx)
        local bases = heldBases(ctx)
        sum.zones_free = #zones

        placeMinimumSites(ctx, zones, bases)
        fillZones(ctx, zones)
        fillAirfields(ctx, bases)

        local kinds, left = {}, {}
        for _, k in ipairs(sortedKeys(sum.by_kind)) do kinds[#kinds + 1] = k .. " " .. sum.by_kind[k] end
        for _, k in ipairs(sortedKeys(sum.left_free)) do left[#left + 1] = k .. " " .. sum.left_free[k] end
        local zoneSites = 0
        for _, s in ipairs(out.sites) do
            if s.coalition == coalition and s.location == "zone" then zoneSites = zoneSites + 1 end
        end
        Log.info(string.format("  %s: %d sites (%d in %d free zones; %d excluded)  [%s]  zones left free: %s",
            coalition:upper(), sum.sites, zoneSites, sum.zones_free, sum.zones_excluded, table.concat(kinds, ", "),
            #left > 0 and table.concat(left, ", ") or "none"))
    end
    return plan
end
