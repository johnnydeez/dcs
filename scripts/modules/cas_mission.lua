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
local GROUND_SPEED_MPS = 5.0   -- 5 m/s; observed DCS ground unit AI speed
local CONTACT_DIST     = 2400  -- ~1.5 miles; approx range at which tanks first engage defenders
local FRONTAGE         = 2000  -- metres; width of each group's attack line
local FAN_OUT_DIST     = 3700  -- ~2 nm; re-spread waypoint after terrain choke points
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
        { type = "SA-18 Igla manpad", count = {1, 2} },
    },
    high = {
        { type = "Strela-10M3",       count = {1, 2} },
        { type = "ZSU-23-4 Shilka",   count = {1, 2} },
        { type = "SA-18 Igla manpad", count = {2, 3} },
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
        light_armor = { 0.68, 1.13 },
        heavy_armor = { 0.0,  0.0  },
    },
    adequate = {
        infantry    = { 1.05, 1.65 },
        light_armor = { 1.35, 2.03 },
        heavy_armor = { 0.23, 0.68 },
    },
    strong = {
        infantry    = { 2.1,  3.0  },
        light_armor = { 2.48, 3.6  },
        heavy_armor = { 1.13, 2.03 },
    },
    overwhelming = {
        infantry    = { 3.75, 5.25 },
        light_armor = { 4.5,  6.75 },
        heavy_armor = { 2.25, 4.05 },
    },
}

-- ── Mission definitions ────────────────────────────────────────────

local function ll(lat, lon)
    local p = coord.LLtoLO(lat, lon, 0)
    return { x = p.x, y = p.y, z = p.z }
end

