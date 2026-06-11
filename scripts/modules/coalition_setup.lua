-- Coalition Setup: randomizes Red/Blue airbase ownership at mission start.
-- Uses a geographic cluster system so each side holds contiguous territory.
--
-- Cluster types:
--   fixed = coalition.side.BLUE  → always Blue
--   fixed = coalition.side.RED   → always Red
--   fixed = nil                  → contested, randomly assigned each session
--
-- IMPORTANT: Airbase name strings must match exactly what DCS reports.
-- If you see "nil" warnings in the log, run Log.dumpAirbases() to get correct names.

CoalitionSetup = {}

-- ============================================================
-- CLUSTER DEFINITIONS
-- Edit base name lists here if DCS reports name mismatches.
-- ============================================================

local CLUSTERS = {

    -- ── Always Blue ──────────────────────────────────────────

    {
        id    = "CYPRUS_SOUTH",
        name  = "Southern Cyprus (NATO Rear)",
        fixed = coalition.side.BLUE,
        bases = {
            "Akrotiri",
            "Larnaca",
            "Paphos",
            "Kingsfield",
            "Lakatamia",
        },
    },

    -- ── Always Red ───────────────────────────────────────────

    {
        id    = "RED_CORE",
        name  = "Russian Core (Latakia Coast)",
        fixed = coalition.side.RED,
        bases = {
            "Bassel Al-Assad",
            "Hama",
            "Taftanaz",
            "Minakh",
            "Wujah Al Hajar",
        },
    },

    {
        id    = "AT_TANF",
        name  = "At Tanf (US Outpost)",
        fixed = coalition.side.BLUE,
        bases = {
            "At Tanf",
        },
    },

    -- ── Contested (randomized each session) ──────────────────

    {
        id    = "TURKEY",
        name  = "NATO Northern Arc (Turkey)",
        fixed = nil,
        bases = {
            "Incirlik",
            "Adana Sakirpasa",
            "Hatay",
            "Gaziantep",
            "Gazipasa",
            "Sanliurfa",
            "Pinarbashi",
            "Gecitkale",
        },
    },
    {
        id    = "BLUE_SOUTH",
        name  = "Israel & Jordan",
        fixed = nil,
        bases = {
            "Ramat David",
            "Ben Gurion",
            "Haifa",
            "Tel Nof",
            "Hatzor",
            "Kiryat Shmona",
            "Megiddo",
            "Palmachim",
            "Herzliya",
            "King Abdullah II",
            "Muwaffaq Salti",
            "Marka",
            "Prince Hassan",
            "King Hussein Air College",
            "Ruwayshid",
        },
    },
    {
        id    = "DAMASCUS",
        name  = "Damascus Basin",
        fixed = nil,
        bases = {
            "Damascus",
            "Mezzeh",
            "Al-Dumayr",
            "Marj as Sultan North",
            "Marj as Sultan South",
            "Khalkhalah",
            "Marj Ruhayyil",
            "Tha'lah",
            -- "Ghabagheb",  -- name unconfirmed, re-add once dumpAirbases confirms spelling
        },
    },
    {
        id    = "ALEPPO",
        name  = "Aleppo Region",
        fixed = nil,
        bases = {
            "Aleppo",
            "Kuweires",
            "Jirah",
            "Abu al-Duhur",
        },
    },
    {
        id    = "CENTRAL_SYRIA",
        name  = "Central Syria (T4/Homs/Palmyra)",
        fixed = nil,
        bases = {
            "Shayrat",
            "Tiyas",
            "Palmyra",
            "Al Qusayr",
            "Sayqal",
        },
    },
    {
        id    = "LEBANON",
        name  = "Lebanon",
        fixed = nil,
        bases = {
            "Beirut-Rafic Hariri",
            "Rayak",
            "Rene Mouawad",
            "An Nasiriyah",
        },
    },

    {
        id    = "EUPHRATES",
        name  = "Euphrates / Northeast Syria",
        fixed = nil,
        bases = {
            "Kharab Ishk",
            "Tal Siman",
            "Tabqa",
            "Deir ez-Zor",
        },
    },
}

-- ============================================================
-- DYNAMIC SPAWN GROUP → AIRBASE MAPPING
-- For each airbase that has dynamic spawn groups in the ME, list the exact
-- group names here. coalition_setup sets a user flag per group (1=Red, 0=Blue)
-- which the Hooks slotblock script reads to enforce spawn access.
-- Add entries as you create groups in the Mission Editor.
-- ============================================================

