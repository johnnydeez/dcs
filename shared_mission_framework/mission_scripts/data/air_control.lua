-- How the controller directs AI flights after they launch
-- (consumers/control_air_flights/). Plain data, no logic.
--
-- The controller watches every AI flight whose mission type has directives here. Each
-- check it builds the flight's situation (what the coalition knows: its radar picture,
-- the flight's own state, the plan), asks each of the flight's directives what the
-- flight should do, picks one intent and turns it into DCS orders, only when the intent
-- changes. DCS AI is the pilot; this is the controller feeding it calls (John, 2026-10-01).
--
-- directives_by_mission_type: which directives watch a flight of each mission type, in
--   the order they are asked. A mission type with none isn't watched.
-- check_every_s: the fast check, for directives that can't wait for the radar picture's
--   round (self_defence). leash and suppression run on the picture's round (30 s).
-- intent_priority: when directives want different things, the higher number wins
--   (safety first): remove > stand down > land > home > resume > defend.
-- going_home_rules_of_engagement: what a flight sent home may still shoot at.

-- leash: a scramble chases its raid away or kills it, without flying head first into
-- enemy airspace (John, 2026-09-30). It goes home when every group of its raid is dead,
-- dropped from the radar picture, or back over its own airspace heading away (the
-- picture's inbound flag); or when it has gone
-- more than enemy_airspace_km into enemy airspace, or into an enemy kill zone (a
-- killzone_fraction of a medium / long-range SAM ring, AIR_ROUTING.threat_layers).
-- While a raid group is only stale in the picture, the scramble keeps after it.
-- A scramble whose raid is gone before it leaves the ramp is stood down (removed).

-- suppression: a SEAD flight dumps its anti-radiation missiles at its SAM site from the
-- launch point and goes cold (John, 2026-10-01). It is sent home (by its way back, not
-- straight) when it has fired them all (checked the moment it fires one, and every
-- check_every_s; John, 2026-10-02: no waiting once the salvo is away); when it reaches
-- its press-on point having fired nothing ("no shot": no radar to shoot at; bug 36, John,
-- 2026-10-02: on along the same track until a radar ping, then home as planned); when it
-- presses more than press_km past its press-on point (its launch point on a plan without
-- one) toward the site; when it is inside the kill zone of another SAM site
-- (at its height above the ground: low on the run-in, a site reaches only its
-- low-altitude figure; not from the pop-up through the press-on leg while it has
-- missiles aboard, the plan's accepted exposure, roadmap item 12); or
-- when it is still on the attack attack_time_s after it came within arrival_km of its
-- launch point (the site's radar never came on). The clock starts on arrival, not at
-- the planned time, so a flight that took off late still gets its shot (bug 20).

-- suppression, also: a flight with no press-on point (none clear of the other sites)
-- that has reached its launch point and still has every anti-radiation missile
-- no_shot_after_s later gets one "no shot" line (bug 29: the AI retry on the Vuojarvi
-- Tor reached its launch point, fired nothing and flew home).

-- handover: a patrol goes home once the next patrol on its station is there (within
-- on_station_km of the race-track) and on task (John, 2026-10-01, bug 18: rotations
-- overlap, and a short transit made the old and the new patrol fly the race-track
-- together for 17 min). The planned overlap stays the latest handover time.

-- landing: every AI flight on its way home (sent home, past its planned landing, or with
-- a jet already landed) is watched until it is down. A jet getting away_km farther from
-- its landing base than it has been since, or still in the air overdue_s after the
-- flight's planned landing, is lost: the flight gets a new landing order straight to its
-- base, at most max_orders times (bug 19, 2026-10-01: MSN5025_SEAD_2 missed its landing
-- and flew on for 300 km). The order waits while a jet of the flight that landed is still
-- on the ramp (it is removed 3 min after landing), so it never sends that one up again.
-- A jet still in the air orphan_remove_after_s after its flight's last landing is
-- removed and counted as landed, so whatever waits on the flight sees it down (bug 19,
-- 2026-10-02, John: 7 of 13 wingmen whose lead landed first never came out of their
-- holding pattern and flew a straight line, ignoring landing orders; the latest wingman
-- that did land came down 7.5 min after its lead).

-- fuel: patrols, scrambles and the AWACS go home at bingo (bug 60, 2026-10-05: the MiG-31 patrol
-- MSN7016_CAP fought on from 19 % and went down with empty tanks; DCS's own return at
-- bingo didn't bring it home). Bingo for a jet is reserve_fraction plus what it burns
-- flying straight to its landing base: km / its combat radius (AIRCRAFT_PROFILE) ×
-- home_fraction_per_radius. The jet with the least to spare decides for the flight. A
-- flight already going home that is fighting a bandit breaks the fight off instead.
-- Checked on the picture's round (30 s). "bingo: bingo fuel: MSN7016_CAP at 19 %, 110 km
-- from Koshka Yavr (needs 17 %)". Not attack flights for now: they are planned out to
-- their combat radius (a Su-34 at 677 of 700 km), so the same rule could turn a strike
-- back short of its target; they fly their route and DCS brings them home.

-- self_defence: the controller calls a bandit as soon as the coalition's radar picture
-- shows it coming for an attack flight, and decides at once (John, 2026-10-01: "you
-- would tell them immediately a fighter is inbound"). A bandit is an enemy airplane the
-- picture holds within warning_range_km, pointed at the flight (its heading within
-- hot_aspect_deg of the line to the flight) and closing at min_closing_speed_mps or
-- more, on hot_checks_before_call fast checks in a row (so a patrol's race-track leg
-- swinging past doesn't count); or one that fired at the flight in the last
-- shot_memory_s, at any range.
--   can fight (radar-guided air-to-air missiles aboard; infrared ones alone don't count,
--   John): defend, the flight engages the bandit at once and the DCS AI flies the
--   intercept and shoots when its missiles allow. After the fight it always carries on
--   with its mission ("that's what they are there for after all").
--   can't fight: leave, the flight goes home (a patrol isn't going anywhere: it stays
--   on station and circles, John).
-- A flight engages one bandit (another flight of the coalition never takes the same
-- one) and goes back to its mission when the bandit is destroyed, dropped from the
-- picture, turned cold (heading more than cold_aspect_deg off the line to the flight),
-- farther than warning_range_km, after max_engage_s (not while a missile of the flight is
-- still flying, nor within shot_memory_s of being fired upon: 2026-10-04, both SEAD duels
-- of the 2026-10-03 14:15 run were timed out the moment the missiles were in the air),
-- when the flight is out of radar missiles, or when the fight takes it into an enemy
-- kill zone (killzone_fraction of how far a site reaches at its altitude; not a site out
-- of the fight, its radars destroyed) its route doesn't pass through on purpose.
-- After that it engages again only after reengage_after_s; a bandit it broke off for a
-- kill zone, not while the flight is still inside one.
-- A SEAD flight isn't the air-to-air asset (John, 2026-10-02, bug 39): with its
-- anti-radiation missiles aboard it commits only when fired upon, or when the bandit is
-- hot inside sead_commit_km (outside its shot area); otherwise it stays low on its route,
-- or finishes its salvo, and says "press on" once per bandit. After its salvo the same
-- holds on its way home (John, 2026-10-04: in the 2026-10-03 14:15 run 10 of 15 losses
-- were SEAD jets fighting after their salvoes). Its fight is broken off for any kill
-- zone by height (every live site, silenced or not), its own target's included, outside
-- its shot area, and for none inside it.

-- suppression, also: once one jet of a SEAD flight has fired its last anti-radiation
-- missile, the others get salvo_time_s, then the flight goes cold with whatever is left
-- ("salvo over"; bug 40: a wingman firing one HARM at a time for 76 s inside an SA-10's
-- envelope died).
-- While the salvo is going, pressing past press_km doesn't send it home: not for
-- press_after_shot_s after each anti-radiation missile the flight fires (bug 58,
-- 2026-10-05: with no press-on point the limit is the launch point + 5 km, which the
-- Su-34s passed 10 s into their salvo; twice the lead went home with all 4 aboard).

AIR_CONTROL = {
    check_every_s = 5,

    directives_by_mission_type = {
        strike                      = { "self_defence", "landing" },
        airfield_strike             = { "self_defence", "landing" },
        destruction_of_air_defenses = { "self_defence", "landing" },
        suppression_of_air_defenses = { "suppression", "self_defence", "landing" },
        interception                = { "leash", "fuel", "landing" },
        combat_air_patrol           = { "handover", "fuel", "landing" },
        airborne_early_warning      = { "fuel", "landing" },
    },

    intent_priority = { remove = 6, stand_down = 5, land = 4, home = 3, resume = 2, defend = 1 },

    going_home_rules_of_engagement = "return_fire",

    suppression = {
        press_km           = 5,      -- past its press-on point (was 10 past the launch point until bug 36)
        arrival_km         = 15,     -- this close to its launch point it has arrived (the AI starts its attack ~12 km out)
        attack_time_s      = 600,
        killzone_fraction  = 0.85,
        no_shot_after_s    = 120,
        salvo_time_s       = 20,     -- once one jet is empty, the rest of the flight gets this long (bug 40)
        press_after_shot_s = 30,     -- press_km doesn't count this long after each anti-radiation missile fired (bug 58)
    },
    handover = {
        on_station_km      = 15,
    },
    fuel = {
        reserve_fraction         = 0.10,   -- of internal fuel, left on landing
        home_fraction_per_radius = 0.5,    -- fuel to fly home one combat radius (a MiG-31 burned ~1 % per 17 km cruising)
        default_combat_radius_km = 600,    -- a type with no profile
    },
    landing = {
        away_km            = 20,
        overdue_s          = 1200,
        max_orders         = 2,
        orphan_remove_after_s = 480, -- 8 min after the flight's last landing
    },
    leash = {
        enemy_airspace_km  = 5,      -- as far past the contested airspace as it may go
        front_search_km    = 60,     -- how far to look for the contested airspace from deep inside enemy airspace
        killzone_fraction  = 0.85,   -- as patrols (AIR_DEFENSE.killzone_fraction)
    },
    self_defence = {
        warning_range_km                 = 100,
        hot_aspect_deg                   = 45,
        min_closing_speed_mps            = 50,
        hot_checks_before_call           = 2,
        shot_memory_s                    = 30,
        cold_aspect_deg                  = 110,
        max_engage_s                     = 180,
        reengage_after_s                 = 30,
        killzone_fraction                = 0.85,
        sead_commit_km                   = 25,    -- a SEAD flight with missiles aboard commits only this close, or fired upon (bug 39)
    },
}
