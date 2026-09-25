-- Which unit types each coalition fields per role: { type, weight } lists for a weighted
-- pick. The ONLY file that knows red from blue — Russian kit on Blue is just a line here.
-- Every type must exist in UNIT_POOL.ground (checked at load). The roster role is our
-- decision and need not match the pool's own role tag. Plain data, no logic.
--
-- Red: modern Russian Northern Fleet airbase defense. Blue: Nordic bases, using the
-- closest single-vehicle DCS stand-ins, Russian or Chinese kit included when it matches
-- the real system's coverage better — NASAMS, IRIS-T SLS, RBS 70, ASRAD-R and CV90 AA
-- are missing or multi-vehicle; multi-vehicle SAM sites come with stage 3's site
-- recipes. (2026-09-23)

COALITION_ROSTER = {
    red = {
        -- ZU-23-2: at every Russian airfield
        towed_anti_aircraft_gun   = { { "ZU-23 Emplacement", 3 }, { "ZU-23 Emplacement Closed", 2 } },
        -- Shilka (M4 upgrade) still in service; truck-mounted ZU-23 is the cheap mobile gun
        mobile_anti_aircraft_gun  = { { "ZSU-23-4 Shilka", 2 }, { "Ural-375 ZU-23", 1 } },
        -- a towed-gun group that ends up on a road: the ZU-23 on a truck
        truck_mounted_anti_aircraft_gun = { { "Ural-375 ZU-23", 1 } },
        -- Strela-1 left out: retired
        infrared_missile_launcher = { { "Strela-10M3", 1 } },
        -- Pantsir: standard airbase point defense, sits with the S-400s at Olenya and
        -- Severomorsk. Northern Fleet fields the Arctic Tor-M2DT. Osa left out: older army system.
        radar_missile_launcher    = { { "CHAP_PantsirS1", 3 }, { "CHAP_TorM2", 2 }, { "Tor 9A331", 1 },
                                      { "2S6 Tunguska", 1 } },
        shoulder_launched_missile = { { "SA-18 Igla-S manpad", 3 }, { "SA-18 Igla manpad", 1 } },
        infantry                  = { { "Soldier AK", 2 }, { "Infantry AK ver2", 1 }, { "Infantry AK ver3", 1 },
                                      { "Soldier RPG", 1 } },
        -- ── convoys (data/convoy_recipes.lua; Red only for now) ──
        cargo_truck               = { { "Ural-4320-31", 3 }, { "KAMAZ Truck", 2 }, { "GAZ-66", 1 } },
        fuel_truck                = { { "ATZ-10", 2 }, { "ATZ-5", 1 }, { "TZ-22_KrAZ", 1 } },
        armored_personnel_carrier = { { "BTR-82A", 2 }, { "BTR-80", 1 } },
        -- escorts an important column: gun or infrared missiles on a tracked chassis
        mobile_air_defense_vehicle = { { "ZSU-23-4 Shilka", 1 }, { "Strela-10M3", 1 } },
    },
    blue = {
        -- Finland fields ZU-23-2 (23 ItK 61); rosters are per coalition, so it shows up at
        -- Norwegian and Swedish fields too
        towed_anti_aircraft_gun   = { { "ZU-23 Emplacement", 3 }, { "ZU-23 Emplacement Closed", 1 } },
        -- Gepard for Sweden's CV90 AA (40 mm) and Finland's 35 mm Skyguard guns
        mobile_anti_aircraft_gun  = { { "Gepard", 3 }, { "Vulcan", 1 } },
        -- a towed-gun group that ends up on a road: the ZU-23 on a truck
        truck_mounted_anti_aircraft_gun = { { "Ural-375 ZU-23", 1 } },
        -- for ASRAD-R and vehicle-mounted RBS 70. Chaparral left out: retired
        infrared_missile_launcher = { { "M1097 Avenger", 2 }, { "M6 Linebacker", 1 } },
        -- Roland for Finland's Crotale NG (ITO 90M), Tor M2 for IRIS-T SLS. HQ-7B (a Crotale
        -- copy) left out: its launcher has no search radar of its own in DCS and is
        -- unreliable without the separate HQ-7 search radar vehicle, so it waits for
        -- multi-vehicle groups (stage 3 site recipes)
        radar_missile_launcher    = { { "Roland ADS", 2 }, { "CHAP_TorM2", 1 } },
        -- RBS 70 isn't in DCS; Finland fielded Igla until recently
        shoulder_launched_missile = { { "Soldier stinger", 3 }, { "SA-18 Igla-S manpad", 1 } },
        infantry                  = { { "Soldier M4", 3 }, { "Soldier M249", 1 } },
    },
}

