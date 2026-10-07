"""Offline test harness: replays a mission on a frozen saved world with fixed seeds, and
compares the result with a recorded baseline.

    python replay_and_compare.py kola --record-baseline    the baseline, before a change
    python replay_and_compare.py kola                      after a change: same as the baseline?
    python replay_and_compare.py kola --test plan          one test only

Two tests (shared_mission_framework framework_design.md, *How the transfer is tested*), each seed one
luae.exe run of replay_mission.lua (the mission's real init.lua over stub_dcs.lua and
stub_dcs_world.lua):
    plan      test A: planning only, seeds 1-5
    mission   test B level 1: the whole mission, its clock run 2 hours, everything standing still, seeds 1-3
    flying    test B level 2: the same with the AI flying, radars seeing, a stand-in player, seeds 1-3
into output\\<mission>\\latest\\<test>_seed_<n>\\ or, when recording,
baselines\\<mission>\\<test>_seed_<n>\\. A seed passes when every file it wrote is the
baseline's, line for line. Any difference is either a regression or an intended change, to
be written down.

Standard library only (Python 3.7+).
"""

import argparse
import difflib
import os
import shutil
import subprocess
import sys

HARNESS_FOLDER = os.path.dirname(os.path.abspath(__file__))
REPOSITORY_FOLDER = os.path.dirname(os.path.dirname(HARNESS_FOLDER))
LUAE = r"C:\Program Files\Eagle Dynamics\DCS World\bin\luae.exe"

# Each mission the harness replays:
#   scripts_name    its folder under Saved Games\DCS\Scripts, as its mission editor trigger loads init.lua
#   scripts_folder  where those scripts are in the repository
#   saved_world     a plan the mission wrote in DCS, frozen in baselines\<mission>\ (only its plan.world is read)
#   plan_dump       the file name the mission writes its plan to (CONFIG.PLAN_DUMP_FILE)
# Every mission also loads the shared framework from Scripts\shared_mission_framework\
# (FRAMEWORK_SCRIPTS), passed only once that folder exists in the repository.
FRAMEWORK_SCRIPTS = ("shared_mission_framework", os.path.join(REPOSITORY_FOLDER, "shared_mission_framework", "mission_scripts"))
MISSIONS = {
    "kola": {
        "scripts_name": "kola_f16",
        "scripts_folder": os.path.join(REPOSITORY_FOLDER, "missions", "kola_f16_random_tasking", "kola_f16"),
        "saved_world": os.path.join(HARNESS_FOLDER, "baselines", "kola", "saved_world_from_2026-10-06_0016_run.lua"),
        "plan_dump": "kola_last_plan.lua",
    },
    "caucasus": {
        "scripts_name": "caucasus_f16",
        "scripts_folder": os.path.join(REPOSITORY_FOLDER, "missions", "caucasus_multiplayer_random_tasking", "caucasus_f16"),
        "saved_world": os.path.join(HARNESS_FOLDER, "baselines", "caucasus", "saved_world_from_2026-10-06_2127_run.lua"),
        "plan_dump": "caucasus_last_plan.lua",
    },
}

# Each test: its name, the replay mode, its seeds, and the files compared (plan_dump: the
# mission's CONFIG.PLAN_DUMP_FILE; redirected\*: whatever the mission wrote there, its event
# log and radio calls file).
TESTS = [
    ("plan", "plan", [1, 2, 3, 4, 5],
     ["plan_dump", "loaded_files.txt", "dcs_log.txt", "screen_texts.txt", "commands.txt", "redirected_writes.txt"]),
    ("mission", "mission:7203", [1, 2, 3],
     ["plan_dump", "loaded_files.txt", "dcs_log.txt", "screen_texts.txt", "commands.txt", "redirected_writes.txt",
      "menu_items.txt", "drawings.txt", "orders.txt", "spawned_countries.txt", "redirected\\*"]),
    ("flying", "flying:7203", [1, 2, 3],
     ["plan_dump", "loaded_files.txt", "dcs_log.txt", "screen_texts.txt", "commands.txt", "redirected_writes.txt",
      "menu_items.txt", "drawings.txt", "orders.txt", "spawned_countries.txt", "redirected\\*"]),
]


