class_name GxHeli
extends Node3D
## TV helicopter (AS350 "Ecureuil"-style, the classic rally TV ship): a lofted
## fuselage with a glass canopy and cabin windows, engine fairing, tail boom,
## stabilisers, fin, skids and a nose camera gimbal; rotor blur discs over a
## slowly turning blade set. Flies a smoothed loop round the circuit at
## 80-150 m above the ground, banking into turns, nose slightly down, with a
## synthesised positional rotor sound (Ambience bus) and Doppler.
## Optional: a news-camera drone hovering at a corner.
##
##   GxHeli.place(c, Transform3D.IDENTITY, {})                    # the flying helicopter
##   GxHeli.place(c, Gx.frame(c, corner.along, side, 6.0), {kind = "drone"})
##
## Options: alt_min (80), alt_max (150), speed (34 m/s), livery 0..2,
##   kind "heli" | "drone", height (drone: 9 m), sound (true).
## Purely cosmetic and local (not networked); no collision.

const RATE := 22050.0
const LOOP_S := 2.0

static var _banks := {} ## kind -> AudioStreamWAV
static var _jobs := {} ## kind -> [task id, PackedByteArray holder]
static var _meshes := {} ## "heli_<livery>" / "drone" -> Node3D template parts [Array of [mesh, mat, shadow]]

var path: Curve3D
var speed := 34.0
var drone := false
var _s := 0.0
var _rotor: Node3D
var _tail: Node3D
var _audio: AudioStreamPlayer3D
var _kind := "heli"
var _home := Vector3.ZERO
var _t := 0.0
var _roll := 0.0
# searchlight (night / storm): additive cone + ground pool, aimed at 4 Hz
var _beam: MeshInstance3D
var _pool: MeshInstance3D
var _curve: Curve3D
var _race: Node
var _aim := Vector3.ZERO
var _target := Vector3.ZERO
var _aim_t := 0.0
var _energy := 0.0
static var _beam_mat: ShaderMaterial
static var _pool_mat: ShaderMaterial


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var kind := str(opts.get("kind", "heli"))
	var h := GxHeli.new()
	h._kind = kind
	if kind == "drone":
		h.drone = true
		h.name = "GxDrone"
		h._build_drone()
		var p := xf.origin + Vector3.UP * float(opts.get("height", 9.0)) - xf.basis.z * 2.0
		h._home = p
		h.transform = Transform3D(xf.basis, p)
	elif opts.has("hover"): # showcase / test: hovering in place, `hover` metres up
		h.name = "GxHeliHover"
		h._build_heli(int(opts.get("livery", 0)))
		h._home = xf.origin + Vector3.UP * float(opts.hover) + xf.basis.z * 12.0
		h.transform = Transform3D(xf.basis * Basis(Vector3.UP, 0.6), h._home)
		h.drone = true # hover motion
	else:
		h.name = "GxHeli"
		h.speed = float(opts.get("speed", 34.0))
		h.path = _flight_path(c, float(opts.get("alt_min", 80.0)), float(opts.get("alt_max", 150.0)))
		if h.path == null:
			return
		h._s = randf() * h.path.get_baked_length()
		h._build_heli(int(opts.get("livery", 0)))
		var w := Weather.current()
		if OS.get_cmdline_user_args().has("--heli_near"): # debug: start over the grid
			h._s = h.path.get_closest_offset(Gx.centre(c, 0.0))
		if GxCamp._b(opts.get("searchlight", true)) and not GxLive.off() and (GxLive.dark() or (w and w.cycle)):
			h._build_searchlight(c)
	if GxCamp._b(opts.get("sound", true)) and not OS.get_cmdline_user_args().has("--no-heli-sound"):
		h._audio = AudioStreamPlayer3D.new()
		h._audio.bus = &"Ambience"
		h._audio.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_IDLE_STEP
		if h.drone:
			h._audio.unit_size = 3.0
			h._audio.max_distance = 120.0
			h._audio.volume_db = -6.0
		else:
			h._audio.unit_size = 45.0
			h._audio.max_distance = 1800.0
			h._audio.volume_db = -2.0
			h._audio.attenuation_filter_cutoff_hz = 2500.0
		h.add_child(h._audio)
	c.add_child(h)
	if h.drone:
		GxCamp.maybe_ab(h, h._home + xf.basis.x * -14.0 + Vector3(0, -4.0, 0) - xf.basis.z * 10.0, h._home)


