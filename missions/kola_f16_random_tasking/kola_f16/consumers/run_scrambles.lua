-- Consumer: scrambles — each coalition's response to enemy aircraft in its defended air
-- space (plan doc §1.10, "Defensive air — design"). The plan holds only the posture
-- (plan.air_tasking_orders[coalition].alert: alert bases and their aircraft, defended air
-- zones, the radars that watch); this loop reacts to what actually flies.
--
-- Every check_interval_s, per coalition:
--   1. the radar picture: every enemy aircraft its own radars detect (early-warning
--      sites, SAM search radars, the AWACS: Controller:getDetectedTargets, radar only),
--      or with detection = "distance" every enemy aircraft at all
--   2. an enemy group inside a defended air zone, with no live scramble already sent after
--      it, draws one: the nearest alert base with launches left, off cooldown and in reach
--      launches a single ship hot off the runway, under max_airborne_aircraft
--   3. the scramble flies at the intruder's position with EngageGroup on it (plus
--      EngageTargets for whatever else it meets), then home; the scheduler logs its shots,
--      kills and losses and removes it after landing
-- Log lines (grep "radar" and "scramble"):
--   "RED radars: 24 of 26 answered, enemy aircraft groups seen: 2"   the first checks, then every 10 min
--   "RED radar: MSN2001 (F-15ESE) first seen by SAM_OLEN_SA10_1, 132 km from Olenya"
--   "RED scramble MSN5901: MiG-31 from Monchegorsk → MSN2001 (F-15ESE), in base Olenya"
-- Scramble ids are MSN<first_number + n> (Blue 2901+, Red 5901+), the DCS group name.
-- Reads the plan; writes nothing back to it. Launches, cooldowns and who was answered are
-- runtime state kept here.

RunScrambles = {}

local SIDE = { red = 1, blue = 2 }             -- coalition.side
local ENEMY = { red = "blue", blue = "red" }
local PICTURE_LOG_S = 600

local _state = {}   -- coalition → { posture, bases = { base → { remaining, ready_s } }, answered, seen, next_number }

local function inAir(unit)
    local ok, v = pcall(function() return unit:inAir() end)
    return ok and v
end

-- Aircraft of this coalition airborne now.
local function airborne(coalitionName)
    local n = 0
    for _, g in ipairs(coalition.getGroups(SIDE[coalitionName], Group.Category.AIRPLANE) or {}) do
        for _, u in ipairs(g:getUnits() or {}) do
            if inAir(u) then n = n + 1 end
        end
    end
    return n
end

local function isEnemyAircraft(obj, coalitionName)
    local ok, yes = pcall(function()
        if obj:getCategory() ~= Object.Category.UNIT then return false end
        local cat = obj:getDesc().category
        if cat ~= Unit.Category.AIRPLANE and cat ~= Unit.Category.HELICOPTER then return false end
        return obj:getCoalition() == SIDE[ENEMY[coalitionName]] and obj:inAir()
    end)
    return ok and yes
end

-- enemy group name → { pos, type, seen_by }; plus radars asked and answered.
local function radarPicture(st, coalitionName)
    local picture, asked, answered = {}, 0, 0
    local function add(obj, by)
        local ok, name = pcall(function() return obj:getGroup():getName() end)
        if ok and name and not picture[name] then
            picture[name] = { pos = obj:getPoint(), type = obj:getTypeName(), seen_by = by }
        end
    end
    if st.posture.detection == "distance" then
        for _, g in ipairs(coalition.getGroups(SIDE[ENEMY[coalitionName]], Group.Category.AIRPLANE) or {}) do
            for _, u in ipairs(g:getUnits() or {}) do
                if inAir(u) then add(u, "distance") end
            end
        end
        return picture, 0, 0
    end
    for _, radar in ipairs(st.posture.radars) do
        local g = Group.getByName(radar)
        if g and g:isExist() then
            asked = asked + 1
            local ok, list = pcall(function() return g:getController():getDetectedTargets(Controller.Detection.RADAR) end)
            if ok and type(list) == "table" then
                answered = answered + 1
                for _, t in ipairs(list) do
                    if t.object and isEnemyAircraft(t.object, coalitionName) then add(t.object, radar) end
                end
            end
        end
    end
    return picture, asked, answered
end

local function zoneOf(st, pos)
    for _, z in ipairs(st.posture.zones) do
        if (pos.x - z.x) ^ 2 + (pos.z - z.z) ^ 2 <= z.radius_m ^ 2 then return z end
    end
    return nil
end

local function nearestBaseName(pos)
    local best, bestD
    for _, ab in ipairs(world.getAirbases() or {}) do
        local p = ab:getPoint()
        local d = (p.x - pos.x) ^ 2 + (p.z - pos.z) ^ 2
        if not bestD or d < bestD then best, bestD = ab:getName(), d end
    end
    return best, bestD and math.sqrt(bestD) or 0
end

-- The alert base to answer from, and its aircraft type; or nil.
local function pickBase(st, pos, now)
    local best, bestD, bestType
    for _, b in ipairs(st.posture.bases) do
        local s = st.bases[b.base]
        if s.remaining > 0 and now >= s.ready_s then
            local ab = Airbase.getByName(b.base)
            if ab and ab:getCoalition() == SIDE[st.coalition] then
                local aircraftType = Util.weightedPick(b.aircraft)
                local d = Util.dist(b.pos, { x = pos.x, z = pos.z })
                if d <= AIRCRAFT_PROFILE[aircraftType].combat_radius_km * 1000 and (not bestD or d < bestD) then
                    best, bestD, bestType = b, d, aircraftType
                end
            end
        end
    end
    return best, bestType, bestD
