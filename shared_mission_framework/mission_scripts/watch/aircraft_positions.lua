-- Watch: every airborne aircraft of a coalition now, as plain fields, for the event log's
-- POSITION lines (logs\event_log.lua, every EVENT_LOG.position_every_s). Worked out when
-- asked; read through record\aircraft_positions.lua.

WatchAircraftPositions = {}

local function safe(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

-- Every airplane, then every helicopter, of coalition `side` (coalition.side) in the air,
-- in DCS's order: { group, name, type, coalition, player, point { x, y, z },
-- velocity { x, y, z }, fuel (fraction of internal fuel) }.
function WatchAircraftPositions.list(side)
    local out = {}
    for _, category in ipairs({ Group.Category.AIRPLANE, Group.Category.HELICOPTER }) do
        for _, g in ipairs(coalition.getGroups(side, category) or {}) do
            local group = safe(function() return g:getName() end)
            for _, u in ipairs(safe(function() return g:getUnits() end) or {}) do
                if safe(function() return u:inAir() end) then
                    local p, v = safe(function() return u:getPoint() end), safe(function() return u:getVelocity() end)
                    out[#out + 1] = { group = group, name = safe(function() return u:getName() end),
                                      type = safe(function() return u:getTypeName() end), coalition = side,
                                      player = safe(function() return u.getPlayerName and u:getPlayerName() end),
                                      point = p and { x = p.x, y = p.y, z = p.z },
                                      velocity = v and { x = v.x, y = v.y, z = v.z },
                                      fuel = safe(function() return u:getFuel() end) }
                end
            end
        end
    end
    return out
end
