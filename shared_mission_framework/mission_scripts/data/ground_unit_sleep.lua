-- Which ground units sleep while no enemy aircraft is near, and when they wake
-- (controller/wake_ground_units.lua; roadmap.md, performance in VR). Plain data, no logic.
--
-- A sleeping group has its AI switched off (Controller:setOnOff(false)): it doesn't scan
-- the sky or think, which is most of what ~500 base-defense units cost while nothing is
-- near them. Everything that reaches less than ~10 km sleeps; it wakes, a base at a time,
-- when an enemy aircraft comes within wake_km, long before it can be in reach. SAM sites
-- never sleep: they are the air denial. The whole thing is switched off with
-- CONFIG.SLEEP_GROUND_UNITS.

GROUND_UNIT_SLEEP = {
    -- base-defense components that sleep. radar_missile_launchers (Pantsir, Tor, Roland)
    -- stay awake: they reach ~20 km, and their radars feed the radar picture
    -- (RADAR_PICTURE.base_defense_components)
    components = {
        towed_anti_aircraft_guns        = true,
        mobile_anti_aircraft_guns       = true,
        infrared_missile_launchers      = true,
        shoulder_launched_missile_teams = true,
        security_infantry               = true,   -- not fielded since 2026-10-01; sleeps if it comes back
    },
    wake_km         = 30,    -- a base's sleeping groups wake when an enemy aircraft is this close to the base
    reach_km        = 10,    -- inside every sleeping weapon's reach: an enemy here while the base sleeps is a
                             -- LATE_WAKE warning; one here while it's awake is a close pass for the summary
    check_every_s   = 10,    -- how often every base is checked against every enemy aircraft
    sleep_after_s   = 180,   -- back to sleep this long after the last enemy aircraft left wake_km and the
                             -- base's last shot, so a base doesn't flap while a jet orbits near the edge
    summary_every_s = 300,   -- the AWAKE_COUNT line per coalition
}
