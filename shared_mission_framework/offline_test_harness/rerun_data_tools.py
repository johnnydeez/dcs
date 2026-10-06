"""Offline test harness, test D: re-runs the map data tools for a mission and compares what
they write with a recorded baseline (shared_mission_framework plan.md, *How the transfer is
tested*), so changing or moving the tools can't silently change the data they make.

    python rerun_data_tools.py kola --record-baseline    the baseline, before a change
    python rerun_data_tools.py kola                      after a change: same as the baseline?

The tools never write into the repository here: each run copies, into
output\\<mission>\\data_tools\\<run>\\ and laid out as in the repository, the framework's
map_data_tools\\ and the data files the tools read, and the mission's mission_settings.lua,
map_data_sources\\ and data inputs. It runs the tools there, in order, the mission's tools on
the copied mission folder (their argument). Every file they write and everything they print
(paths shown as <copy>) is compared with baselines\\<mission>\\data_tools\\ line for line.
Each data file is also compared with the one committed in the repository, as information: a
difference there means the committed data is older than its inputs (a .miz or survey
changed since), not that the tool broke.

Some inputs live outside the repository (the .miz files and the zone survey in Saved Games,
the DCS install, the pydcs and Liberation checkouts): if one of those changes, re-record.

Standard library only (Python 3.7+).
"""

import argparse
import os
import shutil
import subprocess
import sys

HARNESS_FOLDER = os.path.dirname(os.path.abspath(__file__))
REPOSITORY_FOLDER = os.path.dirname(os.path.dirname(HARNESS_FOLDER))
SAVED_GAMES = os.path.join(os.path.expanduser("~"), "Saved Games", "DCS")

# Paths relative to the repository (and to each run's copy of it).
TOOLS_FOLDER = os.path.join("shared_mission_framework", "map_data_tools")
FRAMEWORK_DATA = os.path.join("shared_mission_framework", "mission_scripts", "data")

# Each mission:
#   mission_folder  the mission's folder
#   scripts_folder  its scripts folder inside that (where mission_settings.lua and data\ are)
#   inputs          data files the tools read, copied from the repository first
#   runs            each tool, in order: (script, arguments); "{mission}" is the copied mission folder
#   outputs         the data files the tools write, compared
MISSIONS = {
    "kola": {
        "mission_folder": os.path.join("missions", "kola_f16_random_tasking"),
        "scripts_folder": "kola_f16",
        "inputs": [os.path.join(FRAMEWORK_DATA, "unit_pool.lua"), os.path.join(FRAMEWORK_DATA, "aircraft_pylons.lua"),
                   os.path.join("missions", "kola_f16_random_tasking", "kola_f16", "data", "clusters.lua")],
        "runs": [
            ("unit_pool.py", []),
            ("aircraft_loadouts.py", []),
            ("cloud_presets.py", []),
            ("airfield_frequencies.py", ["{mission}"]),
            ("miz_player_slots.py", ["{mission}", os.path.join(SAVED_GAMES, "Missions", "kola_f16_random_tasking.miz")]),
            ("miz_zones.py", ["{mission}", os.path.join(SAVED_GAMES, "Missions", "khola_ground_zones.miz"),
                              "--terrain", os.path.join(SAVED_GAMES, "kola_zone_terrain.lua")]),
        ],
        "outputs": [os.path.join(FRAMEWORK_DATA, name) for name in
                    ("unit_pool.lua", "aircraft_pylons.lua", "aircraft_loadouts.lua", "cloud_presets.lua")]
                   + [os.path.join("missions", "kola_f16_random_tasking", "kola_f16", "data", name) for name in
                      ("airfield_frequencies.lua", "player_slots.lua", "zones.lua")],
    },
}


def copy_into(folder, relative):
    """Copies a file or folder of the repository to the same place under `folder`."""
    source, target = os.path.join(REPOSITORY_FOLDER, relative), os.path.join(folder, relative)
    if os.path.isdir(source):
        shutil.copytree(source, target, ignore=shutil.ignore_patterns("__pycache__"))
    else:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(source, target)


def run_tools(mission, folder):
    """Copies the tools and their inputs into `folder` (emptied first), runs every tool there.
    Returns a list of problems (empty when every tool ran)."""
    m = MISSIONS[mission]
    if os.path.isdir(folder):
        shutil.rmtree(folder)
    os.makedirs(folder)
    copy_into(folder, TOOLS_FOLDER)
    copy_into(folder, os.path.join(m["mission_folder"], m["scripts_folder"], "mission_settings.lua"))
    copy_into(folder, os.path.join(m["mission_folder"], "map_data_sources"))
    for relative in m["inputs"]:
        copy_into(folder, relative)
    os.makedirs(os.path.join(folder, FRAMEWORK_DATA), exist_ok=True)
    os.makedirs(os.path.join(folder, m["mission_folder"], m["scripts_folder"], "data"), exist_ok=True)
    mission_copy = os.path.join(folder, m["mission_folder"])
    problems = []
    for script, arguments in m["runs"]:
        arguments = [mission_copy if a == "{mission}" else a for a in arguments]
        run = subprocess.run([sys.executable, os.path.join(folder, TOOLS_FOLDER, script)] + arguments,
                             cwd=folder, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
        text = run.stdout.replace(folder, "<copy>")
        with open(os.path.join(folder, "printed_by_" + script + ".txt"), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        if run.returncode != 0:
            problems.append("{} failed (exit {}): {}".format(script, run.returncode, text.strip().splitlines()[-1:]))
    return problems


def read_lines(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read().splitlines()


def compare(a, b):
    """'same', 'missing …' or 'n lines differ'."""
    for path, which in ((a, "first"), (b, "second")):
        if not os.path.isfile(path):
            return "missing in the {}".format(which)
    before, after = read_lines(a), read_lines(b)
    if before == after:
        return "same"
    changed = sum(1 for x, y in zip(before, after) if x != y) + abs(len(before) - len(after))
    return "{} lines differ".format(changed)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mission", choices=sorted(MISSIONS))
    parser.add_argument("--record-baseline", action="store_true", help="record the baseline instead of comparing")
    args = parser.parse_args()
    m = MISSIONS[args.mission]

    baseline = os.path.join(HARNESS_FOLDER, "baselines", args.mission, "data_tools")
    latest = os.path.join(HARNESS_FOLDER, "output", args.mission, "data_tools", "latest")
    if args.record_baseline and os.path.isdir(baseline):
        print("a baseline already exists; remove this folder first if it really should be replaced:\n  " + baseline)
        return 1
    target = baseline if args.record_baseline else latest
    problems = run_tools(args.mission, target)
    for p in problems:
        print("FAILED: " + p)

    failed = len(problems)
    compared = m["outputs"] + ["printed_by_" + script + ".txt" for script, _ in m["runs"]]
    print("{:<70} {:<22} {}".format("file", "against the baseline", "against the committed data"))
    for rel in compared:
        against_baseline = "(recording)" if args.record_baseline else compare(os.path.join(baseline, rel),
                                                                              os.path.join(latest, rel))
        committed = ""
        if rel in m["outputs"]:
            committed = compare(os.path.join(REPOSITORY_FOLDER, rel), os.path.join(target, rel))
        if against_baseline not in ("same", "(recording)"):
            failed += 1
        print("{:<70} {:<22} {}".format(rel, against_baseline, committed))
    print()
    if args.record_baseline:
        print("baseline recorded" if not problems else "a tool failed; baseline not usable")
    else:
        print("every tool's output same as the baseline" if failed == 0 else "{} failed or differ".format(failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
