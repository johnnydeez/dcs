-- The record of every airborne aircraft of a coalition now (the event log's POSITION
-- lines). One writer: watch\aircraft_positions.lua, worked out when read (rule 11).

RecordAircraftPositions = {}

-- Every airborne aircraft of coalition `side` (watch\aircraft_positions.lua says what each holds).
function RecordAircraftPositions.list(side)
    return WatchAircraftPositions.list(side)
end
