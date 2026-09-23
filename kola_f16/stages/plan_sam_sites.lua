-- Stage 3a: plan the SAM and early-warning network of both coalitions.
-- Reads plan.world (zones, airbases), plan.territory (who holds each zone and base),
-- plan.base_defenses (which bases are heavily defended) + data/sam_site_recipes.lua,
-- data/sam_site_density.lua and COALITION_SAM_SYSTEMS. Writes plan.sam_sites. Spawns
-- nothing.
--
-- Per zone a coalition holds: role (asset_ring / front_belt / rear_area, see
-- sam_site_density.lua) → chance → layer → a system of that layer that fits the zone →
-- the site laid out inside the zone from its recipe → one DCS group, plus an escort
-- group when the recipe names one. Every zone this stage uses is in zones_used, so
-- later stages (garrisons, targets) skip it.
--
-- plan.sam_sites = {
--   sites      = { { id, side, system, layer, role, zone, defends, pos, engage_m,
--                    detect_m, group_ids } },
--   groups     = { spawn-ready: { id, side, skill, purpose, site, pos,
--                                 units = { { type, x, z, heading_deg } } } },
--   zones_used = { [zone name] = site id },
--   summary    = { red = { zones_held, sites, by_layer = { [layer] = n } }, blue = … },
-- }
-- Group ids: SAM_<CODE>_<system>_<n> (e.g. SAM_OLEN_SA10_1), escorts <id>_escort.

PlanSamSites = {}

local LAYERS  = { "long_range", "medium_range", "short_range", "early_warning" }
local SMALLER = { long_range = "medium_range", medium_range = "short_range", short_range = "early_warning" }
local COALITIONS = { "red", "blue" }
local TRIES_UNIT = 40

-- ── data checks ─────────────────────────────────────────────────