-- Which SAM and early-warning systems each coalition fields per layer: { recipe, weight }
-- where recipe is a key of SAM_SITE_RECIPE (data/sam_site_recipes.lua) of that layer.
-- Target feel: a lived-in, mixed-age network like the Ukraine war, from what DCS has.
COALITION_SAM_SYSTEMS = {
    red = {
        -- S-300PS stands in for S-300/S-400; few sites, around what Russia values most
        long_range    = { { "SA-10", 1 } },
        -- Buk is the army workhorse; Kub is older stock out of storage
        medium_range  = { { "SA-11", 3 }, { "SA-6", 1 } },
        short_range   = { { "SA-8", 2 }, { "SA-15", 1 } },
        early_warning = { { "1L13", 1 }, { "55G6", 1 } },
    },
    blue = {
        -- Sweden fields Patriot, plus US deployments. SA-10: Ukraine fights with S-300,
        -- and NATO's Greece, Bulgaria and Slovakia have operated it — and in DCS it holds
        -- up where the Patriot (sector radar, launch logic) underperforms
        long_range    = { { "Patriot", 2 }, { "SA-10", 1 } },
        -- NASAMS: Norway's and Finland's backbone; IRIS-T for Sweden's systems; Buk is
        -- real for Finland (ITO 96, to 2015) and Ukraine, and the most reliable medium
        -- system Blue has in DCS; Hawk is older reserve stock
        medium_range  = { { "NASAMS", 3 }, { "IRIS-T SLM", 2 }, { "SA-11", 2 }, { "Hawk", 1 } },
        -- Osa and Tor: Greece (NATO) and Ukraine field both; Tor also shoots down
        -- incoming missiles. Rapier left out: useless against low flyers in DCS
        short_range   = { { "SA-8", 2 }, { "SA-15", 1 }, { "Roland", 1 } },
        early_warning = { { "FPS-117", 1 } },
    },
}

-- Which aircraft each coalition sends on each air mission type: { type, weight }. Every
-- type needs an AIRCRAFT_PROFILE (data/aircraft_profiles.lua) and a loadout for that
-- mission type (data/aircraft_loadouts.lua, generated). Independent of the parked
-- aircraft: any base whose class the profile allows can launch it. Mission types not
-- built yet (data/air_tasking.lua) have rosters already, so building them is one flag.
COALITION_AIRCRAFT = {
    red = {
        -- Su-24M: Severomorsk naval aviation; Su-34: the modern front-line bomber;
        -- Tu-22M3: Olenya's long-range bombers, carpet-bombing airfields and large sites
        strike                      = { { "Su-34", 3 }, { "Su-24M", 2 }, { "Tu-22M3", 1 } },
        airfield_strike             = { { "Su-34", 2 }, { "Su-24M", 2 }, { "Tu-22M3", 2 } },
        suppression_of_air_defenses = { { "Su-34", 2 }, { "Su-24M", 1 } },
        interdiction                = { { "Su-34", 1 } },
    },
    blue = {
        -- F/A-18C for Finland's Hornets, F-16C for Norway's F-35 and Sweden's Gripen (neither
        -- in DCS), F-15E and B-1B for US reinforcements
        strike                      = { { "FA-18C_hornet", 3 }, { "F-16C_50", 3 }, { "F-15ESE", 2 }, { "B-1B", 1 } },
        airfield_strike             = { { "FA-18C_hornet", 2 }, { "F-16C_50", 2 }, { "F-15ESE", 2 }, { "B-1B", 1 } },
        suppression_of_air_defenses = { { "F-16C_50", 2 }, { "FA-18C_hornet", 1 } },
        destruction_of_air_defenses = { { "F-15ESE", 1 }, { "F-16C_50", 1 }, { "FA-18C_hornet", 1 } },
        interdiction                = { { "F-15ESE", 2 }, { "B-1B", 1 } },
        close_air_support           = { { "A-10C_2", 2 }, { "F-16C_50", 1 }, { "FA-18C_hornet", 1 } },
    },
}

