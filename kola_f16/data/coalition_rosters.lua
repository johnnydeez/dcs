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
