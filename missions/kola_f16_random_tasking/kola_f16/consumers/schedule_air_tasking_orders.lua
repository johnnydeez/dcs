-- Consumer: runs the air tasking orders on the mission clock. Each planned flight is
-- spawned by SpawnAircraftGroups at its start_s (mission time); a start already past is
-- spawned a second from now. Aircraft of planned flights are removed a few minutes after
-- they land, freeing their parking spots and the alive-aircraft budget (the Syria
-- S_EVENT_LAND pattern).
-- What the flights did (shots, kills, losses, landings, positions) goes to the event
-- log (consumers/write_event_log.lua), which catches the DCS events for every unit; this
-- only adds each mission's target progress:
--   "TARGET  MSN2001_STRIKE  TGT_IVAL_command_post_1_static_2 destroyed: 3 of 6 critical"
-- Reads the plan; writes nothing back to it. What has launched, landed and been
-- destroyed is runtime state, kept here under the plan's mission ids.

ScheduleAirTaskingOrders = {}

local REMOVE_AFTER_LANDING_S = 180

local _flights = {}   -- mission id → { mission, spawned, destroyed = n }
local _targets = {}   -- critical object name → mission id
local _gone    = {}   -- names already counted destroyed or lost

local function nameOf(object)
    local ok, name = pcall(function() return object:getName() end)
    return ok and name or nil
end

-- The mission id of the planned flight this unit belongs to, or nil.
local function flightOf(unit)
    local ok, name = pcall(function() return unit:getGroup():getName() end)
    if ok and _flights[name] then return name end
    return nil
end

local function landed(unit)
    local name = flightOf(unit)
    if not name then return end
    local unitName = unit:getName()
    _flights[name].landed = _flights[name].landed + 1
    timer.scheduleFunction(function()
        local u = Unit.getByName(unitName)
        if u and u:isExist() then u:destroy() end
    end, nil, timer.getTime() + REMOVE_AFTER_LANDING_S)
end

local function destroyed(object)
    local name = nameOf(object)
    if not name or _gone[name] then return end
    local target = _targets[name]
    if target then
        _gone[name] = true
        local f = _flights[target]
        f.destroyed = f.destroyed + 1
        WriteEventLog.add(f.mission.coalition, "TARGET", target, string.format("%s destroyed: %d of %d critical",
            name, f.destroyed, #f.mission.critical_names))
        return
    end
    local flight = flightOf(object)
    if flight then
        _gone[name] = true
        _flights[flight].lost = _flights[flight].lost + 1
    end
end

local handler = {}
function handler:onEvent(e)
    if not e.initiator then return end
    if e.id == world.event.S_EVENT_LAND then
        local ok, category = pcall(function() return e.initiator:getCategory() end)
        if ok and category == Object.Category.UNIT then landed(e.initiator) end
    elseif e.id == world.event.S_EVENT_KILL then
        if e.target then destroyed(e.target) end
    elseif e.id == world.event.S_EVENT_DEAD then
        destroyed(e.initiator)
    elseif e.id == world.event.S_EVENT_CRASH then
        destroyed(e.initiator)
    elseif e.id == world.event.S_EVENT_EJECTION then
        destroyed(e.initiator)
    end
end

-- A flight spawned at run time (a scramble), tracked like a planned one: its losses
-- count and its aircraft are removed after landing.
function ScheduleAirTaskingOrders.track(m)
    _flights[m.id] = { mission = m, spawned = true, destroyed = 0, lost = 0, landed = 0 }
end

-- A planned flight's state now, in a few words: "planned", "airborne", "landed",
-- "2 of 2 lost", …, plus its target objects destroyed so far (anyone's hits count).
function ScheduleAirTaskingOrders.statusOf(id)
    local f = _flights[id]
    if not f then return "unknown" end
    local m = f.mission
    local state
    if m.flown_by == "human" then
        state = "for a player"
    elseif not f.spawned then
        state = "planned"
    elseif f.lost >= m.count then
        state = string.format("%d of %d lost", f.lost, m.count)
    elseif f.lost + f.landed >= m.count then
        state = f.lost > 0 and string.format("landed, %d lost", f.lost) or "landed"
    else
        state = f.lost > 0 and string.format("airborne, %d lost", f.lost) or "airborne"
    end
    if f.destroyed > 0 then
        state = string.format("%s; target %d of %d critical destroyed", state, f.destroyed, #(m.critical_names or {}))
    end
    return state
end

function ScheduleAirTaskingOrders.start(plan)
    local ato = plan.air_tasking_orders
    if not ato or ato.problems then return end
    local now, count, first = timer.getTime(), 0, nil
    local human = 0
    for _, coalition in ipairs({ "red", "blue" }) do
        for _, m in ipairs(ato[coalition] and ato[coalition].missions or {}) do
            _flights[m.id] = { mission = m, spawned = false, destroyed = 0, lost = 0, landed = 0 }
            if not m.escorts then
                for _, name in ipairs(m.critical_names or {}) do _targets[name] = m.id end
            end
            -- human flights aren't spawned: the player spawns in on the slot (its target
            -- is still watched, above)
            if m.flown_by == "human" then
                human = human + 1
            else
                local at = math.max(m.start_s, now + 1)
                timer.scheduleFunction(function()
                    _flights[m.id].spawned = SpawnAircraftGroups.spawn(m) ~= nil
                end, nil, at)
                count = count + 1
                if not first or at < first then first = at end
            end
        end
    end
    world.addEventHandler(handler)
    Log.info(string.format("--- Air tasking orders: %d flights scheduled%s, %d human flights left to players ---", count,
        first and string.format(", first at T+%d s", math.floor(first)) or "", human))
end
