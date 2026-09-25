-- The air mission types and how many each coalition flies. Plain data, no logic.
--
-- AIR_MISSION_TYPE[mission type] — names match the target catalog's mission_types:
--   built        false: planned for later; the stage skips it (the entry records how it
--                will attack, so nothing is forgotten)
--   group_task   the DCS group task (the Mission Editor's spelling). It only decides which
--                waypoint actions the AI accepts; DCS Liberation flies air-defense
--                destruction as CAS for that reason
--   attack       how the flight is told what to hit, on its ingress waypoint:
--                  bomb_critical_objects  one Bombing task per critical object of the
--                                         target, at its position (works for static
--                                         objects, which search tasks never pick)
--                  attack_group           AttackGroup on the target's DCS group
--                  engage_group           EngageGroup: attacks only once the group is
--                                         detected — for anti-radiation missiles, so the
--                                         flight waits for a radar to emit instead of diving
--                                         at a silent SAM (Liberation's lesson)
--                  engage_in_zone         EngageTargetsInZone around the target
--   weapon_type  pydcs WeaponType name for the attack task (auto, bombs, guided, arm, ...)
--   max_attack_points  bomb_critical_objects: at most this many Bombing tasks per flight
--   ingress_km   the ingress point sits this far before the target, on the way in
--   egress_km    the egress point sits this far past the target, turned toward home
--   escort_only  true: never planned on its own, only in another mission's package.
--                Suppression flights fly their package's route, so their own ingress_km
--                and egress_km are not used
--   missiles_per_threat  suppression: anti-radiation missiles a flight keeps for each
--                group it engages; with the profile's anti_radiation_missiles this sets
--                how many groups one flight takes
--   max_groups_per_flight  suppression: and never more than this many, so a flight
--                with a big load (Su-34, 8 Kh-31P) doesn't take on alone what another
--                coalition sends two flights for. A SAM site's point-defense escort
--                (the Tor / Pantsir / Roland guarding an SA-10 or Patriot) is engaged
--                with its site and counts as one more group; they are the best missile
--                killers in DCS and otherwise shoot the anti-radiation missiles down
--   return_when_out_of  pydcs WeaponType name: the flight heads home once these are gone —
--                straight home, off its route, so only for flights with nothing in the way
--
-- Every attack flight also gets, on its first waypoint: rules of engagement "open fire"
-- (attack the assigned target, don't wander off after others — weapons free is for
-- search tasks), reaction to threat "evade fire", return at bingo fuel, no jettisoning
-- stores, and an empty gun unless its profile keeps_gun.

AIR_MISSION_TYPE = {
    strike = {
        built = true, group_task = "Ground Attack", attack = "bomb_critical_objects",
        weapon_type = "auto", max_attack_points = 4, ingress_km = 25, egress_km = 20,
    },
    airfield_strike = {
        built = true, group_task = "Ground Attack", attack = "bomb_critical_objects",
        weapon_type = "auto", max_attack_points = 4, ingress_km = 25, egress_km = 20,
    },
    -- EngageGroup on each threat given to the flight, anti-radiation missiles only, from
    -- the waypoint before the first of their rings. No return_when_out_of: DCS then flies
    -- straight home, over whatever SAMs lie on the line (first package run, 2026-09-25);
    -- the flight stays on the package's route and comes home the way it went in
    suppression_of_air_defenses = {
        built = true, escort_only = true, group_task = "SEAD", attack = "engage_group",
        weapon_type = "arm", ingress_km = 40, egress_km = 30,
        missiles_per_threat = 2, max_groups_per_flight = 2,
    },
    -- AttackGroup on each of the SAM or early-warning site's groups, from the ingress point
    destruction_of_air_defenses = {
        built = true, group_task = "CAS", attack = "attack_group",
        weapon_type = "auto", ingress_km = 30, egress_km = 20,
    },
    -- ── not built yet ──
    interdiction = {
        built = false, group_task = "CAS", attack = "attack_group",
        weapon_type = "auto", ingress_km = 25, egress_km = 20,
    },
    close_air_support = {
        built = false, group_task = "CAS", attack = "engage_in_zone",
        weapon_type = "auto", ingress_km = 20, egress_km = 15,
    },
}

-- DCS WeaponType bit masks (pydcs dcs/task.py) for the names used above.
AIR_WEAPON_TYPE = {
    auto   = 9663676414,
    bombs  = 2032,
    guided = 268402702,
    arm    = 32768,
}

-- How many ground attack missions each coalition flies and when.
--   missions            { min, max } per mission window, not counting the suppression
--                       flights in their packages
--   mission_types       { { mission type, weight } } — only built types are used
--   max_airborne_aircraft  aircraft of this coalition in the air at once, counting every
--                       flight of every package
--   window_s            missions start between first_start_s and the end of this window
--   first_start_s       earliest start (mission time), so the first flights are soon
--   taxi_s / attack_s / landing_s   time on the ground before takeoff, over the target,
--                       and from the landing base's overhead to shutdown (for timing only)
AIR_TASKING_PER_COALITION = {
    red = {
        missions = { 4, 6 }, max_airborne_aircraft = 10,
        mission_types = { { "strike", 3 }, { "airfield_strike", 2 }, { "destruction_of_air_defenses", 1 } },
    },
    blue = {
        missions = { 6, 8 }, max_airborne_aircraft = 10,
        mission_types = { { "strike", 3 }, { "airfield_strike", 2 }, { "destruction_of_air_defenses", 2 } },
    },
}

AIR_TASKING_TIMING = {
    window_s      = 6 * 3600,
    first_start_s = 120,
    taxi_s        = 600,
    attack_s      = 300,
    landing_s     = 600,
    parking_hold_s = 1800,   -- a parking spot stays reserved this long after a flight's start
}

AIR_TASKING_SKILL = { "Average", "Good", "High" }

-- Packages. A mission whose route still crosses threat rings (needs_suppression) gets
-- suppression flights for them, or isn't flown at all: a flight that needs suppression
-- never goes without it. Each suppression flight takes the next threats in the order the
-- route meets them, as many as its missiles allow (max_groups_per_flight at most). It flies the package's route from its
-- own base and is over the target suppression_lead_s before the mission it escorts, so
-- it reaches every ring on the way that much earlier too.
--   suppression_lead_s  { min, max } seconds each suppression flight is ahead
AIR_PACKAGE = {
    suppression_lead_s = { 180, 300 },
}

-- How attack flights route around what they can't overfly. Flights cruise at least
-- min_cruise_altitude_m, above guns, shoulder-launched missiles and short-range SAMs;
-- what reaches higher is routed around:
--   threat_layers        enemy SAM site layers that reach above cruise altitude
--   threat_margin_km     kept clear of a SAM site's engagement ring
--   base_defense_roles   enemy base-defense roles that reach above cruise altitude
--                        (Pantsir, Tor-M2 at enemy airfields), kept clear by
--                        base_defense_margin_km past their range
--   max_detour           the way around may be at most this many times the direct
--                        distance (and within the aircraft's reach); otherwise the flight
--                        goes through and the mission is marked needs_suppression
--   descent_km_per_km    the descent from cruise to attack altitude starts this many km
--                        before the ingress point per km of altitude lost (at least
--                        min_descent_km)
-- Every enemy site is known (fixed sites are found by intelligence); a flight that has to
-- cross a ring lists it in suppression_threats, and its package gets suppression flights.
AIR_ROUTING = {
    min_cruise_altitude_m = 7500,
    threat_layers         = { medium_range = true, long_range = true },
    threat_margin_km      = 10,
    base_defense_roles    = { radar_missile_launcher = true },
    base_defense_margin_km = 5,
    max_detour            = 1.6,
    descent_km_per_km     = 5,
    min_descent_km        = 10,
}