local BASE_GROUPS = {
    ["Beirut-Rafic Hariri"] = { "BeirutRaficHariri_A10cii" },
    ["Tel Nof"]             = { "TelNof_A10cii" },
    ["Incirlik"]            = { "Incirlik_A10cii" },
}

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

local _markId = 1000

-- Colors: {r, g, b, a} as positional array, values 0-1.
-- DCS reads color tables by numeric index, not named keys.
local BLUE_LINE = { 0,    0.45, 1,    1   }
local BLUE_FILL = { 0,    0.45, 1,    0.3 }
local RED_LINE  = { 1,    0.1,  0.1,  1   }
local RED_FILL  = { 1,    0.1,  0.1,  0.3 }

local function setBase(name, side)
    local ab = Airbase.getByName(name)
    if not ab or not ab:isExist() then
        Log.warn("Airbase not found: '" .. name .. "' — check spelling against Log.dumpAirbases()")
        return false
    end
    ab:autoCapture(false)
    ab:setCoalition(side)

    local flagVal = (side == coalition.side.RED) and 1 or 0
    for _, gname in ipairs(BASE_GROUPS[name] or {}) do
        trigger.action.setUserFlag(gname, flagVal)
        Log.debug("Flag '" .. gname .. "' = " .. flagVal)
        -- if side == coalition.side.RED then
        --     local grp = Group.getByName(gname)
        --     if grp then
        --         grp:destroy()
        --         Log.debug("Destroyed client slot group '" .. gname .. "'")
        --     else
        --         Log.warn("Client slot group '" .. gname .. "' not found — check name in BASE_GROUPS")
        --     end
        -- end
    end

    local pos      = ab:getPoint()
    local lineCol  = (side == coalition.side.BLUE) and BLUE_LINE or RED_LINE
    local fillCol  = (side == coalition.side.BLUE) and BLUE_FILL or RED_FILL

    -- Radius 5000m (~2.7 nm) — large enough to be obvious at map zoom
    trigger.action.circleToAll(-1, _markId, pos, 5000, lineCol, fillCol, 1, true, "")
    _markId = _markId + 1

    return true
end

local function applyCluster(cluster, side)
    local sideName = (side == coalition.side.BLUE) and "BLUE" or "RED"
    local ok, fail = 0, 0
    for _, name in ipairs(cluster.bases) do
        if setBase(name, side) then ok = ok + 1 else fail = fail + 1 end
    end
    Log.info(string.format("  [%s] → %s  (%d ok, %d not found)", cluster.name, sideName, ok, fail))
end

-- ============================================================
-- PUBLIC API
-- ============================================================

-- Returns a flat list of { name, side } for every base — used by other modules
-- (e.g. DefenseSetup) to act on assignment results without coupling into this module.
function CoalitionSetup.assign()
    Log.info("--- Coalition Assignment Start ---")

    -- math.randomseed is unavailable in DCS's Lua environment.
    -- Instead, advance the RNG state manually using mission time so each
    -- session produces a different sequence.
    local t = timer and math.floor(timer.getAbsTime()) or 0
    local steps = (t % 97) + 1
    for i = 1, steps do math.random() end
    Log.debug("RNG advanced " .. steps .. " steps (t=" .. t .. ")")

    local results      = { blue = {}, red = {} }
    local assignments  = {}
    local clusterSides = {}  -- cluster.id → coalition.side, used by sam_setup

    for _, cluster in ipairs(CLUSTERS) do
        local side

        if cluster.fixed ~= nil then
            side = cluster.fixed
        else
            -- Each contested cluster independently has a 50% chance per side.
            side = (math.random(2) == 1) and coalition.side.BLUE or coalition.side.RED
        end

        applyCluster(cluster, side)
        clusterSides[cluster.id] = side

        local label = (side == coalition.side.BLUE) and results.blue or results.red
        table.insert(label, cluster.name)

        for _, baseName in ipairs(cluster.bases) do
            table.insert(assignments, { name = baseName, side = side })
        end
    end

    -- ── Mission-start summary (visible on screen for 60 s) ───
    local lines = { "=== MISSION START ===" }
    table.insert(lines, "BLUE territory:")
    for _, n in ipairs(results.blue) do table.insert(lines, "  + " .. n) end
    table.insert(lines, "RED territory:")
    for _, n in ipairs(results.red)  do table.insert(lines, "  - " .. n) end
    local summary = table.concat(lines, "\n")

    trigger.action.outText(summary, 60)
    Log.info(summary)
    Log.info("--- Coalition Assignment Complete ---")

    return assignments, clusterSides
end
