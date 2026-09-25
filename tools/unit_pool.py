"""Build kola_f16/data/unit_pool.lua and kola_f16/data/aircraft_pylons.lua from pydcs.

    python tools/unit_pool.py [--pydcs C:\\Users\\johnk\\Git\\pydcs] [--out-dir kola_f16/data]

pydcs (github.com/pydcs/dcs) is reference material only: its dcs/vehicles.py, planes.py,
helicopters.py, ships.py, statics.py and weapons_data.py are generated straight from
DCS's own unit database, so the `id` strings are exactly what coalition.addGroup and
coalition.addStaticObject expect. This script reads those source files as text (no
import, no dependency) and writes two plain-data Lua files:

  unit_pool.lua       every AI-operable unit in base DCS (incl. the CoreMods packs —
                      Currenthill, ColdWar, Massun92 …), segmented ground / plane /
                      helicopter / ship, keyed by exact type string. Side-, country-
                      and era-agnostic: the spawner always uses CJTF_RED / CJTF_BLUE.
                      `role` is a planner-facing tag assigned here by name heuristics,
                      overridden by unit_role_overrides.json next to this script.
                      Plus `static`: every structure / cargo static object type
                      (statics.py: Fortification, Warehouse, Cargo) with its category
                      and shape_name, as coalition.addStaticObject needs them.
  aircraft_pylons.lua per-aircraft pylon -> allowed weapon CLSIDs. Kept out of the pool
                      because it is large; used to validate hand-authored loadouts.

Anything the heuristics can't classify is reported at the end — add it to the
overrides file and re-run.
"""

import argparse
import ast
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

DEFAULT_PYDCS = os.path.join(os.path.dirname(REPO), "pydcs")
DEFAULT_OUT = os.path.join(REPO, "kola_f16", "data")
OVERRIDES = os.path.join(HERE, "unit_role_overrides.json")

CLASS_RE = re.compile(r"^(\s*)class (\w+)(?:\((\w+(?:\.\w+)?)\))?:\s*$")
ASSIGN_RE = re.compile(r"^(\s*)(\w+)(?::\s*[\w\[\], ]+)?\s*=\s*(.+?)\s*(?:#.*)?$")
PYLON_ITEM_RE = re.compile(r"^\s*\w+\s*=\s*\((\d+),\s*Weapons\.(\w+)\)\s*$")
TASK_RE = re.compile(r"task\.(\w+)")


# ── Source parsing ──────────────────────────────────────────────

def literal(text):
    try:
        return ast.literal_eval(text)
    except (ValueError, SyntaxError):
        return text


def parse_classes(path):
    """Yields (outer_class_name, class_name, fields{}, pylons{num: [weapon_attr]}).

    Handles the three layouts pydcs uses: vehicles.py (category class -> unit class),
    planes/helicopters.py (unit class with nested Pylon classes), ships.py (flat)."""
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()

    units = []
    outer = None
    cur = None            # (indent, name, fields, pylons)
    pylon_num = None
    skip_indent = None    # inside a nested class that is not a Pylon (e.g. Properties)
    for line in lines:
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        if skip_indent is not None:
            if indent > skip_indent:
                continue
            skip_indent = None
        m = CLASS_RE.match(line)
        if m:
            name, base = m.group(2), m.group(3)
            if cur is not None and indent > cur[0]:
                if name.startswith("Pylon"):
                    pylon_num = int(name[5:])
                    cur[3].setdefault(pylon_num, [])
                else:
                    pylon_num = None
                    skip_indent = indent
                continue
            pylon_num = None
            if cur is not None:
                units.append((outer, cur[1], cur[2], cur[3]))
                cur = None
            if base is None and indent == 0:
                outer = name           # vehicles.py category holder
                continue
            cur = (indent, name, {}, {})
            continue

        if cur is None:
            continue
        if pylon_num is not None:
            pm = PYLON_ITEM_RE.match(line)
            if pm:
                cur[3][pylon_num].append(pm.group(2))
                continue
            if len(line) - len(line.lstrip()) <= cur[0] + 4:
                pylon_num = None       # left the Pylon class body
        am = ASSIGN_RE.match(line)
        if am and len(am.group(1)) == cur[0] + 4:
            key, val = am.group(2), am.group(3)
            if key == "tasks":
                cur[2][key] = TASK_RE.findall(val)
            elif key == "task_default":
                cur[2][key] = val.replace("task.", "")
            elif key == "pylons":
                cur[2][key] = sorted(int(x) for x in re.findall(r"\d+", val))
            else:
                cur[2][key] = literal(val)
    if cur is not None:
        units.append((outer, cur[1], cur[2], cur[3]))
    return [u for u in units if "id" in u[2]]


