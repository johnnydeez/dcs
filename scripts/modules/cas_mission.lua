-- CAS Mission Setup: semi-preplanned missions with late-activation and/or dynamic spawns.
-- Mark IDs 3100–3199 reserved for CAS missions.
--
-- Mission definition fields:
--   name       string   internal identifier, used for group name prefixes
--   label      string   F10 menu display name
--   mtype      string   "blue_defending" | "red_defending"
--   pos        Vec3     hardcoded site center — F10 circle, label, and attack waypoint
--
--   blue / red side tables (both fields optional within each side):
--     .groups     list   ME late-activation group names to activate at mission start
--     .spawn_defs list   {type=...} unit defs for dynamic spawn (red_defending / blue side use)
--     .spawn_pos  Vec3   anchor for dynamic spawns (required when spawn_defs is set)
--
--   defenders  table    Blue force composition — Red counts scale against these values.
--                       Required for blue_defending missions.
--     .infantry    number   infantry unit count
--     .light_armor number   APC count
--     .heavy_armor number   IFV + tank count
--
--   airdef_anchor Vec3  Red air defense spawn anchor (red_defending missions).
--                       For blue_defending, air defense is placed dynamically near Red approach.

CasMission = {}

local MISSION_RADIUS   = 3000
local MISSION_LINE     = { 1, 0.75, 0, 1    }   -- amber, distinct from S&D orange / convoy green
local MISSION_FILL     = { 1, 0.75, 0, 0.15 }
local _markId          = 3100
local GROUND_SPEED_MPS = 3.1   -- ~7 mph; matches observed DCS infantry speed; vehicles set to same
local ORBIT_RADIUS     = 185   -- ~0.10 nm; orbit ring around the defended position
local ORBIT_STEPS      = 12    -- waypoints per full loop
local ORBIT_LOOPS      = 3     -- number of full orbits before stopping

-- ── Unit type pools ────────────────────────────────────────────────
-- BMP-1 confirmed: dumpLateGroupUnits group 'A' → type='BMP-1'
-- BMP-2 confirmed: dumpLateGroupUnits group 'B' → type='BMP-2'
local INFANTRY_POOL    = { "Soldier AK", "Soldier AK", "Infantry AK Ins", "Soldier RPG" }
local INFANTRY_TYPES   = { ["Soldier AK"]=true, ["Infantry AK Ins"]=true, ["Soldier RPG"]=true }
-- BRDM-2 confirmed: dumpLateGroupUnits group 'B' → type='BRDM-2' (ColdWarAssetsPack replaces model)
local LIGHT_ARMOR_POOL = { "BTR-70", "BTR-80", "BTR-80", "BMP-1", "BRDM-2" }
local HEAVY_ARMOR_POOL = { "T-55", "T-55", "T-72B" }

-- ── Air defense loadouts per threat level ──────────────────────────
local THREAT_DEFS = {
    low = {
        { type = "Ural-375 ZU-23",    count = {1, 2} },
        { type = "SA-18 Igla manpad", count = {1, 2} },
    },
    med = {
        { type = "Strela-1 9P31",     count = {1, 1} },
        { type = "Ural-375 ZU-23",    count = {1, 1} },
    },
    high = {
        { type = "Strela-10M3",       count = {1, 1} },
        { type = "ZSU-23-4 Shilka",   count = {1, 2} },
    },
}

-- ── Red force level multipliers ────────────────────────────────────
-- Applied against defenders.infantry / .light_armor / .heavy_armor.
-- Ranges {min, max}; a random value is picked within each range per session.
-- Attacking in DCS is significantly harder than defending, so even "adequate"
-- must exceed Blue unit counts to pose a real threat.
local FORCE_LEVELS = {
    weak = {
        infantry    = { 0.45, 0.75 },
        light_armor = { 0.45, 0.75 },
        heavy_armor = { 0.0,  0.0  },
    },
    adequate = {
        infantry    = { 1.05, 1.65 },
        light_armor = { 0.9,  1.35 },
        heavy_armor = { 0.15, 0.45 },
    },
    strong = {
        infantry    = { 2.1,  3.0  },
        light_armor = { 1.65, 2.4  },
        heavy_armor = { 0.75, 1.35 },
    },
    overwhelming = {
        infantry    = { 3.75, 5.25 },
        light_armor = { 3.0,  4.5  },
        heavy_armor = { 1.5,  2.7  },
    },
}

