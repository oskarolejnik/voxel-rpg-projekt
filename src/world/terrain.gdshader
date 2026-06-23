shader_type spatial;
// Shader terenu voxelowego (Faza 0B + FEEL 6).
// Cel: zachować TOŻSAMOŚĆ VOXELA (twarde normalne, kolor z wierzchołków) i dodać
// głębię/"premium" BEZ tekstur i BEZ kosztu BUDOWY chunku: hemisferyczny "fake GI",
// micro-AO z pochodnych ekranowych, rim light (fresnel * kierunek słońca) oraz tani
// pseudo-specular (half-vector). Wszystko liczone w GPU (fragment), zero kosztu CPU.
//
// FEEL 6: kontrast materiału bez tekstur => natychmiastowy skok premium. KALIBRACJA pod
// AGX tonemap + glow: rim/spec trzymane NISKO i mnożone przez NdotL (tylko oświetlona
// strona), by nie przepalać sylwetek i nie karmić bloomu (EMISSION zostaje subtelna).
render_mode cull_back;

// Hemisferyczny ambient: górne ściany łapią lekko barwę nieba, dolne barwę ziemi.
uniform vec3 sky_tint : source_color = vec3(0.55, 0.70, 0.95);
uniform vec3 ground_tint : source_color = vec3(0.32, 0.26, 0.20);
uniform float hemi_strength : hint_range(0.0, 0.6) = 0.22;

// Micro-AO: cienkie przyciemnienie krawędzi voxeli (pochodna world-normal w ekranie) +
// delikatne pogłębienie szczelin. Tanie, czytelne, bez map AO.
uniform float edge_ao : hint_range(0.0, 1.0) = 0.35;
uniform float micro_ao : hint_range(0.0, 0.6) = 0.18;   // FEEL 6: dodatkowe miekkie zacienienie wnek

// Rim light: rozjaśnienie sylwetki — czytelność na tle terenu/nieba. FEEL 6: modulowany
// kierunkiem słońca (LIGHT w funkcji light()) => rim "zapala się" od strony światła.
// FEEL 3: wzmocniony (0.16->0.24) — sylwetka terenu mocniej "odrywa się" od nieba/dali. Trzymane
// pod kontrolą przez sun_facing + ATTENUATION (gaśnie w cieniu) => brak przepału pod AGX+glow.
uniform vec3 rim_color : source_color = vec3(1.0, 0.97, 0.85);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.24;   // FEEL 3: 0.16->0.24 (silniejsza sylwetka)
uniform float rim_power : hint_range(1.0, 8.0) = 2.6;       // FEEL 3: 3.0->2.6 (szerszy pas rim na zboczu)

// FEEL 6: tani pseudo-specular (half-vector, bez map). Niska moc => "wilgotny" połysk na
// oświetlonych ścianach, BEZ metalicznego przepału. Liczony w light() (zna kierunek słońca).
// FEEL 3: lekko wzmocniony (0.10->0.14) — mocniejszy akcent na oświetlonych szczytach (kontrast).
uniform float fake_spec : hint_range(0.0, 0.5) = 0.14;
uniform float fake_spec_power : hint_range(2.0, 64.0) = 20.0;

// FEEL 3: VALUE CONTRAST (bez tekstur) — rzeźbi tonalnie teren by skończyć z "matowo/płasko":
//   * peaks (ściany skierowane W GÓRĘ) lekko ROZJAŚNIONE (łapią więcej nieba/słońca),
//   * cavities (ściany w dół/bok) lekko PRZYCIEMNIONE (głębsza okluzja niż samo micro_ao).
// Liczone czysto w GPU z world-normal.y. Trzymane NISKO (peak 0.10 / dim 0.16), by AGX+glow nie
// rozjechały tonów; nasycenie odrobinę podbite w cieniu (ciemne = bardziej barwne => "głębia").
uniform float value_peak : hint_range(0.0, 0.4) = 0.10;     // rozjaśnienie szczytów (góra)
uniform float value_dim : hint_range(0.0, 0.5) = 0.16;      // przyciemnienie zagłębień (dół/bok)
uniform float shade_saturate : hint_range(0.0, 0.6) = 0.18; // podbicie nasycenia w cieniu (głębia barwy)

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

	// FEEL 6: micro-AO — ściany skierowane w dół/w bok dostają lekkie przyciemnienie (imitacja
	// okluzji we wnękach voxeli). Tania, bezteksturowa głębia; góra (niebo) zostaje jasna.
	float cavity = (1.0 - up);
	base *= (1.0 - cavity * micro_ao);

	// FEEL 3: VALUE CONTRAST — rzeźba tonalna. up^2 koncentruje rozjaśnienie na realnych szczytach
	// (płaskie wierzchy voxeli), a cavity^1.5 pogłębia tylko strome dno/boki (nie blaknie pionowych
	// ścian). Efekt: jasne grzbiety vs ciemne wąwozy => natychmiastowa czytelność rzeźby z daleka.
	float peak_w = up * up;                     // 0 na dole, ~1 na płaskich wierzchach
	float pit_w = pow(cavity, 1.5);             // pogłębione tylko mocno skierowane w dół/bok
	base *= (1.0 + peak_w * value_peak);        // szczyty jaśniejsze
	base *= (1.0 - pit_w * value_dim);          // zagłębienia ciemniejsze

	// FEEL 3: nasycenie barwy rośnie w zacienionych zagłębieniach (ciemne piksele bardziej kolorowe
	// => unika "szarego mleka" w cieniu, daje malarską głębię). Tania korekta wokół luminancji.
	float luma = dot(base, vec3(0.299, 0.587, 0.114));
	base = mix(vec3(luma), base, 1.0 + pit_w * shade_saturate);
	base = max(base, vec3(0.0));

	ALBEDO = base;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

// FEEL 6: oświetlenie własne — tu znamy LIGHT (kierunek słońca) i LIGHT_COLOR, więc rim i
// pseudo-spec są STEROWANE SŁOŃCEM (zapalają się od strony światła, gasną w cieniu). Liczone
// per-light; w grze świeci jedno DirectionalLight3D (słońce), więc koszt = jeden przebieg.
void light() {
	// Lambert (zachowuje twardy voxelowy cieniowany wygląd; ATTENUATION = cień słońca).
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ndotl * ATTENUATION;

	// Rim (fresnel) * kierunek słońca: jasne na sylwetce ZWRÓCONEJ do światła. Mnożymy przez
	// ndotl (tylko oświetlona strona) i ATTENUATION (gaśnie w cieniu) => brak przepału pod AGX.
	// FEEL 3: sun_facing podbity (×1.8) => rim "zapala się" wcześniej na zboczu zwróconym do słońca,
	// czytelniejsza sylwetka grzbietów. Nadal mnożony przez ATTENUATION (cień gasi) => bez flara.
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), rim_power);
	float sun_facing = clamp(ndotl * 1.8, 0.0, 1.0);
	SPECULAR_LIGHT += srgb_to_lin(rim_color) * LIGHT_COLOR * fres * sun_facing * rim_strength * ATTENUATION;

	// Pseudo-specular (Blinn half-vector) — tani, niski, "wilgotny" błysk na oświetlonych ścianach.
	vec3 half_v = normalize(LIGHT + normalize(VIEW));
	float spec = pow(max(dot(NORMAL, half_v), 0.0), fake_spec_power);
	SPECULAR_LIGHT += LIGHT_COLOR * spec * fake_spec * ndotl * ATTENUATION;
}
