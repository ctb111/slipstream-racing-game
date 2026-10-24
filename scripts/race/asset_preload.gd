class_name AssetPreload
extends RefCounted
## While the loading screen is up, decodes the big shared assets (PBR texture
## sets, people meshes, vegetation atlases, the grid's car models) on worker
## threads with ResourceLoader.load_threaded_request. The circuit build on the
## main thread then finds most of them already in the cache (a load() of a
## path that is still loading just waits for that one), instead of decoding
## every JPEG itself one after the other.
##
## `-- --nopreload` turns it off (for A/B load timing).

const DIRS := ["res://assets/textures", "res://assets/road", "res://assets/materials",
	"res://assets/vegetation", "res://assets/people/meshes", "res://assets/themes"]
const FILES := ["res://assets/people/people_atlas.png"]
const EXT := ["jpg", "png", "res", "tres", "glb", "webp"]

static var _requested: Array[String] = []


static func start(_track: Dictionary, car_models: Array) -> void:
	if OS.get_cmdline_user_args().has("--nopreload"):
		return
	var paths: Array[String] = []
	# Cars first: they are needed last but are the biggest single files.
	for id in car_models:
		var p: String = CarCatalog.get_car(id).get("path", "")
		if p != "":
			paths.append(p)
	paths.append_array(FILES)
	for d in DIRS:
		_collect(d, paths)
	for p in paths:
		if ResourceLoader.has_cached(p) or _requested.has(p) or not ResourceLoader.exists(p):
			continue
		if ResourceLoader.load_threaded_request(p, "", false) == OK:
			_requested.append(p)


## Hands finished loads back (the cache keeps what the circuit actually uses;
## anything it didn't use is dropped here).
static func finish() -> void:
	for p in _requested:
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			ResourceLoader.load_threaded_get(p) # waits for stragglers (rare), then releases the request
	_requested.clear()


static func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		var ext := f.get_extension().to_lower()
		if ext == "import" or ext == "remap":
			f = f.trim_suffix("." + ext)
			ext = f.get_extension().to_lower()
		if EXT.has(ext):
			var p := dir.path_join(f)
			if not out.has(p):
				out.append(p)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)
