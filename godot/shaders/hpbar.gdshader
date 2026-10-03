// 적 머리 위 체력바: 항상 카메라를 향하고 instance uniform으로 채움 비율 지정
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

instance uniform float fill = 1.0;
instance uniform vec4 bar_color : source_color = vec4(0.8, 0.13, 0.13, 1.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float edge = step(0.04, UV.y) * step(UV.y, 0.96) * step(0.01, UV.x) * step(UV.x, 0.99);
	vec3 col = UV.x < fill ? bar_color.rgb : vec3(0.12, 0.0, 0.0);
	ALBEDO = mix(vec3(0.0), col, edge);
	ALPHA = 0.9;
}
