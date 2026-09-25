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
--   weapon_type  pydcs WeaponType name for the attack task (auto, bombs, guided, ...)
--   max_attack_points  bomb_critical_objects: at most this many Bombing tasks per flight
--   ingress_km   the ingress point sits this far before the target, on the way in
--   egress_km    the egress point sits this far past the target, turned toward home
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
    -- ── not built yet ──
    suppression_of_air_defenses = {
        built = false, group_task = "SEAD", attack = "engage_group",
        weapon_type = "guided", ingress_km = 40, egress_km = 30,
    },
    destruction_of_air_defenses = {
        built = false, group_task = "CAS", attack = "attack_group",
        weapon_type = "auto", ingress_km = 30, egress_km = 20,
    },
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
--   missions            { min, max } per mission window
--   mission_types       { { mission type, weight } } — only built types are used
--   max_airborne        flights of this coalition in the air at once
--   window_s            missions start between first_start_s and the end of this window
--   first_start_s       earliest start (mission time), so the first flights are soon
--   taxi_s / attack_s / landing_s   time on the ground before takeoff, over the target,
--                       and from the landing base's overhead to shutdown (for timing only)
AIR_TASKING_PER_COALITION = {
    red = {
        missions = { 4, 6 }, max_airborne = 3,
        mission_types = { { "strike", 3 }, { "airfield_strike", 2 } },
    },
    blue = {
        missions = { 6, 8 }, max_airborne = 3,
        mission_types = { { "strike", 3 }, { "airfield_strike", 2 } },
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
-- cross a ring lists it in suppression_threats, for the SEAD/DEAD escorts to come.
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
