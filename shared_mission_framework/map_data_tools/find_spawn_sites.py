"""Find spawn sites in the spawn site survey's measurements, and make the missions that run
the survey and show what it found (missions/afghanistan_campaign/mission_design.md, *Map
data: the site survey*; John, 2026-10-07).

A spawn site is one kind of place: a clear, flat, dry disc where anything fits (a group of
ground units, a large SAM site, a target). The survey (map_surveys/survey_spawn_sites.lua,
in DCS) measures; this decides, so the rules below can be tuned without flying it again.

    python find_spawn_sites.py                  every surveyed area of the map: sites
    python find_spawn_sites.py make-missions    the survey and viewer missions

Reads  Saved Games/DCS/map_surveys/<map>/area_<name>.lua  (SURVEYED_AREA, one per area)
Writes Saved Games/DCS/map_surveys/<map>/spawn_sites_<name>.lua  (SPAWN_SITES), which the
       viewer mission (map_surveys/show_spawn_sites.lua) draws on the F10 map.

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
import zipfile
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
    ap.add_argument("what", nargs="?", default="sites", choices=["sites", "make-missions"])
    ap.add_argument("--map", default=DEFAULT_MAP)
    ap.add_argument("--template", default=str(SAVED_GAMES / "Missions" / "Afghanistan_survey_1.miz"),
                    help="make-missions: the mission to copy")
    ap.add_argument("--force", action="store_true", help="make-missions: replace the survey mission too")
    ap.add_argument("--surveys", help="sites: the folder of area_*.lua files (default: Saved Games/DCS/map_surveys/<map>)")
    args = ap.parse_args()
    if args.what == "make-missions":
        run_missions(args.map, args.template, args.force)
    else:
        run_sites(args.map, args.surveys)


if __name__ == "__main__":
    main()
