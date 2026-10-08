"""Divide a map among its airbases: each base's domain, the ground nearer to it than to any
other base, and every spawn site's home base (missions/afghanistan_campaign/mission_design.md,
*Base domains and rings*; John, 2026-10-08).

Map data, the same whoever holds the bases: a mission looks up who holds a site's home base,
and when a base changes hands its whole domain goes with it. Straight-line distance for now
(John: "domains by straight line to start are fine"); travel cost once off-road routing exists,
rewriting only what this tool writes.

    python find_base_domains.py                 the domains and every site's home base
    python find_base_domains.py make-mission    the viewer mission (show_base_domains.lua)

Reads  shared_mission_framework/map_data/<map>/airbases.lua      (MAP_AIRBASES)
       shared_mission_framework/map_data/<map>/spawn_sites_index.lua and spawn_sites/tile_*.lua
       the survey run's run.lua (its measured box), when it is on this PC
Writes shared_mission_framework/map_data/<map>/base_domains.lua  (BASE_DOMAINS: the bases with
       a domain, their outlines, neighbours and site counts)
       shared_mission_framework/map_data/<map>/site_domains/tile_*.lua  (SITE_DOMAINS_TILE:
       one line per site, in its spawn_sites tile's order: number, home base id, distance)
Never writes the spawn site files themselves (John: they took a long time to make).

The bases with a domain: every airfield; a helipad (longest runway under HELIPAD_RUNWAY_M) is
part of the airfield within HELIPAD_PART_OF_FIELD_M of it (Kandahar Heliport is Kandahar's),
else a base with a domain of its own (Ghazni, Urgoon). A base's centre is the mean of its
runways' midpoints (Airbase:getPoint() is a runway threshold: dcs_scripting_gotchas.md).

The distance, not a ring: how far out each ring reaches is each mission's own setting.

Standard library only; runs on Python 3.7+.
"""

import argparse
import math
import os
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dcslua               # noqa: E402
import find_spawn_sites     # noqa: E402

HELIPAD_RUNWAY_M = 500           # a "runway" shorter than this is a helipad's pad (heliports report as airdromes)
HELIPAD_PART_OF_FIELD_M = 10000  # a helipad this close to an airfield is part of it
OFF_THE_MAP_M = 2000000          # placeholder "airdromes" sit millions of metres off the map
COUNT_BAND_M = 25000             # each domain's sites are counted in bands this wide, for the summary
SHARED_EDGE_M = 1.0              # a corner of a domain this close to the bisector with a neighbour lies on their border
DOMAINS_INDEX = "base_domains.lua"
DOMAINS_FOLDER = "site_domains"


def base_centre(base):
    runways = dcslua.as_list(base.get("runways") or {})
    if runways:
        return (sum(r["x"] for r in runways) / len(runways), sum(r["z"] for r in runways) / len(runways))
    return (base["x"], base["z"])


def longest_runway(base):
    return max([r.get("length_m", 0) for r in dcslua.as_list(base.get("runways") or {})] or [0])


def domain_bases(airbases):
    """The bases that get a domain, each { id, name, kind, x, z, helipads }, and what was left out."""
    fields, helipads, skipped = [], [], []
    for b in airbases:
        if abs(b["x"]) > OFF_THE_MAP_M or abs(b["z"]) > OFF_THE_MAP_M:
            skipped.append(b["name"] + " (off the map)")
            continue
        x, z = base_centre(b)
        entry = {"id": int(b["id"]), "name": b["name"], "x": round(x), "z": round(z), "helipads": []}
        if longest_runway(b) < HELIPAD_RUNWAY_M:
            entry["kind"] = "helipad"
            helipads.append(entry)
        else:
            entry["kind"] = "airfield"
            fields.append(entry)
    bases = list(fields)
    for h in helipads:
        nearest = min(fields, key=lambda f: math.hypot(f["x"] - h["x"], f["z"] - h["z"]))
        if math.hypot(nearest["x"] - h["x"], nearest["z"] - h["z"]) <= HELIPAD_PART_OF_FIELD_M:
            nearest["helipads"].append({"id": h["id"], "name": h["name"]})
        else:
            bases.append(h)
    bases.sort(key=lambda b: b["id"])
    return bases, skipped