-- ── Mission definitions ────────────────────────────────────────────

local function ll(lat, lon)
    local p = coord.LLtoLO(lat, lon, 0)
    return { x = p.x, y = p.y, z = p.z }
end

local MISSIONS = {
    {
        name  = "KOVANLI_DEFENSE",
        label = "Defend Kovanli",
        mtype = "blue_defending",
        pos   = ll(36.8112, 37.6984),

        blue = {
            groups = {
                "BLUE_CAS_Kovanli_Infantry",
                "BLUE_CAS_Kovanli_Bradley",
                "BLUE_CAS_Kovanli_AAVAPC7",
                "BLUE_CAS_Kovanli_Scorpion",
            },
        },

        -- Blue force composition: Red unit counts scale against these values.
        defenders = {
            infantry    = 30,   -- M4 infantry
            light_armor = 5,    -- AAV-7 APCs
            heavy_armor = 5,    -- 3 Bradley IFVs + 2 Scorpion light tanks
        },
    },
}

-- ── Helpers ────────────────────────────────────────────────────────

local function pick(tbl)
    return tbl[math.random(#tbl)]
end

local function randBetween(a, b)
    return a + math.random() * (b - a)
end

local function formatAbsTime(t)
    local s = math.floor(t) % 86400
    return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60)
end

local function buildAirDefDefs(threat)
    local defs = {}
    for _, entry in ipairs(THREAT_DEFS[threat]) do
        local n = math.random(entry.count[1], entry.count[2])
        for i = 1, n do
            table.insert(defs, { type = entry.type })
        end
    end
    return defs
end

local function activateGroups(groups)
    if not groups then return end
    for _, name in ipairs(groups) do
        local g = Group.getByName(name)
        if g then
            g:activate()
            Log.info("CasMission: activated '" .. name .. "'")
        else
            Log.warn("CasMission: group not found '" .. name .. "'")
        end
    end
end

local function spawnSide(sideDef, countryId, missionName, sideLabel)
    if not sideDef then return end
    activateGroups(sideDef.groups)
    if sideDef.spawn_defs and sideDef.spawn_pos then
        Spawner.spawnGroundGroup(countryId, sideDef.spawn_pos, sideDef.spawn_defs, {
            name = "CAS_" .. missionName .. "_" .. sideLabel .. "_spawn",
        })
    end
end

-- Route: spawn position → ORBIT_LOOPS loops around the town at ORBIT_RADIUS.
-- entryBearing is the unit's approach angle from town center so the ring entry is smooth.
-- spawnPos: {x=north, y=east, alt}; townVec3: Vec3 {x=north, y=alt, z=east}.
local function buildOrbitRoute(spawnPos, townVec3, entryBearing)
    local cx = townVec3.x
    local cy = townVec3.z
    local points = {
        { x=spawnPos.x, y=spawnPos.y, alt=spawnPos.alt, type="Turning Point", action="Off Road", speed=GROUND_SPEED_MPS, ETA=0, ETA_locked=false },
    }
    for i = 0, ORBIT_STEPS * ORBIT_LOOPS - 1 do
        local a  = entryBearing + i * (2 * math.pi / ORBIT_STEPS)
        local wx = cx + ORBIT_RADIUS * math.cos(a)
        local wy = cy + ORBIT_RADIUS * math.sin(a)
        table.insert(points, {
            x=wx, y=wy, alt=land.getHeight({x=wx, y=wy}),
            type="Turning Point", action="Off Road",
            speed=GROUND_SPEED_MPS, ETA=0, ETA_locked=false,
        })
    end
    return { points = points }
end

-- Splits total Red unit budget across groupCount groups.
-- Returns list of {infantry, light_armor, heavy_armor} per-group tables.
local function computeGroupBudgets(defenders, forceLevel, groupCount)
    local mults = FORCE_LEVELS[forceLevel]
    local totalInf   = math.max(2, math.floor(defenders.infantry    * randBetween(mults.infantry[1],    mults.infantry[2])))
    local totalLight = math.max(0, math.floor(defenders.light_armor * randBetween(mults.light_armor[1], mults.light_armor[2])))
    local totalHeavy = math.max(0, math.floor(defenders.heavy_armor * randBetween(mults.heavy_armor[1], mults.heavy_armor[2])))

    local budgets = {}
    for i = 1, groupCount do
        budgets[i] = {
            infantry    = math.max(2, math.floor(totalInf   / groupCount)),
            light_armor = math.floor(totalLight / groupCount),
            heavy_armor = math.floor(totalHeavy / groupCount),
        }
    end
    -- Assign remainders to the last group.
    budgets[groupCount].infantry    = budgets[groupCount].infantry    + (totalInf   % groupCount)
    budgets[groupCount].light_armor = budgets[groupCount].light_armor + (totalLight % groupCount)
    budgets[groupCount].heavy_armor = budgets[groupCount].heavy_armor + (totalHeavy % groupCount)
    return budgets
end

local function buildUnitDefs(budget)
    local defs = {}
    for i = 1, budget.infantry    do table.insert(defs, { type = pick(INFANTRY_POOL)    }) end
    for i = 1, budget.light_armor do table.insert(defs, { type = pick(LIGHT_ARMOR_POOL) }) end
    for i = 1, budget.heavy_armor do table.insert(defs, { type = pick(HEAVY_ARMOR_POOL) }) end
    return defs
end

-- ── blue_defending Red spawner ─────────────────────────────────────

local function spawnRedAttackers(def, threat)
    local forceLevelPool = { "weak", "adequate", "strong", "overwhelming" }
    local forceLevel = forceLevelPool[math.random(#forceLevelPool)]

    local groupCount = math.random(1, 3)
    local attackMins = math.random(30, 120)
    local spawnDist  = attackMins * 60 * GROUND_SPEED_MPS   -- metres from town

    local budgets    = computeGroupBudgets(def.defenders, forceLevel, groupCount)
    local totalUnits = 0

    -- Groups approach from evenly-spaced bearings with a random overall rotation.
    local bearingOffset = math.random() * 2 * math.pi

    for i = 1, groupCount do
        local bearing  = bearingOffset + (i - 1) * (2 * math.pi / groupCount)
        local unitDefs = buildUnitDefs(budgets[i])

        -- Each unit is its own DCS group so they pathfind independently instead of
        -- marching in a single column. ±15° bearing jitter + ±15% distance jitter
        -- gives natural spread across the approach cone.
        for j, udef in ipairs(unitDefs) do
            local unitBearing = bearing + (math.random() - 0.5) * math.rad(30)
            local unitDist    = spawnDist * randBetween(0.85, 1.15)
            if not INFANTRY_TYPES[udef.type] then
                unitDist = unitDist * 0.85   -- vehicles lead; spawn ~15% closer to objective
            end
            local sx = def.pos.x + unitDist * math.cos(unitBearing)
            local sy = def.pos.z + unitDist * math.sin(unitBearing)
            local uPos = { x = sx, y = sy, alt = land.getHeight({x = sx, y = sy}) }
            Spawner.spawnGroundGroup(country.id.CJTF_RED, uPos, { udef }, {
                name  = "CAS_" .. def.name .. "_red_" .. i .. "_" .. j,
                route = buildOrbitRoute(uPos, def.pos, unitBearing),
            })
        end

        totalUnits = totalUnits + #unitDefs
        Log.info(string.format("CasMission: Red group %d/%d @ bearing %.0f°, dist=%.0fm, %d units (force=%s)",
            i, groupCount, math.deg(bearing) % 360, spawnDist, #unitDefs, forceLevel))
    end

    -- Air defense: spawns 1–2 nm behind the assault force, then routes to a support
    -- position 1.5–2.5 km from town on the approach bearing — close enough for SA-13
    -- and ZU-23 to cover the assault as it closes on the defenders.
    -- Each unit is its own group with jittered spawn (500m) and destination (200m)
    -- so they remain spread out rather than clumping at the waypoint.
    local adDist    = spawnDist + randBetween(1852, 3704)
    local adAnchorX = def.pos.x + adDist * math.cos(bearingOffset)
    local adAnchorY = def.pos.z + adDist * math.sin(bearingOffset)
    local supportDist = randBetween(1500, 2500)
    local supX = def.pos.x + supportDist * math.cos(bearingOffset)
    local supY = def.pos.z + supportDist * math.sin(bearingOffset)

    local adDefs = buildAirDefDefs(threat)
    for k, adef in ipairs(adDefs) do
        local spawnA = math.random() * 2 * math.pi
        local spawnR = math.random() * 500
        local ux  = adAnchorX + spawnR * math.cos(spawnA)
        local uy  = adAnchorY + spawnR * math.sin(spawnA)
        local uAlt = land.getHeight({x = ux, y = uy})
        local wpA = math.random() * 2 * math.pi
        local wpR = math.random() * 200
        local wpx = supX + wpR * math.cos(wpA)
        local wpy = supY + wpR * math.sin(wpA)
        Spawner.spawnGroundGroup(country.id.CJTF_RED, { x = ux, y = uy, alt = uAlt }, { adef }, {
            name  = "CAS_" .. def.name .. "_airdef_" .. k,
            route = {
                points = {
                    { x = ux,  y = uy,  alt = uAlt,                           type = "Turning Point", action = "Off Road", speed = GROUND_SPEED_MPS, ETA = 0, ETA_locked = false },
                    { x = wpx, y = wpy, alt = land.getHeight({x = wpx, y = wpy}), type = "Turning Point", action = "Off Road", speed = GROUND_SPEED_MPS, ETA = 0, ETA_locked = false },
                }
            },
        })
    end

    return {
        groupCount  = groupCount,
        forceLevel  = forceLevel,
        attackMins  = attackMins,
        totalUnits  = totalUnits,
        arrivalTime = timer.getAbsTime() + math.max(30, attackMins * 60 - 10 * 60),
    }
end

-- ── Spawn one CAS mission ──────────────────────────────────────────

local function spawnOneMission(def, threat)
    spawnSide(def.blue, country.id.CJTF_BLUE, def.name, "blue")

    local redInfo
    if def.mtype == "blue_defending" then
        redInfo = spawnRedAttackers(def, threat)
    else
        spawnSide(def.red, country.id.CJTF_RED, def.name, "red")
        local airdefAnchor = def.airdef_anchor
            or (def.red and def.red.spawn_pos)
            or def.pos
        Spawner.spawnGroundGroup(country.id.CJTF_RED, airdefAnchor, buildAirDefDefs(threat), {
            name   = "CAS_" .. def.name .. "_airdef",
            spread = 150,
        })
    end

    trigger.action.circleToAll(-1, _markId, def.pos, MISSION_RADIUS, MISSION_LINE, MISSION_FILL, 1, true, "")
    _markId = _markId + 1
    trigger.action.markToAll(_markId,
        string.format("CAS: %s [%s]", def.label, threat:upper()),
        def.pos, true, "")
    _markId = _markId + 1

    Log.info(string.format("CasMission: '%s' spawned, threat=%s", def.name, threat))

    return {
        label   = def.label,
        mtype   = def.mtype,
        threat  = threat,
        pos     = def.pos,
        redInfo = redInfo,
    }
end

-- ── Public API ─────────────────────────────────────────────────────

function CasMission.generate(assignments, casMenu)
    Log.info("--- CAS Mission Generation Start ---")

    local threats = { "low", "med", "high" }
    for i = #threats, 2, -1 do
        local j = math.random(i)
        threats[i], threats[j] = threats[j], threats[i]
    end

    local lines     = { "=== CAS MISSIONS ===" }
    local menuInfos = {}

    for i, def in ipairs(MISSIONS) do
        local threat = threats[(i - 1) % #threats + 1]
        local result = spawnOneMission(def, threat)
        if result then
            local infoStr
            if result.redInfo then
                local ri = result.redInfo
                infoStr = string.format(
                    "CAS: %s [%s]\n   DEFEND — Blue force under attack\n   GPS: %s\n   Attackers: %d units in %d group%s\n   Est. arrival: %s",
                    result.label, result.threat:upper(),
                    Spawner.formatLL(result.pos),
                    ri.totalUnits, ri.groupCount, ri.groupCount > 1 and "s" or "",
                    formatAbsTime(ri.arrivalTime))
            else
                infoStr = string.format(
                    "CAS: %s [%s]\n   ASSAULT\n   GPS: %s",
                    result.label, result.threat:upper(), Spawner.formatLL(result.pos))
            end
            table.insert(lines, "\n" .. infoStr)
            table.insert(menuInfos, {
                title = string.format("%s [%s]", result.label, result.threat:upper()),
                info  = infoStr,
            })
        end
    end

    trigger.action.outText(table.concat(lines, "\n"), 300)

    if casMenu then
        for _, entry in ipairs(menuInfos) do
            missionCommands.addCommandForCoalition(coalition.side.BLUE, entry.title, casMenu,
                function(text) trigger.action.outText(text, 60) end,
                entry.info)
        end
    end

    Log.info("--- CAS Mission Generation Complete ---")
end
