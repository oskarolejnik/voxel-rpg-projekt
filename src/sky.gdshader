shader_type sky;
// sky.gdshader — stylizowane "Storybook Voxel" niebo (ART OVERHAUL).
// Maluje gradient zenit->horyzont + miekkie 2-oktawowe chmury (TIME-scroll), pole gwiazd
// (rozpalane noca) i miekki dysk ksiezyca. Sterowane przez DayNight._apply (uniformy ponizej):
//   top_color / horizon_color — kolory pory doby (z _SKY_TOP / _SKY_HORIZON),
//   night — 0 w dzien, 1 okolo polnocy (gwiazdy + ksiezyc + przygaszone chmury),
//   sun_dir / moon_dir — kierunki (jednostkowe) sterujace ciepla luna slonca i pozycja ksiezyca.
// CELOWO TANIE: niskie oktawy, brak petli, bez teksturowania. Niebo to look, nie koszt.

// --- Uniformy sterowane przez DayNight (z bezpiecznymi domyslnymi = dzien) ---
uniform vec3 top_color : source_color = vec3(0.18, 0.42, 0.78);     // zenit
uniform vec3 horizon_color : source_color = vec3(0.72, 0.84, 0.95); // horyzont
uniform float night : hint_range(0.0, 1.0) = 0.0;                   // 0 dzien .. 1 noc
uniform vec3 sun_dir = vec3(0.0, 0.3, -1.0);                        // kierunek slonca (jednostkowy)
uniform vec3 moon_dir = vec3(0.0, 0.4, 1.0);                        // kierunek ksiezyca (jednostkowy)

// --- Stale wygladu (strojenie looku bez ruszania kodu) ---
const float CLOUD_COVER = 0.50;     // prog krycia chmur (wiecej = wiecej nieba miedzy chmurami)
const float CLOUD_SOFT = 0.28;      // miekkosc krawedzi chmur
const vec3 CLOUD_COLOR = vec3(1.0, 0.97, 0.92);  // cieple bialo-kremowe chmury (zlota godzina)
const vec3 STAR_COLOR = vec3(0.95, 0.97, 1.0);   // chlodna biel gwiazd
const vec3 MOON_COLOR = vec3(0.96, 0.97, 0.92);  // kremowa tarcza ksiezyca

// Tani hash 2D -> [0,1) (bez tekstur). Stabilny, deterministyczny per kierunek.
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

// Value noise (interpolowany hash) — gladki, tani fundament chmur.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);   // smoothstep na komorce
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 2-oktawowe chmury (fBm light). Scroll TIME w dwoch kierunkach => warstwy plyna rozna predkoscia.
float clouds(vec2 uv) {
	float t = TIME * 0.004;
	float n = value_noise(uv + vec2(t, t * 0.6)) * 0.65;
	n += value_noise(uv * 2.3 + vec2(-t * 1.7, t * 0.9)) * 0.35;
	return n;
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	// (1) Gradient zenit->horyzont na bazie wysokosci patrzenia (EYEDIR.y).
	// up01: 0 przy horyzoncie, 1 w zenicie. pow zageszcza pas przy horyzoncie (miekkie wstanie barwy).
	float up01 = clamp(dir.y, 0.0, 1.0);
	float grad = pow(up01, 0.45);
	vec3 col = mix(horizon_color, top_color, grad);

	// (2) Cieplа luna slonca przy horyzoncie w jego kierunku (zlota godzina). Tania, tylko nad horyzontem.
	float sun_d = max(dot(dir, normalize(sun_dir)), 0.0);
	float sun_glow = pow(sun_d, 6.0) * (1.0 - night);
	col += horizon_color * sun_glow * 0.6;

	// (3) Chmury — rzutujemy kierunek na "kopule" (xz / (y+bias)) => plaskie, plynace nad glowa.
	// Tlumione przy horyzoncie (horizon_fade) i pod horyzontem (nie malujemy chmur w ziemi).
	float dome = 1.0 / (dir.y + 0.35);          // perspektywa kopuly (mniej rozciagniete niz 1/y)
	vec2 cuv = dir.xz * dome * 1.6;
	float c = clouds(cuv);
	float cloud_mask = smoothstep(CLOUD_COVER, CLOUD_COVER + CLOUD_SOFT, c);
	float horizon_fade = smoothstep(-0.02, 0.22, dir.y);   // brak chmur tuz przy/pod horyzontem
	cloud_mask *= horizon_fade;
	// Chmury ciemnieja noca (chlodniejsze, mniej obecne), w dzien pelna kremowa biel.
	vec3 cloud_rgb = mix(CLOUD_COLOR, CLOUD_COLOR * vec3(0.35, 0.40, 0.55), night);
	col = mix(col, cloud_rgb, cloud_mask * (1.0 - 0.45 * night));

	// (4) Gwiazdy — hash na "kafelkowanym" kierunku; tylko jasne progi => rzadkie punkty. Faded by night.
	if (night > 0.01) {
		vec2 suv = dir.xz * dome * 60.0;
		vec2 cell = floor(suv);
		float star = hash21(cell);
		float twinkle = 0.6 + 0.4 * sin(TIME * 2.0 + star * 100.0);
		float star_on = smoothstep(0.985, 1.0, star) * twinkle;
		star_on *= smoothstep(0.05, 0.35, dir.y);   // gwiazdy tylko wyzej (nie w horyzoncie/chmurach)
		star_on *= (1.0 - cloud_mask);               // chmura zaslania gwiazdy
		col += STAR_COLOR * star_on * night;
	}

	// (5) Miekki dysk ksiezyca w kierunku moon_dir. Rdzen + delikatna poswiata. Tylko noca.
	if (night > 0.01) {
		float md = dot(dir, normalize(moon_dir));
		float disc = smoothstep(0.995, 0.999, md);   // ostra tarcza
		float halo = pow(max(md, 0.0), 64.0) * 0.5;   // miekka aureola wokol
		col += MOON_COLOR * (disc + halo) * night;
	}

	COLOR = col;
}
