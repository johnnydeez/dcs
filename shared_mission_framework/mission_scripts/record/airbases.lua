-- The record of the airbases now: who holds each, and the ramp spots DCS reports free.
-- One writer: watch\airbases.lua, worked out when read (rule 11), so actors and Inform
-- never name a Watch module.

RecordAirbases = {}

-- { { terminal_index, terminal_type, x, z, distance_to_runway_m } } free at `base` now, or nil.
function RecordAirbases.freeSpots(base)
    return WatchAirbases.freeSpots(base)
end

-- Where DCS puts airbase `base`: { x, y (elevation), z }, or nil.
function RecordAirbases.point(base)
    return WatchAirbases.point(base)
end

-- DCS's id of airbase `base`, or nil.
function RecordAirbases.id(base)
    return WatchAirbases.id(base)
end

-- The coalition holding `base` now (coalition.side), or nil.
function RecordAirbases.holder(base)
    return WatchAirbases.holder(base)
end
