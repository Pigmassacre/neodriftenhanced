#!/bin/sh
# Shortcut for Tools/release.py; takes the same arguments.
exec python3 "$(dirname "$0")/release.py" "$@"
