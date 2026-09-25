"""Parse ME trigger zones out of a survey .miz into kola_f16/data/zones.lua.

    python tools/miz_zones.py "<path to zones .miz>" [--out kola_f16/data/zones.lua] [--report-only]

The survey .miz is only a drawing surface: zones are clearings where ground units
can realistically be placed. They carry no side and no role — the planner decides
both at run time. The real mission .miz never contains these zones; the generated
data file is the only source.

Per zone:
  * name     generated from geometry: ZONE_<BASE>_<brg>_<km*10>, e.g. ZONE_KITT_100_012
             is 1.2 km on bearing 100 from Kittila. BASE codes live in kola_airbases.json.
             On a collision (same base/bearing/100 m ring) later zones get a B, C ... suffix,
             ordered by zoneId, and the report says so. Hand-typed ME names are ignored.
  * zone_id  the ME's internal id — stable while the zone exists, even if moved; use it
             for anything (catalog entries) that must survive a zone being nudged
  * cluster  nearest airbase's cluster from kola_f16/data/clusters.lua, or the ME zone
             property `cluster` if set; the zone inherits that cluster's rolled side
  * x, z     DCS projected metres, x = north, z = east (the .miz calls east `y`);
             circles keep radius, quads keep 4 vertices
lat/lon and nearest-base distance are written as a comment for review; in-sim the plan
derives lat/lon via coord.LOtoLL.

Classes: static facts about each zone, one question each, so later stages pick zones by
class ("large, road nearby") instead of raw numbers. size and airfield_distance come from
the .miz alone; the rest come from DCS terrain measured by flying the zone mission once
(kola_f16/survey/survey_zone_terrain.lua writes Saved Games\\DCS\\kola_zone_terrain.lua,
read here with --terrain; default: the folder above the .miz's Missions folder). A zone
the survey hasn't measured (new, or moved since) gets "unknown" terrain classes and is
listed in the report: fly the zone mission again. Thresholds: CLASS_THRESHOLDS below.
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import dcslua      # noqa: E402
import kola_proj   # noqa: E402

ZONE_TYPES = {0: "circle", 2: "quad"}

TERRAIN_FILE = "kola_zone_terrain.lua"

# Class thresholds (metres unless noted). Tune here and re-run; no need to re-fly the survey.
CLASS_THRESHOLDS = {
    "size_medium_m":       100,    # usable radius >= this: medium
    "size_large_m":        150,    # >= this: large (fits SA-10 / Patriot)
    "at_airfield_km":      5,      # nearest airbase <= this: at_airfield
    "near_airfield_km":    20,     # <= this: near_airfield; else remote
    "ground_flat_m":       3,      # height spread inside the zone <= this: flat
    "ground_uneven_m":     8,      # <= this: uneven; else steep
    "terrain_ring_m":      3000,   # ring the centre height is compared with
    "terrain_high_m":      40,     # centre >= ring mean + this: high_ground
    "terrain_low_m":       40,     # centre <= ring mean - this: low_ground
    "road_nearby_m":       500,    # road within the zone radius: road_in_zone; <= this: road_nearby
    "railway_nearby_m":    1000,
    "waterside_m":         500,    # water on a ring <= this: waterside
    "near_water_m":        2000,   # <= this: near_water; else inland
    "radar_view_m":        15000,  # distance radar view is judged at
    "radar_view_open":     12,     # bearings seen (of 16) >= this: open
    "radar_view_partial":  6,      # >= this: partial; else masked
    "town_buildings":      150,    # buildings (not clutter) within 2 km >= this: town
    "village_buildings":   15,     # >= this: village; else none
    "prepared_margin_m":   100,    # a SAM revetment this far outside the zone still counts
    "moved_m":             25,     # zone this far from where it was surveyed: stale
}

# What each map object type is, by name; first match wins, anything else is a building.
# Sort new names in here as the report shows them (it lists every type it found).
#   sam_revetment     dug-in SAM launcher position (the map's own SAM sites)
#   aircraft_shelter  hardened aircraft shelter
#   clutter           not a building: woodpiles, fences, walls, containers, power lines,
#                     bridges, trailers (CLTR* assumed to be clutter props)
OBJECT_CATEGORIES = [
    ("sam_revetment",    re.compile(r"^SAMREV")),
    ("aircraft_shelter", re.compile(r"(^|_)HAS(_|\d|$)")),
    ("clutter",          re.compile(r"WOODPILE|FENCE|WALL|CONTAINER|PYLON|POWER_|TRANS_LINE|TRANSFORMER"
                                    r"|WOODEN_SUPPORT|TRAILER|BRIDGE|^CLTR|LAMP|POLE|SIGN")),
]

# Terrain classes, in the order they are written; "unknown" until the zone is surveyed.
TERRAIN_CLASSES = ["ground", "terrain", "road_access", "railway_access", "water",
                   "radar_view", "settlement", "prepared_sam_position"]

DEFAULT_OUT = os.path.join(REPO, "kola_f16", "data", "zones.lua")
DEFAULT_CLUSTERS = os.path.join(REPO, "kola_f16", "data", "clusters.lua")
DEFAULT_AIRBASES = os.path.join(HERE, "kola_airbases.json")


def load_airbases(path, clusters_path):
    with open(path) as f:
        bases = json.load(f)["airbases"]
    base_cluster = {}
    if os.path.exists(clusters_path):
        with open(clusters_path, encoding="utf-8") as f:
            clusters = dcslua.loads(f.read())
        for c in dcslua.as_list(clusters):
            for b in dcslua.as_list(c["bases"]):
                base_cluster[b] = c["id"]
    for b in bases:
        b["cluster"] = base_cluster.get(b["name"])
    return bases


def nearest_base(x, z, bases):
    best, best_d = None, float("inf")
    for b in bases:
        d = kola_proj.dist_m(x, z, b["x"], b["y"])
        if d < best_d:
            best, best_d = b, d
    return best, best_d


def zone_properties(z):
    """ME stores properties as { [1] = { key = "...", value = "..." }, ... }."""
    props = {}
    for p in dcslua.as_list(z.get("properties") or {}):
        if isinstance(p, dict) and "key" in p:
            props[str(p["key"]).strip().lower()] = str(p.get("value", "")).strip()
    return props


def parse_zones(mission, bases):
    zones = []
    for raw in dcslua.as_list(mission["triggers"]["zones"]):
        x, z = float(raw["x"]), float(raw["y"])
        ztype = ZONE_TYPES.get(raw.get("type", 0))
        props = zone_properties(raw)

        nb, nd = nearest_base(x, z, bases)
        brg = kola_proj.bearing_deg(nb["x"], nb["y"], x, z)
        lat, lon = kola_proj.to_latlon(x, z)

        entry = {
            "zone_id": int(raw["zoneId"]),
            "me_name": raw["name"],
            "cluster": props.get("cluster") or nb["cluster"],
            "base": nb["name"], "base_code": nb["code"],
            "brg": int(round(brg)) % 360,
            "km": nd / 1000.0,
            "type": ztype, "x": x, "z": z,
            "lat": lat, "lon": lon,
        }
        if ztype == "circle":
            entry["radius"] = float(raw["radius"])
        elif ztype == "quad":
            verts = raw.get("verticies") or raw.get("vertices") or {}
            entry["verts"] = [(float(v["x"]), float(v["y"])) for v in dcslua.as_list(verts)]
        else:
            entry["type"] = "unknown(%s)" % raw.get("type")
        zones.append(entry)

    assign_names(zones)
    zones.sort(key=lambda e: e["name"])
    return zones


def assign_names(zones):
    """ZONE_<BASE>_<brg>_<km*10>; suffix B, C ... on collision, ordered by zone_id."""
    groups = defaultdict(list)
    for e in zones:
        e["stem"] = "ZONE_%s_%03d_%03d" % (e["base_code"], e["brg"], int(round(e["km"] * 10)))
        groups[e["stem"]].append(e)
    for stem, members in groups.items():
        members.sort(key=lambda e: e["zone_id"])
        for i, e in enumerate(members):
            e["name"] = stem if i == 0 else stem + chr(ord("A") + i)
            e["collision"] = len(members) > 1


def load_terrain(path):
    """ZONE_TERRAIN from the zone survey, keyed by ME zone id; None if there is no file."""
    if not path or not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        data = dcslua.loads(f.read())
    return {int(k): v for k, v in data.items()}


def object_category(type_name):
    for category, pattern in OBJECT_CATEGORIES:
        if pattern.search(type_name):
            return category
    return "building"


def object_types(f):
    """The zone's map object types as dicts: name, category, total, near, in_zone,
    nearest_m. A survey from before per-type counts only has { name, total }."""
    out = []
    for t in dcslua.as_list(f["buildings"].get("types") or {}):
        t = dcslua.as_list(t)
        out.append({"name": t[0], "category": object_category(t[0]), "total": t[1],
                    "near": t[2] if len(t) > 2 else None, "in_zone": t[3] if len(t) > 3 else None,
                    "nearest_m": t[4] if len(t) > 4 else None})
    return out


def usable_radius(z):
    """A circle's radius, or the distance from a quad's centre to its nearest edge."""
    if z["type"] != "quad":
        return z.get("radius", 0.0)
    vs, best = z["verts"], float("inf")
    for i in range(len(vs)):
        (ax, az), (bx, bz) = vs[i], vs[(i + 1) % len(vs)]
        vx, vz, wx, wz = bx - ax, bz - az, z["x"] - ax, z["z"] - az
        l2 = vx * vx + vz * vz
        t = max(0.0, min(1.0, (wx * vx + wz * vz) / l2)) if l2 > 0 else 0.0
        best = min(best, ((wx - t * vx) ** 2 + (wz - t * vz) ** 2) ** 0.5)
    return best if best < float("inf") else 0.0


def classify(z, terrain):
    """Sets z["classes"] (and z["measured"] once surveyed). Returns why the terrain classes
    are unknown, or None."""
    T = CLASS_THRESHOLDS
    radius = usable_radius(z)
    c = {
        "size": ("large" if radius >= T["size_large_m"]
                 else "medium" if radius >= T["size_medium_m"] else "small"),
        "airfield_distance": ("at_airfield" if z["km"] <= T["at_airfield_km"]
                              else "near_airfield" if z["km"] <= T["near_airfield_km"] else "remote"),
    }
    z["classes"] = c

    f = terrain.get(z["zone_id"]) if terrain is not None else None
    if terrain is None:
        why = "no terrain file"
    elif f is None:
        why = "not surveyed"
    else:
        moved = kola_proj.dist_m(z["x"], z["z"], f["x"], f["z"])
        why = "moved %.0f m since the survey" % moved if moved > T["moved_m"] else None
    if why:
        for k in TERRAIN_CLASSES:
            c[k] = "unknown"
        c["surveyed"] = False
        return why

    rings = dcslua.as_list(f["rings"])
    spread = f["inside"]["height_max_m"] - f["inside"]["height_min_m"]
    c["ground"] = ("flat" if spread <= T["ground_flat_m"]
                   else "uneven" if spread <= T["ground_uneven_m"] else "steep")

    ring = next((r for r in rings if r["distance_m"] == T["terrain_ring_m"]), None)
    rise = f["height_m"] - ring["height_mean_m"] if ring else None
    c["terrain"] = ("unknown" if rise is None else "high_ground" if rise >= T["terrain_high_m"]
                    else "low_ground" if rise <= -T["terrain_low_m"] else "level")

    road = f.get("road_m")
    c["road_access"] = ("no_road" if road is None else "road_in_zone" if road <= radius
                        else "road_nearby" if road <= T["road_nearby_m"] else "no_road")
    rail = f.get("railway_m")
    c["railway_access"] = ("railway_nearby" if rail is not None and rail <= T["railway_nearby_m"]
                           else "no_railway")

    wet = [r["distance_m"] for r in rings if r["water_points"] > 0]
    water = min(wet) if wet else None
    c["water"] = ("waterside" if water is not None and water <= T["waterside_m"]
                  else "near_water" if water is not None and water <= T["near_water_m"] else "inland")

    view = next((v for v in dcslua.as_list(f["radar_view"]) if v["distance_m"] == T["radar_view_m"]), None)
    seen = view["bearings_seen"] if view else None
    c["radar_view"] = ("unknown" if seen is None else "open" if seen >= T["radar_view_open"]
                       else "partial" if seen >= T["radar_view_partial"] else "masked")

    types = object_types(f)
    z["object_types"] = types
    buildings = sum(t["total"] for t in types if t["category"] == "building")
    c["settlement"] = ("town" if buildings >= T["town_buildings"]
                       else "village" if buildings >= T["village_buildings"] else "none")

    # Is it one of the map's own prepared SAM positions (dug-in launcher revetments)?
    # "unknown" for a survey without per-type distances.
    reach = radius + T["prepared_margin_m"]
    if any(t["nearest_m"] is None for t in types):
        c["prepared_sam_position"] = "unknown"
    elif any(t["category"] == "sam_revetment" and t["nearest_m"] <= reach for t in types):
        c["prepared_sam_position"] = "revetments"
    else:
        c["prepared_sam_position"] = "none"
    c["surveyed"] = True

    surfaces = f["inside"].get("surfaces") or {}
    z["measured"] = {
        "height_m": f["height_m"], "rise_m": rise, "spread_m": spread,
        "road_m": road, "railway_m": rail, "water_m": water,
        "radar_bearings_seen": seen, "buildings": buildings,
        "buildings_in_zone": sum(t["in_zone"] or 0 for t in types if t["category"] == "building"),
        "sam_revetments_in_zone": sum(t["in_zone"] or 0 for t in types if t["category"] == "sam_revetment"),
        "aircraft_shelters_in_zone": sum(t["in_zone"] or 0 for t in types if t["category"] == "aircraft_shelter"),
        "water_points_in_zone": surfaces.get("water", 0) + surfaces.get("shallow_water", 0),
    }
    return None


def report_object_types(zones, top=40):
    """Every map object type the survey found, by category, so OBJECT_CATEGORIES can be
    checked: the most common buildings should be houses / industry, not props."""
    totals, seen_in = defaultdict(int), defaultdict(int)
    for z in zones:
        for t in z.get("object_types", []):
            totals[t["name"]] += t["total"]
            seen_in[t["name"]] += 1
    if not totals:
        return
    by_category = defaultdict(list)
    for name in totals:
        by_category[object_category(name)].append(name)
    print("\nmap object types within 2 km of the zones (overlapping zones count twice):")
    for category in ("building", "clutter", "sam_revetment", "aircraft_shelter"):
        names = sorted(by_category.get(category, []), key=lambda n: -totals[n])
        print("  %s: %d types, %d objects%s" % (category, len(names), sum(totals[n] for n in names),
                                                "  (top %d)" % top if len(names) > top else ""))
        for n in names[:top]:
            print("    %6d  %-28s in %d zone(s)" % (totals[n], n, seen_in[n]))


def report_classes(zones, unknown):
    cols = ["size", "airfield_distance"] + TERRAIN_CLASSES
    print("\n%-22s %s" % ("name", " ".join("%-14s" % k[:14] for k in cols)))
    print("-" * (23 + 15 * len(cols)))
    for z in zones:
        print("%-22s %s" % (z["name"], " ".join("%-14s" % z["classes"][k] for k in cols)))

    print("\nclass counts:")
    for k in cols:
        counts = defaultdict(int)
        for z in zones:
            counts[z["classes"][k]] += 1
        print("  %-18s %s" % (k, ", ".join("%s %d" % kv for kv in sorted(counts.items()))))

    problems = []
    for z in zones:
        m = z.get("measured") or {}
        if m.get("water_points_in_zone"):
            problems.append((z["name"], "%d of 25 points inside the zone are water" % m["water_points_in_zone"]))
        if m.get("buildings_in_zone"):
            problems.append((z["name"], "%d map building(s) inside the zone" % m["buildings_in_zone"]))
    if problems:
        print("\ncheck these zones in the ME:")
        for name, msg in problems:
            print("  %-22s %s" % (name, msg))

    prepared = [z for z in zones if z["classes"].get("prepared_sam_position") == "revetments"]
    if prepared:
        print("\nprepared SAM positions (map's own SAM revetments in or within %d m of the zone):"
              % CLASS_THRESHOLDS["prepared_margin_m"])
        for z in prepared:
            m = z["measured"]
            print("  %-22s %d SAM revetment(s) inside%s" % (
                z["name"], m["sam_revetments_in_zone"],
                ", %d aircraft shelter(s) inside" % m["aircraft_shelters_in_zone"]
                if m["aircraft_shelters_in_zone"] else ""))

    report_object_types(zones)
    if unknown:
        print("\n%d zone(s) with unknown terrain classes — fly the zone mission again:" % len(unknown))
        for name, why in unknown:
            print("  %-22s %s" % (name, why))


def report(zones):
    print("%-22s %7s  %-24s %-14s %-7s %8s  %s" % (
        "name", "zoneId", "ME name", "cluster", "type", "size m", "position"))
    print("-" * 118)
    for z in zones:
        size = "r=%.0f" % z["radius"] if z["type"] == "circle" else "%d verts" % len(z.get("verts", []))
        flag = "   <-- name collision" if z.get("collision") else ""
        print("%-22s %7d  %-24s %-14s %-7s %8s  %s%s" % (
            z["name"], z["zone_id"], z["me_name"][:24], z["cluster"] or "-", z["type"], size,
            kola_proj.fmt_dms(z["lat"], z["lon"]), flag))


def emit_lua(zones, src_name):
    lines = [
        "-- Ground zones parsed from %s by tools/miz_zones.py — do not hand-edit;" % src_name,
        "-- redraw in the survey .miz and re-run the tool. Plain data, no logic.",
        "--",
        "-- A zone is a clearing where ground units can realistically be placed. No side,",
        "-- no role: the planner assigns both at run time.",
        "--",
        "--   name     ZONE_<BASE>_<brg>_<km*10> from the nearest airbase (suffix letter on collision)",
        "--   zone_id  ME internal id — stable while the zone exists; key catalog entries on this",
        "--   cluster  nearest base's cluster (or ME property `cluster`); zone inherits its rolled side",
        "--   base/brg/km  nearest airbase, bearing from it, distance — for briefs and logs",
        "--   x, z     DCS projected metres (x = north, z = east); lat/lon derived in-sim",
        "--   type     \"circle\" (radius) | \"quad\" (verts = { {x, z}, ... })",
        "--",
        "-- Classes, one question each (thresholds: CLASS_THRESHOLDS in tools/miz_zones.py):",
        "--   size               What fits here?                    small / medium / large",
        "--   airfield_distance  Is it part of an airfield?         at_airfield / near_airfield / remote",
        "--   ground             How level is the zone itself?      flat / uneven / steep",
        "--   terrain            Is it high or low ground?          high_ground / level / low_ground",
        "--   road_access        Can trucks reach it?               road_in_zone / road_nearby / no_road",
        "--   railway_access     Is there a railway close by?       railway_nearby / no_railway",
        "--   water              How close is open water?           waterside / near_water / inland",
        "--   radar_view         Would a radar here see low flyers? open / partial / masked",
        "--   settlement         Is it in or near a built-up place? town / village / none",
        "--                      (buildings within 2 km; woodpiles, fences, pylons etc. don't count)",
        "--   prepared_sam_position  Is it one of the map's own dug-in SAM positions?",
        "--                      revetments / none (SAM revetments in or just outside the zone)",
        "--   surveyed           false: the terrain classes are \"unknown\" (zone not measured yet)",
        "-- measured: the survey numbers behind the classes, in metres: centre height, rise above",
        "-- the 3 km ring, height spread inside, nearest road / railway / water, radar bearings",
        "-- seen of 16 at 15 km, buildings within 2 km and inside the zone, SAM revetments and",
        "-- aircraft shelters inside the zone, water points inside (of 25).",
        "",
        "ZONES = {",
    ]
    for z in zones:
        lines.append("    -- %s" % kola_proj.fmt_dms(z["lat"], z["lon"]))
        lines.append("    {")
        lines.append("        name    = %s," % dcslua.dumps(z["name"]))
        lines.append("        zone_id = %d," % z["zone_id"])
        lines.append("        cluster = %s," % dcslua.dumps(z["cluster"]))
        lines.append("        base    = %s," % dcslua.dumps(z["base"]))
        lines.append("        brg     = %d," % z["brg"])
        lines.append("        km      = %.1f," % z["km"])
        lines.append("        type    = %s," % dcslua.dumps(z["type"]))
        lines.append("        x       = %.3f," % z["x"])
        lines.append("        z       = %.3f," % z["z"])
        if z["type"] == "circle":
            lines.append("        radius  = %.1f," % z["radius"])
        elif z["type"] == "quad":
            vs = ", ".join("{ %.3f, %.3f }" % v for v in z["verts"])
            lines.append("        verts   = { %s }," % vs)
        for k in ["size", "airfield_distance"] + TERRAIN_CLASSES:
            lines.append("        %-17s = %s," % (k, dcslua.dumps(z["classes"][k])))
        lines.append("        %-17s = %s," % ("surveyed", "true" if z["classes"]["surveyed"] else "false"))
        m = z.get("measured")
        if m:
            parts = ["%s = %d" % (k, round(v)) for k, v in m.items() if v is not None]
            lines.append("        measured          = { %s }," % ", ".join(parts))
        lines.append("    },")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")   # degree signs in the report
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("miz")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--clusters", default=DEFAULT_CLUSTERS)
    ap.add_argument("--airbases", default=DEFAULT_AIRBASES)
    ap.add_argument("--terrain", help="zone survey output (default: %s in the folder above the "
                                      ".miz's Missions folder)" % TERRAIN_FILE)
    ap.add_argument("--report-only", action="store_true", help="print the table, don't write zones.lua")
    args = ap.parse_args()

    mission = dcslua.load_miz(args.miz)
    if mission.get("theatre") != "Kola":
        print("warning: theatre is %r, not Kola — projection will be wrong" % mission.get("theatre"))

    bases = load_airbases(args.airbases, args.clusters)
    zones = parse_zones(mission, bases)
    report(zones)

    terrain_path = args.terrain or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(args.miz))), TERRAIN_FILE)
    terrain = load_terrain(terrain_path)
    if terrain is None:
        print("\nwarning: no zone terrain at %s: terrain classes will be \"unknown\"."
              "\n  Fly the zone mission once (kola_f16/survey/survey_zone_terrain.lua), then re-run." % terrain_path)
    else:
        print("\nzone terrain: %s (%d zones)" % (terrain_path, len(terrain)))
        if os.path.getmtime(args.miz) > os.path.getmtime(terrain_path):
            print("warning: the .miz was saved after the survey ran; fly it again if zones changed")
    unknown = []
    for z in zones:
        why = classify(z, terrain)
        if why:
            unknown.append((z["name"], why))
    report_classes(zones, unknown)

    collisions = sorted({z["stem"] for z in zones if z.get("collision")})
    if collisions:
        print("\n%d name collision(s) resolved with suffix letters: %s" % (len(collisions), ", ".join(collisions)))

    if args.report_only:
        return
    text = emit_lua(zones, os.path.basename(args.miz))
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(text)
    print("\nwrote %d zones -> %s" % (len(zones), os.path.relpath(args.out, REPO)))


if __name__ == "__main__":
    main()
