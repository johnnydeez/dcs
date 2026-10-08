"""Find spawn sites in the spawn site survey's measurements, and make the missions that run
the survey and show what it found (missions/afghanistan_campaign/mission_design.md, *Map
data: the site survey*; John, 2026-10-07).

A spawn site is one kind of place: a clear, flat, dry disc where anything fits (a group of
ground units, a large SAM site, a target). The survey (map_surveys/survey_spawn_sites.lua,
in DCS) measures; this decides, so the rules below can be tuned without flying it again.

    python find_spawn_sites.py                  every surveyed test area of the map: sites
    python find_spawn_sites.py map-survey       the whole map, from its newest finished survey
    python find_spawn_sites.py make-missions    the survey and viewer missions

Test areas (trigger zones in the survey mission):
Reads  Saved Games/DCS/map_surveys/<map>/area_<name>.lua  (SURVEYED_AREA, one per area)
Writes Saved Games/DCS/map_surveys/<map>/spawn_sites_<name>.lua  (SPAWN_SITES), which the
       viewer mission (map_surveys/show_spawn_sites.lua) draws on the F10 map.

The whole map (John, 2026-10-08):
Reads  shared_mission_framework/map_data/<map>/survey_measurements/<run>/  (run.lua, the
       tile_*.txt files, latitude_longitude_grid.txt; git-ignored)
Writes shared_mission_framework/map_data/<map>/spawn_sites_index.lua and spawn_sites/tile_*.lua
       (SPAWN_SITES, the index, and SPAWN_SITES_TILE per tile: every site of
       the map with its GPS), and says what changed against the file it replaces.
Same rules as the test areas, and the same sites a test area's survey would find there: a
site centred near a tile's edge is judged with the neighbouring tile's points, and the
spacing is worked out across the whole map at once.

make-missions copies John's survey mission (the template: any mission on the map whose one
trigger runs a map_surveys script) into
    Saved Games/DCS/Missions/<map>_spawn_site_survey.miz   runs survey_spawn_sites.lua; put
        a trigger zone where each test area should be (its name names the area). Not
        overwritten once it exists (zones may have been added), unless --force.
    Saved Games/DCS/Missions/<map>_spawn_sites_shown.miz   runs show_spawn_sites.lua.

Standard library only; runs on Python 3.7+.
"""

import argparse
import math
import os
import re
import sys
import time
import zipfile
from array import array
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dcslua    # noqa: E402

# ── the rules (tune here) ───────────────────────────────────────────
SITE_RADIUS_M = 275        # a disc 550 m across: Kola's zones were 274 m circles, which every SAM site and target fit
MAX_RISE_M = 15            # highest − lowest survey point inside the disc
MAX_STEP_M = 10            # between neighbouring points (100 m apart) inside the disc: 10 % slope
OBJECT_MARGIN_M = 50       # no map object within the disc and this far beyond it
SURFACES_ALLOWED = "LR"    # land and road; never water, shallow water or runway
SITE_SPACING_M = 1000      # between two sites' centres: discs 450 m apart at least

DEFAULT_MAP = "Afghanistan"
SAVED_GAMES = Path(os.path.expanduser("~")) / "Saved Games" / "DCS"
MAP_DATA = Path(os.path.dirname(os.path.abspath(__file__))).parent / "map_data"
SAME_SITE_M = 100          # comparing with the last sites file: a site this close to an old one is the same site
SITES_INDEX = "spawn_sites_index.lua"   # the whole map's sites: this index in map_data/<map>/ (John, 2026-10-08)
SITES_FOLDER = "spawn_sites"            # ... and one file per tile in this folder beside it


def survey_folder(map_name):
    return SAVED_GAMES / "map_surveys" / map_name


def load_lua_global(path, name):
    """The table a data file assigns to `name` (NAME = { ... }, comments above it)."""
    text = Path(path).read_text(encoding="utf-8")
    if not re.search(r"^%s\s*=" % re.escape(name), text, re.M):
        raise SystemExit("%s: no %s = { ... } in it" % (path, name))
    return dcslua.loads(text)


# ── one area ────────────────────────────────────────────────────────

