-- Watch: AI jets around the airfields, as plain fields: on the ground or in the air, where,
-- how fast, which way the nose points. Worked out when asked; read through
-- record\airfield_traffic.lua by the airfield calls (inform\radio\airfield_calls.lua), which
-- make each field's traffic calls from it (and later the comms menu's traffic list,
-- roadmap.md item 15).

WatchAirfieldTraffic = {}

local function norm(deg) return (deg % 360 + 360) % 360 end

-- Every unit of group `group`, in DCS's order: { name, exists, airborne, point { x, y, z },
-- velocity { x, y, z }, nose_deg (grid heading of its nose: on the ground its velocity may
-- be ~0) }; a field DCS doesn't give is nil.
function WatchAirfieldTraffic.jets(group)
    local g = Group.getByName(group)
    local ok, list = pcall(function() return g and g:getUnits() end)
    local out = {}
    for _, u in ipairs(ok and list or {}) do
        local j = {}
        local okName, name = pcall(function() return u:getName() end)
        j.name = okName and name or nil
        local okE, exists = pcall(function() return u:isExist() end)
        j.exists = okE and exists == true
        local okAir, air = pcall(function() return u:isExist() and u:inAir() end)
        j.airborne = okAir and air == true
        local okP, p = pcall(function() return u:getPoint() end)
        if okP and p then j.point = { x = p.x, y = p.y, z = p.z } end
        local okV, v = pcall(function() return u:getVelocity() end)
        if okV and v then j.velocity = { x = v.x, y = v.y, z = v.z } end
        local okO, o = pcall(function() return u:getPosition() end)
        if okO and o then j.nose_deg = norm(math.deg(math.atan2(o.x.z, o.x.x))) end
        out[#out + 1] = j
    end
    return out
end
