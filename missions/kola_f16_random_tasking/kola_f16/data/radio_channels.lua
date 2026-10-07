-- Kola's radio channels for the spoken calls (the framework's consumers/send_radio_calls.lua;
-- every other radio setting is shared, data/radio_calls.lua). Each its own frequency, MHz,
-- as on the F-16's radios (UHF AN/ARC-164, VHF AN/ARC-222), clear of the map's tower
-- frequencies. The airfields use their real tower frequencies from the map
-- (data/airfield_frequencies.lua, VHF); a field the map gives none uses the common
-- traffic frequency. Plain data, no logic.

RADIO_CHANNELS = {
    awacs    = { mhz = 262.000, radio = "UHF", label = "Darkstar (AWACS)" },
    mission  = { mhz = 140.000, radio = "VHF", label = "mission (tactical common)" },
    airfield = { radio = "VHF", common_traffic_mhz = 122.800 },
}
