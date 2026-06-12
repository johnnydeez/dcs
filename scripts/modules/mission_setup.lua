-- Mission Setup: generates a randomized set of missions for the session.
-- Each mission is a type + location pair with air threat and battle size.
-- Draws orange circles (13.5 km radius) and labels on the F10 map.
-- Mark IDs 3000–3999 reserved for missions (coalition=1000-1999, convoy=2000-2999).

MissionSetup = {}

local MISSION_TYPES = {
    "BLUE Defend",
    "BLUE Attack",
    "Search and Destroy",
}

local LOCATION_TYPES = {
    "Airfield",
    "Town",
    "Road",
}

local AIR_THREATS  = { "Low", "Medium", "High" }
local BATTLE_SIZES = { "Small", "Medium", "Large" }

-- Which side's bases are valid for each mission type.
local SIDE_REQUIRED = {
    ["BLUE Defend"]        = coalition.side.BLUE,
    ["BLUE Attack"]        = coalition.side.RED,
    ["Search and Destroy"] = coalition.side.RED,
}

-- Stub town table — expand in a later pass.
-- lat/lon stored for future unit spawning; used here to place F10 markers.
local TOWNS = {
    { name = "Homs",   lat = 34.730, lon = 36.710 },
    { name = "Raqqa",  lat = 35.952, lon = 39.005 },
    { name = "Tartus", lat = 34.893, lon = 35.887 },
}

local MISSION_COUNT  = 3
local MISSION_RADIUS = 13500  -- half of convoy circle (27 000 m)

local ROAD_MIN_DIST = 27780   -- 15 nm in metres
local ROAD_MAX_DIST = 111120  -- 60 nm in metres

-- Orange: distinct from blue/red territory circles and green convoy circles.
local MISSION_LINE = { 1, 0.55, 0, 1   }
local MISSION_FILL = { 1, 0.55, 0, 0.2 }

local _markId = 3000

local function pick(tbl)
    return tbl[math.random(#tbl)]
end

local function buildBasePool(mtype, assignments)
    local requiredSide = SIDE_REQUIRED[mtype]
    local pool = {}
    for _, a in ipairs(assignments) do
        if a.side == requiredSide then
            table.insert(pool, a.name)
        end
    end
    return pool
end

-- Returns name (string) and Vec3 position, or nil on failure.
local function resolveLocation(mtype, ltype, assignments)
    if ltype == "Town" then
        local town = pick(TOWNS)
        local pos  = coord.LLtoLO(town.lat, town.lon, 0)
        return town.name, pos
    end

    local pool = buildBasePool(mtype, assignments)
    if #pool == 0 then
        Log.warn("Mission generator: no valid bases for '" .. mtype .. "'")
        return nil, nil
    end

    local name = pool[math.random(#pool)]
    local ab   = Airbase.getByName(name)
    if not ab then
        Log.warn("Mission generator: airbase not found '" .. name .. "'")
        return nil, nil
    end

    local basePos = ab:getPoint()

    if ltype == "Road" then
        -- Pick a road-snapped point 15–60 nm from the base.
        -- Spawner.nearPos returns {x=north, y=east, alt=h}; convert to Vec3.
        local rp  = Spawner.nearPos(basePos, ROAD_MIN_DIST, ROAD_MAX_DIST, true)
        local pos = { x = rp.x, y = rp.alt, z = rp.y }
        return name, pos
    end

    return name, basePos
end

local function formatLocation(ltype, name)
    if ltype == "Road" then return "Road near " .. name end
    return ltype .. ": " .. name
end

function MissionSetup.generate(assignments)
    Log.info("--- Mission Generation Start ---")

    local used     = {}
    local missions = {}
    local attempts = 0

    while #missions < MISSION_COUNT do
        attempts = attempts + 1
        if attempts > 100 then
            Log.warn("Mission generator: exceeded attempt limit, stopping early")
            break
        end

        local mtype     = pick(MISSION_TYPES)
        local ltype     = pick(LOCATION_TYPES)
        local name, pos = resolveLocation(mtype, ltype, assignments)

        if name and pos then
            -- Deduplicate on location name only — no two missions at the same place.
            if not used[name] then
                used[name] = true
                table.insert(missions, {
                    mtype  = mtype,
                    ltype  = ltype,
                    name   = name,
                    pos    = pos,
                    threat = pick(AIR_THREATS),
                    size   = pick(BATTLE_SIZES),
                })
            end
        end
    end

    -- Draw F10 map circles and labels.
    for i, m in ipairs(missions) do
        trigger.action.circleToAll(-1, _markId, m.pos, MISSION_RADIUS, MISSION_LINE, MISSION_FILL, 1, true, "")
        _markId = _markId + 1
        trigger.action.markToAll(_markId, string.format("M%d: %s", i, m.mtype), m.pos, true, "")
        _markId = _markId + 1
    end

    -- Screen summary.
    local lines = { "=== MISSIONS ===" }
    for i, m in ipairs(missions) do
        local line = string.format("%d. %s / %s  [Air: %s | Size: %s]",
            i, m.mtype, formatLocation(m.ltype, m.name), m.threat, m.size)
        local gps  = "   GPS: " .. Spawner.formatLL(m.pos)
        table.insert(lines, line)
        table.insert(lines, gps)
        Log.info("  " .. line)
        Log.info("  " .. gps)
    end

    trigger.action.outText(table.concat(lines, "\n"), 180)
    Log.info("--- Mission Generation Complete ---")
end
