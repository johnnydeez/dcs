-- Watch: the enemy aircraft the sleeping base defenses wake for: every airplane and
-- helicopter of a coalition's enemy, where it is now. Worked out when asked; read through
-- record\enemy_aircraft_near_bases.lua by the controller's wake rule
-- (controller\wake_ground_units.lua), which measures them against its bases.

WatchEnemyAircraftNearBases = {}

local SIDE = { red = 1, blue = 2 }
local ENEMY = { red = "blue", blue = "red" }

local function safe(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

-- Every aircraft of `coalitionName`'s enemy: { pos { x, z }, name, who ("MSN7023_1 (Su-34)") }.
function WatchEnemyAircraftNearBases.enemyAircraft(coalitionName)
    local list = {}
    for _, category in ipairs({ Group.Category.AIRPLANE, Group.Category.HELICOPTER }) do
        for _, g in ipairs(coalition.getGroups(SIDE[ENEMY[coalitionName]], category) or {}) do
            for _, u in ipairs(safe(function() return g:getUnits() end) or {}) do
                local p = safe(function() return u:isExist() and u:getPoint() end)
                if p then
                    list[#list + 1] = { pos = { x = p.x, z = p.z }, name = u:getName(),
                                        who = string.format("%s (%s)", u:getName(), u:getTypeName()) }
                end
            end
        end
    end
    return list
end
