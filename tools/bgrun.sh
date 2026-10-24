#!/bin/zsh
# Run the game for a test/screenshot WITHOUT stealing focus (macOS: open -g keeps
# it in the background). Waits for it to exit and prints its output.
#   tools/bgrun.sh res://scenes/race.tscn -- --bots=3 --screenshot=/tmp/x.png --shot_at=3
# Pass "" as the scene to start at the main menu. VEG_OFF / NO_THEMES env vars pass through.
cd "$(dirname "$0")/.." || exit 1
log=$(mktemp -t bgrun)
scene="$1"; shift
args=(--path "$PWD" --audio-driver Dummy) # test runs are silent (user request)
[[ -n "$scene" ]] && args+=("$scene")
envs=()
for v in VEG_OFF NO_THEMES VEG_DEBUG FOREST_OFF GRASS_OFF TERRAIN_FLAT BELT_OFF FILL_OFF NO_DRESS NO_SHAPER; do [[ -n "${(P)v}" ]] && envs+=(--env "$v=${(P)v}"); done
LOCK_LANES=gpu
source tools/lock.sh
# New class_name scripts are only known after an import: refresh the global
# class cache when any script is newer than it (cheap when nothing changed).
if [[ -z "$(find scripts -name '*.gd' -newer .godot/global_script_class_cache.cfg 2>/dev/null | head -1)" ]] && [[ -f .godot/global_script_class_cache.cfg ]]; then :; else
	perl -e 'alarm 240; exec @ARGV' godot --headless --path "$PWD" --import >/dev/null 2>&1
	# The import only rewrites the cache when class names change; touch it so
	# the next run doesn't re-import (that cost every run minutes).
	touch .godot/global_script_class_cache.cfg
fi
# Watchdog: a hung run must never hold the lock for long (LIMIT seconds, default 300).
tag="--bgrun-id=$$"
[[ " $* " == *" -- "* ]] || set -- "$@" --
( /bin/sleep ${LIMIT:-300}; pkill -f -- "$tag" && echo "bgrun: killed after ${LIMIT:-300}s" >> "$log" ) &
dog=$!
open -g -W -n -a /Applications/Godot.app "${envs[@]}" --stdout "$log" --stderr "$log" --args "${args[@]}" "$@" "$tag"
kill $dog 2>/dev/null
cat "$log"
rm -f "$log"
