"""A mission's folder, as the map data tools see it.

    mission = MissionFolder(r"C:\\Users\\johnk\\Git\\dcs\\missions\\kola_f16_random_tasking")
    mission.map_name                          "Kola"
    mission.data_file("zones.lua")            <mission>\\kola_f16\\data\\zones.lua
    mission.map_data_source("kola_airbases.json")   <mission>\\map_data_sources\\kola_airbases.json
    mission.setting("flyable_mission_file")   any value of the mission's MISSION table

What a tool needs to know about a mission comes from the mission's own
mission_settings.lua (the MISSION table the mission's scripts read in DCS too), so each
fact is written once: the mission's scripts folder (the one subfolder holding a
mission_settings.lua), its map, its file names. A missing setting stops the tool, naming
the setting and the file.

The framework's own folders (FRAMEWORK_DATA_FOLDER: the shared data the DCS-wide tools
write) are found from where this file is: shared_mission_framework\\map_data_tools\\.
Stdlib only.
"""

import glob
import os

import dcslua

TOOLS_FOLDER = os.path.dirname(os.path.abspath(__file__))
FRAMEWORK_FOLDER = os.path.dirname(TOOLS_FOLDER)
FRAMEWORK_DATA_FOLDER = os.path.join(FRAMEWORK_FOLDER, "mission_scripts", "data")
SAVED_GAMES_DCS = os.path.join(os.path.expanduser("~"), "Saved Games", "DCS")

MISSION_FOLDER_HELP = ("the mission's folder (missions\\<mission>); its map, data folder and file names "
                       "come from its mission_settings.lua")


class MissionFolder:
    def __init__(self, path):
        self.path = os.path.abspath(path)
        found = glob.glob(os.path.join(self.path, "*", "mission_settings.lua"))
        if len(found) != 1:
            raise SystemExit("%s: expected one <scripts folder>\\mission_settings.lua in it, found %d"
                             % (self.path, len(found)))
        self.settings_file = found[0]
        with open(self.settings_file, encoding="utf-8") as f:
            self.settings = dcslua.loads(f.read())   # MISSION = { ... }: the table
        self.scripts_folder = os.path.dirname(self.settings_file)
        if os.path.basename(self.scripts_folder) != self.setting("scripts_folder"):
            raise SystemExit("%s: MISSION.scripts_folder is %r, but the file is in %s"
                             % (self.settings_file, self.setting("scripts_folder"), self.scripts_folder))
        self.data_folder = os.path.join(self.scripts_folder, "data")
        self.map_data_sources_folder = os.path.join(self.path, "map_data_sources")
        self.map_name = self.setting("map")

    def setting(self, key):
        if key not in self.settings:
            raise SystemExit("%s: MISSION.%s is missing" % (self.settings_file, key))
        return self.settings[key]

    def data_file(self, name):
        """A data file in the mission's scripts folder (data\\<name>)."""
        return os.path.join(self.data_folder, name)

    def map_data_source(self, name):
        """An input the map tools read for this mission's map (map_data_sources\\<name>)."""
        return os.path.join(self.map_data_sources_folder, name)
