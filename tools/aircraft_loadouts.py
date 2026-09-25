"""Build kola_f16/data/aircraft_loadouts.lua: one loadout per aircraft type and mission type.

    python tools/aircraft_loadouts.py                   write the data file
    python tools/aircraft_loadouts.py --list Su-34      show every loadout a type has, with weapons

Hand-writing AI loadouts goes wrong quietly (pylon numbers, rack CLSIDs, fuel units all
differ per jet), so the loadouts are copied out of files that already work:

  dcs         ED's own named loadouts: DCS World\\MissionEditor\\data\\scripts\\UnitPayloads\\*.lua
              (AI aircraft) and DCS World\\CoreMods\\aircraft\\*\\UnitPayloads\\*.lua (modules)
  liberation  DCS Liberation's loadouts chosen for AI use, one per mission type
              ("Liberation Strike", "STRIKE", ...): resources\\customized_payloads\\*.lua in a
              local checkout (C:\\Users\\johnk\\Git\\dcs_liberation). Reference only, like pydcs.
  hand        loadouts proven in our own missions (the Syria CAS jets), in
              aircraft_loadouts_by_hand.json next to this script

Which loadout each type uses per mission type is chosen in aircraft_loadout_choices.json:
    { "<type>": { "<mission type>": "<source>:<loadout name>" } }
Every chosen pylon's CLSID is checked against kola_f16/data/aircraft_pylons.lua (from
pydcs); fuel, chaff and flare come from kola_f16/data/unit_pool.lua. The gun is kept at
100 % here — the planner decides per mission whether the flight keeps it.
Stdlib only, Python 3.7+.
"""

import argparse
import glob
import json
import os
import re
import sys

import dcslua

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DATA = os.path.join(REPO, "kola_f16", "data")
CHOICES = os.path.join(HERE, "aircraft_loadout_choices.json")
BY_HAND = os.path.join(HERE, "aircraft_loadouts_by_hand.json")
DEFAULT_DCS = r"C:\Program Files\Eagle Dynamics\DCS World"
DEFAULT_LIBERATION = os.path.join(os.path.dirname(REPO), "dcs_liberation")
OUT = os.path.join(DATA, "aircraft_loadouts.lua")
SKIPPED = []   # payload files this reader can't parse (none of them on our rosters so far)

MISSION_TYPES = ["strike", "airfield_strike", "suppression_of_air_defenses",
                 "destruction_of_air_defenses", "interdiction", "close_air_support"]


# ── Reading ─────────────────────────────────────────────────────

