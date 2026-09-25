-- Stage 4 (first part): plan the convoys — ground groups that drive on roads from one of
-- a coalition's airbases to another. For now one Red supply convoy per mission, from a
-- rear or mid base to a front base, parking on the road outside the destination.
-- Reads plan.world, plan.territory, and every unit and static object planned so far (to
-- keep the convoy's start and end clear of them) + data/convoy_recipes.lua and
-- COALITION_ROSTER. Writes plan.convoys. Spawns nothing.
--
-- Asks the terrain (allowed for stages): land.getClosestPointOnRoads for the start and
-- end points, land.findPathOnRoads to prove a road route exists and to measure it. A
-- pair of bases with no road between them is skipped.
--
-- plan.convoys = {
--   convoys = { { id, kind, label, coalition, cluster, from_base, to_base, pos, skill,
--                 speed_mps, road_km, travel_minutes, waypoints = { { x, z } },
--                 value, mission_types, success, group_ids, critical_names, units } },
--   groups  = { spawn-ready, same shape as the other ground groups, plus
--               route = { speed_mps, points = { { x, z } } } },
--   summary = { red = { convoys, units }, blue = … },
-- }
-- Ids: CONVOY_<CODE>_<kind>_<n> (e.g. CONVOY_OLEN_supply_convoy_1), CODE of the base it
-- leaves from. The id is the DCS group name; units are <id>_<n>, the lead first.

PlanConvoys = {}

local COALITIONS = { "red", "blue" }
local COLUMNS    = { head = true, ends = true, body = true, tail = true }

local ROUTE_TRIES          = 8      -- base pairs tried per convoy before giving up
local ROAD_POINT_KM        = { 2.5, 3.5, 5 }   -- how far out of an airbase a convoy starts / parks
local ROAD_POINT_ANGLES    = { 0, -30, 30, -60, 60, -90, 90 }   -- degrees off the other base's bearing
local ROAD_POINT_MAX_M     = 8000   -- a snapped road point farther than this from the base is refused
local AIRFIELD_KEEP_OUT_M  = 1000   -- start and end stay this far outside every runway's box
local OCCUPIED_KEEP_M      = 60     -- and this far from anything already planned
local PATH_END_MATCH_M     = 1000   -- a road path must start and end this close to the asked points
local WAYPOINT_STEP_M      = 20000  -- a waypoint along the road path this often

local function round(v) return math.floor(v + 0.5) end

local function codeFor(base)
    return AIRBASE_CODE[base] or base:gsub("%W", ""):upper():sub(1, 4)
end

-- ── data checks ─────────────────────────────────────────────────

function PlanConvoys.validate()
    local problems = {}
    local function bad(msg) problems[#problems + 1] = msg end

    for kind, r in pairs(CONVOY_RECIPE) do
        local where = "recipe '" .. kind .. "'"
        if type(r.label) ~= "string" then bad(where .. " needs a label") end
        if type(r.parts) ~= "table" or #r.parts == 0 then bad(where .. " needs parts") end
        local critical = false
        for i, p in ipairs(r.parts or {}) do
            if type(p.role) ~= "string" then bad(string.format("%s part %d needs a role", where, i)) end
            if type(p.min) ~= "number" or type(p.max) ~= "number" or p.min < 0 or p.min > p.max then
                bad(string.format("%s part %d needs 0 <= min <= max", where, i))
            end
            if not COLUMNS[p.column] then
                bad(string.format("%s part %d: column '%s' is not head / ends / body / tail", where, i, tostring(p.column)))
            end
            if p.critical then critical = true end
        end
        if not critical then bad(where .. " needs a critical part") end
        for _, f in ipairs({ "unit_spacing_m", "speed_mps", "road_km_max", "value" }) do
            if type(r[f]) ~= "number" or r[f] <= 0 then bad(string.format("%s needs a positive %s", where, f)) end
        end
        if type(r.route_km) ~= "table" or #r.route_km ~= 2 or r.route_km[1] > r.route_km[2] then
            bad(where .. " needs route_km = { min, max }")
        end
        if type(r.skills) ~= "table" or #r.skills == 0 then bad(where .. " needs skills") end
        if type(r.success) ~= "table" or type(r.success.critical_fraction) ~= "number" then
            bad(where .. " needs success = { critical_fraction }")
        end
        if type(r.mission_types) ~= "table" or #r.mission_types == 0 then bad(where .. " needs mission_types") end
    end

    for _, c in ipairs(COALITIONS) do
        for kind, n in pairs(CONVOYS_PER_COALITION[c] or {}) do
            local r = CONVOY_RECIPE[kind]
            if not r then
                bad(string.format("CONVOYS_PER_COALITION.%s: '%s' has no recipe", c, kind))
            else
                if type(n) ~= "number" or n < 0 then bad(string.format("CONVOYS_PER_COALITION.%s.%s needs a count", c, kind)) end
                for _, p in ipairs(r.parts or {}) do
                    local list = COALITION_ROSTER[c] and COALITION_ROSTER[c][p.role]
                    if not list or #list == 0 then
                        bad(string.format("recipe '%s' needs role '%s' but roster %s has none", kind, tostring(p.role), c))
                    else
                        for _, e in ipairs(list) do
                            if not UNIT_POOL.ground[e[1]] then
                                bad(string.format("roster %s.%s: '%s' is not in UNIT_POOL.ground", c, p.role, tostring(e[1])))
                            end
                        end
                    end
                end
            end
        end
    end
    return problems
end

local _problems
function PlanConvoys.checkData()
    if not _problems then
        _problems = PlanConvoys.validate()
        for _, p in ipairs(_problems) do Log.error("convoy data: " .. p) end
        if #_problems == 0 then Log.info("convoy data: OK") end
    end
    return _problems
end

-- ── what's already on the map ───────────────────────────────────

-- Every unit and static object planned before this stage, as { x, z } points.
local function occupiedPoints(plan)
    local pts = {}
    local function addGroups(groups)
        for _, g in ipairs(groups or {}) do
            for _, u in ipairs(g.units) do pts[#pts + 1] = { x = u.x, z = u.z } end
        end
    end
    addGroups(plan.base_defenses and plan.base_defenses.groups)
    addGroups(plan.sam_sites and plan.sam_sites.groups)
    addGroups(plan.fixed_ground_targets and plan.fixed_ground_targets.groups)
    for _, o in ipairs(plan.fixed_ground_targets and plan.fixed_ground_targets.static_objects or {}) do
        pts[#pts + 1] = { x = o.x, z = o.z }
    end
    return pts
end

local function nearOccupied(occupied, p)
    local keep2 = OCCUPIED_KEEP_M * OCCUPIED_KEEP_M
    for _, q in ipairs(occupied) do
        local dx, dz = p.x - q.x, p.z - q.z
        if dx * dx + dz * dz < keep2 then return true end
    end
    return false
end

-- ── route ───────────────────────────────────────────────────────

-- A road point a few km outside `base`, roughly toward `toward`: off the airfield, clear
-- of runways, parking, zones and anything planned. nil if none.
local function roadPointOutside(ctx, base, toward)
    local world = ctx.plan.world
    local ab = world.airbases[base]
    local view = { runways = ab.runways, parking = ab.parking, zones = {} }
    for _, name in ipairs(world.zone_list or {}) do
        local z = world.zones[name]
        if Util.dist(z.pos, ab.pos) <= ROAD_POINT_MAX_M + 2000 then view.zones[#view.zones + 1] = z end
    end
    local brg = math.atan2(toward.z - ab.pos.z, toward.x - ab.pos.x)
    for _, km in ipairs(ROAD_POINT_KM) do
        for _, off in ipairs(ROAD_POINT_ANGLES) do
            local a = brg + math.rad(off)
            local q = Placement.snapToRoad({ x = ab.pos.x + km * 1000 * math.cos(a), z = ab.pos.z + km * 1000 * math.sin(a) })
            if q and Util.dist(q, ab.pos) <= ROAD_POINT_MAX_M
                and not Placement.onAirfieldGround(view, q, AIRFIELD_KEEP_OUT_M)
                and Placement.isClearRoad(view, q)
                and not nearOccupied(ctx.occupied, q) then
                return q
            end
        end
    end
    return nil
end

-- The road path from a to b as { points = { { x, z } }, length_m }, or nil, why.
local function roadPath(a, b)
    local raw = land.findPathOnRoads("roads", a.x, a.z, b.x, b.z)
    if type(raw) ~= "table" or #raw < 2 then return nil, "no road path" end
    local pts = {}
    for _, p in ipairs(raw) do pts[#pts + 1] = { x = p.x, z = p.y } end
    if Util.dist(pts[1], a) > PATH_END_MATCH_M or Util.dist(pts[#pts], b) > PATH_END_MATCH_M then
        return nil, "road path doesn't connect"
    end
    local len = 0
    for i = 2, #pts do len = len + Util.dist(pts[i - 1], pts[i]) end
    return { points = pts, length_m = len }
end

-- Point and heading (radians, atan2(dz, dx)) at distance d along a path.
local function alongPath(path, d)
    local pts = path.points
    for i = 2, #pts do
        local a, b = pts[i - 1], pts[i]
        local seg = Util.dist(a, b)
        if seg > 0 then
            local h = math.atan2(b.z - a.z, b.x - a.x)
            if d <= seg or i == #pts then
                local t = math.min(d / seg, 1)
                return { x = a.x + t * (b.x - a.x), z = a.z + t * (b.z - a.z) }, h
            end
            d = d - seg
        end
    end
    return { x = pts[#pts].x, z = pts[#pts].z }, 0
end

-- Ordered base pairs this coalition could run the convoy between, best first: a rear or
-- mid base to a front base, then any base to one closer to the enemy, shuffled within
-- each tier so the route changes between rolls.
local function candidatePairs(ctx, recipe)
    local t, world = ctx.plan.territory, ctx.plan.world
    local held = {}
    for name, b in pairs(t.bases) do
        if b.side == ctx.coalition then held[#held + 1] = name end
    end
    table.sort(held)
    local tiers = { {}, {} }
    for _, from in ipairs(held) do
        for _, to in ipairs(held) do
            if from ~= to then
                local km = Util.dist(world.airbases[from].pos, world.airbases[to].pos) / 1000
                if km >= recipe.route_km[1] and km <= recipe.route_km[2] then
                    local fb, tb = t.bases[from], t.bases[to]
                    local fe = t.front.nearest_enemy[from]
                    local te = t.front.nearest_enemy[to]
                    if tb.echelon == "front" and fb.echelon ~= "front" then
                        table.insert(tiers[1], { from = from, to = to })
                    elseif fe and te and te.km < fe.km then
                        table.insert(tiers[2], { from = from, to = to })
                    end
                end
            end
        end
    end
    local out = {}
    for _, tier in ipairs(tiers) do
        for _, p in ipairs(Util.shuffle(tier)) do out[#out + 1] = p end
    end
    return out
end

-- Tries candidate pairs until one has road points at both ends and a road path between
-- them. Returns { from, to, start, finish, path } or nil.
local function findRoute(ctx, recipe, label)
    local tried = 0
    for _, pair in ipairs(candidatePairs(ctx, recipe)) do
        if tried >= ROUTE_TRIES then break end
        tried = tried + 1
        local ab = ctx.plan.world.airbases
        local start  = roadPointOutside(ctx, pair.from, ab[pair.to].pos)
        local finish = start and roadPointOutside(ctx, pair.to, ab[pair.from].pos)
        local path, why
        if not start then
            why = "no clear road outside " .. pair.from
        elseif not finish then
            why = "no clear road outside " .. pair.to
        else
            path, why = roadPath(start, finish)
            if path and path.length_m > recipe.road_km_max * 1000 then
                why = string.format("road route %.0f km, over %d", path.length_m / 1000, recipe.road_km_max)
                path = nil
            end
        end
        if path then
            return { from = pair.from, to = pair.to, start = start, finish = finish, path = path }
        end
        Log.info(string.format("  %s %s → %s: %s", label, pair.from, pair.to, why))
    end
    return nil
end

-- ── the column ──────────────────────────────────────────────────

-- The convoy's vehicles in driving order, lead first: { { type, critical } }.
local function columnOrder(ctx, recipe)
    local head, body, tail, rear = {}, {}, {}, {}
    local roster = COALITION_ROSTER[ctx.coalition]
    for _, p in ipairs(recipe.parts) do
        for i = 1, math.random(p.min, p.max) do
            local v = { type = Util.weightedPick(roster[p.role]), critical = p.critical == true }
            if p.column == "head" then head[#head + 1] = v
            elseif p.column == "tail" then tail[#tail + 1] = v
            elseif p.column == "ends" then
                if i % 2 == 1 then head[#head + 1] = v else rear[#rear + 1] = v end
            else body[#body + 1] = v end
        end
    end
    local out = {}
    for _, list in ipairs({ head, Util.shuffle(body), tail, rear }) do
        for _, v in ipairs(list) do out[#out + 1] = v end
    end
    return out
end

local function buildConvoy(ctx, kind, recipe, route)
    local out, sum, coalition = ctx.out, ctx.sum, ctx.coalition
    local code = codeFor(route.from)
    local key = code .. "|" .. kind
    ctx.ids[key] = (ctx.ids[key] or 0) + 1
    local id = string.format("CONVOY_%s_%s_%d", code, kind, ctx.ids[key])

    -- vehicles stand on the first stretch of the road path, lead farthest along
    local vehicles = columnOrder(ctx, recipe)
    local spacing = recipe.unit_spacing_m
    local leadAt = math.min((#vehicles - 1) * spacing, route.path.length_m)
    local units, critical = {}, {}
    for i, v in ipairs(vehicles) do
        local p, h = alongPath(route.path, math.max(leadAt - (i - 1) * spacing, 0))
        units[i] = { type = v.type, x = round(p.x), z = round(p.z), heading_deg = round(math.deg(h)) % 360 }
        if v.critical then critical[#critical + 1] = id .. "_" .. i end
    end

    -- waypoints: the lead's spot, every WAYPOINT_STEP_M along the road, the parking spot
    local waypoints = { { x = units[1].x, z = units[1].z } }
    local d = leadAt + WAYPOINT_STEP_M
    while d < route.path.length_m - WAYPOINT_STEP_M / 2 do
        local p = alongPath(route.path, d)
        waypoints[#waypoints + 1] = { x = round(p.x), z = round(p.z) }
        d = d + WAYPOINT_STEP_M
    end
    waypoints[#waypoints + 1] = { x = round(route.finish.x), z = round(route.finish.z) }

    local pos = Util.withLatLon({ x = units[1].x, z = units[1].z })
    local skill = Util.pick(recipe.skills)
    local roadKm = route.path.length_m / 1000
    out.groups[#out.groups + 1] = { id = id, side = coalition, skill = skill, purpose = "convoy", site = id,
        pos = pos, units = units, route = { speed_mps = recipe.speed_mps, points = waypoints } }
    local convoy = {
        id = id, kind = kind, label = recipe.label, coalition = coalition,
        cluster = ctx.plan.territory.bases[route.from].cluster,
        from_base = route.from, to_base = route.to, pos = pos, skill = skill,
        speed_mps = recipe.speed_mps, road_km = round(roadKm),
        travel_minutes = round(route.path.length_m / recipe.speed_mps / 60),
        waypoints = waypoints, value = recipe.value, mission_types = recipe.mission_types,
        success = recipe.success, group_ids = { id }, critical_names = critical, units = #units,
    }
    out.convoys[#out.convoys + 1] = convoy
    sum.convoys = sum.convoys + 1
    sum.units = sum.units + #units
    Log.info(string.format("  %-32s %-4s %s → %s  %d vehicles (%d critical), %d km by road (%.0f km direct), ~%d min, %d waypoints",
        id, coalition:upper(), route.from, route.to, #units, #critical, convoy.road_km,
        Util.dist(route.start, route.finish) / 1000, convoy.travel_minutes, #waypoints))
    return convoy
end

-- ── stage ───────────────────────────────────────────────────────

function PlanConvoys.run(plan)
    Log.info("--- Stage 4: convoys ---")
    local out = { convoys = {}, groups = {}, summary = {} }
    plan.convoys = out
    if #PlanConvoys.checkData() > 0 then
        out.problems = _problems
        return plan
    end

    local ids = {}
    local occupied = occupiedPoints(plan)
    for _, coalition in ipairs(COALITIONS) do
        local sum = { convoys = 0, units = 0 }
        out.summary[coalition] = sum
        local ctx = { plan = plan, out = out, sum = sum, ids = ids, coalition = coalition, occupied = occupied }
        local wanted = CONVOYS_PER_COALITION[coalition] or {}
        local kinds = {}
        for kind in pairs(wanted) do kinds[#kinds + 1] = kind end
        table.sort(kinds)
        for _, kind in ipairs(kinds) do
            local recipe = CONVOY_RECIPE[kind]
            for _ = 1, wanted[kind] do
                local route = findRoute(ctx, recipe, recipe.label)
                if route then
                    buildConvoy(ctx, kind, recipe, route)
                else
                    Log.warn(string.format("  %s %s: no road route between two of its airbases — not planned",
                        coalition:upper(), recipe.label))
                end
            end
        end
        if sum.convoys > 0 then
            Log.info(string.format("  %s: %d convoys, %d vehicles", coalition:upper(), sum.convoys, sum.units))
        end
    end
    return plan
end