def parse_weapons(path):
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^\s*(\w+)\s*=\s*(\{.*\})\s*$", line)
            if m:
                d = literal(m.group(2))
                if isinstance(d, dict) and "clsid" in d:
                    out[m.group(1)] = d
    return out


# ── Role heuristics ─────────────────────────────────────────────

SHORAD_IDS = {
    "2S6 Tunguska", "Osa 9A33 ln", "Tor 9A331", "Strela-10M3", "Strela-1 9P31",
    "M48 Chaparral", "M6 Linebacker", "M1097 Avenger", "Roland ADS", "CHAP_PantsirS1",
    "CHAP_TorM2", "HQ-7_LN_SP", "HQ-7_LN_P",
}

SAM_SYSTEM_RE = re.compile(
    r"\b(SA-\d+(?:/\d+)*|Patriot|Hawk|NASAMS|Rapier|Roland|IRIS-T SLM|HQ-7B?|S-300|S-200|S-75|S-125)\b")


def has(s, *words):
    s = " " + s + " "
    return any((" " + w + " ") in s for w in words)


def sam_system(name):
    m = SAM_SYSTEM_RE.search(name)
    return m.group(1).replace("HQ-7B", "HQ-7") if m else None


def role_ground(cat, uid, name):
    n = name
    lid = uid.lower()
    if cat == "Infantry":
        return "jtac" if "JTAC" in n else "infantry"
    if cat == "AirDefence":
        if n.startswith("MANPADS"):
            return "manpads_c2" if "C2" in n else "manpads"
        if n.startswith("EWR") or n.startswith("MCC-SR") or "EWR" in uid or n.endswith("EWR"):
            return "ewr"
        if uid in SHORAD_IDS or "SHORAD TELAR" in n:
            return "shorad"
        if "Rangefinder" in n or "Kdo" in n:
            return "aaa_director"
        if n.startswith("SPAAA") or ("AAA" in n and (" on " in n or n.endswith("Truck"))) or n.startswith("LPWS"):
            return "aaa_sp"
        if n.startswith("AAA"):
            return "aaa"
        if n.startswith("SAM") or n.startswith("HQ-7"):
            if has(n, "LN", "Launcher", "TEL", "TELAR") or lid.endswith(" ln") or "launcher" in lid or "_LN" in uid:
                return "sam_ln"
            if has(n, "SR", "STR", "CWAR") or lid.endswith(" sr") or "_SR" in uid or "_STR" in uid or "Tall king" in n:
                return "sam_sr"
            if has(n, "TR", "Tracker", "RF") or lid.endswith(" tr") or "_tr" in lid or "Blindfire" in n:
                return "sam_tr"
            if has(n, "CP", "C2", "ICC", "PCP", "CC", "ECS") or "(PCP)" in n or "_CP" in uid or lid.endswith(" cp"):
                return "sam_cp"
            if has(n, "EPP-III", "CR") or "AMG" in n:
                return "sam_support"
            return None
        if "Power Station" in n or "Gen" in n.split() or "Maschinensatz" in n:
            return "sam_support"
        if n.startswith("SL "):
            return "searchlight"
        return None
    if cat == "Armor":
        first = n.split()[0]
        if "MRAP" in n:
            return "mrap"
        table = {"MBT": "mbt", "IFV": "ifv", "APC": "apc", "Scout": "recon", "ATGM": "atgm",
                 "LT": "light_tank", "Tk": "tank", "MT": "tank", "SPG": "spg", "MRAP": "mrap",
                 "Tractor": "tractor", "Car": "recon"}
        return table.get(first)
    if cat == "Artillery":
        if n.startswith("Mortar"):
            return "mortar"
        if n.startswith(("SPH", "SPM")):
            return "arty_sp"
        if n.startswith(("MLRS", "MRLS", "Grad")):
            return "mlrs"
        if n.startswith("FH") or "Artillery Gun" in n:
            return "arty_towed"
        return None
    if cat == "Unarmed":
        if n.startswith("Refueler"):
            return "fuel"
        if "(C2)" in n or n.startswith(("MCC", "GCI")) or " MCC" in n or "Mobile ATC" in n or "Command" in n:
            return "c2"
        if n.startswith("Firefighter"):
            return "fire"
        if n.startswith("GPU"):
            return "gpu"
        if n.startswith("M92") or "Lift Truck" in n:
            return "ground_crew"
        if "beacon" in lid or "RSBN" in n or "PRMG" in n:
            return "beacon"
        if "jammer" in n.lower():
            return "jammer"
        if n.startswith("Ammo"):
            return "ammo"
        if n.startswith("LUV") or "Jeep" in n:
            return "light_vehicle"
        if n.startswith(("Bus", "ZIU", "Car", "Trolley")) or "civil" in lid:
            return "civilian"
        if n.startswith(("Truck", "Tractor", "Trailer")) or "Tractor" in n or "Trailer" in n:
            return "truck"
        if n.startswith("APC"):
            return "apc"
        return None
    if cat == "Fortification":
        return "beacon" if "Beacon" in n else "fortification"
    if cat == "MissilesSS":
        if n.startswith(("SRBM", "SSM")):
            return "ssm"
        if n.startswith("AShM"):
            return "ashm"
        if n.startswith("Payload") or "Launch Ramp" in n:
            return "misc"
        return None
    if cat == "Locomotive":
        return "locomotive"
    if cat == "Carriage":
        return "railcar"
    return None


