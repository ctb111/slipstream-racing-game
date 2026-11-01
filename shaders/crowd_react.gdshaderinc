// Crowd reactions, pushed every frame by CrowdReact (scripts/world/crowd_react.gd,
// project.godot [shader_globals]). No per-instance writes: each figure / flare
// measures its own distance to these points.
global uniform vec4 crowd_hot0; // xyz = hotspot (leader, player, battle; lagging the car), w = 0..1
global uniform vec4 crowd_hot1;
global uniform vec4 crowd_hot2;
global uniform vec4 crowd_hot3;
global uniform vec4 marshal_yellow0; // xyz = centre of the yellow sector, w = 0..1 (ramped)
global uniform vec4 marshal_yellow1;
global uniform vec4 marshal_chequer; // xyz = finish line, w = 0..1 (final lap / finish)

float crowd_hot_one(vec3 p, vec4 h) {
	return h.w * smoothstep(85.0, 25.0, distance(p, h.xyz));
}

// 0 calm .. 1 the cars that matter are right here.
float crowd_hype(vec3 p) {
	return max(max(crowd_hot_one(p, crowd_hot0), crowd_hot_one(p, crowd_hot1)),
		max(crowd_hot_one(p, crowd_hot2), crowd_hot_one(p, crowd_hot3)));
}

// 0 .. 1: an incident in this marshal's sector.
float marshal_yellow(vec3 p) {
	return max(marshal_yellow0.w * step(distance(p, marshal_yellow0.xyz), 85.0),
		marshal_yellow1.w * step(distance(p, marshal_yellow1.xyz), 85.0));
}
