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
-- 3:1 country:airbase weighting — missile sites cluster near airfields without this
local VALID_LOCATIONS = { "country", "country", "country", "airbase" }

-- Valid location types for VIP missions (road is valid; helicopter can land near roads).
local VIP_VALID_LOCATIONS = { "country", "country", "road", "airbase" }

-- VIP unit constants.
local VIP_SPREAD    = 30       -- metres — tight cluster simulating a meeting/landing
local VIP_HELO_TYPE = "Mi-8MT" -- unverified static type; check dcs.log for woCar errors on first run

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

-- Returns a random Blue base name and its Vec3, or nil, nil if none available.
local function pickBlueTarget(assignments)
    local pool = {}
    for _, a in ipairs(assignments) do
        if a.side == coalition.side.BLUE then
            table.insert(pool, a.name)
        end
    end
    if #pool == 0 then
        Log.warn("SdMission.pickBlueTarget: no Blue bases in assignments")
        return nil, nil
    end
    local name = pick(pool)
    local ab = Airbase.getByName(name)
    if not ab then
        Log.warn("SdMission.pickBlueTarget: Airbase.getByName failed for '" .. name .. "'")
        return nil, nil
    end
    return name, ab:getPoint()
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

    local minD, maxD
    if ltype == "airbase" then
        minD, maxD = 800, 2500
    else
        minD, maxD = 15000, 60000
    end

    local p
    for attempt = 1, 10 do
        p = Spawner.nearPos(abVec3, minD, maxD, false)
        if Spawner.isOnLand(p) and Spawner.isFlatEnough(p) then break end
        if attempt == 10 then
            Log.warn("SdMission.resolveSite: all retries failed land/flat check near " .. baseName)
        end
    end

    local locationLabel = ltype == "airbase" and ("outskirts of " .. baseName)
                                              or  ("countryside near " .. baseName)
    return locationLabel, posToVec3(p)
end

-- Returns label and site Vec3 for a VIP mission, or nil on failure.
-- Tighter flatness check (100m / 15m) — site must be viable as a helicopter LZ.
local function resolveVipSite(assignments)
    local pool = {}
    for _, a in ipairs(assignments) do
        if a.side == coalition.side.RED then
            table.insert(pool, a.name)
        end
    end
    if #pool == 0 then
        Log.warn("SdMission.resolveVipSite: no Red bases in assignments")
        return nil, nil
    end

    local baseName = pick(pool)
    local ab = Airbase.getByName(baseName)
    if not ab then
        Log.warn("SdMission.resolveVipSite: airbase not found '" .. baseName .. "'")
        return nil, nil
    end
    local abVec3 = ab:getPoint()

    local ltype = pick(VIP_VALID_LOCATIONS)
    local minD, maxD, snapRoad
    if ltype == "airbase" then
        minD, maxD, snapRoad = 800, 2500, false
    elseif ltype == "road" then
        minD, maxD, snapRoad = 15000, 60000, true
    else
        minD, maxD, snapRoad = 15000, 60000, false
    end

    local p
    for attempt = 1, 10 do
        p = Spawner.nearPos(abVec3, minD, maxD, snapRoad)
        if Spawner.isOnLand(p) and Spawner.isFlatEnough(p, 100, 15) then break end
        if attempt == 10 then
            Log.warn("SdMission.resolveVipSite: all retries failed land/flat check near " .. baseName)
        end
    end

    local locationLabel
    if ltype == "airbase" then
        locationLabel = "outskirts of " .. baseName
    elseif ltype == "road" then
        locationLabel = "road near " .. baseName
    else
        locationLabel = "countryside near " .. baseName
    end
    return locationLabel, posToVec3(p)
end

-- ── Spawn one S&D missile mission ────────────────────────────────

local function spawnOneMission(idx, ltype, threat, assignments)
    local label, siteVec3 = resolveSite(ltype, assignments)
    if not siteVec3 then
        Log.warn("SdMission: could not resolve site for mission " .. idx)
        return nil
    end

    local sitePos = vec3ToPos(siteVec3)   -- {x,y,alt} for spawnGroundGroup

    -- 1. TEL groups: one group per launcher so each group controller fires independently.
    local telCount      = math.random(1, 5)
    local telGroupNames = {}
    for i = 1, telCount do
        local gName  = "SD_M" .. idx .. "_tel_" .. i
        local telPos
        for attempt = 1, 10 do
            telPos = Spawner.nearPos(siteVec3, 0, TEL_SPREAD, false)
            if Spawner.isFlatEnough(telPos, 75, 20) then break end
            if attempt == 10 then
                Log.warn("SdMission: M" .. idx .. " TEL " .. i .. " could not find flat ground, using best candidate")
            end
        end
        Spawner.spawnGroundGroup(country.id.CJTF_RED, telPos, {{ type = SCUD_TYPE }}, {
            name = gName,
        })
        table.insert(telGroupNames, gName)
    end

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

    -- 4. Blue target base for the launch order.
    local targetName, targetVec3 = pickBlueTarget(assignments)

    -- 5. F10 circle and label.
    trigger.action.circleToAll(-1, _markId, siteVec3, MISSION_RADIUS, MISSION_LINE, MISSION_FILL, 1, true, "")
    _markId = _markId + 1
    trigger.action.markToAll(_markId,
        string.format("S&D %d: Missile Site [%s]", idx, threat:upper()),
        siteVec3, true, "")
    _markId = _markId + 1

    return {
        idx           = idx,
        mtype         = "missile",
        ltype         = ltype,
        label         = label,
        threat        = threat,
        telCount      = telCount,
        pos           = siteVec3,
        telGroupNames = telGroupNames,
        targetName    = targetName,
        targetVec3    = targetVec3,
    }
