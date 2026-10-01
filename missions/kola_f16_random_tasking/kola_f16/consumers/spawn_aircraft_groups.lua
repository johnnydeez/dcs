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
--              waypoint before their first ring; for patrols and the AWACS the station):
--              the attack tasks, in pydcs's parameter shape — Bombing per attack point,
--              AttackGroup / EngageGroup per group (a scramble's EngageGroup goes on the
--              takeoff waypoint: its route marks takeoff carries_attack_tasks), a race-track Orbit held until the time
--              on station is up (patrols engage from takeoff: EngageTargetsInZone on their
--              station's defended zone and each commit circle, on waypoint 1), the AWACS
--              task + that Orbit.
--              Group tasks need DCS group ids, looked up by name now; a group that no
--              longer exists is skipped
--   landing    at the landing base
--   every waypoint between takeoff and landing starts with a script command that writes
--              the event log's WAYPOINT line when the flight gets there
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

-- The attack tasks, numbered from `first`. Only the built attack kinds exist so far.
local function attackTasks(m, first)
    local tasks, a = {}, m.attack
    local function add(id, params)
        tasks[#tasks + 1] = { number = first + #tasks, auto = false, id = id, enabled = true, params = params }
    end
    if a.kind == "bomb_critical_objects" then
        for _, p in ipairs(a.points) do
            add("Bombing", {
                x = p.x, y = p.z, weaponType = a.weapon_type, expend = a.expend,
                attackQtyLimit = false, attackQty = 1, directionEnabled = false, direction = 0,
                altitudeEnabled = false, altitude = 0, groupAttack = true,
            })
        end
    elseif a.kind == "attack_group" then
        for _, id in ipairs(groupIds(m, a.groups)) do
            add("AttackGroup", {
                groupId = id, weaponType = a.weapon_type, expend = a.expend, groupAttack = true,
                attackQtyLimit = false, attackQty = 1, directionEnabled = false, direction = 0,
                altitudeEnabled = false, altitude = 0,
            })
        end
    elseif a.kind == "engage_group" then
        -- en-route task: attacks each group once it is detected, in route order
        for i, id in ipairs(groupIds(m, a.groups)) do
            add("EngageGroup", { groupId = id, weaponType = a.weapon_type, priority = i, visible = false })
        end
    elseif a.kind == "engage_aircraft_on_station" or a.kind == "early_warning_on_station" then
        if a.kind == "engage_aircraft_on_station" then
            -- a patrol with a defended zone got its engage tasks at takeoff (zoneEngageTasks);
            -- older plans without one: any enemy aircraft within range of the route
            if not a.zone then
                add("EngageTargets", { targetTypes = { [1] = "Air" }, value = "Air;", priority = 0,
                                       maxDistEnabled = true, maxDist = a.engage_range_m })
            end
        else
            add("AWACS", {})
        end
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
                 command = string.format("WriteEventLog.waypoint(%q, %d)", m.id, index) } } } }
end

local function waypoint(r, extra)
    local wp = {
        x = r.x, y = r.z, alt = r.alt_m, alt_type = "BARO", speed = r.speed_mps, speed_locked = true,
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
        }
    end
    local rules = m.rules_of_engagement or "open_fire"

    local points = {}
    for index, r in ipairs(m.route) do
        if r.kind == "takeoff" then
            local tasks = {
                option(1, OPTION_ROE, ROE[rules]),
                option(2, OPTION_REACTION_ON_THREAT, EVADE_FIRE),
                option(3, OPTION_RETURN_AT_BINGO_FUEL, true),
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
            points[#points + 1] = waypoint(r, { task = combo({ reachedCommand(m, index) }) })
        end
    end

    return {
        name = m.id, task = m.group_task, uncontrolled = false, start_time = 0,
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

-- What each unit of a spawned flight actually carries, as DCS reports it (John's run,
-- 2026-09-27: a Su-24M flight looked unarmed although the plan gave it a loadout), to
-- the event log. A flight with nothing aboard while its loadout lists pylons is also a
-- warning in dcs.log.
function SpawnAircraftGroups.logAmmo(m)
    local grp = Group.getByName(m.id)
    if not (grp and grp:isExist()) then return end
    for _, u in ipairs(grp:getUnits() or {}) do
        local parts = {}
        for _, a in ipairs(u:getAmmo() or {}) do
            local d = a.desc or {}
            parts[#parts + 1] = string.format("%s x%d", d.displayName or d.typeName or "?", a.count or 0)
        end
        local carries = #parts > 0 and table.concat(parts, ", ") or "nothing"
        WriteEventLog.add(m.coalition, "LOADOUT", u:getName(), string.format("%s carries %s", m.aircraft_type, carries))
        if #parts == 0 and #m.loadout.pylons > 0 then
            Log.warn(string.format("%s: %s carries nothing — its loadout '%s' lists %d pylons", m.id, u:getName(),
                m.loadout.name, #m.loadout.pylons))
        end
    end
end
