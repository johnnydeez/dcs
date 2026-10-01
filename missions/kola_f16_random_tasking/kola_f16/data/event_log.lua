-- The event log (consumers/write_event_log.lua): a plain-language file per mission run
-- with every event of the air war, unit by unit, to watch live or comb through after
-- (roadmap.md item 3). Plain data, no logic.
--
-- Lines are held hold_s before they are written, so repeats can fold into one line
-- (a burst of gun hits, a stick of bombs, a kill that arrives just after the death);
-- the file is written every write_every_s. The sim never waits on the disk for more
-- than one write of a few lines.

EVENT_LOG = {
    -- one file per run, named by the wall clock, in the repository (git-ignored; John: not
    -- in the DCS game folder). If that can't be written, fallback_folder under Saved Games\DCS
    folder          = "C:\\Users\\johnk\\Git\\dcs\\missions\\kola_f16_random_tasking\\event_logs",
    fallback_folder = "kola_event_logs",
    write_every_s   = 5,
    hold_s          = 10,

    -- repeats of the same thing within this many seconds of the last one fold into its line
    fold_hits_s     = 5,     -- the same shooter hitting the same target with the same weapon
    fold_shots_s    = 5,     -- the same shooter firing the same weapon (at the same target)
    fold_guns_s     = 10,    -- the same shooter opening fire with its guns again

    -- a POSITION line for every airborne aircraft this often (0 = off)
    position_every_s = 60,

    -- how wide the subject column is (longer names push the details right)
    subject_width   = 26,
}
