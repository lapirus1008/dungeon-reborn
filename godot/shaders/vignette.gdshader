// 화면 가장자리 효과: 피격(빨강), 보호막(파랑)
shader_type canvas_item;

uniform float hurt = 0.0;
uniform float shield = 0.0;
uniform float shield_hit = 0.0;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p * vec2(1.0, 0.75));
	float edge = smoothstep(0.32, 0.7, r);
	vec4 red = vec4(0.7, 0.0, 0.0, edge * hurt);
	float ripple = 0.75 + 0.25 * sin(TIME * 4.0 + r * 30.0);
	float sh = edge * (shield * 0.4 * ripple + shield_hit * 0.5);
	vec4 blue = vec4(0.3, 0.6, 1.0, sh);
	COLOR = vec4(mix(red.rgb, blue.rgb, sh / max(0.001, sh + red.a)), max(red.a, sh));
}
