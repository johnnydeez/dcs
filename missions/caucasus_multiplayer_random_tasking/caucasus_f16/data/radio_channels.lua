-- Caucasus's radio channels for the spoken calls (the framework's consumers/send_radio_calls.lua;
-- every other radio setting is shared, data/radio_calls.lua). Each its own frequency, MHz,
-- as on the F-16's radios (UHF AN/ARC-164, VHF AN/ARC-222), clear of the map's tower
-- frequencies: those run VHF 121.000–141.000 and UHF 250.000–270.000, one per field
-- (data/airfield_frequencies.lua), so Kola's 140.000 / 262.000 would land on Vaziani's and
-- Kobuleti's towers; these sit just past the towers' ranges. The airfields use their real
-- tower frequencies; a field the map gives none uses the common traffic frequency.
--
-- awacs_per_player_slot: each player slot's own Darkstar frequency (roadmap.md item 19,
-- John, 2026-10-07): that player's picture and threat calls are on it, and every call
-- Darkstar makes to all (its orders to AI flights, check-ins and check-outs, the pilots'
-- answers and reports) too, so each player hears on their own frequency what one player
-- hears on the AWACS channel alone, and not the other player's picture. Keyed by the
-- slot's group name (data/player_slots.lua); a slot not listed uses the AWACS channel.
-- UHF, past the towers (250.000-270.000) and the AWACS channel; per base, the F-16 then
-- the F/A-18. map_data_tools/miz_radio_presets.py puts each on its slot's radio 1,
-- channel 1, in the flyable .miz.
-- Plain data, no logic.

RADIO_CHANNELS = {
    awacs    = { mhz = 272.000, radio = "UHF", label = "Darkstar (AWACS)" },
    mission  = { mhz = 143.000, radio = "VHF", label = "mission (tactical common)" },
    airfield = { radio = "VHF", common_traffic_mhz = 122.800 },
    awacs_per_player_slot = {
        f16_batumi   = 273.000, f18_batumi   = 273.500,
        f16_gudauta  = 274.000, f18_gudauta  = 274.500,
        f16_kobuleti = 275.000, f18_kobuleti = 275.500,
        f16_sukhumi  = 276.000, f18_sukhumi  = 276.500,
        f16_tbilisi  = 277.000, f18_tbilisi  = 277.500,
    },
}
