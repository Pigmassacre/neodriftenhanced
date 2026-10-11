#!/bin/sh
# Build everything the Godot project needs from the ROMs, into data/ (not checked in):
# graphics and tables, the recompiled game program, and the start snapshot.
# Needs neodrift/ (game ROMs), neogeo/ (BIOS), python3 and mame.
set -e
cd "$(dirname "$0")"
python3 build_data.py
python3 recomp/build_code.py
python3 make_start_snapshot.py