local MISSIONS = {
    {
        name  = "HS02_ATTACK",
        label = "Attack HS02",
        mtype = "red_defending",
        pos   = ll(35.3363, 36.0742),

        -- Perimeter points clockwise from NW, derived from in-game coordinate markers.
        -- Each becomes an anchor for one spawn bucket; units scatter within 80m of it.
        perimeter = {
            ll(35.3402, 36.0688),   -- NW: revetments / parking area
            ll(35.3402, 36.0728),   -- N: northern apron
            ll(35.3392, 36.0795),   -- NE: barracks north
            ll(35.3360, 36.0795),   -- E: barracks east side
            ll(35.3333, 36.0770),   -- SE: barracks south end
            ll(35.3328, 36.0718),   -- S: south edge
            ll(35.3325, 36.0688),   -- SW: road loop bottom
            ll(35.3365, 36.0688),   -- W: western fence
        },

        garrison = {
            infantry    = 16,
            light_armor = 4,
            heavy_armor = 2,
        },

        airdef_anchor = ll(35.3363, 36.0742),
        battle_smoke  = true,
    },
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

        smoke_zone   = "BLUE_CAS_Kovanli_GreenSmoke",
        battle_smoke = true,

        -- Exclude bearings from 90° (due east) clockwise to 241° (WSW) through south.
        -- The Turkey/Syria border wall blocks ground movement in that entire arc.
        -- Center = (90+241)/2 = 165.5°; half-width = (241-90)/2 = 75.5°.
        spawn_arc_exclude = { math.rad(165.5), math.rad(75.5) },
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

-- Converts a Vec3 from ll() {x=north, y=alt, z=east} to spawner pos {x=north, y=east, alt}.
local function vec3ToPos(v)
    return { x = v.x, y = v.z, alt = land.getHeight({ x = v.x, y = v.z }) }
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

local function spawnBattleSmoke(townPos)
    local count = math.random(3, 7)
    for i = 1, count do
        local angle = math.random() * 2 * math.pi
        local dist  = randBetween(300, 1500)
        local nx    = townPos.x + dist * math.cos(angle)
        local ez    = townPos.z + dist * math.sin(angle)
        local alt   = land.getHeight({ x = nx, y = ez })
        local pos   = { x = nx, y = alt, z = ez }
        local name   = string.format("cas_bsmoke_%d_%d", i, math.random(9999))
        local preset = math.random(2) == 1 and 1 or 2
        trigger.action.effectSmokeBig(pos, preset, 0.9, name)
    end
    Log.info(string.format("CasMission: spawned %d battle fire/smoke effects", count))
end

local function loopSmoke(zoneName, _)
    local zone = trigger.misc.getZone(zoneName)
    if zone then
        local p   = zone.point
        local alt = land.getHeight({ x = p.x, y = p.z })
        trigger.action.smoke({ x = p.x, y = alt, z = p.z }, trigger.smokeColor.Green)
        timer.scheduleFunction(loopSmoke, zoneName, timer.getTime() + 270)
    end
end

local function startSmoke(zoneName)
    local zone = trigger.misc.getZone(zoneName)
    if zone then
        local p   = zone.point
        local alt = land.getHeight({ x = p.x, y = p.z })
        trigger.action.smoke({ x = p.x, y = alt, z = p.z }, trigger.smokeColor.Green)
        timer.scheduleFunction(loopSmoke, zoneName, timer.getTime() + 270)
        Log.info("CasMission: started green smoke at zone '" .. zoneName .. "'")
    else
        Log.warn("CasMission: smoke zone not found '" .. zoneName .. "'")
    end
end

-- Returns true if bearing falls within the exclusion arc {center, halfWidth} (radians).
local function bearingExcluded(b, excl)
    if not excl then return false end
    local diff = b - excl[1]
    while diff >  math.pi do diff = diff - 2 * math.pi end
    while diff < -math.pi do diff = diff + 2 * math.pi end
    return math.abs(diff) < excl[2]
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

-- Route: spawn → fan-out waypoint on the 2nm ring → ORBIT_LOOPS loops around town.
-- fanOutPos: pre-computed {x=north, y=east} on the 2nm ring; each unit has its own
-- position spread laterally across the ring so they arrive on a wide front.
-- entryBearing: direction from town to fanOutPos, used to start the orbit smoothly.
-- spawnPos: {x=north, y=east, alt}; townVec3: Vec3 {x=north, y=alt, z=east}.
local function buildOrbitRoute(spawnPos, townVec3, entryBearing, fanOutPos)
    local cx = townVec3.x
    local cy = townVec3.z
    local points = {
        { x=spawnPos.x,  y=spawnPos.y,  alt=spawnPos.alt,                              type="Turning Point", action="Off Road", speed=GROUND_SPEED_MPS, ETA=0, ETA_locked=false },
        { x=fanOutPos.x, y=fanOutPos.y, alt=land.getHeight({x=fanOutPos.x, y=fanOutPos.y}), type="Turning Point", action="Off Road", speed=GROUND_SPEED_MPS, ETA=0, ETA_locked=false },
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
    local forceLevelPool = { "adequate", "strong", "overwhelming" }
    local forceLevel = forceLevelPool[math.random(#forceLevelPool)]

    local groupCount = math.random(1, 3)
    local attackMins = math.random(30, 45)
    local spawnDist  = attackMins * 60 * GROUND_SPEED_MPS + CONTACT_DIST   -- metres from town

    local totalUnits    = 0
    local groupBearings = {}

    -- Each group independently picks a random approach bearing, retrying up to 60
    -- times to avoid the exclusion arc. Groups may approach from similar directions
    -- but none will spawn in terrain that blocks movement.
    local perGroupBearings = {}
    for i = 1, groupCount do
        local b = 0
        for _ = 1, 60 do
            b = math.random() * 2 * math.pi
            if not bearingExcluded(b, def.spawn_arc_exclude) then break end
        end
        perGroupBearings[i] = b
    end

    local budgets = computeGroupBudgets(def.defenders, forceLevel, groupCount)

    for i = 1, groupCount do
        local bearing  = perGroupBearings[i]
        local unitDefs = buildUnitDefs(budgets[i])

        -- Line-of-departure: units spread evenly along a line perpendicular to the
        -- approach bearing at spawn distance. Each advances straight toward town from
        -- its own lateral position, keeping the front spread until the orbit ring.
        local n        = #unitDefs
        local perpBear = bearing + math.pi / 2
        local cx       = def.pos.x + spawnDist * math.cos(bearing)
        local cy       = def.pos.z + spawnDist * math.sin(bearing)

        for j, udef in ipairs(unitDefs) do
            local t             = n > 1 and (j - 1) / (n - 1) - 0.5 or 0  -- -0.5 to 0.5
            local lateralOffset = t * FRONTAGE
            local depthJitter   = spawnDist * randBetween(-0.07, 0.07)
            local sx = cx + lateralOffset * math.cos(perpBear) + depthJitter * math.cos(bearing)
            local sy = cy + lateralOffset * math.sin(perpBear) + depthJitter * math.sin(bearing)

            -- Fan-out waypoint: same lateral spread as spawn, placed on the 2nm ring.
            -- Small depth jitter per unit so they don't line up on a perfectly flat front.
            local fanDist  = FAN_OUT_DIST * randBetween(0.93, 1.07)
            local fwx      = def.pos.x + fanDist * math.cos(bearing) + lateralOffset * math.cos(perpBear)
            local fwy      = def.pos.z + fanDist * math.sin(bearing) + lateralOffset * math.sin(perpBear)
            local fanOutPos    = { x = fwx, y = fwy }
            local entryBearing = math.atan2(fwy - def.pos.z, fwx - def.pos.x)

            local uPos = { x = sx, y = sy, alt = land.getHeight({ x = sx, y = sy }) }
            Spawner.spawnGroundGroup(country.id.CJTF_RED, uPos, { udef }, {
                name  = "CAS_" .. def.name .. "_red_" .. i .. "_" .. j,
                route = buildOrbitRoute(uPos, def.pos, entryBearing, fanOutPos),
            })
        end

        totalUnits = totalUnits + #unitDefs
        local hdg = math.floor(math.deg(bearing) % 360 + 0.5)
        table.insert(groupBearings, hdg)
        Log.info(string.format("CasMission: Red group %d/%d @ bearing %03d°, dist=%.0fm, %d units (force=%s)",
            i, groupCount, hdg, spawnDist, #unitDefs, forceLevel))
    end

    -- Air defense: spawns 1–2 nm behind the assault force, then routes to a support
    -- position 1.5–2.5 km from town on the approach bearing — close enough for SA-13
    -- and ZU-23 to cover the assault as it closes on the defenders.
    -- Each unit is its own group with jittered spawn (500m) and destination (200m)
    -- so they remain spread out rather than clumping at the waypoint.
    local adDist    = spawnDist + randBetween(1852, 3704)
    local adAnchorX = def.pos.x + adDist * math.cos(perGroupBearings[1])
    local adAnchorY = def.pos.z + adDist * math.sin(perGroupBearings[1])
    local supportDist = randBetween(1500, 2500)
    local supX = def.pos.x + supportDist * math.cos(perGroupBearings[1])
    local supY = def.pos.z + supportDist * math.sin(perGroupBearings[1])

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
        groupCount    = groupCount,
        forceLevel    = forceLevel,
        attackMins    = attackMins,
        totalUnits    = totalUnits,
        arrivalTime   = timer.getAbsTime() + attackMins * 60,
        groupBearings = groupBearings,
    }
end

-- ── red_defending garrison spawner ─────────────────────────────────

local function spawnRedDefenders(def, threat)
    local forceLevelPool = { "adequate", "strong", "overwhelming" }
    local forceLevel     = forceLevelPool[math.random(#forceLevelPool)]
    local mults          = FORCE_LEVELS[forceLevel]

    local totalInf   = math.max(2, math.floor(def.garrison.infantry    * randBetween(mults.infantry[1],    mults.infantry[2])))
    local totalLight = math.max(0, math.floor(def.garrison.light_armor * randBetween(mults.light_armor[1], mults.light_armor[2])))
    local totalHeavy = math.max(0, math.floor(def.garrison.heavy_armor * randBetween(mults.heavy_armor[1], mults.heavy_armor[2])))

    local unitDefs = {}
    for _ = 1, totalInf   do table.insert(unitDefs, { type = pick(INFANTRY_POOL)    }) end
    for _ = 1, totalLight do table.insert(unitDefs, { type = pick(LIGHT_ARMOR_POOL) }) end
    for _ = 1, totalHeavy do table.insert(unitDefs, { type = pick(HEAVY_ARMOR_POOL) }) end
    for i = #unitDefs, 2, -1 do
        local j = math.random(i)
        unitDefs[i], unitDefs[j] = unitDefs[j], unitDefs[i]
    end

    -- Build closed perimeter polyline: each segment stores its start, normalised
    -- direction, perpendicular, length, and cumulative distance from point 0.
    local perim      = def.perimeter
    local perimCount = #perim
    local segments   = {}
    local perimLen   = 0
    for i = 1, perimCount do
        local a  = perim[i]
        local b  = perim[(i % perimCount) + 1]
        local dx = b.x - a.x
        local dz = b.z - a.z
        local len = math.sqrt(dx * dx + dz * dz)
        if len > 0 then
            local ndx = dx / len
            local ndz = dz / len
            table.insert(segments, {
                ax = a.x, az = a.z,
                ndx = ndx, ndz = ndz,
                perpx = -ndz, perpz = ndx,
                len = len, cum = perimLen,
            })
            perimLen = perimLen + len
        end
    end

    -- Random positions along the perimeter, sorted so units stay ordered around the
    -- loop without crossing. This produces natural clusters and gaps rather than
    -- regular spacing.
    local n         = #unitDefs
    local positions = {}
    for i = 1, n do positions[i] = math.random() * perimLen end
    table.sort(positions)

    for idx, udef in ipairs(unitDefs) do
        local t = positions[idx]

        local seg = segments[#segments]
        for _, s in ipairs(segments) do
            if t < s.cum + s.len then
                seg = s
                break
            end
        end

        local along = t - seg.cum
        local px    = seg.ax + along * seg.ndx + randBetween(-30, 30) * seg.perpx
        local pz    = seg.az + along * seg.ndz + randBetween(-30, 30) * seg.perpz

        Spawner.spawnGroundGroup(country.id.CJTF_RED, { x = px, y = pz, alt = land.getHeight({x=px, y=pz}) }, { udef }, {
            name = string.format("CAS_%s_def_%d", def.name, idx),
        })
    end

    Log.info(string.format("CasMission: '%s' garrison — force=%s, %d units (inf=%d, la=%d, ha=%d)",
        def.name, forceLevel, n, totalInf, totalLight, totalHeavy))

    return { forceLevel = forceLevel, totalUnits = n }
end

-- ── Spawn one CAS mission ──────────────────────────────────────────

local function spawnOneMission(def, threat)
    spawnSide(def.blue, country.id.CJTF_BLUE, def.name, "blue")

    local redInfo
    local defenderInfo
    if def.mtype == "blue_defending" then
        redInfo = spawnRedAttackers(def, threat)
    else
        spawnSide(def.red, country.id.CJTF_RED, def.name, "red")
        if def.perimeter then
            defenderInfo = spawnRedDefenders(def, threat)
        end
        local airdefVec3 = def.airdef_anchor or def.pos
        Spawner.spawnGroundGroup(country.id.CJTF_RED, vec3ToPos(airdefVec3), buildAirDefDefs(threat), {
            name   = "CAS_" .. def.name .. "_airdef",
            spread = 200,
        })
    end

    if def.smoke_zone then
        startSmoke(def.smoke_zone)
    end
    if def.battle_smoke then
        spawnBattleSmoke(def.pos)
    end

    trigger.action.circleToAll(-1, _markId, def.pos, MISSION_RADIUS, MISSION_LINE, MISSION_FILL, 1, true, "")
    _markId = _markId + 1
    trigger.action.markToAll(_markId,
        string.format("CAS: %s [%s]", def.label, threat:upper()),
        def.pos, true, "")
    _markId = _markId + 1

    Log.info(string.format("CasMission: '%s' spawned, threat=%s", def.name, threat))

    return {
        label        = def.label,
        mtype        = def.mtype,
        threat       = threat,
        pos          = def.pos,
        redInfo      = redInfo,
        defenderInfo = defenderInfo,
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
            if result.mtype == "blue_defending" then
                local ri = result.redInfo
                local hdgStrs = {}
                for _, h in ipairs(ri.groupBearings) do
                    table.insert(hdgStrs, string.format("%03d°", h))
                end
                infoStr = string.format(
                    "CAS: %s [%s]\n   DEFEND — Blue force under attack\n   GPS: %s\n   Attackers: %d units in %d group%s\n   Attack radials: %s\n   Est. first contact: %s",
                    result.label, result.threat:upper(),
                    Spawner.formatLL(result.pos),
                    ri.totalUnits, ri.groupCount, ri.groupCount > 1 and "s" or "",
                    table.concat(hdgStrs, ", "),
                    formatAbsTime(ri.arrivalTime))
            else
                local di = result.defenderInfo
                infoStr = string.format(
                    "CAS: %s [%s]\n   STRIKE — assault Red garrison\n   GPS: %s\n   Garrison: %d units [%s]",
                    result.label, result.threat:upper(), Spawner.formatLL(result.pos),
                    di and di.totalUnits or 0, di and di.forceLevel or "?")
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
