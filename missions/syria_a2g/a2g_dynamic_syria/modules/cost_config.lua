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
    ["MiG-29A"]             = 25,   -- ~$24M (2026 estimate)
    ["MiG-29S"]             = 35,   -- modernized variant premium
    ["MiG-29G"]             = 30,
    ["Su-27"]               = 45,   -- ~$30M in 1997; inflation-adjusted ~$45M
    ["Su-30"]               = 55,   -- ~$34M export price; modern equivalent ~$55M
    ["Su-33"]               = 60,   -- naval variant premium over Su-27
    ["Su-25"]               = 18,   -- Frogfoot attack aircraft
    ["Su-25T"]              = 25,   -- upgraded Frogfoot
    ["MiG-21Bis"]           = 12,   -- late variant of aging 1960s airframe
    ["MiG-23MLD"]           = 18,   -- late-model swing-wing
    ["J-11A"]               = 50,   -- Chinese Su-27 derivative

    -- ── Enemy Helicopters ────────────────────────────────────
    ["Mi-24V"]              = 12,   -- Hind gunship
    ["Mi-8MT"]              = 8,    -- Hip transport
    ["SA342M"]              = 5,    -- Gazelle armed
    ["SA342L"]              = 4,

    -- ── SAM Systems ──────────────────────────────────────────
    -- All values: per vehicle (not per battery), 2026 USD millions.
    -- Sources: battery contract prices ÷ vehicle count, export deal inflation-adjustment,
    -- ForecastInternational archives, Ukraine war damage assessments.
    ["S-300PS 64H6E sr"]    = 18,   -- Big Bird phased-array search radar; most expensive S-300 vehicle
    ["S-300PS 40B6M tr"]    = 12,   -- S-300PS launcher; ~$120-150M battery ÷ ~10 vehicles
    ["SA-11 Buk LN"]        = 14,   -- 9A310 TELAR; ~$100M battery ÷ 4 TELARs + support
    ["SA-11 Buk SR"]        = 8,    -- 9S18 Snow Drift acquisition radar
    ["SA-6 Kub BM"]         = 7,    -- 2K12 Kub launcher vehicle (user-confirmed benchmark)
    ["SA-6 Kub SR"]         = 8.5,  -- 1S91 SURN radar/illuminator; nerve center of battery
    ["2S6 Tunguska"]        = 15,   -- ForecastInternational explicit cite: $15.1M unit cost
    ["Osa 9A33 ln"]         = 9,    -- SA-8 Gecko; all-in-one (radar + missiles on one chassis)
    ["ZSU-23-4 Shilka"]     = 2.5,  -- Libya 1972 export price × CPI to 2026
    ["Strela-10M3"]         = 5,    -- SA-13 Gopher on MT-LB chassis
    ["Strela-1 9P31"]       = 3.5,  -- SA-9 Gaskin on BRDM-2; older/simpler seeker than SA-13
    ["SA-3 S-125 TR"]       = 4,    -- SNR-125 Low Bow fire-control radar
    ["5p73 s-125 ln"]       = 2.5,  -- SA-3 4-rail launcher (passive; fully dependent on Low Bow)
    ["SNR_75V tr"]          = 4,    -- SA-2 Fan Song radar; India battery deal backs out to ~$4M
    ["S_75M_Volhov"]        = 3,    -- SA-2 S-75 launcher; India deal ~$3M/launcher ex-missiles
    ["SA-18 Igla manpad"]   = 0.35, -- Per gripstock + 2-missile set; complete 9K38 system ~$528K
    ["Ural-375 ZU-23"]      = 0.25, -- ZU-23-2 gun ($15-20K) + Ural truck + military markup

    -- ── Ballistic Missile / S&D targets ──────────────────────
    ["Scud_B"]              = 6,    -- 9P117 MAZ-543 TEL; HIMARS launcher ($5-6M) as comparator

    -- ── Tanks & Heavy AFVs ───────────────────────────────────
    ["T-90"]                = 5.0,  -- T-90A ~$4.15M FY2011 Russian MOD; T-90M ~$5M in 2026
    ["T-80UD"]              = 3.5,  -- Pakistan paid $650M for 320 (late 1990s) × CPI to 2026
    ["T-72B3"]              = 3.0,  -- ~52M ruble modernization package + base vehicle cost
    ["T-72B"]               = 2.0,  -- Late-Soviet production; below B3 for older FCS/ERA
    ["CHAP_T64BV"]          = 2.5,  -- T-64BV Type 2017; no active production line
    ["T-55"]                = 0.35, -- Surplus; real transaction prices $200-500K
    ["BMP-3"]               = 3.2,  -- Greek export purchase data; most reliable IFV figure
    ["BMP-2"]               = 1.2,  -- Finland €350K/unit (2016) × CPI to 2026
    ["BMP-1"]               = 0.5,  -- Germany sold surplus to Greece at ~€25K (demil); combat-ready higher
    ["BTR-80"]              = 1.2,  -- Consistent across multiple sources
    ["BTR-70"]              = 0.4,  -- Surplus only; no current production
    ["BRDM-2"]              = 0.25, -- Light 4×4 scout; abundant ex-Soviet surplus
    ["ZSU_57_2"]            = 0.6,  -- 1950s twin-57mm, no radar; surplus value only
    ["AAV7"]                = 3.5,  -- Romania 2024 transfer ~$4.77M; older BAE contract ~$2.3M; midpoint
    ["CHAP_MATV"]           = 0.9,  -- FY2009-11 procurement $587K × 1.5 CPI to 2026
    ["MTLB"]                = 0.4,  -- Light tracked transporter; common ex-Soviet surplus

    -- ── Logistics / Soft Targets ─────────────────────────────
    -- Real replacement costs are much lower than previous values.
    -- Trucks are cheap; convoy kills are rewarded by volume, not per-unit price.
    ["ATZ-5"]               = 0.15, -- Military fuel tanker on Zil base
    ["ATZ-10"]              = 0.15,
    ["Ural-375 PBU"]        = 0.15, -- Command vehicle on Ural chassis
    ["Ural-4320-31"]        = 0.10, -- Standard military cargo truck
    ["Ural-4320T"]          = 0.10,
    ["Ural-375"]            = 0.10,
    ["KAMAZ Truck"]         = 0.10,
    ["kamaz_tent_civil"]    = 0.10, -- civilian-style KAMAZ with tent cover (confirmed type name from log)
    ["GAZ-66"]              = 0.08,
    ["GAZ-3308"]            = 0.08,
    ["ZIL-135"]             = 0.30, -- Specialized 8×8 heavy military vehicle; not standard cargo

    -- ── Infantry ─────────────────────────────────────────────
    ["Soldier AK"]          = 0.1,
    ["Soldier RPG"]         = 0.1,
    ["Infantry AK Ins"]     = 0.1,  -- AKM insurgent

    -- ── Naval ────────────────────────────────────────────────
    ["MOSCOW"]              = 30,   -- Slava-class cruiser
    ["Neustrashimy"]        = 20,
    ["Rezky"]               = 15,
    ["SOM"]                 = 5,    -- Small patrol craft

    -- ── Default fallback ─────────────────────────────────────
    ["default"]             = 1,
}

-- ============================================================
--  END OF CONFIGURATION
-- ============================================================
