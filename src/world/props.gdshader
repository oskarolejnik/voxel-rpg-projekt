shader_type spatial;
// Shader drobnych propów (trawa/kwiaty/grzyby) — wiatr + STREFY WIATRU (Faza 1A + FEEL 8).
// Czubki kołyszą się na wietrze; podstawa zakotwiczona. Waga sway jest w COLOR.a
// (0 = podstawa, 1 = czubek), RGB to albedo (sRGB→lin). Czysty koszt GPU (vertex),
// zero kosztu budowy chunku. Faza fali zależy od pozycji świata => spójny powiew.
//
// FEEL 8: WIND ZONES — siła wiatru modulowana wolną falą w czasie/przestrzeni (porywy biegnące
// przez łąkę). Trawa raz stoi spokojnie, raz kładzie się od podmuchu => "świat oddycha".
render_mode cull_back;

uniform float wind_speed = 1.6;     // tempo kołysania (drżenie źdźbeł)
uniform float wind_amp = 0.06;      // amplituda bazowa w metrach
uniform float wind_scale = 0.18;    // przestrzenna częstotliwość fazy (większe = krótsza fala)

// FEEL 8: strefy wiatru (porywy). Wolna fala 2D w przestrzeni+czasie skalująca amplitudę:
// gust ∈ [1-gust_amount, 1+gust_amount]. Mała częstotliwość przestrzenna => szerokie podmuchy.
uniform float gust_amount : hint_range(0.0, 1.0) = 0.6;   // jak mocno poryw zmienia siłę wiatru
uniform float gust_speed = 0.35;    // tempo przesuwania się porywów przez teren
uniform float gust_scale = 0.04;    // przestrzenna częstotliwość porywów (małe = szerokie strefy)
uniform vec2 wind_dir = vec2(1.0, 0.3);   // kierunek wiania (porywy biegną wzdłuż niego)
// FAZA 5: WIND ZONES dopracowane — globalna SIŁA wiatru ustawiana z gry (Main wg biomu/pogody).
// 1.0 = baza; Frosthelm > Verdant > Emberwaste. Mnoży amplitudę i tempo porywów (świat oddycha
// inaczej w różnych biomach). Default 1.0 => brak zmiany dla scen, które nie pushują uniformu.
uniform float wind_strength : hint_range(0.0, 3.0) = 1.0;

// FAZA 5: REAKTYWNA FOLIAGE — trawa/propy ROZSUWAJĄ się gdy gracz (lub wróg) przez nie przechodzi.
// Główny podmiot (gracz) w player_pos; do 2 dodatkowych "pushujących" (najbliżsi wrogowie) w
// pusher_a/pusher_b (xyz pozycja, w = aktywność 0/1). Czubki (sway~1) odginają się POZIOMO od
// podmiotu w promieniu push_radius; podstawa (sway~0) zakotwiczona. Czysty koszt GPU (vertex).
uniform vec3 player_pos = vec3(0.0, -9999.0, 0.0);   // pozycja gracza (świat); y bardzo niskie = brak
uniform vec4 pusher_a = vec4(0.0, -9999.0, 0.0, 0.0);  // dodatkowy podmiot (wróg) xyz + aktywność.w
uniform vec4 pusher_b = vec4(0.0, -9999.0, 0.0, 0.0);
uniform float push_radius : hint_range(0.3, 4.0) = 1.4;   // zasięg rozsuwania (m)
uniform float push_strength : hint_range(0.0, 1.2) = 0.55; // siła odgięcia czubka (m)

// FEEL 3: spójność z terenem — propy też dostają value-contrast (czubki jaśniejsze = łapią światło,
// podstawa ciemniejsza = okluzja runa) + delikatny rim od słońca, by trawa/kwiaty nie były "płaską
// nalepką" na rzeźbionym terenie. Waga (sway w COLOR.a) służy też jako oś góra/dół rośliny.
uniform float tip_bright : hint_range(0.0, 0.5) = 0.16;   // rozjaśnienie czubków (sway~1)
uniform float root_dim : hint_range(0.0, 0.5) = 0.18;     // przyciemnienie podstawy (sway~0)
uniform vec3 rim_color : source_color = vec3(1.0, 0.97, 0.85);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.18;
uniform float rim_power : hint_range(1.0, 8.0) = 2.6;

varying vec3 v_wn;        // world-normal (do rim w light())
varying float v_sway;     // waga góra/dół rośliny (z COLOR.a) — oś value-contrast

