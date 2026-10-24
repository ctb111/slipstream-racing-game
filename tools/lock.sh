# Sourced by the run wrappers. Fair (first-come-first-served) queues:
#   gpu lane - windowed runs. TWO slots, so two screenshot runs go side by side.
#              LOCK_EXCLUSIVE=1 (perfcheck) waits until it is first in line AND
#              both slots are free, then takes both at once: clean fps numbers,
#              and it never sits on one slot waiting for the other.
#   cpu lane - headless runs, one slot.
# LOCK_LANES = "gpu" or "cpu" (default "gpu"). BGRUN_LOCKED=1: caller holds it.
if [[ -z "$BGRUN_LOCKED" ]]; then
	_held=()
	_tickets=()
	_cleanup() { rm -rf "${_held[@]}" "${_tickets[@]}"; }
	trap _cleanup EXIT
	trap '_cleanup; exit 130' INT TERM HUP # really stop when told to
	lane=${LOCK_LANES:-gpu}
	lane=${lane%% *}
	q=/tmp/slipstream_${lane}.queue
	mkdir -p "$q"
	if [[ $lane == gpu ]]; then
		slots=(/tmp/slipstream_bgrun.lock /tmp/slipstream_bgrun2.lock)
	else
		slots=(/tmp/slipstream_cpu.lock)
	fi
	ticket="$q/$(perl -MTime::HiRes=time -e 'printf "%.6f", time')_$$"
	: > "$ticket"
	_tickets+=("$ticket")
	waited=0
	while true; do
		for t in "$q"/*(N); do kill -0 "${t##*_}" 2>/dev/null || rm -f "$t"; done
		for s in $slots; do # free slots whose owner died
			o=$(cat "$s/pid" 2>/dev/null)
			[[ -n "$o" ]] && ! kill -0 "$o" 2>/dev/null && rm -rf "$s"
		done
		first=$(ls "$q" 2>/dev/null | sort | head -1)
		if [[ "$q/$first" == "$ticket" ]]; then
			if [[ -n "$LOCK_EXCLUSIVE" ]]; then
				free=1
				for s in $slots; do [[ -d "$s" ]] && free=0; done
				if (( free )); then
					for s in $slots; do mkdir "$s" 2>/dev/null && echo $$ > "$s/pid" && _held+=("$s"); done
					(( ${#_held} == ${#slots} )) && break
					rm -rf "${_held[@]}"; _held=()
				fi
			else
				for s in $slots; do
					if mkdir "$s" 2>/dev/null; then echo $$ > "$s/pid"; _held+=("$s"); break; fi
				done
				(( ${#_held} )) && break
			fi
		fi
		(( waited++ == 0 )) && echo "waiting for the $lane lane ($(ls "$q" | wc -l | tr -d ' ') in queue)..." >&2
		/bin/sleep 1
	done
	rm -f "$ticket"
	export BGRUN_LOCKED=1
	# The gpu lane also waits while a real game WINDOW is open (the user
	# playing): only actual Godot processes, never shells that mention it.
	if [[ $lane == gpu ]]; then
		while true; do
			busy=0
			for pid in $(pgrep -x Godot) $(pgrep -x godot); do
				ps -p $pid -o args= | grep -q -- "--headless" && continue
				ps -p $pid -o args= | grep -q -- "--screenshot\|--gx_test\|--dress_shots\|--fxshots\|--uishot\|_shots\|tree_gallery\|preview" && continue
				busy=1
			done
			(( busy )) || break
			(( waited++ == 0 )) && echo "waiting for the open game window to close..." >&2
			/bin/sleep 2
		done
	fi
fi
