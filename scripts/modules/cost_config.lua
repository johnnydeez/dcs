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
    ["A-10CII"]         = 65.0,  -- A-10C II (no longer produced; estimated today's replacement cost ~$50-80M)
    ["A-10C"]           = 55.0,  -- A-10C (earlier avionics suite)
    ["F-16C_50"]        = 65.0,  -- F-16C Block 50 (~$60-70M in today's dollars; newer Block 70/72 is $80-90M)
    ["F-15C"]           = 65.0,  -- F-15C (out of production; F-15EX replacement is ~$94M)
    ["F-15E"]           = 75.0,  -- F-15E Strike Eagle (~$65-80M inflation-adjusted)
    ["FA-18C_hornet"]   = 50.0,  -- F/A-18C legacy Hornet (out of production; Super Hornet is $65M+)
    ["AV8BNA"]          = 40.0,  -- AV-8B Harrier II+
    ["Su-25T"]          = 25.0,  -- Su-25T Frogfoot (Russian procurement pricing)
    ["default"]         = 40.0,  -- Fallback for any unlisted aircraft
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
    -- DCS getTypeName() returns underscores where names have hyphens.
    -- Hyphen form kept as alias until confirmed via SHOT log.
    ["AIM_9X"]              = 0.472,  ["AIM-9X"] = 0.472,  -- Sidewinder Block II
    ["AIM_9M"]              = 0.300,  ["AIM-9M"] = 0.300,
    ["AIM_9L"]              = 0.200,  ["AIM-9L"] = 0.200,

    -- ── Air-to-Ground Missiles ───────────────────────────────
    ["AGM_65D"]             = 0.070,  ["AGM-65D"] = 0.070,  -- Maverick IR
    ["AGM_65G"]             = 0.070,  ["AGM-65G"] = 0.070,  -- Maverick IR (warhead variant)
    ["AGM_65H"]             = 0.110,  ["AGM-65H"] = 0.110,  -- Maverick CCD
    ["AGM_65K"]             = 0.280,  ["AGM-65K"] = 0.280,  -- Maverick AGM datalink
    ["AGM_65L"]             = 0.300,  ["AGM-65L"] = 0.300,  -- Maverick laser
    ["AGM_88C"]             = 0.284,  ["AGM-88C"] = 0.284,  -- HARM

    -- ── Guided Bombs (Paveway series) ────────────────────────
    ["GBU_10"]              = 0.020,  ["GBU-10"] = 0.020,  -- 2000 lb Paveway II
    ["GBU_12"]              = 0.019,  ["GBU-12"] = 0.019,  -- 500 lb Paveway II
    ["GBU_16"]              = 0.020,  ["GBU-16"] = 0.020,  -- 1000 lb Paveway II

    -- ── Guided Bombs (JDAM series) ───────────────────────────
    ["GBU_31"]              = 0.025,  ["GBU-31"] = 0.025,  -- JDAM 2000 lb
    -- Penetrator variant: engine shows GBU-38(V)1/B → GBU_38, so this follows same pattern
    ["GBU_31_V_3B"]         = 0.025,  ["GBU_31(V)3/B"] = 0.025,  ["GBU-31(V)3/B"] = 0.025,
    ["GBU_32"]              = 0.022,  ["GBU-32"] = 0.022,  -- JDAM 1000 lb
    ["GBU_38"]              = 0.021,  ["GBU-38"] = 0.021,  -- JDAM 500 lb
    ["GBU_54"]              = 0.028,  ["GBU-54"] = 0.028,  -- Laser JDAM 500 lb

    -- ── Cluster Bombs ────────────────────────────────────────
    ["CBU_87"]              = 0.014,  -- CEM unguided cluster (confirmed underscore)
    ["CBU_97"]              = 0.360,  -- SFW sensor-fuzed (confirmed underscore from log)
    ["CBU_103"]             = 0.370,  -- SFW with WCMD guidance
    ["CBU_105"]             = 0.400,  -- SFW WCMD (most capable)

    -- ── Unguided Bombs ───────────────────────────────────────
    ["Mk_82"]               = 0.004,  -- 500 lb iron bomb (confirmed underscore)
    ["Mk_82AIR"]            = 0.005,  -- 500 lb retarded (BSU-49 fin)
    ["Mk_82SE"]             = 0.005,  -- 500 lb Snake Eye retarded
    ["Mk_84"]               = 0.016,  -- 2000 lb iron bomb (confirmed underscore from log)
    ["BDU_50LD"]            = 0.001,  ["BDU-50LD"] = 0.001,  -- Practice bomb (token cost)
    ["BDU_50HD"]            = 0.001,  ["BDU-50HD"] = 0.001,

    -- ── Rockets (cost per individual rocket fired) ───────────
    --  DCS fires one S_EVENT_SHOT per rocket.
    --  Names with spaces: hyphen→underscore uncertain, both forms kept.
    ["Hydra_70 M151"]       = 0.002,  ["Hydra-70 M151"] = 0.002,  -- FFAR HE
    ["Hydra_70 M229"]       = 0.002,  ["Hydra-70 M229"] = 0.002,  -- FFAR HE (heavier)
    ["Hydra_70 M247"]       = 0.002,  ["Hydra-70 M247"] = 0.002,  -- FFAR HEAT
    ["Hydra_70 WTU-1/B"]    = 0.001,  ["Hydra-70 WTU-1/B"] = 0.001,  -- Practice rocket
    ["FFAR Mk5 HEAT"]       = 0.002,  -- no hyphens, probably correct as-is
    ["Zuni Mk71"]           = 0.004,  -- no hyphens, probably correct as-is

    -- ── Gun (cost per trigger pull — approx 50-rd GAU-8 burst)
    --  GAU-8 round ~$50 each x ~50 rds = ~$2,500 per burst
    --  Slash/space in name: form uncertain, both kept.
    ["GAU_8/A Avenger"]     = 0.0025, ["GAU-8/A Avenger"] = 0.0025,

    -- ── Default fallback ─────────────────────────────────────
    ["default"]             = 0.010,  -- Unknown munition
}

-- ============================================================
--  ENEMY UNIT KILL VALUES  (credited on confirmed kill)
--  Values tuned for gameplay — high-value threats reward more.
-- ============================================================
COST_CONFIG.killValue = {

    -- ── Enemy Fixed-Wing Aircraft ────────────────────────────
    ["MiG-29A"]             = 25,  -- ~$24M (2026 estimate)
    ["MiG-29S"]             = 35,  -- modernized variant premium
    ["MiG-29G"]             = 30,
    ["Su-27"]               = 45,  -- ~$30M in 1997; inflation-adjusted ~$45M today
    ["Su-30"]               = 55,  -- ~$34M export price; modern equivalent ~$55M
    ["Su-33"]               = 60,  -- naval variant premium over Su-27
    ["Su-25"]               = 18,  -- Frogfoot attack aircraft
    ["Su-25T"]              = 25,  -- upgraded Frogfoot
    ["MiG-21Bis"]           = 12,  -- late variant of aging 1960s airframe
    ["MiG-23MLD"]           = 18,  -- late-model swing-wing
    ["J-11A"]               = 50,  -- Chinese Su-27 derivative

    -- ── Enemy Helicopters ────────────────────────────────────
    ["Mi-24V"]              = 12,  -- Hind gunship (~$12M)
    ["Mi-8MT"]              = 8,   -- Hip transport (~$8M)
    ["SA342M"]              = 5,   -- Gazelle armed (~$4-6M)
    ["SA342L"]              = 4,

    -- ── SAM Systems ──────────────────────────────────────────
    ["S-300PS 40B6M tr"]    = 18,  -- S-300 launch vehicle
    ["S-300PS 64H6E sr"]    = 20,  -- S-300 search radar
    ["SA-11 Buk LN"]        = 12,  -- SA-11 launcher
    ["SA-11 Buk SR"]        = 10,  -- SA-11 search radar
    ["SA-6 Kub BM"]         = 9,   -- SA-6 launcher
    ["SA-6 Kub SR"]         = 8,   -- SA-6 radar
    ["Osa 9A33 ln"]         = 7,   -- SA-8 Gecko
    ["2S6 Tunguska"]        = 10,  -- SA-19 combined gun/SAM (~$8-12M)
    ["ZSU-23-4 Shilka"]     = 2.0, -- radar-guided AAA (~$1-2M)
    ["Strela-10M3"]         = 6,   -- SA-13 Gopher (spawned by sam_setup)
    ["Strela-1 9P31"]       = 5,   -- SA-9 Gaskin (spawned by sam_setup)
    ["SA-3 S-125 TR"]       = 8,   -- SA-3 track radar
    ["5p73 s-125 ln"]       = 7,   -- SA-3 launcher
    ["SNR_75V tr"]          = 10,  -- SA-2 Fan Song tracking radar (type string unconfirmed)
    ["S_75M_Volhov"]        = 7,   -- SA-2 S-75 launcher (type string unconfirmed)
    ["SA-18 Igla manpad"]   = 1.0, -- MANPADS (defense_setup / sd_mission air defense)
    ["Ural-375 ZU-23"]      = 0.8, -- ZU-23 AAA gun truck

    -- ── Ballistic Missile / S&D targets ──────────────────────
    ["Scud_B"]              = 5.0, -- Scud-B TEL (primary S&D missile mission target)

    -- ── Tanks & Heavy AFVs ───────────────────────────────────
    ["T-55"]                = 0.5, -- obsolete; surplus pricing (~$0.3-0.5M)
    ["T-72B"]               = 2.5, -- ~$2M procurement; B variant slight premium
    ["T-72B3"]              = 3.5, -- modernized; reactive armor + new FCS
    ["T-80UD"]              = 4.0, -- gas turbine variant; more capable than T-72
    ["T-90"]                = 5.5, -- ~$4-7M per research; splitting the range
    ["CHAP_T64BV"]          = 3.0, -- T-64BV Type 2017 (CH mod, convoy)
    ["BMP-1"]               = 0.8, -- 1960s IFV; low surplus value
    ["BMP-2"]               = 1.5, -- upgraded IFV with 30mm autocannon
    ["BMP-3"]               = 3.2, -- confirmed ~$3.2M (Greek export pricing)
    ["BTR-70"]              = 0.5, -- aging 8x8 APC; widespread surplus
    ["BTR-80"]              = 1.2, -- confirmed ~$1.2M
    ["BRDM-2"]              = 0.4, -- light recon vehicle; cheap and obsolete
    ["ZSU_57_2"]            = 1.5, -- twin-57mm AAA; old but still dangerous
    ["AAV7"]                = 2.5, -- US amphibious APC (~$2.5M)
    ["CHAP_MATV"]           = 1.0, -- M-ATV (CH mod, convoy)

    -- ── Logistics / Soft Targets ─────────────────────────────
    ["ATZ-5"]               = 0.5, -- fuel truck (convoy)
    ["ATZ-10"]              = 0.5, -- fuel truck (convoy)
    ["Ural-375 PBU"]        = 0.5, -- command vehicle (convoy, aka Ural-4320 MCC in ME)
    ["Ural-4320-31"]        = 0.5, -- cargo truck
    ["Ural-4320T"]          = 0.5,
    ["Ural-375"]            = 0.5,
    ["KAMAZ Truck"]         = 0.5,
    ["kamaz_tent_civil"]    = 0.3,  -- civilian-style KAMAZ with tent cover (confirmed type name from log)
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