void vertex() {
	float sway = COLOR.a;
	v_sway = sway;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Pozycja świata wierzchołka — wspólna faza dla sąsiednich propów (fala biegnie przez łąkę).
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// FEEL 8: STREFA WIATRU — wolna fala wzdłuż kierunku wiatru daje porywy przesuwające się
	// przez teren. Druga, prostopadła składowa łamie regularność (porywy nie są idealnymi pasami).
	vec2 d = normalize(wind_dir);
	float along = dot(wp.xz, d);
	float across = dot(wp.xz, vec2(-d.y, d.x));
	float gust = sin(TIME * gust_speed + along * gust_scale)
		* cos(TIME * gust_speed * 0.6 + across * gust_scale * 0.7);
	// Mapujemy [-1,1] -> [1-gust_amount, 1+gust_amount]: siła wiatru faluje wokół bazowej.
	float gust_mul = 1.0 + gust * gust_amount;

	// Drżenie źdźbła (szybka fala) — faza z pozycji świata, by sąsiedzi kołysali się spójnie.
	float phase = (wp.x + wp.z) * wind_scale;
	float w = sin(TIME * wind_speed + phase) + 0.5 * sin(TIME * wind_speed * 0.7 + phase * 1.3);

	// Łączna amplituda = baza * poryw strefy * globalna siła wiatru (biom/pogoda). Czubek mocniej.
	float amp = wind_amp * gust_mul * wind_strength * sway;
	VERTEX.x += w * amp * d.x;
	VERTEX.z += w * amp * d.y * 0.8;

	// FAZA 5: REAKTYWNA FOLIAGE — odgięcie POZIOME czubka OD podmiotów (gracz + 2 wrogów). Im bliżej
	// i im wyżej na roślinie (sway), tym mocniej źdźbło kładzie się na bok (rozstępuje się przed nogami).
	vec3 push = vec3(0.0);
	// Gracz (player_pos.y bardzo niskie => brak gracza/scena bez pushu => zero efektu).
	vec2 dp = wp.xz - player_pos.xz;
	float dpl = length(dp);
	if (dpl < push_radius && dpl > 0.0001) {
		float falloff = 1.0 - dpl / push_radius;          // 1 w środku, 0 na krawędzi
		push.xz += normalize(dp) * falloff * falloff;     // kwadratowy => ostrzejsze rozsunięcie u nóg
	}
	// Dodatkowi pushujący (wrogowie) — aktywni tylko gdy .w > 0.5.
	if (pusher_a.w > 0.5) {
		vec2 da = wp.xz - pusher_a.xz; float dal = length(da);
		if (dal < push_radius && dal > 0.0001) {
			float fa = 1.0 - dal / push_radius;
			push.xz += normalize(da) * fa * fa;
		}
	}
	if (pusher_b.w > 0.5) {
		vec2 db = wp.xz - pusher_b.xz; float dbl = length(db);
		if (dbl < push_radius && dbl > 0.0001) {
			float fb = 1.0 - dbl / push_radius;
			push.xz += normalize(db) * fb * fb;
		}
	}
	VERTEX.xz += push.xz * push_strength * sway;
}

void fragment() {
	vec3 base = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));  // sRGB→lin (jak vertex_color_is_srgb)

	// FEEL 3: value contrast wzdłuż rośliny (waga z sway): czubek jaśniejszy (światło góry), podstawa
	// ciemniejsza (cień runa). Spójne z value_peak/value_dim terenu => trawa "siedzi" w scenie.
	base *= (1.0 + v_sway * tip_bright);
	base *= (1.0 - (1.0 - v_sway) * root_dim);

	ALBEDO = max(base, vec3(0.0));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

// FEEL 3: rim od słońca — czytelność źdźbeł/kwiatów na tle terenu (cienka roślina łapie kontur
// światła). Mnożone przez ndotl + ATTENUATION (tylko oświetlona strona, gaśnie w cieniu) => bez flara.
void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ndotl * ATTENUATION;
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), rim_power);
	float sun_facing = clamp(ndotl * 1.8, 0.0, 1.0);
	vec3 rim_lin = pow(max(rim_color, vec3(0.0)), vec3(2.2));
	SPECULAR_LIGHT += rim_lin * LIGHT_COLOR * fres * sun_facing * rim_strength * ATTENUATION;
}