## Smoothed loop over the circuit: the centreline averaged over +-250 m (cuts
## the corners, stays over the track area), lifted to alt_min..alt_max above
## the highest ground nearby.
static func _flight_path(c: Node3D, alt_min: float, alt_max: float) -> Curve3D:
	var cv := Gx.curve(c)
	if cv == null:
		return null
	var l := cv.get_baked_length()
	var step := 20.0
	var n := maxi(int(l / step), 12)
	var raw: Array[Vector3] = []
	for i in n:
		raw.append(cv.sample_baked(l * i / n))
	var win := maxi(int(250.0 / step), 2)
	var out := Curve3D.new()
	out.bake_interval = 4.0
	var pts: Array[Vector3] = []
	for i in n:
		var acc := Vector3.ZERO
		var wsum := 0.0
		for k in range(-win, win + 1):
			var w := 1.0 - absf(float(k)) / (win + 1)
			acc += raw[(i + k + n) % n] * w
			wsum += w
		var p := acc / wsum
		var gy := -INF
		for d: Vector3 in [Vector3.ZERO, Vector3(30, 0, 0), Vector3(-30, 0, 0), Vector3(0, 0, 30), Vector3(0, 0, -30)]:
			gy = maxf(gy, Gx.ground(c, p + d))
		gy = maxf(gy, raw[i].y)
		var alt := lerpf(alt_min, alt_max, 0.5 + 0.5 * sin(TAU * 2.0 * i / n + 1.3))
		pts.append(Vector3(p.x, gy + alt, p.z))
	# second pass: soften altitude so it doesn't follow every hill
	for i in n:
		var y := 0.0
		for k in range(-3, 4):
			y += pts[(i + k + n) % n].y
		out.add_point(Vector3(pts[i].x, y / 7.0, pts[i].z))
	out.add_point(out.get_point_position(0))
	return out


func _ready() -> void:
	if _audio:
		_audio_start()


func _process(delta: float) -> void:
	_t += delta
	if _rotor:
		_rotor.rotate_y(delta * 14.0)
	if _tail:
		_tail.rotate_x(delta * 40.0)
	if drone:
		var bob := Vector3(sin(_t * 0.7) * 0.4, sin(_t * 1.1) * 0.25, cos(_t * 0.5) * 0.3)
		position = _home + bob
		rotation = Vector3(0.03 * sin(_t * 1.3), rotation.y + 0.0, 0.03 * cos(_t * 0.9))
	elif path:
		var l := path.get_baked_length()
		_s = fmod(_s + speed * delta, l)
		var p := path.sample_baked(_s, true)
		var ahead := path.sample_baked(fmod(_s + 25.0, l), true)
		var ahead2 := path.sample_baked(fmod(_s + 50.0, l), true)
		var d1 := (ahead - p)
		var d2 := (ahead2 - ahead)
		d1.y = 0.0
		d2.y = 0.0
		var turn := d1.normalized().signed_angle_to(d2.normalized(), Vector3.UP) # + = left
		var want := clampf(turn * 2.2, -0.45, 0.45)
		_roll = lerpf(_roll, want, clampf(delta * 1.5, 0.0, 1.0))
		var dir := (ahead - p).normalized()
		if dir.length() < 0.1:
			dir = Vector3.FORWARD
		var b := Basis.looking_at(dir, Vector3.UP)
		b = b * Basis(Vector3.FORWARD, -_roll) * Basis(Vector3.RIGHT, -0.09) # bank, nose down
		transform = Transform3D(b, p)
		if _beam:
			_searchlight(delta)
	if _audio and not _audio.playing and _banks.has(_kind):
		_audio.stream = _banks[_kind]
		_audio.play(randf() * LOOP_S)
	elif _audio and not _banks.has(_kind) and _jobs.has(_kind):
		var job: Array = _jobs[_kind]
		if WorkerThreadPool.is_task_completed(job[0]):
			WorkerThreadPool.wait_for_task_completion(job[0])
			var wav := AudioStreamWAV.new()
			wav.format = AudioStreamWAV.FORMAT_16_BITS
			wav.mix_rate = int(RATE)
			wav.stereo = false
			wav.data = job[1][0]
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(RATE * LOOP_S)
			_banks[_kind] = wav
			_jobs.erase(_kind)


