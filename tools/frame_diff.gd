extends SceneTree
## Frame diff for flicker hunts (headless, no ImageMagick needed):
##   tools/hrun.sh -s res://tools/frame_diff.gd -- <dir> <prefix>
## Reads <prefix>_<capture>_<frame>.png (from `--pop-shots`, bursts of
## consecutive frames) and prints, per capture, how many pixels change between
## consecutive frames (AE, |d| > 24/255 on any channel) and how many FLICKER:
## change from frame k to k+1 and change back at k+2 (animation moves on,
## flicker returns). Hot cells = the 8x6 screen grid cells with most flicker.

const T := 24.0 / 255.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	var prefix: String = args[1]
	var files := DirAccess.get_files_at(dir)
	var caps := {}
	for f in files:
		if f.begins_with(prefix + "_") and f.ends_with(".png"):
			var parts := f.trim_suffix(".png").split("_")
			var cap := int(parts[parts.size() - 2])
			if not caps.has(cap):
				caps[cap] = []
			caps[cap].append(f)
	var keys := caps.keys()
	keys.sort()
	var prev_last: Image = null
	for cap: int in keys:
		var list: Array = caps[cap]
		list.sort()
		var imgs: Array[Image] = []
		for f: String in list:
			imgs.append(Image.load_from_file(dir.path_join(f)))
		var ae := []
		for k in imgs.size() - 1:
			ae.append(_ae(imgs[k], imgs[k + 1]))
		var step_ae := _ae(prev_last, imgs[0]) if prev_last else -1
		var fl := 0
		var cells := {}
		for k in imgs.size() - 2:
			fl += _flicker(imgs[k], imgs[k + 1], imgs[k + 2], cells)
		var hot := cells.keys()
		hot.sort_custom(func(a, b): return cells[a] > cells[b])
		var hs := []
		for h in hot.slice(0, 4):
			hs.append("%s:%d" % [h, cells[h]])
		print("cap %03d  step_AE %7d  burst_AE %s  flicker %6d  hot %s" % [cap, step_ae, str(ae), fl, " ".join(hs)])
		prev_last = imgs[imgs.size() - 1]
	quit()


func _ae(a: Image, b: Image) -> int:
	var n := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > T or absf(p.g - q.g) > T or absf(p.b - q.b) > T:
				n += 1
	return n * 4


func _flicker(a: Image, b: Image, c: Image, cells: Dictionary) -> int:
	var n := 0
	var w := a.get_width()
	var h := a.get_height()
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			var r := c.get_pixel(x, y)
			var d1 := maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b)))
			var d2 := maxf(absf(p.r - r.r), maxf(absf(p.g - r.g), absf(p.b - r.b)))
			if d1 > T and d2 < T * 0.5:
				n += 4
				var key := Vector2i(x * 8 / w, y * 6 / h)
				cells[key] = cells.get(key, 0) + 4
	return n
