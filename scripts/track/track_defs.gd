class_name TrackDefs
extends RefCounted
## The circuits you can pick in the menu. Each is a closed loop of control
## points (metres, XZ plane) turned into a smooth spline by TrackBuilder.
## `start` is a point on the main straight where the start/finish line goes.

const ROAD_WIDTH := 12.0

const TRACKS: Array[Dictionary] = [
	{
		id = "kiefernring",
		name = "Kiefernring",
		hills = 14.0,
		weather = Weather.Kind.CLEAR,
		blurb = "1.9 km of pine forest. A long straight into a tight left, then flowing esses.",
		start = Vector3(0, 0, 60),
		points = [
			Vector3(0, 0, 200), Vector3(0, 0, -250), Vector3(40, 0, -320), Vector3(120, 0, -330),
			Vector3(170, 0, -280), Vector3(160, 0, -200), Vector3(220, 0, -140), Vector3(320, 0, -150),
			Vector3(380, 0, -90), Vector3(360, 0, 20), Vector3(280, 0, 60), Vector3(230, 0, 150),
			Vector3(260, 0, 250), Vector3(200, 0, 320), Vector3(90, 0, 330), Vector3(20, 0, 280),
		],
	},
	{
		id = "hochwald",
		name = "Hochwald",
		hills = 30.0,
		weather = Weather.Kind.CLEAR,
		blurb = "3.0 km of high-speed sweepers. Brave in the long corners, patient into the hairpin.",
		start = Vector3(0, 0, 150),
		points = [
			Vector3(0, 0, 300), Vector3(0, 0, -200), Vector3(60, 0, -380), Vector3(250, 0, -450),
			Vector3(480, 0, -400), Vector3(560, 0, -250), Vector3(500, 0, -80), Vector3(560, 0, 80),
			Vector3(700, 0, 160), Vector3(740, 0, 320), Vector3(640, 0, 440), Vector3(430, 0, 430),
			Vector3(320, 0, 320), Vector3(170, 0, 420), Vector3(50, 0, 420),
		],
	},
	{
		id = "valle_club",
		name = "Valle Club",
		hills = 20.0,
		weather = Weather.Kind.CLEAR,
		blurb = "1.3 km club circuit. Short straights, hairpins and a lot of braking.",
		start = Vector3(0, 0, 40),
		points = [
			Vector3(0, 0, 120), Vector3(0, 0, -120), Vector3(30, 0, -165), Vector3(95, 0, -155),
			Vector3(115, 0, -90), Vector3(170, 0, -60), Vector3(240, 0, -100), Vector3(295, 0, -60),
			Vector3(275, 0, 25), Vector3(205, 0, 45), Vector3(185, 0, 110), Vector3(235, 0, 170),
			Vector3(190, 0, 225), Vector3(90, 0, 215), Vector3(40, 0, 175),
		],
	},
	{
		id = "brackenmoor",
		name = "Brackenmoor",
		hills = 24.0,
		weather = Weather.Kind.STORM,
		blurb = "2.0 km across open moorland in a thunderstorm. Standing water, no grip, no mercy.",
		start = Vector3(0, 0, 120),
		points = [
			Vector3(0, 0, 220), Vector3(0, 0, -180), Vector3(35, 0, -260), Vector3(120, 0, -290),
			Vector3(210, 0, -250), Vector3(260, 0, -170), Vector3(350, 0, -140), Vector3(430, 0, -190),
			Vector3(500, 0, -150), Vector3(520, 0, -40), Vector3(460, 0, 40), Vector3(380, 0, 60),
			Vector3(340, 0, 140), Vector3(380, 0, 230), Vector3(320, 0, 300), Vector3(200, 0, 310),
			Vector3(110, 0, 270), Vector3(40, 0, 300),
		],
	},
	{
		id = "schneekopf",
		name = "Schneekopf",
		hills = 34.0,
		weather = Weather.Kind.SNOW,
		blurb = "1.5 km mountain circuit in a blizzard. Steep climbs, packed snow, pines to the edge.",
		start = Vector3(0, 0, 80),
		points = [
			Vector3(0, 0, 150), Vector3(0, 0, -120), Vector3(-30, 0, -200), Vector3(20, 0, -260),
			Vector3(110, 0, -250), Vector3(150, 0, -180), Vector3(120, 0, -100), Vector3(170, 0, -40),
			Vector3(260, 0, -60), Vector3(300, 0, 20), Vector3(260, 0, 110), Vector3(170, 0, 130),
			Vector3(130, 0, 210), Vector3(60, 0, 240), Vector3(10, 0, 210),
		],
	},
	{
		id = "kuestenstrasse",
		name = "Küstenstraße",
		theme = "coast",
		hills = 16.0,
		weather = Weather.Kind.GOLDEN,
		blurb = "2.9 km along the cliffs. Sea on your left, a lighthouse ahead, the harbour town below.",
		start = Vector3(0, 0, 60),
		points = [
			Vector3(0, 0, 210), Vector3(0, 0, -158), Vector3(-42, 0, -242), Vector3(-26, 0, -336),
			Vector3(68, 0, -410), Vector3(221, 0, -425), Vector3(332, 0, -373), Vector3(332, 0, -273),
			Vector3(408, 0, -200), Vector3(561, 0, -210), Vector3(680, 0, -147), Vector3(697, 0, -42),
			Vector3(595, 0, 32), Vector3(459, 0, 42), Vector3(374, 0, 116), Vector3(425, 0, 210),
			Vector3(544, 0, 273), Vector3(510, 0, 368), Vector3(357, 0, 420), Vector3(187, 0, 399),
			Vector3(85, 0, 336),
		],
	},
	{
		id = "altstadt",
		name = "Altstadt",
		theme = "town",
		hills = 7.0,
		weather = Weather.Kind.CLEAR,
		blurb = "2.1 km through the old town. Walls of houses, cobbled corners, no room for mistakes.",
		start = Vector3(0, 0, 120),
		points = [
			Vector3(0, 0, -120), Vector3(0, 0, -138), Vector3(9, 0, -159), Vector3(30, 0, -168),
			Vector3(48, 0, -168), Vector3(146, 0, -168), Vector3(243, 0, -168), Vector3(261, 0, -168),
			Vector3(282, 0, -159), Vector3(291, 0, -138), Vector3(291, 0, -120), Vector3(291, 0, -91),
			Vector3(291, 0, -73), Vector3(299, 0, -53), Vector3(319, 0, -45), Vector3(337, 0, -45),
			Vector3(424, 0, -45), Vector3(442, 0, -45), Vector3(463, 0, -37), Vector3(474, 0, -17),
			Vector3(476, 0, 1), Vector3(489, 0, 105), Vector3(491, 0, 123), Vector3(492, 0, 134),
			Vector3(490, 0, 145), Vector3(486, 0, 163), Vector3(480, 0, 184), Vector3(476, 0, 201),
			Vector3(465, 0, 218), Vector3(447, 0, 224), Vector3(429, 0, 224), Vector3(382, 0, 224),
			Vector3(364, 0, 224), Vector3(344, 0, 216), Vector3(336, 0, 196), Vector3(336, 0, 178),
			Vector3(336, 0, 169), Vector3(336, 0, 151), Vector3(328, 0, 131), Vector3(308, 0, 123),
			Vector3(290, 0, 123), Vector3(227, 0, 123), Vector3(209, 0, 123), Vector3(188, 0, 132),
			Vector3(179, 0, 153), Vector3(179, 0, 171), Vector3(179, 0, 231), Vector3(179, 0, 292),
			Vector3(179, 0, 310), Vector3(172, 0, 329), Vector3(153, 0, 339), Vector3(135, 0, 342),
			Vector3(54, 0, 352), Vector3(36, 0, 354), Vector3(11, 0, 346), Vector3(0, 0, 322),
			Vector3(0, 0, 304), Vector3(0, 0, 198), Vector3(0, 0, 92), Vector3(0, 0, -14),
		],
	},
	{
		id = "valtellina",
		name = "Autodromo di Valtellina",
		theme = "autodromo",
		hills = 20.0,
		weather = Weather.Kind.GOLDEN,
		blurb = "2.9 km of flat-out Italian autodromo. Long straights, fast sweepers, vineyards all around.",
		start = Vector3(0, 0, 150),
		points = [
			Vector3(0, 0, -330), Vector3(29, 0, -401), Vector3(100, 0, -430), Vector3(199, 0, -430),
			Vector3(298, 0, -430), Vector3(398, 0, -430), Vector3(497, 0, -430), Vector3(537, 0, -417),
			Vector3(563, 0, -384), Vector3(599, 0, -282), Vector3(614, 0, -252), Vector3(636, 0, -226),
			Vector3(697, 0, -166), Vector3(759, 0, -106), Vector3(792, 0, -55), Vector3(800, 0, 6),
			Vector3(793, 0, 93), Vector3(786, 0, 179), Vector3(761, 0, 230), Vector3(709, 0, 252),
			Vector3(626, 0, 255), Vector3(542, 0, 258), Vector3(508, 0, 274), Vector3(494, 0, 308),
			Vector3(494, 0, 372), Vector3(480, 0, 407), Vector3(446, 0, 422), Vector3(335, 0, 426),
			Vector3(225, 0, 431), Vector3(114, 0, 435), Vector3(34, 0, 405), Vector3(0, 0, 325),
			Vector3(0, 0, 216), Vector3(0, 0, 107), Vector3(0, 0, -2), Vector3(0, 0, -112),
			Vector3(0, 0, -221),
		],
	},
	{
		id = "capo_rosso",
		name = "Capo Rosso",
		theme = "mediterranean",
		hills = 12.0,
		weather = Weather.Kind.GOLDEN,
		blurb = "3.4 km Riviera hill circuit. Flat out along the harbour and through the fish market, up the terraces to a hilltop village, then down the cliffs past the lighthouse.",
		start = Vector3(120, 0, 336),
		sea = Vector2(0, 1),
		harbour_at = 0.71,
		beach_at = 0.42,
		headland_at = 0.05,
		## Big landforms: the hill the village sits on, and the cape.
		peaks = [[Vector3(-90, 58, -400), 330.0], [Vector3(560, 20, 120), 190.0]],
		## Theme anchors (nearest point of the lap): village street from..to,
		## the arch over the road, the market hall the road drives through.
		village = [Vector3(-250, 0, -390), Vector3(140, 0, -370)],
		arch_at = Vector3(-215, 0, -410),
		market_at = Vector3(-150, 0, 335),
		points = [
			Vector3(338, 0, 331), Vector3(0, 0, 338), Vector3(-270, 0, 331), Vector3(-446, 0, 297),
			Vector3(-540, 0, 202), Vector3(-554, 0, 81), Vector3(-500, 0, -14), Vector3(-405, 0, -27),
			Vector3(-338, 0, -108), Vector3(-378, 0, -216), Vector3(-338, 0, -324), Vector3(-230, 0, -405),
			Vector3(-108, 0, -432), Vector3(14, 0, -418), Vector3(122, 0, -378), Vector3(243, 0, -310),
			Vector3(351, 0, -189), Vector3(405, 0, -54), Vector3(513, 0, 27), Vector3(634, 0, 81),
			Vector3(675, 0, 189), Vector3(594, 0, 284), Vector3(473, 0, 324),
		],
	},
	{
		id = "herbstwald",
		name = "Herbstwald",
		theme = "autumn",
		hills = 9.0,
		terrain_shaper = "res://scripts/track/autumn_terrain.gd",
		fixed_heights = true, # point heights are the real profile (crests, a valley), land follows them
		weather = Weather.Kind.GOLDEN,
		blurb = "3.4 km through the autumn forest. A rock tunnel, flying crests, a hairpin, the old stone bridge and the sawmill.",
		start = Vector3(0, 20, 120),
		# River (XZ polyline, upstream first) crossed by the stone bridge.
		river = [Vector2(600, -150), Vector2(720, -60), Vector2(820, 30), Vector2(884, 84),
			Vector2(960, 130), Vector2(1080, 190), Vector2(1220, 290), Vector2(1400, 420)],
		river_levels = [8.2, 1.0], # water surface at source / mouth (5.5 at the bridge)
		# Raised land (x, z, radius, +height): the ridge the tunnel goes through.
		land_bumps = [Vector4(470, -405, 170, 42)],
		cut = [Vector2(330, -400), Vector2(610, -388)], # rock cut from / to (nearest track points)
		tunnel = [Vector2(430, -401), Vector2(515, -400)],
		points = [
			Vector3(0, 20, 330), Vector3(0, 20, 150), Vector3(0, 21, -30), Vector3(0, 23, -180),
			Vector3(30, 26, -290), Vector3(120, 31, -360), Vector3(240, 37, -392), Vector3(360, 42, -401),
			Vector3(470, 44, -401), Vector3(580, 43, -392), Vector3(680, 38, -365),
			Vector3(740, 39.4, -342), Vector3(790, 40.6, -323), Vector3(838, 39.4, -304.5), # crest 1 (dead straight: no sliding off when light)
			Vector3(895, 36.2, -283), Vector3(945, 35.9, -263.5), Vector3(982, 36.6, -249.5), Vector3(1020, 35.9, -235), # crest 2
			Vector3(1080, 32, -212), Vector3(1145, 27, -201), Vector3(1190, 25.5, -193), # brake for the hairpin
			Vector3(1214, 24.5, -172), Vector3(1203, 24, -147), Vector3(1166, 23, -136), # hairpin
			Vector3(1095, 20.5, -122), Vector3(1005, 16, -80), Vector3(935, 13, -5),
			Vector3(884, 11.5, 82), Vector3(835, 11.5, 155), # the stone bridge, then the sawmill
			Vector3(745, 12.5, 212), Vector3(625, 14, 232), Vector3(505, 19, 268), Vector3(405, 24.5, 330),
			Vector3(345, 27, 395), Vector3(305, 27.8, 438), Vector3(245, 25.6, 475), # crest by the lodge
			Vector3(125, 21, 482), Vector3(42, 20, 430),
		],
	},
	{
		id = "alpenpass",
		name = "Alpenpass",
		theme = "alpine",
		hills = 4.0,
		terrain_shaper = "res://scripts/track/alpine_terrain.gd",
		terrain = {bank = [1.5, 5.0], bowl = 0.0, relief = 3.0, design = 0.0}, # alpine_terrain.gd then cuts the walls / drops
		fixed_heights = true, # point heights are the real profile; the mountain follows them
		weather = Weather.Kind.CLEAR,
		blurb = "3.9 km mountain pass. Out of the village, over the gorge, four hairpins up the face, through the avalanche gallery and the summit tunnel, then flat out back down the valley.",
		start = Vector3(0, 21, 331),
		# Mountain behind the summit, ridges east and south, the bowl inside the loop the descent drops into.
		peaks = [[Vector3(80, 300, -700), 260.0], [Vector3(900, 240, -160), 230.0], [Vector3(-760, 220, -150), 220.0],
			[Vector3(-40, 150, 600), 220.0], [Vector3(560, 200, 560), 200.0]],
		land_bumps = [Vector4(-150, -200, 230, -50), Vector4(140, 120, 90, 28), Vector4(-140, -395, 70, 22),
			Vector4(150, -300, 120, -35), Vector4(-20, -300, 110, -35), Vector4(-380, -120, 110, -30), Vector4(-330, 60, 110, -28)],
		# The gorge (XZ polyline, upstream first) under the stone bridge; waterfall at its head.
		river = [Vector2(170, 150), Vector2(240, 178), Vector2(310, 196), Vector2(383, 205), Vector2(460, 212),
			Vector2(560, 205), Vector2(680, 190), Vector2(820, 200), Vector2(980, 230)],
		river_levels = [13.0, 2.0],
		gallery = [Vector2(150, -376), Vector2(25, -385)], # avalanche gallery (nearest lap points)
		cut = [Vector2(-40, -378), Vector2(-230, -392)], # rock cut either side of the summit tunnel
		tunnel = [Vector2(-95, -376), Vector2(-165, -379)],
		village = [Vector2(-160, 330), Vector2(230, 325)],
		points = [
			Vector3(-120, 20.0, 330), Vector3(40, 21.0, 332), Vector3(200, 21.9, 328), Vector3(310, 22.6, 300),
			Vector3(370, 23.1, 240), Vector3(395, 23.6, 170), Vector3(405, 27.3, 110), Vector3(440, 30.6, 70),
			Vector3(520, 35.7, 50), Vector3(620, 42.0, 40),
			Vector3(672, 45.2, 30), Vector3(692, 47.1, 8), Vector3(684, 48.8, -18), Vector3(655, 50.7, -30), # hairpin 1
			Vector3(560, 56.6, -40), Vector3(460, 62.9, -55),
			Vector3(410, 66.1, -65), Vector3(388, 68.1, -88), Vector3(398, 69.7, -113), Vector3(430, 71.8, -122), # hairpin 2
			Vector3(530, 78.0, -135), Vector3(620, 83.7, -150),
			Vector3(668, 86.7, -160), Vector3(688, 88.6, -183), Vector3(678, 90.3, -208), Vector3(648, 92.3, -218), # hairpin 3
			Vector3(550, 98.4, -232), Vector3(450, 104.7, -250), Vector3(370, 109.9, -275),
			Vector3(310, 111.4, -320), Vector3(230, 113.2, -360), Vector3(130, 115.2, -380), Vector3(20, 117.4, -385), # gallery
			Vector3(-80, 119.4, -375), Vector3(-180, 112.1, -380), # summit, tunnel
			Vector3(-290, 103.7, -410), Vector3(-410, 94.8, -385), Vector3(-490, 86.2, -300), Vector3(-490, 78.2, -190),
			Vector3(-540, 70.0, -90), Vector3(-560, 62.5, 10), Vector3(-510, 55.0, 100), Vector3(-420, 47.4, 150),
			Vector3(-370, 41.1, 220), Vector3(-300, 33.9, 290), Vector3(-220, 27.3, 330),
		],
	},
	{
		id = "hafenstadt",
		name = "Hafenstadt",
		theme = "harbour",
		street = true, # walled street circuit: concrete barriers, no gravel traps
		hills = 1.2,
		fixed_heights = true, # flat city; the elevated motorway section is in the profile
		terrain = {bank = [0.0, 0.0], bowl = 0.0, relief = 0.0, design = 0.0},
		terrain_shaper = "res://scripts/track/harbour_terrain.gd",
		weather = 4, # clear night: street lamps, lit windows, neon, port floodlights
		blurb = "3.5 km harbour street circuit at night. The waterfront, a drive-through warehouse, the container port, a rail crossing, the elevated motorway and a tunnel into neon downtown.",
		start = Vector3(-100, 0, 300),
		quay_z = 346.0, # the quay edge south of the waterfront straight; sea beyond
		points = [
			Vector3(328, 0.0, 300), Vector3(339, 0.0, 297), Vector3(347, 0.0, 289), Vector3(350, 0.0, 278), Vector3(350, 0.0, 220), Vector3(350, 0.0, 162),
			Vector3(350, 0.0, 104), Vector3(352, 0.0, 95), Vector3(357, 0.0, 87), Vector3(365, 0.0, 82), Vector3(374, 0.0, 80), Vector3(430, 0.0, 80),
			Vector3(485, 0.0, 80), Vector3(540, 0.0, 80), Vector3(596, 0.0, 80), Vector3(605, 0.0, 78), Vector3(613, 0.0, 73), Vector3(618, 0.0, 65),
			Vector3(620, 0.0, 56), Vector3(620, 0.0, 0), Vector3(620, 0.0, -56), Vector3(620, 0.0, -113), Vector3(620, 0.6, -169), Vector3(619, 0.7, -179),
			Vector3(615, 0.9, -189), Vector3(608, 1.2, -197), Vector3(600, 1.6, -204), Vector3(590, 2.1, -208), Vector3(545, 4.3, -219), Vector3(500, 5.5, -230),
			Vector3(454, 5.9, -241), Vector3(409, 6.8, -253), Vector3(364, 7.8, -264), Vector3(319, 8.4, -275), Vector3(310, 8.5, -277), Vector3(300, 8.5, -279),
			Vector3(290, 8.5, -280), Vector3(280, 8.5, -280), Vector3(233, 8.5, -280), Vector3(186, 8.5, -280), Vector3(139, 8.5, -280), Vector3(93, 8.5, -280),
			Vector3(46, 8.5, -280), Vector3(-1, 8.5, -280), Vector3(-48, 8.5, -280), Vector3(-95, 8.5, -280), Vector3(-142, 8.5, -280), Vector3(-150, 8.5, -280),
			Vector3(-158, 8.5, -279), Vector3(-204, 7.6, -274), Vector3(-250, 6.1, -269), Vector3(-296, 4.7, -264), Vector3(-342, 4.0, -259), Vector3(-388, 3.1, -254),
			Vector3(-398, 2.7, -251), Vector3(-407, 2.3, -245), Vector3(-414, 1.9, -238), Vector3(-418, 1.5, -228), Vector3(-420, 1.2, -218), Vector3(-420, 0.3, -173),
			Vector3(-420, 0.0, -127), Vector3(-420, 0.0, -82), Vector3(-417, 0.0, -71), Vector3(-409, 0.0, -63), Vector3(-398, 0.0, -60), Vector3(-340, 0.0, -60),
			Vector3(-282, 0.0, -60), Vector3(-271, 0.0, -57), Vector3(-263, 0.0, -49), Vector3(-260, 0.0, -38), Vector3(-260, 0.0, 7), Vector3(-260, 0.0, 53),
			Vector3(-260, 0.0, 98), Vector3(-263, 0.0, 109), Vector3(-271, 0.0, 117), Vector3(-282, 0.0, 120), Vector3(-340, 0.0, 120), Vector3(-398, 0.0, 120),
			Vector3(-456, 0.0, 120), Vector3(-465, 0.0, 122), Vector3(-473, 0.0, 127), Vector3(-478, 0.0, 135), Vector3(-480, 0.0, 144), Vector3(-480, 0.0, 210),
			Vector3(-480, 0.0, 276), Vector3(-478, 0.0, 285), Vector3(-473, 0.0, 293), Vector3(-465, 0.0, 298), Vector3(-456, 0.0, 300), Vector3(-410, 0.0, 300),
			Vector3(-364, 0.0, 300), Vector3(-318, 0.0, 300), Vector3(-272, 0.0, 300), Vector3(-225, 0.0, 300), Vector3(-179, 0.0, 300), Vector3(-133, 0.0, 300),
			Vector3(-87, 0.0, 300), Vector3(-41, 0.0, 300), Vector3(5, 0.0, 300), Vector3(51, 0.0, 300), Vector3(97, 0.0, 300), Vector3(144, 0.0, 300),
			Vector3(190, 0.0, 300), Vector3(236, 0.0, 300), Vector3(282, 0.0, 300)
		],
	},
]


static func get_track(id: String) -> Dictionary:
	for t in TRACKS:
		if t.id == id:
			return t
	return TRACKS[0]
