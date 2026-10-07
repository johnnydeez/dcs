"""Write the player slots' radio presets into a mission's flyable .miz, from the mission's data.

    python map_data_tools/miz_radio_presets.py <mission folder> ["<mission .miz>"] [--dry-run]

The .miz defaults to Saved Games\\DCS\\Missions\\<MISSION.flyable_mission_file>. Close it in
the mission editor first (the editor would save its own copy over this one). Run it again
whenever slots are added or moved (after miz_player_slots.py) or a frequency changes.

Every player slot in the mission's data/player_slots.lua gets the same layout, whatever its
jet (roadmap.md item 19, John, 2026-10-07: each jet starts on its own Darkstar and its
field's tower; F-16C: radio 1 UHF, radio 2 VHF; F/A-18C: COMM1, COMM2):
    radio 1  channel 1   the slot's own Darkstar (RADIO_CHANNELS.awacs_per_player_slot, else
                         the AWACS channel); also the group's frequency
             channel 2   the AWACS channel (Darkstar common)
             3 to 20     the airfields' UHF towers: the slot's own field, the other fields
                         that can be Blue (data/clusters.lua: not fixed Red), then the rest,
                         each alphabetical
    radio 2  channel 1   the slot's own field's traffic frequency (its tower VHF, else
                         RADIO_CHANNELS.airfield.common_traffic_mhz), as the mission's
                         airfield traffic calls use
             channel 2   the mission channel
             3 to 20     the other fields' tower VHF, in the same order
Radio 1's frequencies are checked against UHF (225-399.975 MHz), radio 2's against VHF
(116-151.975 MHz); the per-slot Darkstar list against the slots and the towers.

Only each slot unit's ["Radio"] table and its group's ["frequency"] are rewritten, as text,
in the layout DCS writes; the rest of the file stays byte for byte. Before anything is
written, the new mission is read back and compared with the old: every value but those must
be the same. The old .miz is kept beside it first as <name>.miz.<date_time>.backup (not a
.miz, so the mission editor doesn't list it). --dry-run prints the presets and writes nothing.

Reads the mission's data/radio_channels.lua, airfield_frequencies.lua, player_slots.lua and
clusters.lua, and map_data_sources\\<MISSION.airbase_reference_file> (each airbase's DCS id).
"""

import argparse
import json
import os
import re
import shutil
import sys
import time
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import dcslua      # noqa: E402
from mission_folder import MISSION_FOLDER_HELP, SAVED_GAMES_DCS, MissionFolder   # noqa: E402

CHANNELS = 20
UHF_MHZ = (225.0, 399.975)
VHF_MHZ = (116.0, 151.975)


def load_global(path):
    with open(path, encoding="utf-8") as f:
        return dcslua.loads(f.read())


def mhz_text(mhz):
    """273.0 → "273", 273.5 → "273.5", as DCS writes them."""
    text = "%.3f" % mhz
    return text.rstrip("0").rstrip(".")


# ── the presets ─────────────────────────────────────────────────────

