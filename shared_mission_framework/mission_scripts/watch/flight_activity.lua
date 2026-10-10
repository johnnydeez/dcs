-- Watch: what an AI flight's jets are doing now, as plain fields: which are in the air,
-- where, heading which way, fuel and weapons aboard. Worked out when asked; read through
-- record\flight_activity.lua by the flight calls and the airfield calls (inform\radio\),
-- which make the radio calls from it.

WatchFlightActivity = {}

local function weaponsAboard(u)
    local n = 0
    local ok, ammo = pcall(function() return u:getAmmo() end)
    for _, a in ipairs(ok and ammo or {}) do
        if a.desc and a.desc.category ~= Weapon.Category.SHELL then n = n + (a.count or 0) end
    end
    return n
end

local function state(u)
    local s = {}
    local okName, name = pcall(function() return u:getName() end)
    s.name = okName and type(name) == "string" and name or nil
    local okE, exists = pcall(function() return u:isExist() end)
    s.exists = okE and exists == true
    local okAir, air = pcall(function() return u:isExist() and u:inAir() end)
    s.airborne = okAir and air == true
    local okP, p = pcall(function() return u:getPoint() end)
    if okP and p then s.point = { x = p.x, y = p.y, z = p.z } end
    local okV, v = pcall(function() return u:getVelocity() end)
    if okV and v then s.velocity = { x = v.x, y = v.y, z = v.z } end
    local okF, fuel = pcall(function() return u:getFuel() end)
    if okF then s.fuel = fuel end
    s.weapons = weaponsAboard(u)
    return s
end

-- The jets of group `name` alive and in the air, lead first (DCS's order):
-- { { name, exists, airborne, point, velocity, fuel, weapons (aboard, guns aside) } }.
function WatchFlightActivity.airborneJets(name)
    local out = {}
    local g = Group.getByName(name)
    local ok, units = pcall(function() return g and g:getUnits() end)
    for _, u in ipairs(ok and units or {}) do
        local okAir, air = pcall(function() return u:isExist() and u:inAir() end)
        if okAir and air then out[#out + 1] = state(u) end
    end
    return out
end

-- Jet `unitName` now (the fields above), or nil when DCS doesn't know it.
function WatchFlightActivity.jet(unitName)
    local u = Unit.getByName(unitName)
    return u and state(u) or nil
end

-- Where the first jet of group `name` still there (in the air or not) is: { x, y, z }, or nil.
function WatchFlightActivity.firstAlivePoint(name)
    local g = Group.getByName(name)
    local ok, units = pcall(function() return g and g:getUnits() end)
    for _, u in ipairs(ok and units or {}) do
        local okE, e = pcall(function() return u:isExist() end)
        if okE and e then
            local okP, p = pcall(function() return u:getPoint() end)
            return okP and p and { x = p.x, y = p.y, z = p.z } or nil
        end
    end
    return nil
end
