-- Spawns randomized ground convoys at mission start.
--
-- ConvoySetup.spawn(clusterSides, assignments)
--
-- Currently spawns one supply convoy traveling between two Red airbases.
-- mechanized-convoy and armor-convoy are stubbed for future implementation.

ConvoySetup = {}

local _markId = 2000  -- convoy mark IDs start here (coalition marks use 1000–1999)

-- ============================================================
-- CONVOY TYPE DEFINITIONS
-- ============================================================
-- Each slot: { name, types, minCount, maxCount, skill }
-- 'types' is a list — one is chosen at random per unit spawned.
-- Unit type strings marked [unconfirmed] may silently spawn Leopard-2s;
-- verify in dcs.log after first run (woCar: Unit X is unknown).

local CONVOY_TYPES = {
    ["supply-convoy"] = {
        { name = "Cargo",   types = { "Ural-4320-31", "KAMAZ Truck", "GAZ-3308" }, minCount = 4, maxCount = 12, skill = "Average" }, -- KAMAZ/GAZ [unconfirmed]
        { name = "Fuel",    types = { "ATZ-5", "ATZ-10" },                           minCount = 1, maxCount = 3,  skill = "Average" },
        { name = "Command", types = { "Ural-375 PBU" },                             minCount = 0, maxCount = 2,  skill = "Average" },
        { name = "BTR",     types = { "BTR-80" },                                   minCount = 1, maxCount = 2,  skill = "Average" },
        { name = "ZU23",    types = { "Ural-375 ZU-23" },                           minCount = 0, maxCount = 2,  skill = "Average" },
    },
    ["mechanized-convoy"] = nil,  -- stub: not yet implemented
    ["armor-convoy"]      = nil,  -- stub: not yet implemented
}

local CONVOY_SPEED = 13.9  -- m/s (~50 km/h)

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

local function formatLL(vec3)
    local lat, lon = coord.LOtoLL(vec3)
    local function dms(deg)
        local d = math.floor(math.abs(deg))
        local m = math.floor((math.abs(deg) - d) * 60)
        local s = math.floor(((math.abs(deg) - d) * 60 - m) * 60)
        return d, m, s
    end
    local latD, latM, latS = dms(lat)
    local lonD, lonM, lonS = dms(lon)
    local latH = lat >= 0 and "N" or "S"
    local lonH = lon >= 0 and "E" or "W"
    return string.format("%s%d°%02d'%02d\"  %s%d°%02d'%02d\"", latH, latD, latM, latS, lonH, lonD, lonM, lonS)
end

-- Returns bearing in degrees (0=N, 90=E, clockwise) from 2D pos a to b.
-- Positions use spawner convention: {x = DCS north-south, y = DCS east-west}.
-- atan2(east_diff, north_diff) gives compass bearing from North.
local function bearingDeg(a, b)
    local deg = math.atan2(b.y - a.y, b.x - a.x) * 180 / math.pi
    if deg < 0 then deg = deg + 360 end
    return deg
end

local function bearingToDir(deg)
    local dirs = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
    return dirs[math.floor((deg + 22.5) / 45) % 8 + 1]
end

local function dist2d(a, b)
    local dx = b.x - a.x
    local dy = b.y - a.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Estimates convoy position after 'minutes' of travel along start→mid→end.
-- Returns a DCS Vec3 suitable for circleToAll.
local function estimatedPos(startPos, midPos, endPos, minutes)
    local travelDist = CONVOY_SPEED * minutes * 60
    local seg1 = dist2d(startPos, midPos)
    local a, b, t
    if travelDist <= seg1 then
        a, b, t = startPos, midPos, travelDist / seg1
    else
        local seg2 = dist2d(midPos, endPos)
        a, b, t = midPos, endPos, math.min((travelDist - seg1) / seg2, 1.0)
    end
    local ex = a.x + t * (b.x - a.x)
    local ey = a.y + t * (b.y - a.y)
    return { x = ex, y = land.getHeight({ x = ex, y = ey }), z = ey }
end

-- Snaps to nearest road; returns {x, y, alt} in spawner coordinate convention.
local function snapToRoad(x, y)
    local rx, ry = land.getClosestPointOnRoads("roads", x, y)
    if rx then
        return { x = rx, y = ry, alt = land.getHeight({ x = rx, y = ry }) }
    end
    Log.debug("ConvoySetup: no road found near (" .. x .. ", " .. y .. "), using raw position")
    return { x = x, y = y, alt = land.getHeight({ x = x, y = y }) }
end

