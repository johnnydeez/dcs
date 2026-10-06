"""Parse the player slots out of a mission's flyable .miz into its data/player_slots.lua.

    python map_data_tools/miz_player_slots.py <mission folder> ["<mission .miz>"] [--out <file>]

The .miz defaults to Saved Games\\DCS\\Missions\\<MISSION.flyable_mission_file>; the airbases
come from the mission's map_data_sources\\<MISSION.airbase_reference_file>.

A player slot is a dynamic spawn template group (dynSpawnTemplate) or any Client / Player
unit placed on a parking spot. DCS always spawns the player on that exact spot, so the
planner keeps AI aircraft (parked static aircraft and AI flights) off it.

Per slot: the airbase (nearest to the unit, from the airbase reference file), the DCS terminal
index (the .miz unit's `parking`, same as Airbase:getParking() Term_Index), the ME spot
name (`parking_id`), the group name, the aircraft type and the position. In-sim,
gather.lua checks each slot against the airbase's real parking spots and warns on a
mismatch.
"""

import argparse
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import dcslua      # noqa: E402
from mission_folder import MISSION_FOLDER_HELP, SAVED_GAMES_DCS, MissionFolder   # noqa: E402

PLAYER_SKILLS = ("Client", "Player")
MAX_BASE_DISTANCE_M = 5000   # a slot farther than this from every airbase isn't on one

HEADER = """\
-- Player slots parsed from {miz} by map_data_tools/miz_player_slots.py — do not hand-edit;
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
"""


def load_airbases(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)["airbases"]


def nearest_base(bases, x, z):
    best, best_d = None, None
    for b in bases:
        d = math.hypot(b["x"] - x, b["y"] - z)
        if best_d is None or d < best_d:
            best, best_d = b["name"], d
    return best, best_d


def read_slots(miz, airbases_path):
    mission = dcslua.load_miz(miz)
    bases = load_airbases(airbases_path)
    slots, problems = [], []
    for coalition in mission["coalition"].values():
        for country in dcslua.as_list(coalition.get("country", {})):
            for category in ("plane", "helicopter"):
                for group in dcslua.as_list(country.get(category, {}).get("group", {})):
                    template = bool(group.get("dynSpawnTemplate"))
                    for unit in dcslua.as_list(group["units"]):
                        if not template and unit.get("skill") not in PLAYER_SKILLS:
                            continue
                        where = "%s / %s" % (group["name"], unit["name"])
                        if unit.get("parking") is None:
                            problems.append("%s is not on a parking spot" % where)
                            continue
                        x, z = unit["x"], unit["y"]
                        base, d = nearest_base(bases, x, z)
                        if d > MAX_BASE_DISTANCE_M:
                            problems.append("%s is %.1f km from the nearest airbase (%s)"
                                            % (where, d / 1000, base))
                            continue
                        slots.append({
                            "base": base,
                            "terminal_index": int(unit["parking"]),
                            "spot": str(unit.get("parking_id", "")),
                            "group": group["name"],
                            "type": unit["type"],
                            "x": round(x), "z": round(z),
                        })
    seen = {}
    for s in slots:
        key = (s["base"], s["terminal_index"])
        if key in seen:
            problems.append("%s and %s share %s spot %s"
                            % (seen[key], s["group"], s["base"], s["spot"]))
        seen[key] = s["group"]
    return slots, problems


def write_lua(slots, miz, out):
    by_base = {}
    for s in slots:
        by_base.setdefault(s["base"], []).append(s)
    lines = [HEADER.format(miz=os.path.basename(miz)), "PLAYER_SLOTS = {"]
    for base in sorted(by_base):
        lines.append('    [%s] = {' % dcslua._lua_str(base))
        for s in sorted(by_base[base], key=lambda s: s["terminal_index"]):
            lines.append('        { terminal_index = %d, spot = %s, group = %s, type = %s, x = %d, z = %d },'
                         % (s["terminal_index"], dcslua._lua_str(s["spot"]), dcslua._lua_str(s["group"]),
                            dcslua._lua_str(s["type"]), s["x"], s["z"]))
        lines.append('    },')
    lines.append("}")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    return by_base


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("mission_folder", help=MISSION_FOLDER_HELP)
    ap.add_argument("miz", nargs="?", help="default: Saved Games\\DCS\\Missions\\<MISSION.flyable_mission_file>")
    ap.add_argument("--out", help="default: the mission's data/player_slots.lua")
    args = ap.parse_args()
    mission = MissionFolder(args.mission_folder)
    miz = args.miz or os.path.join(SAVED_GAMES_DCS, "Missions", mission.setting("flyable_mission_file"))
    out = args.out or mission.data_file("player_slots.lua")

    slots, problems = read_slots(miz, mission.map_data_source(mission.setting("airbase_reference_file")))
    for p in problems:
        print("WARNING: " + p)
    by_base = write_lua(slots, miz, out)
    print("%d player slots at %d airbases -> %s" % (len(slots), len(by_base), out))
    for base in sorted(by_base):
        print("  %-24s %s" % (base, ", ".join("%s (%d)" % (s["spot"], s["terminal_index"])
                                              for s in by_base[base])))


if __name__ == "__main__":
    main()
