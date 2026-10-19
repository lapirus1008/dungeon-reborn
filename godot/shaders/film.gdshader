// 화면 후처리 (던전 분위기): 가장자리 어둡게(비네트) · 필름 그레인 · 어두운 곳은 차갑고 밝은 곳은 따뜻하게 · 약한 색번짐
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.55;
uniform float grain = 0.045;
uniform float fringe = 0.0004;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	// 가장자리로 갈수록 빨강/파랑이 아주 조금 어긋남 (오래된 렌즈 느낌)
	vec3 c;
	c.r = texture(screen_tex, uv + d * fringe * 4.0).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - d * fringe * 4.0).b;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	// 어두운 부분은 푸르스름하게, 밝은 부분(횃불)은 주황빛으로
	vec3 shadow_tint = vec3(0.88, 0.95, 1.08);
	vec3 light_tint = vec3(1.08, 0.98, 0.86);
	c *= mix(shadow_tint, light_tint, smoothstep(0.05, 0.6, lum));
	// 비네트
	float r = length(d * vec2(1.0, 0.8));
	c *= 1.0 - vignette * smoothstep(0.25, 0.85, r);
	// 필름 그레인 (어두운 곳에서 더 보임)
	float n = hash(uv * vec2(1920.0, 1080.0) + fract(TIME * 13.7) * 100.0) - 0.5;
	c += n * grain * (1.0 - smoothstep(0.0, 0.7, lum));
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
