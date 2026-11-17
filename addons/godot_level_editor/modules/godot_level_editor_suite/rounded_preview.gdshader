shader_type canvas_item;
uniform vec2 rect_size = vec2(256.0, 180.0);
uniform float radius = 22.0;
varying vec2 local_position;
void vertex() {
 local_position = VERTEX;
}
void fragment() {
 vec2 q = abs(local_position - rect_size * 0.5) - (rect_size * 0.5 - vec2(radius));
 float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
 COLOR.a *= 1.0 - smoothstep(-0.75, 0.75, d);
}
