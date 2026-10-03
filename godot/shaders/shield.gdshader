// 마법사 비전 보호막 구체: 가장자리가 빛나는 프레넬 + 육각 무늬 일렁임
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.35, 0.65, 1.0, 1.0);
uniform float strength = 1.0;
uniform float hit = 0.0;

void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	vec2 uv = UV * vec2(24.0, 12.0);
	vec2 g = abs(fract(uv + vec2(0.5 * floor(uv.y), 0.0)) - 0.5);
	float hex = smoothstep(0.42, 0.5, max(g.x, g.y));
	float wave = 0.5 + 0.5 * sin(TIME * 3.0 + UV.y * 20.0);
	float a = (fres * 0.8 + hex * 0.12 * wave + hit * 0.3) * strength;
	ALBEDO = tint.rgb * a;
}