end

-- ── Spawn one S&D VIP mission ─────────────────────────────────────

local function spawnVipMission(idx, threat, assignments)
    local label, siteVec3 = resolveVipSite(assignments)
    if not siteVec3 then
        Log.warn("SdMission: could not resolve VIP site for mission " .. idx)
        return nil
    end

    local sitePos = vec3ToPos(siteVec3)

    -- 1. Infantry + vehicles: tight cluster simulating a meeting around the landing site.
    local groupDefs = {}
    for i = 1, math.random(5, 8) do
        table.insert(groupDefs, { type = math.random(2) == 1 and "Soldier AK" or "Infantry AK Ins" })
    end
    table.insert(groupDefs, { type = "BTR-80"       })
    table.insert(groupDefs, { type = "Ural-4320-31" })
    table.insert(groupDefs, { type = "Ural-4320-31" })
    Spawner.spawnGroundGroup(country.id.CJTF_RED, sitePos, groupDefs, {
        name   = "SD_M" .. idx .. "_vip",
        spread = VIP_SPREAD,
    })

    -- 2. Static helicopter parked at the meeting site.
    local heloPos = Spawner.nearPos(siteVec3, 0, VIP_SPREAD, false)
    coalition.addStaticObject(country.id.CJTF_RED, {
        name    = "SD_M" .. idx .. "_helo",
        type    = VIP_HELO_TYPE,
        x       = heloPos.x,
        y       = heloPos.y,
        heading = math.random() * 2 * math.pi,
    })

    -- 3. Air defense group offset from site.
    local airPos = Spawner.nearPos(siteVec3, AIRDEF_OFFSET_MIN, AIRDEF_OFFSET_MAX, false)
    Spawner.spawnGroundGroup(country.id.CJTF_RED, airPos, buildThreatDefs(threat), {
        name   = "SD_M" .. idx .. "_airdef",
        spread = AIRDEF_SPREAD,
    })

    -- 4. F10 circle and label.
    trigger.action.circleToAll(-1, _markId, siteVec3, MISSION_RADIUS, MISSION_LINE, MISSION_FILL, 1, true, "")
    _markId = _markId + 1
    trigger.action.markToAll(_markId,
        string.format("S&D %d: VIP [%s]", idx, threat:upper()),
        siteVec3, true, "")
    _markId = _markId + 1

    return {
        idx    = idx,
        mtype  = "vip",
        label  = label,
        threat = threat,
        pos    = siteVec3,
    }
end

-- ── Helpers ──────────────────────────────────────────────────────

-- Formats an absolute DCS mission time (seconds since midnight) as HH:MM:SS.
local function formatAbsTime(t)
    local s = math.floor(t) % 86400
    return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60)
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

    -- Two missions per session: one missile (M1) and one VIP (M2).
    -- Threats are shuffled above so threat level assignment varies each session.
    local missions = {}

    local m1 = spawnOneMission(1, pick(VALID_LOCATIONS), threats[1], assignments)
    if m1 then
        table.insert(missions, m1)
        Log.info(string.format("  M1: %s / threat=%s / %d TELs @ %s → %s",
            m1.label, m1.threat, m1.telCount,
            Spawner.formatLL(m1.pos), m1.targetName or "no target"))
    end

    local m2 = spawnVipMission(2, threats[2], assignments)
    if m2 then
        table.insert(missions, m2)
        Log.info(string.format("  M2: VIP / threat=%s @ %s",
            m2.threat, Spawner.formatLL(m2.pos)))
    end

    -- Schedule fire timers (missile only) and build screen summary.
    local lines = { "=== STRIKE MISSIONS (S&D) ===" }
    for _, m in ipairs(missions) do
        if m.mtype == "missile" then
            local launchers = m.telCount == 1 and "1 launcher" or (m.telCount .. " launchers")
            if m.targetName and m.targetVec3 then
                local duration   = math.random(120, 180)  -- 2–3 min for testing; increase later
                local launchTime = formatAbsTime(timer.getAbsTime() + duration)
                local gNames = m.telGroupNames
                local tVec3  = m.targetVec3
                timer.scheduleFunction(function(_, _t)
                    Log.info("SdMission: M" .. m.idx .. " launch — " .. #gNames .. " TEL(s) → " .. m.targetName)
                    Spawner.fireGroups(gNames, tVec3, 4)
                end, nil, timer.getTime() + duration)
                Log.info(string.format("  M%d: launch in %ds at %s → %s", m.idx, duration, launchTime, m.targetName))
                table.insert(lines, string.format(
                    "\nM%d [%s] Missile Site — %s\n   GPS: %s\n   Target: %s | Launch: %s | %s",
                    m.idx, m.threat:upper(), m.label,
                    Spawner.formatLL(m.pos), m.targetName, launchTime, launchers))
            else
                Log.warn("SdMission: M" .. m.idx .. " has no Blue target, skipping fire timer")
                table.insert(lines, string.format(
                    "\nM%d [%s] Missile Site — %s\n   GPS: %s\n   %s | No target assigned",
                    m.idx, m.threat:upper(), m.label,
                    Spawner.formatLL(m.pos), launchers))
            end
        elseif m.mtype == "vip" then
            table.insert(lines, string.format(
                "\nM%d [%s] VIP Target — %s\n   GPS: %s",
                m.idx, m.threat:upper(), m.label,
                Spawner.formatLL(m.pos)))
        end
    end
    trigger.action.outText(table.concat(lines, "\n"), 300)

    Log.info("--- S&D Mission Generation Complete ---")
end
