// 화면 가장자리 효과: 피격(빨강), 보호막(보호막 색), 서리 장벽(하양-하늘), 은신(보라)
shader_type canvas_item;

uniform float hurt = 0.0;
uniform float shield = 0.0;
uniform float shield_hit = 0.0;
uniform vec4 tint : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float frost = 0.0;
uniform float stealth = 0.0;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p * vec2(1.0, 0.75));
	float edge = smoothstep(0.32, 0.7, r);
	float ripple = 0.75 + 0.25 * sin(TIME * 4.0 + r * 30.0);
	vec4 col = vec4(0.0);
	// 은신: 보라색 가장자리
	col = mix(col, vec4(0.35, 0.15, 0.55, 1.0), edge * stealth * 0.55);
	// 서리 장벽: 화면 전체가 얼어붙음
	float fr = frost * (0.25 + edge * 0.55);
	col = mix(col, vec4(0.75, 0.9, 1.0, 1.0), fr);
	float sh = edge * (shield * 0.4 * ripple + shield_hit * 0.5);
	col = mix(col, vec4(tint.rgb, 1.0), sh);
	col = mix(col, vec4(0.7, 0.0, 0.0, 1.0), edge * hurt);
	COLOR = vec4(col.rgb, max(max(edge * stealth * 0.55, fr), max(sh, edge * hurt)));
}
