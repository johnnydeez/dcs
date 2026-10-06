-- The air picture shown to human players (consumers/call_air_picture.lua, roadmap.md
-- item 5). Plain data, no logic.
--
-- Every call_every_s each player in an aircraft gets a list of every contact in their own
-- coalition's radar picture (consumers/track_radar_picture.lua: only what its radars
-- see), highest threat first, each as BRAA from the player's own position: magnetic
-- bearing, range in nautical miles, altitude in thousands of feet, aspect (John,
-- 2026-10-02: no bullseye, no request needed; short lines read at a glance:
-- "MiG-29S - 110/120nm, 10k, hot, 5s", the last number how old the position is).

AIR_PICTURE_CALLS = {
    enabled      = true,
    call_every_s = 120,     -- John, 2026-10-02: every 2 min is enough
    show_s       = 14,      -- long enough to read, then off the screen (John, 2026-10-02; was 7)
    on_the_ground = true,   -- also before takeoff (the picture is useful on the ramp)
    max_groups   = 10,      -- lines in one list; the rest are counted ("+3 more")

    -- the controller's callsign in the header, per coalition (DCS's AWACS callsigns)
    callsign = { blue = "DARKSTAR", red = "OVERLORD" },

    -- aspect: the angle between the contact's heading and the line from it to the player
    -- (brevity: hot 0–30°, flank 40–70°, beam 70–110°, drag past 110°; the gap at 30–40
    -- goes to flank)
    hot_deg   = 30,
    flank_deg = 70,
    beam_deg  = 110,
    -- threat order: range × this factor, smallest first (a hot group at 40 nm comes
    -- before one dragging at 20 nm)
    threat_range_factor = { hot = 1, flank = 1.5, beam = 2, drag = 3 },

    -- (the magnetic variation when DCS's magvar module doesn't answer, and the airbase its
    -- start-up self-test asks about, are the map's: MISSION.fallback_magnetic_variation,
    -- MISSION.magnetic_variation_check_airbase)

    log_calls = true,       -- one PICTURE_CALL line per player per call in the event log

    -- coverage: a player outside every live sensor's reach gets "no radar coverage your
    -- area" instead of a clean picture (2026-10-02, John: two Red scrambles closed on him
    -- unseen while the picture read clean). Reach at the player's height, each no farther
    -- than the radar horizon. Planning figures, to tune from the CONTACT lines' "seen by
    -- … km away" (the E-3A's first detections came at 120-210 km for jets low down,
    -- session 11)
    coverage = {
        awacs_km          = 250,   -- an AWACS (AIR_DEFENSE.early_warning_coverage_km)
        fighter_km        = 80,    -- a patrol's or scramble's own radar
        ground_max_km     = 300,   -- a ground radar: its type's detection range, at most this
        ground_default_km = 60,    -- a ground radar whose types the unit pool has no range for
        radar_height_m    = 10,    -- a ground radar's antenna above its ground, for the horizon
    },
}
