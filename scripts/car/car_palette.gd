class_name CarPalette
extends RefCounted
## Period-correct paint colours for the field (muted, like real 70s/80s cars).

const COLORS: Array[Color] = [
	Color(0.48, 0.045, 0.035), # Signal Red
	Color(0.78, 0.78, 0.74), # Pearl White
	Color(0.035, 0.035, 0.04), # Black
	Color(0.42, 0.43, 0.44), # Silver metallic
	Color(0.06, 0.16, 0.1), # Forest Green metallic
	Color(0.05, 0.09, 0.2), # Midnight Blue
	Color(0.62, 0.48, 0.1), # Mustard Yellow, muted
	Color(0.28, 0.14, 0.07), # Copper Brown metallic
	Color(0.5, 0.2, 0.05), # Burnt Orange, muted
	Color(0.2, 0.22, 0.24), # Slate Grey
]


static func pick(slot: int) -> Color:
	return COLORS[slot % COLORS.size()]
