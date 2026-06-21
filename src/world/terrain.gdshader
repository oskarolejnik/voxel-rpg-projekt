shader_type spatial;
// Shader terenu voxelowego (Faza 0B).
// Cel: zachować TOŻSAMOŚĆ VOXELA (twarde normalne, kolor z wierzchołków) i dodać
// głębię bez kosztu BUDOWY chunku: hemisferyczny "fake GI", edge-AO z pochodnych
// ekranowych oraz rim light dla czytelności sylwetki. Wszystko liczone w GPU.
render_mode cull_back;

// Hemisferyczny ambient: górne ściany łapią lekko barwę nieba, dolne barwę ziemi.
uniform vec3 sky_tint : source_color = vec3(0.55, 0.70, 0.95);
uniform vec3 ground_tint : source_color = vec3(0.32, 0.26, 0.20);
uniform float hemi_strength : hint_range(0.0, 0.6) = 0.22;

// Edge-AO: cienkie przyciemnienie krawędzi voxeli (pochodna world-normal w ekranie).
uniform float edge_ao : hint_range(0.0, 1.0) = 0.35;

// Rim light: rozjaśnienie sylwetki — czytelność na tle terenu/nieba.
uniform vec3 rim_color : source_color = vec3(1.0, 0.97, 0.85);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.18;
uniform float rim_power : hint_range(1.0, 8.0) = 3.0;

varying vec3 v_wn;  // world-space normal (twardy, stały per ściana)

// Nasze vertex colors są dobrane jak sRGB — linearyzujemy do oświetlenia.
vec3 srgb_to_lin(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

void vertex() {
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = srgb_to_lin(COLOR.rgb);

	// Hemisferyczny tint wg pionu (0 = dół, 1 = góra) — tania kierunkowość zamiast GI.
	float up = clamp(v_wn.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 hemi = mix(srgb_to_lin(ground_tint), srgb_to_lin(sky_tint), up);
	base += hemi * hemi_strength * 0.2;

	// Edge-AO: na twardych normalnych fwidth ~0 wewnątrz ściany, skok na krawędzi.
	float edge = clamp(length(fwidth(v_wn)) * 2.0, 0.0, 1.0);
	base *= (1.0 - edge * edge_ao);

	ALBEDO = base;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;

	// Rim light (EMISSION, by działał też w cieniu) — podbija sylwetkę.
	float rim = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), rim_power);
	EMISSION += srgb_to_lin(rim_color) * rim * rim_strength;
}
