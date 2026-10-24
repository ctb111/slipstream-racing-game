extends SceneTree
## Builds the photo facade atlas from assets/facades_src (see FacadeKit).
##   tools/hrun.sh --script res://tools/build_facade_atlas.gd
## Prints the SIZES table for facade_kit.gd.

const CELL := 512
const PAD := 16
const OUT := "res://assets/textures/facades/"


func _init() -> void:
	var src_dir := ProjectSettings.globalize_path("res://assets/facades_src/")
	var out_dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var alb := Image.create(CELL * 4, CELL * 5, false, Image.FORMAT_RGBA8)
	var nor := Image.create(CELL * 4, CELL * 5, false, Image.FORMAT_RGB8)
	var mask := Image.create(CELL * 4, CELL * 5, false, Image.FORMAT_RGB8)
	nor.fill(Color(0.5, 0.5, 1.0))
	var sizes := []
	var inner := CELL - PAD * 2
	for i in FacadeKit.CELLS.size():
		var c: Dictionary = FacadeKit.CELLS[i]
		var img := Image.load_from_file(src_dir + String(c.src))
		img.convert(Image.FORMAT_RGBA8)
		var cr: Array = c.crop
		var W := img.get_width()
		var H := img.get_height()
		var r := Rect2i(int(cr[0] * W), int(cr[1] * H), int((cr[2] - cr[0]) * W), int((cr[3] - cr[1]) * H))
		var crop := img.get_region(r)
		var h: float = c.h
		sizes.append(Vector2(snappedf(h * float(r.size.x) / float(r.size.y), 0.01), h))
		# Backdrop: the crop stretched over the whole cell, so the padding
		# continues the edge colours (no bleeding at low mips).
		var back: Image = crop.duplicate()
		back.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		crop.resize(inner, inner, Image.INTERPOLATE_LANCZOS)
		back.blit_rect(crop, Rect2i(0, 0, inner, inner), Vector2i(PAD, PAD))
		var ox := (i % 4) * CELL
		var oy := (i / 4) * CELL
		var is_door: bool = c.get("door", false)
		var g: Array = c.get("glass", [])
		var gr := Rect2()
		if g.size() == 4:
			gr = Rect2((g[0] - cr[0]) / (cr[2] - cr[0]), (g[1] - cr[1]) / (cr[3] - cr[1]),
				(g[2] - g[0]) / (cr[2] - cr[0]), (g[3] - g[1]) / (cr[3] - cr[1]))
		var gray := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
		for y in CELL:
			for x in CELL:
				var col := back.get_pixel(x, y)
				# Coverage: soft 3 px edge at the crop border; on doors the
				# photo's white background (arch corners) is cut away.
				var ex := minf(x - PAD, PAD + inner - 1 - x)
				var ey := minf(y - PAD, PAD + inner - 1 - y)
				var a := clampf((minf(ex, ey) + 1.0) / 3.0, 0.0, 1.0)
				var lum := col.r * 0.3 + col.g * 0.59 + col.b * 0.11
				if is_door:
					var sat := maxf(col.r, maxf(col.g, col.b)) - minf(col.r, minf(col.g, col.b))
					if lum > 0.86 and sat < 0.1:
						a = 0.0
				col.a = a
				alb.set_pixel(ox + x, oy + y, col)
				gray.set_pixel(x, y, Color(lum, lum, lum))
				var glass := 0.0
				if gr.size.x > 0.0:
					var u := (x - PAD) / float(inner)
					var v := (y - PAD) / float(inner)
					var inside := clampf(minf(minf(u - gr.position.x, gr.end.x - u), minf(v - gr.position.y, gr.end.y - v)) * 120.0, 0.0, 1.0)
					if c.get("pale", false): # light glass, dark glazing bars
						glass = inside * clampf((lum - 0.4) * 3.0, 0.0, 1.0)
					else:
						glass = inside * clampf((0.72 - lum) * 2.5, 0.0, 1.0)
				mask.set_pixel(ox + x, oy + y, Color(glass, 0.82 - 0.68 * glass, 0.0))
		# Relief from the photo itself (frames, panels, shutter slats): soft.
		gray.bump_map_to_normal_map(2.0)
		gray.convert(Image.FORMAT_RGB8)
		nor.blit_rect(gray, Rect2i(0, 0, CELL, CELL), Vector2i(ox, oy))
	alb.save_png(out_dir + "facade_alb.png")
	nor.save_png(out_dir + "facade_nor.png")
	mask.save_png(out_dir + "facade_mask.png")
	# Brick block (ambientCG Facade018A): colour, GL normal, mask from roughness.
	var bc := Image.load_from_file(src_dir + "Facade018A_2K-JPG_Color.jpg")
	bc.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	bc.save_jpg(out_dir + "block_alb.jpg", 0.9)
	var bn := Image.load_from_file(src_dir + "Facade018A_2K-JPG_NormalGL.jpg")
	bn.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	bn.save_png(out_dir + "block_nor.png")
	var br := Image.load_from_file(src_dir + "Facade018A_2K-JPG_Roughness.jpg")
	br.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	var bm := Image.create(1024, 1024, false, Image.FORMAT_RGB8)
	for y in 1024:
		for x in 1024:
			var rr := br.get_pixel(x, y).r
			bm.set_pixel(x, y, Color(clampf((0.4 - rr) * 5.0, 0.0, 1.0), rr, 0.0))
	bm.save_png(out_dir + "block_mask.png")
	var line := "const SIZES := ["
	for s: Vector2 in sizes:
		line += "Vector2(%.2f, %.2f), " % [s.x, s.y]
	print(line + "]")
	quit()
