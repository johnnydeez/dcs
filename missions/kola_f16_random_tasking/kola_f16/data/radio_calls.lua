-- Spoken radio calls (consumers/send_radio_calls.lua, announce_flight_activity.lua,
-- track_airfield_traffic.lua; roadmap.md item 7). Plain data, no logic.
--
-- The mission works out the facts of each call and writes them, one JSON line per call, to
-- calls_file. Outside DCS the radio helper (radio_calls/speak_mission_calls.py) reads that
-- file, words each call from its phrase bank, speaks it in a Windows voice and hands it to
-- the radio player, which plays it with a radio sound, only when one of the jet's radios
-- is tuned to the call's frequency (our export script, radio_calls/export_cockpit_radios.lua).
-- The mission never waits on them: with the helper down it plays as before, text only.
--
-- Who talks (Blue only for now):
--   Darkstar (AWACS channel): the picture every 2 min (with the on-screen list) and threat
--       calls at once (a hot hostile inside threat_nm);
--   AI flights: checking in and out with Darkstar (AWACS channel); their mission calls,
--       pushing, Fox, Magnum, Splash, defending, off target (mission channel), from what
--       they actually do (announce_flight_activity.lua), never from the controller's orders;
--   AI flights at Blue airfields: traffic calls on that field's own frequency, the way an
--       uncontrolled field works (track_airfield_traffic.lua), heard within airfield_range_nm.

RADIO_CALLS = {
    enabled     = true,
    coalitions  = { blue = true },

    -- the player's callsign as spoken, the same for every slot until slots carry their
    -- own (John, 2026-10-05: "Snake one one" for now)
    player_callsign = "Snake one one",
    -- the controller's callsign as spoken, per coalition
    awacs_callsign  = { blue = "Darkstar", red = "Overlord" },

    -- channels: each its own frequency, MHz, as on the F-16's radios (UHF AN/ARC-164,
    -- VHF AN/ARC-222). The airfields use their real tower frequencies from the map
    -- (data/airfield_frequencies.lua, VHF); a field the map gives none uses the common
    -- traffic frequency.
    channels = {
        awacs    = { mhz = 262.000, radio = "UHF", label = "Darkstar (AWACS)" },
        mission  = { mhz = 140.000, radio = "VHF", label = "mission (tactical common)" },
        airfield = { radio = "VHF", common_traffic_mhz = 122.800 },
    },

    -- threat call: the highest-threat group that is hot, its range known, inside this
    threat_nm        = 40,
    -- the same group called again for the same player only after this long
    threat_repeat_s  = 180,

    -- every kind of call: its priority (1 first: combat; 2 airfield; 3 routine), how long
    -- the radio player may hold it before it is old news (expires_s), and for the watcher's
    -- calls how long the same call from the same flight is folded into the one before
    -- (fold_s: four AIM-120s in a salvo are one "Fox three")
    kinds = {
        picture       = { priority = 3, expires_s = 90 },
        picture_clean = { priority = 3, expires_s = 90 },
        no_coverage   = { priority = 3, expires_s = 90 },
        threat        = { priority = 1, expires_s = 30 },
        airborne      = { priority = 3, expires_s = 45 },
        on_station    = { priority = 3, expires_s = 60 },
        pushing       = { priority = 3, expires_s = 30 },
        fox           = { priority = 1, expires_s = 8,  fold_s = 15 },
        magnum        = { priority = 1, expires_s = 8,  fold_s = 30 },
        rifle         = { priority = 1, expires_s = 8,  fold_s = 30 },
        bombs         = { priority = 1, expires_s = 8,  fold_s = 30 },
        splash        = { priority = 1, expires_s = 15, fold_s = 5 },
        defending     = { priority = 1, expires_s = 8,  fold_s = 30 },
        jet_down      = { priority = 1, expires_s = 20 },
        winchester    = { priority = 2, expires_s = 20 },
        bingo         = { priority = 2, expires_s = 30 },
        off_target    = { priority = 3, expires_s = 30 },
        check_out     = { priority = 3, expires_s = 45 },
        taxi          = { priority = 2, expires_s = 20 },
        departing     = { priority = 2, expires_s = 20 },
        inbound       = { priority = 2, expires_s = 20 },
        final         = { priority = 2, expires_s = 15 },
        clear         = { priority = 2, expires_s = 20 },
    },

    -- the watcher (announce_flight_activity.lua)
    watch_every_s        = 5,      -- flights' positions, fuel and weapons looked at this often
    rtb_heading_deg      = 35,     -- heading home: within this of the bearing to its landing base,
    rtb_closing_km       = 0.5,    --   closing on it by this much since the last look (~100 m/s),
    rtb_after_target_km  = 15,     --   and this much nearer home than its farthest point out
    on_station_km        = 20,     -- a patrol this close to its race-track is on station
    bingo_fuel           = 0.15,   -- "bingo": the lead's fuel (internal fraction) this low, and
    bingo_min_home_km    = 60,     --   still this far from its landing base

    -- airfield traffic (track_airfield_traffic.lua)
    airfield_every_s     = 3,      -- jets near Blue fields looked at this often
    airfield_range_nm    = 40,     -- a field's calls are made only with a player this close
                                   --   (a tower frequency's reach for a jet near the ground)
    taxi_speed_mps       = 3,      -- a jet on the ramp moving this fast is taxiing
    inbound_nm           = 10,     -- "inbound": a flight coming back to land (seen heading home,
                                   --   or already this slow and low) heading for its base this close
    inbound_max_mps      = 130,    --   (~250 kt)
    inbound_height_m     = 1500,
    final_km             = 9,      -- "final": lined up with a runway end this close,
    final_height_m       = 700,    --   this low above the field,
    final_max_mps        = 110,    --   at approach speed (~215 kt; a jet egressing low past its
                                   --   own base is far faster)
    final_aligned_deg    = 20,
    clear_after_landing_s = 25,    -- "clear of the runway" this long after touchdown

    -- where the calls go: one JSON line each, the file emptied at mission start
    calls_file    = "C:\\Users\\johnk\\Git\\dcs\\missions\\kola_f16_random_tasking\\radio_calls\\mission_calls.jsonl",
    -- started once at mission start (os.execute, "start" so DCS doesn't wait): the radio
    -- player (if it isn't running already) and the helper, in minimised windows
    start_command = "C:\\Users\\johnk\\Git\\dcs\\missions\\kola_f16_random_tasking\\radio_calls\\start_radio_calls.cmd",
}