class Area:
    """The survey's points and object squares of one area, on one grid of step_m."""

    def __init__(self, raw):
        self.raw = raw
        self.name = raw["name"]
        self.x_min, self.z_min = raw["x_min"], raw["z_min"]
        st = raw["settings"]
        self.step = st["step_m"]
        self.cell_m = st["cell_m"]
        self.cells = dcslua.as_list(raw["cells"])
        self.points = {}    # (i, k) → (height, surface letter); i north, k east, from the area's corner
        self.squares = {}   # (i, k) → objects in the square whose south-west corner is point (i, k)
        self.cell_at = {}   # (row, col) → cell
        for c in self.cells:
            self.cell_at[(c["row"], c["col"])] = c
            two = c.get("pass_2")
            if not two:
                continue
            n = two["points_per_side"]
            h = dcslua.as_list(two["h"])
            s = two["s"]
            i0 = int(round((c["x"] - self.x_min) / self.step))
            k0 = int(round((c["z"] - self.z_min) / self.step))
            for a in range(n):
                for b in range(n):
                    self.points[(i0 + a, k0 + b)] = (h[a * n + b], s[a * n + b])
            q = two.get("squares_per_side", n - 1)
            sq = dcslua.as_list(two.get("squares") or [])
            for a in range(q):
                for b in range(q):
                    if sq and sq[a * q + b]:
                        self.squares[(i0 + a, k0 + b)] = sq[a * q + b]

    def xz(self, i, k):
        return self.x_min + i * self.step, self.z_min + k * self.step

    def cell_of(self, x, z):
        return self.cell_at.get((int((x - self.x_min) // self.cell_m), int((z - self.z_min) // self.cell_m)))


def disc_offsets(step):
    r = SITE_RADIUS_M / step
    n = int(math.ceil(r))
    return [(a, b) for a in range(-n, n + 1) for b in range(-n, n + 1) if math.hypot(a, b) <= r + 1e-9]


def square_offsets(step):
    """Squares (by their south-west corner, relative to a centre point) whose middle lies
    within the disc plus the margin plus half a square's diagonal: any part of it may be
    inside."""
    r = (SITE_RADIUS_M + OBJECT_MARGIN_M) / step + math.sqrt(0.5)
    n = int(math.ceil(r)) + 1
    return [(a, b) for a in range(-n, n) for b in range(-n, n) if math.hypot(a + 0.5, b + 0.5) <= r]


def judge(area, i, k, disc, squares):
    """None if a site may centre on point (i, k), else why not; and the disc's rise."""
    heights = []
    for a, b in disc:
        p = area.points.get((i + a, k + b))
        if p is None:
            return "not surveyed (steep or wet nearby)", None
        if p[1] not in SURFACES_ALLOWED:
            return "water or runway", None
        heights.append(p[0])
    for a, b in squares:
        if area.squares.get((i + a, k + b)):
            return "map objects", None
    rise = max(heights) - min(heights)
    if rise > MAX_RISE_M:
        return "rise", rise
    inside = set(disc)
    for a, b in disc:
        h = area.points[(i + a, k + b)][0]
        for da, db in ((1, 0), (0, 1)):
            if (a + da, b + db) in inside and abs(area.points[(i + a + da, k + b + db)][0] - h) > MAX_STEP_M:
                return "slope", rise
    return None, rise


def find_sites(area):
    disc = disc_offsets(area.step)
    squares = square_offsets(area.step)
    reasons, good = {}, []
    for (i, k) in sorted(area.points):
        why, rise = judge(area, i, k, disc, squares)
        if why:
            reasons[why] = reasons.get(why, 0) + 1
        else:
            good.append((rise, i, k))
    # flattest first, then spaced out
    good.sort()
    chosen = []
    spacing = SITE_SPACING_M / area.step
    for rise, i, k in good:
        if all(math.hypot(i - ci, k - ck) >= spacing for _, ci, ck in chosen):
            chosen.append((rise, i, k))
    sites = []
    for n, (rise, i, k) in enumerate(sorted(chosen, key=lambda t: (t[1], t[2])), 1):
        x, z = area.xz(i, k)
        cell = area.cell_of(x, z) or {}
        sites.append({
            "number": n, "x": x, "z": z, "radius_m": SITE_RADIUS_M,
            "height_m": area.points[(i, k)][0], "rise_m": rise,
            "road_m": (cell.get("pass_2") or {}).get("road_m"),
        })
    # flat and dry cells (through to pass 2) with no site centre in them
    with_site = {(int((s["x"] - area.x_min) // area.cell_m), int((s["z"] - area.z_min) // area.cell_m)) for s in sites}
    near = [{"x": c["x"], "z": c["z"], "size_m": area.cell_m} for c in area.cells
            if c.get("pass_2") and (c["row"], c["col"]) not in with_site]
    return sites, near, reasons, len(good)


def write_sites(path, area, sites, near, reasons, candidates):
    raw = area.raw
    out = {
        "area": {"name": area.name, "x_min": raw["x_min"], "x_max": raw["x_max"],
                 "z_min": raw["z_min"], "z_max": raw["z_max"]},
        "rules": {"site_radius_m": SITE_RADIUS_M, "max_rise_m": MAX_RISE_M, "max_step_m": MAX_STEP_M,
                  "object_margin_m": OBJECT_MARGIN_M, "surfaces_allowed": SURFACES_ALLOWED,
                  "site_spacing_m": SITE_SPACING_M},
        "counts": {"points": len(area.points), "candidates": candidates, "sites": len(sites),
                   "rejected": reasons},
        "sites": sites,
        "near_misses": near,
    }
    head = ("-- Spawn sites in one surveyed area, found by map_data_tools/find_spawn_sites.py from\n"
            "-- %s. Generated; do not hand-edit. Metres; x north, z east (DCS's own).\n\n" % os.path.basename(raw["_file"]))
    path.write_text(head + "SPAWN_SITES = " + dcslua.dumps(out, key_order=["area", "rules", "counts", "number", "x", "z"]) + "\n",
                    encoding="utf-8")


def run_sites(map_name, folder=None):
    folder = Path(folder) if folder else survey_folder(map_name)
    files = sorted(folder.glob("area_*.lua")) if folder.exists() else []
    if not files:
        raise SystemExit("no surveyed areas in %s: fly the survey mission first" % folder)
    for f in files:
        raw = load_lua_global(f, "SURVEYED_AREA")
        raw["_file"] = str(f)
        area = Area(raw)
        sites, near, reasons, candidates = find_sites(area)
        out = folder / ("spawn_sites_" + f.name[len("area_"):])
        write_sites(out, area, sites, near, reasons, candidates)
        cells = len(area.cells)
        two = sum(1 for c in area.cells if c.get("pass_2"))
        print("%s: %d cells, %d flat and dry enough for pass 2; %d points looked at, %d could centre a site, "
              "%d sites chosen (%d m apart at least)" % (area.name, cells, two, len(area.points), candidates,
                                                        len(sites), SITE_SPACING_M))
        for why, n in sorted(reasons.items(), key=lambda t: -t[1]):
            print("    not a centre, %-36s %7d points" % (why + ":", n))
        if sites:
            roads = sorted(s["road_m"] for s in sites if s["road_m"] is not None)
            if roads:
                print("    road from the site's cell: median %d m, farthest %d m" % (roads[len(roads) // 2], roads[-1]))
        print("    -> %s" % out)


# ── the whole map ───────────────────────────────────────────────────

class Points:
    """Survey points and object squares on the map's own step_m lattice, (I, K) with
    x = I * step, z = K * step: what judge() reads."""

    def __init__(self):
        self.points = {}    # (I, K) → (height, surface letter)
        self.squares = {}   # (I, K) → objects in the square whose south-west corner is point (I, K)


def tile_name(x_m, z_m):
    """As survey_spawn_sites.lua names a tile: its lattice corner in km."""
    return "tile_x%+05d_z%+05d" % (x_m // 1000, z_m // 1000)


def read_tile(path):
    """A tile file: its tile line, its pass 2 cells' fields by (row, col), and its end line."""
    tile, end, cells = None, None, {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("B "):
                parts = line.split()
                cells[(int(parts[1]), int(parts[2]))] = parts
            elif line.startswith("tile "):
                tile = [int(v) for v in line.split()[1:]]
            elif line.startswith("end "):
                end = [int(v) for v in line.split()[1:]]
    if tile is None or end is None:
        raise SystemExit("%s: not a whole tile (no tile or end line)" % path)
    return {"tile": tile, "end": end, "cells": cells}


def add_cell(grid, parts, per_cell):
    """One pass 2 cell's points and object squares into grid. parts: B row col rise objects
    pass_1_heights pass_1_surfaces road_m lowest heights surfaces squares."""
    n = per_cell + 1
    i0, k0 = int(parts[1]) * per_cell, int(parts[2]) * per_cell
    lowest = int(parts[8])
    heights = parts[9].split(",")
    letters = parts[10]
    if len(letters) == 1:
        letters = letters * (n * n)
    points = grid.points
    index = 0
    for a in range(n):
        for b in range(n):
            points[(i0 + a, k0 + b)] = (lowest + int(heights[index]), letters[index])
            index += 1
    if parts[11] != "-":
        for item in parts[11].split(","):
            k, count = item.split(":")
            k = int(k)
            grid.squares[(i0 + k // per_cell, k0 + k % per_cell)] = int(count)


def read_latitude_grid(path):
    grid = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            x, z, lat, lon = line.split()
            grid[(int(x), int(z))] = (float(lat), float(lon))
    return grid


def latitude_longitude(grid, spacing, x, z):
    """DCS's GPS of (x, z), between the four grid points around it."""
    x0, z0 = (x // spacing) * spacing, (z // spacing) * spacing
    fx, fz = (x - x0) / spacing, (z - z0) / spacing
    corners = [grid.get((x0 + a * spacing, z0 + b * spacing)) for a in (0, 1) for b in (0, 1)]
    if None in corners:   # on the grid's last line: the point itself is on it
        exact = grid.get((x0, z0))
        return exact if exact else (None, None)
    (a, b), (c, d), (e, f), (g, h) = corners   # (x0,z0) (x0,z1) (x1,z0) (x1,z1)
    lat = (a * (1 - fz) + c * fz) * (1 - fx) + (e * (1 - fz) + g * fz) * fx
    lon = (b * (1 - fz) + d * fz) * (1 - fx) + (f * (1 - fz) + h * fz) * fx
    return lat, lon


def newest_finished_run(folder):
    runs = sorted(p for p in folder.glob("????-??-??_????") if (p / "survey_complete.lua").exists()) if folder.exists() else []
    if not runs:
        raise SystemExit("no finished survey in %s: fly the survey mission first" % folder)
    return runs[-1]


SITE_LINE = re.compile(r"^\s*\{ (\d+), (-?\d+), (-?\d+),", re.M)                  # a tile file's site
OLD_SITE_LINE = re.compile(r"\{ number = \d+, x = (-?\d+), z = (-?\d+),")          # the one-file sites (2026-10-08 first run)
OLD_RUN = re.compile(r'^\s*survey_run = "([^"]*)"', re.M)


def read_site_positions(index):
    """The sites an earlier sites file lists, as {"x", "z"}, and its survey run: from the index and
    its tile files, or from the one big file the first run wrote (2026-10-08). Read by pattern,
    not as Lua: the big file is 39 MB."""
    text = index.read_text(encoding="utf-8")
    run = OLD_RUN.search(text)
    run = run.group(1) if run else "?"
    if "tiles = {" in text:
        folder = index.parent / SITES_FOLDER
        positions = []
        for f in sorted(folder.glob("tile_*.lua")):
            positions += [{"x": int(m.group(2)), "z": int(m.group(3))} for m in SITE_LINE.finditer(f.read_text(encoding="utf-8"))]
        return positions, run
    return [{"x": int(m.group(1)), "z": int(m.group(2))} for m in OLD_SITE_LINE.finditer(text)], run


def compare_with_last(path, sites):
    """How many of `sites` an earlier sites file has too (within SAME_SITE_M), how many are new
    and how many of its sites are gone; None when there is no earlier file."""
    if not path.exists():
        return None
    old_sites, old_run = read_site_positions(path)
    by_km = {}
    for n, s in enumerate(old_sites):
        by_km.setdefault((int(s["x"] // 1000), int(s["z"] // 1000)), []).append(n)
    matched_old = set()
    same = 0
    for s in sites:
        ci, ck = int(s["x"] // 1000), int(s["z"] // 1000)
        found = None
        for a in (ci - 1, ci, ci + 1):
            for b in (ck - 1, ck, ck + 1):
                for n in by_km.get((a, b), ()):
                    o = old_sites[n]
                    if n not in matched_old and math.hypot(o["x"] - s["x"], o["z"] - s["z"]) <= SAME_SITE_M:
                        found = n
                        break
                if found is not None:
                    break
            if found is not None:
                break
        if found is not None:
            matched_old.add(found)
            same += 1
    return {"run": old_run, "same": same, "new": len(sites) - same, "gone": len(old_sites) - same}


SITE_FIELDS = ["number", "x", "z", "latitude", "longitude", "height_m", "rise_m"]


def remove_tile_files(folder):
    """The tile files of an earlier sites folder (tile_*.lua, one by one), then the folder."""
    if folder.exists():
        for f in folder.glob("tile_*.lua"):
            f.unlink()
        folder.rmdir()   # fails, and stops the tool, if anything else was put in it


def write_map_sites(index, map_name, run_name, rules, counts, sites, tile_m):
    """The map's sites, split by tile so a mission loads only what it needs (John, 2026-10-08:
    the one 39 MB file was too big for the repository and for a mission to load): an index,
    <index> (SPAWN_SITES: the map, the run, the rules, the counts, every tile with its bounds and
    number of sites), and one file per tile with sites, <index without .lua>\\tile_<x>_<z>.lua
    (SPAWN_SITES_TILE: its sites, one short line each, fields as SPAWN_SITES.site_fields)."""
    by_tile = {}
    for s in sites:
        by_tile.setdefault(((s["x"] // tile_m) * tile_m, (s["z"] // tile_m) * tile_m), []).append(s)
    folder = index.parent / SITES_FOLDER
    temp_folder = index.parent / (SITES_FOLDER + ".tmp")
    remove_tile_files(temp_folder)
    temp_folder.mkdir(parents=True)
    tiles = []
    for (tx, tz) in sorted(by_tile):
        name = tile_name(tx, tz)
        tile_sites = by_tile[(tx, tz)]
        lines = [
            "-- The spawn sites of one %d km tile of the %s map, from the whole-map survey %s; see" % (tile_m // 1000, map_name, run_name),
            "-- ..\\%s for the rules and every tile. Generated by map_data_tools/find_spawn_sites.py; do not hand-edit." % index.name,
            "-- One site per line: number, x, z, latitude, longitude, height_m, rise_m (metres; x north, z east,",
            "-- DCS's own; degrees as DCS converts them).",
            "",
            "SPAWN_SITES_TILE = {",
            "    tile = %s, x_min = %d, x_max = %d, z_min = %d, z_max = %d," % (dcslua.dumps(name), tx, tx + tile_m, tz, tz + tile_m),
            "    sites = {",
        ]
        for s in tile_sites:
            lines.append("        { %d, %d, %d, %.5f, %.5f, %d, %d }," % (s["number"], s["x"], s["z"], s["latitude"], s["longitude"],
                                                                   s["height_m"], s["rise_m"]))
        lines += ["    },", "}", ""]
        (temp_folder / (name + ".lua")).write_text("\n".join(lines), encoding="utf-8")
        tiles.append({"name": name, "file": name + ".lua", "x_min": tx, "x_max": tx + tile_m, "z_min": tz, "z_max": tz + tile_m,
                      "sites": len(tile_sites), "first_number": tile_sites[0]["number"]})
    remove_tile_files(folder)
    os.replace(temp_folder, folder)
    lines = [
        "-- Every spawn site of the %s map (a clear, flat, dry disc where anything fits: a group of ground" % map_name,
        "-- units, a large SAM site, a target), found by map_data_tools/find_spawn_sites.py from the whole-map",
        "-- survey %s (survey_measurements\\%s, git-ignored). Generated; do not hand-edit." % (run_name, run_name),
        "-- This index lists the tiles; each tile's sites are in %s\\<file>: load only the tiles a mission needs." % folder.name,
        "-- Every site is a disc of rules.site_radius_m. No road distance (John, 2026-10-08: a mission looks it",
        "-- up for the sites it uses, land.getClosestPointOnRoads). Metres; x north, z east (DCS's own).",
        "",
        "SPAWN_SITES = {",
        "    map = %s," % dcslua.dumps(map_name),
        "    survey_run = %s," % dcslua.dumps(run_name),
        "    found = %s," % dcslua.dumps(time.strftime("%Y-%m-%d %H:%M")),
        "    tile_m = %d," % tile_m,
        "    folder = %s," % dcslua.dumps(folder.name),
        "    site_fields = { %s }," % ", ".join(dcslua.dumps(f) for f in SITE_FIELDS),
        "    rules = %s," % dcslua.dumps(rules, 1),
        "    counts = %s," % dcslua.dumps(counts, 1),
        "    tiles = {",
    ]
    for t in tiles:
        lines.append("        { name = %s, file = %s, x_min = %d, x_max = %d, z_min = %d, z_max = %d, sites = %d, first_number = %d },"
                     % (dcslua.dumps(t["name"]), dcslua.dumps(t["file"]), t["x_min"], t["x_max"], t["z_min"], t["z_max"],
                        t["sites"], t["first_number"]))
    lines += ["    },", "}", ""]
    temp = index.with_suffix(".lua.tmp")
    temp.write_text("\n".join(lines), encoding="utf-8")
    os.replace(temp, index)
    return folder, len(tiles)


def run_map_survey(map_folder, run=None, measurements=None, output=None):
    started = time.time()
    folder = Path(measurements) if measurements else MAP_DATA / map_folder / "survey_measurements"
    run_dir = folder / run if run else newest_finished_run(folder)
    if not (run_dir / "survey_complete.lua").exists():
        raise SystemExit("%s: the survey isn't finished (no survey_complete.lua): fly the survey mission to carry on" % run_dir)
    info = load_lua_global(run_dir / "run.lua", "SURVEY_RUN")
    st = info["settings"]
    cell_m, step, tile_m = st["cell_m"], st["step_m"], st["tile_m"]
    per_cell = cell_m // step
    x_min, x_max, z_min, z_max = info["x_min"], info["x_max"], info["z_min"], info["z_max"]
    last_row, last_col = x_max // cell_m - 1, z_max // cell_m - 1
    print("%s, survey %s: x %d to %d, z %d to %d (%d x %d km)" % (info["map"], run_dir.name, x_min, x_max, z_min, z_max,
                                                                 (x_max - x_min) // 1000, (z_max - z_min) // 1000))

    # the tiles, as survey_spawn_sites.lua lays them out
    tiles = []
    for tx in range((x_min // tile_m) * tile_m, x_max, tile_m):
        for tz in range((z_min // tile_m) * tile_m, z_max, tile_m):
            t = {"x": tx, "z": tz, "x_min": max(tx, x_min), "x_max": min(tx + tile_m, x_max),
                 "z_min": max(tz, z_min), "z_max": min(tz + tile_m, z_max), "name": tile_name(tx, tz)}
            if t["x_max"] > t["x_min"] and t["z_max"] > t["z_min"]:
                if not (run_dir / (t["name"] + ".txt")).exists():
                    raise SystemExit("%s: no %s.txt, though the survey says it is finished" % (run_dir, t["name"]))
                tiles.append(t)
    names = {(t["x"], t["z"]) for t in tiles}

    loaded = {}

    def tile_cells(tx, tz):
        if (tx, tz) not in names:
            return {}
        if (tx, tz) not in loaded:
            loaded[(tx, tz)] = read_tile(run_dir / (tile_name(tx, tz) + ".txt"))
        return loaded[(tx, tz)]["cells"]

    disc = disc_offsets(step)
    squares = square_offsets(step)
    i_base = x_min // step - 2 * per_cell
    k_base = z_min // step - 2 * per_cell
    span = (z_max - z_min) // step + 4 * per_cell
    height_offset, height_span = 1000, 16384   # a candidate is packed with its height: (key * span) + height + offset
    buckets = [array("q") for _ in range(MAX_RISE_M + 1)]
    reasons = {}
    points_judged = cells = pass_2_cells = objects = 0
    survey_s = 0

    for number, t in enumerate(tiles, 1):
        for key in [k for k in loaded if k[0] < t["x"] - tile_m]:   # rows of tiles behind us
            del loaded[key]
        r0, r1 = t["x_min"] // cell_m, t["x_max"] // cell_m
        c0, c1 = t["z_min"] // cell_m, t["z_max"] // cell_m
        grid = Points()
        for row in range(r0 - 1, r1 + 1):
            for col in range(c0 - 1, c1 + 1):
                parts = tile_cells((row * cell_m // tile_m) * tile_m, (col * cell_m // tile_m) * tile_m).get((row, col))
                if parts:
                    add_cell(grid, parts, per_cell)
        end = loaded[(t["x"], t["z"])]["end"]
        cells += end[0]
        pass_2_cells += end[1]
        objects += end[2]
        survey_s += end[3]
        found_here = 0
        for (i, k), (h, _) in grid.points.items():
            # each point is judged once, in the tile of the cell it is the south-west corner of;
            # the box's north and east edge points belong to the last cell before them
            row, col = min(i // per_cell, last_row), min(k // per_cell, last_col)
            if not (r0 <= row < r1 and c0 <= col < c1):
                continue
            points_judged += 1
            why, rise = judge(grid, i, k, disc, squares)
            if why:
                reasons[why] = reasons.get(why, 0) + 1
                continue
            if not (-height_offset <= h < height_span - height_offset):
                raise SystemExit("height %d m at x %d, z %d is outside what the packing holds" % (h, i * step, k * step))
            buckets[rise].append(((i - i_base) * span + (k - k_base)) * height_span + h + height_offset)
            found_here += 1
        print("tile %d of %d, %s: %d points could centre a site (%.0f s so far)"
              % (number, len(tiles), t["name"], found_here, time.time() - started))

    # flattest first, then spaced out, across the whole map at once (as find_sites)
    spacing = SITE_SPACING_M / step
    hash_size = int(math.ceil(spacing))
    chosen, by_square = [], {}
    candidates = sum(len(b) for b in buckets)
    for rise, bucket in enumerate(buckets):
        for packed in sorted(bucket):
            key, h = divmod(packed, height_span)
            di, dk = divmod(key, span)
            i, k = di + i_base, dk + k_base
            si, sk = i // hash_size, k // hash_size
            clear = True
            for a in (si - 1, si, si + 1):
                for b in (sk - 1, sk, sk + 1):
                    for (ci, ck) in by_square.get((a, b), ()):
                        if math.hypot(i - ci, k - ck) < spacing:
                            clear = False
                            break
                    if not clear:
                        break
                if not clear:
                    break
            if clear:
                chosen.append((i, k, rise, h - height_offset))
                by_square.setdefault((si, sk), []).append((i, k))
        buckets[rise] = None
    print("sites spaced out (%.0f s so far)" % (time.time() - started))

    latitude_grid = read_latitude_grid(run_dir / "latitude_longitude_grid.txt")
    latitude_spacing = st.get("latitude_grid_m", 10000)
    sites = []
    for n, (i, k, rise, h) in enumerate(sorted(chosen), 1):
        x, z = i * step, k * step
        lat, lon = latitude_longitude(latitude_grid, latitude_spacing, x, z)
        sites.append({"number": n, "x": x, "z": z, "latitude": lat, "longitude": lon, "height_m": h, "rise_m": rise,
                      "radius_m": SITE_RADIUS_M})

    out = Path(output) if output else MAP_DATA / map_folder / SITES_INDEX
    comparison = compare_with_last(out, sites)
    rules = {"site_radius_m": SITE_RADIUS_M, "max_rise_m": MAX_RISE_M, "max_step_m": MAX_STEP_M,
             "object_margin_m": OBJECT_MARGIN_M, "surfaces_allowed": SURFACES_ALLOWED, "site_spacing_m": SITE_SPACING_M}
    counts = {"tiles": len(tiles), "cells": cells, "pass_2_cells": pass_2_cells, "map_objects": objects,
              "points": points_judged, "candidates": candidates, "sites": len(sites), "rejected": reasons}
    folder, tile_files = write_map_sites(out, info["map"], run_dir.name, rules, counts, sites, tile_m)

    print("summary")
    print("%s: %d tiles, %d cells (1 km), %d flat and dry enough for pass 2; surveyed in %s"
          % (info["map"], len(tiles), cells, pass_2_cells, "%d h %02d min" % (survey_s // 3600, survey_s % 3600 // 60)))
    print("%d points looked at, %d could centre a site, %d sites chosen (%d m apart at least)"
          % (points_judged, candidates, len(sites), SITE_SPACING_M))
    for why, n in sorted(reasons.items(), key=lambda t: -t[1]):
        print("    not a centre, %-36s %9d points" % (why + ":", n))
    if comparison:
        print("against the last sites file (survey %s): %d the same (within %d m), %d new, %d gone"
              % (comparison["run"], comparison["same"], SAME_SITE_M, comparison["new"], comparison["gone"]))
    else:
        print("the map's first sites file")
    print("-> %s and %d tile files in %s (%.0f s)" % (out, tile_files, folder, time.time() - started))


# ── the missions ────────────────────────────────────────────────────

SCRIPT_IN_TRIGGER = re.compile(r"(map_surveys(?:\\)+)([A-Za-z0-9_]+\.lua)")


def mission_running(template_text, script):
    """The template's mission text with its trigger's map_surveys script swapped for
    `script` (both places the editor keeps it: trig and trigrules)."""
    new, n = SCRIPT_IN_TRIGGER.subn(lambda m: m.group(1) + script, template_text)
    if n == 0:
        raise SystemExit("the template's trigger runs no map_surveys script: it needs one trigger "
                         "ONCE → TIME MORE 1 → DO SCRIPT dofile(lfs.writedir() .. \"Scripts\\\\map_surveys\\\\<any>.lua\")")
    return new


def write_miz(template, out, mission_text):
    temp = out.with_suffix(".miz.tmp")
    with zipfile.ZipFile(template) as old, zipfile.ZipFile(temp, "w", zipfile.ZIP_DEFLATED) as new:
        for info in old.infolist():
            data = old.read(info.filename)
            if info.filename == "mission":
                data = mission_text.encode("utf-8")
            new.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED)
    os.replace(temp, out)


def run_missions(map_name, template, force):
    template = Path(template)
    if not template.exists():
        raise SystemExit("no template mission %s" % template)
    with zipfile.ZipFile(template) as z:
        text = z.read("mission").decode("utf-8")
    m = dcslua.loads(text)
    if m.get("theatre") != map_name:
        raise SystemExit("the template %s is on the %s map, not %s" % (template, m.get("theatre"), map_name))
    missions = SAVED_GAMES / "Missions"
    survey = missions / ("%s_spawn_site_survey.miz" % map_name.lower())
    shown = missions / ("%s_spawn_sites_shown.miz" % map_name.lower())
    if survey.exists() and not force:
        print("kept %s (it exists; --force replaces it, and its trigger zones with it)" % survey)
    else:
        write_miz(template, survey, mission_running(text, "survey_spawn_sites.lua"))
        print("wrote %s: add a trigger zone where each test area goes (named as you like), save, fly" % survey)
    write_miz(template, shown, mission_running(text, "show_spawn_sites.lua"))
    print("wrote %s: fly it after running this tool on a survey" % shown)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("what", nargs="?", default="sites", choices=["sites", "map-survey", "make-missions"])
    ap.add_argument("--map", default=DEFAULT_MAP)
    ap.add_argument("--map-folder", help="map-survey: the map's folder under map_data (default: --map in lower case)")
    ap.add_argument("--run", help="map-survey: the survey run's folder name (default: the newest finished one)")
    ap.add_argument("--measurements", help="map-survey: the survey_measurements folder (default: the map's in map_data)")
    ap.add_argument("--output", help="map-survey: the sites index (default: map_data/<map>/spawn_sites_index.lua; the tiles go in spawn_sites/ beside it)")
    ap.add_argument("--template", default=str(SAVED_GAMES / "Missions" / "Afghanistan_survey_1.miz"),
                    help="make-missions: the mission to copy")
    ap.add_argument("--force", action="store_true", help="make-missions: replace the survey mission too")
    ap.add_argument("--surveys", help="sites: the folder of area_*.lua files (default: Saved Games/DCS/map_surveys/<map>)")
    args = ap.parse_args()
    if args.what == "make-missions":
        run_missions(args.map, args.template, args.force)
    elif args.what == "map-survey":
        run_map_survey(args.map_folder or args.map.lower(), args.run, args.measurements, args.output)
    else:
        run_sites(args.map, args.surveys)


if __name__ == "__main__":
    main()