def role_ship(uid, name):
    n = name
    if re.match(r"^(CVN|CV\b|CV-|Essex|HMS Invincible|ARA Veinticinco)", n) or "Carrier" in n:
        return "carrier"
    if n.startswith(("LHA", "LS ", "LST")) or "Amphibious" in n:
        return "amphibious"
    if n.startswith(("CG", "Cruiser", "Battlecruiser")):
        return "cruiser"
    if n.startswith("DDG") or "Destroyer" in n:
        return "destroyer"
    if n.startswith(("FFG", "Frigate")) or "Frigate" in n or uid.startswith("leander"):
        return "frigate"
    if n.startswith(("Corvette", "Patrol", "FAC", "Castle")) or "Missile Boat" in n:
        return "corvette"
    if n.startswith(("SSK", "U-boat", "ARA Santa Fe")) or "Submarine" in n:
        return "submarine"
    if n.startswith(("Tanker", "Bulker", "Cargo", "Supply", "SS ", "Harbor")):
        return "auxiliary"
    if n.startswith("Boat"):
        return "boat"
    return None


FIGHTER_TASKS = {"CAP", "Intercept", "FighterSweep", "Escort"}
STRIKE_TASKS = {"CAS", "GroundAttack", "PinpointStrike", "RunwayAttack", "SEAD", "AntishipStrike"}