def replay(mission, mode, seed, folder):
    """One replay into `folder` (emptied first). Returns (ok, the harness's result line)."""
    if os.path.isdir(folder):
        shutil.rmtree(folder)
    os.makedirs(folder)
    m = MISSIONS[mission]
    command = [LUAE, "replay_mission.lua", m["scripts_name"], m["scripts_folder"] + "\\",
               m["saved_world"], str(seed), mode, folder + "\\"]
    framework_name, framework_folder = FRAMEWORK_SCRIPTS
    if os.path.isdir(framework_folder):
        command.append("{}={}\\".format(framework_name, framework_folder))
    run = subprocess.run(command, cwd=HARNESS_FOLDER, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         universal_newlines=True)
    lines = run.stdout.strip().splitlines()
    return run.returncode == 0, "\n".join(lines) if lines else "(no output)"


def compared_files(mission, files, baseline_folder, latest_folder):
    """The file names to compare, relative to a run's folder."""
    names = []
    for name in files:
        if name == "plan_dump":
            names.append(MISSIONS[mission]["plan_dump"])
        elif name == "redirected\\*":
            found = set()
            for folder in (baseline_folder, latest_folder):
                sub = os.path.join(folder, "redirected")
                if os.path.isdir(sub):
                    found.update(os.listdir(sub))
            names.extend(os.path.join("redirected", f) for f in sorted(found))
        else:
            names.append(name)
    return names


def compare(mission, files, baseline_folder, latest_folder):
    """Differences between two runs of one seed, as text lines; empty when identical."""
    differences = []
    for file_name in compared_files(mission, files, baseline_folder, latest_folder):
        missing = [which for which, folder in (("baseline", baseline_folder), ("latest", latest_folder))
                   if not os.path.isfile(os.path.join(folder, file_name))]
        if missing:
            differences.append("  {}: missing in the {} run".format(file_name, " and ".join(missing)))
            continue
        with open(os.path.join(baseline_folder, file_name), encoding="utf-8", errors="replace") as f:
            before = f.read().splitlines()
        with open(os.path.join(latest_folder, file_name), encoding="utf-8", errors="replace") as f:
            after = f.read().splitlines()
        if before == after:
            continue
        diff = list(difflib.unified_diff(before, after, "baseline", "latest", lineterm="", n=1))
        changed = sum(1 for line in diff if line[:1] in "+-" and line[:3] not in ("+++", "---"))
        differences.append("  {}: {} lines differ; first ones:".format(file_name, changed))
        differences.extend("    " + line for line in diff[2:22])
    return differences


def main():
    # the logs hold non-ASCII text (→, °, —); Windows' console encoding can't print all of it
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mission", choices=sorted(MISSIONS))
    parser.add_argument("--record-baseline", action="store_true", help="record the baseline instead of comparing")
    parser.add_argument("--test", choices=[t[0] for t in TESTS], help="only this test (default: all)")
    args = parser.parse_args()
    mission = args.mission
    tests = [t for t in TESTS if args.test in (None, t[0])]

    if not os.path.isfile(MISSIONS[mission]["saved_world"]):
        print("missing the frozen saved world: " + MISSIONS[mission]["saved_world"])
        return 1
    # a baseline is never overwritten: an old one is removed by hand, by its exact path
    if args.record_baseline:
        existing = [os.path.join(HARNESS_FOLDER, "baselines", mission, "{}_seed_{}".format(name, seed))
                    for name, _, seeds, _ in tests for seed in seeds]
        existing = [folder for folder in existing if os.path.isdir(folder)]
        if existing:
            print("a baseline already exists; remove these folders first if it really should be replaced:")
            print("\n".join("  " + folder for folder in existing))
            return 1

    failed, runs = 0, 0
    for name, mode, seeds, files in tests:
        print("== test {} ({})".format(name, mode))
        for seed in seeds:
            runs += 1
            run_name = "{}_seed_{}".format(name, seed)
            baseline = os.path.join(HARNESS_FOLDER, "baselines", mission, run_name)
            latest = os.path.join(HARNESS_FOLDER, "output", mission, "latest", run_name)
            target = baseline if args.record_baseline else latest
            ok, result = replay(mission, mode, seed, target)
            print("seed {}: {}".format(seed, result))
            if not ok:
                failed += 1
                continue
            if args.record_baseline:
                continue
            if not os.path.isdir(baseline):
                print("  no baseline for this seed: record one with --record-baseline")
                failed += 1
                continue
            differences = compare(mission, files, baseline, latest)
            if differences:
                failed += 1
                print("  DIFFERENT from the baseline:")
                print("\n".join(differences))
            else:
                print("  same as the baseline")

    print()
    if args.record_baseline:
        print("baseline recorded" if failed == 0 else "{} of {} runs failed; baseline not usable".format(failed, runs))
    else:
        print("all {} runs same as the baseline".format(runs) if failed == 0
              else "{} of {} runs failed or differ".format(failed, runs))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
