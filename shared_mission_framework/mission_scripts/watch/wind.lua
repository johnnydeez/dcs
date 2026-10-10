-- Watch: the wind at a point now (atmosphere.getWind), as { x, z } in metres per second,
-- the way the air moves; nil when DCS can't say. Read through record\wind.lua.

WatchWind = {}

function WatchWind.at(point)
    local ok, v = pcall(atmosphere.getWind, point)
    if ok and v then return { x = v.x, z = v.z } end
    return nil
end
