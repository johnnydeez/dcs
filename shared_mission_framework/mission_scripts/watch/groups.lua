-- Watch: groups and units now, as DCS has them: alive or not, in the air or not. Worked out
-- when asked; nothing kept. Actors and Inform ask through record\groups.lua.

WatchGroups = {}

-- The group `name` while it exists with at least one live unit (life above 0), else nil.
-- A DCS object, for Watch's own use (the flight situations); others ask RecordGroups.alive.
function WatchGroups.live(name)
    local g = Group.getByName(name)
    local ok, live = pcall(function()
        if not (g and g:isExist()) then return false end
        for _, u in ipairs(g:getUnits() or {}) do
            if u:isExist() and u:getLife() > 0 then return true end
        end
        return false
    end)
    return ok and live and g or nil
end

-- Whether the unit or static object `name` exists with life of at least 1.
function WatchGroups.liveUnit(name)
    local o = Unit.getByName(name) or StaticObject.getByName(name)
    local ok, live = pcall(function() return o and o:isExist() and o:getLife() >= 1 end)
    return ok and live == true
end

-- Whether the unit `name` exists.
function WatchGroups.unitExists(name)
    local u = Unit.getByName(name)
    local ok, exists = pcall(function() return u and u:isExist() end)
    return ok and exists == true
end

-- The names of group `name`'s live units (life above 0), in DCS's order.
function WatchGroups.liveUnitNames(name)
    local names = {}
    local g = Group.getByName(name)
    pcall(function()
        for _, u in ipairs(g:getUnits() or {}) do
            if u:isExist() and u:getLife() > 0 then names[#names + 1] = u:getName() end
        end
    end)
    return names
end

-- The first live jet of group `name` in the air (exists and in the air), as
-- { name, type, point { x, y, z }, velocity { x, y, z } }, or nil.
function WatchGroups.airborneLead(name)
    local g = Group.getByName(name)
    local ok, units = pcall(function() return g and g:getUnits() end)
    for _, u in ipairs(ok and units or {}) do
        local okAir, air = pcall(function() return u:isExist() and u:inAir() end)
        if okAir and air then
            local okRead, p, v, t, n = pcall(function() return u:getPoint(), u:getVelocity(), u:getTypeName(), u:getName() end)
            if not okRead then return nil end
            return { name = n, type = t, point = { x = p.x, y = p.y, z = p.z }, velocity = { x = v.x, y = v.y, z = v.z } }
        end
    end
    return nil
end

-- Where unit `name` is: { x, y, z }, or nil.
function WatchGroups.unitPoint(name)
    local u = Unit.getByName(name)
    local ok, p = pcall(function() return u:getPoint() end)
    return ok and p and { x = p.x, y = p.y, z = p.z } or nil
end

-- Where the first unit of group `name` is: { x, y, z }, or nil.
function WatchGroups.firstUnitPoint(name)
    local g = Group.getByName(name)
    local ok, p = pcall(function() return g:getUnits()[1]:getPoint() end)
    return ok and p and { x = p.x, y = p.y, z = p.z } or nil
end

-- The type of every unit of group `name`, in DCS's order (empty when it isn't there).
function WatchGroups.unitTypes(name)
    local types = {}
    local g = Group.getByName(name)
    pcall(function()
        for _, u in ipairs(g:getUnits() or {}) do types[#types + 1] = u:getTypeName() end
    end)
    return types
end

-- How many jets of group `name` are in the air now, and how many exist.
function WatchGroups.jetsUp(name)
    local g = Group.getByName(name)
    if not g then return 0, 0 end
    local ok, units = pcall(function() return g:getUnits() end)
    if not ok or not units then return 0, 0 end
    local up, alive = 0, 0
    for _, u in ipairs(units) do
        local okAir, air = pcall(function() return u:isExist() and u:inAir() end)
        if okAir and air then up = up + 1 end
        local okLive, live = pcall(function() return u:isExist() end)
        if okLive and live then alive = alive + 1 end
    end
    return up, alive
end

-- Every unit of group `name` (DCS's order, alive or not) as { name, point } (point nil
-- when DCS gives none); empty when the group isn't there.
function WatchGroups.units(name)
    local out = {}
    local g = Group.getByName(name)
    local ok, units = pcall(function() return g and g:getUnits() end)
    for _, u in ipairs(ok and units or {}) do
        local okN, n = pcall(function() return u:getName() end)
        local okP, p = pcall(function() return u:getPoint() end)
        out[#out + 1] = { name = okN and n or nil, point = okP and p and { x = p.x, y = p.y, z = p.z } or nil }
    end
    return out
end

-- Whether DCS knows group `name`.
function WatchGroups.exists(name)
    return Group.getByName(name) ~= nil
end

-- How many units group `name` has (getSize), 0 when it isn't there.
function WatchGroups.size(name)
    local g = Group.getByName(name)
    local ok, n = pcall(function() return g and g:isExist() and g:getSize() end)
    return ok and n or 0
end

-- Whether group `name` exists with a DCS controller.
function WatchGroups.hasController(name)
    local g = Group.getByName(name)
    local ok, c = pcall(function() return g and g:isExist() and g:getController() end)
    return ok and c and true or false
end

-- Whether any unit of group `name` is in the air.
function WatchGroups.inAir(name)
    local g = Group.getByName(name)
    local ok, air = pcall(function()
        if not (g and g:isExist()) then return false end
        for _, u in ipairs(g:getUnits() or {}) do
            if u:inAir() then return true end
        end
        return false
    end)
    return ok and air
end
