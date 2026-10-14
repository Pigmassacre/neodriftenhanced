#!/bin/sh
# Shortcut for Tools/build.py; takes the same arguments.
exec python3 "$(dirname "$0")/build.py" "$@"