-- Builds a flat list of {type, skill} unit definitions from a convoy type definition.
local function buildUnitList(typeName)
    local slots = CONVOY_TYPES[typeName]
    if not slots then
        Log.warn("ConvoySetup: unknown or unimplemented convoy type '" .. tostring(typeName) .. "'")
        return nil
    end
    local units = {}
    for _, slot in ipairs(slots) do
        local n = math.random(slot.minCount, slot.maxCount)
        for _ = 1, n do
            table.insert(units, { type = slot.types[math.random(#slot.types)], skill = slot.skill })
        end
    end
    return units
end

-- Spawns a ground group with a 3-point road route: start → mid → end.
-- All units spawn at the same road point; DCS columns them up as they move.
local function spawnConvoyGroup(groupName, startPos, midPos, endPos, unitDefs)
    local dx = midPos.x - startPos.x
    local dy = midPos.y - startPos.y
    local heading = math.atan2(dx, dy)
    if heading < 0 then heading = heading + 2 * math.pi end

    local units = {}
    for i, def in ipairs(unitDefs) do
        local angle  = math.random() * 2 * math.pi
        local radius = math.random() * 40
        local ux = startPos.x + radius * math.cos(angle)
        local uy = startPos.y + radius * math.sin(angle)
        units[i] = {
            name           = groupName .. "_" .. i,
            type           = def.type,
            skill          = def.skill or "Average",
            x              = ux,
            y              = uy,
            alt            = land.getHeight({ x = ux, y = uy }),
            heading        = heading,
            playerCanDrive = false,
        }
    end

    local function wp(pos)
        return {
            x            = pos.x,
            y            = pos.y,
            alt          = pos.alt,
            type         = "Turning Point",
            action       = "On Road",
            speed        = CONVOY_SPEED,
            speed_locked = true,
            ETA          = 0,
            ETA_locked   = false,
        }
    end

    local grp = coalition.addGroup(country.id.CJTF_RED, Group.Category.GROUND, {
        name  = groupName,
        task  = "Ground Nothing",
        x     = startPos.x,
        y     = startPos.y,
        units = units,
        route = { points = { wp(startPos), wp(midPos), wp(endPos) } },
    })

    if grp then
        Log.info("ConvoySetup: spawned '" .. groupName .. "' (" .. #units .. " units)")
    else
        Log.warn("ConvoySetup: coalition.addGroup returned nil for '" .. groupName .. "'")
    end
    return grp
end

-- ============================================================
-- PUBLIC API
-- ============================================================

-- clusterSides : cluster.id → coalition.side  (from CoalitionSetup.assign())
-- assignments  : list of { name, side }        (from CoalitionSetup.assign())
function ConvoySetup.spawn(clusterSides, assignments)
    Log.info("--- Convoy Spawn Start ---")

    -- Collect all Red airbases with their 2D positions
    local redBases = {}
    for _, a in ipairs(assignments or {}) do
        if a.side == coalition.side.RED then
            local ab = Airbase.getByName(a.name)
            if ab then
                local pt = ab:getPoint()
                table.insert(redBases, { name = a.name, pos2d = { x = pt.x, y = pt.z } })
            end
        end
    end

    if #redBases < 2 then
        Log.warn("ConvoySetup: need at least 2 Red airbases, found " .. #redBases .. " — skipping convoy")
        trigger.action.outText("=== CONVOY ===\n  (insufficient Red territory — convoy skipped)", 180)
        return
    end

    -- Pick a random start, then use the furthest Red base as destination
    local startBase = redBases[math.random(#redBases)]
    local endBase, maxD = nil, 0
    for _, b in ipairs(redBases) do
        if b.name ~= startBase.name then
            local d = dist2d(startBase.pos2d, b.pos2d)
            if d > maxD then maxD = d; endBase = b end
        end
    end

    Log.info(string.format("  Route: %s → %s  (%.0f m)", startBase.name, endBase.name, maxD))

    -- Offset the spawn snap point 2 km toward the destination so we catch
    -- the road on the departure side of the airbase, not the far side.
    local dx = endBase.pos2d.x - startBase.pos2d.x
    local dy = endBase.pos2d.y - startBase.pos2d.y
    local len = math.sqrt(dx * dx + dy * dy)
    local nx = len > 0 and (dx / len) or 0
    local ny = len > 0 and (dy / len) or 0
    local startPos = snapToRoad(startBase.pos2d.x + nx * 2000, startBase.pos2d.y + ny * 2000)
    local endPos   = snapToRoad(endBase.pos2d.x,   endBase.pos2d.y)
    local midPos   = snapToRoad(
        (startPos.x + endPos.x) / 2,
        (startPos.y + endPos.y) / 2
    )

    local unitDefs = buildUnitList("supply-convoy")
    if not unitDefs or #unitDefs == 0 then
        Log.warn("ConvoySetup: empty unit list — skipping convoy")
        return
    end

    local grp = spawnConvoyGroup("CONVOY_Supply_1", startPos, midPos, endPos, unitDefs)

    -- Green circle centered on estimated convoy position after 35-min cold start (~27 km radius)
    if grp then
        local GREEN_LINE = { 0, 0.85, 0, 0.9 }
        local GREEN_FILL = { 0, 0.85, 0, 0.1 }
        local circleCenter = estimatedPos(startPos, midPos, endPos, 35)
        trigger.action.circleToAll(-1, _markId, circleCenter, 27000, GREEN_LINE, GREEN_FILL, 1, true, "")
        _markId = _markId + 1
        trigger.action.markToAll(_markId, "Supply Convoy", circleCenter, true, "")
        _markId = _markId + 1
    end

    -- Screen summary
    local lines = { "=== CONVOY DETECTED ===" }
    if grp then
        local ll     = formatLL(grp:getUnit(1):getPoint())
        local brg    = bearingDeg(startBase.pos2d, endBase.pos2d)
        local dir    = bearingToDir(brg)
        local distMi = math.floor(maxD / 1609.34 + 0.5)
        table.insert(lines, string.format("  Supply convoy  (%d vehicles)", #unitDefs))
        table.insert(lines, string.format("  %s → %s", startBase.name, endBase.name))
        table.insert(lines, string.format("  Heading %s  (~%d mi route)", dir, distMi))
        table.insert(lines, "  GPS: " .. ll)
    else
        table.insert(lines, "  (spawn failed — check dcs.log)")
    end
    trigger.action.outText(table.concat(lines, "\n"), 180)

    Log.info("--- Convoy Spawn Complete ---")
end
