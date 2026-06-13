-- ============================================================
--  cost_config.lua
--  Mission Cost Counter – Configuration & Price Tables
--
--  All values are in M (millions USD, approximate real-world).
--  Examples:
--    $4,000   = 0.004M
--    $100,000 = 0.1M
--    $1,800,000 = 1.8M
--
--  DCS type name strings must match exactly what DCS returns
--  from event.weapon:getTypeName() or Unit:getTypeName().
--  Use the DCS lua console or Tacview to verify names.
-- ============================================================

COST_CONFIG = {}

-- ============================================================
--  DISPLAY SETTINGS
-- ============================================================
COST_CONFIG.display = {
    intervalSeconds = 300,       -- Auto-display interval (5 min)
    displayDuration = 20,        -- On-screen duration in seconds
    f10MenuName     = "Show Mission Score",
}

-- ============================================================
--  PLAYER AIRCRAFT COSTS
--  Deducted when aircraft is destroyed or pilot ejects.
--  NOT deducted if aircraft lands at a blue airfield.
--  Values = approximate real-world flyaway cost in M USD.
-- ============================================================
COST_CONFIG.aircraftCost = {
    ["A-10CII"]         = 18.0,  -- A-10C II (~$18M unit cost)
    ["A-10C"]           = 12.0,
    ["F-16C_50"]        = 25.0,  -- F-16C Block 50 (~$25M)
    ["F-15C"]           = 30.0,
    ["F-15E"]           = 43.0,
    ["FA-18C_hornet"]   = 29.0,
    ["AV8BNA"]          = 24.0,
    ["Su-25T"]          = 11.0,
    ["default"]         = 15.0,  -- Fallback for any unlisted aircraft
}

-- ============================================================
--  MUNITION COSTS  (deducted per S_EVENT_SHOT)
--
--  IMPORTANT — how DCS fires events:
--    Missiles/bombs : one event per weapon released       ✓ per-round cost is correct
--    Rockets        : one event per rocket fired          ✓ per-round cost is correct
--    Guns           : one event per trigger pull (~50 rds
--                     for GAU-8 burst) — cost reflects
--                     a burst, not a single shell.
--
--  Values = approximate unit procurement cost in M USD.
-- ============================================================
COST_CONFIG.munitionCost = {

    -- ── Air-to-Air Missiles ──────────────────────────────────
    ["AIM-9X"]              = 0.472,  -- Sidewinder Block II
    ["AIM-9M"]              = 0.300,
    ["AIM-9L"]              = 0.200,

    -- ── Air-to-Ground Missiles ───────────────────────────────
    ["AGM-65D"]             = 0.070,  -- Maverick IR
    ["AGM-65G"]             = 0.070,  -- Maverick IR (warhead variant)
    ["AGM-65H"]             = 0.110,  -- Maverick CCD
    ["AGM-65K"]             = 0.280,  -- Maverick AGM datalink
    ["AGM-65L"]             = 0.300,  -- Maverick laser
    ["AGM-88C"]             = 0.284,  -- HARM

    -- ── Guided Bombs (Paveway series) ────────────────────────
    ["GBU-10"]              = 0.020,  -- 2000 lb Paveway II
    ["GBU-12"]              = 0.019,  -- 500 lb Paveway II
    ["GBU-16"]              = 0.020,  -- 1000 lb Paveway II

    -- ── Guided Bombs (JDAM series) ───────────────────────────
    ["GBU-31"]              = 0.025,  -- JDAM 2000 lb
    ["GBU-31(V)3/B"]        = 0.025,  -- JDAM 2000 lb penetrator variant
    ["GBU-32"]              = 0.022,  -- JDAM 1000 lb
    ["GBU-38"]              = 0.021,  -- JDAM 500 lb
    ["GBU-54"]              = 0.028,  -- Laser JDAM 500 lb

    -- ── Cluster Bombs ────────────────────────────────────────
    ["CBU-87"]              = 0.014,  -- CEM unguided cluster
    ["CBU-97"]              = 0.360,  -- SFW sensor-fuzed (expensive)
    ["CBU-103"]             = 0.370,  -- SFW with WCMD guidance
    ["CBU-105"]             = 0.400,  -- SFW WCMD (most capable)

    -- ── Unguided Bombs ───────────────────────────────────────
    ["Mk_82"]               = 0.004,  -- 500 lb iron bomb
    ["Mk_82AIR"]            = 0.005,  -- 500 lb retarded (BSU-49 fin)
    ["Mk_82SE"]             = 0.005,  -- 500 lb Snake Eye retarded
    ["Mk_84"]               = 0.016,  -- 2000 lb iron bomb
    ["BDU-50LD"]            = 0.001,  -- Practice bomb (token cost)
    ["BDU-50HD"]            = 0.001,

    -- ── Rockets (cost per individual rocket fired) ───────────
    --  DCS fires one S_EVENT_SHOT per rocket.
    ["Hydra-70 M151"]       = 0.002,  -- FFAR HE
    ["Hydra-70 M229"]       = 0.002,  -- FFAR HE (heavier)
    ["Hydra-70 M247"]       = 0.002,  -- FFAR HEAT
    ["Hydra-70 WTU-1/B"]    = 0.001,  -- Practice rocket
    ["FFAR Mk5 HEAT"]       = 0.002,
    ["Zuni Mk71"]           = 0.004,  -- 5" Zuni

    -- ── Gun (cost per trigger pull — approx 50-rd GAU-8 burst)
    --  GAU-8 round ~$50 each x ~50 rds = ~$2,500 per burst
    ["GAU-8/A Avenger"]     = 0.0025,

    -- ── Default fallback ─────────────────────────────────────
    ["default"]             = 0.010,  -- Unknown munition
}

