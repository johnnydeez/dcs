"""
Comments out the sanitize block in DCS MissionScripting.lua so that lfs, io,
os, require, etc. are available to mission scripts.

Must be run as Administrator (the file lives in Program Files).
Safe to run multiple times -- skips lines already commented out.
Compatible with Python 2 and Python 3.

Usage:
  1. Open a terminal as Administrator (right-click -> "Run as administrator")
  2. Run: python desanitize_dcs.py
  3. Fully restart DCS (not just the mission)

Re-run this script after every DCS update -- updates reset MissionScripting.lua.
"""

from __future__ import print_function
import sys
import os
import io
import shutil
from datetime import datetime

TARGET = r"C:\Program Files\Eagle Dynamics\DCS World\Scripts\MissionScripting.lua"

SANITIZE_LINES = [
    "sanitizeModule('os')",
    "sanitizeModule('io')",
    "sanitizeModule('lfs')",
    "_G['require'] = nil",
    "_G['loadlib'] = nil",
    "_G['package'] = nil",
]

def should_comment(line):
    stripped = line.strip()
    if stripped.startswith("--"):
        return False  # already commented
    return any(s in stripped for s in SANITIZE_LINES)

def main():
    if not os.path.exists(TARGET):
        print("ERROR: File not found: {}".format(TARGET))
        print("Check your DCS install path.")
        sys.exit(1)

    with io.open(TARGET, encoding="utf-8") as f:
        lines = f.readlines()

    changed = 0
    new_lines = []
    for line in lines:
        if should_comment(line):
            indent = len(line) - len(line.lstrip())
            new_lines.append(line[:indent] + "--" + line[indent:])
            changed += 1
        else:
            new_lines.append(line)

    if changed == 0:
        print("Already de-sanitized -- no changes needed.")
        return

    backup = TARGET + ".bak_" + datetime.now().strftime("%Y%m%d_%H%M%S")
    shutil.copy2(TARGET, backup)
    print("Backup saved: {}".format(os.path.basename(backup)))

    try:
        with io.open(TARGET, "w", encoding="utf-8") as f:
            f.writelines(new_lines)
    except IOError:
        print("ERROR: Permission denied. Run this script as Administrator.")
        sys.exit(1)

    print("Done -- commented out {} line(s). Restart DCS for changes to take effect.".format(changed))

if __name__ == "__main__":
    main()
