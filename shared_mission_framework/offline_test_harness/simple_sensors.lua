-- Offline test harness, test B level 2: what a group's sensors detect
-- (Controller:getDetectedTargets), simply, so the mission's radar picture, scrambles,
-- bandit calls and Darkstar have contacts to work with (shared_mission_framework framework_design.md,
-- *How the transfer is tested*). Loaded after stub_dcs_world.lua; SimpleSensors.install().
--
--   radar  (any detection kind but RWR) every enemy aircraft in the air within reach of one
--          of the group's units: a ground unit its type's detection range (UNIT_POOL
--          detection_m), an aircraft AWACS_REACH_M for an AWACS type, else AIRCRAFT_REACH_M;
--          type and range always known
--   RWR    every enemy ground unit with a radar whose detection range reaches one of the
--          group's units
-- No terrain masking, no jamming, no look-down limits. Listed in unit name order, so a run
-- repeats.

SimpleSensors = {}

local AWACS_REACH_M = 350000
local AIRCRAFT_REACH_M = 100000

local W = StubDcsWorld

local function poolEntry(typeName)
    for _, kind in ipairs({ "ground", "ship", "plane", "helicopter" }) do
        local e = UNIT_POOL and UNIT_POOL[kind] and UNIT_POOL[kind][typeName]
        if e then return e end
    end
    return nil
end

-- How far a unit's radar reaches, metres (0: none).
local function radarReach(u)
    local e = poolEntry(u.type)
    if u.category == Unit.Category.AIRPLANE or u.category == Unit.Category.HELICOPTER then
        return (e and e.role == "awacs") and AWACS_REACH_M or AIRCRAFT_REACH_M
    end
    return e and e.detection_m or 0
end

local function distance(a, b)
    local dx, dz = a.pos.x - b.pos.x, a.pos.z - b.pos.z
    return math.sqrt(dx * dx + dz * dz)
end

local function sortedUnits()
    local names = {}
    for name in pairs(W.units) do names[#names + 1] = name end
    table.sort(names)
    local out = {}
    for i, name in ipairs(names) do out[i] = W.units[name] end
    return out
end

local function wantsRwr(...)
    for _, kind in ipairs({ ... }) do
        if kind == Controller.Detection.RWR then return true end
    end
    return false
end

local function detect(group, ...)
    local found = {}
    if not group.alive then return found end
    local own = group.unit_list
    local rwr = wantsRwr(...)
    for _, other in ipairs(sortedUnits()) do
        if other.alive and other.group.coalition ~= group.coalition then
            local seen = false
            if rwr then
                local reach = other.has_radar and (other.category == Unit.Category.GROUND_UNIT
                    or other.category == Unit.Category.SHIP) and radarReach(other) or 0
                for _, u in ipairs(own) do
                    if reach > 0 and distance(u, other) <= reach then seen = true break end
                end
            elseif other.in_air and (other.category == Unit.Category.AIRPLANE or other.category == Unit.Category.HELICOPTER) then
                for _, u in ipairs(own) do
                    local reach = radarReach(u)
                    if reach > 0 and distance(u, other) <= reach then seen = true break end
                end
            end
            if seen then found[#found + 1] = { object = other, visible = false, type = true, distance = true } end
        end
    end
    return found
end

function SimpleSensors.install()
    W.detect = detect
end
