-- Stages 5–6: the air tasking orders — each coalition's ground attack missions over the
-- mission window. For now: strike and airfield strike, one flight per mission, no
-- escorts or suppression packages. Each coalition is planned from the target catalog
-- and its own bases only, never from the other coalition's air plan (plan doc §1.10).
-- Reads plan.world, plan.territory, plan.target_catalog, and the planned units and
-- static objects (for the positions of each target's critical objects) +
-- data/air_tasking.lua, data/aircraft_profiles.lua, data/aircraft_loadouts.lua and
-- COALITION_AIRCRAFT. Writes plan.air_tasking_orders. Spawns nothing; the scheduler
-- consumer spawns each flight at its start time.
--
-- Per mission: a mission type (weighted) → an aircraft type (roster) → an enemy target
-- of that type within the aircraft's reach from a base that can launch it (weighted by
-- value; no target is hit twice) → the launch base (one of the three nearest that fit)
-- → the route → a start time that keeps the coalition under max_airborne → parking
-- spots free at that time → the attack tasks.
--
-- Routes (data/air_tasking.lua AIR_ROUTING, lib/threat_routing.lua): flights cruise at
-- least 7,500 m, above guns, shoulder-launched missiles and short-range SAMs, and route
-- around the enemy threats that reach higher (medium- and long-range SAM rings, Pantsir /
-- Tor-M2 at enemy bases) when the way around is at most max_detour × direct and within
-- reach. A route that still crosses a ring marks the mission needs_suppression, listing
-- the threats in suppression_threats (for the SEAD/DEAD escorts to come). Cruise
-- altitude holds until a descent point before the ingress; from the ingress over the
-- target the flight is at its attack altitude for that mission type.
--
-- plan.air_tasking_orders = {
--   red  = { missions = { mission }, summary = { missions, by_type, not_planned } },
--   blue = … ,
-- }
-- mission = { id, number, coalition, mission_type, group_task, target, target_label,
--   target_kind, aircraft_type, count, skill, launch_base, landing_base,
--   parking = { { terminal_index, x, z } } (one per aircraft, lead first), start_s, takeoff_s, tot_s, end_s, distance_km, route = { { kind, x, z,
--   alt_m, speed_mps } }, attack = { kind, points = { { x, z } }, weapon_type, expend },
--   loadout = { … }, keeps_gun, success, critical_names }
--   route_km, needs_suppression, suppression_threats = { threat ids the route crosses }
--   route kinds: takeoff, departure, transit, descent, ingress, target, egress, landing
--   times are mission time in seconds (timer.getTime())
-- Ids: MSN<number>, the DCS group name; Blue numbers from 2001, Red from 5001 (plan doc
-- §11.7). Units are <id>_<n>.

PlanAirTasking = {}

local COALITIONS     = { "red", "blue" }
local FIRST_NUMBER   = { blue = 2001, red = 5001 }
local ATTACKS        = { bomb_critical_objects = true, attack_group = true, engage_group = true, engage_in_zone = true }
local BASE_CLASSES   = { hub = true, fighter = true, bomber = true, dispersal = true, strip = true, heli = true }
local MISSION_TRIES  = 8     -- aircraft/target picks tried per mission
local START_TRIES    = 60    -- start times tried per mission
local NEAREST_BASES  = 3     -- the launch base is one of this many nearest that fit
local DEPARTURE_KM   = 20    -- the climb-out point, this far from the base toward the ingress
local SAME_POINT_M   = 30    -- attack points closer than this are one point

local function round(v) return math.floor(v + 0.5) end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function clock(s)
    return string.format("%02d:%02d", math.floor(s / 3600), math.floor(s % 3600 / 60))
end

-- ── data checks ─────────────────────────────────────────────────

