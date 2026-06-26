class_name DayNight
extends Node
## DayNight.gd — sterownik cyklu dnia i nocy.
## Płynnie interpoluje słońce (rotacja/kolor/energia), niebo (zenit/horyzont),
## światło otoczenia i kolor mgły między keyframe'ami pór doby.
##
## NIE tworzy własnego światła/nieba — animuje to, co wstrzyknie Main przez setup().
##
## WAŻNE (współpraca z Main): aby keyframe'y _AMBIENT realnie rozjaśniały noc,
## Main MUSI ustawić Environment.ambient_light_sky_contribution < 1.0. Przy domyślnym
## 1.0 całe światło otoczenia bierze się z (nocą ciemnego) nieba, a ambient_light_energy
## jest IGNOROWANE — i noc gaśnie do czerni. Main robi to w _setup_environment().

# Długość pełnej doby w sekundach (świt->dzień->zachód->noc->świt).
@export var day_length_seconds: float = 240.0
# Od jakiej fazy startujemy. 0.42 = przedpołudnie — słońce już wysoko i jasno
# (między keyframe'em ŚWIT t=0.22 a DZIEŃ t=0.50, blisko dnia).
@export var start_time: float = 0.42
# Czy cykl ma w ogóle płynąć (false = zamrożona pora, do debugowania).
@export var running: bool = true

# Czas doby w zakresie 0.0..1.0.
var time_of_day: float = 0.42

# Referencje przekazane z Main — NIE tworzymy ich tu.
var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
# ART OVERHAUL: opcjonalny ShaderMaterial stylizowanego nieba (sky.gdshader). Gdy != null,
# _apply ustawia tez jego uniformy (top_color/horizon_color/night/sun_dir/moon_dir). Gdy null —
# stara sciezka (tylko ProceduralSkyMaterial), wiec brak shadera NIE psuje cyklu doby.
var _sky_shader: ShaderMaterial = null

# Cache stanu cieni — przełączamy shadow_enabled tylko przy realnej zmianie,
# zamiast pisać tę samą wartość co klatkę. (-1 = nieznane, wymusza pierwsze ustawienie.)
var _shadow_state: int = -1

# FEEL 3: ostatnio policzone BAZOWE nasycenie pory doby (przed modulacją biomu w Main). Main MNOŻY
# tę bazę przez mnożnik biomu — czyta JĄ (a nie _env.adjustment_saturation, które samo nadpisuje),
# więc per-biom post jest IDEMPOTENTNY (nie kumuluje się, gdy DayNight jest zatrzymany — np. probe/menu).
var base_saturation: float = 1.12

# --- Keyframe'y pór doby (const => bez alokacji co klatkę) ---
# Progi faz. Ostatni (1.00) == pierwszy (0.00), żeby pętla doby była ciągła.
const _KEY_T: Array[float] = [0.00, 0.22, 0.50, 0.78, 1.00]  # NOC, ŚWIT, DZIEŃ, ZACHÓD, NOC

# (a) KĄT słońca nad horyzontem w stopniach (elewacja). Ujemny = pod ziemią.
const _SUN_ELEV: Array[float] = [ -60.0, 2.0, 75.0, 2.0, -60.0 ]

# (b) KOLOR światła słońca.
const _SUN_COLOR: Array[Color] = [
	Color(0.20, 0.28, 0.55),   # NOC   – zimny, prawie wygaszony (i tak energia ~0)
	Color(1.00, 0.55, 0.32),   # ŚWIT  – ciepły pomarańcz
	Color(1.00, 0.95, 0.85),   # DZIEŃ – istniejące ciepłe białe
	Color(1.00, 0.45, 0.25),   # ZACHÓD– mocniejsza czerwień/pomarańcz
	Color(0.20, 0.28, 0.55),   # NOC
]

# (c) ENERGIA światła słońca (nocą ~0; scena widoczna dzięki ambient).
const _SUN_ENERGY: Array[float] = [ 0.02, 0.55, 1.10, 0.50, 0.02 ]

