-- The event log (logs/event_log.lua): a plain-language file per mission run
-- with every event of the air war, unit by unit, to watch live or comb through after
-- (roadmap.md item 3). Plain data, no logic.
--
-- Lines are held hold_s before they are written, so repeats can fold into one line
-- (a burst of gun hits, a stick of bombs, a kill that arrives just after the death);
-- the file is written every write_every_s. The sim never waits on the disk for more
-- than one write of a few lines.

EVENT_LOG = {
    -- one file per run, named by the wall clock, in the mission's folder in the repository
    -- (git-ignored; John: not in the DCS game folder): MISSION.event_log_folder, and
    -- MISSION.event_log_fallback_folder under Saved Games\DCS if that can't be written
    write_every_s   = 5,
    hold_s          = 10,

    -- repeats of the same thing within this many seconds of the last one fold into its line
    fold_hits_s     = 5,     -- the same shooter hitting the same target with the same weapon
    fold_shots_s    = 5,     -- the same shooter firing the same weapon (at the same target)
    fold_guns_s     = 10,    -- the same shooter opening fire with its guns again

    -- a POSITION line for every airborne aircraft this often (0 = off)
    position_every_s = 60,

    -- IMPACT lines (watch/weapon_impacts.lua): bombs and air-to-ground missiles
    -- from aircraft, followed to where they come down
    impact_every_s       = 0.1,   -- each followed weapon's position read this often (~30 m at 300 m/s)
    impact_follow_max    = 40,    -- at most this many followed at once (a big salvo's rest unlogged)
    impact_max_flight_s  = 900,   -- given up after this long in flight
    impact_air_burst_m   = 50,    -- gone higher than this above the ground: "gone in the air"
    impact_search_m      = 1500,  -- objects looked for this far around the impact (the nearest named
    impact_near_m        = 150,   --   when none is within impact_near_m; those within it listed,
    impact_list_max      = 4,     --   at most this many)
    impact_snapshot_s    = 1,     -- the objects' life before the blast read this long before it
    impact_snapshot_m    = 150,   --   comes down, or once it is this low (a missile flying flat)
    impact_settle_s      = 1.5,   -- the objects' life read again this long after the impact

    -- how wide the subject column is (longer names push the details right)
    subject_width   = 26,
}
