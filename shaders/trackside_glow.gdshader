shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

// Additive camera-facing glows (TracksideKit): flare heads and campfires that
// flicker, photographers' camera flashes that pop now and then.
// COLOR = light colour; INSTANCE_CUSTOM = (phase, size, kind 0 flicker / 1 flash, energy).

varying vec4 tint;
varying float kind;
varying float k;
varying float energy;

float hash(float x) { return fract(sin(x * 91.17) * 43758.5453); }

void vertex() {
	float ph = INSTANCE_CUSTOM.r;
	kind = INSTANCE_CUSTOM.b;
	tint = COLOR;
	energy = INSTANCE_CUSTOM.a;
	float size = INSTANCE_CUSTOM.g;
	if (kind < 0.5) {
		k = 0.75 + 0.25 * sin(TIME * 23.0 + ph * 40.0) * sin(TIME * 7.3 + ph * 11.0);
		size *= mix(0.85, 1.1, k);
	} else {
		// a burst of 2-3 frames every few seconds, at random
		float slot = floor(TIME * 2.2 + ph * 13.0);
		float f = fract(TIME * 2.2 + ph * 13.0);
		k = step(0.72, hash(slot + ph * 37.0)) * (1.0 - smoothstep(0.0, 0.16, f));
		size *= k;
	}
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	c += normalize(-c) * 0.3; // stay in front of the head / logs
	VERTEX = c + vec3(VERTEX.xy * size, 0.0);
}

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float core = exp(-d * d * 9.0);
	float halo = exp(-d * d * 2.5) * 0.35;
	ALBEDO = tint.rgb * (core + halo) * k * energy;
}