-- What each coalition's fixed ground targets are made of, per role: { type, weight }.
-- Roles are named by data/fixed_ground_target_recipes.lua. Kept apart from
-- COALITION_ROSTER because these include static objects and parked aircraft, not only
-- ground units. A recipe part says whether its role spawns as units or static objects:
--   unit           type must be in UNIT_POOL.ground
--   static_object  type must be in UNIT_POOL.static (structures), .ground (a parked
--                  vehicle), .plane or .helicopter (a parked aircraft)
-- Structures are core DCS objects only (no M92 asset-pack tents / containers).
COALITION_FIXED_GROUND_TARGET_ROSTER = {
    red = {
        -- ── structures ──
        barracks              = { { "Barracks 2", 3 }, { "FARP Tent", 2 } },
        command_building      = { { "Military staff", 2 }, { ".Command Center", 1 }, { "FARP CP Blindage", 1 } },
        communications_tower  = { { "Comms tower M", 3 }, { "TV tower", 1 } },
        warehouse             = { { "Warehouse", 2 }, { "Small werehouse 1", 1 }, { "Small werehouse 2", 1 } },
        ammunition_storage    = { { ".Ammunition depot", 2 }, { "FARP Ammo Dump Coating", 1 } },
        fuel_storage_tank     = { { "Fuel tank", 2 }, { "Tank", 2 } },
        supply_containers     = { { "Container brown", 2 }, { "Container red 1", 1 }, { "Container white", 1 } },
        generator             = { { "GeneratorF", 1 } },
        -- ── parked vehicles ──
        supply_truck          = { { "Ural-4320-31", 2 }, { "KAMAZ Truck", 2 }, { "GAZ-66", 1 } },
        fuel_truck            = { { "ATZ-10", 2 }, { "ATZ-5", 1 }, { "TZ-22_KrAZ", 1 } },
        command_vehicle       = { { "Ural-375 PBU", 2 }, { "SKP-11", 1 } },
        -- ── ground units ──
        infantry              = { { "Soldier AK", 2 }, { "Infantry AK ver2", 1 }, { "Infantry AK ver3", 1 },
                                  { "Soldier RPG", 1 } },
        infantry_carrier      = { { "BTR-82A", 2 }, { "BMP-2", 2 }, { "BMP-3", 1 }, { "MTLB", 1 } },
        main_battle_tank      = { { "T-72B3", 3 }, { "T-80B", 2 }, { "T-90", 1 } },
        -- one type per battery (recipe same_type): tube or rocket artillery
        artillery_piece       = { { "SAU Msta", 3 }, { "SAU Gvozdika", 1 }, { "Grad-URAL", 2 },
                                  { "Uragan_BM-27", 1 } },
        -- ── parked aircraft (Northern Fleet aviation and the long-range bombers at Olenya) ──
        parked_fighter        = { { "Su-27", 3 }, { "MiG-31", 3 }, { "MiG-29S", 1 }, { "Su-30", 1 } },
        parked_strike_aircraft = { { "Su-24M", 2 }, { "Su-34", 2 } },
        parked_bomber         = { { "Tu-22M3", 3 }, { "Tu-95MS", 1 }, { "Tu-142", 1 } },
        parked_transport      = { { "An-26B", 2 }, { "IL-76MD", 1 } },
        parked_helicopter     = { { "Mi-8MT", 3 }, { "Ka-27", 1 }, { "Mi-24P", 1 } },
    },
    blue = {
        -- ── structures ──
        barracks              = { { "Barracks 2", 3 }, { "FARP Tent", 2 } },
        command_building      = { { "Military staff", 2 }, { ".Command Center", 1 }, { "FARP CP Blindage", 1 } },
        communications_tower  = { { "Comms tower M", 3 }, { "TV tower", 1 } },
        warehouse             = { { "Warehouse", 2 }, { "Small werehouse 1", 1 }, { "Small werehouse 2", 1 } },
        ammunition_storage    = { { ".Ammunition depot", 2 }, { "FARP Ammo Dump Coating", 1 } },
        fuel_storage_tank     = { { "Fuel tank", 2 }, { "Tank", 2 } },
        supply_containers     = { { "Container brown", 2 }, { "Container red 1", 1 }, { "Container white", 1 } },
        generator             = { { "GeneratorF", 1 } },
        -- ── parked vehicles ──
        supply_truck          = { { "M 818", 2 }, { "CHAP_M1083", 1 }, { "Land_Rover_101_FC", 1 } },
        fuel_truck            = { { "M978 HEMTT Tanker", 1 } },
        command_vehicle       = { { "Land_Rover_101_FC", 1 }, { "Hummer", 1 } },
        -- ── ground units ──
        infantry              = { { "Soldier M4", 3 }, { "Soldier M249", 1 } },
        -- Marder for Norway's and Sweden's CV90, Stryker for Finland's Patria AMV; M113
        -- still serves in Norway and Finland
        infantry_carrier      = { { "Marder", 2 }, { "M1126 Stryker ICV", 2 }, { "M-113", 1 } },
        -- Leopard 2 in all three armies (Strv 122 ≈ 2A5)
        main_battle_tank      = { { "Leopard-2A5", 2 }, { "leopard-2A4", 2 }, { "Leopard-2", 1 } },
        -- M109 for Norway's K9, Dana for Sweden's wheeled Archer; Finland fields M270 MLRS
        artillery_piece       = { { "M-109", 2 }, { "SpGH_Dana", 1 }, { "MLRS", 1 }, { "CHAP_M142_GMLRS_M31", 1 } },
        -- ── parked aircraft (Nordic air forces plus allied reinforcements) ──
        -- F-16 for Norway's F-35 / Sweden's Gripen (neither in DCS), Hornet for Finland
        parked_fighter        = { { "FA-18C_hornet", 3 }, { "F-16C_50", 2 }, { "F-15C", 1 } },
        parked_strike_aircraft = { { "F-15ESE", 2 }, { "FA-18C_hornet", 1 } },
        -- US bomber task force deployments to Norway; stands in for Evenes' P-8s too
        parked_bomber         = { { "B-1B", 2 }, { "B-52H", 1 } },
        parked_transport      = { { "C-130", 2 }, { "C-130J-30", 1 } },
        parked_helicopter     = { { "UH-60A", 2 }, { "CH-47D", 1 }, { "SH-60B", 1 } },
    },
}
