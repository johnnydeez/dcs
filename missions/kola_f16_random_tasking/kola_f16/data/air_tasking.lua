-- The air mission types and how many each coalition flies. Plain data, no logic.
--
-- AIR_MISSION_TYPE[mission type] — names match the target catalog's mission_types:
--   group_name_tag  the mission type in every flight's DCS group name: MSN<number>_<tag>
--                (MSN2002_CAP, MSN2025_DEAD, MSN2901_SCRAM; John, 2026-09-30). Real-world
--                terms: OCA is offensive counter-air (attacking enemy airfields); SCRAM
--                is a scramble (John: easier to remember than QRA)
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
--                Suppression flights (planned_as "escort") fly their package's route, so
--                their own ingress_km and egress_km are not used
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
--   planned_as   how the stage plans it: "mission" (default: from the weighted
--                mission_types, against a catalog target), "escort" (only in another
--                mission's package), "station" (defensive air: a racetrack held over the
--                window, AIR_DEFENSE), "response" (never planned: scrambled at run time
--                by consumers/run_scrambles.lua)
--   flight_size  { min, max }: overrides the aircraft profile's for this mission type
--   rules_of_engagement  "open_fire" (default) | "weapons_free" (engage anything
--                found: patrols) | "weapons_hold" (never fire: AWACS)
--   engage_range_km  engage_aircraft_on_station: enemy aircraft within this distance of
--                the flight's route are engaged
--   takeoff      "parking" (default, hot) | "runway" (hot on the runway: the AWACS at
--                start). Scrambles start hot from a free ramp spot, never on the runway,
--                so they can't spawn on top of jets lined up there (John, 2026-09-30)
--   keeps_gun    true: the gun stays loaded (fighters), whatever the profile says
--   may_jettison true: the flight may jettison stores (fighters drop tanks to fight);
--                otherwise jettisoning is prohibited, so attack flights keep their bombs
--
-- Attack kinds for the defensive types (on the station waypoint):
--   engage_aircraft_on_station  EngageTargetsInZone (air) over the station's defended zone
--                (engage_range_km around the sites it protects), then a race-track Orbit
--                between the station's two ends until the flight's time on station is up
--                (Syria's blue_air_support lesson: the engage task stands for the whole
--                orbit, and the flight is weapons free)
--   early_warning_on_station    the AWACS task, then the same Orbit until the window ends
--   intercept                   EngageGroup on each group of the intruding raid, on the
--                takeoff waypoint so it's active from wheels-up and the AI flies its own
--                intercept at the target; nothing else is engaged unless it shoots first
--                (open fire). The scramble flies at the profile's dash_speed_mps with
--                afterburner allowed
--
-- Every attack flight also gets, on its first waypoint: rules of engagement "open fire"
-- (attack the assigned target, don't wander off after others — weapons free is for
-- search tasks), reaction to threat "evade fire", return at bingo fuel, no jettisoning
-- stores unless may_jettison, and an empty gun unless its profile keeps_gun.
-- Patrols are "open_fire" too (2026-09-27): weapons free let them go after anything the
-- AWACS datalink showed, far off their route and zone and into enemy SAMs; open fire
-- keeps them to their task, enemy aircraft inside their station's defended zone.

