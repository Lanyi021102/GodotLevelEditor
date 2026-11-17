shader_type sky;
uniform vec4 upper_color : source_color = vec4(0.61, 0.68, 0.69, 1.0);
uniform vec4 lower_color : source_color = vec4(0.91, 0.86, 0.73, 1.0);
void sky() {
	float height = smoothstep(-0.96, -0.34, EYEDIR.y);
	COLOR = mix(lower_color.rgb, upper_color.rgb, height);
}
