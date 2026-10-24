// Live weather, set every frame by Weather / WeatherCycle (project.godot [shader_globals]).
// Materials keep their own build-time uniforms; take max(uniform, global) so a
// fixed preset and changeable weather both work without touching any material.
global uniform float wx_wet;      // 0 dry .. 1 soaked (lags behind the rain, dries slowly)
global uniform float wx_wet_line; // wetness on the racing line (dries first)
global uniform float wx_snow;     // 0 none .. 1 snow cover
global uniform float wx_rain;     // falling rain 0..1
global uniform float wx_wind;     // 0 calm .. 1 storm

// Travelling gusts: fronts that roll downwind (WX_DIR, the same wind direction
// the vegetation uses) faster and stronger as wx_wind rises. 0 calm .. 1 in a
// gust front. Pass TIME. Atmosphere.gust() is the same function on the CPU.
const vec2 WX_DIR = vec2(0.9246, 0.3807); // normalize(0.85, 0.35)
float wx_gust(vec2 xz, float t) {
	float spd = 4.0 + 10.0 * wx_wind;
	float a = dot(xz, WX_DIR) - t * spd;
	float b = dot(xz, vec2(-WX_DIR.y, WX_DIR.x));
	float g1 = sin(a * 0.045 + sin(b * 0.013) * 2.0) * 0.5 + 0.5;
	float g2 = sin(a * 0.11 + b * 0.021 + 1.7) * 0.5 + 0.5;
	return smoothstep(0.5, 1.0, g1 * 0.7 + g2 * 0.3) * (0.35 + 0.65 * smoothstep(0.1, 0.6, wx_wind));
}