# (d) NIEBO – kolor zenitu (sky_top_color).
const _SKY_TOP: Array[Color] = [
	Color(0.03, 0.04, 0.12),   # NOC   – granat
	Color(0.30, 0.34, 0.55),   # ŚWIT  – chłodny fiolet->błękit
	Color(0.18, 0.42, 0.78),   # DZIEŃ – istniejący błękit
	Color(0.28, 0.22, 0.42),   # ZACHÓD– fioletowo-różowy zenit
	Color(0.03, 0.04, 0.12),   # NOC
]

# (e) NIEBO – kolor horyzontu (sky_horizon_color, też ground_horizon_color).
const _SKY_HORIZON: Array[Color] = [
	Color(0.06, 0.07, 0.16),   # NOC   – ciemny granat przy ziemi
	Color(0.95, 0.55, 0.40),   # ŚWIT  – łuna pomarańcz/róż
	Color(0.72, 0.84, 0.95),   # DZIEŃ – istniejący jasny błękit
	Color(0.98, 0.45, 0.30),   # ZACHÓD– mocna pomarańcz/czerwień
	Color(0.06, 0.07, 0.16),   # NOC
]

# (f) AMBIENT – energia światła otoczenia. ART OVERHAUL: nocny floor 0.12->0.16, by „księżycowa"
# noc była realnie NAWIGOWALNA (mniej martwej czerni), nie tylko ciemnoniebieska pustka.
# (działa TYLKO przy ambient_light_sky_contribution < 1.0 — ustawia to Main).
const _AMBIENT: Array[float] = [ 0.16, 0.20, 0.25, 0.18, 0.16 ]

# (f2) AMBIENT KOLOR — ART OVERHAUL „Moonlit Navigable Night" (Art Direction Bible). Przy
# ambient_light_sky_contribution=0.6 (Main) 0.4 wagi ambientu bierze się z TEGO koloru, więc nocą
# niebieski księżycowy tint realnie barwi scenę zamiast gasić ją do granatu. Dzień = ciepła biel.
const _AMBIENT_COLOR: Array[Color] = [
	Color(0.30, 0.38, 0.62),   # NOC    – chłodny księżycowy błękit (czytelna, klimatyczna noc)
	Color(0.70, 0.60, 0.58),   # ŚWIT   – ciepło-chłodny poranek
	Color(1.00, 0.97, 0.90),   # DZIEŃ  – ciepła biel
	Color(0.74, 0.56, 0.50),   # ZACHÓD – ciepły zmierzch
	Color(0.30, 0.38, 0.62),   # NOC
]

# (g) Kolor mgły wolumetrycznej (volumetric_fog_albedo).
const _FOG: Array[Color] = [
	Color(0.05, 0.07, 0.16),   # NOC   – ciemna mgła
	Color(0.85, 0.62, 0.55),   # ŚWIT  – ciepła
	Color(0.80, 0.86, 0.95),   # DZIEŃ – istniejąca
	Color(0.90, 0.55, 0.45),   # ZACHÓD– ciepła
	Color(0.05, 0.07, 0.16),   # NOC
]

# (h) GĘSTOŚĆ mgły wolumetrycznej — gęściej o świcie/zachodzie (god rays + poranna mgła), cienko w dzień.
const _FOG_DENSITY: Array[float] = [ 0.0030, 0.0050, 0.0015, 0.0050, 0.0030 ]
# (i) ANIZOTROPIA mgły — silne rozpraszanie do przodu o złotej godzinie => promienie słońca (god rays).
const _FOG_ANISO: Array[float] = [ 0.20, 0.75, 0.35, 0.75, 0.20 ]
# (j) NASYCENIE (color grade) — soczyściej o złotej godzinie, spokojniej nocą.
const _SATURATION: Array[float] = [ 1.05, 1.22, 1.12, 1.25, 1.05 ]

# (j2) FOG SUN SCATTER — ART OVERHAUL „Golden-Hour God-Rays". Rozprasza kolor słońca w mgle
# dystansowej wokół kierunku słońca => ciepła łuna/promienie o świcie i zachodzie. Działa na
# DARMOWEJ mgle depth (BEZ volumetryka), więc god-rays wracają nawet na presecie LOW. Wysoko o
# złotej godzinie (0.34), nisko w dzień/nocą (słońce wysoko/wygaszone => bez halo).
const _FOG_SUN_SCATTER: Array[float] = [ 0.06, 0.34, 0.08, 0.34, 0.06 ]

