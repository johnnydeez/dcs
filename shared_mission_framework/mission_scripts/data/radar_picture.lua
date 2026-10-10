-- How each coalition's radar picture is kept (watch/radar_picture.lua). Plain
-- data, no logic.
--
-- Every poll_interval_s every sensor is asked once what its radar detects; the sensors
-- are spread over poll_slices steps so the questions don't all come at once. A contact
-- not seen for stale_after_s turns stale ("last seen N s ago"); after drop_after_s it is
-- dropped from the picture.
--
-- Sensors: ground groups come from the plan (SAM sites, base defenses) and count only
-- when a unit carries a radar (Unit:hasSensors). Flights count while airborne, by their
-- mission type. Attack flights and human flights are never sensors.

RADAR_PICTURE = {
    poll_interval_s  = 30,    -- one full round of every sensor (John: plenty often, also for AWACS calls)
    poll_slices      = 10,    -- the round is split into this many steps (one every 3 s)
    stale_after_s    = 60,    -- unseen this long → stale (two missed rounds; one missed sweep is normal)
    drop_after_s     = 300,   -- unseen this long → dropped
    log_every_s      = 300,   -- the periodic "picture:" summary line per coalition

    -- which kinds of sensor feed the picture
    sensor_kinds = {
        early_warning = true,   -- SAM sites with layer early_warning
        sam_search    = true,   -- every other SAM site, and its point-defense escort
        base_defense  = true,   -- base-defense groups of the components below
        awacs         = true,
        patrol        = true,
        scramble      = true,
    },
    -- base-defense components whose radars report to the network; gun fire-control radars
    -- (Shilka, Gepard, Vulcan) don't (John, 2026-09-30)
    base_defense_components = { radar_missile_launchers = true },
    -- flights whose own radars feed the picture while airborne, by mission type
    flight_sensor_kinds = {
        airborne_early_warning = "awacs",
        combat_air_patrol      = "patrol",
        interception           = "scramble",
    },

    -- inbound: the contact's heading line passes within threat_pass_km of an own asset (a
    -- held base or a catalog target) ahead of it; the soonest one is its threat_asset,
    -- threat_minutes away. Scrambles trigger on it; the leash uses it for "heading away"
    threat_pass_km        = 30,
    inbound_min_speed_mps = 50, -- slower than this is never inbound (orbiting, hovering)

    -- test aids for the first DCS run (roadmap item 1): log the first time a ground
    -- sensor's radar tracks each enemy group (Unit:getRadar), and count the missiles the
    -- radars list in the periodic summary
    log_radar_tracking = true,
    count_missiles     = true,
}