def plan_presets(mission):
    """Each slot's presets: {group: {"base", "type", "radio1": [...], "radio2": [...]}}, and
    the problems found."""
    channels = load_global(mission.data_file("radio_channels.lua"))
    frequencies = load_global(mission.data_file("airfield_frequencies.lua"))
    slots_by_base = load_global(mission.data_file("player_slots.lua"))
    clusters = dcslua.as_list(load_global(mission.data_file("clusters.lua")))
    with open(mission.map_data_source(mission.setting("airbase_reference_file")), encoding="utf-8") as f:
        airbases = json.load(f)["airbases"]
    problems = []

    ids = {b["name"]: b.get("id") for b in airbases}
    missing_ids = sorted(n for n, i in ids.items() if i is None)
    if missing_ids:
        raise SystemExit("%s: no DCS id for %s: add each airbase's \"id\" (Airbase:getID())"
                         % (mission.setting("airbase_reference_file"), ", ".join(missing_ids)))
    can_be_blue = set()
    for c in clusters:
        if c.get("fixed") != "red":
            can_be_blue.update(dcslua.as_list(c.get("bases") or {}))

    awacs = float(channels["awacs"]["mhz"])
    mission_mhz = float(channels["mission"]["mhz"])
    common_traffic = float(channels["airfield"]["common_traffic_mhz"])
    own = {k: float(v) for k, v in (channels.get("awacs_per_player_slot") or {}).items()}

    def tower(name):
        f = frequencies.get(ids[name]) or {}
        return f.get("uhf"), f.get("vhf")

    slots = {}
    for base, entries in slots_by_base.items():
        for s in dcslua.as_list(entries):
            slots[s["group"]] = {"base": base, "type": s["type"]}
    for group in sorted(set(own) - set(slots)):
        problems.append("RADIO_CHANNELS.awacs_per_player_slot.%s: no such player slot" % group)
    for group in sorted(set(slots) - set(own)):
        if own:
            problems.append("%s has no Darkstar frequency of its own: it gets the AWACS channel's" % group)
    seen = {}
    towers_uhf = {tower(n)[0]: n for n in ids if tower(n)[0]}
    for group, mhz in sorted(own.items()):
        if mhz in seen:
            problems.append("%s and %s share Darkstar %s" % (seen[mhz], group, mhz_text(mhz)))
        seen[mhz] = group
        if mhz == awacs:
            problems.append("%s's Darkstar %s is the AWACS channel" % (group, mhz_text(mhz)))
        if mhz in towers_uhf:
            problems.append("%s's Darkstar %s is %s's tower" % (group, mhz_text(mhz), towers_uhf[mhz]))

    names = sorted(ids)
    out = {}
    for group, slot in sorted(slots.items()):
        home = slot["base"]
        order = [home] + [n for n in names if n != home and n in can_be_blue] \
                       + [n for n in names if n != home and n not in can_be_blue]
        darkstar = own.get(group, awacs)
        radio1 = [darkstar, awacs] + [tower(n)[0] for n in order if tower(n)[0]]
        home_vhf = tower(home)[1] or common_traffic
        radio2 = [home_vhf, mission_mhz] + [tower(n)[1] for n in order[1:] if tower(n)[1]]
        radio1, radio2 = [float(x) for x in radio1[:CHANNELS]], [float(x) for x in radio2[:CHANNELS]]
        for label, radio, (low, high) in (("radio 1", radio1, UHF_MHZ), ("radio 2", radio2, VHF_MHZ)):
            for i, mhz in enumerate(radio, 1):
                if not low <= mhz <= high:
                    problems.append("%s %s channel %d: %s is outside %s-%s" % (group, label, i, mhz_text(mhz),
                                                                              mhz_text(low), mhz_text(high)))
        out[group] = {"base": home, "type": slot["type"], "radio1": radio1, "radio2": radio2,
                      "fields": [n for n in order if tower(n)[0]][:CHANNELS - 2]}
    return out, problems


# ── the mission file ────────────────────────────────────────────────

def radio_block(indent, radios):
    """A unit's ["Radio"] table as DCS writes it, at `indent` tabs."""
    t = "\t" * indent
    lines = [t + '["Radio"] = ', t + "{"]
    for n, channels in enumerate(radios, 1):
        lines += [t + "\t[%d] = " % n, t + "\t{"]
        lines += [t + '\t\t["channels"] = ', t + "\t\t{"]
        lines += [t + "\t\t\t[%d] = %s," % (i, mhz_text(mhz)) for i, mhz in enumerate(channels, 1)]
        lines += [t + '\t\t}, -- end of ["channels"]']
        lines += [t + '\t\t["modulations"] = ', t + "\t\t{"]
        lines += [t + "\t\t\t[%d] = 0," % i for i in range(1, len(channels) + 1)]
        lines += [t + '\t\t}, -- end of ["modulations"]']
        lines += [t + '\t\t["channelsNames"] = {},']
        lines += [t + "\t}, -- end of [%d]" % n]
    lines.append(t + '}, -- end of ["Radio"]')
    return lines


RADIO_START = re.compile(r'^(\t+)\["Radio"\] = $')


