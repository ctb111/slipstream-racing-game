class_name GxRoadText
extends RefCounted
## Fan messages hand-painted on the tarmac (worn white / yellow roller paint):
## driver names, ALLEZ!, GO GO GO, hearts, arrows, chequered flags. Any string
## works (composed per letter from a painted glyph atlas, each letter jittered),
## so the player's own name and the bot names are painted live.
##
##   GxRoadText.place(c, Gx.road_frame(c, 820.0))                     # random fan message
##   GxRoadText.place(c, Gx.road_frame(c, 820.0), {text = "ALLEZ ROSSI!", color = "yellow"})
##   GxRoadText.place(c, xf, {kind = "player"})    # "GO <PLAYER>!" + heart
##   kinds: "mixed" (default, random), "name", "player", "allez", "gogo", "heart", "arrows", "flag"
##   opts: text, color ("white" / "yellow"), lateral (m from the centreline), size (letter
##   width m, 1.0), stretch (along-road elongation, 3.4: letters ~3.4 m long), seed.
##
## Lies flush on the road at LIFT, following the lap curve (reads left to right for
## the approaching driver, letters elongated so they read at speed). xf: any frame
## on the road (only its position is used). Atlas: tools/make_gx_road_text.py.
## Cost: one draw call per message, 2 tris per letter, ~0.05 ms.

const ATLAS := "res://assets/gimmicks/gx_road_text.png"
const LIFT := 0.037 ## road ribbon +0.02, tyre marks +0.032, trackside kit paint +0.036
const WHITE := Color(0.93, 0.93, 0.9)
const YELLOW := Color(0.96, 0.78, 0.18)
const CHEERS := ["ALLEZ!", "GO GO GO", "FORZA!", "VAMOS!", "HOPP HOPP", "VOLLGAS!", "FLAT OUT", "NO LIFT", "SEND IT"]
const ACCENTS := {"Ö": "Ö", "Ô": "O", "Ó": "O", "Ò": "O", "Í": "I", "Ì": "I", "Ú": "U", "Ù": "U", "Á": "A", "Â": "A", "Ã": "A", "Ê": "E", "Ë": "E", "Ý": "Y", "Ć": "C", "Ń": "N", "Ś": "S", "Ź": "Z", "Ż": "Z", "Č": "C", "Ř": "R", "Ě": "E", "Ů": "U"}

static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/gx_print_alpha.gdshader")
		_mat.set_shader_parameter("atlas", load(ATLAS))
		_mat.set_shader_parameter("detail_nor", Mats.tex("concrete", "nor_gl"))
		_mat.set_shader_parameter("detail_arm", Mats.tex("concrete", "arm"))
		_mat.set_shader_parameter("detail_scale", 0.8)
		_mat.set_shader_parameter("normal_strength", 0.35)
		_mat.set_shader_parameter("rough_base", 0.62)
		_mat.set_shader_parameter("rough_detail", 0.3)
		_mat.render_priority = 1
	return _mat


## Surname in capitals: "K. Weber" -> "WEBER".
static func surname(full: String) -> String:
	var parts := full.strip_edges().split(" ", false)
	return (parts[parts.size() - 1] if parts.size() > 0 else full).to_upper()


static func player_name() -> String:
	var g = Engine.get_main_loop().root.get_node_or_null("Game") if Engine.get_main_loop() is SceneTree else null
	var n := str(g.get("player_name")) if g else ""
	return surname(n) if n != "" and n != "<null>" else "DRIVER"


