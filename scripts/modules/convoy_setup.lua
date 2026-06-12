-- Spawns randomized ground convoys at mission start.
--
-- ConvoySetup.spawn(clusterSides, assignments)
--
-- Spawns one supply convoy, one mechanized convoy, and one armor convoy each session.
-- Each convoy gets a different start base (shuffled), routing to its furthest Red base.
-- Skill level is randomized per convoy from Average / Good / High.

ConvoySetup = {}

local _markId = 2000  -- convoy mark IDs start here (coalition marks use 1000–1999)

-- ============================================================
-- CONVOY TYPE DEFINITIONS
-- ============================================================
-- Each slot: { name, types, minCount, maxCount }
-- 'types' is a list — one is chosen at random per unit spawned.
-- Skill is assigned per convoy at spawn time (see randomSkill).
-- Type strings marked [unconfirmed] need verification via dumpLateGroupUnits.

local CONVOY_TYPES = {
    ["supply-convoy"] = {
        { name = "Cargo",   types = { "Ural-4320-31", "KAMAZ Truck", "GAZ-3308" }, minCount = 4, maxCount = 12 },  -- KAMAZ/GAZ [unconfirmed; no woCar seen but not yet in debug groups]
        { name = "Fuel",    types = { "ATZ-5", "ATZ-10" },                          minCount = 1, maxCount = 3  },
        { name = "Command", types = { "Ural-375 PBU" },                             minCount = 0, maxCount = 2  },
        { name = "BTR",     types = { "BTR-80" },                                   minCount = 1, maxCount = 2  },
        { name = "ZU23",    types = { "Ural-375 ZU-23" },                           minCount = 0, maxCount = 2  },
    },
    ["mechanized-convoy"] = {
        { name = "APC",    types = { "BTR-70", "BTR-80" }, minCount = 3, maxCount = 8 },
        { name = "Tank",   types = { "T-55", "T-72B" },                minCount = 2, maxCount = 4 },
        { name = "SA13",   types = { "Strela-10M3" },                  minCount = 0, maxCount = 2 },
        { name = "Truck",  types = { "Ural-4320-31" },                 minCount = 2, maxCount = 6 },
        { name = "Shilka", types = { "ZSU-23-4 Shilka" },             minCount = 0, maxCount = 2 },
    },
    ["armor-convoy"] = {
        { name = "Tank",   types = { "T-55", "T-72B" },       minCount = 4, maxCount = 8 },
        { name = "T64",    types = { "CHAP_T64BV" },           minCount = 1, maxCount = 2 },
        { name = "MRAP",   types = { "CHAP_MATV" },            minCount = 1, maxCount = 3 },
        { name = "SA13",   types = { "Strela-10M3" },         minCount = 1, maxCount = 2 },
        { name = "Shilka", types = { "ZSU-23-4 Shilka" },    minCount = 1, maxCount = 1 },
        { name = "Truck",  types = { "Ural-4320-31" },        minCount = 2, maxCount = 4 },
        { name = "BMP3",   types = { "BMP-3" },               minCount = 0, maxCount = 2 },
        { name = "BMP2",   types = { "BMP-2" },               minCount = 1, maxCount = 3 },
    },
}

local CONVOY_SPEED    = 13.9    -- m/s (~50 km/h)
local MAX_ROUTE_DIST  = 175000  -- meters; prevents cross-map routes with no viable roads
local SKILLS = { "Average", "Good", "High" }

-- Bases that are on islands with no road connection to the mainland.
-- Convoys starting here must stay on the same landmass.
-- Gecitkale (Northern Cyprus) is the only one that can go Red — it sits inside
-- the TURKEY cluster. Southern Cyprus bases are fixed Blue and never Red.
local ISLAND_BASES = {
    ["Gecitkale"] = true,
    ["Ercan"]     = true,
    ["Gazipasa"]  = true,  -- not an island, but excluded due to convoy routing issues (units get stuck)
}

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