end

local function scramble(st, enemyGroup, contact, zone, now)
    local b, aircraftType, d = pickBase(st, contact.pos, now)
    if not b then return false, "no alert base with a launch left in reach" end
    if airborne(st.coalition) + 1 > st.posture.max_airborne_aircraft then return false, "over the airborne cap" end
    local mt = AIR_MISSION_TYPE.interception
    local p = AIRCRAFT_PROFILE[aircraftType]
    local number = st.next_number
    st.next_number = number + 1
    local alt = p.attack_altitude_m.interception
    local m = {
        id = "MSN" .. number, number = number, coalition = st.coalition, mission_type = "interception",
        group_task = mt.group_task, target = enemyGroup, target_label = contact.type,
        target_pos = { x = contact.pos.x, z = contact.pos.z },
        aircraft_type = aircraftType, count = 1, skill = Util.pick(AIR_TASKING_SKILL),
        launch_base = b.base, landing_base = b.base, parking = {}, takeoff = "runway",
        start_s = math.floor(now), takeoff_s = math.floor(now), tot_s = math.floor(now + d / p.cruise_speed_mps),
        end_s = math.floor(now + 2 * d / p.cruise_speed_mps + 1200),
        route = {
            { kind = "takeoff", x = b.pos.x, z = b.pos.z, alt_m = 0, speed_mps = 0 },
            { kind = "intercept", x = contact.pos.x, z = contact.pos.z, alt_m = alt, speed_mps = p.cruise_speed_mps,
              carries_attack_tasks = true },
            { kind = "landing", x = b.pos.x, z = b.pos.z, alt_m = 0, speed_mps = p.cruise_speed_mps },
        },
        attack = { kind = "intercept", groups = { enemyGroup }, weapon_type = AIR_WEAPON_TYPE[mt.weapon_type],
                   engage_range_m = mt.engage_range_km * 1000 },
        rules_of_engagement = mt.rules_of_engagement, loadout = AIRCRAFT_LOADOUT[aircraftType].interception,
        keeps_gun = true, critical_names = {}, suppression_threats = {},
    }
    local grp = SpawnAircraftGroups.spawn(m)
    if not grp then return false, "spawn failed" end
    ScheduleAirTaskingOrders.track(m)
    local s = st.bases[b.base]
    s.remaining, s.ready_s = s.remaining - 1, now + b.cooldown_s
    st.answered[enemyGroup] = m.id
    Log.info(string.format("%s scramble %s: %s from %s → %s (%s), in %s, %d km; %s has %d launch(es) left",
        st.coalition:upper(), m.id, aircraftType, b.base, enemyGroup, contact.type, zone.id, math.floor(d / 1000),
        b.base, s.remaining))
    return true
end

local function alive(groupName)
    local g = groupName and Group.getByName(groupName)
    if not (g and g:isExist()) then return false end
    for _, u in ipairs(g:getUnits() or {}) do
        if u:isExist() and u:getLife() > 0 then return true end
    end
    return false
end

local function check(st, now)
    local picture, asked, answered = radarPicture(st, st.coalition)
    local groups = 0
    for name, c in pairs(picture) do
        groups = groups + 1
        if not st.seen[name] then
            st.seen[name] = true
            local base, dist = nearestBaseName(c.pos)
            Log.info(string.format("%s radar: %s (%s) first seen by %s, %d km from %s", st.coalition:upper(), name,
                c.type, c.seen_by, math.floor(dist / 1000), base or "?"))
        end
        local zone = zoneOf(st, c.pos)
        if zone and not alive(st.answered[name]) then
            local ok, why = scramble(st, name, c, zone, now)
            if not ok and st.refused[name] ~= why then
                st.refused[name] = why
                Log.info(string.format("%s: no scramble for %s (%s) in %s — %s", st.coalition:upper(), name, c.type, zone.id, why))
            end
        end
    end
    if st.checks < 3 or now >= st.next_picture_log then
        st.next_picture_log = now + PICTURE_LOG_S
        Log.info(string.format("%s radars: %d of %d answered, enemy aircraft groups seen: %d", st.coalition:upper(),
            answered, asked, groups))
    end
    st.checks = st.checks + 1
end

function RunScrambles.start(plan)
    local ato = plan.air_tasking_orders
    if not ato or ato.problems then return end
    local interval
    for _, c in ipairs({ "red", "blue" }) do
        local posture = ato[c] and ato[c].alert
        if posture then
            local st = { coalition = c, posture = posture, bases = {}, answered = {}, seen = {}, refused = {},
                         next_number = posture.first_number, checks = 0, next_picture_log = 0 }
            for _, b in ipairs(posture.bases) do st.bases[b.base] = { remaining = b.scrambles, ready_s = 0 } end
            _state[c] = st
            interval = posture.check_interval_s
        end
    end
    if not interval then return end
    timer.scheduleFunction(function(_, t)
        for _, c in ipairs({ "red", "blue" }) do
            if _state[c] then
                local ok, err = pcall(check, _state[c], t)
                if not ok then Log.error("scramble check " .. c .. ": " .. tostring(err)) end
            end
        end
        return t + interval
    end, nil, timer.getTime() + interval)
    Log.info(string.format("--- Scrambles: checking every %d s ---", interval))
end