def role_air(tasks, default, is_heli):
    """Role from the ME's default task first (what ED thinks the airframe is for), the
    task list second. A buddy-refuelling A-6E or a C-130J is not a tanker."""
    t = set(tasks)
    d = default or "Nothing"
    if d == "AWACS":
        return "awacs"
    if d == "Refueling":
        return "tanker"
    if d == "Transport":
        return "transport"
    if d in ("Reconnaissance", "AFAC"):
        return "recon"
    if is_heli:
        if d in STRIKE_TASKS:
            return "attack"
    elif d in FIGHTER_TASKS:
        return "multirole" if t & {"PinpointStrike", "SEAD"} else "fighter"
    elif d in STRIKE_TASKS:
        return "multirole" if t & {"CAP", "Intercept"} else "strike"
    # No usable default ("Nothing"): fall back on the task list.
    if is_heli:
        if t & STRIKE_TASKS:
            return "attack"
        return "transport" if "Transport" in t else "utility"
    if t & FIGHTER_TASKS and t & STRIKE_TASKS:
        return "multirole"
    if t & FIGHTER_TASKS:
        return "fighter"
    if t & STRIKE_TASKS:
        return "strike"
    for task, role in (("Transport", "transport"), ("AWACS", "awacs"), ("Refueling", "tanker"),
                       ("Reconnaissance", "recon")):
        if task in t:
            return role
    return None


# ── Lua output ──────────────────────────────────────────────────

def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return ("%d" % v) if float(v).is_integer() else ("%.3f" % v).rstrip("0")
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua_val(x) for x in v) + " }"
    raise TypeError(v)


def lua_entry(fields):
    parts = []
    for k, v in fields:
        if v is None:
            continue
        parts.append("%s = %s" % (k, lua_val(v)))
    return "{ " + ", ".join(parts) + " }"


# statics.py holder classes whose types are placeable structures / cargo. GroundObject
# (Building, Bridge, Transport, Train) is scenery, not something a mission places.
STATIC_HOLDERS = {"Fortification", "Warehouse", "Cargo"}
STATIC_DEFAULT_CATEGORY = "Fortifications"   # unittype.StaticType's default


def static_entries(path):
    out = []
    for holder, _cls, f, _p in parse_classes(path):
        if holder not in STATIC_HOLDERS:
            continue
        uid = f["id"]
        out.append((uid, [
            ("type", uid), ("name", f.get("name", "")),
            ("category", f.get("category") or STATIC_DEFAULT_CATEGORY),
            ("shape_name", f.get("shape_name")), ("can_cargo", f.get("can_cargo")),
        ]))
    return sorted(out, key=lambda e: (dict(e[1])["category"], e[0].lower()))


def write_pool(path, ground, planes, helis, ships, statics, src):
    L = [
        "-- Every AI-operable DCS unit type, extracted from pydcs (%s) by tools/unit_pool.py —" % src,
        "-- do not hand-edit; fix tools/unit_role_overrides.json and re-run. Plain data, no logic.",
        "--",
        "-- Side-, country- and era-agnostic: the spawner always spawns as CJTF_RED / CJTF_BLUE,",
        "-- so which side may use a type is decided elsewhere (data/force_pools.lua). Keyed by the",
        "-- exact `type` string coalition.addGroup expects — an unknown string is silently replaced",
        "-- by a Leopard-2 in DCS, so every string a pool references must exist here.",
        "--",
        "--   type            the DCS type string (also the key)",
        "--   name            ED's display name (ground/ship only; pydcs has none for aircraft)",
        "--   cat             pydcs category: Infantry / AirDefence / Armor / Artillery / Unarmed / …",
        "--   role            planner tag: infantry manpads shorad sam_sr sam_tr sam_ln sam_cp ewr aaa aaa_sp",
        "--                   mbt ifv apc recon atgm light_tank tank spg mrap arty_sp arty_towed mortar mlrs",
        "--                   truck fuel c2 light_vehicle civilian fire gpu ground_crew beacon jammer ammo",
        "--                   fortification ssm ashm locomotive railcar misc  |  ships: carrier cruiser",
        "--                   destroyer frigate corvette submarine amphibious auxiliary boat  |  air:",
        "--                   fighter multirole strike awacs tanker transport recon attack utility",
        "--   system          SAM family a part belongs to (SA-10, Patriot, Hawk …) for site recipes",
        "--   detection_m / threat_m / air_weapon_m   ED's sensor range and longest weapon reach, metres",
        "--   aircraft:       tasks (DCS task names the AI can fly), task_default, fuel_max (kg),",
        "--                   max_speed (km/h), chaff, flare, pylons (count), flyable, large_parking, tacan",
        "--   static:         structure / cargo static objects for coalition.addStaticObject: type, name,",
        "--                   category (Fortifications / Warehouses / Cargos), shape_name, can_cargo.",
        "--                   Aircraft and vehicles placed as static objects use the plane / helicopter /",
        "--                   ground entries instead.",
        "",
        "UNIT_POOL = {",
    ]

    def section(title, entries):
        L.append("")
        L.append("    -- ── %s (%d) ──" % (title, len(entries)))
        L.append("    %s = {" % title)
        for key, fields in entries:
            L.append("        [%s] = %s," % (lua_str(key), lua_entry(fields)))
        L.append("    },")

    section("ground", ground)
    section("plane", planes)
    section("helicopter", helis)
    section("ship", ships)
    section("static", statics)
    L.append("")
    L.append("    -- Stub: weapon CLSIDs come in a later pass.")
    L.append("    weapons = {},")
    L.append("}")
    L.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L))