def read_payload_file(path):
    """A UnitPayloads file: `local unitPayloads = { ... } return unitPayloads`."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    text = re.sub(r"^\s*local\s+", "", text, count=1)
    text = re.sub(r"\breturn\s+\w+\s*$", "", text.strip())
    table = dcslua.loads(text)
    loadouts = {}
    for p in dcslua.as_list(table.get("payloads", {})):
        pylons = []
        for py in dcslua.as_list(p.get("pylons", {})):
            pylons.append({"num": int(py["num"]), "CLSID": py["CLSID"]})
        pylons.sort(key=lambda py: py["num"])
        loadouts[p["name"]] = pylons
    return table.get("unitType") or table.get("name"), loadouts


def read_sources(dcs_dir, liberation_dir):
    """{ source: { aircraft type: { loadout name: pylons } } }"""
    sources = {"dcs": {}, "liberation": {}, "hand": {}}
    dcs_files = glob.glob(os.path.join(dcs_dir, "MissionEditor", "data", "scripts", "UnitPayloads", "*.lua"))
    dcs_files += glob.glob(os.path.join(dcs_dir, "CoreMods", "aircraft", "*", "UnitPayloads", "*.lua"))
    for path in dcs_files:
        try:
            unit, loadouts = read_payload_file(path)
        except Exception as e:  # a file we can't parse is reported, not fatal
            SKIPPED.append("%s: %s" % (path, e))
            continue
        sources["dcs"].setdefault(unit, {}).update(loadouts)
    for path in glob.glob(os.path.join(liberation_dir, "resources", "customized_payloads", "*.lua")):
        try:
            unit, loadouts = read_payload_file(path)
        except Exception as e:
            SKIPPED.append("%s: %s" % (path, e))
            continue
        sources["liberation"].setdefault(unit, {}).update(loadouts)
    if os.path.exists(BY_HAND):
        with open(BY_HAND, encoding="utf-8") as f:
            for unit, loadouts in json.load(f).items():
                if unit.startswith("_"):
                    continue
                for name, lo in loadouts.items():
                    sources["hand"].setdefault(unit, {})[name] = sorted(lo["pylons"], key=lambda py: py["num"])
    return sources


def read_pylons():
    """{ type: { pylon: { clsid: weapon name } } } from aircraft_pylons.lua."""
    out, unit, pylon = {}, None, None
    with open(os.path.join(DATA, "aircraft_pylons.lua"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r'^    \["(.+)"\] = \{', line)
            if m:
                unit = m.group(1)
                out[unit] = {}
                continue
            m = re.match(r"^        \[(\d+)\] = \{", line)
            if m and unit:
                pylon = int(m.group(1))
                out[unit][pylon] = {}
                continue
            m = re.match(r'^            "(.+)",\s*--\s*(.*)$', line)
            if m and unit and pylon is not None:
                out[unit][pylon][m.group(1)] = m.group(2).strip()
    return out


def read_pool():
    """{ type: { fuel_max, chaff, flare } } for planes and helicopters in unit_pool.lua."""
    out = {}
    with open(os.path.join(DATA, "unit_pool.lua"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r'^        \["(.+?)"\] = \{ type = .*?fuel_max = ([\d.]+).*?chaff = (\d+), flare = (\d+)', line)
            if m:
                out[m.group(1)] = {"fuel": float(m.group(2)), "chaff": int(m.group(3)), "flare": int(m.group(4))}
    return out


def weapon_names(pylons_db, unit, pylons):
    names = []
    for py in pylons:
        names.append(pylons_db.get(unit, {}).get(py["num"], {}).get(py["CLSID"], "? " + py["CLSID"]))
    return names


# ── Writing ─────────────────────────────────────────────────────

def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def fmt_number(v):
    return str(int(v)) if float(v).is_integer() else repr(v)


def write(path, chosen):
    lines = [
        "-- One loadout per aircraft type and mission type, for AI flights. Generated by",
        "-- tools/aircraft_loadouts.py from ED's UnitPayloads, DCS Liberation's AI loadouts and",
        "-- our own proven hand loadouts; which one is chosen lives in",
        "-- tools/aircraft_loadout_choices.json. Do not hand-edit: change the choice and re-run.",
        "-- Plain data, no logic. Every CLSID was checked against data/aircraft_pylons.lua.",
        "--   AIRCRAFT_LOADOUT[type][mission type] = { source, name, fuel, chaff, flare, gun,",
        "--       pylons = { { num, CLSID } } }   (trailing comment = weapon name)",
        "",
        "AIRCRAFT_LOADOUT = {",
    ]
    for unit in sorted(chosen):
        lines.append("    [%s] = {" % lua_str(unit))
        for mission in [m for m in MISSION_TYPES if m in chosen[unit]]:
            lo = chosen[unit][mission]
            lines.append("        %s = {" % mission)
            lines.append("            source = %s, name = %s," % (lua_str(lo["source"]), lua_str(lo["name"])))
            lines.append("            fuel = %s, chaff = %d, flare = %d, gun = 100," % (
                fmt_number(lo["fuel"]), lo["chaff"], lo["flare"]))
            lines.append("            pylons = {")
            for py, name in zip(lo["pylons"], lo["weapons"]):
                lines.append("                { num = %d, CLSID = %s },  -- %s" % (py["num"], lua_str(py["CLSID"]), name))
            lines.append("            },")
            lines.append("        },")
        lines.append("    },")
    lines.append("}")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


# ── Main ────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dcs", default=DEFAULT_DCS)
    ap.add_argument("--liberation", default=DEFAULT_LIBERATION)
    ap.add_argument("--list", metavar="TYPE", help="show every loadout this aircraft type has, with weapons")
    args = ap.parse_args()

    sources = read_sources(args.dcs, args.liberation)
    pylons_db = read_pylons()

    if args.list:
        for src in ("hand", "liberation", "dcs"):
            for name, pylons in sorted(sources[src].get(args.list, {}).items()):
                print("%-10s %-40s %s" % (src, name, ", ".join(weapon_names(pylons_db, args.list, pylons))))
        return 0

    with open(CHOICES, encoding="utf-8") as f:
        choices = {k: v for k, v in json.load(f).items() if not k.startswith("_")}
    pool = read_pool()
    chosen, problems = {}, []
    for unit, missions in sorted(choices.items()):
        if unit not in pool:
            problems.append("%s: not an aircraft in unit_pool.lua" % unit)
            continue
        for mission, pick in missions.items():
            if mission not in MISSION_TYPES:
                problems.append("%s: '%s' is not a mission type" % (unit, mission))
                continue
            src, _, name = pick.partition(":")
            pylons = sources.get(src, {}).get(unit, {}).get(name)
            if pylons is None:
                problems.append("%s.%s: no %s loadout named '%s' (try --list %s)" % (unit, mission, src, name, unit))
                continue
            known = pylons_db.get(unit, {})
            for py in pylons:
                if py["CLSID"] not in known.get(py["num"], {}):
                    problems.append("%s.%s: pylon %d can't carry %s" % (unit, mission, py["num"], py["CLSID"]))
            chosen.setdefault(unit, {})[mission] = dict(
                source=src, name=name, pylons=pylons, weapons=weapon_names(pylons_db, unit, pylons), **pool[unit])
    for p in problems:
        print("PROBLEM: " + p)
    if problems:
        print("not written")
        return 1
    for s in SKIPPED:
        print("  skipped (can't parse) " + s)
    write(OUT, chosen)
    n = sum(len(m) for m in chosen.values())
    print("wrote %s: %d aircraft types, %d loadouts" % (OUT, len(chosen), n))
    for unit in sorted(chosen):
        for mission, lo in sorted(chosen[unit].items()):
            print("  %-14s %-28s %-10s %-28s %s" % (unit, mission, lo["source"], lo["name"], ", ".join(lo["weapons"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
