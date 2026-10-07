-- Caucasus's radio channels for the spoken calls (the framework's consumers/send_radio_calls.lua;
-- every other radio setting is shared, data/radio_calls.lua). Each its own frequency, MHz,
-- as on the F-16's radios (UHF AN/ARC-164, VHF AN/ARC-222), clear of the map's tower
-- frequencies: those run VHF 121.000–141.000 and UHF 250.000–270.000, one per field
-- (data/airfield_frequencies.lua), so Kola's 140.000 / 262.000 would land on Vaziani's and
-- Kobuleti's towers; these sit just past the towers' ranges. The airfields use their real
-- tower frequencies; a field the map gives none uses the common traffic frequency.
-- Plain data, no logic.

RADIO_CHANNELS = {
    awacs    = { mhz = 272.000, radio = "UHF", label = "Darkstar (AWACS)" },
    mission  = { mhz = 143.000, radio = "VHF", label = "mission (tactical common)" },
    airfield = { radio = "VHF", common_traffic_mhz = 122.800 },
}
