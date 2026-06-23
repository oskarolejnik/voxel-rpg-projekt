shader_type spatial;
// Stylizowana woda (Faza 1B) — wariant pewny, bez czytania bufora głębi.
// Przezroczysta tafla: głęboki błękit, fresnel (jaśniej/„lustrzano" pod małym kątem),
// animowane falowanie + ruchome lśnienie. Czysty koszt GPU. (Foam z DEPTH_TEXTURE —
// do dodania później; w 4.7 rekonstrukcja głębi okazała się kapryśna i dawała pianę wszędzie.)
render_mode cull_disabled;

// FEEL 3: deep zbity (mocniejszy kontrast głębia<->płycizna => tafla czyta się jako MIEJSCE, nie
// szara plama). shallow nieco bardziej turkusowy (tropikalny akcent biomu wodnego).
uniform vec3 deep_color : source_color = vec3(0.03, 0.18, 0.36);     // głębia (głębszy błękit)
uniform vec3 shallow_color : source_color = vec3(0.14, 0.58, 0.68);  // turkus przy płaskim kącie
uniform vec3 fresnel_color : source_color = vec3(0.80, 0.90, 1.00);  // odblask nieba (horyzont tafli)
uniform float fresnel_power : hint_range(1.0, 8.0) = 4.0;
uniform float wave_amp = 0.05;
uniform float wave_speed = 1.0;
uniform float wave_scale = 0.7;
uniform float water_alpha : hint_range(0.0, 1.0) = 0.78;
// FEEL 3: błysk słońca na tafli (sun glint) — emisyjny akcent na grzbietach fal. Subtelny, ostry
// (wysoki power), gaśnie poza grazing => "żywa", lśniąca woda bez metalicznego przepału pod glow.
uniform float sun_glint : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(v_wpos.x * wave_scale + TIME * wave_speed)
			+ sin(v_wpos.z * wave_scale * 1.3 + TIME * wave_speed * 1.2);
	VERTEX.y += w * wave_amp * 0.5;   // delikatne falowanie tafli
}

void fragment() {
	// Fresnel — jaśniej/„lustrzano" przy płaskim (grazing) kącie patrzenia.
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), fresnel_power);

	// Animowana perturbacja normalnej — ruchome lśnienie na wodzie.
	float t = TIME * wave_speed;
	float nx = sin(v_wpos.x * 1.4 + t) + sin(v_wpos.z * 1.1 - t * 1.3);
	float nz = cos(v_wpos.z * 1.3 - t) + sin(v_wpos.x * 1.0 + t * 0.7);
	NORMAL = normalize(NORMAL + vec3(nx, 0.0, nz) * 0.05);

	vec3 col = mix(deep_color, shallow_color, fres * 0.45);  // pod kątem lekko turkus
	col = mix(col, fresnel_color, fres * 0.6);               // sky-sheen przy horyzoncie tafli

	// FEEL 3: emisyjny sun-glint na grzbietach perturbowanej tafli — animowane lśnienie skupione w
	// jasnym pasie (sin perturbacji^8). Dodawane do EMISSION (nie albedo) => świeci, karmi glow
	// punktowo, nie wybiela całej tafli. Trzymane nisko by AGX nie spaliło do białej plamy.
	float crest = clamp((nx + nz) * 0.5, 0.0, 1.0);
	float glint = pow(crest, 8.0) * fres;
	EMISSION = fresnel_color * glint * sun_glint;

	ALBEDO = col;
	ROUGHNESS = mix(0.10, 0.03, fres);
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = water_alpha;   // stała przezroczystość => widać dno, tafla się nie „wybiela"
}
