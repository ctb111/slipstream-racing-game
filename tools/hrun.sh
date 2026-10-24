#!/bin/zsh
# Headless Godot run through the shared lock, killed after $LIMIT s (default 300).
#   tools/hrun.sh res://scenes/race.tscn --quit-after 2000 -- --allbots --track=altstadt
cd "$(dirname "$0")/.." || exit 1
LOCK_LANES=cpu
source tools/lock.sh
# New class_name scripts are only known after an import: refresh the global
# class cache when any script is newer than it (cheap when nothing changed).
if [[ -z "$(find scripts -name '*.gd' -newer .godot/global_script_class_cache.cfg 2>/dev/null | head -1)" ]] && [[ -f .godot/global_script_class_cache.cfg ]]; then :; else
	perl -e 'alarm 240; exec @ARGV' godot --headless --path "$PWD" --import >/dev/null 2>&1
	# The import only rewrites the cache when class names change; touch it so
	# the next run doesn't re-import (that cost every run minutes).
	touch .godot/global_script_class_cache.cfg
fi
perl -e 'alarm shift; exec @ARGV' ${LIMIT:-300} godot --headless --path "$PWD" "$@"
