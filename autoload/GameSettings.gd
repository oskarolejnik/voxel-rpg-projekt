extends Node
## GameSettings.gd (autoload) — USTAWIENIA gry (ETAP 8 polish) + zapis/odczyt user://settings.cfg.
##
## Centralne zrodlo prawdy dla:
##   - PRESETU GRAFIKI (LOW / HIGH) — wg TDD sek.7 "Skalowalna jakosc grafiki",
##   - GLOSNOSCI (Master / SFX / Music) — spina sie z AudioManager (szyny AudioServer),
##   - CZULOSCI MYSZY (mnoznik na Player.mouse_sensitivity).
##
## ZASADY (mandat Etapu 8):
##   - Preset LOW jest DOMYSLNY (laptop Oskara, RTX 3050 4GB) — gra ma chodzic od razu.
##   - apply_graphics(world, environment) ustawia DOKLADNE property Environment/VoxelWorld dla
##     obu presetow (TDD7). Wolane przez Main po _setup_environment (gdy oba wezly istnieja).
##   - Zapis do user://settings.cfg (ConfigFile) — czytelny, wersjonowany, latwy do recznej edycji.
##   - SP-SAFETY: czysta warstwa konfiguracji; nie dotyka logiki gry/sieci. Brak Environment/World
##     (np. test headless) -> apply_graphics jest bezpiecznym no-op na brakujacych argumentach.
##
## Determinizm presetow (zrodlo: TDD sek.7 + realne property w Main._setup_environment / VoxelWorld):
##   LOW : volumetric_fog OFF, SDFGI OFF, SSR OFF, SSIL OFF, DoF OFF; near=3/far=5; MSAA 2x;
##         cienie 80 m; ssao ON (tani); glow ON (tani).
##   HIGH: volumetric_fog ON (god-rays), SDFGI ON (GI), SSR ON (woda/metal), SSIL ON, DoF ON;
##         near=6/far=10; MSAA 4x; cienie 160 m; gestszy detal (wieksze near/far daja gestsze propy).

const CONFIG_PATH: String = "user://settings.cfg"
const CONFIG_VERSION: int = 1

## Presety grafiki. LOW domyslny (4GB). HIGH dla mocniejszego GPU (ten sam silnik, TDD7).
enum GraphicsPreset { LOW, HIGH }

# --- Wartosci ustawien (stan biezacy; zapisywane do user://settings.cfg) ---
var graphics_preset: GraphicsPreset = GraphicsPreset.LOW   # DOMYSLNY: LOW (mandat Etapu 8)
var master_volume: float = 0.9    # 0..1 (liniowo); AudioManager mapuje na dB
var sfx_volume: float = 0.9       # 0..1
var music_volume: float = 0.7     # 0..1
var mouse_sensitivity: float = 1.0   # MNOZNIK na bazowy Player.mouse_sensitivity (0.0025)

## Zakres czulosci myszy (mnoznik). Suwak w SettingsMenu mapuje 0..1 na ten zakres.
const MOUSE_SENS_MIN: float = 0.25
const MOUSE_SENS_MAX: float = 3.0

## Emitowany po KAZDEJ zmianie ustawien (UI/Main odswiezaja sie). Po wczytaniu pliku tez.
signal settings_changed

## Emitowany gdy zmieni sie preset grafiki (Main przeładuje apply_graphics na aktualnych wezlach).
signal graphics_preset_changed(preset: int)


func _ready() -> void:
	load_settings()
	# Glosnosc aplikujemy od razu (AudioManager moze juz istniec jako autoload — kolejnosc w
	# project.godot: AudioManager po GameSettings, wiec AudioManager._ready sam pociagnie wartosci;
	# tu wolamy defensywnie, gdyby ktos zmienial kolejnosc). Mysz/grafike aplikuje Main na wezlach.
	apply_audio()


# ============================================================================
#  ZAPIS / ODCZYT (user://settings.cfg)
# ============================================================================

