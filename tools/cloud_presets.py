"""Extract DCS's cloud presets into kola_f16/data/cloud_presets.lua.

    python tools/cloud_presets.py [--dcs "C:\\Program Files\\Eagle Dynamics\\DCS World"] [--out ...]

Source: <DCS>\\Config\\Effects\\clouds.lua — the file the Mission Editor's preset
picker reads. A mission using preset weather stores only `clouds.preset = "PresetN"`
and `clouds.base`; everything else about the sky (coverage, layers, precipitation)
lives here. The planner needs it to turn a preset name into ceiling/coverage/precip.

Per preset:
  * id          the key the .miz stores ("Preset10", "RainyPreset1")
  * name        the ME's short label ("Scattered 5")
  * metar       ED's own METAR-style description ("SCT/BKN 18/20 FEW36/38 FEW 40")
  * coverage    lowest-layer coverage word taken from that METAR (FEW/SCT/BKN/OVC or
                a slash pair like "SCT/BKN") — the planner's ceiling coverage
  * precip      precipitationPower; -1 = none, otherwise 0..1 (rain presets)
  * base_min/max  allowed cloud base range in metres (ME slider limits)
  * layers      { alt_min, alt_max, coverage, density } per cloud layer, as defined in the
                file. The in-mission base shifts these; the reference base is not stated
                in the file, so treat layer altitudes as relative, not absolute.

Regex-driven: the file uses _() localisation calls and string concatenation, which the
plain table reader in dcslua.py doesn't evaluate. Stdlib only.
"""

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

DEFAULT_DCS = r"C:\Program Files\Eagle Dynamics\DCS World"
DEFAULT_OUT = os.path.join(REPO, "kola_f16", "data", "cloud_presets.lua")

PRESET_HEAD = re.compile(r"^\t\t(\w+)\s*=\s*$")
PRESET_END = re.compile(r"^\t\t\},?\s*$")
LAYER_HEAD = re.compile(r"^\t\t\t\t\{\s*$")
LAYER_END = re.compile(r"^\t\t\t\t\},?\s*$")
KV = re.compile(r"^\s*(\w+)\s*=\s*(.+?),?\s*$")
METAR = re.compile(r"METAR:\s*(.+?)\s*'\)")
COVER_WORD = re.compile(r"\b((?:FEW|SCT|BKN|OVC)(?:/(?:FEW|SCT|BKN|OVC))?)\b")


def num(s):
    try:
        return float(s)
    except ValueError:
        return None


def parse(text):
    presets = []
    cur = None
    layer = None
    for line in text.splitlines():
        if cur is None:
            m = PRESET_HEAD.match(line)
            if m:
                cur = {"id": m.group(1), "layers": []}
            continue

        if layer is not None:
            if LAYER_END.match(line):
                cur["layers"].append(layer)
                layer = None
            else:
                m = KV.match(line)
                if m and m.group(1) in ("altitudeMin", "altitudeMax", "coverage", "density"):
                    layer[m.group(1)] = num(m.group(2))
            continue

        if LAYER_HEAD.match(line):
            layer = {}
            continue

        if PRESET_END.match(line):
            if cur.get("visibleInGUI"):
                if not cur.get("coverage"):
                    cur["coverage"] = coverage_from_layers(cur["layers"])
                    cur["coverage_guessed"] = True
                presets.append(cur)
            cur = None
            continue

        m = KV.match(line)
        if not m:
            continue
        key, val = m.group(1), m.group(2)
        if key == "visibleInGUI":
            cur["visibleInGUI"] = val.strip() == "true"
        elif key == "readableName":
            mm = METAR.search(val)
            cur["metar"] = mm.group(1).strip() if mm else ""
            cw = COVER_WORD.search(cur["metar"])
            cur["coverage"] = cw.group(1) if cw else None
        elif key == "readableNameShort":
            mm = re.search(r"_\('(.+?)'\)", val)
            cur["name"] = mm.group(1) if mm else val.strip("'\"")
        elif key == "precipitationPower":
            cur["precip"] = num(val)
        elif key == "presetAltMin":
            cur["base_min"] = num(val)
        elif key == "presetAltMax":
            cur["base_max"] = num(val)
    return presets


