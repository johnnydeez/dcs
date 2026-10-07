-- Player slots parsed from caucasus_multiplayer_random_tasking.miz by map_data_tools/miz_player_slots.py — do not hand-edit;
-- move or add slots in the mission editor and re-run the tool. Plain data, no logic.
--
-- DCS always spawns a dynamic-spawn player on the template's exact parking spot, so the
-- planner keeps AI aircraft (parked static aircraft, AI flights) off these spots.
--
--   PLAYER_SLOTS[airbase] = list of
--     terminal_index  DCS parking spot index (Airbase:getParking() Term_Index)
--     spot            the spot's name in the mission editor
--     group           the ME group name
--     type            aircraft type
--     x, z            DCS projected metres (x = north, z = east)

PLAYER_SLOTS = {
    ["Batumi"] = {
        { terminal_index = 2, spot = "06", group = "f16_batumi", type = "F-16C_50", x = -356070, z = 618235 },
    },
    ["Gudauta"] = {
        { terminal_index = 17, spot = "17", group = "f16_gudauta", type = "F-16C_50", x = -196722, z = 515803 },
    },
    ["Kobuleti"] = {
        { terminal_index = 37, spot = "10", group = "f16_kobuleti", type = "F-16C_50", x = -318253, z = 635494 },
    },
    ["Sukhumi-Babushara"] = {
        { terminal_index = 23, spot = "19", group = "f16_sukhumi", type = "F-16C_50", x = -219803, z = 564289 },
    },
    ["Tbilisi-Lochini"] = {
        { terminal_index = 34, spot = "05", group = "f16_tbilisi", type = "F-16C_50", x = -314771, z = 896635 },
    },
}