## Zapisuje biezace ustawienia do user://settings.cfg. Zwraca true przy sukcesie.
func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", CONFIG_VERSION)
	cfg.set_value("graphics", "preset", int(graphics_preset))
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("GameSettings.save_settings: blad zapisu %s (err %d)" % [CONFIG_PATH, err])
		return false
	return true


## Wczytuje ustawienia z user://settings.cfg. Brak pliku = wartosci DOMYSLNE (LOW, glosnosc itd.) —
## pierwsze uruchomienie zachowuje sie poprawnie (nie crashuje). Po wczytaniu emituje settings_changed.
func load_settings() -> bool:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		# Brak pliku / blad -> zostaw domyslne (LOW). To NIE jest blad krytyczny (pierwszy start).
		settings_changed.emit()
		return false
	graphics_preset = _clamp_preset(int(cfg.get_value("graphics", "preset", int(GraphicsPreset.LOW))))
	master_volume = _clamp01(float(cfg.get_value("audio", "master", master_volume)))
	sfx_volume = _clamp01(float(cfg.get_value("audio", "sfx", sfx_volume)))
	music_volume = _clamp01(float(cfg.get_value("audio", "music", music_volume)))
	mouse_sensitivity = clampf(float(cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)),
		MOUSE_SENS_MIN, MOUSE_SENS_MAX)
	settings_changed.emit()
	return true


# ============================================================================
#  SETTERY (UI woła te metody; kazdy aplikuje efekt + emituje sygnal; zapis robi UI na zamknieciu)
# ============================================================================

## Ustawia preset grafiki + (opcjonalnie) aplikuje na podanych wezlach. UI zwykle wola
## set_graphics_preset(p) i osobno prosi Main o apply na aktualnych wezlach przez sygnal.
func set_graphics_preset(preset: GraphicsPreset) -> void:
	preset = _clamp_preset(int(preset))
	if preset == graphics_preset:
		return
	graphics_preset = preset
	graphics_preset_changed.emit(int(graphics_preset))
	settings_changed.emit()


func set_master_volume(v: float) -> void:
	master_volume = _clamp01(v)
	apply_audio()
	settings_changed.emit()


func set_sfx_volume(v: float) -> void:
	sfx_volume = _clamp01(v)
	apply_audio()
	settings_changed.emit()


func set_music_volume(v: float) -> void:
	music_volume = _clamp01(v)
	apply_audio()
	settings_changed.emit()


## Ustawia czulosc myszy z surowej wartosci suwaka 0..1 (mapowanej na MIN..MAX). Aplikuje na graczu.
func set_mouse_sensitivity_normalized(t: float) -> void:
	t = _clamp01(t)
	mouse_sensitivity = lerpf(MOUSE_SENS_MIN, MOUSE_SENS_MAX, t)
	apply_mouse()
	settings_changed.emit()


## Odwrotnosc: gdzie suwak ma stac dla biezacej czulosci (0..1).
func mouse_sensitivity_normalized() -> float:
	var span := MOUSE_SENS_MAX - MOUSE_SENS_MIN
	if span <= 0.0:
		return 0.0
	return clampf((mouse_sensitivity - MOUSE_SENS_MIN) / span, 0.0, 1.0)


# ============================================================================
#  APLIKACJA GRAFIKI (TDD sek.7) — DOKLADNE property Environment/VoxelWorld per preset
# ============================================================================

## Aplikuje BIEZACY preset grafiki na podanych wezlach. Oba argumenty opcjonalne (no-op na null) —
## bezpieczne w headless/tescie, gdzie moze brakowac jednego z wezlow. To JEDYNE miejsce, ktore
## tlumaczy preset na property silnika (zrodlo prawdy zgodne z Main._setup_environment).
func apply_graphics(world: Node = null, environment: Environment = null) -> void:
	match graphics_preset:
		GraphicsPreset.HIGH:
			_apply_high(world, environment)
		_:
			_apply_low(world, environment)


