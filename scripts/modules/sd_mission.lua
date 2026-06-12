-- Search & Destroy Missions: dynamically spawns ballistic missile target sites.
-- Each session generates one mission per threat level (low / med / high).
-- Each mission = 1 TEL group + 1 support group + 1 air-defense group.
-- Mark IDs 3000–3099 reserved for S&D missions.

SdMission = {}

-- NOTE: Scud-B type string unconfirmed.
-- Add a Scud-B unit to ME debug group "E" and check dcs.log for the
-- getTypeName() output, then update this constant.
local SCUD_TYPE = "Scud_B"

local MISSION_RADIUS = 13500  -- F10 circle radius in metres

-- Spawning geometry around the site anchor point.
local TEL_SPREAD         = 200
local SUPPORT_SPREAD     = 300
local AIRDEF_OFFSET_MIN  = 400
local AIRDEF_OFFSET_MAX  = 900
local AIRDEF_SPREAD      = 150

-- Orange circles, distinct from territory (blue/red) and convoy (green) circles.
local MISSION_LINE = { 1, 0.55, 0, 1   }
local MISSION_FILL = { 1, 0.55, 0, 0.2 }

local _markId = 3000


-- Air defense loadouts per threat level. count = {min, max}.
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

-- Valid location types for ballistic missile missions.
-- "airbase"  → site hidden 800–2500m outside a Red airbase perimeter
-- "country"  → open terrain 15–60 km from a Red base anchor, no road snap
-- Other mission types (troops, VIP, CAS) will declare their own valid lists.
local VALID_LOCATIONS = { "airbase", "country" }

-- ── Helpers ──────────────────────────────────────────────────────

local function pick(tbl)
    return tbl[math.random(#tbl)]
end

-- nearPos returns {x=north, y=east, alt}; DCS draw/mark calls need Vec3 {x,y,z}.
local function posToVec3(p)
    return { x = p.x, y = p.alt, z = p.y }
end

-- Vec3 {x=north, y=alt, z=east} → nearPos/spawnGroundGroup format {x,y,alt}.
local function vec3ToPos(v)
    return { x = v.x, y = v.z, alt = v.y }
end

local function buildThreatDefs(threatLevel)
    local defs = {}
    for _, entry in ipairs(THREAT_DEFS[threatLevel]) do
        local n = math.random(entry.count[1], entry.count[2])
        for i = 1, n do
            table.insert(defs, { type = entry.type })
        end
    end
    return defs
end

-- Returns label (string) and site Vec3, or nil on failure.
local function resolveSite(ltype, assignments)
    local pool = {}
    for _, a in ipairs(assignments) do
        if a.side == coalition.side.RED then
            table.insert(pool, a.name)
        end
    end
    if #pool == 0 then
        Log.warn("SdMission.resolveSite: no Red bases in assignments")
        return nil, nil
    end

    local baseName = pick(pool)
    local ab = Airbase.getByName(baseName)
    if not ab then
        Log.warn("SdMission.resolveSite: airbase not found '" .. baseName .. "'")
        return nil, nil
    end
    local abVec3 = ab:getPoint()

    if ltype == "airbase" then
        -- Site hidden 800–2500m outside the runway perimeter, off-road.
        local p = Spawner.nearPos(abVec3, 800, 2500, false)
        return "outskirts of " .. baseName, posToVec3(p)
    end

    -- country: open terrain 15–60 km from a Red base anchor, no road snap.
    local p = Spawner.nearPos(abVec3, 15000, 60000, false)
    return "countryside near " .. baseName, posToVec3(p)
end

-- ── Spawn one S&D missile mission ────────────────────────────────

local function spawnOneMission(idx, ltype, threat, assignments)
    local label, siteVec3 = resolveSite(ltype, assignments)
    if not siteVec3 then
        Log.warn("SdMission: could not resolve site for mission " .. idx)
        return nil
    end

    local sitePos = vec3ToPos(siteVec3)   -- {x,y,alt} for spawnGroundGroup

    -- 1. TEL group: 1–5 Scud-B launchers clustered together.
    local telCount = math.random(1, 5)
    local telDefs  = {}
    for i = 1, telCount do
        table.insert(telDefs, { type = SCUD_TYPE })
    end
    Spawner.spawnGroundGroup(country.id.CJTF_RED, sitePos, telDefs, {
        name   = "SD_M" .. idx .. "_tels",
        spread = TEL_SPREAD,
    })

    -- 2. Support group: infantry and vehicles guarding the site.
    local supDefs = {}
    for i = 1, math.random(2, 6) do table.insert(supDefs, { type = "Soldier AK"   }) end
    for i = 1, math.random(1, 3) do table.insert(supDefs, { type = "Soldier RPG"  }) end
    for i = 1, math.random(1, 2) do table.insert(supDefs, { type = "BTR-80"       }) end
    for i = 1, math.random(1, 2) do table.insert(supDefs, { type = "Ural-4320-31" }) end
    Spawner.spawnGroundGroup(country.id.CJTF_RED, sitePos, supDefs, {
        name   = "SD_M" .. idx .. "_support",
        spread = SUPPORT_SPREAD,
    })

    -- 3. Air defense group: offset 600–1500m from site center.
    local airPos = Spawner.nearPos(siteVec3, AIRDEF_OFFSET_MIN, AIRDEF_OFFSET_MAX, false)
    Spawner.spawnGroundGroup(country.id.CJTF_RED, airPos, buildThreatDefs(threat), {
        name   = "SD_M" .. idx .. "_airdef",
        spread = AIRDEF_SPREAD,
    })

    -- 4. F10 circle and label.
    trigger.action.circleToAll(-1, _markId, siteVec3, MISSION_RADIUS, MISSION_LINE, MISSION_FILL, 1, true, "")
    _markId = _markId + 1
    trigger.action.markToAll(_markId,
        string.format("S&D %d: Missile Site [%s]", idx, threat:upper()),
        siteVec3, true, "")
    _markId = _markId + 1

    return {
        idx      = idx,
        ltype    = ltype,
        label    = label,
        threat   = threat,
        telCount = telCount,
        pos      = siteVec3,
    }
end

-- ── Public API ────────────────────────────────────────────────────

function SdMission.generate(assignments)
    Log.info("--- S&D Mission Generation Start ---")

    -- One mission per threat level; shuffle order so map presentation varies.
    local threats = { "low", "med", "high" }
    for i = #threats, 2, -1 do
        local j = math.random(i)
        threats[i], threats[j] = threats[j], threats[i]
    end

    local missions = {}
    for i, threat in ipairs(threats) do
        local ltype = pick(VALID_LOCATIONS)
        local m     = spawnOneMission(i, ltype, threat, assignments)
        if m then
            table.insert(missions, m)
            Log.info(string.format("  M%d: %s / threat=%s / %d TELs @ %s",
                m.idx, m.label, m.threat, m.telCount, Spawner.formatLL(m.pos)))
        end
    end

    -- Screen summary.
    local lines = { "=== STRIKE MISSIONS (S&D) ===" }
    for _, m in ipairs(missions) do
        table.insert(lines, string.format(
            "M%d: Ballistic Missile Site — %s  [Air: %s | %d launcher%s]",
            m.idx, m.label, m.threat:upper(), m.telCount,
            m.telCount > 1 and "s" or ""))
        table.insert(lines, "   GPS: " .. Spawner.formatLL(m.pos))
    end
    trigger.action.outText(table.concat(lines, "\n"), 180)

    Log.info("--- S&D Mission Generation Complete ---")
end
