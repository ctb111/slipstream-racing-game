extends Node
## Headless: builds every circuit (or `-- --track=<id>`) and prints per-step build times.
##   godot --headless --path . res://tests/load_profile.tscn

func _ready() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			only = a.trim_prefix("--track=")
	for t in TrackDefs.TRACKS:
		if only != "" and t.id != only:
			continue
		var c := Circuit.new()
		add_child(c)
		var t0 := Time.get_ticks_msec()
		await c.build(t)
		var total := Time.get_ticks_msec() - t0
		var parts := []
		for k in c.load_times:
			parts.append("%s %.0f" % [k, c.load_times[k]])
		print("%-14s %5d ms | %s" % [t.id, total, ", ".join(parts)])
		if OS.get_cmdline_user_args().has("--used"):
			var used := []
			_scan("res://assets", used)
			print("  used %d: %s" % [used.size(), " ".join(used)])
		c.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _scan(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".import") or f.ends_with(".txt"):
			continue
		var p := dir.path_join(f)
		if ResourceLoader.has_cached(p):
			out.append(p.trim_prefix("res://assets/"))
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)