## PRESET LOW (cel: RTX 3050 4GB — obecny tuning gry). Atmosfere niesie TANIA depth fog,
## wiec wylaczamy najdrozsze efekty GPU. Wartosci spojne z Main._setup_environment (baseline LOW).
func _apply_low(world: Node, environment: Environment) -> void:
	if world != null:
		_set_if_has(world, "near_dist", 3)
		_set_if_has(world, "far_dist", 5)
		_set_if_has(world, "chunks_per_frame", 2)
	if environment != null:
		environment.volumetric_fog_enabled = false   # froxele = najdrozszy efekt — OFF na 4GB
		environment.sdfgi_enabled = false             # GI zalewa scene + obciaza GPU — OFF
		environment.ssr_enabled = false               # screen-space reflections OFF
		environment.ssil_enabled = false              # screen-space indirect light OFF
		# DEKLARATYWNY preset (review #minor): przywroc tez NIE-enable pola tuningu do baseline
		# Main._setup_environment, by LOW byl pelnym lustrem baseline (a nie tylko *_enabled=false).
		# Pola sa bezczynne gdy *_enabled=false, ale symetria chroni przed dziwnym stanem, gdyby ktos
		# pozniej recznie wlaczyl efekt bez ponownej aplikacji pelnego presetu.
		environment.volumetric_fog_length = 48.0       # == Main._setup_environment baseline
		environment.ssr_max_steps = 64                 # silnikowy baseline (HIGH ustawia 32)
		# Tanie efekty zostaja WLACZONE (glebia/look bez kosztu froxeli):
		environment.ssao_enabled = true               # AO w stykach (tani, duza wartosc wizualna)
		environment.glow_enabled = true               # bloom na jasnych powierzchniach (tani)
		# Mgla dystansowa (depth fog) — GLOWNE narzedzie atmosfery dali na LOW (patrz Main).
		environment.fog_enabled = true
	_apply_dof(false)                                 # DoF OFF (DoF zyje na kamerze, nie Environment)
	_apply_shadow_distance(80.0)
	_apply_msaa(Viewport.MSAA_2X)


## PRESET HIGH (mocniejszy GPU, TEN SAM silnik). Wlaczamy pelny arsenal Forward+: volumetric god-rays,
## SDFGI (real-time GI), SSR (woda/metal), SSIL, DoF; wiekszy zasieg detalu (gestsze propy/liscie z
## wiekszego near/far); MSAA 4x; dluzsze/ostrzejsze cienie. Look "oszalamiajacy" bez zmiany silnika (TDD7).
func _apply_high(world: Node, environment: Environment) -> void:
	if world != null:
		_set_if_has(world, "near_dist", 6)
		_set_if_has(world, "far_dist", 10)
		_set_if_has(world, "chunks_per_frame", 3)   # wiekszy zasieg -> wiecej submitow/klatke
	if environment != null:
		environment.volumetric_fog_enabled = true     # god-rays / bliska atmosfera
		environment.volumetric_fog_density = 0.018
		environment.volumetric_fog_albedo = Color(0.80, 0.86, 0.95)
		environment.volumetric_fog_length = 64.0
		environment.volumetric_fog_anisotropy = 0.4
		environment.sdfgi_enabled = true              # real-time GI (TDD7 — "SDFGI ON lub probes")
		environment.ssr_enabled = true                # odbicia (woda/metal)
		environment.ssr_max_steps = 32
		environment.ssil_enabled = true               # screen-space indirect light (SSIL)
		environment.ssao_enabled = true
		environment.glow_enabled = true
		environment.fog_enabled = true
	_apply_dof(true, 120.0, 40.0)                     # DoF ON (dal) — na CameraAttributes aktywnej kamery
	_apply_shadow_distance(160.0)
	_apply_msaa(Viewport.MSAA_4X)


## Ustawia maksymalny dystans cieni na DirectionalLight3D "Sun" (jesli istnieje w drzewie).
## Szukamy w glownym drzewie (Sun jest dzieckiem Main). Brak slonca (headless/test) = no-op.
func _apply_shadow_distance(dist: float) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var sun := tree.root.find_child("Sun", true, false)
	if sun is DirectionalLight3D:
		(sun as DirectionalLight3D).directional_shadow_max_distance = dist


