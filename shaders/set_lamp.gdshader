shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Emissive lamps (mast beacons, floodlights). COLOR = light colour,
// UV.x = 1 blinks, UV.y = blink phase.
uniform float energy = 3.0;

void fragment() {
	float blink = mix(1.0, step(0.5, fract(TIME * 0.75 + UV.y)), UV.x);
	ALBEDO = COLOR.rgb * energy * mix(0.06, 1.0, blink);
}
