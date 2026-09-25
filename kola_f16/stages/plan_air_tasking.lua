-- Stages 5–6: the air tasking orders — each coalition's ground attack missions over the
-- mission window: strike, airfield strike and destruction of air defenses, one flight per
-- mission, each with the suppression flights its route needs (a package). Each coalition
-- is planned from the target catalog and its own bases only, never from the other
-- coalition's air plan (plan doc §1.10).
-- Reads plan.world, plan.territory, plan.target_catalog, the planned units and static
-- objects (for the positions of each target's critical objects) and the enemy SAM sites
-- and base defenses (the threats routes go around) + data/air_tasking.lua,
-- data/aircraft_profiles.lua, data/aircraft_loadouts.lua and COALITION_AIRCRAFT. Writes
-- plan.air_tasking_orders. Spawns nothing; the scheduler consumer spawns each flight at
-- its start time.
--
-- Per mission: a mission type (weighted) → an aircraft type (roster) → an enemy target
-- of that type within the aircraft's reach from a base that can launch it (weighted by
-- value; no target is hit twice) → the launch base (one of the three nearest that fit)
-- → the route → its suppression flights, if the route crosses threat rings → start times
-- that keep the coalition under max_airborne_aircraft → parking spots free at those times
-- → the attack tasks. A mission whose suppression can't be planned isn't flown; another
-- target is tried.
--
-- Routes (data/air_tasking.lua AIR_ROUTING, lib/threat_routing.lua): flights cruise at
-- least 7,500 m, above guns, shoulder-launched missiles and short-range SAMs, and route
-- around the enemy threats that reach higher (medium- and long-range SAM rings, Pantsir /
-- Tor-M2 at enemy bases) when the way around is at most max_detour × direct and within
-- reach. A route that still crosses a ring marks the mission needs_suppression, listing
-- the threats in suppression_threats in the order the route meets them. Cruise altitude
-- holds until a descent point before the ingress; from the ingress over the target the
-- flight is at its attack altitude for that mission type.
--
-- Packages (AIR_PACKAGE): the threats are shared out in route order between suppression
-- flights. A threat is one or more DCS groups: a SAM site and its point-defense escort
-- (engaged together, so the escort can't shoot the missiles down unopposed), or a
-- base-defense group. Each flight takes whole threats, as many groups as its
-- anti-radiation missiles allow, at most max_groups_per_flight. A suppression flight
-- flies the package's route (joining it from its own base if that differs), at its own
-- cruise and suppression altitudes, with EngageGroup on its threats from the waypoint
-- before the first of their rings. It is over the target suppression_lead_s before the
-- mission it escorts, so at every ring on the way it is that much ahead too.
--
-- plan.air_tasking_orders = {
--   red  = { missions = { mission }, packages = { package },
--            summary = { missions, suppression_flights, flights, by_type, not_planned,
--                        failures = { reason = n } } },
--   blue = … ,
-- }
-- package = { id, mission (the escorted mission's id), suppression_flights = { ids }, tot_s }
-- mission = { id, number, coalition, package, mission_type, group_task, target,
--   target_label, target_kind, target_pos, aircraft_type, count, skill, launch_base,
--   landing_base, parking = { { terminal_index, x, z } } (one per aircraft, lead first),
--   start_s, takeoff_s, tot_s, end_s, distance_km, route_km,
--   route = { { kind, x, z, alt_m, speed_mps, carries_attack_tasks } },
--   attack = { kind, points = { { x, z } } | groups = { DCS group names }, weapon_type,
--              expend },
--   return_when_out_of (weapon mask or nil), loadout = { … }, keeps_gun, success,
--   critical_names,
--   needs_suppression, suppression_threats = { threat ids the route crosses },
--   suppressed_by = { suppression flight ids }        (escorted missions)
--   escorts, suppresses = { threat ids it takes } } (suppression flights; attack.groups
--   holds their groups, escorts included)
--   route kinds: takeoff, departure, transit, descent, ingress, target, egress, landing;
--   the attack tasks go on the waypoint with carries_attack_tasks
--   times are mission time in seconds (timer.getTime())
-- Ids: MSN<number>, the DCS group name; Blue numbers from 2001, Red from 5001 (plan doc
-- §11.7). Units are <id>_<n>. A package is PKG<number of the mission it escorts>.

PlanAirTasking = {}

local COALITIONS     = { "red", "blue" }
local FIRST_NUMBER   = { blue = 2001, red = 5001 }
local ATTACKS        = { bomb_critical_objects = true, attack_group = true, engage_group = true, engage_in_zone = true }
local BASE_CLASSES   = { hub = true, fighter = true, bomber = true, dispersal = true, strip = true, heli = true }
local SUPPRESSION    = "suppression_of_air_defenses"
local MISSION_TRIES  = 8     -- aircraft/target picks tried per mission
local START_TRIES    = 60    -- start times tried per package
local AIRCRAFT_TRIES = 4     -- aircraft picks tried per suppression flight
local NEAREST_BASES  = 3     -- the launch base is one of this many nearest that fit
local DEPARTURE_KM   = 20    -- the climb-out point, this far from the base toward the ingress
local SAME_POINT_M   = 30    -- attack points closer than this are one point
local REACH_FACTOR   = 1.2   -- a leg may be this much longer than the combat radius

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
        if m.return_when_out_of and not AIR_WEAPON_TYPE[m.return_when_out_of] then
            bad(string.format("mission type '%s': return_when_out_of '%s' is unknown", mt, tostring(m.return_when_out_of)))
        end
        if type(m.group_task) ~= "string" then bad(string.format("mission type '%s' needs a group_task", mt)) end
        if type(m.ingress_km) ~= "number" or type(m.egress_km) ~= "number" then
            bad(string.format("mission type '%s' needs ingress_km and egress_km", mt))
        end
        if m.attack == "bomb_critical_objects" and type(m.max_attack_points) ~= "number" then
            bad(string.format("mission type '%s' needs max_attack_points", mt))
        end
    end
    local sead = AIR_MISSION_TYPE[SUPPRESSION]
    if not (sead and sead.built and sead.escort_only and sead.attack == "engage_group") then
        bad(SUPPRESSION .. " must be a built, escort_only engage_group mission type (packages need it)")
    else
        if type(sead.missiles_per_threat) ~= "number" or sead.missiles_per_threat <= 0 then
            bad(SUPPRESSION .. " needs a positive missiles_per_threat")
        end
        if type(sead.max_groups_per_flight) ~= "number" or sead.max_groups_per_flight < 1 then
            bad(SUPPRESSION .. " needs max_groups_per_flight of at least 1")
        end
    end
    local lead = AIR_PACKAGE and AIR_PACKAGE.suppression_lead_s
    if type(lead) ~= "table" or type(lead[1]) ~= "number" or type(lead[2]) ~= "number" or lead[1] > lead[2] then
        bad("AIR_PACKAGE needs suppression_lead_s = { min, max }")
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
                if p and mt == SUPPRESSION and (type(p.anti_radiation_missiles) ~= "number" or p.anti_radiation_missiles <= 0) then
                    bad(string.format("COALITION_AIRCRAFT.%s.%s: profile '%s' needs a positive anti_radiation_missiles", c, mt, t))
                end
                if type(e[2]) ~= "number" or e[2] <= 0 then bad(string.format("COALITION_AIRCRAFT.%s.%s: '%s' needs a positive weight", c, mt, t)) end
            end
        end
        if not (COALITION_AIRCRAFT[c] and COALITION_AIRCRAFT[c][SUPPRESSION]) then
            bad(string.format("COALITION_AIRCRAFT.%s has no %s roster (packages need it)", c, SUPPRESSION))
        end
        local per = AIR_TASKING_PER_COALITION[c]
        if not per then
            bad("AIR_TASKING_PER_COALITION has no " .. c)
        else
            if type(per.max_airborne_aircraft) ~= "number" or per.max_airborne_aircraft <= 0 then
                bad(string.format("AIR_TASKING_PER_COALITION.%s needs a positive max_airborne_aircraft", c))
            end
            for _, e in ipairs(per.mission_types or {}) do
                local m = AIR_MISSION_TYPE[e[1]]
                if not m then bad(string.format("AIR_TASKING_PER_COALITION.%s: '%s' is not a mission type", c, e[1])) end
                if m and m.escort_only then
                    bad(string.format("AIR_TASKING_PER_COALITION.%s: '%s' is escort_only, planned only in packages", c, e[1]))
                end
                if m and m.built and not (COALITION_AIRCRAFT[c] and COALITION_AIRCRAFT[c][e[1]]) then
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
-- spot first and the others nearest to it, plus the reservations made (for release); or nil.
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
    local spots, held = {}, {}
    for i = 1, count do
        local s = free[i]
        spots[i] = s
        busy[s[4]] = busy[s[4]] or {}
        local span = { start_s, start_s + hold }
        table.insert(busy[s[4]], span)
        held[#held + 1] = { list = busy[s[4]], span = span }
    end
    return spots, held
end

local function releaseParking(held)
    for _, h in ipairs(held) do
        for i, span in ipairs(h.list) do
            if span == h.span then table.remove(h.list, i) break end
        end
    end
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
-- is at most max_detour × direct and within reach, else straight through. The search only
-- looks at paths within that length; searches are cached per coalition, since retried
-- missions ask for the same base → target legs.
local function threatRoute(ctx, from, to, reach_m)
    local maxLength = math.min(AIR_ROUTING.max_detour * Util.dist(from, to), reach_m)
    local key = string.format("%d,%d>%d,%d<%d", round(from.x), round(from.z), round(to.x), round(to.z), round(maxLength))
    local path = ctx.routes[key]
    if not path then
        path = ThreatRouting.route(ctx.threats, from, to, maxLength)
        ctx.routes[key] = path
    end
    local len = ThreatRouting.length(path)
    if len > maxLength then
        path = { { x = from.x, z = from.z }, { x = to.x, z = to.z } }
    end
    return path
end

local function reachOf(p) return p.combat_radius_km * 1000 * REACH_FACTOR end

-- Route points from base to target and home, around what the flight can't overfly:
--   takeoff → departure → transit … → descent → ingress → target → egress → transit … → landing
-- The way home is the way out reversed (John, after the first package run: a flight
-- that went around SAMs on the way in flew straight over an SA-11 on the way back).
-- Cruise altitude until the descent point, the mission's attack altitude from the
-- ingress over the target, cruise again from the egress; the attack tasks go on the
-- ingress. Returns the route and the ids of the threat circles it still crosses.
local function buildRoute(ctx, basePos, target, missionType, mt, p)
    local attackAlt = p.attack_altitude_m[missionType]
    local cruise, speed = p.cruise_altitude_m, p.cruise_speed_mps
    local reach = reachOf(p)
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
    route[#route].carries_attack_tasks = true
    add("target", target, attackAlt)

    -- back: the way out reversed, so the flight comes home through the same gaps it went
    -- in by; the egress sits on it
    local back = {}
    for i = #out, 1, -1 do back[#back + 1] = out[i] end
    local egressAt = math.min(mt.egress_km * 1000, outLen * 0.5)
    local egress = cutAt(back, egressAt)
    add("egress", egress, cruise)
    local walked = 0
    for i = 2, #back do
        walked = walked + Util.dist(back[i - 1], back[i])
        -- (the way out starts at the base itself when there is no departure point)
        if walked > egressAt and Util.dist(back[i], basePos) > 1000 then add("transit", back[i], cruise) end
    end
    add("landing", basePos, 0)

    for _, r in ipairs(route) do r.x, r.z = round(r.x), round(r.z) end
    return route, ThreatRouting.crossed(ctx.threats, route)
end

-- A suppression flight's route: the escorted mission's route, from takeoff to landing at
-- `baseName`. From the mission's own base it is the same route; from another base it
-- joins at the outbound point nearest that base (at the ingress at the latest) by a
-- threat-routed leg, and comes home the same way: it leaves the mission's way home where
-- that passes the joining point (at the egress at the earliest) and flies the joining leg
-- back. Cruise altitude, except the suppression altitude from the ingress
-- over the target. The attack tasks go on the waypoint before the first of `threats`'
-- rings. Returns the route.
local function suppressionRoute(ctx, mission, baseName, p, threats)
    local basePos = ctx.plan.world.airbases[baseName].pos
    local cruise, speed = p.cruise_altitude_m, p.cruise_speed_mps
    local attackAlt = p.attack_altitude_m[SUPPRESSION]
    local pr = mission.route
    local ingressAt, egressAt = 2, #pr - 1
    for i, r in ipairs(pr) do
        if r.kind == "ingress" then ingressAt = i end
        if r.kind == "egress" then egressAt = i end
    end
    local join, leave = 2, #pr - 1
    if baseName ~= mission.base then
        for i = 2, ingressAt do
            if Util.dist(basePos, pr[i]) < Util.dist(basePos, pr[join]) then join = i end
        end
        -- the mission comes home the way it went out: leave where the way home passes
        -- closest to the joining point
        for i = egressAt, #pr - 1 do
            if Util.dist(pr[join], pr[i]) <= Util.dist(pr[join], pr[leave]) then leave = i end
        end
    end

    local route = { { kind = "takeoff", x = basePos.x, z = basePos.z, alt_m = 0, speed_mps = 0 } }
    local function add(kind, q)
        local alt = (kind == "ingress" or kind == "target") and attackAlt or cruise
        route[#route + 1] = { kind = kind, x = round(q.x), z = round(q.z), alt_m = alt, speed_mps = speed }
    end
    local leg = baseName ~= mission.base and threatRoute(ctx, basePos, pr[join], reachOf(p))
    if leg then
        for i = 2, #leg - 1 do add("transit", leg[i]) end
    end
    for i = join, leave do add(pr[i].kind, pr[i]) end
    if leg then
        -- back to the joining point, then the joining leg reversed
        if Util.dist(pr[leave], pr[join]) > 1000 then add("transit", pr[join]) end
        for i = #leg - 1, 2, -1 do add("transit", leg[i]) end
    end
    route[#route + 1] = { kind = "landing", x = round(basePos.x), z = round(basePos.z), alt_m = 0, speed_mps = speed }

    -- the attack tasks: on the waypoint before the first leg that enters one of its rings
    local own = { circles = {} }
    for _, id in ipairs(threats) do own.circles[#own.circles + 1] = ThreatRouting.circle(ctx.threats, id) end
    local at
    for i = 2, #route do
        if #ThreatRouting.crossed(own, { route[i - 1], route[i] }) > 0 then at = i - 1 break end
    end
    if not at then
        for i, r in ipairs(route) do if r.kind == "ingress" then at = i end end
    end
    route[at or 1].carries_attack_tasks = true
    return route
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

-- What the flight is told to hit, by attack kind.
local function attackOf(ctx, draft)
    local mt, p, t = draft.mt, draft.p, draft.target
    if mt.attack == "bomb_critical_objects" then
        local points = attackPoints(ctx, t, mt, p)
        return { kind = mt.attack, points = points,
                 weapon_type = AIR_WEAPON_TYPE[p.carpet_bombing and "bombs" or mt.weapon_type],
                 expend = (#points == 1) and "All" or "Auto" }
    elseif mt.attack == "engage_group" then
        return { kind = mt.attack, groups = draft.groups, weapon_type = AIR_WEAPON_TYPE[mt.weapon_type] }
    end
    return { kind = mt.attack, groups = t.group_ids, weapon_type = AIR_WEAPON_TYPE[mt.weapon_type], expend = "Auto" }
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

-- A flight before its times and parking are fixed: what flies, from where, the route
-- and how long the legs take.
local function draftMission(ctx, missionType)
    local mt = AIR_MISSION_TYPE[missionType]
    local aircraftType = Util.weightedPick(COALITION_AIRCRAFT[ctx.coalition][missionType])
    local p = AIRCRAFT_PROFILE[aircraftType]
    local choices = reachableTargets(ctx, missionType, aircraftType, launchBases(ctx, aircraftType))
    if #choices == 0 then return nil end
    local weighted = {}
    for _, c in ipairs(choices) do weighted[#weighted + 1] = { c, c.target.value or 1 } end
    local pick = Util.weightedPick(weighted)
    table.sort(pick.bases, function(a, b) return a.km < b.km end)
    local nearest = {}
    for i = 1, math.min(NEAREST_BASES, #pick.bases) do nearest[i] = pick.bases[i] end
    local base = Util.pick(nearest)
    -- routed from the base centre; the takeoff point moves to the lead's spot later
    local route, crossed = buildRoute(ctx, ctx.plan.world.airbases[base.name].pos, pick.target.pos, missionType, mt, p)
    local toTarget, home = legSeconds(route, p.cruise_speed_mps)
    return { mission_type = missionType, mt = mt, aircraft_type = aircraftType, p = p, target = pick.target,
             base = base.name, distance_km = base.km, count = math.random(p.flight_size[1], p.flight_size[2]),
             route = route, crossed = crossed, to_target_s = toTarget, home_s = home, lead_s = 0 }
end

-- One suppression flight for the next threats in `remaining` (taken off it on success),
-- escorting `mission`: an aircraft from the roster with a base that can reach the target,
-- the escorted mission's own base when it can launch this type, else the nearest one.
local function draftSuppressionFlight(ctx, mission, remaining)
    local mt = AIR_MISSION_TYPE[SUPPRESSION]
    local missionBasePos = ctx.plan.world.airbases[mission.base].pos
    for _ = 1, AIRCRAFT_TRIES do
        local aircraftType = Util.weightedPick(COALITION_AIRCRAFT[ctx.coalition][SUPPRESSION])
        local p = AIRCRAFT_PROFILE[aircraftType]
        local best, bestKm
        for _, b in ipairs(launchBases(ctx, aircraftType)) do
            local pos = ctx.plan.world.airbases[b].pos
            if Util.dist(pos, mission.target.pos) <= p.combat_radius_km * 1000 then
                local km = b == mission.base and -1 or Util.dist(pos, missionBasePos) / 1000
                if not bestKm or km < bestKm then best, bestKm = b, km end
            end
        end
        if best then
            local count = math.random(p.flight_size[1], p.flight_size[2])
            local take = math.min(mt.max_groups_per_flight,
                math.max(1, math.floor(count * p.anti_radiation_missiles / mt.missiles_per_threat)))
            -- whole threats (a site and its escort stay together), at least one
            local threats, groups = {}, {}
            for _, id in ipairs(remaining) do
                local g = ctx.threat_groups[id] or { id }
                if #threats > 0 and #groups + #g > take then break end
                threats[#threats + 1] = id
                for _, name in ipairs(g) do groups[#groups + 1] = name end
            end
            local route = suppressionRoute(ctx, mission, best, p, threats)
            if ThreatRouting.length(route) <= 2 * reachOf(p) then
                for _ = 1, #threats do table.remove(remaining, 1) end
                local toTarget, home = legSeconds(route, p.cruise_speed_mps)
                local lead = AIR_PACKAGE.suppression_lead_s
                return { mission_type = SUPPRESSION, mt = mt, aircraft_type = aircraftType, p = p,
                         target = mission.target, base = best,
                         distance_km = Util.dist(ctx.plan.world.airbases[best].pos, mission.target.pos) / 1000,
                         count = count, route = route, crossed = {}, threats = threats, groups = groups,
                         to_target_s = toTarget, home_s = home,
                         lead_s = round(lead[1] + math.random() * (lead[2] - lead[1])) }
            end
        end
    end
    return nil
end

-- Every suppression flight the mission's crossed threats need, or nil if one can't be had.
local function draftSuppression(ctx, mission)
    local remaining, flights = {}, {}
    for i, id in ipairs(mission.crossed) do remaining[i] = id end
    while #remaining > 0 do
        local f = draftSuppressionFlight(ctx, mission, remaining)
        if not f then return nil end
        flights[#flights + 1] = f
    end
    return flights
end

-- Aircraft of this coalition in the air, most at any moment, with `extra` flights added:
-- { { up_s, down_s, count } }; airborne from takeoff until landing_s before the end.
local function airborneAtMost(ctx, extra)
    local spans = {}
    for _, m in ipairs(ctx.out.missions) do
        spans[#spans + 1] = { m.takeoff_s, m.end_s - AIR_TASKING_TIMING.landing_s, m.count }
    end
    for _, s in ipairs(extra) do spans[#spans + 1] = s end
    local most = 0
    for _, a in ipairs(spans) do
        local up = 0
        for _, b in ipairs(spans) do
            if b[1] <= a[1] and a[1] < b[2] then up = up + b[3] end
        end
        if up > most then most = up end
    end
    return most
end

-- Start times and parking for a package (flights[1] the escorted mission, then its
-- suppression flights): every flight's time over the target is the mission's TOT minus
-- its lead. Tries package starts until one keeps the coalition under
-- max_airborne_aircraft, fits the window and finds parking for every flight; the first
-- package of the coalition starts at first_start_s. Sets start_s / takeoff_s / tot_s /
-- end_s / spots on each flight and returns true, or returns false and the reason.
local function schedulePackage(ctx, flights)
    local T = AIR_TASKING_TIMING
    local main = flights[1]
    local earliest, latest = math.huge, -math.huge
    for _, f in ipairs(flights) do
        -- relative to the escorted mission's start
        f.rel_tot = T.taxi_s + main.to_target_s - f.lead_s
        f.rel_start = f.rel_tot - f.to_target_s - T.taxi_s
        f.rel_end = f.rel_tot + T.attack_s + f.home_s + T.landing_s
        earliest = math.min(earliest, f.rel_start)
        latest = math.max(latest, f.rel_end)
    end
    local lastStart = T.window_s - (latest - earliest)
    if lastStart < T.first_start_s then return false, "too long for the window" end
    local reason = "over the airborne cap"
    for try = 1, START_TRIES do
        local first = (#ctx.out.missions == 0 and try == 1) and T.first_start_s
                      or T.first_start_s + math.random() * (lastStart - T.first_start_s)
        local zero = round(first - earliest)
        local spans = {}
        for i, f in ipairs(flights) do
            f.start_s = zero + round(f.rel_start)
            f.takeoff_s = f.start_s + T.taxi_s
            f.tot_s = zero + round(f.rel_tot)
            f.end_s = zero + round(f.rel_end)
            spans[i] = { f.takeoff_s, f.end_s - T.landing_s, f.count }
        end
        if airborneAtMost(ctx, spans) <= ctx.per.max_airborne_aircraft then
            local held, ok = {}, true
            for _, f in ipairs(flights) do
                local spots, h = reserveParking(ctx, f.base, f.aircraft_type, f.count, f.start_s)
                if not spots then ok = false break end
                f.spots = spots
                for _, x in ipairs(h) do held[#held + 1] = x end
            end
            if ok then return true end
            releaseParking(held)
            reason = "no parking"
        end
    end
    return false, reason
end

-- A drafted and scheduled flight → its plan entry, numbered.
local function commitFlight(ctx, f, packageId)
    local number = ctx.next_number
    ctx.next_number = number + 1
    local t = f.target
    local parking = {}
    for i, s in ipairs(f.spots) do parking[i] = { terminal_index = s[4], x = s[1], z = s[2] } end
    f.route[1].x, f.route[1].z = round(f.spots[1][1]), round(f.spots[1][2])
    local mission = {
        id = "MSN" .. number, number = number, coalition = ctx.coalition, package = packageId,
        mission_type = f.mission_type, group_task = f.mt.group_task,
        target = t.id, target_label = t.label, target_kind = t.kind, target_pos = t.pos,
        aircraft_type = f.aircraft_type, count = f.count, skill = Util.pick(AIR_TASKING_SKILL),
        launch_base = f.base, landing_base = f.base, parking = parking,
        start_s = f.start_s, takeoff_s = f.takeoff_s, tot_s = f.tot_s, end_s = f.end_s,
        distance_km = round(f.distance_km), route = f.route,
        route_km = round(ThreatRouting.length(f.route) / 1000),
        needs_suppression = #f.crossed > 0, suppression_threats = f.crossed,
        attack = attackOf(ctx, f),
        return_when_out_of = f.mt.return_when_out_of and AIR_WEAPON_TYPE[f.mt.return_when_out_of],
        loadout = AIRCRAFT_LOADOUT[f.aircraft_type][f.mission_type], keeps_gun = f.p.keeps_gun == true,
        success = t.success, critical_names = t.critical_names,
    }
    ctx.out.missions[#ctx.out.missions + 1] = mission
    return mission
end

local function logFlight(ctx, m, extra)
    Log.info(string.format("  %-7s %-4s %-27s %dx %-13s %-22s → %-34s %4d km (%d flown)  start %s  TOT %s  back %s%s",
        m.id, ctx.coalition:upper(), m.mission_type, m.count, m.aircraft_type, m.launch_base, m.target,
        m.distance_km, m.route_km, clock(m.start_s), clock(m.tot_s), clock(m.end_s), extra))
end

-- One mission and its package, or nil. `failures` counts why tries failed.
local function planMission(ctx, missionType, failures)
    local function fail(reason) failures[reason] = (failures[reason] or 0) + 1 end
    for _ = 1, MISSION_TRIES do
        local main = draftMission(ctx, missionType)
        if not main then
            fail("no target in reach")
        else
            local flights, escorts = { main }, {}
            if #main.crossed > 0 then escorts = draftSuppression(ctx, main) end
            if not escorts then
                fail("no suppression flight in reach")
            else
                for _, f in ipairs(escorts) do flights[#flights + 1] = f end
                local ok, why = schedulePackage(ctx, flights)
                if not ok then
                    fail(why)
                else
                    local packageId = "PKG" .. ctx.next_number
                    ctx.taken[main.target.id] = true
                    local mission = commitFlight(ctx, main, packageId)
                    local package = { id = packageId, mission = mission.id, suppression_flights = {}, tot_s = mission.tot_s }
                    local attack = mission.attack
                    logFlight(ctx, mission, string.format("  %s%s", attack.points and (#attack.points .. " attack point(s)")
                        or (#attack.groups .. " group(s)"),
                        mission.needs_suppression and ("  crosses: " .. table.concat(mission.suppression_threats, ", ")) or ""))
                    mission.suppressed_by = {}
                    for i = 2, #flights do
                        local s = commitFlight(ctx, flights[i], packageId)
                        s.escorts, s.suppresses = mission.id, flights[i].threats
                        mission.suppressed_by[#mission.suppressed_by + 1] = s.id
                        package.suppression_flights[#package.suppression_flights + 1] = s.id
                        logFlight(ctx, s, string.format("  escorts %s, %d s ahead, engages: %s", mission.id,
                            flights[i].lead_s, table.concat(s.attack.groups, ", ")))
                    end
                    ctx.out.packages[#ctx.out.packages + 1] = package
                    return mission, package
                end
            end
        end
    end
    return nil
end

-- ── what a coalition's flights route around ─────────────────────

-- The enemy threats this coalition's flights can't overfly, as circles: SAM sites of the
-- layers in AIR_ROUTING.threat_layers (engagement ring + margin) and enemy base-defense
-- groups of AIR_ROUTING.base_defense_roles (their longest reach + margin). Also returns,
-- per circle id, the DCS groups a suppression flight engages for it: a SAM site's own
-- group first, then its point-defense escort; a base-defense group itself.
local function threatCircles(plan, coalition)
    local circles, groups = {}, {}
    local margin = AIR_ROUTING.threat_margin_km * 1000
    for _, s in ipairs(plan.sam_sites and plan.sam_sites.sites or {}) do
        if s.side ~= coalition and AIR_ROUTING.threat_layers[s.layer] and (s.engage_m or 0) > 0 then
            circles[#circles + 1] = { id = s.id, x = s.pos.x, z = s.pos.z, radius_m = s.engage_m + margin }
            local g = { s.id }
            for _, name in ipairs(s.group_ids or {}) do
                if name ~= s.id then g[#g + 1] = name end
            end
            groups[s.id] = g
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
                groups[g.id] = { g.id }
            end
        end
    end
    return circles, groups
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
        local res = { missions = {}, packages = {},
                      summary = { missions = 0, suppression_flights = 0, flights = 0, by_type = {},
                                  not_planned = 0, failures = {} } }
        out[coalition] = res
        local held = {}
        for name, b in pairs(plan.territory.bases) do
            if b.side == coalition then held[#held + 1] = name end
        end
        table.sort(held)
        local circles, threatGroups = threatCircles(plan, coalition)
        local ctx = { plan = plan, coalition = coalition, per = per, out = res, held = held,
                      threats = ThreatRouting.buildMap(circles, mapBounds(plan.world)), threat_groups = threatGroups,
                      positions = positions, taken = {}, parking_busy = {}, routes = {},
                      next_number = FIRST_NUMBER[coalition] }

        local types = {}
        for _, e in ipairs(per.mission_types) do
            local m = AIR_MISSION_TYPE[e[1]]
            if m.built and not m.escort_only then types[#types + 1] = e end
        end
        local wanted = math.random(per.missions[1], per.missions[2])
        for _ = 1, wanted do
            local missionType = Util.weightedPick(types)
            local failures = {}
            local m, package = planMission(ctx, missionType, failures)
            if m then
                res.summary.missions = res.summary.missions + 1
                res.summary.suppression_flights = res.summary.suppression_flights + #package.suppression_flights
                res.summary.by_type[missionType] = (res.summary.by_type[missionType] or 0) + 1
            else
                res.summary.not_planned = res.summary.not_planned + 1
                local parts = {}
                for _, k in ipairs(sortedKeys(failures)) do
                    parts[#parts + 1] = k .. " " .. failures[k]
                    res.summary.failures[k] = (res.summary.failures[k] or 0) + failures[k]
                end
                Log.warn(string.format("  %s %s: mission not planned (%s)", coalition:upper(), missionType,
                    table.concat(parts, ", ")))
            end
        end
        res.summary.flights = #res.missions
        table.sort(res.missions, function(a, b) return a.start_s < b.start_s end)
        local parts = {}
        for _, k in ipairs(sortedKeys(res.summary.by_type)) do parts[#parts + 1] = k .. " " .. res.summary.by_type[k] end
        Log.info(string.format("  %s: %d of %d missions planned, %d suppression flights, %d flights  [%s]",
            coalition:upper(), res.summary.missions, wanted, res.summary.suppression_flights, res.summary.flights,
            table.concat(parts, ", ")))
    end
    return plan
end
