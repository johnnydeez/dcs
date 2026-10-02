-- Consumer: spawns one planned flight (a plan.air_tasking_orders mission) with
-- coalition.addGroup — the one spawner for aircraft (ground groups and static objects
-- have their own, since DCS adds them with different tables). Called by the scheduler at
-- the mission's start time, not at mission start.
--
-- Builds, from the plan entry, nothing new decided:
--   units      on their reserved parking spots, hot (or on the runway for a runway
--              takeoff), with the planned loadout (gun emptied unless the mission keeps it)
--   waypoint 1 takeoff from parking or the runway, hot, plus the behaviour options
--              (data/air_tasking.lua): the mission's rules of engagement (open fire unless
--              it says otherwise), evade fire, return at bingo, no jettisoning unless the
--              mission may_jettison (fighters), return when out of its main weapon
--              if the mission says so, and afterburner allowed if it says afterburner
--              (scrambles)
--   the waypoint with carries_attack_tasks (the ingress; for suppression flights the
--              launch point; for patrols and the AWACS the station):
--              the attack tasks, in pydcs's parameter shape — Bombing per attack point,
--              AttackGroup / EngageGroup per group (a scramble's EngageGroup goes on the
--              takeoff waypoint: its route marks takeoff carries_attack_tasks), a race-track Orbit held until the time
--              on station is up (patrols engage from takeoff: EngageTargetsInZone on their
--              station's defended zone and each commit circle, on waypoint 1), the AWACS
--              task + that Orbit.
--              Group tasks need DCS group ids, looked up by name now; a group that no
--              longer exists is skipped
--   every other waypoint at its planned altitude, above sea level or, where the route
--              says alt_type "RADIO" (a SEAD flight's low run-in), above the ground; one
--              with `afterburner` set switches the afterburner option there
--   landing    at the landing base
--   every waypoint between takeoff and landing starts with a script command that writes
--              the event log's WAYPOINT line when the flight gets there
-- Datalink: every unit gets its own Link 16 STN and the editor's Link 16 settings block,
-- and the group an explicit group id and the EPLRS command (datalink on) as the first
-- task of its first waypoint, as the mission editor gives every AI flight (and the
-- Caucasus test pair that showed on the HSD had; the 2026-10-02 Kola run, with only STNs
-- and EPLRS by setCommand right after a ramp spawn, showed nothing: bug 25). setCommand
-- right after the spawn is kept too.
-- After the spawn, every unit's type is compared with the plan (DCS swaps unknown types),
-- the flight goes to the event log (SPAWNED), each unit's ammo is logged there a few
-- seconds later (LOADOUT, logAmmo), and a slow addGroup is a warning in dcs.log (a type's first spawn froze the sim; see
-- consumers/preload_aircraft_types.lua).
-- Reads the plan; writes nothing back to it.

SpawnAircraftGroups = {}

local COUNTRY = { red = "CJTF_RED", blue = "CJTF_BLUE" }
-- A spawn slower than this froze the sim noticeably (logged as a warning).
local SLOW_SPAWN_S = 1
-- Seconds after the spawn that each unit's ammo is logged (logAmmo).
local AMMO_CHECK_DELAY_S = 5
-- Link 16 STNs (five octal digits) for AI aircraft, one per unit, counted up from here;
-- the player slots' own STNs are 00201–00211 (the .miz)
local FIRST_AI_STN = 8 ^ 3   -- 01000
local _nextStn = FIRST_AI_STN

-- Explicit DCS group ids for AI flights (the EPLRS task names its group), counted up from
-- here, far above the editor's and DCS's own
local FIRST_AI_GROUP_ID = 700000
local _nextGroupId = FIRST_AI_GROUP_ID

local function nextStn()
    local stn = string.format("%05o", _nextStn)
    _nextStn = _nextStn + 1
    if _nextStn >= 8 ^ 5 then _nextStn = FIRST_AI_STN end
    return stn
end

-- DCS option ids and values (pydcs dcs/task.py: OptROE, OptReactOnThreat, ...).
local OPTION_ROE                                  = 0
local ROE = { weapons_free = 0, open_fire = 2, weapons_hold = 4 }
local OPTION_REACTION_ON_THREAT, EVADE_FIRE        = 1, 2
local OPTION_RETURN_AT_BINGO_FUEL                  = 6
local OPTION_PROHIBIT_JETTISON                     = 15
local OPTION_RETURN_WHEN_OUT_OF_AMMUNITION         = 10
local OPTION_PROHIBIT_AFTERBURNER                  = 16

local function option(number, name, value)
    return { number = number, auto = false, id = "WrappedAction", enabled = true,
             params = { action = { id = "Option", params = { name = name, value = value } } } }
end

local function combo(tasks)
    return { id = "ComboTask", params = { tasks = tasks } }
end

-- DCS group ids of the named groups that still exist, in order.
local function groupIds(m, names)
    local ids = {}
    for _, name in ipairs(names or {}) do
        local g = Group.getByName(name)
        if g and g:isExist() then
            ids[#ids + 1] = g:getID()
        else
            Log.info(string.format("%s: attack group %s no longer exists — skipped", m.id, name))
        end
    end
    return ids
end

-- The planned altitude of the route's target waypoint (the attack altitude; a SEAD
-- flight's pop-up altitude), or nil.
local function attackAltitude(m)
    for _, r in ipairs(m.route or {}) do
        if r.kind == "target" and r.alt_m and r.alt_m > 0 then return r.alt_m end
    end
    return nil
end

-- The attack tasks, numbered from `first`. Only the built attack kinds exist so far.
-- Bombing and AttackGroup carry the planned attack altitude: without it the DCS AI picks
-- its own once the attack starts, and flew it low (2026-10-02 run: MSN2027_STRIKE dropped
-- GBU-31s from 3,585 ft, planned 7,000 m, and died to an SA-8; MSN5024_SEAD fired its
-- Kh-31Ps from 3,400 ft, its pop-up planned at 3,000 m).
local function attackTasks(m, first)
    local tasks, a = {}, m.attack
    local function add(id, params)
        tasks[#tasks + 1] = { number = first + #tasks, auto = false, id = id, enabled = true, params = params }
    end
    local alt = attackAltitude(m)
    if a.kind == "bomb_critical_objects" then
        -- a set expend (All: one pass with everything; One / Two / Four: a standoff weapon
        -- spread over the critical objects) is one attack per point, then on to the egress
        local oneAttack = a.expend ~= nil and a.expend ~= "Auto"
        for _, p in ipairs(a.points) do
            add("Bombing", {
                x = p.x, y = p.z, weaponType = a.weapon_type, expend = a.expend,
                attackQtyLimit = oneAttack, attackQty = 1, directionEnabled = false, direction = 0,
                altitudeEnabled = alt ~= nil, altitude = alt or 0, groupAttack = true,
            })
        end
    elseif a.kind == "attack_group" then
        for _, id in ipairs(groupIds(m, a.groups)) do
            add("AttackGroup", {
                groupId = id, weaponType = a.weapon_type, expend = a.expend, groupAttack = true,
                attackQtyLimit = false, attackQty = 1, directionEnabled = false, direction = 0,
                altitudeEnabled = alt ~= nil, altitude = alt or 0,
            })
        end
    elseif a.kind == "harm_salvo" then
        -- the SEAD flight at its launch point: every anti-radiation missile at the site, once
        for _, id in ipairs(groupIds(m, a.groups)) do
            add("AttackGroup", {
                groupId = id, weaponType = a.weapon_type, expend = "All", groupAttack = true,
                attackQtyLimit = true, attackQty = 1, directionEnabled = false, direction = 0,
                altitudeEnabled = alt ~= nil, altitude = alt or 0,
            })
        end
    elseif a.kind == "engage_group" then
        -- en-route task: attacks each group once it is detected, in route order; with
        -- a.expend, each aircraft fires that many at a group, once (one attack), so the
        -- missiles last for every group it was given
        for i, id in ipairs(groupIds(m, a.groups)) do
            local t = { groupId = id, weaponType = a.weapon_type, priority = i, visible = false }
            if a.expend then t.expend, t.attackQtyLimit, t.attackQty = a.expend, true, 1 end
            add("EngageGroup", t)
        end
    elseif a.kind == "engage_aircraft_on_station" or a.kind == "early_warning_on_station" then
        if a.kind == "engage_aircraft_on_station" then
            -- a patrol with a defended zone got its engage tasks at takeoff (zoneEngageTasks);
            -- older plans without one: any enemy aircraft within range of the route
            if not a.zone then
                add("EngageTargets", { targetTypes = { [1] = "Air" }, value = "Air;", priority = 0,
                                       maxDistEnabled = true, maxDist = a.engage_range_m })
            end
        end   -- (the AWACS task is on the takeoff waypoint: bug 38)
        -- race-track between the station's two ends, until the time on station is up
        add("ControlledTask", {
            task = { id = "Orbit", params = { pattern = "Race-Track",
                point = { x = a.station[1], y = a.station[2] }, point2 = { x = a.station[3], y = a.station[4] },
                altitude = a.altitude_m, speed = a.speed_mps, speedEdited = true } },
            stopCondition = { time = a.until_s },
        })
    elseif a.kind == "intercept" then
        -- a scramble: only the raid it was sent after, in order (John, 2026-09-30: burn
        -- straight at that threat and kill it); on the takeoff waypoint, so it is active
        -- from wheels-up
        for i, id in ipairs(groupIds(m, a.groups)) do
            add("EngageGroup", { groupId = id, weaponType = a.weapon_type, priority = i, visible = false })
        end
    else
        Log.warn(string.format("%s: attack kind '%s' isn't built — the flight has no attack task", m.id, a.kind))
    end
    return tasks
end

-- A SEAD flight's en-route attack on its site, from the top of its pop-up on: the moment the site's radar is seen, every anti-radiation missile at
-- it, once (John, 2026-10-02, bug 36: on along the same track until it gets a radar ping
-- and can launch). It stays on past the launch point, through the press-on leg; the go
-- cold replaces the whole task when the salvo is away or the flight goes home.
local function pingAttackTasks(m, first)
    local tasks = {}
    for _, id in ipairs(groupIds(m, m.attack.groups)) do
        tasks[#tasks + 1] = { number = first + #tasks, auto = false, id = "EngageGroup", enabled = true,
                              params = { groupId = id, weaponType = m.attack.weapon_type, priority = 0, visible = false,
                                         expend = "All", attackQtyLimit = true, attackQty = 1 } }
    end
    return tasks
end

-- The index of the waypoint that carries a SEAD flight's en-route attack: the top of its
-- pop-up, so it fires from up there, not on the way up (2026-10-02, 17:48 run: the
-- Su-34s, armed from the pop-up, fired their Kh-31Ps from 1,500-3,300 ft at the first
-- ping, slow and low, and the SA-10 shot all 8 down; 0 of 24 Kh-31Ps through against
-- SA-10s and Patriots so far, while the F-16s fired from the top and killed the
-- Sodankyla SA-10's radars). On a route without a pop-up top: the pop-up, else the last
-- waypoint before the launch point. nil for other flights.
local function pingAttackIndex(m)
    if not (m.attack and m.attack.kind == "harm_salvo") then return nil end
    local popup
    for i, r in ipairs(m.route) do
        if r.kind == "popup_top" then return i end
        if r.kind == "popup" then popup = i end
        if r.kind == "target" then return popup or (i > 2 and i - 1) or nil end
    end
    return nil
end

-- A patrol's standing tasks from takeoff to landing: engage any enemy aircraft inside its
-- station's defended zone or one of its commit circles (the own and contested airspace
-- of its sector), so a patrol still on its way (or relieving one that was shot down)
-- defends them too. Numbered from `first`; empty for every other flight.
local function zoneEngageTasks(m, first)
    local a, tasks = m.attack, {}
    if not (a and a.kind == "engage_aircraft_on_station" and a.zone) then return tasks end
    local function add(z)
        tasks[#tasks + 1] = { number = first + #tasks, auto = false, id = "EngageTargetsInZone", enabled = true,
                              params = { targetTypes = { [1] = "Air" }, value = "Air;", priority = 0,
                                         point = { x = z.x, y = z.z }, zoneRadius = z.radius_m } }
    end
    add(a.zone)
    for _, z in ipairs(a.commit or {}) do add(z) end
    return tasks
end

-- The script command that writes the event log's WAYPOINT line when the flight reaches
-- waypoint `index`; runs first on that waypoint.
local function reachedCommand(m, index)
    return { number = 1, auto = false, id = "WrappedAction", enabled = true,
             params = { action = { id = "Script", params = {
                 command = string.format("WriteEventLog.waypoint(%q, %d) ControlAirFlights.waypoint(%q, %d)",
                     m.id, index, m.id, index) } } } }
end

local function waypoint(r, extra)
    local wp = {
        x = r.x, y = r.z, alt = r.alt_m, alt_type = r.alt_type or "BARO", speed = r.speed_mps, speed_locked = true,
        ETA = 0, ETA_locked = false, type = "Turning Point", action = "Turning Point", task = combo({}),
    }
    for k, v in pairs(extra or {}) do wp[k] = v end
    return wp
end

local function buildGroup(m, launchId, landingId)
    local lo = m.loadout
    local units = {}
    local runway = m.takeoff == "runway"
    for i = 1, m.count do
        -- a runway takeoff has no spot: DCS lines the group up on the runway
        local spot = (not runway) and m.parking[i] or { x = m.route[1].x, z = m.route[1].z }
        local pylons = {}
        for _, py in ipairs(lo.pylons) do pylons[py.num] = { CLSID = py.CLSID, num = py.num } end
        units[i] = {
            name = m.id .. "_" .. i, type = m.aircraft_type, skill = m.skill,
            x = spot.x, y = spot.z, alt = land.getHeight({ x = spot.x, y = spot.z }), alt_type = "BARO",
            heading = 0, speed = 0, parking = spot.terminal_index,
            payload = { pylons = pylons, fuel = lo.fuel, chaff = lo.chaff, flare = lo.flare,
                        gun = m.keeps_gun and 100 or 0 },
            AddPropAircraft = { STN_L16 = nextStn() },
            datalinks = { Link16 = {
                settings = { flightLead = i == 1, transmitPower = 3, specialChannel = 1, fighterChannel = 1,
                             missionChannel = 1 },
                network = { teamMembers = {}, donors = {} },
            } },
        }
    end
    local groupId = _nextGroupId
    _nextGroupId = _nextGroupId + 1
    local rules = m.rules_of_engagement or "open_fire"

    local points = {}
    local pingAt = pingAttackIndex(m)
    for index, r in ipairs(m.route) do
        if r.kind == "takeoff" then
            local tasks = {
                { number = 1, auto = false, id = "WrappedAction", enabled = true,
                  params = { action = { id = "EPLRS", params = { value = true, groupId = groupId } } } },
                option(2, OPTION_ROE, ROE[rules]),
                option(3, OPTION_REACTION_ON_THREAT, EVADE_FIRE),
                option(4, OPTION_RETURN_AT_BINGO_FUEL, true),
            }
            if not m.may_jettison then   -- attack flights keep their stores; fighters may drop tanks
                tasks[#tasks + 1] = option(#tasks + 1, OPTION_PROHIBIT_JETTISON, true)
            end
            if m.return_when_out_of then
                tasks[#tasks + 1] = option(#tasks + 1, OPTION_RETURN_WHEN_OUT_OF_AMMUNITION, m.return_when_out_of)
            end
            if m.afterburner then   -- scrambles: afterburner explicitly allowed
                tasks[#tasks + 1] = option(#tasks + 1, OPTION_PROHIBIT_AFTERBURNER, false)
            end
            for _, t in ipairs(zoneEngageTasks(m, #tasks + 1)) do tasks[#tasks + 1] = t end
            -- the AWACS works from takeoff, not only on station (bug 38: the E-3A reported its
            -- first contact a minute before its station, 26 min after takeoff)
            if m.attack and m.attack.kind == "early_warning_on_station" then
                tasks[#tasks + 1] = { number = #tasks + 1, auto = false, id = "AWACS", enabled = true, params = {} }
            end
            if r.carries_attack_tasks then
                for _, t in ipairs(attackTasks(m, #tasks + 1)) do tasks[#tasks + 1] = t end
            end
            points[#points + 1] = waypoint(r, {
                type = runway and "TakeOff" or "TakeOffParkingHot",
                action = runway and "From Runway" or "From Parking Area Hot", airdromeId = launchId,
                alt = land.getHeight({ x = r.x, y = r.z }), speed = 0, task = combo(tasks),
            })
        elseif r.carries_attack_tasks then
            local tasks = { reachedCommand(m, index) }
            for _, t in ipairs(attackTasks(m, 2)) do tasks[#tasks + 1] = t end
            points[#points + 1] = waypoint(r, { task = combo(tasks) })
        elseif r.kind == "landing" then
            points[#points + 1] = waypoint(r, { type = "Land", action = "Landing", airdromeId = landingId,
                alt = land.getHeight({ x = r.x, y = r.z }) })
        else
            local tasks = { reachedCommand(m, index) }
            if r.afterburner ~= nil then   -- SEAD: allowed from the pop-up through the egress; off again at the climb
                tasks[2] = option(2, OPTION_PROHIBIT_AFTERBURNER, not r.afterburner)
            end
            if index == pingAt then
                for _, t in ipairs(pingAttackTasks(m, #tasks + 1)) do tasks[#tasks + 1] = t end
            end
            points[#points + 1] = waypoint(r, { task = combo(tasks) })
        end
    end

    return {
        name = m.id, groupId = groupId, task = m.group_task, uncontrolled = false, start_time = 0,
        x = units[1].x, y = units[1].y, units = units, route = { points = points },
    }
end

-- Spawns one mission's flight. Returns the DCS group or nil.
function SpawnAircraftGroups.spawn(m)
    local launch  = Airbase.getByName(m.launch_base)
    local landing = Airbase.getByName(m.landing_base)
    if not launch or not landing then
        Log.warn(string.format("%s: airbase %s / %s not found — not spawned", m.id, m.launch_base, m.landing_base))
        return nil
    end
    local data = buildGroup(m, launch:getID(), landing:getID())
    local t0 = Util.clock()
    local ok, grp = pcall(coalition.addGroup, country.id[COUNTRY[m.coalition]], Group.Category.AIRPLANE, data)
    local spent = Util.clock() - t0
    if not ok or not grp then
        Log.warn(string.format("%s: coalition.addGroup failed (%s)", m.id, tostring(grp)))
        return nil
    end
    -- the EPLRS task on the first waypoint names the group id we asked for (bug 25)
    if grp:getID() ~= data.groupId then
        Log.warn(string.format("%s: asked for group id %d, DCS gave %s: its EPLRS task names the wrong group",
            m.id, data.groupId, tostring(grp:getID())))
    end
    -- datalink on, so the flight shows on the players' HSD (as the mission editor does)
    local okLink, linkErr = pcall(function()
        grp:getController():setCommand({ id = "EPLRS", params = { value = true, groupId = grp:getID() } })
    end)
    if not okLink then Log.warn(string.format("%s: EPLRS command failed (%s)", m.id, tostring(linkErr))) end
    for i, u in ipairs(grp:getUnits() or {}) do
        if u:getTypeName() ~= m.aircraft_type then
            Log.warn(string.format("%s unit %d: asked for '%s', DCS spawned '%s'", m.id, i, m.aircraft_type, u:getTypeName()))
        end
    end
    WriteEventLog.spawned(m, m.takeoff == "runway")
    if spent > SLOW_SPAWN_S then
        Log.warn(string.format("%s: addGroup took %.1f s — the sim froze (was %s preloaded?)", m.id, spent, m.aircraft_type))
    end
    timer.scheduleFunction(function() SpawnAircraftGroups.logAmmo(m) end, nil, timer.getTime() + AMMO_CHECK_DELAY_S)
    return grp
end

-- Pylons of a loadout that hold weapons (not fuel tanks, targeting or jamming pods, smoke).
local function weaponPylons(loadout)
    local n = 0
    for _, py in ipairs(loadout.pylons or {}) do
        local w = (py.weapon or ""):lower()
        if not (w:find("fuel tank", 1, true) or w:find("targeting pod", 1, true) or w:find("ecm", 1, true)
                or w:find("jamm", 1, true) or w:find("smoke", 1, true)) then
            n = n + 1
        end
    end
    return n
end

-- What each unit of a spawned flight actually carries, as DCS reports it (John's run,
-- 2026-09-27: a Su-24M flight looked unarmed although the plan gave it a loadout), to
-- the event log. A jet with no weapon aboard (its gun aside) while its loadout lists
-- weapon pylons is a warning in dcs.log, and the controller removes it on the ramp
-- (ControlAirFlights.unarmed; bug 6), so it never flies into a fight with nothing.
function SpawnAircraftGroups.logAmmo(m)
    local grp = Group.getByName(m.id)
    if not (grp and grp:isExist()) then return end
    local pylons = weaponPylons(m.loadout)
    local unarmed = {}
    for _, u in ipairs(grp:getUnits() or {}) do
        local parts, weapons = {}, 0
        for _, a in ipairs(u:getAmmo() or {}) do
            local d = a.desc or {}
            parts[#parts + 1] = string.format("%s x%d", d.displayName or d.typeName or "?", a.count or 0)
            if d.category ~= Weapon.Category.SHELL and (a.count or 0) > 0 then weapons = weapons + 1 end
        end
        local carries = #parts > 0 and table.concat(parts, ", ") or "nothing"
        WriteEventLog.add(m.coalition, "LOADOUT", u:getName(), string.format("%s carries %s", m.aircraft_type, carries))
        if weapons == 0 and pylons > 0 then
            Log.warn(string.format("%s: %s carries no weapons — its loadout '%s' lists %d weapon pylons", m.id, u:getName(),
                m.loadout.name, pylons))
            unarmed[#unarmed + 1] = u:getName()
        end
    end
    if #unarmed > 0 then
        ControlAirFlights.unarmed(m, unarmed, string.format("'%s' lists %d weapon pylons", m.loadout.name, pylons))
    end
end
