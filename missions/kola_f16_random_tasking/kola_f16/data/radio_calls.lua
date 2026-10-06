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
--       uncontrolled field works (track_airfield_traffic.lua), heard within airfield_range_nm;
--   Darkstar's orders to AI flights (AWACS channel): the controller's decisions that are
--       orders to a flight in the air, engage, resume, RTB, land, a scramble's vector
--       (announce_controller_orders.lua, listening to the controller's decisions);
--       a decision only the pilot could make (fuel, weapons, no shot) is said as the
--       pilot's report instead, and Darkstar says "copy" (roadmap item 7 step 15);
--   the pilots' answers to Darkstar's orders (AWACS channel), once the flight is seen
--       following the order (announce_flight_activity.lua); none when it doesn't.

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
        -- splash and jet down outlast one Darkstar picture (~25 s) on the other radio, as
        -- calls never overlap (bug 70, 00:16 run: both jet-down calls queued behind a
        -- picture and were dropped at 20 s); a Fox call that late is no news, so it goes
        splash        = { priority = 1, expires_s = 40, fold_s = 5 },
        defending     = { priority = 1, expires_s = 8,  fold_s = 30 },
        jet_down      = { priority = 1, expires_s = 45 },
        winchester    = { priority = 2, expires_s = 20 },
        bingo         = { priority = 2, expires_s = 30 },
        off_target    = { priority = 3, expires_s = 30 },
        check_out     = { priority = 3, expires_s = 45 },
        taxi          = { priority = 2, expires_s = 20 },
        departing     = { priority = 2, expires_s = 20 },
        inbound       = { priority = 2, expires_s = 20 },
        final         = { priority = 2, expires_s = 15 },
        clear         = { priority = 2, expires_s = 20 },
        -- Darkstar's orders (a "leave", RTB with a bandit hot and nothing to fight it, goes at priority 1)
        engage          = { priority = 1, expires_s = 15 },
        resume          = { priority = 3, expires_s = 20 },
        return_to_base  = { priority = 3, expires_s = 30 },
        land_at         = { priority = 2, expires_s = 30 },
        scramble_vector = { priority = 1, expires_s = 20 },
        -- a pilot's report of a decision only the pilot could make (bingo, Magnum
        -- complete, no emitter, Winchester), then Darkstar's "copy" of it
        report          = { priority = 2, expires_s = 30 },
        acknowledge     = { priority = 2, expires_s = 30 },
        -- a pilot's answer to an order: at its order's priority, so it plays after it
        answer          = { priority = 3, expires_s = 20 },
    },

    -- Darkstar's orders (announce_controller_orders.lua)
    orders = {
        engage_fold_s         = 90,   -- an engage on the same bandit to the same flight said once in this long
                                      --   (a fight broken off for a SAM ring is called again 30 s later)
        vector_after_takeoff_s = 4,   -- a scramble's vector this long after its takeoff, after the
                                      --   pilot's own airborne call
        -- the controller's reasons only the pilot would know (what is inside the jet: fuel,
        -- weapons, whether the target's radar showed): said as the pilot's report, and
        -- Darkstar's "copy", not as Darkstar's order (John, 2026-10-06: a controller can't
        -- see a jet's fuel)
        pilot_reasons = { bingo = true, salvo_complete = true, salvo_over = true, no_shot = true,
                          out_of_missiles = true },
    },

    -- the pilots' answers to Darkstar's orders (announce_flight_activity.lua): an answer
    -- once the flight is seen following the order, within that order's time; none after it
    -- (event log: "no answer"); a newer order to the flight replaces one not yet answered
    answers = {
        every_s     = 2,      -- flights waiting to answer looked at this often
        within_s    = { engage = 30, resume = 30, return_to_base = 45, land_at = 60, scramble_vector = 45 },
        toward_deg  = 30,     -- engage / vector: the lead's nose within this of the bandit
        route_deg   = 45,     -- resume: within this of one of its next two waypoints
        home_deg    = 35,     -- RTB / land / continue RTB: within this of its base,
        home_looks  = 2,      --   this many looks in a row
    },

    -- the watcher (announce_flight_activity.lua)
    watch_every_s        = 5,      -- flights' positions, fuel and weapons looked at this often
    rtb_heading_deg      = 35,     -- heading home: within this of the bearing to its landing base,
    rtb_closing_km       = 0.5,    --   closing on it by this much since the last look (~100 m/s),
    rtb_after_target_km  = 15,     --   and this much nearer home than its farthest point out
    bingo_fuel           = 0.15,   -- "bingo": the lead's fuel (internal fraction) this low, and
    bingo_min_home_km    = 60,     --   still this far from its landing base

    -- airfield traffic (track_airfield_traffic.lua)
    airfield_every_s     = 3,      -- jets near Blue fields looked at this often
    airfield_range_nm    = 40,     -- a field's calls are made only with a player this close
                                   --   (a tower frequency's reach for a jet near the ground)
    taxi_speed_mps       = 3,      -- a jet on the ramp moving this fast is taxiing
    lineup_margin_m      = 15,     -- "departing": a taxiing jet inside a runway's strip (this
    lineup_aligned_deg   = 20,     --   much beyond its edges and ends), nose within this of
                                   --   one of its directions: lined up (bug 67)
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
