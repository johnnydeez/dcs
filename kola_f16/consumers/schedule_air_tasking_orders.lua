-- Consumer: runs the air tasking orders on the mission clock. Each planned flight is
-- spawned by SpawnAircraftGroups at its start_s (mission time); a start already past is
-- spawned a second from now. Aircraft of planned flights are removed a few minutes after
-- they land, freeing their parking spots and the alive-aircraft budget (the Syria
-- S_EVENT_LAND pattern).
-- Reads the plan; writes nothing back to it. What has launched and landed is runtime
-- state, kept here under the plan's mission ids.

ScheduleAirTaskingOrders = {}

local REMOVE_AFTER_LANDING_S = 180

local _flights = {}   -- mission id → { mission, spawned }

local function landed(unit)
    local ok, name = pcall(function() return unit:getGroup():getName() end)
    if not ok or not _flights[name] then return end
    local unitName = unit:getName()
    Log.info(string.format("%s: %s landed — removing it in %d s", name, unitName, REMOVE_AFTER_LANDING_S))
    timer.scheduleFunction(function()
        local u = Unit.getByName(unitName)
        if u and u:isExist() then u:destroy() end
    end, nil, timer.getTime() + REMOVE_AFTER_LANDING_S)
end

local handler = {}
function handler:onEvent(e)
    if e.id == world.event.S_EVENT_LAND and e.initiator then
        local ok, category = pcall(function() return e.initiator:getCategory() end)
        if ok and category == Object.Category.UNIT then landed(e.initiator) end
    end
end

function ScheduleAirTaskingOrders.start(plan)
    local ato = plan.air_tasking_orders
    if not ato or ato.problems then return end
    local now, count, first = timer.getTime(), 0, nil
    for _, coalition in ipairs({ "red", "blue" }) do
        for _, m in ipairs(ato[coalition] and ato[coalition].missions or {}) do
            _flights[m.id] = { mission = m, spawned = false }
            local at = math.max(m.start_s, now + 1)
            timer.scheduleFunction(function()
                _flights[m.id].spawned = SpawnAircraftGroups.spawn(m) ~= nil
            end, nil, at)
            count = count + 1
            if not first or at < first then first = at end
        end
    end
    world.addEventHandler(handler)
    Log.info(string.format("--- Air tasking orders: %d flights scheduled%s ---", count,
        first and string.format(", first at T+%d s", math.floor(first)) or ""))
end
