-- How each AI aircraft type flies its missions: where it can take off from, how far it
-- reaches, how fast and how high it flies. Coalition-agnostic; which coalition flies what
-- is COALITION_AIRCRAFT (data/coalition_rosters.lua). Plain data, no logic.
--
--   base_classes        airbase classes (data/airbase_classes.lua) it may launch from
--   min_runway_m        longest runway at the base must be at least this long
--   parking             terminal types (DCS Term_Type) it may park on: 104 large, 72 open
--   flight_size         { min, max } aircraft per flight
--   combat_radius_km    farthest target from the launch base, with its mission load
--   cruise_speed_mps    true airspeed in transit
--   cruise_altitude_m   transit altitude, held until the descent point before the ingress.
--                       At least 7,500 m (~25k ft) for every attack flight: above guns,
--                       shoulder-launched missiles and short-range SAMs (SA-8, SA-15, Roland,
--                       ~5-6 km), so flights only have to route around what reaches higher
--   attack_altitude_m   { mission type = m }: altitude from the ingress point over the
--                       target — what's realistic for the jet and its payload, whatever the
--                       threat: unguided bombs lower, cluster bombs lower still, JDAMs and
--                       carpet bombing from high up
--   anti_radiation_missiles  per aircraft in its suppression_of_air_defenses loadout
--                       (data/aircraft_loadouts.lua); keep in step when that choice changes
--   carpet_bombing      true: one Bombing task at the centre of the target, all bombs in
--                       one pass (heavy bombers; DCS Liberation does the same for Tu-22M3 / B-52)
--   keeps_gun           true: the gun stays loaded on attack missions (gun-armed attack
--                       aircraft). Otherwise the gun is emptied, so the AI can't press an
--                       attack with it after its bombs are gone (Liberation's lesson)
-- Figures are rough real-world ones, shortened for a loaded jet flying a simple profile.

AIRCRAFT_PROFILE = {
    ["Su-24M"] = {
        base_classes = { "hub", "fighter", "bomber" }, min_runway_m = 2000, parking = { 104, 72 },
        flight_size = { 2, 2 }, combat_radius_km = 550,
        -- FAB-500 level bombing from medium altitude, as in Syria; RBK cluster bombs lower
        cruise_speed_mps = 230, cruise_altitude_m = 7500,
        attack_altitude_m = { strike = 5000, airfield_strike = 3000, suppression_of_air_defenses = 6000 },
        anti_radiation_missiles = 4,   -- 2 Kh-58U + 2 Kh-25MPU
    },
    ["Su-34"] = {
        base_classes = { "hub", "fighter", "bomber" }, min_runway_m = 2000, parking = { 104, 72 },
        flight_size = { 2, 2 }, combat_radius_km = 700,
        cruise_speed_mps = 230, cruise_altitude_m = 8000,
        -- Kh-29T TV-guided missiles against air-defense sites from medium altitude
        attack_altitude_m = { strike = 5000, airfield_strike = 3000, suppression_of_air_defenses = 6000,
                              destruction_of_air_defenses = 4000, interdiction = 4000 },
        anti_radiation_missiles = 4,   -- Kh-31P
    },
    ["Tu-22M3"] = {
        base_classes = { "bomber" }, min_runway_m = 2500, parking = { 104 },
        flight_size = { 2, 2 }, combat_radius_km = 1500,
        cruise_speed_mps = 250, cruise_altitude_m = 9000,
        attack_altitude_m = { strike = 8000, airfield_strike = 8000 },
        carpet_bombing = true,
    },
    ["FA-18C_hornet"] = {
        base_classes = { "hub", "fighter", "dispersal" }, min_runway_m = 1800, parking = { 72, 104 },
        flight_size = { 2, 2 }, combat_radius_km = 550,
        -- JDAMs from medium-high altitude; Mavericks and HARMs lower
        cruise_speed_mps = 230, cruise_altitude_m = 7500,
        attack_altitude_m = { strike = 7000, airfield_strike = 7000, suppression_of_air_defenses = 6000,
                              destruction_of_air_defenses = 7000, close_air_support = 4500 },
        anti_radiation_missiles = 2,   -- AGM-88C
    },
    ["F-16C_50"] = {
        base_classes = { "hub", "fighter", "dispersal" }, min_runway_m = 1800, parking = { 72, 104 },
        flight_size = { 2, 2 }, combat_radius_km = 550,
        cruise_speed_mps = 230, cruise_altitude_m = 7500,
        attack_altitude_m = { strike = 7000, airfield_strike = 7000, suppression_of_air_defenses = 6000,
                              destruction_of_air_defenses = 7000, close_air_support = 4500 },
        anti_radiation_missiles = 2,   -- AGM-88C
    },
    ["F-15ESE"] = {
        base_classes = { "hub", "fighter", "bomber" }, min_runway_m = 2200, parking = { 104, 72 },
        flight_size = { 2, 2 }, combat_radius_km = 900,
        cruise_speed_mps = 240, cruise_altitude_m = 8000,
        attack_altitude_m = { strike = 7500, airfield_strike = 7500, destruction_of_air_defenses = 7500,
                              interdiction = 6000 },
    },
    ["B-1B"] = {
        base_classes = { "hub", "bomber" }, min_runway_m = 2500, parking = { 104 },
        flight_size = { 1, 2 }, combat_radius_km = 2500,
        cruise_speed_mps = 250, cruise_altitude_m = 9000,
        attack_altitude_m = { strike = 9000, airfield_strike = 9000, interdiction = 7500 },
    },
    ["A-10C_2"] = {
        base_classes = { "hub", "fighter", "dispersal" }, min_runway_m = 1500, parking = { 72, 104 },
        flight_size = { 2, 2 }, combat_radius_km = 400,
        cruise_speed_mps = 160, cruise_altitude_m = 7500,
        attack_altitude_m = { close_air_support = 3500 },
        keeps_gun = true,
    },
}
