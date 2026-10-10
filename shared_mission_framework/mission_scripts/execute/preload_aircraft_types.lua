-- Execute: loads every aircraft type the air tasking orders will use, at start-up, so
-- no first spawn freezes the sim mid-mission. DCS loads a type's model, liveries and
-- damage model on its first spawn, on the main thread, inside coalition.addGroup: the
-- 2026-09-25 run froze ~25 s on the first F-15E (T+120 s) and ~7 s on the first Su-24M
-- (T+1132 s). Repeat spawns of a type were clean.
--
-- For every coalition and aircraft type among the planned flights and the scramble
-- posture's alert aircraft, one group is spawned in the air, 9 km above a base that type
-- flies from, with one unit per distinct loadout (so the weapon models load too), and
-- destroyed at once. Runs with the rest of start-up, before any flight is scheduled.
-- Each spawn is timed; the first-spawn cost now lands here instead of in the mission:
--   "PRELOAD RED Su-24M: 2 loadouts, 6.84 s"
-- Reads the plan; writes nothing back to it.

ExecutePreloadAircraftTypes = {}

local COUNTRY = { red = "CJTF_RED", blue = "CJTF_BLUE" }
local ALTITUDE_M = 9000
local SPEED_MPS = 200
local UNIT_SPACING_M = 200

-- A loadout's identity: its pylons' CLSIDs in order.
local function loadoutKey(lo)
    local parts = {}
    for _, py in ipairs(lo.pylons) do parts[#parts + 1] = py.num .. "=" .. py.CLSID end
    return table.concat(parts, ";")
end

-- { { coalition, aircraft_type, pos, loadouts = { … } } } in first-seen order.
local function typesToLoad(plan)
    local list, byKey = {}, {}
    local function add(coalition, aircraftType, pos, lo)
        local key = coalition .. "|" .. aircraftType
        local e = byKey[key]
        if not e then
            e = { coalition = coalition, aircraft_type = aircraftType, pos = pos, loadouts = {}, seen = {} }
            byKey[key] = e
            list[#list + 1] = e
        end
        if lo and not e.seen[loadoutKey(lo)] then
            e.seen[loadoutKey(lo)] = true
            e.loadouts[#e.loadouts + 1] = lo
        end
    end
    local ato = plan.air_tasking_orders
    for _, c in ipairs({ "red", "blue" }) do
        for _, m in ipairs(ato[c] and ato[c].missions or {}) do
            -- human flights aren't spawned: the player brings the aircraft
            if m.flown_by ~= "human" then
                add(c, m.aircraft_type, { x = m.route[1].x, z = m.route[1].z }, m.loadout)
            end
        end
        local alert = ato[c] and ato[c].alert
        for _, b in ipairs(alert and alert.bases or {}) do
            for _, e in ipairs(b.aircraft) do
                local byType = AIRCRAFT_LOADOUT[e[1]]
                add(c, e[1], b.pos, byType and byType.interception)
            end
        end
    end
    return list
end

local function buildGroup(e, name)
    local units = {}
    for i, lo in ipairs(e.loadouts) do
        local pylons = {}
        for _, py in ipairs(lo.pylons) do pylons[py.num] = { CLSID = py.CLSID, num = py.num } end
        units[i] = {
            name = name .. "_" .. i, type = e.aircraft_type, skill = "Average",
            x = e.pos.x + (i - 1) * UNIT_SPACING_M, y = e.pos.z, alt = ALTITUDE_M, alt_type = "BARO",
            heading = 0, speed = SPEED_MPS,
            payload = { pylons = pylons, fuel = lo.fuel, chaff = lo.chaff, flare = lo.flare, gun = 100 },
        }
    end
    return {
        name = name, task = "Nothing", uncontrolled = false, start_time = 0,
        x = e.pos.x, y = e.pos.z, units = units,
        route = { points = { {
            x = e.pos.x, y = e.pos.z, alt = ALTITUDE_M, alt_type = "BARO", speed = SPEED_MPS,
            type = "Turning Point", action = "Turning Point",
            task = { id = "ComboTask", params = { tasks = {} } },
        } } },
    }
end

-- Spawns and removes one group; returns seconds spent in addGroup, or nil and why.
local function load(e)
    local name = string.format("PRELOAD_%s_%s", e.coalition:upper(), e.aircraft_type)
    local t0 = Util.clock()
    local ok, grp = pcall(coalition.addGroup, country.id[COUNTRY[e.coalition]], Group.Category.AIRPLANE,
        buildGroup(e, name))
    local spent = Util.clock() - t0
    if not ok or not grp then return nil, tostring(grp or "not spawned") end
    local mismatch
    for _, u in ipairs(grp:getUnits() or {}) do
        if u:getTypeName() ~= e.aircraft_type then mismatch = u:getTypeName() end
    end
    pcall(grp.destroy, grp)
    if mismatch then return spent, "DCS spawned '" .. mismatch .. "'" end
    return spent
end

function ExecutePreloadAircraftTypes.run(plan)
    local ato = plan.air_tasking_orders
    if not ato or ato.problems then return end
    local list = typesToLoad(plan)
    local total, slowest, slowestType = 0, 0, nil
    for _, e in ipairs(list) do
        if #e.loadouts == 0 then
            Log.warn(string.format("PRELOAD %s %s: no loadout known — skipped", e.coalition:upper(), e.aircraft_type))
        else
            local spent, why = load(e)
            if spent then
                total = total + spent
                if spent > slowest then slowest, slowestType = spent, e.aircraft_type end
                Log.info(string.format("PRELOAD %s %s: %d loadout(s), %.2f s%s", e.coalition:upper(), e.aircraft_type,
                    #e.loadouts, spent, why and (" — " .. why) or ""))
            else
                Log.warn(string.format("PRELOAD %s %s: failed (%s)", e.coalition:upper(), e.aircraft_type, why))
            end
        end
    end
    Log.info(string.format("--- Aircraft types preloaded: %d in %.1f s%s ---", #list, total,
        slowestType and string.format(", slowest %s %.1f s", slowestType, slowest) or ""))
end