function PlanAirTasking.validate()
    local problems = {}
    local function bad(msg) problems[#problems + 1] = msg end

    for mt, m in pairs(AIR_MISSION_TYPE) do
        if not ATTACKS[m.attack] then bad(string.format("mission type '%s': attack '%s' is unknown", mt, tostring(m.attack))) end
        if not AIR_WEAPON_TYPE[m.weapon_type] then bad(string.format("mission type '%s': weapon_type '%s' is unknown", mt, tostring(m.weapon_type))) end
        if type(m.group_task) ~= "string" then bad(string.format("mission type '%s' needs a group_task", mt)) end
        if type(m.ingress_km) ~= "number" or type(m.egress_km) ~= "number" then
            bad(string.format("mission type '%s' needs ingress_km and egress_km", mt))
        end
        if m.attack == "bomb_critical_objects" and type(m.max_attack_points) ~= "number" then
            bad(string.format("mission type '%s' needs max_attack_points", mt))
        end
    end

    for t, p in pairs(AIRCRAFT_PROFILE) do
        local where = "profile '" .. t .. "'"
        if not UNIT_POOL.plane[t] then bad(where .. ": not a plane in UNIT_POOL") end
        for _, c in ipairs(p.base_classes or {}) do
            if not BASE_CLASSES[c] then bad(string.format("%s: base class '%s' is unknown", where, tostring(c))) end
        end
        if type(p.base_classes) ~= "table" or #p.base_classes == 0 then bad(where .. " needs base_classes") end
        if type(p.parking) ~= "table" or #p.parking == 0 then bad(where .. " needs parking terminal types") end
        if type(p.flight_size) ~= "table" or #p.flight_size ~= 2 or p.flight_size[1] > p.flight_size[2] then
            bad(where .. " needs flight_size = { min, max }")
        end
        for _, f in ipairs({ "min_runway_m", "combat_radius_km", "cruise_speed_mps", "cruise_altitude_m" }) do
            if type(p[f]) ~= "number" or p[f] <= 0 then bad(string.format("%s needs a positive %s", where, f)) end
        end
        if type(p.cruise_altitude_m) == "number" and p.cruise_altitude_m < AIR_ROUTING.min_cruise_altitude_m then
            bad(string.format("%s: cruise_altitude_m below AIR_ROUTING.min_cruise_altitude_m (%d)", where,
                AIR_ROUTING.min_cruise_altitude_m))
        end
        if type(p.attack_altitude_m) ~= "table" then bad(where .. " needs attack_altitude_m = { mission type = m }") end
    end

    for _, c in ipairs(COALITIONS) do
        for mt, list in pairs(COALITION_AIRCRAFT[c] or {}) do
            if not AIR_MISSION_TYPE[mt] then bad(string.format("COALITION_AIRCRAFT.%s: '%s' is not a mission type", c, mt)) end
            for _, e in ipairs(list) do
                local t = e[1]
                if not AIRCRAFT_PROFILE[t] then bad(string.format("COALITION_AIRCRAFT.%s.%s: '%s' has no profile", c, mt, t)) end
                if not (AIRCRAFT_LOADOUT[t] and AIRCRAFT_LOADOUT[t][mt]) then
                    bad(string.format("COALITION_AIRCRAFT.%s.%s: '%s' has no %s loadout (tools/aircraft_loadouts.py)", c, mt, t, mt))
                end
                local p = AIRCRAFT_PROFILE[t]
                if p and type(p.attack_altitude_m) == "table" and type(p.attack_altitude_m[mt]) ~= "number" then
                    bad(string.format("COALITION_AIRCRAFT.%s.%s: profile '%s' has no attack_altitude_m.%s", c, mt, t, mt))
                end
                if type(e[2]) ~= "number" or e[2] <= 0 then bad(string.format("COALITION_AIRCRAFT.%s.%s: '%s' needs a positive weight", c, mt, t)) end
            end
        end
        local per = AIR_TASKING_PER_COALITION[c]
        if not per then
            bad("AIR_TASKING_PER_COALITION has no " .. c)
        else
            for _, e in ipairs(per.mission_types or {}) do
                if not AIR_MISSION_TYPE[e[1]] then bad(string.format("AIR_TASKING_PER_COALITION.%s: '%s' is not a mission type", c, e[1])) end
                if AIR_MISSION_TYPE[e[1]] and AIR_MISSION_TYPE[e[1]].built
                    and not (COALITION_AIRCRAFT[c] and COALITION_AIRCRAFT[c][e[1]]) then
                    bad(string.format("AIR_TASKING_PER_COALITION.%s: '%s' has no COALITION_AIRCRAFT roster", c, e[1]))
                end
            end
        end
    end
    return problems
end

local _problems
function PlanAirTasking.checkData()
    if not _problems then
        _problems = PlanAirTasking.validate()
        for _, p in ipairs(_problems) do Log.error("air tasking data: " .. p) end
        if #_problems == 0 then Log.info("air tasking data: OK") end
    end
    return _problems
end

-- ── what's where ────────────────────────────────────────────────

-- Every planned unit and static object by DCS name → { x, z }.
local function objectPositions(plan)
    local pos = {}
    local function addGroups(groups)
        for _, g in ipairs(groups or {}) do
            for i, u in ipairs(g.units) do pos[g.id .. "_" .. i] = { x = u.x, z = u.z } end
        end
    end
    addGroups(plan.sam_sites and plan.sam_sites.groups)
    addGroups(plan.fixed_ground_targets and plan.fixed_ground_targets.groups)
    addGroups(plan.convoys and plan.convoys.groups)
    for _, o in ipairs(plan.fixed_ground_targets and plan.fixed_ground_targets.static_objects or {}) do
        pos[o.id] = { x = o.x, z = o.z }
    end
    return pos
end

local function longestRunway(ab)
    local m = 0
    for _, r in ipairs(ab.runways or {}) do if r.length > m then m = r.length end end
    return m
end

-- The coalition's bases that can launch this aircraft type (class, runway, parking type).
local function launchBases(ctx, aircraftType)
    local p = AIRCRAFT_PROFILE[aircraftType]
    local classes, terminals = {}, {}
    for _, c in ipairs(p.base_classes) do classes[c] = true end
    for _, t in ipairs(p.parking) do terminals[t] = true end
    local out = {}
    for _, name in ipairs(ctx.held) do
        local ab = ctx.plan.world.airbases[name]
        if classes[AIRBASE_CLASS[name]] and longestRunway(ab) >= p.min_runway_m then
            local spots = 0
            for _, s in ipairs(ab.parking) do if terminals[s[3]] then spots = spots + 1 end end
            if spots >= p.flight_size[2] then out[#out + 1] = name end
        end
    end
    return out
end

-- ── parking ─────────────────────────────────────────────────────

-- Free spots of the right types at `base` for `count` aircraft, held from start_s, lead's
-- spot first and the others nearest to it; or nil.
local function reserveParking(ctx, base, aircraftType, count, start_s)
    local p = AIRCRAFT_PROFILE[aircraftType]
    local terminals = {}
    for _, t in ipairs(p.parking) do terminals[t] = true end
    local busy = ctx.parking_busy[base] or {}
    ctx.parking_busy[base] = busy
    local hold = AIR_TASKING_TIMING.parking_hold_s
    local statics = ctx.plan.fixed_ground_targets and ctx.plan.fixed_ground_targets.parking_used[base] or {}
    local free = {}
    for _, s in ipairs(ctx.plan.world.airbases[base].parking) do
        local idx = s[4]
        local taken = statics[idx] ~= nil
        for _, span in ipairs(busy[idx] or {}) do
            if start_s < span[2] and start_s + hold > span[1] then taken = true end
        end
        if terminals[s[3]] and not taken then free[#free + 1] = s end
    end
    if #free < count then return nil end
    local lead = Util.pick(free)
    table.sort(free, function(a, b)
        return (a[1] - lead[1]) ^ 2 + (a[2] - lead[2]) ^ 2 < (b[1] - lead[1]) ^ 2 + (b[2] - lead[2]) ^ 2
    end)
    local spots = {}
    for i = 1, count do
        local s = free[i]
        spots[i] = s
        busy[s[4]] = busy[s[4]] or {}
        table.insert(busy[s[4]], { start_s, start_s + hold })
    end
    return spots
end

-- ── route and timing ────────────────────────────────────────────

local function offset(from, towards, km)
    local d = Util.dist(from, towards)
    if d < 1 then return { x = from.x, z = from.z } end
    local f = km * 1000 / d
    return { x = from.x + (towards.x - from.x) * f, z = from.z + (towards.z - from.z) * f }
end

-- The point `d` metres along a polyline, and the polyline's points strictly before it.
local function cutAt(points, d)
    local before = { points[1] }
    for i = 2, #points do
        local seg = Util.dist(points[i - 1], points[i])
        if d <= seg then
            local t = seg > 0 and d / seg or 0
            local a, b = points[i - 1], points[i]
            return { x = a.x + t * (b.x - a.x), z = a.z + t * (b.z - a.z) }, before
        end
        d = d - seg
        before[#before + 1] = points[i]
    end
    return points[#points], before
end

-- The route between two points around the coalition's threat map: the way round if it
-- is at most max_detour × direct and within reach, else straight through.
local function threatRoute(ctx, from, to, reach_m)
    local path = ThreatRouting.route(ctx.threats, from, to)
    local len = ThreatRouting.length(path)
    if len > AIR_ROUTING.max_detour * Util.dist(from, to) or len > reach_m then
        path = { { x = from.x, z = from.z }, { x = to.x, z = to.z } }
    end
    return path
end

-- Route points from base to target and home, around what the flight can't overfly:
--   takeoff → departure → transit … → descent → ingress → target → egress → transit … → landing
-- Cruise altitude until the descent point, the mission's attack altitude from the
-- ingress over the target, cruise again from the egress. Returns the route and the ids
-- of the threat circles it still crosses.
local function buildRoute(ctx, basePos, target, missionType, mt, p)
    local attackAlt = p.attack_altitude_m[missionType]
    local cruise, speed = p.cruise_altitude_m, p.cruise_speed_mps
    local reach = p.combat_radius_km * 1000 * 1.2
    local route = { { kind = "takeoff", x = basePos.x, z = basePos.z, alt_m = 0, speed_mps = 0 } }
    local function add(kind, q, alt) route[#route + 1] = { kind = kind, x = q.x, z = q.z, alt_m = alt, speed_mps = speed } end

    local direct = Util.dist(basePos, target)
    local start = basePos
    if direct > (DEPARTURE_KM + 40) * 1000 then
        start = offset(basePos, target, DEPARTURE_KM)
        add("departure", start, cruise)
    end

    -- out: the ingress and the descent point sit on the path, counted back from the target
    local out = threatRoute(ctx, start, target, reach)
    local outLen = ThreatRouting.length(out)
    local ingressM = math.min(mt.ingress_km * 1000, outLen * 0.5)
    local descentM = math.max(AIR_ROUTING.min_descent_km,
        (cruise - attackAlt) / 1000 * AIR_ROUTING.descent_km_per_km) * 1000
    descentM = math.min(descentM, math.max(outLen - ingressM - 5000, 0))
    local ingress = cutAt(out, outLen - ingressM)
    local descent, transit = cutAt(out, outLen - ingressM - descentM)
    for i = 2, #transit do add("transit", transit[i], cruise) end
    if descentM > 0 then add("descent", descent, cruise) end
    add("ingress", ingress, attackAlt)
    add("target", target, attackAlt)

    -- back: the egress sits on the way home
    local back = threatRoute(ctx, target, basePos, reach)
    local backLen = ThreatRouting.length(back)
    local egress, _ = cutAt(back, math.min(mt.egress_km * 1000, backLen * 0.5))
    add("egress", egress, cruise)
    local _, home = cutAt(back, backLen)
    local egressAt = math.min(mt.egress_km * 1000, backLen * 0.5)
    local walked = 0
    for i = 2, #home do
        walked = walked + Util.dist(home[i - 1], home[i])
        if walked > egressAt then add("transit", home[i], cruise) end
    end
    add("landing", basePos, 0)

    for _, r in ipairs(route) do r.x, r.z = round(r.x), round(r.z) end
    return route, ThreatRouting.crossed(ctx.threats, route)
end

-- Seconds of flight from the takeoff point to the target, and from the target home.
local function legSeconds(route, speed)
    local toTarget, home, reached = 0, 0, false
    for i = 2, #route do
        local d = Util.dist(route[i - 1], route[i]) / speed
        if reached then home = home + d else toTarget = toTarget + d end
        if route[i].kind == "target" then reached = true end
    end
    return toTarget, home
end

-- A start time keeping this coalition's airborne flights ≤ max_airborne (the first
-- mission starts at first_start_s so something flies early), or nil.
local function findStart(ctx, flight_s)
    local T = AIR_TASKING_TIMING
    local latest = T.window_s - flight_s - T.taxi_s
    if latest < T.first_start_s then return nil end
    for try = 1, START_TRIES do
        local start = (#ctx.out.missions == 0 and try == 1) and T.first_start_s
                      or T.first_start_s + math.random() * (latest - T.first_start_s)
        local up, down = start + T.taxi_s, start + T.taxi_s + flight_s
        local overlapping = 0
        for _, m in ipairs(ctx.out.missions) do
            if up < m.end_s - T.landing_s and down > m.takeoff_s then overlapping = overlapping + 1 end
        end
        if overlapping < ctx.per.max_airborne then return round(start) end
    end
    return nil
end

-- ── one mission ─────────────────────────────────────────────────

-- The attack points for a bomb_critical_objects target: its critical objects' positions,
-- merged when closer than SAME_POINT_M, at most max; or the centre for carpet bombing.
local function attackPoints(ctx, target, mt, p)
    local pts = {}
    for _, name in ipairs(target.critical_names or {}) do
        local q = ctx.positions[name]
        if q then
            local near = false
            for _, e in ipairs(pts) do if Util.dist(e, q) < SAME_POINT_M then near = true end end
            if not near then pts[#pts + 1] = { x = round(q.x), z = round(q.z) } end
        end
    end
    if #pts == 0 then pts[1] = { x = round(target.pos.x), z = round(target.pos.z) } end
    if p.carpet_bombing then
        local cx, cz = 0, 0
        for _, q in ipairs(pts) do cx, cz = cx + q.x, cz + q.z end
        return { { x = round(cx / #pts), z = round(cz / #pts) } }
    end
    Util.shuffle(pts)
    while #pts > mt.max_attack_points do table.remove(pts) end
    return pts
end

-- Enemy targets offering this mission type, not taken yet, in reach of one of `bases`.
-- Returns { { target, bases = { { name, km } } } }.
local function reachableTargets(ctx, missionType, aircraftType, bases)
    local p = AIRCRAFT_PROFILE[aircraftType]
    local cat, world = ctx.plan.target_catalog, ctx.plan.world
    local out = {}
    for _, id in ipairs(cat.list) do
        local t = cat.targets[id]
        if t.coalition ~= ctx.coalition and not ctx.taken[id] then
            local offers = false
            for _, m in ipairs(t.mission_types) do if m == missionType then offers = true end end
            if offers then
                local inReach = {}
                for _, b in ipairs(bases) do
                    local km = Util.dist(world.airbases[b].pos, t.pos) / 1000
                    if km <= p.combat_radius_km then inReach[#inReach + 1] = { name = b, km = km } end
                end
                if #inReach > 0 then out[#out + 1] = { target = t, bases = inReach } end
            end
        end
    end
    return out
end

local function planMission(ctx, missionType)
    local mt = AIR_MISSION_TYPE[missionType]
    local roster = COALITION_AIRCRAFT[ctx.coalition][missionType]
    for _ = 1, MISSION_TRIES do
        local aircraftType = Util.weightedPick(roster)
        local p = AIRCRAFT_PROFILE[aircraftType]
        local choices = reachableTargets(ctx, missionType, aircraftType, launchBases(ctx, aircraftType))
        if #choices > 0 then
            local weighted = {}
            for _, c in ipairs(choices) do weighted[#weighted + 1] = { c, c.target.value or 1 } end
            local pick = Util.weightedPick(weighted)
            local t = pick.target
            table.sort(pick.bases, function(a, b) return a.km < b.km end)
            local nearest = {}
            for i = 1, math.min(NEAREST_BASES, #pick.bases) do nearest[i] = pick.bases[i] end
            local base = Util.pick(nearest)
            local basePos = ctx.plan.world.airbases[base.name].pos
            local count = math.random(p.flight_size[1], p.flight_size[2])

            -- routed from the base centre; the takeoff point moves to the lead's spot below
            local route, crossed = buildRoute(ctx, basePos, t.pos, missionType, mt, p)
            local toTarget, home = legSeconds(route, p.cruise_speed_mps)
            local T = AIR_TASKING_TIMING
            local flight_s = toTarget + T.attack_s + home + T.landing_s
            local start = findStart(ctx, flight_s)
            local spots = start and reserveParking(ctx, base.name, aircraftType, count, start)
            if spots then
                route[1].x, route[1].z = round(spots[1][1]), round(spots[1][2])
                local points = attackPoints(ctx, t, mt, p)
                ctx.taken[t.id] = true
                local number = ctx.next_number
                ctx.next_number = number + 1
                local parking = {}
                for i, s in ipairs(spots) do parking[i] = { terminal_index = s[4], x = s[1], z = s[2] } end
                local takeoff = start + T.taxi_s
                local tot = round(takeoff + toTarget)
                local mission = {
                    id = "MSN" .. number, number = number, coalition = ctx.coalition,
                    mission_type = missionType, group_task = mt.group_task,
                    target = t.id, target_label = t.label, target_kind = t.kind, target_pos = t.pos,
                    aircraft_type = aircraftType, count = count, skill = Util.pick(AIR_TASKING_SKILL),
                    launch_base = base.name, landing_base = base.name, parking = parking,
                    start_s = start, takeoff_s = takeoff, tot_s = tot,
                    end_s = round(tot + T.attack_s + home + T.landing_s),
                    distance_km = round(base.km), route = route,
                    route_km = round((ThreatRouting.length(route)) / 1000),
                    needs_suppression = #crossed > 0, suppression_threats = crossed,
                    attack = { kind = mt.attack, points = points,
                               weapon_type = AIR_WEAPON_TYPE[p.carpet_bombing and "bombs" or mt.weapon_type],
                               expend = (#points == 1) and "All" or "Auto" },
                    loadout = AIRCRAFT_LOADOUT[aircraftType][missionType], keeps_gun = p.keeps_gun == true,
                    success = t.success, critical_names = t.critical_names,
                }
                ctx.out.missions[#ctx.out.missions + 1] = mission
                Log.info(string.format("  %-7s %-4s %-15s %dx %-13s %-22s → %-34s %4d km (%d flown)  start %s  TOT %s  back %s  %d attack point(s)%s",
                    mission.id, ctx.coalition:upper(), missionType, count, aircraftType, base.name, t.id,
                    mission.distance_km, mission.route_km, clock(start), clock(tot), clock(mission.end_s), #points,
                    #crossed > 0 and ("  needs suppression: " .. table.concat(crossed, ", ")) or ""))
                return mission
            end
        end
    end
    return nil
end

-- ── what a coalition's flights route around ─────────────────────

-- The enemy threats this coalition's flights can't overfly, as circles: SAM sites of the
-- layers in AIR_ROUTING.threat_layers (engagement ring + margin) and enemy base-defense
-- groups of AIR_ROUTING.base_defense_roles (their longest reach + margin).
local function threatCircles(plan, coalition)
    local circles = {}
    local margin = AIR_ROUTING.threat_margin_km * 1000
    for _, s in ipairs(plan.sam_sites and plan.sam_sites.sites or {}) do
        if s.side ~= coalition and AIR_ROUTING.threat_layers[s.layer] and (s.engage_m or 0) > 0 then
            circles[#circles + 1] = { id = s.id, x = s.pos.x, z = s.pos.z, radius_m = s.engage_m + margin }
        end
    end
    local bdMargin = AIR_ROUTING.base_defense_margin_km * 1000
    for _, g in ipairs(plan.base_defenses and plan.base_defenses.groups or {}) do
        if g.side ~= coalition and AIR_ROUTING.base_defense_roles[g.role] then
            local reach = 0
            for _, u in ipairs(g.units) do
                local pool = UNIT_POOL.ground[u.type]
                if pool and (pool.threat_m or 0) > reach then reach = pool.threat_m end
            end
            if reach > 0 then
                circles[#circles + 1] = { id = g.id, x = g.pos.x, z = g.pos.z, radius_m = reach + bdMargin }
            end
        end
    end
    return circles
end

-- The map area the routing grid covers: every airbase, plus room to fly around.
local function mapBounds(world)
    local b = { min_x = math.huge, max_x = -math.huge, min_z = math.huge, max_z = -math.huge }
    for _, ab in pairs(world.airbases) do
        b.min_x, b.max_x = math.min(b.min_x, ab.pos.x), math.max(b.max_x, ab.pos.x)
        b.min_z, b.max_z = math.min(b.min_z, ab.pos.z), math.max(b.max_z, ab.pos.z)
    end
    local pad = 200000
    return { min_x = b.min_x - pad, max_x = b.max_x + pad, min_z = b.min_z - pad, max_z = b.max_z + pad }
end

-- ── stage ───────────────────────────────────────────────────────

function PlanAirTasking.run(plan)
    Log.info("--- Stages 5–6: air tasking orders ---")
    local out = {}
    plan.air_tasking_orders = out
    if #PlanAirTasking.checkData() > 0 then
        out.problems = _problems
        return plan
    end

    local positions = objectPositions(plan)
    for _, coalition in ipairs(COALITIONS) do
        local per = AIR_TASKING_PER_COALITION[coalition]
        local res = { missions = {}, summary = { missions = 0, by_type = {}, not_planned = 0 } }
        out[coalition] = res
        local held = {}
        for name, b in pairs(plan.territory.bases) do
            if b.side == coalition then held[#held + 1] = name end
        end
        table.sort(held)
        local circles = threatCircles(plan, coalition)
        local ctx = { plan = plan, coalition = coalition, per = per, out = res, held = held,
                      threats = ThreatRouting.buildMap(circles, mapBounds(plan.world)),
                      positions = positions, taken = {}, parking_busy = {},
                      next_number = FIRST_NUMBER[coalition] }

        local types = {}
        for _, e in ipairs(per.mission_types) do
            if AIR_MISSION_TYPE[e[1]].built then types[#types + 1] = e end
        end
        local wanted = math.random(per.missions[1], per.missions[2])
        for _ = 1, wanted do
            local missionType = Util.weightedPick(types)
            local m = planMission(ctx, missionType)
            if m then
                res.summary.missions = res.summary.missions + 1
                res.summary.by_type[missionType] = (res.summary.by_type[missionType] or 0) + 1
            else
                res.summary.not_planned = res.summary.not_planned + 1
                Log.warn(string.format("  %s %s: no target, base, start time or parking fits — mission not planned",
                    coalition:upper(), missionType))
            end
        end
        table.sort(res.missions, function(a, b) return a.start_s < b.start_s end)
        local parts = {}
        for _, k in ipairs(sortedKeys(res.summary.by_type)) do parts[#parts + 1] = k .. " " .. res.summary.by_type[k] end
        Log.info(string.format("  %s: %d of %d missions planned  [%s]", coalition:upper(), res.summary.missions,
            wanted, table.concat(parts, ", ")))
    end
    return plan
end
