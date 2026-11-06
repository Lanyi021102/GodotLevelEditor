shader_type fog;
uniform float density : hint_range(0.0, 1.0) = 0.48;
uniform vec4 cloud_color : source_color = vec4(0.92, 0.89, 0.79, 1.0);

void fog() {
	// Keep the puzzle deck clear; slowly varying layers swallow the lower island.
	float drift = TIME * 0.06;
	float wave = sin(WORLD_POSITION.x * 0.16 + drift) * 0.45
		+ cos(WORLD_POSITION.z * 0.13 - drift) * 0.35;
	float height_mask = smoothstep(0.35, 4.5, -WORLD_POSITION.y + wave);
	DENSITY = density * height_mask;
	ALBEDO = cloud_color.rgb;
	EMISSION = cloud_color.rgb * 1.2;
}