# Fallback for a preset whose METAR text is missing ("--"): coverage word from the
# lowest layer's numeric coverage. Thresholds fitted to the presets that do have
# METAR text (FEW/SCT ~0.36-0.42, SCT ~0.44-0.47, SCT/BKN ~0.48-0.52, BKN ~0.52-0.65,
# BKN/OVC ~0.55-0.75, OVC 0.61+) — coarse, but keeps the planner off "SKC" for a rain preset.
def coverage_from_layers(layers):
    if not layers:
        return "SKC"
    low = min(layers, key=lambda l: l.get("altitudeMin", 0))
    c = low.get("coverage") or 0
    if c < 0.1:
        return "SKC"
    if c < 0.43:
        return "FEW/SCT"
    if c < 0.48:
        return "SCT"
    if c < 0.53:
        return "SCT/BKN"
    if c < 0.65:
        return "BKN"
    if c < 0.75:
        return "BKN/OVC"
    return "OVC"


def preset_sort_key(p):
    m = re.match(r"([A-Za-z]+)(\d+)", p["id"])
    return (m.group(1), int(m.group(2))) if m else (p["id"], 0)


def fmt(v):
    if isinstance(v, float):
        return ("%.3f" % v).rstrip("0").rstrip(".") if v != int(v) else "%d" % int(v)
    return str(v)


def write_lua(presets, out_path, src_path):
    lines = [
        "-- DCS cloud presets extracted from %s by tools/cloud_presets.py — do not hand-edit;" % src_path.replace("\\", "\\\\"),
        "-- re-run the tool after a DCS update. Plain data, no logic.",
        "--",
        "-- A mission with preset weather stores only clouds.preset + clouds.base; this table",
        "-- turns the preset id into coverage / precipitation for the planner (§1.11).",
        "--   coverage   lowest-layer coverage word from ED's METAR text (FEW/SCT/BKN/OVC, or a pair)",
        "--   precip     precipitationPower: -1 = none, 0..1 = rain intensity",
        "--   base_min/max  allowed cloud base in metres",
        "--   layers     { alt_min, alt_max, coverage, density } — altitudes are relative to an",
        "--              unstated reference base; the in-mission base shifts them",
        "",
        "CLOUD_PRESETS = {",
    ]
    for p in sorted(presets, key=preset_sort_key):
        lines.append("    %s = {" % p["id"])
        lines.append('        id       = "%s",' % p["id"])
        lines.append('        name     = "%s",' % p.get("name", ""))
        lines.append('        metar    = "%s",' % p.get("metar", "").replace('"', '\\"'))
        lines.append('        coverage = "%s",%s' % (p.get("coverage", "SKC"),
                     "  -- no METAR text in source; from layer coverage" if p.get("coverage_guessed") else ""))
        lines.append("        precip   = %s," % fmt(p.get("precip", -1)))
        lines.append("        base_min = %s," % fmt(p.get("base_min", 0)))
        lines.append("        base_max = %s," % fmt(p.get("base_max", 0)))
        lines.append("        layers   = {")
        for l in p["layers"]:
            lines.append("            { alt_min = %s, alt_max = %s, coverage = %s, density = %s }," % (
                fmt(l.get("altitudeMin", 0)), fmt(l.get("altitudeMax", 0)),
                fmt(l.get("coverage", 0)), fmt(l.get("density", 0))))
        lines.append("        },")
        lines.append("    },")
    lines.append("}")
    lines.append("")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dcs", default=DEFAULT_DCS, help="DCS World install directory")
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    src = os.path.join(args.dcs, "Config", "Effects", "clouds.lua")
    if not os.path.exists(src):
        sys.exit("not found: %s" % src)
    with open(src, encoding="utf-8", errors="replace") as f:
        presets = parse(f.read())
    if not presets:
        sys.exit("no presets parsed from %s — file layout changed?" % src)

    write_lua(presets, args.out, src)
    print("%d presets -> %s" % (len(presets), args.out))
    for p in sorted(presets, key=preset_sort_key):
        print("  %-13s %-22s %-8s precip=%-4s base %4s-%4s  %d layers  %s" % (
            p["id"], p.get("name", ""), p.get("coverage"), fmt(p.get("precip", -1)),
            fmt(p.get("base_min", 0)), fmt(p.get("base_max", 0)), len(p["layers"]), p.get("metar", "")))


if __name__ == "__main__":
    main()
