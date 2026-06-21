shader_type spatial;
// Shader drobnych propów (trawa/kwiaty/grzyby) — wiatr (Faza 1A).
// Czubki kołyszą się na wietrze; podstawa zakotwiczona. Waga sway jest w COLOR.a
// (0 = podstawa, 1 = czubek), RGB to albedo (sRGB→lin). Czysty koszt GPU (vertex),
// zero kosztu budowy chunku. Faza fali zależy od pozycji świata => spójny powiew.
render_mode cull_back;

uniform float wind_speed = 1.6;     // tempo kołysania
uniform float wind_amp = 0.06;      // amplituda w metrach
uniform float wind_scale = 0.18;    // przestrzenna częstotliwość fazy (większe = krótsza fala)

void vertex() {
	float sway = COLOR.a;
	// Pozycja świata wierzchołka — wspólna faza dla sąsiednich propów (fala biegnie przez łąkę).
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = (wp.x + wp.z) * wind_scale;
	float w = sin(TIME * wind_speed + phase) + 0.5 * sin(TIME * wind_speed * 0.7 + phase * 1.3);
	// Kołyszemy lokalnym X/Z (chunk bez rotacji => ~kierunki świata), skalując wagą sway.
	VERTEX.x += w * wind_amp * sway;
	VERTEX.z += w * 0.6 * wind_amp * sway;
}

void fragment() {
	ALBEDO = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));  // sRGB→lin (jak vertex_color_is_srgb)
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