# ---------------------------------------------------------------- searchlight

const BEAM_R := 5.0 ## radius of the beam where it meets the ground (m)


func _build_searchlight(c: Node3D) -> void:
	_curve = Gx.curve(c)
	if _beam_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float energy = 0.0;
uniform bool pool = false;
varying float along;
void vertex() {
	along = UV.y;
}
void fragment() {
	float a;
	if (pool) {
		float r = length(UV - 0.5) * 2.0;
		a = smoothstep(1.0, 0.2, r) * 0.55;
	} else {
		float face = abs(dot(normalize(NORMAL), normalize(VIEW))); // soft edges, bright core
		a = pow(face, 2.0) * (1.0 - along * 0.75) * smoothstep(0.0, 0.05, along) * 0.11;
	}
	ALBEDO = vec3(1.0, 0.96, 0.86) * a * energy;
}
"""
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = sh
		_pool_mat = ShaderMaterial.new()
		_pool_mat.shader = sh
		_pool_mat.set_shader_parameter("pool", true)
	# unit cone: apex at the origin, 1 m long down -z, radius 1 at the far end
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var e0 := Vector3(cos(a0), sin(a0), -1.0)
		var e1 := Vector3(cos(a1), sin(a1), -1.0)
		for v: Vector3 in [Vector3.ZERO, e0, e1]:
			st.set_normal(Vector3(v.x, v.y, 0.3).normalized() if v != Vector3.ZERO else Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0.3).normalized())
			st.set_uv(Vector2(0.0, -v.z))
			st.add_vertex(v)
	_beam = MeshInstance3D.new()
	_beam.name = "Searchlight"
	_beam.mesh = st.commit()
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.extra_cull_margin = 400.0 # the mesh is unit size, stretched by the transform
	add_child(_beam)
	var q := QuadMesh.new()
	q.size = Vector2(BEAM_R * 2.6, BEAM_R * 2.6)
	q.orientation = PlaneMesh.FACE_Y
	_pool = MeshInstance3D.new()
	_pool.name = "SearchlightPool"
	_pool.mesh = q
	_pool.material_override = _pool_mat
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pool.top_level = true
	add_child(_pool)


## Every frame while flying: move the beam with the ship (one transform each);
## at 4 Hz pick the target: the leader if within 350 m, else sweep the track below.
func _searchlight(dt: float) -> void:
	_aim_t -= dt
	if _aim_t <= 0.0:
		_aim_t = 0.25
		var want := 1.0 if GxLive.dark() else 0.0
		_energy = want if _energy < 0.0 else _energy
		_energy = move_toward(_energy, want, 0.1)
		_beam.visible = _energy > 0.01
		_pool.visible = _beam.visible
		if not _beam.visible:
			return
		_beam_mat.set_shader_parameter("energy", _energy)
		_pool_mat.set_shader_parameter("energy", _energy)
		if _race == null:
			_race = GxLive.race(self)
		var lead = GxLive.leader(_race)
		var here := position
		var tgt := Vector3.INF
		if lead and lead.car and is_instance_valid(lead.car):
			var lp: Vector3 = (get_parent() as Node3D).to_local(lead.car.global_position)
			if Vector2(lp.x - here.x, lp.z - here.z).length() < 350.0:
				tgt = lp
		if tgt == Vector3.INF and _curve:
			tgt = _curve.get_closest_point(here)
			tgt += Vector3(sin(_t * 0.45), 0, cos(_t * 0.31)) * 18.0 # searching
		_target = tgt
		if _aim == Vector3.ZERO:
			_aim = tgt
	if not _beam.visible:
		return
	_aim = _aim.lerp(_target, clampf(dt * 1.6, 0.0, 1.0))
	var src := global_transform * Vector3(0, 0.3, -2.2) # under the nose
	var dst: Vector3 = (get_parent() as Node3D).global_transform * _aim
	var d := dst - src
	var l := d.length()
	if l < 1.0:
		return
	var b := Basis.looking_at(d / l, Vector3.UP if absf(d.y) < l * 0.99 else Vector3.FORWARD)
	_beam.global_transform = Transform3D(b.scaled_local(Vector3(BEAM_R, BEAM_R, l)), src)
	_pool.global_transform = Transform3D(Basis(), dst + Vector3.UP * 0.25)


# ---------------------------------------------------------------- sound

func _audio_start() -> void:
	if _banks.has(_kind) or _jobs.has(_kind):
		return
	var holder := [PackedByteArray()]
	var kind := _kind
	var id := WorkerThreadPool.add_task(func() -> void: holder[0] = GxHeli._synth(kind))
	_jobs[_kind] = [id, holder]


## A seamless 2 s loop. Heli: 20 Hz main-rotor blade slap (filtered noise
## bursts + a low thump), 100 Hz tail-rotor buzz, turbine whine, wash noise.
## Drone: four detuned prop tones ~190-230 Hz with harmonics + hiss.
static func _synth(kind: String) -> PackedByteArray:
	var n := int(RATE * LOOP_S)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var lp1 := 0.0
	var lp2 := 0.0
	var lp3 := 0.0
	var peak := 0.0001
	for i in n:
		var t := float(i) / RATE
		var wn := rng.randf_range(-1.0, 1.0)
		lp1 += (wn - lp1) * 0.08  # ~280 Hz
		lp2 += (wn - lp2) * 0.02  # ~70 Hz
		lp3 += (wn - lp3) * 0.35  # ~1.5 kHz
		var v := 0.0
		if kind == "drone":
			for k in 4:
				var f: float = [196.0, 207.5, 219.0, 231.5][k]
				var ph: float = TAU * f * t + k
				v += 0.18 * sin(ph) + 0.08 * sin(2.0 * ph + 0.3) + 0.04 * sin(3.0 * ph)
			v *= 1.0 + 0.15 * sin(TAU * 3.0 * t)
			v += lp3 * 0.25
		else:
			var phase := fmod(t * 20.0, 1.0)
			var env := exp(-phase * 7.0)
			var slap := lp1 * env * 2.2 + sin(TAU * 20.0 * t) * 0.22 + sin(TAU * 40.0 * t) * env * 0.35
			var buzz := tanh(2.5 * sin(TAU * 100.0 * t)) * 0.07 * (0.8 + 0.2 * sin(TAU * 20.0 * t))
			var whine := 0.022 * sin(TAU * 1450.0 * t) + 0.012 * sin(TAU * 2900.0 * t + 0.4)
			var wash := lp2 * 1.2 + lp3 * 0.08
			v = slap + buzz + whine + wash
		buf[i] = v
		peak = maxf(peak, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var g := 0.85 / peak
	# 20 ms crossfade of the loop seam (noise filters don't wrap)
	var xf := int(RATE * 0.02)
	for i in xf:
		var a := float(i) / xf
		buf[i] = buf[i] * a + buf[n - xf + i] * (1.0 - a)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
	return bytes


# ---------------------------------------------------------------- models

func _build_heli(livery: int) -> void:
	var g := GxGeo.new()
	var white := Color(0.9, 0.9, 0.88)
	var accent: Color = [Color(0.62, 0.06, 0.05), Color(0.06, 0.16, 0.42), Color(0.95, 0.55, 0.05)][livery % 3]
	var dark := Color(0.05, 0.05, 0.06)
	# stations: z, half width, bottom y, top y, squareness exponent
	var st := [
		[-2.42, 0.06, 0.62, 0.70, 2.0],
		[-2.32, 0.38, 0.40, 1.00, 2.2],
		[-2.12, 0.62, 0.20, 1.32, 2.4],
		[-1.80, 0.80, 0.07, 1.58, 2.6],
		[-1.35, 0.90, 0.02, 1.76, 2.8],
		[-0.70, 0.95, 0.00, 1.86, 3.0],
		[0.10, 0.95, 0.00, 1.88, 3.0],
		[0.85, 0.92, 0.04, 1.86, 3.0],
		[1.45, 0.78, 0.22, 1.82, 2.8],
		[1.95, 0.55, 0.55, 1.74, 2.6],
		[2.35, 0.34, 0.90, 1.60, 2.4],
		[2.60, 0.26, 1.08, 1.52, 2.2],
	]
	var na := 28
	var grid := []
	for s: Array in st:
		var ring := []
		var cy: float = (s[2] + s[3]) * 0.5
		var hy: float = (s[3] - s[2]) * 0.5
		for j in na:
			var a := TAU * j / na
			var ca := cos(a)
			var sa := sin(a)
			var e: float = s[4]
			var sup := pow(pow(absf(ca), e) + pow(absf(sa), e), -1.0 / e)
			ring.append(Vector3(ca * sup * s[1], cy + sa * sup * hy, s[0]))
		grid.append(ring)
	var ns := st.size()
	# smooth normals from the grid
	var nrm := []
	for i in ns:
		var row := []
		for j in na:
			var pu: Vector3 = grid[mini(i + 1, ns - 1)][j] - grid[maxi(i - 1, 0)][j]
			var pv: Vector3 = grid[i][(j + 1) % na] - grid[i][(j - 1 + na) % na]
			var n := pv.cross(pu).normalized()
			var cen := Vector3(0, (st[i][2] + st[i][3]) * 0.5, st[i][0])
			if n.dot(grid[i][j] - cen) < 0.0:
				n = -n
			row.append(n)
		nrm.append(row)
	for i in ns - 1:
		for j in na:
			var j2 := (j + 1) % na
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i][j2]
			var cc: Vector3 = grid[i + 1][j2]
			var d: Vector3 = grid[i + 1][j]
			var mid := (a + b + cc + d) * 0.25
			var mat := "painted_metal"
			var col := white
			# canopy: the front bubble above the nose band
			if mid.z < -1.0 and mid.y > 0.52 and not (absf(mid.x) < 0.05 and mid.y > 1.2):
				mat = "glass"
			# cabin side windows / doors
			elif mid.z > -1.0 and mid.z < 0.95 and mid.y > 0.98 and mid.y < 1.62 and absf(mid.x) > 0.6:
				if absf(mid.z - (-0.05)) > 0.07:
					mat = "glass"
				else:
					col = dark
			if mat != "glass":
				if mid.y < 0.42:
					col = accent
				elif mid.y < 0.55 and mid.y > 0.47:
					col = accent.darkened(0.3)
				if mid.y < 0.12:
					col = Color(0.25, 0.25, 0.26)
			g.col = col if mat != "glass" else Color(0.7, 0.75, 0.8)
			var n00: Vector3 = nrm[i][j]
			var n01: Vector3 = nrm[i][j2]
			var n11: Vector3 = nrm[i + 1][j2]
			var n10: Vector3 = nrm[i + 1][j]
			var fn := (b - a).cross(d - a)
			var scen := Vector3(0, (st[i][2] + st[i][3] + st[i + 1][2] + st[i + 1][3]) * 0.25, mid.z)
			if fn.dot(mid - scen) >= 0.0:
				g.tri_n(mat, a, b, cc, n00, n01, n11)
				g.tri_n(mat, a, cc, d, n00, n11, n10)
			else:
				g.tri_n(mat, a, cc, b, n00, n11, n01)
				g.tri_n(mat, a, d, cc, n00, n10, n11)
	# nose cap + rear cap (rear joins the boom)
	g.col = white
	for e: int in [0, ns - 1]:
		var cen := Vector3(0, (st[e][2] + st[e][3]) * 0.5, st[e][0] + (-0.03 if e == 0 else 0.0))
		for j in na:
			var a: Vector3 = grid[e][j]
			var b: Vector3 = grid[e][(j + 1) % na]
			_tri_out(g, "painted_metal", cen, a, b, cen + Vector3(0, 0, 1.0 if e == 0 else -1.0))
	# engine / transmission fairing on the roof, exhaust
	g.col = white
	g.box("painted_metal", Vector3(0, 2.0, 0.55), Vector3(1.05, 0.34, 2.2), 0.14)
	g.box("painted_metal", Vector3(0, 1.95, -0.65), Vector3(0.8, 0.22, 0.6), 0.1)
	g.col = Color(0.12, 0.12, 0.12)
	g.box("painted_metal", Vector3(0.4, 2.02, 0.2), Vector3(0.06, 0.18, 0.5), 0.02) # intake grille
	g.box("painted_metal", Vector3(-0.4, 2.02, 0.2), Vector3(0.06, 0.18, 0.5), 0.02)
	g.tube("steel", [Vector3(0.0, 1.95, 1.6), Vector3(0.0, 1.92, 1.95)], 0.13, 10)
	# tail boom (tapered), stabilisers with end plates, fin, tail-rotor gearbox
	var boom := []
	var radii := []
	for k in 9:
		var t := float(k) / 8.0
		boom.append(Vector3(0, lerpf(1.32, 1.42, t), lerpf(2.4, 6.55, t)))
		radii.append(lerpf(0.26, 0.11, t))
	g.col = white
	g.tube("painted_metal", boom, 0.2, 12, true, radii)
	g.col = accent
	g.box("painted_metal", Vector3(0, 1.38, 5.35), Vector3(2.3, 0.05, 0.42), 0.02)
	for sx: float in [-1.0, 1.0]:
		g.box("painted_metal", Vector3(sx * 1.15, 1.38, 5.4), Vector3(0.04, 0.42, 0.42), 0.015, Basis(Vector3.RIGHT, -0.25))
	g.col = white
	# fin: swept quad slab (upper + lower)
	g.box("painted_metal", Vector3(0, 1.95, 6.55), Vector3(0.06, 1.05, 0.55), 0.02, Basis(Vector3.RIGHT, -0.45))
	g.box("painted_metal", Vector3(0, 1.08, 6.45), Vector3(0.05, 0.45, 0.4), 0.02, Basis(Vector3.RIGHT, 0.4))
	g.col = accent
	g.box("painted_metal", Vector3(0, 2.25, 6.72), Vector3(0.065, 0.35, 0.5), 0.02, Basis(Vector3.RIGHT, -0.45))
	# skids
	g.col = Color(0.55, 0.55, 0.55)
	for sx: float in [-1.0, 1.0]:
		var sk := [Vector3(sx * 1.12, -0.62, -1.75), Vector3(sx * 1.12, -0.72, -1.45), Vector3(sx * 1.12, -0.75, -0.9), Vector3(sx * 1.12, -0.75, 1.45)]
		g.tube("steel", sk, 0.045, 8)
		for zc: float in [-0.75, 0.75]:
			g.tube("steel", [Vector3(sx * 1.12, -0.74, zc), Vector3(sx * 1.05, -0.4, zc), Vector3(sx * 0.7, -0.02, zc), Vector3(0, 0.02, zc)], 0.04, 8)
	# camera gimbal under the nose + step
	g.col = Color(0.2, 0.2, 0.22)
	g.bar("steel", Vector3(-0.55, 0.05, -1.75), Vector3(-0.55, -0.18, -1.85), 0.05)
	g.lathe("painted_metal", Vector3(-0.55, -0.55, -1.9), _sphere_prof(0.24, 8), 14)
	g.col = Color(0.02, 0.02, 0.03)
	g.lathe("glass", Vector3(-0.55, -0.31, -2.06), _sphere_prof(0.08, 5), 10)
	# mast + hub
	g.col = Color(0.15, 0.15, 0.15)
	g.bar("steel", Vector3(0, 2.1, 0.25), Vector3(0, 2.62, 0.25), 0.08, 10)
	_commit_into(g, self, "HeliBody", path == null) # flying high: no shadow pass
	# main rotor: 3 blades (slow visual spin) + blur disc
	_rotor = Node3D.new()
	_rotor.name = "Rotor"
	_rotor.position = Vector3(0, 2.62, 0.25)
	add_child(_rotor)
	var rg := GxGeo.new()
	rg.col = Color(0.06, 0.06, 0.06)
	rg.lathe("steel", Vector3(0, -0.06, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.28, 0.02), Vector2(0.24, 0.12), Vector2(0.0, 0.16)]), 12)
	for k in 3:
		var bb := Basis(Vector3.UP, TAU * k / 3.0)
		rg.box("steel", bb * Vector3(0, 0.02, -2.85), Vector3(0.3, 0.04, 5.4), 0.01, bb * Basis(Vector3.RIGHT, 0.03))
		rg.col = Color(0.85, 0.75, 0.1)
		rg.box("steel", bb * Vector3(0, 0.035, -5.45), Vector3(0.31, 0.045, 0.22), 0.0, bb)
		rg.col = Color(0.06, 0.06, 0.06)
	_commit_into(rg, _rotor, "Blades", false)
	_rotor.add_child(_blur_disc(5.6, 0.04, 0.22))
	# tail rotor
	_tail = Node3D.new()
	_tail.name = "TailRotor"
	_tail.position = Vector3(0.22, 1.7, 6.55)
	add_child(_tail)
	var tg := GxGeo.new()
	tg.col = Color(0.08, 0.08, 0.08)
	for k in 2:
		tg.box("steel", Vector3.ZERO, Vector3(0.03, 1.6, 0.14), 0.0, Basis(Vector3.RIGHT, PI * 0.5 * k))
	_commit_into(tg, _tail, "TailBlades", false)
	var td := _blur_disc(0.85, 0.0, 0.3)
	td.rotation = Vector3(0, 0, PI * 0.5)
	add_child(td)
	td.position = _tail.position + Vector3(0.03, 0, 0)
	# anti-collision beacon (red, tiny emissive) and nav lights
	var beacon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.radial_segments = 8
	sm.rings = 4
	beacon.mesh = sm
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(1, 0.1, 0.05)
	em.emission_enabled = true
	em.emission = Color(1, 0.08, 0.04)
	em.emission_energy_multiplier = 4.0
	beacon.material_override = em
	beacon.position = Vector3(0, 2.22, 1.3)
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beacon)


func _build_drone() -> void:
	var g := GxGeo.new()
	var body := Color(0.22, 0.22, 0.24)
	g.col = body
	g.box("painted_metal", Vector3(0, 0, 0), Vector3(0.24, 0.09, 0.34), 0.035)
	g.col = Color(0.85, 0.85, 0.85)
	g.box("painted_metal", Vector3(0, 0.055, -0.02), Vector3(0.18, 0.03, 0.24), 0.012)
	g.col = body
	var motors := []
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var tip := Vector3(cos(a) * 0.3, 0.02, sin(a) * 0.3)
		g.beam("painted_metal", Vector3(cos(a) * 0.08, 0, sin(a) * 0.1), tip, 0.03, 0.025)
		g.col = Color(0.08, 0.08, 0.08)
		g.tube("steel", [tip + Vector3(0, -0.02, 0), tip + Vector3(0, 0.05, 0)], 0.028, 10)
		g.bar("steel", tip, tip + Vector3(0, -0.13, 0), 0.008, 4) # landing leg
		g.col = body
		motors.append(tip + Vector3(0, 0.06, 0))
	# gimbal + camera
	g.col = Color(0.1, 0.1, 0.1)
	g.box("painted_metal", Vector3(0, -0.08, -0.13), Vector3(0.08, 0.07, 0.09), 0.015)
	g.col = Color(0.02, 0.02, 0.03)
	g.lathe("glass", Vector3(0, -0.08, -0.18), _sphere_prof(0.022, 4), 8)
	_commit_into(g, self, "DroneBody", true)
	for m: Vector3 in motors:
		var d := _blur_disc(0.13, 0.0, 0.35)
		d.position = m
		add_child(d)
	# little status LEDs
	scale = Vector3.ONE * 1.35


static func _sphere_prof(r: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := -PI * 0.5 + PI * i / n
		out.append(Vector2(cos(a) * r + 0.0001, sin(a) * r + r))
	return out


static func _tri_out(g: GxGeo, mat: String, a: Vector3, b: Vector3, cc: Vector3, inside: Vector3) -> void:
	var n := (b - a).cross(cc - a)
	if n.dot((a + b + cc) / 3.0 - inside) < 0.0:
		g.tri(mat, a, cc, b)
	else:
		g.tri(mat, a, b, cc)


func _commit_into(g: GxGeo, parent: Node3D, node_name: String, shadows: bool) -> void:
	# GxGeo.commit adds one MeshInstance3D per material to `parent` (no collision here)
	var holder := Node3D.new()
	holder.name = node_name
	parent.add_child(holder)
	g.commit(holder, node_name, 0.0, shadows)


## Translucent rotor-blur disc: radial streaks, darker at the tips, alpha
## fading towards the hub; drawn both sides.
static func _blur_disc(radius: float, cone: float, alpha: float) -> MeshInstance3D:
	var key := "disc_%.2f" % alpha
	var mi := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 32
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for k in 2:
			var r0 := radius * (0.12 if k == 0 else 0.55)
			var r1 := radius * (0.55 if k == 0 else 1.0)
			var p00 := Vector3(cos(a0) * r0, -cone * r0 / radius, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, -cone * r0 / radius, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, -cone * r1 / radius, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, -cone * r1 / radius, sin(a1) * r1)
			var u0 := r0 / radius
			var u1 := r1 / radius
			for e: Array in [[p00, u0, 0.0], [p10, u1, 0.0], [p11, u1, 1.0], [p00, u0, 0.0], [p11, u1, 1.0], [p01, u0, 1.0]]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(e[1], float(i + e[2]) / n))
				st.add_vertex(e[0])
	mi.mesh = st.commit()
	if not _meshes.has(key):
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled, unshaded;
uniform float alpha = 0.22;
void fragment() {
	float r = UV.x;
	float streak = 0.75 + 0.25 * sin(UV.y * 6.2832 * 3.0 + TIME * 2.0) * sin(UV.y * 6.2832 * 17.0);
	float tip = smoothstep(0.86, 0.98, r) * 0.6;
	ALBEDO = vec3(0.06) + vec3(tip * 0.5, tip * 0.45, 0.0);
	ALPHA = alpha * streak * smoothstep(0.1, 0.35, r) * (1.0 - smoothstep(0.985, 1.0, r)) + tip * alpha;
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("alpha", alpha)
		_meshes[key] = m
	mi.material_override = _meshes[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Blur"
	return mi