static func bot_names() -> Array:
	var g = Engine.get_main_loop().root.get_node_or_null("Game") if Engine.get_main_loop() is SceneTree else null
	var out := []
	if g and "BOT_NAMES" in g:
		for n in g.BOT_NAMES:
			out.append(surname(n))
	return out if not out.is_empty() else ["WEBER", "ROSSI", "LINDQVIST"]


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var o := opts.duplicate()
	for k in o:
		if o[k] is String and (o[k] as String).is_valid_float():
			o[k] = float(o[k])
	var cv := Gx.curve(c)
	var l := cv.get_baked_length()
	var along := fposmod(cv.get_closest_offset(xf.origin) - float(c.get("start_offset")), l)
	var r := Gx.rng(c, "roadtext")
	r.seed = hash(str(r.seed) + str(o.get("seed", int(along))))
	var col: Color = YELLOW if str(o.get("color", "yellow" if r.randf() < 0.3 else "white")) == "yellow" else WHITE
	var size: float = o.get("size", 1.0)
	var stretch: float = o.get("stretch", 3.4)
	var lat: float = o.get("lateral", 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kind: String = o.get("kind", "mixed")
	var text: String = o.get("text", "")
	var names := bot_names()
	if text == "":
		match kind:
			"name": text = names[r.randi() % names.size()] + ("!" if r.randf() < 0.5 else "")
			"player": text = "GO " + player_name() + "!"
			"allez": text = "ALLEZ " + names[r.randi() % names.size()] + "!"
			"gogo": text = "GO GO GO"
			"heart", "arrows", "flag": text = ""
			_:
				var roll := r.randf()
				if roll < 0.35:
					text = names[r.randi() % names.size()]
				elif roll < 0.5:
					text = "GO " + player_name() + "!"
				elif roll < 0.6:
					kind = ["heart", "arrows", "flag"][r.randi() % 3]
				else:
					text = CHEERS[r.randi() % CHEERS.size()]
	var hw := Gx.half_width() - 0.6
	var line_len := size * stretch # along the road
	if text != "":
		_text(st, c, r, text, along, lat, size, stretch, hw, col)
		# a heart or arrows painted after names, sometimes
		if kind in ["name", "player"] or (kind == "mixed" and r.randf() < 0.35):
			_symbol(st, c, along + line_len * 1.6, lat + r.randf_range(-1.5, 1.5), 1.4, 1.4 * stretch * 0.7, 0 if r.randf() < 0.6 else 1, col, r)
	match kind:
		"heart":
			_symbol(st, c, along, lat, 2.2, 2.2 * stretch * 0.7, r.randi() % 2, Color(0.75, 0.1, 0.1) if r.randf() < 0.3 else col, r)
		"arrows":
			for k in 3:
				_symbol(st, c, along + k * 1.0, lat + (k - 1) * 2.6, 1.4, 1.4 * stretch, 2 + (k % 2), col, r)
		"flag":
			_symbol(st, c, along, lat, 2.6, 2.6 * stretch * 0.6, 4, col, r)
	var mi := Gx.add_mesh(c, st, material(), "GxRoadText", 220.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Road frame at lap offset `a`: [centre on the paint plane, forward (follows
## the slope), right]. Sampled once per text line / symbol (cheap).
static func _frame(c: Node3D, a: float) -> Array:
	var p0 := Gx.centre(c, a - 1.5)
	var p1 := Gx.centre(c, a + 1.5)
	var fwd := (p1 - p0).normalized()
	var rgt := fwd.cross(Vector3.UP).normalized()
	return [Gx.centre(c, a) + Vector3.UP * LIFT, fwd, rgt]


## Quad on the road in frame `f` (from _frame at lap offset a_f): along a0..a1
## (relative to the frame; a1 = top of the letter, further away), lateral x0..x1
## (x0 left), uv rect `uvr` (top-left origin), jitter rotation.
static func _road_quad(st: SurfaceTool, f: Array, a0: float, a1: float, x0: float, x1: float, uvr: Rect2, col: Color, rot := 0.0) -> void:
	var ca := (a0 + a1) * 0.5
	var cx := (x0 + x1) * 0.5
	var corners := [Vector2(x0, a0), Vector2(x1, a0), Vector2(x1, a1), Vector2(x0, a1)]
	var uvs := [Vector2(uvr.position.x, uvr.end.y), uvr.end, Vector2(uvr.end.x, uvr.position.y), uvr.position]
	var pts := []
	var aspect := (a1 - a0) / maxf(x1 - x0, 0.01)
	var o: Vector3 = f[0]
	var fwd: Vector3 = f[1]
	var rgt: Vector3 = f[2]
	for q: Vector2 in corners:
		var d := q - Vector2(cx, ca)
		d = Vector2(d.x * cos(rot) - d.y / aspect * sin(rot), (d.x * sin(rot) + d.y / aspect * cos(rot)) * aspect)
		pts.append(o + fwd * (ca + d.y) + rgt * (cx + d.x))
	# seen from above: (x right, a forward) corners are counter-clockwise -> emit clockwise
	for k: int in [0, 2, 1, 0, 3, 2]:
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[k])
		var w: Vector3 = pts[k]
		st.set_uv2(Vector2(w.x, w.z))
		st.add_vertex(w)


static func _glyph_index(ch: String) -> int:
	var i := GxRoadGlyphs.CHARS.find(ch)
	if i < 0 and ACCENTS.has(ch):
		i = GxRoadGlyphs.CHARS.find(ACCENTS[ch])
	return i


static func _text(st: SurfaceTool, c: Node3D, r: RandomNumberGenerator, text: String, along: float, lat: float,
		size: float, stretch: float, hw: float, col: Color) -> void:
	text = text.to_upper()
	var total := 0.0
	for ch in text:
		var gi := _glyph_index(ch)
		total += size * (0.55 if ch == " " else (GxRoadGlyphs.ADV[gi] if gi >= 0 else 0.0)) * 0.92
	var s := minf(1.0, (hw * 2.0) / maxf(total, 0.01)) # shrink long names to fit the road
	var w := size * s
	var x := clampf(lat, -hw + total * s * 0.5, hw - total * s * 0.5) - total * s * 0.5
	var tilt := r.randf_range(-0.04, 0.04) # whole line slightly off-square
	var f := _frame(c, along)
	for ch in text:
		if ch == " ":
			x += w * 0.55 * 0.92
			continue
		var gi := _glyph_index(ch)
		if gi < 0:
			continue
		var adv: float = GxRoadGlyphs.ADV[gi] * w * 0.92
		var var_ := r.randi() % 2
		var cell := gi + var_ * 64
		var uvr := Rect2((cell % 16) * 128.0 / 2048.0, (cell / 16) * 128.0 / 2048.0, 128.0 / 2048.0, 128.0 / 2048.0)
		var js := r.randf_range(0.92, 1.08)
		var gx := x + adv * 0.5
		var ga := gx * tilt + r.randf_range(-0.06, 0.06) * stretch
		var half_w := w * 0.5 * js
		var half_l := w * stretch * 0.5 * js
		var cc := col
		cc.a = r.randf_range(0.78, 1.0)
		_road_quad(st, f, ga - half_l, ga + half_l, gx - half_w, gx + half_w, uvr, cc, r.randf_range(-0.07, 0.07))
		x += adv


static func _symbol(st: SurfaceTool, c: Node3D, along: float, lat: float, w: float, l: float, idx: int,
		col: Color, r: RandomNumberGenerator) -> void:
	var hw := Gx.half_width() - 0.4
	lat = clampf(lat, -hw + w * 0.5, hw - w * 0.5)
	var uvr := Rect2((idx % 8) * 256.0 / 2048.0, (1024.0 + (idx / 8) * 256.0) / 2048.0, 256.0 / 2048.0, 256.0 / 2048.0)
	var cc := col
	cc.a = r.randf_range(0.8, 1.0)
	_road_quad(st, _frame(c, along), -l * 0.5, l * 0.5, lat - w * 0.5, lat + w * 0.5, uvr, cc, r.randf_range(-0.05, 0.05))