# --- Atmospheric perspective (Faza 2B): osobne keyframe DEPTH FOG (mgła dystansowa) ---
# UWAGA: _FOG / _FOG_DENSITY / _FOG_ANISO powyżej sterują WOLUMETRYKIEM (bliska atmosfera,
# god rays). Tablice poniżej sterują DEPTH FOG (głębia + rozpuszczanie dalekiej krawędzi LOD
# FAR w kolorze nieba). Dwie warstwy, dwa zestawy keyframe — celowo rozdzielone.

# (k) KOLOR depth fog = kolor HORYZONTU danej pory (aerial perspective: daleka krawędź zlewa
# się z niebem przy horyzoncie). ~zbieżne z _SKY_HORIZON, lekko CIEMNIEJSZE, by pod AGX+glow
# nie rozjaśnić mgły do mlecznej plamy (start z ciemniejszego => na ekranie ~kolor nieba bez przepału).
const _FOG_LIGHT: Array[Color] = [
	Color(0.05, 0.06, 0.14),   # NOC    – ciemny granat (krawędź ginie w mroku, nie w mleku)
	Color(0.82, 0.50, 0.38),   # ŚWIT   – ciepła łuna (lekko ciemniej niż _SKY_HORIZON)
	Color(0.66, 0.78, 0.90),   # DZIEŃ  – błękit horyzontu, przygaszony vs niebo
	Color(0.85, 0.42, 0.30),   # ZACHÓD – pomarańcz/czerwień horyzontu
	Color(0.05, 0.06, 0.14),   # NOC
]
# (l) GĘSTOŚĆ depth fog per pora — w trybie FOG_MODE_DEPTH (Main) fog_density to MAKS. krycie na
# fog_depth_end (krawędź FAR), NIE współczynnik wykładniczy. 1.0 = ostatni pierścień TONIE całkowicie
# w kolorze nieba (krawędź niewidoczna). Dzień nieco mniej (0.92 — przez resztkę widać zarys najdalszych
# grzbietów => głębia panoramy CW), noc/złota godzina pełniej (1.0 — krótszy klimatyczny zasięg).
# Krawędź „fog wall” znika o KAŻDEJ porze; zmienia się tylko ile prześwituje zza krawędzi.
# (Krzywa gęstnienia i początek mgły = fog_depth_begin/curve w Main; tu sterujemy tylko sufitem krycia.)
const _FOG_DENSITY_DEPTH: Array[float] = [ 1.00, 0.96, 0.92, 0.96, 1.00 ]


## Wstrzykuje referencje, ustawia porę startową i robi pierwszy _apply,
## żeby scena była poprawna już w klatce 0 (bez „mignięcia” wartości z Main).
## sky_shader (opcjonalny): ShaderMaterial z sky.gdshader. Gdy podany, _apply steruje tez jego
## uniformami. Domyslnie null => wsteczna zgodnosc (tylko ProceduralSkyMaterial).
func setup(sun: DirectionalLight3D, environment: Environment, sky_material: ProceduralSkyMaterial, sky_shader: ShaderMaterial = null) -> void:
	_sun = sun
	_env = environment
	_sky = sky_material
	_sky_shader = sky_shader
	time_of_day = fposmod(start_time, 1.0)
	_apply(time_of_day)


## Ustawia porę ręcznie (do testów / skip-to-night).
func set_time(t: float) -> void:
	time_of_day = fposmod(t, 1.0)
	_apply(time_of_day)


## Przesuwa porę o ułamek doby (np. klawisz „przewiń”).
func add_time(dt01: float) -> void:
	time_of_day = fposmod(time_of_day + dt01, 1.0)
	_apply(time_of_day)


func _process(delta: float) -> void:
	if not running or _sun == null:
		return
	# Postęp doby: pełna doba w day_length_seconds.
	time_of_day = fposmod(time_of_day + delta / day_length_seconds, 1.0)
	_apply(time_of_day)


## Zwraca (i, j, f): indeksy sąsiednich keyframe'ów + waga f 0..1.
func _segment(t: float) -> Vector3:
	for k in range(_KEY_T.size() - 1):
		if t < _KEY_T[k + 1]:
			var f := (t - _KEY_T[k]) / (_KEY_T[k + 1] - _KEY_T[k])
			return Vector3(float(k), float(k + 1), f)
	return Vector3(3.0, 4.0, 1.0)  # ogon -> ostatni segment


