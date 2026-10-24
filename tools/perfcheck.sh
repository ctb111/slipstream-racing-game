#!/bin/zsh
# The 60 fps gate. Runs every track (8 cars, Medium, vsync off, adaptive
# resolution on like a real player) and prints avg / 1%-low fps per case.
# A feature is only done when this passes on a QUIET machine (uptime load < 6).
#   tools/perfcheck.sh                 # all tracks, their default weather
#   tools/perfcheck.sh --weather=2     # extra game args go to every case
#   TRACKS="kiefernring brackenmoor" tools/perfcheck.sh
cd "$(dirname "$0")/.." || exit 1
LOCK_LANES=gpu LOCK_EXCLUSIVE=1 # both gpu slots, taken together once both are free
source tools/lock.sh # hold the gpu for the whole check
out=${TMPDIR:-/tmp}/perfcheck.$$
mkdir -p "$out"
tracks=(${=TRACKS:-kiefernring hochwald valle_club brackenmoor schneekopf kuestenstrasse altstadt valtellina herbstwald capo_rosso alpenpass hafenstadt})
load=$(uptime | sed 's/.*averages*: //' | awk '{print $1}')
echo "load average: $load  (results are only meaningful below ~6)"
printf "%-16s %8s %8s %9s %6s  %s\n" track avg low1% worst_ms scale result
fail=0
for t in $tracks; do
	res=$(tools/bgrun.sh res://scenes/race.tscn --disable-vsync -- --allbots --bots=7 --quality=1 --track=$t \
		--screenshot=$out/$t.png --shot_at=24 "$@" 2>&1)
	avg=$(echo "$res" | sed -n 's/.*avg_fps=\([0-9.]*\).*/\1/p' | tail -1)
	low=$(echo "$res" | sed -n 's/.*low1_fps=\([0-9.]*\).*/\1/p' | tail -1)
	worst=$(echo "$res" | sed -n 's/.*worst_ms=\([0-9.]*\).*/\1/p' | tail -1)
	scale=$(echo "$res" | sed -n 's/.*scale=\([0-9.]*\).*/\1/p' | tail -1 | cut -c1-4)
	errs=$(echo "$res" | grep -c "SCRIPT ERROR")
	verdict=PASS
	if [[ -z "$avg" ]] || (( avg < 60 || low < 45 )); then verdict=FAIL; fail=1; fi
	(( errs > 0 )) && verdict="$verdict ($errs script errors)"
	printf "%-16s %8s %8s %9s %6s  %s\n" $t "${avg:--}" "${low:--}" "${worst:--}" "${scale:--}" "$verdict"
done
echo "screenshots: $out"
exit $fail
