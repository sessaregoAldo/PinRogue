class_name SmokeLayer
extends Node2D
## A thin layer of smoke over a table's background picture (Cosmetics item
## with "smoke": true). It drifts slowly; a ball moving through it stirs it a
## little and thins it, and the smoke settles again over a couple of seconds.
## Drawn just above the background and under every part of the table.

const FIELD := Rect2(20, 20, 560, 1100)
## Ball positions remembered for the stirring (oldest dropped first).
const TRAIL_SIZE := 16
const SAMPLE_EVERY := 0.06
## How long a ball's passing stays visible in the smoke.
const SETTLE_SECONDS := 2.2

const SHADER := """
shader_type canvas_item;

uniform vec2 field_size = vec2(560.0, 1100.0);
uniform vec4 trail[16]; // x, y (field px), age (s), strength 0..1
uniform float settle = 2.2;
uniform float opacity = 0.16;
uniform vec3 tint : source_color = vec3(0.78, 0.76, 0.72);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.03 + vec2(17.0, 9.0); a *= 0.5; }
	return v;
}

void fragment() {
	vec2 p = UV * field_size;
	vec2 offset = vec2(0.0);
	float thin = 0.0;
	for (int i = 0; i < 16; i++) {
		vec4 t = trail[i];
		if (t.w <= 0.0) { continue; }
		vec2 d = p - t.xy;
		float r = length(d);
		float fall = exp(-(r * r) / 2600.0) * exp(-t.z / (settle * 0.45)) * t.w;
		vec2 n = d / max(r, 1.0);
		offset += (vec2(-n.y, n.x) * 14.0 + n * 9.0) * fall; // a small swirl, pushed aside
		thin += fall * 0.35;
	}
	float time = TIME;
	vec2 q = (p + offset) / 210.0 + vec2(sin(time * 0.05) * 0.4, -time * 0.018);
	float warp = fbm(q * 0.7 + vec2(time * 0.01, 0.0));
	float n = fbm(q + vec2(warp * 1.6, warp * 0.8));
	float density = smoothstep(0.42, 0.78, n);
	density *= 0.55 + 0.45 * smoothstep(1.0, 0.0, UV.y); // a little heavier up top, where it gathers
	COLOR = vec4(tint, density * opacity * clamp(1.0 - thin, 0.0, 1.0));
}
"""

var _rect: ColorRect
var _material: ShaderMaterial
var _trail: Array[Vector4] = []
var _since_sample: float = 0.0


func _ready() -> void:
	z_index = 0
	_rect = ColorRect.new()
	_rect.position = FIELD.position
	_rect.size = FIELD.size
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("settle", SETTLE_SECONDS)
	_rect.material = _material
	add_child(_rect)


func _process(delta: float) -> void:
	for i in _trail.size():
		_trail[i].z += delta
	while not _trail.is_empty() and _trail[0].z > SETTLE_SECONDS:
		_trail.pop_front()
	_since_sample += delta
	if _since_sample >= SAMPLE_EVERY:
		_since_sample = 0.0
		for node in get_tree().get_nodes_in_group("ball"):
			var ball := node as Ball
			if ball == null or not ball.in_play or not ball.visible or ball.ramp != null:
				continue
			var speed := ball.linear_velocity.length()
			if speed < 60.0:
				continue
			var at := to_local(ball.global_position) - FIELD.position
			_trail.append(Vector4(at.x, at.y, 0.0, clampf(speed / 900.0, 0.25, 1.0)))
		while _trail.size() > TRAIL_SIZE:
			_trail.pop_front()
	var packed: Array[Vector4] = []
	for i in TRAIL_SIZE:
		packed.append(_trail[i] if i < _trail.size() else Vector4.ZERO)
	_material.set_shader_parameter("trail", packed)