local function randomSkill()
    return SKILLS[math.random(#SKILLS)]
end

-- Returns bearing in degrees (0=N, 90=E, clockwise) from 2D pos a to b.
-- Positions use spawner convention: {x = DCS north-south, y = DCS east-west}.
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
local function buildUnitList(typeName, skill)
    local slots = CONVOY_TYPES[typeName]
    if not slots then
        Log.warn("ConvoySetup: unknown convoy type '" .. tostring(typeName) .. "'")
        return nil
    end
    local units = {}
    for _, slot in ipairs(slots) do
        local n = math.random(slot.minCount, slot.maxCount)
        for _ = 1, n do
            table.insert(units, { type = slot.types[math.random(#slot.types)], skill = skill })
        end
    end
    return units
end

-- Spawns a ground group with a 3-point road route: start → mid → end.
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
        local snapped = snapToRoad(ux, uy)
        units[i] = {
            name           = groupName .. "_" .. i,
            type           = def.type,
            skill          = def.skill or "Average",
            x              = snapped.x,
            y              = snapped.y,
            alt            = snapped.alt,
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
        Log.warn("ConvoySetup: need at least 2 Red airbases — skipping all convoys")
        trigger.action.outText("=== CONVOYS ===\n  (insufficient Red territory — convoys skipped)", 300)
        return
    end

    -- Shuffle for route diversity so each convoy type gets a different start base
    for i = #redBases, 2, -1 do
        local j = math.random(i)
        redBases[i], redBases[j] = redBases[j], redBases[i]
    end

    local configs = {
        { type = "supply-convoy",     groupName = "CONVOY_Supply_1",     label = "Supply Convoy" },
        { type = "mechanized-convoy", groupName = "CONVOY_Mechanized_1", label = "Mechanized Convoy" },
        { type = "armor-convoy",      groupName = "CONVOY_Armor_1",      label = "Armor Convoy" },
    }

    local GREEN_LINE = { 0, 0.85, 0, 0.9 }
    local GREEN_FILL = { 0, 0.85, 0, 0.1 }

    local lines = { "=== CONVOYS DETECTED ===" }

    for i, cfg in ipairs(configs) do
        local startBase = redBases[((i - 1) % #redBases) + 1]

        -- Route to the furthest Red base within MAX_ROUTE_DIST on the same landmass.
        -- Falls back to nearest base if none are within the cap.
        local startOnIsland = ISLAND_BASES[startBase.name] == true
        local endBase, maxD = nil, 0
        local fallback, fallbackD = nil, math.huge
        for _, b in ipairs(redBases) do
            local sameIsland = (ISLAND_BASES[b.name] == true) == startOnIsland
            if b.name ~= startBase.name and sameIsland then
                local d = dist2d(startBase.pos2d, b.pos2d)
                if d <= MAX_ROUTE_DIST and d > maxD then maxD = d; endBase = b end
                if d < fallbackD then fallbackD = d; fallback = b end
            end
        end
        if not endBase then
            endBase = fallback
            maxD    = fallbackD
            Log.info(string.format("  %s: no base within %.0f km of %s, using nearest (%s)", cfg.label, MAX_ROUTE_DIST / 1000, startBase.name, endBase and endBase.name or "none"))
        end

        if not endBase then
            Log.warn(string.format("ConvoySetup: %s — no second Red base on same landmass as %s, skipping", cfg.label, startBase.name))
            table.insert(lines, "  " .. cfg.label .. ": skipped (isolated start base)")
        else
            Log.info(string.format("  %s route: %s → %s  (%.0f m)", cfg.label, startBase.name, endBase.name, maxD))

            local dx  = endBase.pos2d.x - startBase.pos2d.x
            local dy  = endBase.pos2d.y - startBase.pos2d.y
            local len = math.sqrt(dx * dx + dy * dy)
            local nx  = len > 0 and (dx / len) or 0
            local ny  = len > 0 and (dy / len) or 0

            local startPos = snapToRoad(startBase.pos2d.x + nx * 2000, startBase.pos2d.y + ny * 2000)
            local endPos   = snapToRoad(endBase.pos2d.x, endBase.pos2d.y)
            local midPos   = snapToRoad((startPos.x + endPos.x) / 2, (startPos.y + endPos.y) / 2)

            local skill    = randomSkill()
            local unitDefs = buildUnitList(cfg.type, skill)

            if unitDefs and #unitDefs > 0 then
                local grp = spawnConvoyGroup(cfg.groupName, startPos, midPos, endPos, unitDefs)

                if grp then
                    local circleCenter = estimatedPos(startPos, midPos, endPos, 35)
                    trigger.action.circleToAll(-1, _markId, circleCenter, 27000, GREEN_LINE, GREEN_FILL, 1, true, "")
                    _markId = _markId + 1
                    trigger.action.markToAll(_markId, cfg.label, circleCenter, true, "")
                    _markId = _markId + 1

                    local ll     = Spawner.formatLL(grp:getUnit(1):getPoint())
                    local brg    = bearingDeg(startBase.pos2d, endBase.pos2d)
                    local dir    = bearingToDir(brg)
                    local distMi = math.floor(maxD / 1609.34 + 0.5)
                    table.insert(lines, string.format("  %s  (%d vehicles)", cfg.label, #unitDefs))
                    table.insert(lines, string.format("    %s → %s  |  Hdg %s  (~%d mi)", startBase.name, endBase.name, dir, distMi))
                    table.insert(lines, "    GPS: " .. ll)
                else
                    table.insert(lines, "  " .. cfg.label .. ": spawn failed — check dcs.log")
                end
            else
                Log.warn("ConvoySetup: empty unit list for " .. cfg.type)
                table.insert(lines, "  " .. cfg.label .. ": unit list empty — check dcs.log")
            end
        end
    end

    trigger.action.outText(table.concat(lines, "\n"), 300)
    Log.info("--- Convoy Spawn Complete ---")
end
