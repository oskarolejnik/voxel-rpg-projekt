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

# Cache stanu cieni — przełączamy shadow_enabled tylko przy realnej zmianie,
# zamiast pisać tę samą wartość co klatkę. (-1 = nieznane, wymusza pierwsze ustawienie.)
var _shadow_state: int = -1

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

# (f) AMBIENT – energia światła otoczenia. Min 0.12 nocą, by scena nie zgasła do czerni
# (działa TYLKO przy ambient_light_sky_contribution < 1.0 — ustawia to Main).
const _AMBIENT: Array[float] = [ 0.12, 0.20, 0.25, 0.18, 0.12 ]

# (g) Kolor mgły wolumetrycznej (volumetric_fog_albedo).
const _FOG: Array[Color] = [
	Color(0.05, 0.07, 0.16),   # NOC   – ciemna mgła
	Color(0.85, 0.62, 0.55),   # ŚWIT  – ciepła
	Color(0.80, 0.86, 0.95),   # DZIEŃ – istniejąca
	Color(0.90, 0.55, 0.45),   # ZACHÓD– ciepła
	Color(0.05, 0.07, 0.16),   # NOC
]


## Wstrzykuje referencje, ustawia porę startową i robi pierwszy _apply,
## żeby scena była poprawna już w klatce 0 (bez „mignięcia” wartości z Main).
func setup(sun: DirectionalLight3D, environment: Environment, sky_material: ProceduralSkyMaterial) -> void:
	_sun = sun
	_env = environment
	_sky = sky_material
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
	_sky.sky_top_color = _SKY_TOP[i].lerp(_SKY_TOP[j], f)
	var horiz := _SKY_HORIZON[i].lerp(_SKY_HORIZON[j], f)
	_sky.sky_horizon_color = horiz
	_sky.ground_horizon_color = horiz   # spójny horyzont góra/dół

	# (e) ambient.
	_env.ambient_light_energy = lerpf(_AMBIENT[i], _AMBIENT[j], f)

	# (f) mgła wolumetryczna.
	_env.volumetric_fog_albedo = _FOG[i].lerp(_FOG[j], f)