## Depth of Field — w Godot 4 ZYJE NA KAMERZE (CameraAttributesPractical), NIE na Environment
## (Environment nie ma pol dof_blur_*). Aplikujemy na AKTYWNEJ kamerze 3D, jesli istnieje. Brak
## kamery (headless/test) = bezpieczny no-op. Tworzymy CameraAttributesPractical tylko gdy DoF ON
## i kamera jeszcze go nie ma (na LOW nie alokujemy nic — czysty OFF na istniejacym attrib lub brak).
func _apply_dof(enabled: bool, far_distance: float = 120.0, far_transition: float = 40.0) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var cam := tree.root.get_camera_3d()
	if cam == null:
		return
	var attr := cam.attributes
	if attr == null:
		if not enabled:
			return                                    # OFF + brak attrib = i tak DoF wylaczone
		attr = CameraAttributesPractical.new()
		cam.attributes = attr
	if attr is CameraAttributesPractical:
		var pa := attr as CameraAttributesPractical
		pa.dof_blur_far_enabled = enabled
		pa.dof_blur_near_enabled = false              # near DoF rozmazuje gracza w 3rd person — OFF
		if enabled:
			pa.dof_blur_far_distance = far_distance
			pa.dof_blur_far_transition = far_transition


## Ustawia MSAA 3D globalnie (project setting + na aktywnym viewporcie, by zadzialalo bez restartu).
## ZALEZNOSC (review #minor): project.godot rendering/anti_aliasing/quality/msaa_3d MUSI zostac
## zgodny z presetem LOW (MSAA_2X) — na zimnym boocie, ZANIM Main._ready zawola apply_graphics,
## viewport uzywa wartosci z project.godot. apply_graphics jest zrodlem prawdy od tego momentu.
func _apply_msaa(msaa: int) -> void:
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", msaa)
	var tree := get_tree()
	if tree != null and tree.root != null:
		tree.root.msaa_3d = msaa as Viewport.MSAA


# ============================================================================
#  APLIKACJA AUDIO / MYSZY
# ============================================================================

## Przekazuje glosnosci do AudioManager (szyny AudioServer). No-op gdy AudioManager nie istnieje
## (np. izolowany test GameSettings) — czysta warstwa konfiguracji nie wymaga audio do dzialania.
func apply_audio() -> void:
	var am := _audio_manager()
	if am == null:
		return
	if am.has_method("set_master_volume"):
		am.set_master_volume(master_volume)
	if am.has_method("set_sfx_volume"):
		am.set_sfx_volume(sfx_volume)
	if am.has_method("set_music_volume"):
		am.set_music_volume(music_volume)


## Przekazuje mnoznik czulosci na lokalnego gracza (GameState.local_player). No-op gdy brak gracza.
func apply_mouse() -> void:
	if GameState == null:
		return
	var p = GameState.local_player
	if p != null and is_instance_valid(p) and p.has_method("set_mouse_sensitivity_mult"):
		p.set_mouse_sensitivity_mult(mouse_sensitivity)


# ============================================================================
#  Helpery
# ============================================================================

func _audio_manager() -> Node:
	# AudioManager to autoload; pobieramy przez root, by nie wiazac sie sztywno (i dzialac w tescie).
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("AudioManager")


## Ustawia property TYLKO gdy obiekt je ma (twardo: 'in') — bezpieczne dla roznych implementacji World.
func _set_if_has(obj: Object, prop: StringName, value: Variant) -> void:
	if obj != null and prop in obj:
		obj.set(prop, value)


func _clamp01(v: float) -> float:
	return clampf(v, 0.0, 1.0)


func _clamp_preset(v: int) -> GraphicsPreset:
	if v == int(GraphicsPreset.HIGH):
		return GraphicsPreset.HIGH
	return GraphicsPreset.LOW
