shader_type fog;
uniform float density : hint_range(0.0, 1.0) = 0.14;
uniform vec4 cloud_color : source_color = vec4(0.82, 0.87, 0.82, 1.0);

float hash_cloud(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float cloud_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash_cloud(cell), hash_cloud(cell + vec3(1,0,0)), f.x),
		mix(hash_cloud(cell + vec3(0,1,0)), hash_cloud(cell + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash_cloud(cell + vec3(0,0,1)), hash_cloud(cell + vec3(1,0,1)), f.x),
		mix(hash_cloud(cell + vec3(0,1,1)), hash_cloud(cell + vec3(1,1,1)), f.x), f.y), f.z);
}

void fog() {
	vec3 p = WORLD_POSITION * vec3(0.13, 0.014, 0.13)
		+ vec3(TIME * 0.003, 0.0, TIME * 0.0018);
	float billow = cloud_noise(p) * 0.65 + cloud_noise(p * 2.1 + 8.7) * 0.35;
	float cloud = smoothstep(0.32, 0.7, billow);
	// Clamp the top below the playable deck, while engulfing the thick island base.
	float height_mask = smoothstep(0.35, 3.0, -WORLD_POSITION.y + (cloud - 0.5) * 0.6);
	DENSITY = density * height_mask * mix(0.05, 2.2, cloud);
	ALBEDO = cloud_color.rgb * mix(0.6, 1.0, cloud);
	EMISSION = cloud_color.rgb * mix(0.25, 1.25, cloud);
}
