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

AIR_BEHAVIOUR_RULES = {
    leash = {
        enemy_airspace_km  = 5,      -- as far past the contested airspace as it may go
        front_search_km    = 60,     -- how far to look for the contested airspace from deep inside enemy airspace
        killzone_fraction  = 0.85,   -- as patrols (AIR_DEFENSE.killzone_fraction)
    },
    -- a flight sent home flies straight to its base at cruise speed and only returns fire
    going_home_rules_of_engagement = "return_fire",
}
