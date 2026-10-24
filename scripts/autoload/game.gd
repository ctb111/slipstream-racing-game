extends Node
## Autoload "Game": session settings shared by the menu, the race and the
## network layer. Player preferences persist in user://settings.cfg.

enum Mode { SINGLE, HOST, CLIENT }
const DIFFICULTY_NAMES := ["Easy", "Medium", "Hard"]
const SETTINGS_PATH := "user://settings.cfg"

var mode := Mode.SINGLE
var player_name := "Driver"
var track_id := "kiefernring"
var laps := 3
var bots := 5
var difficulty := 1
var assists := true
## Graphics quality 0 Low .. 3 Ultra (-1 = pick for this machine on first run).
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]
var quality := -1
## -1 = the track's own weather, otherwise Weather.Kind (menu / lobby choice).
var weather_override := -1
## Changeable weather (conditions 7/8): the host's WeatherCycle timeline for
## this race ({} = roll one when the circuit is built).
var weather_timeline := {}
## Player's paint: index into CarPalette.COLORS.
var paint_index := 0
var car_id := "porsche930" ## CarCatalog id of the player's car

## --- Display / audio / controls (settings screen) ---
enum WindowMode { WINDOWED, FULLSCREEN, EXCLUSIVE }
const WINDOW_NAMES := ["Windowed", "Fullscreen", "Exclusive fullscreen"]
var window_mode := WindowMode.WINDOWED
var vsync := true
## 3D render resolution: 0 = Auto (adaptive on Low / Medium), else percent 50..100.
var render_scale := 0
const RENDER_SCALES := [0, 50, 59, 67, 77, 85, 100] ## 50 / 59 / 67 / 77 = FSR Performance / Balanced / Quality / Ultra Quality
enum Upscaler { FSR, FSR2, BILINEAR }
const UPSCALER_NAMES := ["FSR 1 (sharp)", "FSR 2 (temporal)", "Bilinear"]
var upscaler := Upscaler.FSR
## Linear 0..1 per audio bus (default_bus_layout.tres).
const BUSES := ["Master", "Engine", "Effects", "Ambience", "Music"]
var volumes := {Master = 1.0, Engine = 1.0, Effects = 1.0, Ambience = 1.0, Music = 1.0}
enum Units { KMH, MPH }
var units := Units.KMH
var control_hints := true ## the key strip at the start of a race
## Cockpit rear-view mirror: live view on High and Ultra (a static reflection on
## Medium / Low, where a second scene render doesn't fit 60 fps); off = static.
var cockpit_mirror := true
## Player rebinds: action -> {keys = [k0, k1], pad = {...}} (see InputSetup).
var bindings := {}

## Filled in by the host when a race starts: [{peer, name, bot, skill}], index = grid slot.
var grid: Array = []
## Shown by the menu next time it opens (e.g. "The host closed the game.").
var pending_message := ""

## Single-player game mode the race runs (scripts/modes/). Online races ignore it.
enum Session { RACE, CHAMPIONSHIP, TIME_TRIAL }
var session := Session.RACE
## Time trial: laps per session (0 = unlimited) and whether the best-lap ghost drives.
var tt_laps := 0
var tt_ghost := true
## Menu screen to open next time the menu loads ("" = home), e.g. "championship".
var menu_screen := ""


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		player_name = cfg.get_value("player", "name", player_name)
		track_id = cfg.get_value("race", "track", track_id)
		laps = cfg.get_value("race", "laps", laps)
		bots = cfg.get_value("race", "bots", bots)
		difficulty = cfg.get_value("race", "difficulty", difficulty)
		assists = cfg.get_value("player", "assists", assists)
		quality = cfg.get_value("video", "quality", quality)
		paint_index = cfg.get_value("player", "paint", paint_index)
		car_id = cfg.get_value("player", "car", car_id)
		window_mode = cfg.get_value("video", "window_mode", window_mode)
		vsync = cfg.get_value("video", "vsync", vsync)
		render_scale = cfg.get_value("video", "render_scale", render_scale)
		upscaler = cfg.get_value("video", "upscaler", upscaler)
		var vols = cfg.get_value("audio", "volumes", {})
		if vols is Dictionary:
			for k in vols:
				if volumes.has(k):
					volumes[k] = clampf(float(vols[k]), 0.0, 1.0)
		units = cfg.get_value("player", "units", units)
		control_hints = cfg.get_value("player", "control_hints", control_hints)
		cockpit_mirror = cfg.get_value("player", "cockpit_mirror", cockpit_mirror)
		var b = cfg.get_value("controls", "bindings", {})
		bindings = b if b is Dictionary else {}
		if not CarCatalog.has(car_id):
			car_id = CarCatalog.DEFAULT
	if quality < 0:
		# Integrated Apple GPUs: Medium; anything else: High.
		quality = 1 if RenderingServer.get_video_adapter_name().contains("Apple") else 2
	if not RENDER_SCALES.has(render_scale):
		render_scale = 0
	apply_volumes()
	# Test and screenshot runs always pass game args (the player's own game has
	# none): keep them silent, whatever launched them. Video capture
	# (--write-movie) records the mix to the file without playing it, so keep it.
	if not OS.get_cmdline_user_args().is_empty() and Engine.get_write_movie_path().is_empty():
		AudioServer.set_bus_mute(0, true)
	InputSetup.ensure_actions()
	# Test / screenshot runs (any user args) stay in a background window.
	if OS.get_cmdline_user_args().is_empty():
		apply_window()


## Debug: `-- --uishot=/path.png` captures whatever scene is showing after 1.5 s
## (or `--uishot_at=<seconds>`).
var _uishot := ""
var _uishot_at := 1.5
var _uishot_t := 0.0


