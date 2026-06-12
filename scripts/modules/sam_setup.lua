-- SAM Site Activation: activates fixed SA-2/SA-6 installations and spawns
-- roaming SA-9/SA-13 units at mission start.
--
-- Fixed sites (SA-2, SA-6): pre-placed in ME as late-activation groups.
-- Roaming SAMs (SA-9, SA-13): dynamically spawned via Spawner.
--
-- region values for fixed sites:
--   "always_red"   → always activate (site is in a fixed-Red cluster)
--   cluster id     → activate only if that contested cluster resolved Red

SamSetup = {}

-- ============================================================
-- FIXED SITE DEFINITIONS (SA-2 / SA-6)
-- Add one entry per physical installation. Group names must match ME exactly.
-- ============================================================

local SAM_SITES = {
    { sa2 = "RED_Sanliurfa_SA2",     sa6 = "RED_Sanliurfa_SA6",     region = "TURKEY"   },
    { sa2 = "RED_BasselAlAssad_SA2", sa6 = "RED_BasselAlAssad_SA6", region = "RED_CORE" },
    { sa2 = "RED_Damascus_SA2",      sa6 = "RED_Damascus_SA6",      region = "DAMASCUS" },
    { sa2 = "RED_Aleppo_SA2",        sa6 = "RED_Aleppo_SA6",        region = "ALEPPO"   },
}

-- ============================================================
-- ROAMING SAM DEFINITIONS (SA-9 / SA-13)
-- Dynamically spawned each session. maxCount is the upper bound (0 is always possible).
-- Unit type strings must match DCS exactly — wrong names silently spawn Leopard-2s.
-- ============================================================

local ROAMING_SAMS = {
    { name = "SA-9",  unitType = "Strela-1 9P31", maxCount = 2, skill = "Average" },
    { name = "SA-13", unitType = "Strela-10M3",   maxCount = 3, skill = "Average" },
}

-- Spawn ring for units placed AT a Red airbase
local AT_BASE = { minDist = 500,   maxDist = 2000  }
-- Spawn ring for units placed in open terrain (anchored to a random Red airbase)
local IN_FIELD = { minDist = 15000, maxDist = 40000 }

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

local function isRed(region, clusterSides)
    if region == "always_red" then return true end
    return clusterSides[region] == coalition.side.RED
end

local function activateGroup(name)
    local grp = Group.getByName(name)
    if not grp then
        Log.warn("SAM group not found: '" .. name .. "' — check ME group name spelling")
        return false
    end
    grp:activate()
    return true
end

-- Returns the position of unit 1 in a named group, or nil.
local function groupPos(name)
    local grp = Group.getByName(name)
    if not grp then return nil end
    local u = grp:getUnit(1)
    if not u then return nil end
    return u:getPoint()
end

-- Spawns roaming SA-9/SA-13 units. redBaseNames is a list of Red airbase name strings.
-- Returns a list of screen-summary strings for activated units.
local function spawnRoaming(redBaseNames, activated)
    if #redBaseNames == 0 then
        Log.info("  No Red bases — skipping roaming SAMs")
        return
    end

    for _, def in ipairs(ROAMING_SAMS) do
        local count = math.random(0, def.maxCount)
        Log.info(string.format("  %s: spawning %d this session", def.name, count))

        for i = 1, count do
            local baseName = redBaseNames[math.random(#redBaseNames)]
            local ab = Airbase.getByName(baseName)
            if not ab then
                Log.warn("  Roaming SAM anchor airbase not found: " .. baseName)
            else
                local center   = ab:getPoint()
                local atBase   = math.random(2) == 1
                local ring     = atBase and AT_BASE or IN_FIELD
                local pos      = Spawner.nearPos(center, ring.minDist, ring.maxDist, false)
                local grpName  = "SAM_" .. def.name:gsub("%-", "") .. "_" .. i

                local grp = Spawner.spawnGroundGroup(
                    country.id.CJTF_RED,
                    pos,
                    { { type = def.unitType, skill = def.skill } },
                    { name = grpName }
                )

                if grp then
                    local loc = atBase and ("airbase: " .. baseName) or ("field near " .. baseName)
                    local ll  = Spawner.formatLL(grp:getUnit(1):getPoint())
                    Log.info(string.format("  Spawned %s (%s)  %s", grpName, loc, ll))
                    table.insert(activated, { label = def.name .. "  " .. loc, ll = ll })
                end
            end
        end
    end
end

-- ============================================================
-- PUBLIC API
-- ============================================================

-- clusterSides : cluster.id → coalition.side  (from CoalitionSetup.assign())
-- assignments  : list of { name, side }        (from CoalitionSetup.assign())
function SamSetup.spawn(clusterSides, assignments)
    Log.info("--- SAM Site Activation Start ---")

    -- Build Red airbase list for roaming SAM anchoring
    local redBaseNames = {}
    for _, a in ipairs(assignments or {}) do
        if a.side == coalition.side.RED then
            table.insert(redBaseNames, a.name)
        end
    end

    -- ── Fixed sites: SA-2 and SA-6 ───────────────────────────

    local redSites = {}
    for _, site in ipairs(SAM_SITES) do
        if isRed(site.region, clusterSides) then
            table.insert(redSites, site)
        else
            Log.info("  Skipped fixed site — Blue territory (region: " .. site.region .. ")")
        end
    end

    local activated = {}

    -- SA-2: 10% global chance, at most one on the map
    local sa2Site = nil
    if #redSites > 0 and math.random(100) <= 10 then
        sa2Site = redSites[math.random(#redSites)]
        if activateGroup(sa2Site.sa2) then
            local ll  = Spawner.formatLL(groupPos(sa2Site.sa2))
            Log.info("  Activated SA-2: " .. sa2Site.sa2 .. "  " .. ll)
            table.insert(activated, { label = "SA-2  " .. sa2Site.sa2, ll = ll })
        end
    else
        Log.info("  SA-2: did not spawn this session")
    end

    -- SA-6: 15% per Red site, skipping whichever site got the SA-2
    for _, site in ipairs(redSites) do
        if site == sa2Site then
            Log.debug("  SA-6 skipped at SA-2 site: " .. site.sa6)
        elseif math.random(100) <= 15 then
            if activateGroup(site.sa6) then
                local ll = Spawner.formatLL(groupPos(site.sa6))
                Log.info("  Activated SA-6: " .. site.sa6 .. "  " .. ll)
                table.insert(activated, { label = "SA-6  " .. site.sa6, ll = ll })
            end
        else
            Log.debug("  SA-6 rolled off: " .. site.sa6)
        end
    end

    -- ── Roaming SAMs: SA-9 and SA-13 ─────────────────────────

    spawnRoaming(redBaseNames, activated)

    -- ── Screen summary ────────────────────────────────────────

    local lines = { "=== SAM SITES ACTIVE ===" }
    if #activated == 0 then
        table.insert(lines, "  (none)")
    else
        for _, entry in ipairs(activated) do
            table.insert(lines, "  " .. entry.label)
            table.insert(lines, "    " .. entry.ll)
        end
    end
    trigger.action.outText(table.concat(lines, "\n"), 300)

    Log.info("--- SAM Site Activation Complete ---")
end
