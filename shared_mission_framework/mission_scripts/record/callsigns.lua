-- The record of the callsign numbers given out, per coalition: name → last number given.
-- Writers: the planner, through the plan (air_tasking_orders[coalition].callsign_numbers,
-- copied here at start), then the controller (scrambles and SEAD retries, which carry on
-- from the plan's numbers through the tool, tools\flight_callsigns.lua).

RecordCallsigns = {}

local _numbers = { red = {}, blue = {} }

-- The coalition's numbers table: the controller hands it to FlightCallsigns.assign, which
-- writes the number it gives out into it.
function RecordCallsigns.numbers(c)
    return _numbers[c]
end

-- At start: the numbers the plan gave out.
function RecordCallsigns.start(plan)
    local ato = plan.air_tasking_orders or {}
    for _, coalition in ipairs({ "red", "blue" }) do
        _numbers[coalition] = {}
        for name, n in pairs(ato[coalition] and ato[coalition].callsign_numbers or {}) do
            _numbers[coalition][name] = n
        end
    end
end