## Azymut słońca: wschód (świt) -> zachód, liniowo wokół całej doby.
## -40 świt, -220 zachód. Monotoniczny, więc zwykły lerpf (bez lerp_angle).
func _sun_azimuth_deg(t: float) -> float:
	return lerpf(-40.0, -220.0, t)


## ART OVERHAUL: czynnik nocy 0..1 dla shadera nieba. 1 okolo polnocy (t≈0/1 — keyframe NOC),
## 0 w dzien (t≈0.5). Plynne wstanie gwiazd/ksiezyca o zmierzchu; spojne z keyframe'ami doby
## (NOC=0.0, ŚWIT=0.22, DZIEŃ=0.50, ZACHÓD=0.78). smoothstep'y daja miekkie progi.
func _night_factor(t: float) -> float:
	# Odleglosc fazowa od polnocy (t=0) po petli doby: 0 o polnocy, 0.5 w poludnie.
	var d := minf(t, 1.0 - t)   # 0 przy t=0/1, 0.5 przy t=0.5
	# Pelna noc dla d <= 0.08 (gleboka noc, gwiazdy+ksiezyc), pelny dzien dla d >= 0.20 (przed ŚWIT 0.22
	# i po ZACHÓD 0.78, gdzie d≈0.22). Dzieki temu probe "gold" (t=0.76, d=0.24) ma night≈0 (czyste,
	# cieple niebo z chmurami), a probe "night" (t=0.0, d=0) ma night=1 (gwiazdy + ksiezyc).
	return 1.0 - smoothstep(0.08, 0.20, d)


## ART OVERHAUL: kierunek jednostkowy z elewacji (stopnie nad horyzontem) i azymutu (stopnie wokol Y).
## Uzywany do sun_dir/moon_dir w sky.gdshader. Spojne z osiami sceny (przod = -Z): wektor patrzenia
## ku zrodlu swiatla, znormalizowany. Tani (kilka trig na klatke).
func _dir_from_angles(elev_deg: float, azim_deg: float) -> Vector3:
	var el := deg_to_rad(elev_deg)
	var az := deg_to_rad(azim_deg)
	var ce := cos(el)
	return Vector3(ce * sin(az), sin(el), -ce * cos(az)).normalized()


