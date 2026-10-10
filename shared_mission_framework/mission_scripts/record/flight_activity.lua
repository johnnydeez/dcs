-- The record of what AI flights' jets are doing now: in the air, where, heading, fuel,
-- weapons aboard. One writer: watch\flight_activity.lua, worked out when read (rule 11).

RecordFlightActivity = {}

-- The jets of group `name` alive and in the air, lead first (watch\flight_activity.lua
-- says what each holds).
function RecordFlightActivity.airborneJets(name)
    return WatchFlightActivity.airborneJets(name)
end

-- Jet `unitName` now, or nil.
function RecordFlightActivity.jet(unitName)
    return WatchFlightActivity.jet(unitName)
end

-- Where the first jet of group `name` still there is, or nil.
function RecordFlightActivity.firstAlivePoint(name)
    return WatchFlightActivity.firstAlivePoint(name)
end