def survey_box(map_folder, index):
    """The box the survey measured (its run.lua, git-ignored), or the tiles' bounds without it."""
    run = map_folder / "survey_measurements" / index["survey_run"] / "run.lua"
    if run.exists():
        r = find_spawn_sites.load_lua_global(run, "SURVEY_RUN")
        return {"x_min": r["x_min"], "x_max": r["x_max"], "z_min": r["z_min"], "z_max": r["z_max"]}, "the survey run's box"
    tiles = dcslua.as_list(index["tiles"])
    return ({"x_min": min(t["x_min"] for t in tiles), "x_max": max(t["x_max"] for t in tiles),
             "z_min": min(t["z_min"] for t in tiles), "z_max": max(t["z_max"] for t in tiles)},
            "the tiles' bounds (no run.lua on this PC)")


def clip(polygon, base, other):
    """The part of a convex polygon (list of (x, z)) nearer to base than to other (Sutherland–Hodgman
    on their bisector)."""
    nx, nz = other["x"] - base["x"], other["z"] - base["z"]
    mx, mz = (base["x"] + other["x"]) / 2, (base["z"] + other["z"]) / 2

    def side(p):
        return (p[0] - mx) * nx + (p[1] - mz) * nz     # <= 0: base's side

    out = []
    for k in range(len(polygon)):
        a, b = polygon[k], polygon[(k + 1) % len(polygon)]
        sa, sb = side(a), side(b)
        if sa <= 0:
            out.append(a)
        if (sa <= 0) != (sb <= 0):
            t = sa / (sa - sb)
            out.append((a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])))
    return out


def domain_outlines(bases, box):
    corners = [(box["x_min"], box["z_min"]), (box["x_min"], box["z_max"]), (box["x_max"], box["z_max"]), (box["x_max"], box["z_min"])]
    for b in bases:
        poly = list(corners)
        for o in bases:
            if o is not b:
                poly = clip(poly, b, o)
        b["outline"] = [(round(p[0]), round(p[1])) for p in poly]
        b["area_km2"] = round(abs(sum(poly[k][0] * poly[(k + 1) % len(poly)][1] - poly[(k + 1) % len(poly)][0] * poly[k][1]
                                      for k in range(len(poly)))) / 2 / 1e6)
    # neighbours: the stretch of outline each pair shares, on their bisector
    for b in bases:
        b["neighbours"] = []
        for o in bases:
            if o is b:
                continue
            on = [p for p in b["outline"] if abs(math.hypot(p[0] - b["x"], p[1] - b["z"]) - math.hypot(p[0] - o["x"], p[1] - o["z"])) <= SHARED_EDGE_M + 1]
            if len(on) >= 2:
                a, c = max(((p, q) for p in on for q in on), key=lambda pq: math.hypot(pq[0][0] - pq[1][0], pq[0][1] - pq[1][1]))
                if math.hypot(a[0] - c[0], a[1] - c[1]) > 0:
                    b["neighbours"].append({"id": o["id"], "border": [list(a), list(c)]})


def read_tile_sites(path):
    """A spawn sites tile's (number, x, z) in file order."""
    text = path.read_text(encoding="utf-8")
    return [(int(n), int(x), int(z)) for n, x, z in find_spawn_sites.SITE_LINE.findall(text)]


def write_tile(folder, tile, homes, map_name, run_name):
    lines = [
        "-- The home base of every spawn site in one tile of the %s map: its nearest base with a domain, by" % map_name,
        "-- straight line, and how far. The same sites, in the same order, as ..\\spawn_sites\\%s.lua (survey run %s);" % (tile["name"], run_name),
        "-- see ..\\%s for the bases. Generated by map_data_tools/find_base_domains.py; do not hand-edit." % DOMAINS_INDEX,
        "-- One site per line: number, home base id (DCS's airbase id), distance from its centre in metres.",
        "",
        "SITE_DOMAINS_TILE = {",
        "    tile = %s," % dcslua.dumps(tile["name"]),
        "    sites = {",
    ]
    lines += ["        { %d, %d, %d }," % h for h in homes]
    lines += ["    },", "}", ""]
    (folder / tile["file"]).write_text("\n".join(lines), encoding="utf-8")