def write_pylons(path, aircraft, weapons, src):
    L = [
        "-- Per-aircraft pylon -> allowed weapon CLSIDs, extracted from pydcs (%s) by" % src,
        "-- tools/unit_pool.py — do not hand-edit. Plain data, no logic. Kept apart from the unit",
        "-- pool because of its size; used to validate hand-authored loadouts (data/loadouts.lua)",
        "-- and for the brief's recommended-load text. Not read by the spawner.",
        "--   AIRCRAFT_PYLONS[type][pylon_number] = { clsid, ... }   (trailing comment = weapon name)",
        "",
        "AIRCRAFT_PYLONS = {",
    ]
    missing = set()
    for uid, pylons in aircraft:
        if not pylons:
            continue
        L.append("    [%s] = {" % lua_str(uid))
        for num in sorted(pylons):
            L.append("        [%d] = {" % num)
            for attr in pylons[num]:
                w = weapons.get(attr)
                if not w:
                    missing.add(attr)
                    continue
                L.append("            %s,  -- %s" % (lua_str(w["clsid"]), w["name"].replace("\n", " ")))
            L.append("        },")
        L.append("    },")
    L.append("}")
    L.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    return missing


# ── Main ────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pydcs", default=DEFAULT_PYDCS, help="pydcs checkout (its dcs/ package is read as text)")
    ap.add_argument("--out-dir", default=DEFAULT_OUT)
    args = ap.parse_args()

    src = os.path.join(args.pydcs, "dcs")
    for f in ("vehicles.py", "planes.py", "helicopters.py", "ships.py", "statics.py", "weapons_data.py"):
        if not os.path.exists(os.path.join(src, f)):
            sys.exit("missing %s — is --pydcs pointing at a pydcs checkout?" % os.path.join(src, f))

    overrides = {}
    if os.path.exists(OVERRIDES):
        with open(OVERRIDES, encoding="utf-8") as f:
            overrides = json.load(f)
    used_overrides = set()
    unclassified = []

    def pick_role(uid, guess):
        if uid in overrides:
            used_overrides.add(uid)
            return overrides[uid]
        if guess is None:
            unclassified.append(uid)
            return "unclassified"
        return guess

    # Ground
    ground = []
    for cat, _cls, f, _p in parse_classes(os.path.join(src, "vehicles.py")):
        uid, name = f["id"], f.get("name", "")
        role = pick_role(uid, role_ground(cat, uid, name))
        system = sam_system(name) if cat == "AirDefence" and role.startswith(("sam_", "shorad", "ewr")) else None
        ground.append((uid, [
            ("type", uid), ("name", name), ("cat", cat), ("role", role), ("system", system),
            ("detection_m", f.get("detection_range", 0)), ("threat_m", f.get("threat_range", 0)),
            ("air_weapon_m", f.get("air_weapon_dist", 0)),
        ]))

    # Aircraft
    def air_entries(fname, is_heli):
        out, pyl = [], []
        for _o, _cls, f, pylons in parse_classes(os.path.join(src, fname)):
            uid = f["id"]
            tasks = f.get("tasks", [])
            role = pick_role(uid, role_air(tasks, f.get("task_default"), is_heli))
            out.append((uid, [
                ("type", uid), ("role", role), ("tasks", tasks), ("task_default", f.get("task_default")),
                ("fuel_max", f.get("fuel_max")), ("max_speed", f.get("max_speed")),
                ("chaff", f.get("chaff", 0)), ("flare", f.get("flare", 0)),
                ("pylons", len(f.get("pylons", []))), ("flyable", f.get("flyable", False)),
                ("large_parking", f.get("large_parking_slot")), ("tacan", f.get("tacan")),
                ("group_size_max", f.get("group_size_max")),
            ]))
            pyl.append((uid, pylons))
        return out, pyl

    planes, plane_pylons = air_entries("planes.py", False)
    helis, heli_pylons = air_entries("helicopters.py", True)

    # Ships
    ships = []
    for _o, _cls, f, _p in parse_classes(os.path.join(src, "ships.py")):
        uid, name = f["id"], f.get("name", "")
        role = pick_role(uid, role_ship(uid, name))
        ships.append((uid, [
            ("type", uid), ("name", name), ("role", role),
            ("detection_m", f.get("detection_range", 0)), ("threat_m", f.get("threat_range", 0)),
            ("air_weapon_m", f.get("air_weapon_dist", 0)),
            ("plane_num", f.get("plane_num")), ("helicopter_num", f.get("helicopter_num")),
        ]))

    def order(entries):
        return sorted(entries, key=lambda e: (dict(e[1]).get("cat", ""), dict(e[1])["role"], e[0].lower()))

    ground, planes, helis, ships = order(ground), order(planes), order(helis), order(ships)
    statics = static_entries(os.path.join(src, "statics.py"))

    weapons = parse_weapons(os.path.join(src, "weapons_data.py"))
    src_label = "checkout at " + os.path.abspath(args.pydcs).replace("\\", "/")
    pool_path = os.path.join(args.out_dir, "unit_pool.lua")
    pyl_path = os.path.join(args.out_dir, "aircraft_pylons.lua")
    write_pool(pool_path, ground, planes, helis, ships, statics, src_label)
    missing = write_pylons(pyl_path, plane_pylons + heli_pylons, weapons, src_label)

    print("unit_pool.lua: %d ground, %d planes, %d helicopters, %d ships, %d static objects -> %s" % (
        len(ground), len(planes), len(helis), len(ships), len(statics), pool_path))
    print("aircraft_pylons.lua: %d aircraft with pylons, %d weapons known -> %s" % (
        sum(1 for _u, p in plane_pylons + heli_pylons if p), len(weapons), pyl_path))
    if missing:
        print("WARN weapons referenced by pylons but absent from weapons_data.py: %s" % ", ".join(sorted(missing)))

    from collections import Counter
    for label, entries in (("ground", ground), ("plane", planes), ("helicopter", helis), ("ship", ships)):
        c = Counter(dict(e[1])["role"] for e in entries)
        print("  %-10s %s" % (label, ", ".join("%s=%d" % kv for kv in sorted(c.items()))))

    stale = set(overrides) - used_overrides
    if stale:
        print("WARN overrides for types that no longer exist: %s" % ", ".join(sorted(stale)))
    if unclassified:
        print("UNCLASSIFIED (%d) — add to %s:" % (len(unclassified), os.path.relpath(OVERRIDES, REPO)))
        for uid in unclassified:
            print("  " + uid)


if __name__ == "__main__":
    main()
