-- Spoken AWACS calls (consumers/send_radio_calls.lua, roadmap.md item 7). Plain data, no
-- logic.
--
-- The mission works out the facts of each call (the same ones as the on-screen air
-- picture) and writes them, one JSON line per call, to calls_file. Outside DCS the radio
-- helper (radio_calls/speak_mission_calls.py) reads that file, words each call from
-- radio_calls/awacs_phrases.json, speaks it in a Windows voice and hands it to the radio
-- player, which plays it with a radio sound. The mission never waits on them: with the
-- helper down it plays as before, text only.
--
-- Calls (John, 2026-10-05): Darkstar's picture on the same 2-min cycle as the text, and
-- a threat call at once (on the radar picture's 30-s round) when a hot hostile comes
-- inside threat_nm. Blue only, one frequency, one player callsign for now.

RADIO_CALLS = {
    enabled     = true,
    coalitions  = { blue = true },

    -- the player's callsign as spoken, the same for every slot until slots carry their
    -- own (John, 2026-10-05: "Snake one one" for now)
    player_callsign = "Snake one one",

    -- threat call: the highest-threat group that is hot, its range known, inside this
    threat_nm        = 40,
    -- the same group called again for the same player only after this long
    threat_repeat_s  = 180,

    -- where the calls go: one JSON line each, the file emptied at mission start
    calls_file    = "C:\\Users\\johnk\\Git\\dcs\\missions\\kola_f16_random_tasking\\radio_calls\\mission_calls.jsonl",
    -- started once at mission start (os.execute, "start" so DCS doesn't wait): the radio
    -- player (if it isn't running already) and the helper, in minimised windows
    start_command = "C:\\Users\\johnk\\Git\\dcs\\missions\\kola_f16_random_tasking\\radio_calls\\start_radio_calls.cmd",
}