AIR_MISSION_TYPE = {
    strike = {
        group_name_tag = "STRIKE", built = true, group_task = "Ground Attack", attack = "bomb_critical_objects",
        weapon_type = "auto", max_attack_points = 4, ingress_km = 25, egress_km = 20,
    },
    airfield_strike = {
        group_name_tag = "OCA", built = true, group_task = "Ground Attack", attack = "bomb_critical_objects",
        weapon_type = "auto", max_attack_points = 4, ingress_km = 25, egress_km = 20,
    },
    -- EngageGroup on each threat given to the flight, anti-radiation missiles only, from
    -- the waypoint before the first of their rings. No return_when_out_of: DCS then flies
    -- straight home, over whatever SAMs lie on the line (first package run, 2026-09-25);
    -- the flight stays on the package's route and comes home the way it went in
    suppression_of_air_defenses = {
        group_name_tag = "SEAD", built = true, planned_as = "escort", group_task = "SEAD", attack = "engage_group",
        weapon_type = "arm", ingress_km = 40, egress_km = 30,
        missiles_per_threat = 2, max_groups_per_flight = 2,
    },
    -- AttackGroup on each of the SAM or early-warning site's groups, from the ingress point
    destruction_of_air_defenses = {
        group_name_tag = "DEAD", built = true, group_task = "CAS", attack = "attack_group",
        weapon_type = "auto", ingress_km = 30, egress_km = 20,
    },
    -- ── defensive air ──
    -- single ships for now (John, 2026-09-25: easier to watch what they do)
    combat_air_patrol = {
        group_name_tag = "CAP", built = true, planned_as = "station", group_task = "CAP", attack = "engage_aircraft_on_station",
        weapon_type = "auto", ingress_km = 0, egress_km = 0, flight_size = { 1, 1 },
        rules_of_engagement = "open_fire", engage_range_km = 60, keeps_gun = true, may_jettison = true,
    },
    airborne_early_warning = {
        group_name_tag = "AEW", built = true, planned_as = "station", group_task = "AWACS", attack = "early_warning_on_station",
        weapon_type = "auto", ingress_km = 0, egress_km = 0, flight_size = { 1, 1 },
        rules_of_engagement = "weapons_hold", takeoff = "runway",
    },
    -- a scramble: burns straight at the one raid it was sent after (John, 2026-09-30)
    interception = {
        group_name_tag = "SCRAM", built = true, planned_as = "response", group_task = "Intercept", attack = "intercept",
        weapon_type = "auto", ingress_km = 0, egress_km = 0, flight_size = { 1, 1 },
        rules_of_engagement = "open_fire", takeoff = "parking", keeps_gun = true,
        may_jettison = true,
    },
    -- ── not built yet ──
    interdiction = {
        group_name_tag = "INTERDICTION", built = false, group_task = "CAS", attack = "attack_group",
        weapon_type = "auto", ingress_km = 25, egress_km = 20,
    },
    close_air_support = {
        group_name_tag = "CAS", built = false, group_task = "CAS", attack = "engage_in_zone",
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
--                       flight of every package, the patrols, the AWACS and the scrambles
--                       (one shared cap for now, John 2026-09-25)
--   window_s            missions start between first_start_s and the end of this window
--   first_start_s       earliest start (mission time), so the first flights are soon
--   taxi_s / attack_s / landing_s   time on the ground before takeoff, over the target,
--                       and from the landing base's overhead to shutdown (for timing only)
AIR_TASKING_PER_COALITION = {
    red = {
        missions = { 4, 6 }, max_airborne_aircraft = 16,
        mission_types = { { "strike", 3 }, { "airfield_strike", 2 }, { "destruction_of_air_defenses", 1 } },
    },
    blue = {
        missions = { 6, 8 }, max_airborne_aircraft = 16,
        mission_types = { { "strike", 3 }, { "airfield_strike", 2 }, { "destruction_of_air_defenses", 2 } },
    },
}

-- Which targets ground attack missions go after (plan.md "Attack missions", air denial — jets
-- work the front, not the enemy's rear):
--   max_km_past_contested  a target lies in the contested airspace or at most this far
--                          from it (so at most this deep in enemy airspace)
--   facing_search_km       how far from a target to look for own held ground; the region
--                          found there is the only one whose bases fly against it, so no
--                          flight crosses enemy ground to reach another front (a pocket)
--   enemy_airspace_slack_km  a route may fly this much more in enemy airspace on its way
--                          to the target than the target's depth (the grid is coarse)
AIR_TARGETING = {
    max_km_past_contested   = 40,
    facing_search_km        = 200,
    enemy_airspace_slack_km = 20,
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
-- route meets them, as many as its missiles allow (max_groups_per_flight at most). It
-- flies the package's route from its own base and is over the target suppression_lead_s
-- before the mission it escorts, so it reaches every ring on the way that much earlier.
--   suppression_lead_s  { min, max } seconds each suppression flight is ahead
AIR_PACKAGE = {
    suppression_lead_s = { 180, 300 },
}

-- Human flights (session 10): Blue missions planned for players, listed at mission start
-- and in the F10 menu, flown from a player slot (data/player_slots.lua). Planned like the
-- AI's (same targets near the front, routes, packages and suppression flights), but one
-- aircraft of aircraft_type from a held base with a player slot, and timed from mission
-- start: takeoff after a cockpit startup of startup_s, over the target when the route
-- gets there; the package's AI flights are timed around it. Never spawned: the player
-- spawns in on the slot. Planned after defensive air and before the AI attack missions.
--   coalition      the coalition players fly for
--   missions       planned every roll: the stage falls back to the other mission types,
--                  then to bases another human mission already uses, before giving up
--   mission_types  { type, weight }: every type a player can fly. A player's
--                  suppression_of_air_defenses escorts an AI mission; a player's
--                  combat_air_patrol flies one of the front stations
--   startup_s      { min, max } seconds from mission start to takeoff
HUMAN_TASKING = {
    coalition     = "blue",
    missions      = 2,
    aircraft_type = "F-16C_50",
    mission_types = { { "strike", 3 }, { "airfield_strike", 2 }, { "destruction_of_air_defenses", 2 },
                      { "suppression_of_air_defenses", 2 }, { "combat_air_patrol", 1 } },
    startup_s     = { 600, 1200 },
}

-- Defensive air (plan.md "Defensive air"). Planned before the attack missions
-- ("support up first"), so the patrols and the AWACS always have their share of the cap.
--
-- Kill zones (John, 2026-09-27: SAMs don't fire out to their full drawn range, so jets
-- may work close to a ring or a little inside it, just not fly into the kill zone):
--   killzone_fraction     patrols and the AWACS keep out of each enemy threat's kill zone,
--                         this fraction of its drawn engagement ring (SAM sites) or reach
--                         (Pantsir / Tor at bases), with no routing margin. Their routes,
--                         orbits and defended zones use it. Attack flights still route
--                         around the full ring + AIR_ROUTING.threat_margin_km.
--
-- Patrol stations, per coalition (air denial, session 8): patrols deny their own and the
-- contested airspace to the enemy and protect the coalition's installations near the
-- front. Stations are placed greedily over the defended sites:
--   defended sites        own catalog targets (SAM / early-warning sites, fixed ground
--                         targets) in the contested airspace or at most defended_depth_km
--                         behind it
--   each station          covers the sites within the patrol's engage_range_km of the
--                         best-valued uncovered site; its patrols engage enemy aircraft
--                         inside that circle (the defended zone, centred on the covered
--                         sites' value-weighted centre, cut short of every enemy kill
--                         zone, never below min_zone_radius_km).
--                         Patrols hold that engage task from takeoff, so one still on
--                         its way defends the zone too. The race-track sits as close to
--                         that centre as it can while on own held ground and
--                         station_clearance_km outside every enemy kill zone, walked out
--                         from the nearest own base in the same region; its legs run across
--                         the line to the nearest enemy base
--   max_stations          at most this many stations per coalition
--   min_defended_value    a station must cover sites worth at least this much (catalog
--                         value: 1 low … 3 high)
--   min_zone_radius_km    a defended zone cut short by enemy rings keeps at least this
--   station_spacing_km    race-tracks of one coalition at least this far apart
--   station_leg_km        length of the race-track
--   step_km               how finely a station's walk out is stepped
--   on_station_s          each patrol flight's time on station
--   rotation_overlap_s    the next patrol arrives this long before the last one leaves
-- Patrols launch only from bases in the station's region (never across enemy ground)
-- whose route to the station enters no enemy kill zone (patrols get no suppression) and
-- at most station_enemy_airspace_km of enemy airspace (the AWACS too; the grid is
-- coarse, so a route along the border may clip a cell). Without that check the Kuusamo
-- patrols to the Banak station flew ~300 km across Red Lapland (John's run, 2026-09-27).
--
-- Commit areas (John, 2026-09-27: two fighters 54 nm apart over contested airspace
-- wouldn't both do nothing): besides its defended zone, each patrol engages enemy
-- aircraft in circles laid over the own and contested airspace of its sector, from
-- takeoff. Circle centres sit on a commit_spacing_km lattice within commit_range_km of
-- the station's race-track, on own or contested cells of the station's region; each
-- circle is commit_radius_km, shrunk until it holds no enemy airspace and no enemy kill
-- zone, and dropped below commit_min_radius_km. So an enemy jet over the contested
-- airspace near a patrol is engaged, one in its own airspace isn't. Once engaged, DCS
-- may chase it further (the leash is on the AI behaviour list).
--
-- AWACS, one per coalition, on the runway at mission start:
--   early_warning_start_s      mission time it is spawned
--   early_warning_standoff_km  its orbit stays at least this far from every enemy base, in
--                              own (not contested) airspace, and outside every enemy kill
--                              zone by early_warning_clearance_km
--   early_warning_leg_km       length of its race-track
--
-- Scrambles (roadmap.md item 2; the plan holds the alert posture, consumers/run_scrambles.lua
-- reacts to the radar picture every round, consumers/enforce_air_behaviour_rules.lua
-- brings them home):
--   alert_posture_planned  false: no alert bases are planned, so nothing scrambles
--   alert_bases           alert bases per coalition: held bases whose runway and parking
--                         fit an interception type, nearest the enemy; plus the nearest of
--                         each other region (pocket) that has one (John, 2026-09-30)
--   alert_aircraft_per_base  alert jets each alert base holds. A jet that lands is back on
--                         alert scramble_turnaround_s later (refuelled and rearmed); a jet
--                         that is shot down is gone for the mission (John, 2026-09-30: a base
--                         shouldn't run out if its jets came back)
--   scramble_turnaround_s after landing, this long until the jet can scramble again
--   scramble_cooldown_s   an alert base waits this long between launches
--   scramble_warning_min  answer a raid the radar picture has inbound on an own asset (held
--                         base, catalog target; RADAR_PICTURE.threat_pass_km) that it will
--                         reach within this many minutes, in whatever airspace it is now
--                         (John: 100 km was far too close; a jet at 60 nm can have weapons
--                         on a base in ~5 minutes)
--   scramble_inbound_rounds  radar-picture rounds in a row (30 s each) a contact must stay
--                         inbound, so one turn of a patrol's race-track doesn't trigger
--   scramble_reaction_s   { min, max }: cockpit alert — from the decision to the spawn,
--                         hot on a free ramp spot
--   scramble_over_cap     scrambles may put the coalition this many aircraft over
--                         max_airborne_aircraft (John: up to 2)
--   scramble_min_leg_km   the intercept point (the raid pushed ahead along its heading,
--                         pulled back to own or contested airspace and out of enemy kill
--                         zones) must be at least this far from the base, or there's no
--                         way to the raid and the base doesn't answer
--   raid_radius_km, raid_heading_deg  contacts within this distance of the one that
--                         triggered, and within this many degrees of its heading, are one
--                         raid: one scramble, EngageGroup on each of them
AIR_DEFENSE = {
    planned               = true,
    killzone_fraction     = 0.85,
    max_stations          = 3,
    defended_depth_km     = 60,
    min_defended_value    = 2,
    min_zone_radius_km    = 20,
    station_spacing_km    = 60,
    station_leg_km        = 50,
    station_clearance_km  = 0,
    step_km               = 10,
    on_station_s          = 3600,
    rotation_overlap_s    = 600,
    station_enemy_airspace_km = 5,
    commit_range_km       = 120,
    commit_spacing_km     = 50,
    commit_radius_km      = 40,
    commit_min_radius_km  = 15,

    early_warning_start_s      = 5,
    early_warning_standoff_km  = 200,
    early_warning_clearance_km = 30,
    early_warning_leg_km       = 80,

    alert_posture_planned = true,
    alert_bases           = 3,
    alert_aircraft_per_base = 3,
    scramble_turnaround_s = 1800,
    scramble_cooldown_s   = 900,
    scramble_warning_min  = 15,
    scramble_inbound_rounds = 2,
    scramble_reaction_s   = { 60, 120 },
    scramble_over_cap     = 2,
    scramble_min_leg_km   = 10,
    raid_radius_km        = 20,
    raid_heading_deg      = 45,
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
--   airspace_cost        what a km costs, on top of its threats, by the airspace it lies
--                        in as seen from the flight's coalition (plan.airspace): routes
--                        keep to own airspace, cross the contested zone where it's
--                        narrowest and avoid enemy airspace
-- Every enemy site is known (fixed sites are found by intelligence); a flight that has to
-- cross a ring lists it in suppression_threats, and its package gets suppression flights.
AIR_ROUTING = {
    airspace_cost         = { own = 1, contested = 3, enemy = 10 },
    min_cruise_altitude_m = 7500,
    threat_layers         = { medium_range = true, long_range = true },
    threat_margin_km      = 10,
    base_defense_roles    = { radar_missile_launcher = true },
    base_defense_margin_km = 5,
    max_detour            = 1.6,
    descent_km_per_km     = 5,
    min_descent_km        = 10,
}
