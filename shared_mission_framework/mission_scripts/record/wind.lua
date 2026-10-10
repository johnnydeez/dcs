-- The record of the wind at a point now. One writer: watch\wind.lua, worked out when read
-- (rule 11).

RecordWind = {}

-- The wind at `point` ({ x, y, z }) as { x, z } in metres per second, or nil.
function RecordWind.at(point)
    return WatchWind.at(point)
end
