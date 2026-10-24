class_name CarCatalog
extends RefCounted
## Every drivable car: where its model lives, how to read it (which materials
## are wheels / paint / lamps, which way it faces, how long the real car is),
## who made it, and a physics preset that roughly matches the real thing.
##
## Model fields (used by CarModel):
##   path         glb under res://assets/cars
##   length       real overall length, metres (the model is scaled to it)
##   forward      axis the SOURCE model's nose points along (we rotate it to -Z)
##   skip         materials to drop (ground planes, contact shadows)
##   wheel_mats   materials that spin with the wheels; split into 4 corners by quadrant
##   rim_mat      round part used to find each hub centre (tyres are often squashed)
##   tire_mat     used for radius (top of tyre) and width
##   paint_mats   merged into one recolourable surface, key "paint"
##   lights_mat   headlamp material (front half keeps this key; car.gd lights it)
##   brake_mats   rear lamp materials; their rear half becomes the "brake" surface
##
## Physics preset keys are named exactly like Car's properties so car.gd can
## apply them with `set(key, value)`. torque_rpm / torque_nm replace Car's
## TORQUE_RPM / TORQUE_NM curve (those are consts today, need to become vars).
## drivetrain: "RWD" / "FWD" / "AWD".
## Torque figures are real-world x1.3 for arcade punch (same as the tuned Porsche).
##
## engine (optional): synthesis parameters for CarAudio, overriding
## CarAudio.ENGINE_DEFAULTS (documented there). Cars sharing an engine `type`
## share one synthesised sound bank.

const DEFAULT := "porsche930"

