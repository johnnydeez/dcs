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
"""

import argparse
import json
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import dcslua      # noqa: E402
import kola_proj   # noqa: E402

ZONE_TYPES = {0: "circle", 2: "quad"}

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
    ap.add_argument("--report-only", action="store_true", help="print the table, don't write zones.lua")
    args = ap.parse_args()

    mission = dcslua.load_miz(args.miz)
    if mission.get("theatre") != "Kola":
        print("warning: theatre is %r, not Kola — projection will be wrong" % mission.get("theatre"))

    bases = load_airbases(args.airbases, args.clusters)
    zones = parse_zones(mission, bases)
    report(zones)

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