def run_domains(map_folder_name):
    started = time.time()
    map_folder = find_spawn_sites.MAP_DATA / map_folder_name
    index = find_spawn_sites.load_lua_global(map_folder / find_spawn_sites.SITES_INDEX, "SPAWN_SITES")
    airbases = dcslua.as_list(find_spawn_sites.load_lua_global(map_folder / "airbases.lua", "MAP_AIRBASES"))
    bases, skipped = domain_bases(airbases)
    box, box_from = survey_box(map_folder, index)
    domain_outlines(bases, box)

    temp_folder = map_folder / (DOMAINS_FOLDER + ".tmp")
    find_spawn_sites.remove_tile_files(temp_folder)
    temp_folder.mkdir(parents=True)
    by_id = {b["id"]: b for b in bases}
    for b in bases:
        b["sites"], b["farthest_site_m"], b["sites_per_band"] = 0, 0, {}
    positions = [(b["id"], b["x"], b["z"]) for b in bases]
    total = 0
    for tile in dcslua.as_list(index["tiles"]):
        sites = read_tile_sites(map_folder / index["folder"] / tile["file"])
        if len(sites) != tile["sites"]:
            raise SystemExit("%s: %d sites, the index says %d" % (tile["file"], len(sites), tile["sites"]))
        homes = []
        for number, x, z in sites:
            best, best_d2 = None, None
            for bid, bx, bz in positions:
                d2 = (bx - x) ** 2 + (bz - z) ** 2
                if best_d2 is None or d2 < best_d2:
                    best, best_d2 = bid, d2
            d = round(math.sqrt(best_d2))
            homes.append((number, best, d))
            b = by_id[best]
            b["sites"] += 1
            b["farthest_site_m"] = max(b["farthest_site_m"], d)
            band = d // COUNT_BAND_M
            b["sites_per_band"][band] = b["sites_per_band"].get(band, 0) + 1
        write_tile(temp_folder, tile, homes, index["map"], index["survey_run"])
        total += len(sites)
    folder = map_folder / DOMAINS_FOLDER
    find_spawn_sites.remove_tile_files(folder)
    os.replace(temp_folder, folder)

    out = map_folder / DOMAINS_INDEX
    lines = [
        "-- Each base's domain on the %s map: the ground nearer to it than to any other base with a domain," % index["map"],
        "-- by straight line (John, 2026-10-08). Map data, whoever holds the bases: a site belongs to whoever holds",
        "-- its home base (site_domains\\<tile>.lua, beside the spawn_sites tile files). Generated by",
        "-- map_data_tools/find_base_domains.py from airbases.lua and the spawn sites of survey run %s; do not hand-edit." % index["survey_run"],
        "-- Every airfield has a domain; a helipad within %d km of an airfield is part of it (helipads), else it has" % (HELIPAD_PART_OF_FIELD_M // 1000),
        "-- its own. x / z: the mean of the base's runway midpoints. outline: its domain, corners in order, inside",
        "-- the box (%s). neighbours: each base its domain borders, and the border between them." % box_from,
        "-- sites_per_band: its sites by distance from it, band n holding %d km × n up to %d km × (n + 1)." % (COUNT_BAND_M // 1000, COUNT_BAND_M // 1000),
        "-- Metres; x north, z east (DCS's own).",
        "",
        "BASE_DOMAINS = {",
        "    map = %s," % dcslua.dumps(index["map"]),
        "    survey_run = %s," % dcslua.dumps(index["survey_run"]),
        "    made = %s," % dcslua.dumps(time.strftime("%Y-%m-%d %H:%M")),
        "    distance = \"straight line\",",
        "    folder = %s," % dcslua.dumps(DOMAINS_FOLDER),
        "    site_fields = { \"number\", \"base_id\", \"distance_m\" },",
        "    band_m = %d," % COUNT_BAND_M,
        "    box = { x_min = %d, x_max = %d, z_min = %d, z_max = %d }," % (box["x_min"], box["x_max"], box["z_min"], box["z_max"]),
        "    sites = %d," % total,
        "    bases = {",
    ]
    for b in bases:
        bands = max(b["sites_per_band"]) + 1 if b["sites_per_band"] else 0
        lines += [
            "        {",
            "            id = %d, name = %s, kind = %s, x = %d, z = %d," % (b["id"], dcslua.dumps(b["name"]), dcslua.dumps(b["kind"]), b["x"], b["z"]),
            "            helipads = { %s }," % ", ".join("{ id = %d, name = %s }" % (h["id"], dcslua.dumps(h["name"])) for h in b["helipads"]),
            "            area_km2 = %d, sites = %d, farthest_site_m = %d," % (b["area_km2"], b["sites"], b["farthest_site_m"]),
            "            sites_per_band = { %s }," % ", ".join(str(b["sites_per_band"].get(n, 0)) for n in range(bands)),
            "            outline = { %s }," % ", ".join("{ %d, %d }" % p for p in b["outline"]),
            "            neighbours = {",
        ]
        lines += ["                { id = %d, border = { { %d, %d }, { %d, %d } } }," % (n["id"], n["border"][0][0], n["border"][0][1],
                                                                                    n["border"][1][0], n["border"][1][1]) for n in b["neighbours"]]
        lines += ["            },", "        },"]
    lines += ["    },", "}", ""]
    temp = out.with_suffix(".lua.tmp")
    temp.write_text("\n".join(lines), encoding="utf-8")
    os.replace(temp, out)

    print("%d bases with a domain (%s); left out: %s" % (len(bases), box_from, ", ".join(skipped) or "none"))
    for b in sorted(bases, key=lambda b: -b["sites"]):
        print("  %-28s %-8s %6d km2 %7d sites, farthest %3d km%s" % (b["name"], b["kind"], b["area_km2"], b["sites"],
              b["farthest_site_m"] // 1000, ("; helipads: " + ", ".join(h["name"] for h in b["helipads"])) if b["helipads"] else ""))
    print("%d sites -> %s and %d tile files in %s (%.0f s)" % (total, out, len(index["tiles"]), folder, time.time() - started))


def run_mission(map_name, campaign_mission):
    """The viewer mission: John's campaign mission (who holds which base) with its trigger running
    show_base_domains.lua."""
    template = Path(campaign_mission)
    if not template.exists():
        raise SystemExit("no mission %s" % template)
    import zipfile
    with zipfile.ZipFile(template) as z:
        text = z.read("mission").decode("utf-8")
    if dcslua.loads(text).get("theatre") != map_name:
        raise SystemExit("%s is not on the %s map" % (template, map_name))
    out = find_spawn_sites.SAVED_GAMES / "Missions" / ("%s_base_domains_shown.miz" % map_name.lower())
    find_spawn_sites.write_miz(template, out, find_spawn_sites.mission_running(text, "show_base_domains.lua"))
    print("wrote %s from %s (its bases' owners): fly it to see the domains" % (out, template))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("what", nargs="?", default="domains", choices=["domains", "make-mission"])
    ap.add_argument("--map", default=find_spawn_sites.DEFAULT_MAP)
    ap.add_argument("--map-folder", help="the map's folder under map_data (default: --map in lower case)")
    ap.add_argument("--campaign-mission", default=str(find_spawn_sites.SAVED_GAMES / "Missions" / "afghanistan_campaign.miz"),
                    help="make-mission: the mission whose bases' owners the viewer shows")
    args = ap.parse_args()
    if args.what == "make-mission":
        run_mission(args.map, args.campaign_mission)
    else:
        run_domains(args.map_folder or args.map.lower())


if __name__ == "__main__":
    main()
