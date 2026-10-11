#!/bin/sh
# Run a harness job headless: Tools/mame/run.sh <job.lua> [extra mame args]
# MAME's own state (cfg, nvram) is kept under data/mame so runs are reproducible.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
JOB="$(realpath "$1")"; shift
STATE="$ROOT/data/mame"
mkdir -p "$STATE"
cd "$STATE"
# start every run from the same cold state
rm -rf nvram
NEODRIFT_JOB="$JOB" exec mame neodrift \
  -rompath "$ROOT;$ROOT/neodrift" \
  -video none -sound none -nothrottle \
  -cfg_directory "$STATE/cfg" -nvram_directory "$STATE/nvram" \
  -snapshot_directory "$STATE/snap" \
  -autoboot_script "$ROOT/Tools/mame/harness.lua" "$@"
