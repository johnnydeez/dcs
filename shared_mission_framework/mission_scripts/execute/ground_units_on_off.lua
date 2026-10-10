-- Execute: ground groups' AI switched on or off (the sleeping base defenses). A sleeping
-- group has its AI off (Controller:setOnOff(false)), so it doesn't scan the sky; woken, it
-- gets alarm state red so it doesn't stay passive. The controller decides
-- (controller\wake_ground_units.lua); this acts at once.

ExecuteGroundUnitsOnOff = {}

local function controllerOf(groupName)
    local g = Group.getByName(groupName)
    local ok, c = pcall(function() return g and g:isExist() and g:getController() end)
    return ok and c or nil
end

-- Every group of `groupIds` on (awake, alarm state red) or off.
function ExecuteGroundUnitsOnOff.set(groupIds, awake)
    for _, id in ipairs(groupIds) do
        local c = controllerOf(id)
        if c then
            pcall(function()
                c:setOnOff(awake)
                if awake then
                    c:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
                end
            end)
        end
    end
end
