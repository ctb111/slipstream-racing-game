class_name ModeStore
extends RefCounted
## Where game-mode progress lives (championship state, time-trial ghosts).
## Debug / test runs (any command-line user args) use user://test/ so they never
## touch the player's real progress, mirroring Game.save_settings().


static func dir() -> String:
	var d := "user://test/" if not OS.get_cmdline_user_args().is_empty() else "user://"
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	return d


static func save_json(file: String, data: Variant) -> void:
	var f := FileAccess.open(dir() + file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


static func load_json(file: String) -> Variant:
	var path := dir() + file
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func remove(file: String) -> void:
	var path := dir() + file
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Command-line user args as a dictionary (`--k=v` → v, `--flag` → true).
static func args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.trim_prefix("--").split("=", true, 1)
			out[kv[0]] = kv[1]
		elif arg.begins_with("--"):
			out[arg.trim_prefix("--")] = true
	return out
