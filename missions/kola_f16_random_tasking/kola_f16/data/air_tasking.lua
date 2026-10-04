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
--                SEAD flights fly their own low route to a launch point (suppressionRoute),
--                so their ingress_km and egress_km are not used
--   return_when_out_of  pydcs WeaponType name: the flight heads home once these are gone —
--                straight home, off its route, so only for flights with nothing in the way
--   planned_as   how the stage plans it: "mission" (default: from the weighted
--                mission_types, against a catalog target), "rotation" (SEAD: the standing
--                rotation against the enemy air defenses, and when an attack's route needs
--                a site the rotation doesn't take), "station" (defensive air: a racetrack held over the
--                window, AIR_DEFENSE), "response" (never planned: scrambled at run time
--                by the controller, consumers/control_air_flights/scramble_fighters.lua)
--   flight_size  { min, max }: overrides the aircraft profile's for this mission type
--   rules_of_engagement  "open_fire" (default) | "weapons_free" (engage anything
--                found: patrols) | "weapons_hold" (never fire: AWACS)
--   engage_range_km  engage_aircraft_on_station: enemy aircraft within this distance of
--                the flight's route are engaged
--   takeoff      "parking" (default, hot) | "runway" (hot on the runway) | "air" (in the
--                air at the start of its station's race-track, at station altitude and
--                speed: the AWACS, John 2026-10-04: neither side would launch without
--                AWACS coverage, so it is in place at mission start). Scrambles start hot
--                from a free ramp spot, never on the runway, so they can't spawn on top
--                of jets lined up there (John, 2026-09-30)
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
    -- One SAM site per flight, saturated, under the radar (roadmap item 10; John,
    -- 2026-10-01, after the 14:14 run: "going in low and popping up to launch radiation
    -- missiles at a long range SAM is a really good defeat tactic … my instinct to go high
    -- was wrong"). The flight cruises in own airspace; descends before its route enters
    -- the first enemy SAM ring (low_entry_margin_km short of it), runs in at
    -- low_altitude_m above the ground (RADIO) and low_speed_mps, a waypoint every
    -- low_waypoint_km, routed outside every other site's low-altitude reach; pops up
    -- popup_km before a launch point launch_km from the site, to popup_altitude_m; at the
    -- launch point it attacks the site's group with every anti-radiation missile it
    -- carries (AttackGroup, expend All, one attack; an EngageGroup on the site from the
    -- top of the pop-up fires the moment its radar is seen); with no radar to shoot at yet it presses
    -- on along the same track, up to press_on_km; then straight back down and out the
    -- way it came, low and fast with afterburner allowed, and climbs back to cruise once
    -- clear of the rings. A low km burns low_fuel_factor km of reach. A second site gets a
    -- flight of its own. The site's point-defense escort gets no missiles of its own: the
    -- salvo is meant to saturate it. The controller's directive `suppression`
    -- (data/air_control.lua) sends it home if it presses on.
    -- No return_when_out_of: DCS then flies straight home, over whatever SAMs lie on the
    -- line (first package run, 2026-09-25)
    -- Planned as "rotation" (roadmap item 12, John, 2026-10-02): a SEAD flight is a
    -- mission against one site, its target. Most fly in the coalition's standing rotation,
    -- the general assault on the enemy air defenses, one 2-ship after another, the sites
    -- taken outside in; the rest are planned when an attack's route crosses a site the
    -- rotation doesn't take. Any flight lists the sites it needs out of the fight first
    -- (requires_cleared), a SEAD flight too (the outer sites in its way).
    --   max_order_steps  how deep the outside-in order goes: step 1 the sites with a launch
    --                point clear of every other site, step n those clear once the sites
    --                of the steps before are out of the fight
    suppression_of_air_defenses = {
        group_name_tag = "SEAD", built = true, planned_as = "rotation", group_task = "SEAD", attack = "harm_salvo",
        weapon_type = "arm", ingress_km = 40, egress_km = 30,   -- (not used: see suppressionRoute)
        -- launch_km 55 (2026-10-02; was 40, and 80 before that): from 89-92 km every HARM
        -- was coasting by the end and the Sodankyla SA-10 shot all 8 down (2026-10-01).
        -- From 35-41 km, after a low run-in and a pop-up, 8 HARMs killed both of its
        -- search radars (14:14 run); but in the 2026-10-02 run the sites fired back at
        -- the pop-up from 39-50 km (SA-11 39 km at 10,500 ft, Patriot 50 km at 8,300 ft,
        -- SA-10 46 km at ~3,000 ft) and 6 of 6 SEAD jets that got there died. John: pop
        -- up and fire earlier. 45 since 2026-10-02 (bug 33, with the 6,000 ft pop-up): from
        -- 55 km the AI didn't fire: F-16s at ~10,600 ft pressed on and fired HARMs only at
        -- 44-48 km, a Su-34 at 5,000 ft never fired its Kh-31Ps from 57 km
        launch_km = 45,
        -- a short-reaching target gets a closer launch point: its reach + this, at most
        -- launch_km (bug 29, 2026-10-02: John's SEAD on the Vuojarvi Tor M2, 16 km, flown
        -- by the AI from 40 km, fired nothing). Tor M2 31 km, Pantsir 35, NASAMS 30,
        -- SA-6 40; the SA-11, IRIS-T, Hawk and the long-range sites stay at launch_km
        launch_past_reach_km = 15,
        low_altitude_m = 275,          -- ~900 ft above the ground (John's figure from flying it)
        low_speed_mps = 270,           -- ~525 kt
        low_entry_margin_km = 10,      -- down this far before the first ring
        low_waypoint_km = 15,          -- so the AI re-reads the ground often
        popup_km = 8,                  -- the climb to the shot starts this far before the launch point,
                                       -- on afterburner (bug 33, 2026-10-02; was 15, and 12 before
                                       -- that, when the climb to 3,000 m had no afterburner)
        popup_altitude_m = 2400,       -- ~8,000 ft above sea level (John, 2026-10-02, bug 36: "increase
                                       -- the pop up altitude a bit"; 1,800 m (bug 33) was too low for
                                       -- the sites' radars to see the jets over the fells, and with no
                                       -- radar to home on nothing was fired in the 16:03 run; 3,000 m
                                       -- before bug 33). Up there the other sites
                                       -- reach farther than their low figure; the launch point is
                                       -- still cleared only of that low reach, and the short time up
                                       -- is accepted exposure (roadmap item 12: every SEAD jet lost
                                       -- at its pop-up so far fell to its own target)
        -- the top of the pop-up: a waypoint this far past the pop-up point at the full pop-up
        -- altitude, so the AI climbs hard there and is up before its launch point (bug 40,
        -- 2026-10-02: with the pop-up altitude only on the launch point, DCS spread the climb
        -- over the 8 km leg and counted both waypoints reached early: the F-16s passed their
        -- launch point at 2,825 ft, planned 7,874, and the SA-10 killed them there unfired)
        popup_climb_km = 3,
        -- no radar to shoot at by the launch point: the flight presses on along the same track
        -- toward the site, at the pop-up altitude, until it gets a radar ping and fires, then
        -- turns home as planned (John, 2026-10-02, bug 36: "send the jets forward on that same
        -- track until they get a radar ping and can launch"). It presses on at most this far
        -- (a short-reaching site: to its reach + short_range_margin_km at the closest; a point
        -- inside another site's low reach or short-range ring + margin pulls it back); still
        -- no ping there, it goes home (go cold "no shot")
        press_on_km = 20,
        low_fuel_factor = 1.5,
        max_order_steps = 3,
        -- the way in and out (low legs, climb-out) also keeps this far outside every enemy
        -- short-range SAM site's ring (SA-8 10 km, SA-15 12, Roland 8), which can't reach a
        -- cruising jet but can a low one (bug 22, 2026-10-01: MSN5024_SEAD_1 shot down by
        -- an SA-8 on its climb-out); the launch point too
        short_range_margin_km = 5,
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
        rules_of_engagement = "weapons_hold", takeoff = "air",
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

-- Standoff weapons (John, 2026-10-02: "we are doing air denial with standoff weapons, no
-- one should really be overflying targets"). A strike flight whose loadout carries one
-- (matched by its weapon name in data/aircraft_loadouts.lua) is routed to a release point
-- release_km short of its target, not over it: the "target" waypoint sits there, and the
-- way home turns back from it. Its route is priced (and its SEAD needs worked out) only to
-- that point. Each aircraft fires its weapons spread over the target's critical objects,
-- once (no re-attack). Untested in DCS: how far out the AI really releases each one.
-- A DEAD flight carrying one gets the same release-point route (bug 4, 2026-10-02); its
-- AttackGroup on the site still lets the AI close in if it can't fire from there.
--   name        a piece of the weapon's name
--   release_km  how far short of the target the release point sits
AIR_STANDOFF_WEAPONS = {
    { name = "Kh-59M",   release_km = 40 },   -- inertial standoff missile (real range ~115 km)
    { name = "KAB-500S", release_km = 8 },    -- satellite-guided glide bomb from ~5,000 m
    { name = "AGM-154",  release_km = 20 },   -- JSOW glide weapon (real ~22 km low, ~110 km high)
}

-- DEAD against a short-range SAM site (bug 4, 2026-10-02: Su-34s fired Kh-29Ts at a
-- Roland from 7–9 km, at the edge of its 8 km ring, and lost a jet each time; John: build
-- what completes missions and is realistic). Short-range sites have no SEAD in front of
-- them, so the DEAD flight itself must hit from out of the site's reach: its weapon
-- reaches at least the site's ring + reach_margin_km, or its attack height above the
-- site is at least the system's ceiling (SAM_SITE_RECIPE ceiling_km) + ceiling_margin_m.
-- The planner picks a DEAD loadout that does (AIRCRAFT_LOADOUT_OPTIONS); a target no
-- loadout of the aircraft can hit that way isn't taken by it. Medium and long-range
-- sites need no rule: a DEAD there waits until SEAD has put the site out of the fight.
-- Human flights carry their own weapons and aren't held to it.
--   weapon_reach_km  how far each non-standoff weapon reaches, by a piece of its name
--                    (a standoff weapon counts its release_km)
AIR_DEAD_WEAPONS = {
    reach_margin_km  = 5,
    ceiling_margin_m = 1000,
    weapon_reach_km  = {
        { name = "Kh-29T", reach_km = 9 },   -- TV-guided; Su-34s fired from 7–9 km (2026-09-30, 10-02 runs)
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
--   missions            { min, max } attack missions per mission window, not counting
--                       SEAD flights (the rotation's, and those an attack needs)
--   mission_types       { { mission type, weight } } — only built types are used
--   max_airborne_aircraft  AI aircraft of this coalition in the air at once, counting every
--                       AI attack and SEAD flight, the patrols, the AWACS and the scrambles;
--                       human flights and players never count (John, 2026-10-01)
--                       (one shared cap for now, John 2026-09-25). 12 since 2026-10-01 (was
--                       16; John: performance in VR). Planned flights fill it only up to
--                       AIR_DEFENSE.scramble_reserve_aircraft below it; the rest is kept
--                       for scrambles, which never go over it
--   window_s            missions start between first_start_s and the end of this window
--   first_start_s       earliest start (mission time), so the first flights are soon
--   taxi_s / attack_s / landing_s   time on the ground before takeoff, over the target,
--                       and from the landing base's overhead to shutdown (for timing only)
AIR_TASKING_PER_COALITION = {
    red = {
        missions = { 4, 6 }, max_airborne_aircraft = 12,
        mission_types = { { "strike", 3 }, { "airfield_strike", 2 }, { "destruction_of_air_defenses", 1 } },
    },
    blue = {
        missions = { 6, 8 }, max_airborne_aircraft = 12,
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
--   max_km_past_contested_when_cleared  deeper, up to this far, where the way is cleared:
--                          the route crosses SAM rings and every one of them already has a
--                          SEAD flight (roadmap item 12)
AIR_TARGETING = {
    max_km_past_contested   = 40,
    max_km_past_contested_when_cleared = 100,
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

-- SEAD before the flights that need it (roadmap item 12, John, 2026-10-02). A flight whose
-- route crosses threat rings lists them (requires_cleared) and launches only once they
-- are out of the fight, or isn't flown at all: a flight that needs SEAD never goes
-- without it. Each threat has at most one SEAD flight (the coalition's site table): the
-- rotation's, or one planned for the first attack whose route needs it; every flight
-- that needs that site waits on it. A flight starts strike_after_suppression_s after the
-- planned salvo of each SEAD flight it waits on (for battle damage assessment; not its
-- landing: real forces keep up the tempo), and at run time only if the site is out of
-- the fight (else the SEAD flight flies once more, then the flight is cancelled:
-- consumers/control_air_flights/decide_launches.lua). A player's strike or DEAD isn't
-- held: the AI SEAD flights it needs take off first thing and are over their sites at
-- least suppression_lead_s before the player is over the target.
--   suppression_lead_s  { min, max } seconds a SEAD flight is ahead of the player it opens
--                       the way for
--   strike_after_suppression_s  a flight starts this long after the planned salvo on each
--                       site it needs out of the fight
--   wait_for_room_s     at run time, a flight that would put the coalition over its cap
--                       (a late or early one) waits this long and looks again
--   come_back_after_s   a rotation site still in the fight after its SEAD flight and that
--                       flight's second try comes back into the rotation once more, this
--                       long after the second try is down (<id>_LATER, the same plan
--                       flown again); flights waiting on the site wait for it (2026-10-04,
--                       after the 2026-10-03 14:15 run: the Vuojarvi SA-10 survived two
--                       tries, and every Blue attack mission waited on it)
AIR_PACKAGE = {
    suppression_lead_s = { 180, 300 },
    strike_after_suppression_s = 600,
    wait_for_room_s = 120,
    come_back_after_s = 3600,
}

-- Human flights (session 10): Blue missions planned for players, listed at mission start
-- and in the F10 menu, flown from a player slot (data/player_slots.lua). Planned like the
-- AI's (same targets near the front, routes and SEAD flights), but one
-- aircraft of aircraft_type from a held base with a player slot, and timed from mission
-- start: takeoff after a cockpit startup of startup_s, over the target when the route
-- gets there; the AI SEAD flights it needs are timed around it. Never spawned: the player
-- spawns in on the slot. Planned after defensive air and before the AI attack missions.
--   coalition      the coalition players fly for
--   missions       planned every roll: the stage falls back to the other mission types,
--                  then to bases another human mission already uses, before giving up
--   mission_types  { type, weight }: every type a player can fly. A player's
--                  suppression_of_air_defenses takes a site the SEAD rotation opens
--                  with (nothing has to go before it), instead of the rotation; a
--                  player's combat_air_patrol flies one of the front stations
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
-- AWACS, one per coalition (two where its fronts are too far apart for one radar), on the
-- runway at mission start (2026-10-02, John: put it where its coalition fights; in the
-- 19:29 run Blue's E-3A, held 200 km from every enemy base, orbited off Bodø 460-550 km
-- from the player's Kola tasking, and two Red scrambles at him never reached Blue's
-- picture):
--   early_warning_start_s      mission time it is spawned
--   early_warning_weights      what it should see, weighed: each contested-airspace
--                              sample (front), each enemy target the attacks can reach ×
--                              its value (target), each enemy fighter base (scrambles)
--   early_warning_coverage_km  how far an orbit counts as seeing (a planning figure: the
--                              E-3A's first detections came at 120-210 km for jets low
--                              down, session 11; farther for jets high up)
--   early_warning_fighter_base_km  the orbit stays this far from every enemy fighter base
--   early_warning_front_km     and this far from the contested airspace, in own (not
--                              contested) airspace on own ground, the whole race-track
--                              outside every enemy kill zone by early_warning_clearance_km
--   early_warning_step_km      the grid the orbit and the front are sampled on
--   early_warning_max          at most this many AWACS, per coalition
--   early_warning_second_share a second when the first leaves more than this share of the
--   early_warning_second_gain  weight unseen and it would see at least this share
--   early_warning_tries        best orbits tried in turn when one can't be flown
--   early_warning_leg_km       length of its race-track
--   early_warning_legacy_standoff_km  the old orbit's distance from every enemy base, for a
--                              coalition with no orbit clear of the standoffs above
--
-- Scrambles (roadmap.md item 2; the plan holds the alert posture, consumers/control_air_flights/scramble_fighters.lua
-- reacts to the radar picture every round, the controller (consumers/control_air_flights/)
-- brings them home):
--   alert_posture_planned  false: no alert bases are planned, so nothing scrambles
--   alert bases           every held base whose runway and parking fit an interception
--                         type, outside enemy kill zones (John, 2026-10-02, bug 16: the 3
--                         nearest the enemy left Finnmark with none; was alert_bases = 3
--                         plus the nearest of each other region)
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
--   scramble_reserve_aircraft  of the coalition's max_airborne_aircraft, this many are kept
--                         free for scrambles: planned flights (attack and SEAD flights, patrols, AWACS) fill
--                         the cap only up to this many below it, and scrambles never go over
--                         it (John, 2026-10-01: so strikes can't fill the sky and leave no
--                         room to answer a raid; replaces scramble_over_cap, which let
--                         scrambles go 2 over)
--   scramble_takeoff_s    from the spawn, hot on the ramp, to wheels up (taxi and takeoff;
--                         86-290 s seen on 2026-10-01). With the reaction delay and the dash,
--                         the time to the intercept point: a scramble that would get there
--                         after the raid reaches what it threatens isn't sent (John, 2026-10-01)
--   scramble_min_leg_km   the intercept point (the raid pushed ahead along its heading,
--                         pulled back to own or contested airspace and out of enemy kill
--                         zones) must be at least this far from the base, or there's no
--                         way to the raid and the base doesn't answer
--   scramble_killzone_margin_km  the intercept point is also kept this far outside the
--                         leash's line (killzone_fraction of an enemy ring), so the leash
--                         doesn't send the jet home the moment it gets there (bug 8,
--                         2026-10-01: MSN2902 leashed 19 s after reaching its intercept point)
--   scramble_tail_chase_deg  a base answers a raid only if the raid's heading is within this
--                         many degrees of the line from the raid to the base (coming toward
--                         it or passing across it); one flying away from it is left to a
--                         base ahead of it (bug 16, 2026-10-01: a Hornet from Rovaniemi
--                         chased a raid flying north, away from it)
--   raid_radius_km, raid_heading_deg  contacts within this distance of the one that
--                         triggered, and within this many degrees of its heading, are one
--                         raid: one scramble, EngageGroup on each of them
AIR_DEFENSE = {
    planned               = true,
    killzone_fraction     = 0.85,
    -- a kill zone grows with the aircraft's height above the ground (lib/sam_reach.lua):
    -- the low-altitude reach up to the first, the full ring from the second (John,
    -- 2026-10-01: jets took off unharmed 60 km from a Blue SA-10 the high ring called
    -- deadly; bug 27, 2026-10-02: at the SEAD pop-up, ~900-3,200 m, the sites reached
    -- nearly their full envelope, so the low figure holds only close to the ground; were
    -- 3,000 / 7,000 m). No AI flight launches from a base inside an enemy site's
    -- low-altitude kill zone
    killzone_low_altitude_m  = 300,
    killzone_high_altitude_m = 3000,
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
    early_warning_weights      = { front = 1, target = 1, enemy_fighter_base = 3 },
    early_warning_coverage_km  = 250,
    early_warning_fighter_base_km = 150,
    early_warning_front_km     = 80,
    early_warning_step_km      = 20,
    early_warning_max          = { blue = 2, red = 1 },   -- Russia has few A-50s
    early_warning_second_share = 0.3,
    early_warning_second_gain  = 0.2,
    early_warning_tries        = 5,
    early_warning_clearance_km = 30,
    early_warning_leg_km       = 80,
    early_warning_legacy_standoff_km = 200,

    alert_posture_planned = true,
    alert_aircraft_per_base = 3,
    scramble_turnaround_s = 1800,
    scramble_cooldown_s   = 900,
    scramble_warning_min  = 15,
    scramble_inbound_rounds = 2,
    scramble_reaction_s   = { 60, 120 },
    scramble_reserve_aircraft = 2,
    scramble_takeoff_s    = 150,
    scramble_min_leg_km   = 10,
    scramble_killzone_margin_km = 10,
    scramble_tail_chase_deg = 100,
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
--                        goes through, and the rings it crosses need SEAD first
--   descent_km_per_km    the descent from cruise to attack altitude starts this many km
--                        before the ingress point per km of altitude lost (at least
--                        min_descent_km)
--   airspace_cost        what a km costs, on top of its threats, by the airspace it lies
--                        in as seen from the flight's coalition (plan.airspace): routes
--                        keep to own airspace, cross the contested zone where it's
--                        narrowest and avoid enemy airspace
-- Every enemy site is known (fixed sites are found by intelligence); a flight that has to
-- cross a ring lists it in requires_cleared, and launches only once a SEAD flight has
-- taken it out of the fight.
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