function PlanSamSites.validate()
    local problems = {}
    local function bad(msg) problems[#problems + 1] = msg end
    local isLayer = {}
    for _, l in ipairs(LAYERS) do isLayer[l] = true end

    for id, r in pairs(SAM_SITE_RECIPE) do
        if not isLayer[r.layer] then bad(string.format("recipe '%s': unknown layer '%s'", id, tostring(r.layer))) end
        if type(r.footprint_m) ~= "number" or r.footprint_m <= 0 then bad("recipe '" .. id .. "' needs footprint_m") end
        if type(r.unit_spacing) ~= "number" then bad("recipe '" .. id .. "' needs unit_spacing") end
        for _, part in ipairs(r.parts or {}) do
            if not UNIT_POOL.ground[part[1]] then
                bad(string.format("recipe '%s': '%s' is not in UNIT_POOL.ground", id, tostring(part[1])))
            end
            if not SAM_SITE_PLACE[part[4]] then
                bad(string.format("recipe '%s': part '%s' has unknown place '%s'", id, tostring(part[1]), tostring(part[4])))
            end
        end
        if r.escort_role then
            for _, side in ipairs(COALITIONS) do
                local list = COALITION_ROSTER[side] and COALITION_ROSTER[side][r.escort_role]
                if not list or #list == 0 then
                    bad(string.format("recipe '%s': escort role '%s' has no %s roster", id, r.escort_role, side))
                end
            end
        end
    end

    for _, side in ipairs(COALITIONS) do
        for layer, list in pairs(COALITION_SAM_SYSTEMS[side] or {}) do
            for _, e in ipairs(list) do
                local r = SAM_SITE_RECIPE[e[1]]
                if not r then
                    bad(string.format("COALITION_SAM_SYSTEMS.%s.%s: no recipe '%s'", side, layer, tostring(e[1])))
                elseif r.layer ~= layer then
                    bad(string.format("COALITION_SAM_SYSTEMS.%s.%s: '%s' is a %s system", side, layer, e[1], r.layer))
                end
                if type(e[2]) ~= "number" or e[2] <= 0 then
                    bad(string.format("COALITION_SAM_SYSTEMS.%s.%s: '%s' needs a positive weight", side, layer, tostring(e[1])))
                end
            end
        end
    end

    local isRole = {}
    for _, role in ipairs(SAM_ZONE_ROLE_ORDER) do isRole[role] = true end
    for layer, order in pairs(SAM_SITE_MIN_ROLE_ORDER or {}) do
        if not isLayer[layer] then bad("SAM_SITE_MIN_ROLE_ORDER: unknown layer '" .. tostring(layer) .. "'") end
        for _, role in ipairs(order) do
            if not isRole[role] then bad(string.format("SAM_SITE_MIN_ROLE_ORDER.%s: unknown role '%s'", layer, tostring(role))) end
        end
    end
    for layer, fallback in pairs(SAM_SITE_OVER_CAP_LAYER or {}) do
        if not isLayer[layer] or not isLayer[fallback] then
            bad(string.format("SAM_SITE_OVER_CAP_LAYER: unknown layer in '%s' → '%s'", tostring(layer), tostring(fallback)))
        end
    end
    for side, mins in pairs(SAM_SITE_MIN_PER_LAYER or {}) do
        for layer, n in pairs(mins) do
            if not isLayer[layer] then bad(string.format("SAM_SITE_MIN_PER_LAYER.%s: unknown layer '%s'", side, tostring(layer))) end
            if type(n) ~= "number" or n < 0 then bad(string.format("SAM_SITE_MIN_PER_LAYER.%s.%s needs a count", side, tostring(layer))) end
        end
    end

    for _, role in ipairs(SAM_ZONE_ROLE_ORDER) do
        local d = SAM_SITE_DENSITY[role]
        if not d then
            bad("SAM_SITE_DENSITY has no role '" .. role .. "'")
        else
            for _, e in ipairs(d.layers) do
                if not isLayer[e[1]] then bad(string.format("SAM_SITE_DENSITY.%s: unknown layer '%s'", role, tostring(e[1]))) end
            end
        end
    end
    return problems
end

local _problems
function PlanSamSites.checkData()
    if not _problems then
        _problems = PlanSamSites.validate()
        for _, p in ipairs(_problems) do Log.error("SAM sites data: " .. p) end
        if #_problems == 0 then Log.info("SAM sites data: OK") end
    end
    return _problems
end

-- ── helpers ─────────────────────────────────────────────────────

local function round(v) return math.floor(v + 0.5) end

-- "SA-10" → "SA10", "IRIS-T SLM" → "IRISTSLM": the system as it appears in group ids.
local function systemSlug(system) return (system:gsub("[^%w]", "")) end

-- Longest engagement and detection range of any part (ED's data in UNIT_POOL).
local function siteRanges(recipe)
    local engage, detect = 0, 0
    for _, part in ipairs(recipe.parts) do
        local u = UNIT_POOL.ground[part[1]]
        engage = math.max(engage, u.threat_m or 0)
        detect = math.max(detect, u.detection_m or 0)
    end
    return engage, detect
end

-- Nearest base matching `want(name, territoryBase)`; returns name, distance in m.
local function nearestBase(plan, pos, want)
    local best, bestD
    for name, b in pairs(plan.territory.bases) do
        if want(name, b) then
            local d = Util.dist(pos, plan.world.airbases[name].pos)
            if not bestD or d < bestD then best, bestD = name, d end
        end
    end
    return best, bestD
end

-- How far from an enemy base a zone still counts as front belt this roll (m): the fixed
-- FRONT_BELT_KM, or the front gap (shortest distance between opposing bases) plus
-- FRONT_BELT_DEPTH_KM when the sides sit far apart.
local function frontBeltReach(plan)
    local km = SAM_ZONE_ROLE_KM.FRONT_BELT_KM
    local closest = plan.territory.front and plan.territory.front.adjacency[1]
    if closest then km = math.max(km, closest.km + SAM_ZONE_ROLE_KM.FRONT_BELT_DEPTH_KM) end
    return km * 1000
end

-- What a SAM site in this zone would be doing for `side`: role, what it defends, and
-- the direction the threat comes from (radians, atan2(dz, dx)).
local function zoneRole(plan, zone, side, frontReach)
    local enemy, enemyD = nearestBase(plan, zone.pos, function(_, b) return b.side ~= side end)
    local threat = 0
    if enemy then
        local e = plan.world.airbases[enemy].pos
        threat = math.atan2(e.z - zone.pos.z, e.x - zone.pos.x)
    end
    local levels = plan.base_defenses and plan.base_defenses.bases or {}
    local asset, assetD = nearestBase(plan, zone.pos, function(name, b)
        return b.side == side and levels[name] and SAM_DEFENDED_BASE_LEVELS[levels[name].level]
    end)
    if asset and assetD <= SAM_ZONE_ROLE_KM.ASSET_RING_KM * 1000 then
        return "asset_ring", asset, threat
    end
    if enemy and enemyD <= frontReach then
        return "front_belt", "front (facing " .. enemy .. ")", threat
    end
    return "rear_area", nil, threat
end

-- This side's systems of `layer` whose footprint fits a zone of radius r (weighted list).
local function systemsThatFit(side, layer, r)
    local fits = {}
    for _, e in ipairs(COALITION_SAM_SYSTEMS[side][layer] or {}) do
        if SAM_SITE_RECIPE[e[1]].footprint_m <= r then fits[#fits + 1] = e end
    end
    return fits
end

-- A system of `layer` that fits a zone of radius r. A layer at its SAM_SITE_MAX_PER_LAYER
-- cap (byLayer = this side's counts so far) moves to SAM_SITE_OVER_CAP_LAYER; one at its
-- SAM_SITE_MAX_PER_AREA cap (byLayerHere = counts in the zone's area) or one that doesn't
-- fit moves to the next smaller layer; each layer is tried once. Returns system, layer —
-- or nil, nil and why nothing was picked.
local function pickSystem(side, layer, r, byLayer, byLayerHere)
    local tried, capped = {}, {}
    while layer and not tried[layer] do
        tried[layer] = true
        local cap     = SAM_SITE_MAX_PER_LAYER[layer]
        local areaCap = SAM_SITE_MAX_PER_AREA[layer]
        if cap and (byLayer[layer] or 0) >= cap then
            capped[#capped + 1] = layer
            layer = SAM_SITE_OVER_CAP_LAYER[layer] or SMALLER[layer]
        elseif areaCap and (byLayerHere[layer] or 0) >= areaCap then
            capped[#capped + 1] = layer .. " in this area"
            layer = SMALLER[layer]
        else
            local fits = systemsThatFit(side, layer, r)
            if #fits > 0 then return Util.weightedPick(fits), layer end
            layer = SMALLER[layer]
        end
    end
    if #capped > 0 then
        return nil, nil, "nothing else fits; at cap: " .. table.concat(capped, ", ")
    end
    return nil, nil, "too small for any system"
end

-- The area a zone's site counts toward for SAM_SITE_MAX_PER_AREA, spreading the minimum
-- pass and SAM_REAR_SITES_PER_BASE_MAX: the heavily defended base it guards, otherwise
-- the base its zone is named after.
local function zoneArea(role, defends, zone)
    return role == "asset_ring" and defends or zone.base
end

-- The id of this side's site closer than SAM_SITE_MIN_SPACING_KM to the zone, if any.
local function siteTooClose(ctx, zone)
    local minM = SAM_SITE_MIN_SPACING_KM * 1000
    for _, site in ipairs(ctx.out.sites) do
        if site.side == ctx.side and Util.dist(site.pos, zone.pos) < minM then return site.id end
    end
    return nil
end

-- Counts of this side's sites per layer (and .all) in an area, created on first use.
local function layersInArea(ctx, area)
    ctx.per_area[area] = ctx.per_area[area] or {}
    return ctx.per_area[area]
end

-- Random point in the annulus fracs = { inner, outer } × radius around centre.
local function annulusPoint(centre, radius, fracs)
    local r1, r2 = radius * fracs[1], radius * fracs[2]
    local d = math.sqrt(r1 * r1 + math.random() * (r2 * r2 - r1 * r1))
    local a = math.random() * 2 * math.pi
    return { x = centre.x + d * math.cos(a), z = centre.z + d * math.sin(a) }
end

-- Places `n` units of `unitType` into `units`, keeping `spacing` from everything in
-- `occupied`. Tries full spacing on clear ground, then half spacing, then drops the
-- ground-ring check (the zone was surveyed as open; only the point itself must be
-- land). Units face `heading` (radians) give or take ~35°, or anywhere if nil; with
-- `aim` (degrees off `heading`, one per unit) unit i faces exactly heading + aim[i] —
-- for sector radars. Returns how many could not be placed.
local function placeUnits(units, occupied, view, centre, radius, fracs, n, unitType, spacing, heading, rejects, aim)
    local missing = 0
    for i = 1, n do
        local placed
        for _, step in ipairs({ { 1, Placement.isClear }, { 0.5, Placement.isClear },
                                { 1, Placement.isClearRoad }, { 0.5, Placement.isClearRoad } }) do
            local sp2 = (spacing * step[1]) ^ 2
            local p, rj = Placement.findClear(view, function() return annulusPoint(centre, radius, fracs) end,
                TRIES_UNIT, function(q)
                    for _, o in ipairs(occupied) do
                        local dx, dz = q.x - o.x, q.z - o.z
                        if dx * dx + dz * dz < sp2 then return false, "unit_spacing" end
                    end
                    return true
                end, step[2])
            for k, v in pairs(rj) do rejects[k] = (rejects[k] or 0) + v end
            if p then placed = p; break end
        end
        if placed then
            local h
            if heading and aim and aim[i] then
                h = heading + math.rad(aim[i])
            elseif heading then
                h = heading + (math.random() - 0.5) * 1.2
            else
                h = math.random() * 2 * math.pi
            end
            local u = { type = unitType, x = round(placed.x), z = round(placed.z),
                        heading_deg = round(math.deg(h)) % 360 }
            units[#units + 1] = u
            occupied[#occupied + 1] = u
        else
            missing = missing + 1
        end
    end
    return missing
end

-- Lays out one site of `system` in candidate zone c (from the role pass) and adds it to
-- the plan. ctx = { out, sum, ids, world, side }. Returns the site, or nil if its radar
-- or command post found no room.
local function buildSite(ctx, c, role, system, layer)
    local out, sum, side = ctx.out, ctx.sum, ctx.side
    local zone   = c.zone
    local radius = Placement.zoneRadius(zone)
    local recipe = SAM_SITE_RECIPE[system]
    local code   = AIRBASE_CODE[zone.base] or zone.base:gsub("%W", ""):upper():sub(1, 4)
    local key    = code .. "|" .. systemSlug(system)
    ctx.ids[key] = (ctx.ids[key] or 0) + 1
    local id = string.format("SAM_%s_%s_%d", code, systemSlug(system), ctx.ids[key])

    -- the zone's nearest airfield still keeps its runways and parking clear
    local ab   = ctx.world.airbases[zone.base]
    local view = { runways = ab and ab.runways, parking = ab and ab.parking }
    local r    = math.min(radius, recipe.footprint_m)

    local units, occupied, broken = {}, {}, false
    for _, placeName in ipairs({ "centre", "launchers", "edge" }) do
        for _, part in ipairs(recipe.parts) do
            if part[4] == placeName then
                local n = math.random(part[2], part[3])
                local heading = placeName ~= "edge" and c.threat or nil
                local missing = placeUnits(units, occupied, view, zone.pos, r,
                    SAM_SITE_PLACE[placeName], n, part[1], recipe.unit_spacing, heading, sum.rejects, part.aim)
                if missing > 0 then
                    Log.warn(string.format("  %s: %d x %s could not be placed in %s", id, missing, part[1], zone.name))
                    if placeName == "centre" and part[2] > 0 then broken = true end
                end
            end
        end
    end
    if broken then
        Log.warn(string.format("  %s dropped: a radar or command post found no room in %s", id, zone.name))
        return nil
    end

    local pos = Util.withLatLon({ x = round(zone.pos.x), z = round(zone.pos.z) })
    local engage, detect = siteRanges(recipe)
    local site = { id = id, side = side, system = system, layer = layer, role = role,
                   zone = zone.name, defends = c.defends, pos = pos,
                   engage_m = engage, detect_m = detect, group_ids = { id } }
    out.groups[#out.groups + 1] = { id = id, side = side, skill = SAM_SITE_SKILL,
        purpose = "air_defense", site = id, pos = pos, units = units }

    local escortN = 0
    if recipe.escort_role then
        local eUnits = {}
        local eType  = Util.weightedPick(COALITION_ROSTER[side][recipe.escort_role])
        placeUnits(eUnits, occupied, view, zone.pos, r, SAM_SITE_PLACE.edge,
            1, eType, recipe.unit_spacing, c.threat, sum.rejects)
        if #eUnits > 0 then
            local eid = id .. "_escort"
            out.groups[#out.groups + 1] = { id = eid, side = side, skill = SAM_SITE_SKILL,
                purpose = "air_defense", site = id, pos = pos, units = eUnits }
            site.group_ids[#site.group_ids + 1] = eid
            escortN = #eUnits
        end
    end

    out.sites[#out.sites + 1] = site
    out.zones_used[zone.name] = id
    local here = layersInArea(ctx, c.area)
    here[layer] = (here[layer] or 0) + 1
    here.all    = (here.all or 0) + 1
    sum.sites = sum.sites + 1
    sum.by_layer[layer] = (sum.by_layer[layer] or 0) + 1
    Log.info(string.format("  %-22s %-4s %-10s %-13s %-10s %-24s %2d units%s  engage %3.0f km  (%s)",
        id, side:upper(), system, layer, role, c.defends or "-", #units,
        escortN > 0 and (" + escort") or "", engage / 1000, zone.name))
    return site
end

-- SAM_SITE_MIN_PER_LAYER for one side: before the random pass, place the minimum of each
-- layer in the zones most worth it — role order (SAM_SITE_MIN_ROLE_ORDER[layer], else
-- SAM_ZONE_ROLE_ORDER: asset_ring first), then a cluster this
-- side always holds (the Kola core for Red, not a captured border base), then an area
-- (zoneArea) without a site of this layer yet; ties are broken at random, so the sites
-- move between rolls. Only zones the layer fits, SAM_SITE_MIN_SPACING_KM clear of other
-- sites and under SAM_SITE_MAX_PER_AREA are candidates. Layers go largest first, so long range gets the big zones
-- before early warning takes any. Used zones leave byRole, so the random pass doesn't
-- see them.
local function placeMinimumSites(ctx, byRole)
    local mins = SAM_SITE_MIN_PER_LAYER and SAM_SITE_MIN_PER_LAYER[ctx.side] or {}
    for _, layer in ipairs(LAYERS) do
        local want = mins[layer] or 0
        local areaCap = SAM_SITE_MAX_PER_AREA[layer]
        while (ctx.sum.by_layer[layer] or 0) < want do
            local best, bestRole, bestIdx, bestScore
            local roleOrder = SAM_SITE_MIN_ROLE_ORDER and SAM_SITE_MIN_ROLE_ORDER[layer] or SAM_ZONE_ROLE_ORDER
            for roleIdx, role in ipairs(roleOrder) do
                for i, c in ipairs(byRole[role] or {}) do
                    local radius = Placement.zoneRadius(c.zone)
                    local inArea = layersInArea(ctx, c.area)[layer] or 0
                    if #systemsThatFit(ctx.side, layer, radius) > 0 and not siteTooClose(ctx, c.zone)
                            and not (areaCap and inArea >= areaCap) then
                        -- lower is better: role, then home cluster, then a new area, then chance
                        local score = roleIdx * 1e7 + (c.home and 0 or 1e6)
                                    + (inArea > 0 and 1e5 or 0) + math.random()
                        if not bestScore or score < bestScore then
                            best, bestRole, bestIdx, bestScore = c, role, i, score
                        end
                    end
                end
            end
            if not best then
                Log.warn(string.format("  %s: only %d of %d %s sites — no more zones that fit, spaced and under the area cap",
                    ctx.side:upper(), ctx.sum.by_layer[layer] or 0, want, layer))
                break
            end
            table.remove(byRole[bestRole], bestIdx)
            local radius = Placement.zoneRadius(best.zone)
            local system = Util.weightedPick(systemsThatFit(ctx.side, layer, radius))
            buildSite(ctx, best, bestRole, system, layer)
        end
    end
end

-- ── stage ───────────────────────────────────────────────────────

function PlanSamSites.run(plan)
    Log.info("--- Stage 3a: SAM sites ---")
    local out = { sites = {}, groups = {}, zones_used = {}, summary = {} }
    plan.sam_sites = out
    if #PlanSamSites.checkData() > 0 then
        out.problems = _problems
        return plan
    end

    local world, terr = plan.world, plan.territory
    local ids = {}   -- "OLEN|SA10" → last n
    local frontReach = frontBeltReach(plan)
    Log.info(string.format("  front belt: zones within %.0f km of an enemy base", frontReach / 1000))

    for _, side in ipairs(COALITIONS) do
        local sum = { zones_held = 0, sites = 0, by_layer = {}, rejects = {} }
        out.summary[side] = sum
        local ctx = { out = out, sum = sum, ids = ids, world = world, side = side, per_area = {} }

        -- this side's zones, grouped by role
        local byRole = {}
        for _, name in ipairs(world.zone_list) do
            local tz = terr.zones[name]
            if tz and tz.side == side then
                sum.zones_held = sum.zones_held + 1
                local zone = world.zones[name]
                local role, defends, threat = zoneRole(plan, zone, side, frontReach)
                local cluster = terr.clusters[tz.cluster]
                byRole[role] = byRole[role] or {}
                table.insert(byRole[role], { zone = zone, defends = defends, threat = threat,
                                             area = zoneArea(role, defends, zone),
                                             home = cluster ~= nil and cluster.fixed == side })
            end
        end
        local maxSites = math.floor(sum.zones_held * SAM_SITE_MAX_ZONE_SHARE + 0.5)

        placeMinimumSites(ctx, byRole)

        for _, role in ipairs(SAM_ZONE_ROLE_ORDER) do
            local list = byRole[role] or {}
            Util.shuffle(list)
            for _, c in ipairs(list) do
                if sum.sites >= maxSites then break end
                local density = SAM_SITE_DENSITY[role]
                local here    = layersInArea(ctx, c.area)
                local crowded = role == "rear_area" and (here.all or 0) >= SAM_REAR_SITES_PER_BASE_MAX
                local near    = siteTooClose(ctx, c.zone)
                if near then
                    Log.info(string.format("  %s: left free (within %g km of %s)", c.zone.name, SAM_SITE_MIN_SPACING_KM, near))
                elseif not crowded and math.random() <= density.chance then
                    local radius = Placement.zoneRadius(c.zone)
                    local system, layer, why = pickSystem(side, Util.weightedPick(density.layers), radius,
                                                          sum.by_layer, here)
                    if system then
                        buildSite(ctx, c, role, system, layer)
                    else
                        Log.info(string.format("  %s: left free (%.0f m radius, %s)", c.zone.name, radius, why))
                    end
                end
            end
        end

        local parts = {}
        for _, l in ipairs(LAYERS) do
            if sum.by_layer[l] then parts[#parts + 1] = l .. " " .. sum.by_layer[l] end
        end
        Log.info(string.format("  %s: %d sites in %d of %d zones held (cap %d)  [%s]", side:upper(), sum.sites,
            sum.sites, sum.zones_held, maxSites, table.concat(parts, ", ")))
    end
    return plan
end
