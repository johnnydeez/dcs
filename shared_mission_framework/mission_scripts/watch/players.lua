-- Watch: the players now, as DCS has them, each as plain fields. Worked out when asked
-- (record\players.lua reads it): the air picture, the radio calls, the comms menus and the
-- airfield calls ask through the Record.

WatchPlayers = {}

local function read(o, method)
    local ok, v = pcall(function() return o[method](o) end)
    return ok and v or nil
end

-- The players of coalition `side` (coalition.side) now, in DCS's order:
-- { exists, unit (name), group (name), group_id, player (name), callsign (the jet's, from
--   the mission file: "Python11"), type, point { x, y, z }, airborne }; a field DCS
-- doesn't give is nil.
function WatchPlayers.list(side)
    local out = {}
    for _, u in ipairs(coalition.getPlayers(side) or {}) do
        local p = { exists = read(u, "isExist") == true, unit = read(u, "getName"), player = read(u, "getPlayerName"),
                    callsign = read(u, "getCallsign"), type = read(u, "getTypeName"), airborne = read(u, "inAir") == true }
        local g = read(u, "getGroup")
        if g then p.group, p.group_id = read(g, "getName"), read(g, "getID") end
        local point = read(u, "getPoint")
        if point then p.point = { x = point.x, y = point.y, z = point.z } end
        out[#out + 1] = p
    end
    return out
end
