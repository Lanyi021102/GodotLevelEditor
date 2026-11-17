shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.67, 0.67, 0.67, 1.0);
uniform vec4 major_color : source_color = vec4(0.97, 0.97, 0.95, 1.0);
uniform vec4 half_color : source_color = vec4(0.90, 0.90, 0.88, 0.80);
uniform vec4 minor_color : source_color = vec4(0.87, 0.87, 0.85, 0.38);
// All spacing and line widths are in metres, independent of UVs and node scale.
uniform float major_spacing : hint_range(0.1, 10.0, 0.1) = 1.0;
uniform float half_spacing : hint_range(0.05, 5.0, 0.05) = 0.5;
uniform float minor_spacing : hint_range(0.01, 1.0, 0.01) = 0.1;
uniform float major_width : hint_range(0.001, 0.05, 0.001) = 0.014;
uniform float half_width : hint_range(0.001, 0.03, 0.001) = 0.007;
uniform float minor_width : hint_range(0.0005, 0.01, 0.0005) = 0.002;
uniform vec4 state_emission : source_color = vec4(0.0);
uniform float state_energy : hint_range(0.0, 2.0) = 0.0;
// Curved primitives blend world projections to avoid per-triangle phase seams.
uniform bool triplanar_projection = false;
varying vec3 world_position;
varying vec3 surface_normal_world;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface_normal_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float metric_lines(vec2 metres, float spacing, float width) {
	vec2 uv = metres / max(spacing, 0.0001);
	vec2 footprint = max(fwidth(uv), vec2(0.00001));
	vec2 distance_to_line = abs(fract(uv + 0.5) - 0.5);
	vec2 axis_half_width = vec2(width * 0.5 / spacing);
	vec2 draw_width = max(axis_half_width, footprint * 0.5);
	vec2 coverage = 1.0 - smoothstep(draw_width - footprint * 0.5, draw_width + footprint * 0.5, distance_to_line);
	// Preserve line energy below a pixel; fade each axis before it can alias.
	coverage *= min(vec2(1.0), axis_half_width / draw_width);
	coverage *= 1.0 - smoothstep(vec2(0.18), vec2(0.48), footprint);
	return max(coverage.x, coverage.y);
}

vec3 grid_levels(vec2 metres) {
	return vec3(metric_lines(metres, minor_spacing, minor_width),
		metric_lines(metres, half_spacing, half_width),
		metric_lines(metres, major_spacing, major_width));
}

void fragment() {
	// Geometric face normal, so nonuniform scales and pushed faces remain metric.
	vec3 normal_world = normalize(cross(dFdx(world_position), dFdy(world_position)));
	// Fix normal sign independently of winding, including the underside of blocks.
	if (normal_world.y < -0.0001 || (abs(normal_world.y) < 0.0001 && normal_world.z < -0.0001)
		|| (abs(normal_world.y) < 0.0001 && abs(normal_world.z) < 0.0001 && normal_world.x < 0.0)) {
		normal_world = -normal_world;
	}
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	if (abs(normal_world.y) < 0.9999) {
		tangent = normalize(cross(vec3(0.0, 1.0, 0.0), normal_world));
	} else {
		tangent = normalize(tangent - normal_world * dot(tangent, normal_world));
	}
	vec3 bitangent = normalize(cross(normal_world, tangent));
	vec2 metres = vec2(dot(world_position, tangent), dot(world_position, bitangent));
	vec3 levels = grid_levels(metres);
	if (triplanar_projection) {
		vec3 weights = pow(abs(normalize(surface_normal_world)), vec3(8.0));
		weights /= max(weights.x + weights.y + weights.z, 0.0001);
		levels = grid_levels(world_position.yz) * weights.x
			+ grid_levels(world_position.xz) * weights.y
			+ grid_levels(world_position.xy) * weights.z;
	}
	float minor = levels.x * minor_color.a;
	float half_grid = levels.y * half_color.a;
	float major = levels.z * major_color.a;
	vec3 color = mix(base_color.rgb, minor_color.rgb, minor);
	color = mix(color, half_color.rgb, half_grid);
	ALBEDO = mix(color, major_color.rgb, major);
	ROUGHNESS = 0.88;
	EMISSION = state_emission.rgb * state_energy;
}
