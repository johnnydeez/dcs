-- How each AI aircraft type flies its missions: where it can take off from, how far it
-- reaches, how fast and how high it flies. Coalition-agnostic; which coalition flies what
-- is COALITION_AIRCRAFT (data/coalition_rosters.lua). Plain data, no logic.
--
--   base_classes        heavies only: airbase classes (data/airbase_classes.lua) it may
--                       launch from. Without it, any held field whose runway and parking
--                       fit (fighters and attack jets: every usable runway is used in war)
--   min_runway_m        longest runway at the base must be at least this long (F-16 /
--                       F/A-18 1,500 m, ~4,900 ft: John's figures, 2026-09-27)
--   parking             terminal types (DCS Term_Type) it may park on: 104 open-air (the
--                       big spots, any aircraft), 72 airplane-only (often smaller)
--   flight_size         { min, max } aircraft per flight
--   combat_radius_km    farthest target from the launch base, with its mission load
--   cruise_speed_mps    true airspeed in transit
--   dash_speed_mps      interception types only: the speed a scramble flies at the
--                       intruder, afterburner allowed (about Mach 1.1 for F-16 / F/A-18,
--                       1.2 for F-15C / Su-27 / Su-30 / Su-33, 1.5 for the MiG-31, at
--                       altitude where Mach 1 is ~295 m/s)
--   cruise_altitude_m   transit altitude, held until the descent point before the ingress.
--                       At least 7,500 m (~25k ft) for every attack flight: above guns,
--                       shoulder-launched missiles and short-range SAMs (SA-8, SA-15, Roland,
--                       ~5-6 km), so flights only have to route around what reaches higher
--   attack_altitude_m   { mission type = m }: altitude from the ingress point over the
--                       target — what's realistic for the jet and its payload, whatever the
--                       threat: unguided bombs lower, cluster bombs lower still, JDAMs and
--                       carpet bombing from high up
--   anti_radiation_missiles  per aircraft in its suppression_of_air_defenses loadout
--                       (data/aircraft_loadouts.lua; information: a SEAD flight fires them
--                       all at its one site)
--   carpet_bombing      true: one Bombing task at the centre of the target, all bombs in
--                       one pass (heavy bombers; DCS Liberation does the same for Tu-22M3 / B-52)
--   keeps_gun           true: the gun stays loaded on attack missions (gun-armed attack
--                       aircraft). Otherwise the gun is emptied, so the AI can't press an
--                       attack with it after its bombs are gone (Liberation's lesson)
-- Figures are rough real-world ones, shortened for a loaded jet flying a simple profile.

AIRCRAFT_PROFILE = {
    ["Su-24M"] = {
        min_runway_m = 2000, parking = { 104, 72 },
        flight_size = { 2, 2 }, combat_radius_km = 550,
        -- FAB-500 level bombing from medium altitude, as in Syria; RBK cluster bombs lower
        cruise_speed_mps = 230, cruise_altitude_m = 7500,
        attack_altitude_m = { strike = 5000, airfield_strike = 3000, suppression_of_air_defenses = 9000 },
        anti_radiation_missiles = 4,   -- 2 Kh-58U + 2 Kh-25MPU
    },
    ["Su-34"] = {
        -- open-air spots (104) only, for now: on Afrikanda's airplane-only spots (72) both jets
        -- of two flights blew up seconds after spawning (2026-10-01, bugs_and_fixes.md 13),
        -- most likely too small for it
        min_runway_m = 2000, parking = { 104 },
        flight_size = { 2, 2 }, combat_radius_km = 700,
        cruise_speed_mps = 230, cruise_altitude_m = 8000,
        -- Kh-29T TV-guided missiles against air-defense sites from medium altitude
        attack_altitude_m = { strike = 5000, airfield_strike = 3000, suppression_of_air_defenses = 9000,
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
        min_runway_m = 1500, parking = { 72, 104 },
        flight_size = { 2, 2 }, combat_radius_km = 550,
        -- JDAMs from medium-high altitude; Mavericks and HARMs lower
        cruise_speed_mps = 230, cruise_altitude_m = 7500,
        dash_speed_mps = 325,
        attack_altitude_m = { strike = 7000, airfield_strike = 7000, suppression_of_air_defenses = 9000,
                              destruction_of_air_defenses = 7000, close_air_support = 4500,
                              combat_air_patrol = 8000, interception = 8500 },
        anti_radiation_missiles = 4,   -- AGM-88C (hand: SEAD 4 HARM, John 2026-10-01)
    },
    ["F-16C_50"] = {
        min_runway_m = 1500, parking = { 72, 104 },
        flight_size = { 2, 2 }, combat_radius_km = 550,
        cruise_speed_mps = 230, cruise_altitude_m = 7500,
        dash_speed_mps = 325,
        attack_altitude_m = { strike = 7000, airfield_strike = 7000, suppression_of_air_defenses = 9000,
                              destruction_of_air_defenses = 7000, close_air_support = 4500,
                              combat_air_patrol = 8000, interception = 8500 },
        anti_radiation_missiles = 4,   -- AGM-88C (hand: SEAD 4 HARM, John 2026-10-01)
    },
    ["F-15ESE"] = {
        min_runway_m = 2200, parking = { 104, 72 },
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
        min_runway_m = 1500, parking = { 72, 104 },
        flight_size = { 2, 2 }, combat_radius_km = 400,
        cruise_speed_mps = 160, cruise_altitude_m = 7500,
        attack_altitude_m = { close_air_support = 3500 },
        keeps_gun = true,
    },

    -- ── fighters: combat air patrol and interception ──
    -- attack_altitude_m here is the patrol altitude on station, and the altitude a
    -- scramble climbs to on its way to the intruder. Flight sizes for these missions
    -- come from the mission type (single ships for now, to watch them)
    ["Su-27"] = {
        min_runway_m = 2000, parking = { 104, 72 },
        flight_size = { 1, 2 }, combat_radius_km = 700,
        cruise_speed_mps = 240, cruise_altitude_m = 9000,
        dash_speed_mps = 355,
        attack_altitude_m = { combat_air_patrol = 8000, interception = 9000 },
    },
    ["Su-30"] = {
        min_runway_m = 2000, parking = { 104, 72 },
        flight_size = { 1, 2 }, combat_radius_km = 800,
        cruise_speed_mps = 240, cruise_altitude_m = 9000,
        dash_speed_mps = 355,
        attack_altitude_m = { combat_air_patrol = 8000, interception = 9000 },
    },
    -- Su-33: the Northern Fleet's carrier fighters, ashore at Severomorsk-3
    ["Su-33"] = {
        min_runway_m = 2000, parking = { 104, 72 },
        flight_size = { 1, 2 }, combat_radius_km = 650,
        cruise_speed_mps = 240, cruise_altitude_m = 9000,
        dash_speed_mps = 355,
        attack_altitude_m = { combat_air_patrol = 8000, interception = 9000 },
    },
    -- MiG-31: the long-range interceptor, fast and high
    ["MiG-31"] = {
        min_runway_m = 2200, parking = { 104, 72 },
        flight_size = { 1, 2 }, combat_radius_km = 700,
        cruise_speed_mps = 280, cruise_altitude_m = 10000,
        dash_speed_mps = 440,
        attack_altitude_m = { combat_air_patrol = 10000, interception = 11000 },
    },
    ["F-15C"] = {
        min_runway_m = 2000, parking = { 104, 72 },
        flight_size = { 1, 2 }, combat_radius_km = 900,
        cruise_speed_mps = 240, cruise_altitude_m = 9000,
        dash_speed_mps = 355,
        attack_altitude_m = { combat_air_patrol = 8500, interception = 9000 },
    },

    -- ── airborne early warning ──
    ["A-50"] = {
        base_classes = { "hub", "bomber" }, min_runway_m = 2500, parking = { 104 },
        flight_size = { 1, 1 }, combat_radius_km = 1500,
        cruise_speed_mps = 180, cruise_altitude_m = 9000,
        attack_altitude_m = { airborne_early_warning = 9000 },
    },
    ["E-3A"] = {
        base_classes = { "hub", "bomber" }, min_runway_m = 2500, parking = { 104 },
        flight_size = { 1, 1 }, combat_radius_km = 1600,
        cruise_speed_mps = 200, cruise_altitude_m = 9000,
        attack_altitude_m = { airborne_early_warning = 9000 },
    },
}
