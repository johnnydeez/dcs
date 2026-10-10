-- Watch: the airbases now, as DCS reports them: who holds each, and which ramp spots are
-- free. Worked out when asked (record\airbases.lua reads it); nothing kept.

WatchAirbases = {}

-- The ramp spots DCS reports free at `base` now, in DCS's order:
-- { { terminal_index, terminal_type, x, z, distance_to_runway_m } }, or nil when the base
-- isn't there or DCS gives no list.
function WatchAirbases.freeSpots(base)
    local ab = Airbase.getByName(base)
    if not ab then return nil end
    local ok, list = pcall(function() return ab:getParking(true) end)
    if not ok or type(list) ~= "table" then return nil end
    local spots = {}
    for _, s in ipairs(list) do
        spots[#spots + 1] = { terminal_index = s.Term_Index, terminal_type = s.Term_Type,
                              x = s.vTerminalPos.x, z = s.vTerminalPos.z, distance_to_runway_m = s.fDistToRW }
    end
    return spots
end

-- Where DCS puts airbase `base` (its getPoint: { x, y (elevation), z }), or nil.
function WatchAirbases.point(base)
    local ab = Airbase.getByName(base)
    local ok, p = pcall(function() return ab:getPoint() end)
    return ok and p and { x = p.x, y = p.y, z = p.z } or nil
end

-- DCS's id of airbase `base`, or nil.
function WatchAirbases.id(base)
    local ok, id = pcall(function() return Airbase.getByName(base):getID() end)
    return ok and id or nil
end

-- The coalition holding `base` now (coalition.side), or nil when it can't be read.
function WatchAirbases.holder(base)
    local ab = Airbase.getByName(base)
    local ok, side = pcall(function() return ab and ab:getCoalition() end)
    return ok and side or nil
end
