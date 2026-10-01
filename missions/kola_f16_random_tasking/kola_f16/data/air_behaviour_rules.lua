-- The rules the script enforces on AI flights after they launch
-- (consumers/enforce_air_behaviour_rules.lua). Plain data, no logic.
--
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
-- straight) when it has fired them all; when it presses more than press_km past its
-- launch point toward the site; when it is inside the kill zone of another SAM site; or
-- when it is still on the attack attack_time_s after its time at the launch point (the
-- site's radar never came on).

AIR_BEHAVIOUR_RULES = {
    suppression = {
        press_km           = 10,
        attack_time_s      = 600,
        killzone_fraction  = 0.85,
    },
    leash = {
        enemy_airspace_km  = 5,      -- as far past the contested airspace as it may go
        front_search_km    = 60,     -- how far to look for the contested airspace from deep inside enemy airspace
        killzone_fraction  = 0.85,   -- as patrols (AIR_DEFENSE.killzone_fraction)
    },
    -- a flight sent home flies straight to its base at cruise speed (a SEAD flight: by its
    -- way back) and only returns fire
    going_home_rules_of_engagement = "return_fire",
}
