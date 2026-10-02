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
--   (safety first): stand down > home > resume > defend.
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
-- check_every_s; John, 2026-10-02: no waiting once the salvo is away); when it presses more than press_km past its
-- launch point toward the site; when it is inside the kill zone of another SAM site
-- (at its altitude: low on the run-in, a site reaches only its low-altitude figure); or
-- when it is still on the attack attack_time_s after it came within arrival_km of its
-- launch point (the site's radar never came on). The clock starts on arrival, not at
-- the planned time, so a flight that took off late still gets its shot (bug 20).

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
-- farther than warning_range_km, after max_engage_s, when the flight is out of radar
-- missiles, or when the fight takes it into an enemy kill zone (killzone_fraction of
-- how far a site reaches at its altitude) its route doesn't pass through on purpose.
-- After that it engages again only after reengage_after_s.

AIR_CONTROL = {
    check_every_s = 5,

    directives_by_mission_type = {
        strike                      = { "self_defence" },
        airfield_strike             = { "self_defence" },
        destruction_of_air_defenses = { "self_defence" },
        suppression_of_air_defenses = { "suppression", "self_defence" },
        interception                = { "leash" },
    },

    intent_priority = { stand_down = 4, home = 3, resume = 2, defend = 1 },

    going_home_rules_of_engagement = "return_fire",

    suppression = {
        press_km           = 10,
        arrival_km         = 15,     -- this close to its launch point it has arrived (the AI starts its attack ~12 km out)
        attack_time_s      = 600,
        killzone_fraction  = 0.85,
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
    },
}
