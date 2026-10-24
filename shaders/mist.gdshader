shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// Ground mist (Atmosphere): a huge flat layer at valley level. Where the land
// rises above it, the depth test hides it; where the land falls away below it,
// the depth difference makes it thicker, so mist pools in the valleys on its
// own. Soft against the ground, clear near the camera, drifting slowly.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 mist_color : source_color = vec3(0.75, 0.75, 0.82);
uniform vec3 sun_color : source_color = vec3(1.0, 0.75, 0.65);
uniform vec3 sun_dir = vec3(0.0, 0.1, -1.0); // towards the sun
uniform float strength = 0.8;
uniform float thickness = 5.0; // m of land below the layer for full mist
uniform vec2 drift = vec2(0.6, 0.25); // m/s
uniform float seed = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene = -v.z / v.w;
	float here = -VERTEX.z;
	// How far the view ray travels under the layer before hitting the ground,
	// converted to height below the layer (thickness of mist along the ray).
	vec3 ray = normalize(wpos - CAMERA_POSITION_WORLD);
	float behind = max(scene - here, 0.0);
	float depth_below = behind * max(abs(ray.y), 0.04);
	float soft = smoothstep(0.0, thickness, depth_below) * smoothstep(0.0, 3.0, behind);
	float near = smoothstep(18.0, 70.0, here);
	float far = 1.0 - smoothstep(1800.0, 3200.0, here);
	vec2 p = wpos.xz + drift * TIME;
	float n = texture(noise_tex, p / 260.0 + seed).r * 0.65 + texture(noise_tex, p / 70.0 - seed * 0.7 + TIME * 0.002).r * 0.35;
	n = smoothstep(0.28, 0.72, n);
	float a = strength * soft * near * far * mix(0.35, 1.0, n);
	float fwd = pow(max(dot(ray, normalize(sun_dir)), 0.0), 6.0);
	ALBEDO = mist_color * (0.9 + 0.2 * n) + sun_color * fwd * 0.6;
	ALPHA = clamp(a, 0.0, 0.92);
}
