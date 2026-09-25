-- Consumer: spawns one planned flight (a plan.air_tasking_orders mission) with
-- coalition.addGroup — the one spawner for aircraft (ground groups and static objects
-- have their own, since DCS adds them with different tables). Called by the scheduler at
-- the mission's start time, not at mission start.
--
-- Builds, from the plan entry, nothing new decided:
--   units      on their reserved parking spots, hot, with the planned loadout (gun
--              emptied unless the profile keeps it)
--   waypoint 1 takeoff from parking, hot, plus the behaviour options every attack flight
--              gets (data/air_tasking.lua): open fire, evade fire, return at bingo, no
--              jettisoning, and return when out of its main weapon if the mission says so
--   the waypoint with carries_attack_tasks (the ingress, or for suppression flights the
--              waypoint before their first ring): the attack tasks, in pydcs's parameter
--              shape — Bombing per attack point, AttackGroup / EngageGroup per group.
--              Group tasks need DCS group ids, looked up by name now; a group that no
--              longer exists is skipped
--   landing    at the landing base
-- After the spawn, every unit's type is compared with the plan (DCS swaps unknown types).
-- Reads the plan; writes nothing back to it.

SpawnAircraftGroups = {}

local COUNTRY = { red = "CJTF_RED", blue = "CJTF_BLUE" }

-- DCS option ids and values (pydcs dcs/task.py: OptROE, OptReactOnThreat, ...).
local OPTION_ROE, ROE_OPEN_FIRE                    = 0, 2
local OPTION_REACTION_ON_THREAT, EVADE_FIRE        = 1, 2
local OPTION_RETURN_AT_BINGO_FUEL                  = 6
local OPTION_PROHIBIT_JETTISON                     = 15
local OPTION_RETURN_WHEN_OUT_OF_AMMUNITION         = 10

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
    else
        Log.warn(string.format("%s: attack kind '%s' isn't built — the flight has no attack task", m.id, a.kind))
    end
    return tasks
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
    for i = 1, m.count do
        local spot = m.parking[i]
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

    local points = {}
    for _, r in ipairs(m.route) do
        if r.kind == "takeoff" then
            local tasks = {
                option(1, OPTION_ROE, ROE_OPEN_FIRE),
                option(2, OPTION_REACTION_ON_THREAT, EVADE_FIRE),
                option(3, OPTION_RETURN_AT_BINGO_FUEL, true),
                option(4, OPTION_PROHIBIT_JETTISON, true),
            }
            if m.return_when_out_of then
                tasks[#tasks + 1] = option(#tasks + 1, OPTION_RETURN_WHEN_OUT_OF_AMMUNITION, m.return_when_out_of)
            end
            if r.carries_attack_tasks then
                for _, t in ipairs(attackTasks(m, #tasks + 1)) do tasks[#tasks + 1] = t end
            end
            points[#points + 1] = waypoint(r, {
                type = "TakeOffParkingHot", action = "From Parking Area Hot", airdromeId = launchId,
                alt = land.getHeight({ x = r.x, y = r.z }), speed = 0, task = combo(tasks),
            })
        elseif r.carries_attack_tasks then
            points[#points + 1] = waypoint(r, { task = combo(attackTasks(m, 1)) })
        elseif r.kind == "landing" then
            points[#points + 1] = waypoint(r, { type = "Land", action = "Landing", airdromeId = landingId,
                alt = land.getHeight({ x = r.x, y = r.z }) })
        else
            points[#points + 1] = waypoint(r)
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
    local ok, grp = pcall(coalition.addGroup, country.id[COUNTRY[m.coalition]], Group.Category.AIRPLANE,
        buildGroup(m, launch:getID(), landing:getID()))
    if not ok or not grp then
        Log.warn(string.format("%s: coalition.addGroup failed (%s)", m.id, tostring(grp)))
        return nil
    end
    local mismatches = 0
    for i, u in ipairs(grp:getUnits() or {}) do
        if u:getTypeName() ~= m.aircraft_type then
            mismatches = mismatches + 1
            Log.warn(string.format("%s unit %d: asked for '%s', DCS spawned '%s'", m.id, i, m.aircraft_type, u:getTypeName()))
        end
    end
    Log.info(string.format("%s spawned: %s %s %dx %s at %s → %s (%s)%s, TOT %d s; %d type mismatches",
        m.id, m.coalition:upper(), m.mission_type, m.count, m.aircraft_type, m.launch_base, m.target,
        m.target_label, m.escorts and (", escorting " .. m.escorts .. ", engaging " .. table.concat(m.suppresses, ", ")) or "",
        m.tot_s, mismatches))
    return grp
end
