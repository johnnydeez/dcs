-- Watch: how many AI aircraft of a coalition are in the air now. Players don't count
-- (John, 2026-10-01: the airborne cap is for AI aircraft). Read through
-- record\airborne_aircraft.lua (the launch gate and the scrambles' cap).

WatchAirborneAircraft = {}

local SIDE = { red = 1, blue = 2 }   -- coalition.side

function WatchAirborneAircraft.count(c)
    local n = 0
    for _, g in ipairs(coalition.getGroups(SIDE[c], Group.Category.AIRPLANE) or {}) do
        for _, u in ipairs(g:getUnits() or {}) do
            local ok, air = pcall(function() return u:inAir() and not u:getPlayerName() end)
            if ok and air then n = n + 1 end
        end
    end
    return n
end