static var CARS := {
	"porsche930": {
		name = "Porsche 911 Turbo (930)", year = 1975,
		path = "res://assets/cars/porsche930.glb",
		credit = "\"FREE 1975 Porsche 911 (930) Turbo\" by Lionsharp Studios (sketchfab.com/lionsharp), CC BY 4.0",
		length = 4.29, forward = Vector3(0, 0, 1),
		skip = ["DefaultMaterial", "Material.001"],
		wheel_mats = ["930_rim", "930_tire"], rim_mat = "930_rim", tire_mat = "930_tire",
		paint_mats = ["paint"], lights_mat = "930_lights", brake_mats = ["930_lights"],
		paint_color = Color(0.48, 0.045, 0.035),
		engine = {
			# Air-cooled 3.0 flat-six turbo: uneven header lengths give the boxer
			# burble (1.5 order), belt-driven cooling-fan whine, laggy KKK turbo.
			type = "flat6_930", thump = 0.75, cylinders = 6,
			firing_irregularity = 0.09, cyl_variation = 0.16, pulse_jitter = 0.07, bank_split = 1.06,
			exhaust_resonance_hz = [140.0, 380.0], resonance2 = 0.55, pulse_decay = 1.15,
			harmonics = [[1.5, 0.22], [3.0, 0.5], [4.5, 0.06], [6.0, 0.12]],
			induction_noise = 0.12, induction_hz = 850.0, induction_tone = 0.2,
			grit = 0.55, mech_order = 19.8, mech_level = 0.035,
			brightness = [850.0, 3000.0], drive = 1.7,
			turbo = true, turbo_pitch = 2900.0, turbo_whoosh = 0.45, turbo_level = 0.26,
			spool_rpm = 3200.0, spool_span = 2600.0, spool_rate = 1.6, blowoff = "bov",
			backfire_rate = 1.2, pop_hz = 95.0, pop_crack = 0.5, pop_cluster = 2, limiter_hz = 14.0,
		},
		physics = {
			drivetrain = "RWD", car_mass = 1300.0, com_offset = Vector3(0.0, -0.2, 0.25),
			idle_rpm = 900.0, redline_rpm = 7000.0,
			gear_ratios = PackedFloat32Array([3.18, 2.06, 1.49, 1.16, 0.92]), final_drive = 3.9,
			torque_rpm = [1000.0, 2000.0, 3000.0, 4000.0, 5000.0, 6000.0, 7000.0],
			torque_nm = [330.0, 400.0, 470.0, 530.0, 545.0, 515.0, 440.0],
			drag_coef = 0.40, downforce_coef = 0.25, brake_force = 23000.0, tire_grip = 1.4,
			top_speed_kmh = 250,
		},
	},
	"bmw_e30_m3": {
		name = "BMW M3 (E30)", year = 1986,
		path = "res://assets/cars/bmw_e30_m3.glb",
		credit = "\"[FREE] BMW M3 E30\" by Martin Trafas (sketchfab.com/TinoD2), CC BY 4.0",
		length = 4.345, forward = Vector3(0, 0, 1),
		skip = ["Logo_Plane"],
		wheel_mats = ["BMW_E30_M3_RIM", "BMW_E30_M3_TIRE", "Brake_Disc"],
		rim_mat = "BMW_E30_M3_RIM", tire_mat = "BMW_E30_M3_TIRE",
		paint_mats = ["BMW_E30_M3_PAINT"], lights_mat = "BMW_E30_M3_LENS",
		brake_mats = ["BMW_E30_M3_LENS", "BMW_E30_M3_TAILLIGHT_REFLECTOR"],
		paint_color = Color(0.72, 0.72, 0.70), # Alpine White
		engine = {
			# S14 2.3 inline-four, individual throttle bodies: crisp, raspy intake, loves revs.
			type = "i4_s14", thump = 0.5, cylinders = 4,
			firing_irregularity = 0.015, cyl_variation = 0.07, pulse_jitter = 0.05,
			exhaust_resonance_hz = [230.0, 680.0], resonance2 = 0.45, resonance2_ratio = 2.6, pulse_decay = 0.9,
			attack = 0.00025, harmonics = [[1.0, 0.04], [2.0, 0.42], [4.0, 0.18], [6.0, 0.06]],
			induction_noise = 0.6, induction_hz = 1900.0, induction_tone = 0.15,
			grit = 0.7, grit_hz = 4500.0, brightness = [1400.0, 5200.0], drive = 1.9,
			backfire_rate = 0.3, pop_hz = 130.0, pop_cluster = 1, limiter_hz = 20.0,
		},
		physics = {
			# S14 2.3 16v, 200 PS; light, front-engined, revvy
			drivetrain = "RWD", car_mass = 1200.0, com_offset = Vector3(0.0, -0.22, -0.05),
			idle_rpm = 900.0, redline_rpm = 7250.0,
			gear_ratios = PackedFloat32Array([3.72, 2.40, 1.77, 1.26, 1.00]), final_drive = 4.10,
			torque_rpm = [1000.0, 2000.0, 3000.0, 4000.0, 5000.0, 6000.0, 7250.0],
			torque_nm = [195.0, 240.5, 273.0, 299.0, 312.0, 301.6, 260.0],
			drag_coef = 0.36, downforce_coef = 0.15, brake_force = 21000.0, tire_grip = 1.45,
			top_speed_kmh = 235,
		},
	},
	"datsun_240k": {
		name = "Datsun 240K GT", year = 1972,
		path = "res://assets/cars/datsun_240k.glb",
		credit = "\"(FREE) 1972 Datsun 240k GT\" by Lionsharp Studios / Karol Miklas (sketchfab.com/lionsharp), CC BY-SA 4.0",
		length = 4.46, forward = Vector3(0, 0, 1),
		skip = [],
		wheel_mats = ["alloy", "tire"], rim_mat = "alloy", tire_mat = "tire",
		paint_mats = ["paint"], lights_mat = "headlights", brake_mats = ["red_glass"],
		paint_color = Color(0.55, 0.36, 0.08), # 70s ochre
		engine = {
			# L24 2.4 straight-six on twin SU carbs: smooth, warm, a hollow intake honk.
			type = "i6_l24", thump = 0.85, cylinders = 6,
			firing_irregularity = 0.012, cyl_variation = 0.05, pulse_jitter = 0.04,
			exhaust_resonance_hz = [120.0, 340.0], resonance2 = 0.35, resonance2_ratio = 2.05, pulse_decay = 1.3,
			attack = 0.0006, harmonics = [[3.0, 0.5], [6.0, 0.14], [1.5, 0.04]],
			induction_noise = 0.45, induction_hz = 420.0, induction_tone = 0.75,
			grit = 0.3, grit_hz = 2500.0, brightness = [750.0, 2300.0], drive = 1.3,
			backfire_rate = 0.25, pop_hz = 90.0, pop_crack = 0.3, pop_cluster = 1, limiter_hz = 12.0,
		},
		physics = {
			# L24 2.4 straight-six, ~130 PS; heavy nose, softer
			drivetrain = "RWD", car_mass = 1200.0, com_offset = Vector3(0.0, -0.18, -0.08),
			idle_rpm = 800.0, redline_rpm = 6500.0,
			gear_ratios = PackedFloat32Array([3.38, 2.01, 1.31, 1.00, 0.85]), final_drive = 3.90,
			torque_rpm = [1000.0, 2000.0, 3000.0, 4000.0, 5000.0, 6000.0, 6500.0],
			torque_nm = [195.0, 227.5, 247.0, 257.4, 247.0, 221.0, 201.5],
			drag_coef = 0.42, downforce_coef = 0.05, brake_force = 19500.0, tire_grip = 1.3,
			spring_front = 30000.0, spring_rear = 32000.0,
			top_speed_kmh = 190,
		},
	},
	"toyota_ae86": {
		name = "Toyota Sprinter Trueno (AE86)", year = 1983,
		path = "res://assets/cars/toyota_ae86.glb",
		credit = "\"Japanese Touge Racer - Initial D spec\" (now \"Tiara GT '83 Tuned - Low poly model\") by Daniel Zhabotinsky (sketchfab.com/DanielZhabotinsky), CC BY 4.0",
		length = 4.205, forward = Vector3(-1, 0, 0),
		skip = [],
		wheel_mats = ["ae_rim_colour", "ae_tier", "brakes_1s"], rim_mat = "ae_rim_colour", tire_mat = "ae_tier",
		paint_mats = ["ae_body"], lights_mat = "ae_headlights", brake_mats = ["ae_headlights"],
		paint_color = Color(0.75, 0.75, 0.73), # panda white
		engine = {
			# 4A-GE 1.6 twin-cam: light, buzzy, screams to 7600; the T-VIS second
			# intake runners open at ~4400 rpm and the note hardens ("cam change").
			type = "i4_4age", thump = 0.45, cylinders = 4,
			firing_irregularity = 0.02, cyl_variation = 0.08, pulse_jitter = 0.05,
			exhaust_resonance_hz = [270.0, 820.0], resonance2 = 0.5, resonance2_ratio = 2.45, pulse_decay = 0.8,
			attack = 0.0002, harmonics = [[2.0, 0.34], [4.0, 0.22], [6.0, 0.1]],
			induction_noise = 0.4, induction_hz = 1350.0, induction_tone = 0.3,
			grit = 0.6, grit_hz = 5000.0, mech_order = 24.0, mech_level = 0.02,
			brightness = [1300.0, 5200.0], drive = 1.8,
			rpm_points = [1150.0, 2800.0, 4200.0, 4650.0, 7100.0],
			cam_rpm = 4420.0, cam_bright = 1.4, cam_induction = 1.8,
			backfire_rate = 0.3, pop_hz = 140.0, pop_cluster = 1, limiter_hz = 22.0,
		},
		physics = {
			# 4A-GE 1.6 twin-cam, 130 PS; very light, loves to rev and slide
			drivetrain = "RWD", car_mass = 950.0, com_offset = Vector3(0.0, -0.2, -0.05),
			idle_rpm = 900.0, redline_rpm = 7600.0,
			gear_ratios = PackedFloat32Array([3.59, 2.02, 1.38, 1.00, 0.86]), final_drive = 4.30,
			torque_rpm = [1000.0, 2000.0, 3000.0, 4000.0, 5000.0, 6000.0, 7600.0],
			torque_nm = [123.5, 149.5, 166.4, 182.0, 191.1, 193.7, 166.4],
			drag_coef = 0.38, downforce_coef = 0.05, brake_force = 16500.0, tire_grip = 1.3,
			spring_front = 26000.0, spring_rear = 28000.0, drift_rear_grip = 0.66,
			top_speed_kmh = 195,
		},
	},
	"mazda_rx7_fc": {
		name = "Mazda RX-7 (FC)", year = 1986,
		path = "res://assets/cars/mazda_rx7_fc.glb",
		credit = "\"Mazda RX-7 FC\" by Lexyc16 (sketchfab.com/Lexyc16), CC BY 4.0",
		length = 4.29, forward = Vector3(0, 0, 1),
		skip = ["Material.010"],
		wheel_mats = ["Material.005", "Material.006"], rim_mat = "Material.005", tire_mat = "Material.006",
		paint_mats = ["Material"], lights_mat = "Material.012", brake_mats = ["Material.015"],
		paint_color = Color(0.05, 0.12, 0.30), # deep blue
		engine = {
			# 13B twin-rotor turbo: each rotor fires once per eccentric-shaft turn
			# (2 pulses/rev), abrupt exhaust port = buzzy step; lumpy "brap" idle,
			# lots of overrun pops.
			type = "rotary_13b", thump = 0.3, cylinders = 2, rotary = true,
			firing_irregularity = 0.0, cyl_variation = 0.06, pulse_jitter = 0.1,
			exhaust_resonance_hz = [320.0, 950.0], resonance2 = 0.35, resonance2_ratio = 3.1, pulse_decay = 0.7,
			attack = 0.00005, saw = 0.9, saw_decay = 0.45,
			harmonics = [[2.0, 0.4], [4.0, 0.24], [6.0, 0.14], [8.0, 0.07]],
			induction_noise = 0.25, induction_hz = 1100.0, induction_tone = 0.2,
			grit = 0.45, grit_hz = 4000.0, lope = 0.55,
			brightness = [1600.0, 5400.0], drive = 2.0, overrun_level = 0.6,
			turbo = true, turbo_pitch = 3600.0, turbo_whoosh = 0.35, turbo_level = 0.2,
			spool_rpm = 2800.0, spool_span = 2800.0, spool_rate = 2.8, blowoff = "soft",
			backfire_rate = 4.0, pop_min = 0.4, pop_hz = 120.0, pop_crack = 0.9, pop_cluster = 3, limiter_hz = 18.0,
		},
		physics = {
			# 13B turbo rotary, 185 PS; near 50:50, smooth and high-revving
			drivetrain = "RWD", car_mass = 1280.0, com_offset = Vector3(0.0, -0.22, 0.0),
			idle_rpm = 850.0, redline_rpm = 7500.0,
			gear_ratios = PackedFloat32Array([3.48, 2.00, 1.37, 1.00, 0.76]), final_drive = 4.10,
			torque_rpm = [1000.0, 2000.0, 3000.0, 4000.0, 5000.0, 6000.0, 7500.0],
			torque_nm = [182.0, 260.0, 318.5, 325.0, 318.5, 299.0, 247.0],
			drag_coef = 0.33, downforce_coef = 0.12, brake_force = 22500.0, tire_grip = 1.4,
			top_speed_kmh = 240,
		},
	},
	"ferrari_f40": {
		name = "Ferrari F40", year = 1987,
		path = "res://assets/cars/ferrari_f40.glb",
		credit = "\"Ferrari f40\" by Black Snow (sketchfab.com/BlackSnow02), CC BY 4.0 (mesh simplified)",
		length = 4.358, forward = Vector3(0, 0, 1),
		skip = [],
		wheel_mats = ["F40_Rrims", "Scene_-_Root.002", "F40_Brake"], rim_mat = "F40_Rrims", tire_mat = "Scene_-_Root.002",
		paint_mats = ["material"], lights_mat = "super_headlight", brake_mats = ["super_brakelight"],
		paint_color = Color(0.55, 0.02, 0.02), # Rosso Corsa
		engine = {
			# 2.9 twin-turbo flat-plane V8: even 90-degree firing alternating banks,
			# harsh 4th-order scream, hard IHI spool, wastegate chatter and crackle on lift.
			type = "v8_f40", thump = 0.55, cylinders = 8,
			firing_irregularity = 0.03, cyl_variation = 0.07, pulse_jitter = 0.06, bank_split = 1.09,
			exhaust_resonance_hz = [240.0, 720.0], resonance2 = 0.6, resonance2_ratio = 2.2, pulse_decay = 1.0,
			attack = 0.0002, harmonics = [[2.0, 0.08], [4.0, 0.42], [8.0, 0.16], [12.0, 0.05]],
			induction_noise = 0.3, induction_hz = 2200.0, induction_tone = 0.1,
			grit = 0.75, grit_hz = 5000.0, brightness = [1600.0, 5600.0], drive = 2.1, volume_db = 1.0,
			turbo = true, turbo_pitch = 3200.0, turbo_whoosh = 0.5, turbo_level = 0.32,
			spool_rpm = 3300.0, spool_span = 2500.0, spool_rate = 3.0, blowoff = "wastegate",
			backfire_rate = 2.5, pop_min = 0.5, pop_hz = 105.0, pop_crack = 0.8, pop_cluster = 3, limiter_hz = 16.0,
		},
		physics = {
			# 2.9 twin-turbo V8, 478 PS, 1250 kg wet; mid-engined, turbo kick, big aero
			drivetrain = "RWD", car_mass = 1250.0, com_offset = Vector3(0.0, -0.28, 0.2),
			idle_rpm = 1000.0, redline_rpm = 7750.0,
			gear_ratios = PackedFloat32Array([2.77, 1.72, 1.23, 0.96, 0.77]), final_drive = 3.9,
			torque_rpm = [1000.0, 2000.0, 3000.0, 4000.0, 5000.0, 6000.0, 7750.0],
			torque_nm = [338.0, 468.0, 676.0, 750.1, 728.0, 676.0, 572.0],
			drag_coef = 0.34, downforce_coef = 0.45, brake_force = 24000.0, tire_grip = 1.55,
			top_speed_kmh = 320,
		},
	},
}


static func ids() -> Array:
	return CARS.keys()


static func has(id: String) -> bool:
	return CARS.has(id)


## The whole catalog entry (model + credit + physics). Unknown ids fall back to the default car.
static func get_car(id: String) -> Dictionary:
	return CARS.get(id, CARS[DEFAULT])


static func physics(id: String) -> Dictionary:
	return get_car(id).physics


static func display_name(id: String) -> String:
	var c := get_car(id)
	return "%s (%d)" % [c.name, c.year]


## Only cars whose glb is actually present.
static func available_ids() -> Array:
	return CARS.keys().filter(func(k): return ResourceLoader.exists(CARS[k].path))