def rewrite(text, presets):
    """The mission text with each slot unit's radios and its group's frequency replaced, and
    the slots it found."""
    lines = text.split("\n")
    out, i, found = [], 0, []
    while i < len(lines):
        m = RADIO_START.match(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        indent = len(m.group(1))
        end = lines.index("\t" * indent + '}, -- end of ["Radio"]', i)
        # the unit's name: the next ["name"] at the unit's own depth
        name_re = re.compile(r'^\t{%d}\["name"\] = "(.*)",$' % indent)
        group = next((name_re.match(l).group(1) for l in lines[end:end + 200] if name_re.match(l)), None)
        if group not in presets:
            out.extend(lines[i:end + 1])
            i = end + 1
            continue
        found.append(group)
        p = presets[group]
        out.extend(radio_block(indent, [p["radio1"], p["radio2"]]))
        i = end + 1
        # on to the group's own ["frequency"]: two tables up (the unit, its group's units)
        freq_re = re.compile(r'^(\t{%d})\["frequency"\] = [0-9.]+,$' % (indent - 2))
        group_end = re.compile(r'^\t{%d}}, -- end of \[\d+\]$' % (indent - 3))
        while i < len(lines) and not group_end.match(lines[i]):
            fm = freq_re.match(lines[i])
            out.append('%s["frequency"] = %s,' % (fm.group(1), mhz_text(p["radio1"][0])) if fm else lines[i])
            i += 1
    return "\n".join(out), found


def check_same_but_radios(old_text, new_text, presets):
    """Reads both back: every value but the slots' radios and their groups' frequency the same."""
    old, new = dcslua.loads(old_text), dcslua.loads(new_text)

    def strip(mission):
        for coalition in mission.get("coalition", {}).values():
            for country in (coalition.get("country") or {}).values():
                for category in ("plane", "helicopter"):
                    for group in ((country.get(category) or {}).get("group") or {}).values():
                        units = (group.get("units") or {}).values()
                        if any(u.get("name") in presets for u in units):
                            group.pop("frequency", None)
                            for u in units:
                                if u.get("name") in presets:
                                    u.pop("Radio", None)
        return mission

    def radios_of(mission):
        out = {}
        for coalition in mission.get("coalition", {}).values():
            for country in (coalition.get("country") or {}).values():
                for group in (((country.get("plane") or {}).get("group")) or {}).values():
                    for u in (group.get("units") or {}).values():
                        if u.get("name") in presets:
                            out[u["name"]] = ([float(v) for v in dcslua.as_list(u["Radio"][1]["channels"])],
                                              [float(v) for v in dcslua.as_list(u["Radio"][2]["channels"])],
                                              float(group["frequency"]))
        return out

    got = radios_of(new)
    for group, p in presets.items():
        if got.get(group) != (p["radio1"], p["radio2"], p["radio1"][0]):
            raise SystemExit("read back, %s's radios aren't what was written: nothing written" % group)
    if strip(old) != strip(new):
        raise SystemExit("read back, the new mission differs from the old beyond the radios: nothing written")


def write_miz(miz, new_text):
    stamp = time.strftime("%Y-%m-%d_%H%M%S")
    backup = "%s.%s.backup" % (miz, stamp)
    shutil.copy2(miz, backup)
    temp = miz + ".writing"
    with zipfile.ZipFile(miz) as old, zipfile.ZipFile(temp, "w") as new:
        for info in old.infolist():
            data = new_text.encode("utf-8") if info.filename == "mission" else old.read(info.filename)
            new.writestr(info, data, compress_type=info.compress_type)
    os.replace(temp, miz)
    return backup


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("mission_folder", help=MISSION_FOLDER_HELP)
    ap.add_argument("miz", nargs="?", help="default: Saved Games\\DCS\\Missions\\<MISSION.flyable_mission_file>")
    ap.add_argument("--dry-run", action="store_true", help="print the presets, write nothing")
    args = ap.parse_args()
    mission = MissionFolder(args.mission_folder)
    miz = args.miz or os.path.join(SAVED_GAMES_DCS, "Missions", mission.setting("flyable_mission_file"))

    presets, problems = plan_presets(mission)
    for p in problems:
        print("WARNING: " + p)
    with zipfile.ZipFile(miz) as z:
        old_text = z.read("mission").decode("utf-8")
    new_text, found = rewrite(old_text, presets)
    for group in sorted(set(presets) - set(found)):
        print("WARNING: %s is in player_slots.lua but not in %s: run miz_player_slots.py" % (group, os.path.basename(miz)))
    presets = {g: p for g, p in presets.items() if g in found}
    check_same_but_radios(old_text, new_text, presets)

    for group in sorted(presets):
        p = presets[group]
        print("%-14s %-14s radio 1: Darkstar %s, common %s, then %d towers (%s first); radio 2: %s tower %s, mission %s, then %d"
              % (group, p["type"], mhz_text(p["radio1"][0]), mhz_text(p["radio1"][1]), len(p["radio1"]) - 2, p["base"],
                 p["base"], mhz_text(p["radio2"][0]), mhz_text(p["radio2"][1]), len(p["radio2"]) - 2))
    if args.dry_run:
        print("dry run: %d slots' presets, nothing written" % len(presets))
        return
    if new_text == old_text:
        print("%d slots' presets already as above: %s unchanged" % (len(presets), miz))
        return
    backup = write_miz(miz, new_text)
    print("%d slots' presets written to %s (the old one kept as %s)" % (len(presets), miz, os.path.basename(backup)))


if __name__ == "__main__":
    main()
