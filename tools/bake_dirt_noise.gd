extends SceneTree
## Bakes the tileable noise used by shaders/car_dirt*.gdshader into
## assets/textures/car_dirt/dirt_noise.png (RGBA8, 512², truly periodic):
##   R  soft domain-warped fbm: large dirt blotches / coverage fronts
##   G  Worley F1 distance (0 = drop centre, ~1 = cell edge): splatter, water beads
##   B  fine fbm grain: film breakup, streak source
##   A  random value per G cell: drop size / on-off / phase
## Run: godot --headless --path . --script res://tools/bake_dirt_noise.gd

const SIZE := 512
const CELLS := 28

var _grad := {} ## lattice point (with period) -> gradient
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	_rng.seed = 1234
	var pts := PackedVector2Array()
	var vals := PackedFloat32Array()
	for i in CELLS * CELLS:
		pts.append(Vector2(_rng.randf_range(0.05, 0.95), _rng.randf_range(0.05, 0.95)))
		vals.append(_rng.randf())
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var u := Vector2(x, y) / SIZE
			# Warped fbm (period 1 in u).
			var w := Vector2(_fbm(u * 3.0 + Vector2(5.2, 1.3), 3, 3, 0.5), _fbm(u * 3.0 + Vector2(1.7, 9.2), 3, 3, 0.5))
			var r := _fbm(u * 4.0 + w * 0.35, 4, 6, 0.55)
			var b := _fbm(u * 48.0, 48, 3, 0.5)
			# Worley F1, wrapped.
			var c := u * CELLS
			var ci := Vector2i(floori(c.x), floori(c.y))
			var best := 9.0
			var bv := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n := ci + Vector2i(dx, dy)
					var k := posmod(n.y, CELLS) * CELLS + posmod(n.x, CELLS)
					var d := (Vector2(n) + pts[k] - c).length()
					if d < best:
						best = d
						bv = vals[k]
			out.set_pixel(x, y, Color(clampf(r * 0.62 + 0.5, 0, 1), clampf(best / 0.75, 0, 1),
				clampf(b * 0.75 + 0.5, 0, 1), bv))
	var path := "res://assets/textures/car_dirt/dirt_noise.png"
	print(out.save_png(path), " saved ", path, " in ", Time.get_ticks_msec() - t0, " ms")
	quit()


## Periodic fbm: p in lattice units, `period` lattice cells per tile at octave 0.
func _fbm(p: Vector2, period: int, octaves: int, gain: float) -> float:
	var s := 0.0
	var a := 1.0
	var norm := 0.0
	for o in octaves:
		s += _perlin(p, period) * a
		norm += a
		a *= gain
		p *= 2.0
		period *= 2
	return s / norm * 1.6


func _g(ix: int, iy: int, period: int) -> Vector2:
	var key := Vector3i(posmod(ix, period), posmod(iy, period), period)
	if not _grad.has(key):
		var ang := _rng.randf() * TAU
		_grad[key] = Vector2(cos(ang), sin(ang))
	return _grad[key]


func _perlin(p: Vector2, period: int) -> float:
	var i := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(i)
	var u := f * f * f * (f * (f * 6.0 - Vector2(15, 15)) + Vector2(10, 10))
	var a := _g(i.x, i.y, period).dot(f)
	var b := _g(i.x + 1, i.y, period).dot(f - Vector2(1, 0))
	var c := _g(i.x, i.y + 1, period).dot(f - Vector2(0, 1))
	var d := _g(i.x + 1, i.y + 1, period).dot(f - Vector2(1, 1))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)