func _process(dt: float) -> void:
	if _uishot == "":
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--uishot="):
				_uishot = arg.trim_prefix("--uishot=")
			elif arg.begins_with("--uishot_at="):
				_uishot_at = arg.trim_prefix("--uishot_at=").to_float()
		if _uishot == "":
			set_process(false)
			return
	_uishot_t += dt
	if _uishot_t > _uishot_at:
		var err := get_viewport().get_texture().get_image().save_png(_uishot)
		if err != OK:
			printerr("uishot: could not save %s (%s)" % [_uishot, error_string(err)])
		get_tree().quit()


func save_settings() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		return # debug / test runs never overwrite the player's settings
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "assists", assists)
	cfg.set_value("player", "paint", paint_index)
	cfg.set_value("player", "car", car_id)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("race", "track", track_id)
	cfg.set_value("race", "laps", laps)
	cfg.set_value("race", "bots", bots)
	cfg.set_value("race", "difficulty", difficulty)
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "upscaler", upscaler)
	cfg.set_value("audio", "volumes", volumes)
	cfg.set_value("player", "units", units)
	cfg.set_value("player", "control_hints", control_hints)
	cfg.set_value("player", "cockpit_mirror", cockpit_mirror)
	cfg.set_value("controls", "bindings", bindings)
	cfg.save(SETTINGS_PATH)


## Anti-aliasing and render scale for the 3D view.
func apply_viewport_quality(vp: Viewport) -> void:
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality < 3 else Viewport.SCREEN_SPACE_AA_DISABLED
	var s := render_scale_now()
	vp.scaling_3d_scale = s
	vp.scaling_3d_mode = scaling_mode(s)
	vp.fsr_sharpness = 0.25
	if s < 0.999 and upscaler == Upscaler.FSR2:
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED # FSR 2 does its own temporal AA
	# Shadow filtering and SSAO cost a lot of fill on integrated GPUs.
	var soft: int = [RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][quality]
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft)
	RenderingServer.environment_set_ssao_quality([RenderingServer.ENV_SSAO_QUALITY_VERY_LOW,
		RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		RenderingServer.ENV_SSAO_QUALITY_HIGH][quality], true, 0.5, 2, 50, 300)


## Grass density multiplier for the current quality.
func grass_density() -> float:
	return [0.4, 0.5, 1.0, 1.3][quality]


## Bot skill: fraction of the racing line's ideal speed they aim for.
func bot_skill(rng: RandomNumberGenerator) -> float:
	# Fraction of the bots' planned speed (RacingLine.AI_LAT_G / AI_BRAKE). The
	# car stays clean up to ~1.3 (the real limit): Hard ~4-9% a lap off that, very
	# fast but beatable; Medium a fair fight; Easy relaxed. Tight spread on Hard.
	var base: float = [0.82, 0.99, 1.14][difficulty]
	var spread: float = [0.025, 0.018, 0.012][difficulty]
	return clampf(base + rng.randf_range(-spread, spread * 0.8), 0.7, 1.25)


const BOT_NAMES := ["K. Weber", "A. Rossi", "J. Lindqvist", "M. Duval", "P. Novak", "S. Brennan",
	"L. Moreau", "T. Haas", "R. Castell", "E. Sørensen", "D. Mancini", "F. Kowalski"]


## Starting 3D render scale: the fixed choice, or Auto's starting point
## (DynamicRes adjusts Auto on Low / Medium during a race).
func render_scale_now() -> float:
	if render_scale > 0:
		return render_scale / 100.0
	return 0.85 if quality == 0 else 1.0


func scaling_mode(s: float) -> Viewport.Scaling3DMode:
	if s >= 0.999 and upscaler != Upscaler.FSR2:
		return Viewport.SCALING_3D_MODE_BILINEAR
	match upscaler:
		Upscaler.FSR2: return Viewport.SCALING_3D_MODE_FSR2
		Upscaler.BILINEAR: return Viewport.SCALING_3D_MODE_BILINEAR
	return Viewport.SCALING_3D_MODE_FSR


func apply_volumes() -> void:
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var v: float = volumes.get(bus, 1.0)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v * v, 0.00001))) # squared: even steps sound even
		AudioServer.set_bus_mute(i, v <= 0.001)


func apply_window() -> void:
	var want: DisplayServer.WindowMode = [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN][clampi(window_mode, 0, 2)]
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if want == DisplayServer.WINDOW_MODE_WINDOWED:
		# Back from fullscreen: a sensible window, centred on its screen (big and
		# ultra-wide screens get a bigger window at their own aspect, capped at 16:9 height).
		var scr := DisplayServer.window_get_current_screen()
		var usable := DisplayServer.screen_get_usable_rect(scr)
		var cur := DisplayServer.window_get_size()
		if cur.x >= usable.size.x or cur.y >= usable.size.y or cur.x < 640:
			var h := int(usable.size.y * 0.8)
			var w := mini(int(h * 16.0 / 9.0), int(usable.size.x * 0.9))
			DisplayServer.window_set_size(Vector2i(w, h))
			DisplayServer.window_set_position(usable.position + (usable.size - Vector2i(w, h)) / 2)


## Speed (m/s) in the player's units (see speed_label).
func speed_units(mps: float) -> float:
	return absf(mps) * (3.6 if units == Units.KMH else 2.236936)


func speed_label() -> String:
	return "KM/H" if units == Units.KMH else "MPH"


## "4.2 KM" / "2.6 MI" in the player's units.
func distance_text(km: float) -> String:
	return "%.1f KM" % km if units == Units.KMH else "%.1f MI" % (km * 0.621371)