-- ============================================================
--  ENEMY UNIT KILL VALUES  (credited on confirmed kill)
--  Values tuned for gameplay — high-value threats reward more.
-- ============================================================
COST_CONFIG.killValue = {

    -- ── Enemy Fixed-Wing Aircraft ────────────────────────────
    ["MiG-29A"]             = 8,
    ["MiG-29S"]             = 10,
    ["MiG-29G"]             = 9,
    ["Su-27"]               = 12,
    ["Su-30"]               = 14,
    ["Su-33"]               = 15,
    ["Su-25"]               = 7,
    ["Su-25T"]              = 9,
    ["MiG-21Bis"]           = 5,
    ["MiG-23MLD"]           = 6,
    ["J-11A"]               = 13,

    -- ── Enemy Helicopters ────────────────────────────────────
    ["Mi-24V"]              = 6,   -- Hind gunship
    ["Mi-8MT"]              = 3,   -- Hip transport
    ["SA342M"]              = 4,   -- Gazelle armed
    ["SA342L"]              = 3,

    -- ── SAM Systems ──────────────────────────────────────────
    ["S-300PS 40B6M tr"]    = 18,  -- S-300 launch vehicle
    ["S-300PS 64H6E sr"]    = 20,  -- S-300 search radar
    ["SA-11 Buk LN"]        = 12,  -- SA-11 launcher
    ["SA-11 Buk SR"]        = 10,  -- SA-11 search radar
    ["SA-6 Kub BM"]         = 9,   -- SA-6 launcher
    ["SA-6 Kub SR"]         = 8,   -- SA-6 radar
    ["Osa 9A33 ln"]         = 7,   -- SA-8 Gecko
    ["2S6 Tunguska"]        = 8,   -- SA-19 combined gun/SAM
    ["ZSU-23-4 Shilka"]     = 5,
    ["Strela-10M3"]         = 6,   -- SA-13 Gopher (spawned by sam_setup)
    ["Strela-1 9P31"]       = 5,   -- SA-9 Gaskin (spawned by sam_setup)
    ["SA-3 S-125 TR"]       = 8,   -- SA-3 track radar
    ["5p73 s-125 ln"]       = 7,   -- SA-3 launcher
    ["SA-18 Igla manpad"]   = 1.0, -- MANPADS (defense_setup / sd_mission air defense)
    ["Ural-375 ZU-23"]      = 0.8, -- ZU-23 AAA gun truck

    -- ── Ballistic Missile / S&D targets ──────────────────────
    ["Scud_B"]              = 5.0, -- Scud-B TEL (primary S&D missile mission target)

    -- ── Tanks & Heavy AFVs ───────────────────────────────────
    ["T-55"]                = 2.0, -- older tank (convoy)
    ["T-72B"]               = 3,
    ["T-72B3"]              = 4,
    ["T-80UD"]              = 4,
    ["T-90"]                = 5,
    ["CHAP_T64BV"]          = 4.0, -- T-64BV Type 2017 (CH mod, convoy)
    ["BMP-1"]               = 2,
    ["BMP-2"]               = 2,
    ["BMP-3"]               = 3,
    ["BTR-70"]              = 2,
    ["BTR-80"]              = 2,
    ["BRDM-2"]              = 1,
    ["ZSU_57_2"]            = 3,
    ["AAV7"]                = 2,
    ["CHAP_MATV"]           = 1.0, -- M-ATV (CH mod, convoy)

    -- ── Logistics / Soft Targets ─────────────────────────────
    ["ATZ-5"]               = 0.5, -- fuel truck (convoy)
    ["ATZ-10"]              = 0.5, -- fuel truck (convoy)
    ["Ural-375 PBU"]        = 0.5, -- command vehicle (convoy, aka Ural-4320 MCC in ME)
    ["Ural-4320-31"]        = 0.5, -- cargo truck
    ["Ural-4320T"]          = 0.5,
    ["Ural-375"]            = 0.5,
    ["KAMAZ Truck"]         = 0.5,
    ["GAZ-66"]              = 0.3,
    ["GAZ-3308"]            = 0.3,
    ["ZIL-135"]             = 0.5,
    ["MTLB"]                = 1,

    -- ── Infantry ─────────────────────────────────────────────
    ["Soldier AK"]          = 0.1,
    ["Soldier RPG"]         = 0.1,
    ["Infantry AK Ins"]     = 0.1, -- AKM insurgent

    -- ── Naval ────────────────────────────────────────────────
    ["MOSCOW"]              = 30,  -- Slava-class cruiser
    ["Neustrashimy"]        = 20,
    ["Rezky"]               = 15,
    ["SOM"]                 = 5,   -- Small patrol craft

    -- ── Default fallback ─────────────────────────────────────
    ["default"]             = 1,
}

-- ============================================================
--  END OF CONFIGURATION
-- ============================================================