## Cała interpolacja i przypisanie do sun/env/sky.
func _apply(t: float) -> void:
	var seg := _segment(t)
	var i := int(seg.x)
	var j := int(seg.y)
	var f := smoothstep(0.0, 1.0, seg.z)   # gładsze przejścia

	# (a) rotacja słońca — elewacja (liniowo, NIE lerp_angle) + azymut.
	var elev := lerpf(_SUN_ELEV[i], _SUN_ELEV[j], f)
	var azim := _sun_azimuth_deg(t)
	# rotation.x = -elewacja: elewacja +75° => światło stromo w dół (rotation_degrees.x = -75).
	_sun.rotation_degrees = Vector3(-elev, azim, 0.0)

	# (b) kolor + (c) energia słońca.
	_sun.light_color = _SUN_COLOR[i].lerp(_SUN_COLOR[j], f)
	_sun.light_energy = lerpf(_SUN_ENERGY[i], _SUN_ENERGY[j], f)
	# Cienie tylko gdy słońce nad horyzontem (oszczędność + brak dziwnych cieni nocą).
	# Przełączamy shadow_enabled tylko przy zmianie stanu (nie co klatkę).
	var want_shadow := 1 if elev > 0.0 else 0
	if want_shadow != _shadow_state:
		_sun.shadow_enabled = want_shadow == 1
		_shadow_state = want_shadow

	# (d) niebo.
	var top_c := _SKY_TOP[i].lerp(_SKY_TOP[j], f)
	var horiz := _SKY_HORIZON[i].lerp(_SKY_HORIZON[j], f)
	_sky.sky_top_color = top_c
	_sky.sky_horizon_color = horiz
	_sky.ground_horizon_color = horiz   # spójny horyzont góra/dół

	# (d2) ART OVERHAUL — STYLIZOWANE NIEBO: te same kolory pory doby + night/sun_dir/moon_dir lecą
	# do uniformow sky.gdshader (chmury/gwiazdy/ksiezyc). Gated na _sky_shader != null => brak shadera
	# nie psuje niczego. night liczone z time_of_day (1 okolo polnocy, 0 w dzien) — patrz _night_factor.
	if _sky_shader != null:
		_sky_shader.set_shader_parameter("top_color", top_c)
		_sky_shader.set_shader_parameter("horizon_color", horiz)
		_sky_shader.set_shader_parameter("night", _night_factor(t))
		# Kierunek slonca z elewacji+azymutu (jednostkowy). rotation_degrees.x = -elev (patrz wyzej),
		# wiec kierunek "do slonca" odbudowujemy z tych samych katow. azim w stopniach (wokol Y).
		_sky_shader.set_shader_parameter("sun_dir", _dir_from_angles(elev, azim))
		# Ksiezyc PRZECIWNIE do slonca (po drugiej stronie nieba) => widoczny noca, gdy slonce pod ziemia.
		_sky_shader.set_shader_parameter("moon_dir", _dir_from_angles(-elev, azim + 180.0))

	# (e) ambient — energia + KOLOR (ART OVERHAUL: księżycowy nocny tint przez sky_contribution<1).
	_env.ambient_light_energy = lerpf(_AMBIENT[i], _AMBIENT[j], f)
	_env.ambient_light_color = _AMBIENT_COLOR[i].lerp(_AMBIENT_COLOR[j], f)

	# (f) mgła wolumetryczna — kolor + gęstość + anizotropia (god rays o złotej godzinie).
	_env.volumetric_fog_albedo = _FOG[i].lerp(_FOG[j], f)
	_env.volumetric_fog_density = lerpf(_FOG_DENSITY[i], _FOG_DENSITY[j], f)
	_env.volumetric_fog_anisotropy = lerpf(_FOG_ANISO[i], _FOG_ANISO[j], f)

	# (k+l) DEPTH FOG (Faza 2B, tryb FOG_MODE_DEPTH z Main) — kolor = horyzont danej pory (zlanie
	# dalekiej krawędzi LOD z niebem) + maks. krycie na krawędzi (fog_density). „Fog wall” znika o
	# KAŻDEJ porze: w dzień błękitny, o zachodzie pomarańczowy, nocą tonie w granacie — zawsze w
	# kolorze nieba przy horyzoncie. fog_aerial_perspective (stałe 1.0 w Main) ciągnie barwę z nieba
	# w dali; fog_light_color steruje barwą w średnim zasięgu i po stronie zacienionej => eliminuje
	# „szare mleko” na ciemnej stronie kadru. Początek/krzywa mgły (fog_depth_begin/end/curve, stałe
	# w Main) trzymają bliż czystą — tu animujemy tylko KOLOR i SUFIT krycia na krawędzi.
	_env.fog_light_color = _FOG_LIGHT[i].lerp(_FOG_LIGHT[j], f)
	_env.fog_density = lerpf(_FOG_DENSITY_DEPTH[i], _FOG_DENSITY_DEPTH[j], f)
	# (j2) FOG SUN SCATTER — ART OVERHAUL „Golden-Hour God-Rays": ciepła łuna słońca w mgle depth o
	# świcie/zachodzie (darmowe, bez volumetryka => działa też na presecie LOW).
	_env.fog_sun_scatter = lerpf(_FOG_SUN_SCATTER[i], _FOG_SUN_SCATTER[j], f)

	# (g) color grade — nasycenie zależne od pory doby (Faza 1D). FEEL 3: zapisz BAZĘ do pola, a
	# samego _env.adjustment_saturation NIE pisz tu na sztywno — Main._update_biome_post liczy finalną
	# wartość = base_saturation * mnożnik_biomu (idempotentnie). Gdy Main nie istnieje (test/headless
	# bez Main), nikt nie ustawi nasycenia — więc dla bezpieczeństwa ustawiamy też bazę bezpośrednio.
	base_saturation = lerpf(_SATURATION[i], _SATURATION[j], f)
	_env.adjustment_saturation = base_saturation
