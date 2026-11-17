shader_type sky;
uniform vec4 top_color : source_color = vec4(0.24, 0.48, 0.76, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.78, 0.85, 0.9, 1.0);
uniform vec4 ground_color : source_color = vec4(0.39, 0.43, 0.47, 1.0);
uniform vec4 cloud_color : source_color = vec4(0.94, 0.95, 0.96, 1.0);
uniform vec3 sun_direction = vec3(0.4, 0.7, 0.4);
uniform vec4 sun_color : source_color = vec4(1.0, 0.94, 0.84, 1.0);
uniform float sun_radius = 0.015;
uniform float daylight = 1.0;
uniform float sky_energy = 1.0;
uniform float cloud_coverage = 0.3;
uniform float cloud_height = 1200.0;
uniform float cloud_scale = 900.0;
uniform float cloud_seed = 3.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void sky() {
	vec3 col = mix(horizon_color.rgb, top_color.rgb, pow(clamp(EYEDIR.y, 0.0, 1.0), 0.55));
	col = mix(col, ground_color.rgb, smoothstep(0.0, 0.4, -EYEDIR.y));
	float disk = smoothstep(cos(sun_radius * 1.2), cos(sun_radius), dot(EYEDIR, sun_direction));
	col += sun_color.rgb * disk * daylight * 6.0;
	float height_above_camera = cloud_height - POSITION.y;
	if (EYEDIR.y > 0.005 && cloud_coverage > 0.001 && height_above_camera > 0.0) {
		// A static, seeded horizontal cloud layer. Height is measured above world Y=0.
		vec2 p = (POSITION.xz + EYEDIR.xz * height_above_camera / max(EYEDIR.y, 0.02)) / cloud_scale + vec2(cloud_seed);
		float n = noise(p) * 0.57 + noise(p * 2.1) * 0.28 + noise(p * 4.3) * 0.15;
		float mask = smoothstep(1.0 - cloud_coverage, 1.18 - cloud_coverage, n) * smoothstep(0.005, 0.12, EYEDIR.y);
		col = mix(col, cloud_color.rgb * (0.8 + n * 0.2), mask);
	}
	COLOR = max(col * sky_energy, vec3(0.0));
}
