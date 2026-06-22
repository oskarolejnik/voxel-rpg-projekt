extends CharacterBody3D
## Player.gd — sterowalna postać 3rd-person + kamera orbitalna + RDZEŃ WALKI (ETAP 3, R1).
##
## Sterowanie czytamy bezpośrednio z klawiszy (Input.is_physical_key_pressed),
## żeby prototyp działał bez konfigurowania mapy wejść w edytorze. Później
## przejdziemy na "Input Actions" (czytelniejsze i konfigurowalne przez gracza).
##
## ETAP 3 / RUNDA 1: dołożony rdzeń walki — atak (LMB), unik z i-frames (RMB / Q),
## HP + stamina, combo→przebicie pancerza, take_damage/śmierć/respawn, błysk i knockback,
## sygnały dla HUD. Wszystko współgra z istniejącymi pętlami:
##   _unhandled_input — mysz/kamera + ESC + KLIK LMB/RMB (walka),
##   _process         — WIZUALE: obrót modelu, chód, ANIMACJA ZAMACHU (flaga is_attacking),
##   _physics_process — fizyka: grawitacja, ruch, dash, LICZNIKI czasu walki, move_and_slide.

@export var speed: float = 6.0            # prędkość chodu (m/s)
@export var sprint_speed: float = 10.0    # prędkość biegu (shift)
@export var jump_velocity: float = 7.0    # siła skoku
@export var mouse_sensitivity: float = 0.0025

# ============================================================================
#  STATYSTYKI WALKI (ETAP 3) — eksporty do łatwego strojenia w inspektorze
# ============================================================================

# --- ZDROWIE ---
@export var max_hp: float = 100.0
var hp: float = 100.0                            # publiczne (HUD/wrogowie czytają)

# --- STAMINA ---
@export var max_stamina: float = 100.0
@export var stamina_regen: float = 22.0          # punkty/s, regeneracja
@export var stamina_regen_delay: float = 0.6     # s ciszy po wydatku, zanim rusza regen
@export var dodge_stamina_cost: float = 25.0
@export var sprint_stamina_cost: float = 12.0    # punkty/s podczas biegu
var stamina: float = 100.0                       # publiczne (HUD czyta)
var _stamina_idle: float = 0.0                   # licznik czasu od ostatniego wydatku

# --- ATAK ---
@export var attack_damage: float = 18.0
@export var attack_range: float = 2.2            # m, promień rażenia
@export var attack_arc_dot: float = 0.3          # próg dot() = łuk ~±72° (czyli ~145° z przodu)
@export var attack_cooldown: float = 0.45        # s między zamachami
@export var attack_anim_time: float = 0.28       # s trwania animacji zamachu
var _attack_cd: float = 0.0                      # ile zostało do następnego ciosu
var _attack_anim_t: float = 0.0                  # postęp animacji (>0 = trwa)
var is_attacking: bool = false                   # FLAGA: blokuje chód-anim na rękach

# --- COMBO / PRZEBICIE PANCERZA (sygnatura systemu) ---
@export var combo_window: float = 1.2            # s na kontynuację combo po trafieniu
@export var armor_pierce_per_combo: float = 0.15
@export var armor_pierce_max: float = 0.8
var _combo_count: int = 0
var _combo_timer: float = 0.0                    # odlicza okno combo; 0 = reset

# --- UNIK (dash) ---
@export var dodge_speed: float = 16.0            # m/s zrywu
@export var dodge_time: float = 0.22             # s trwania zrywu
@export var dodge_iframes: float = 0.30          # s nietykalności (lekko dłużej niż dash)
@export var dodge_cooldown: float = 0.55         # s między unikami
var _dodge_t: float = 0.0                        # >0 = trwa dash
var _dodge_cd: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var is_dodging: bool = false

# --- I-FRAMES (nietykalność: unik + po respawnie) ---
var _iframes: float = 0.0                        # s pozostałej nietykalności

# --- RESPAWN ---
@export var respawn_iframes: float = 1.5
var respawn_point: Vector3 = Vector3.ZERO        # ustawiany w _ready() na pozycji startu (i przez Main)
var is_dead: bool = false

# --- KNOCKBACK (gasnący wektor doliczany do ruchu poziomego) ---
var _knockback: Vector3 = Vector3.ZERO

# --- BŁYSK TRAFIENIA (emisja na modelu) ---
var _flash_tween: Tween                          # trzymamy referencję, żeby ubić poprzedni błysk

# --- UNIK z klawiatury (debounce dla KEY_Q) ---
var _q_was_down: bool = false

# --- SYGNAŁY dla HUD i logiki śmierci (HUD podłącza się w Main) ---
signal hp_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal combo_changed(count: int)        # NOWY: HUD pokazuje "Combo xN" (osobna etykieta)
signal died()
signal respawned()

# Grawitacja brana z ustawień projektu (project.godot -> physics/3d/default_gravity).
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)

var _pivot: Node3D        # obrót poziomy kamery (yaw)
var _spring: SpringArm3D  # ramię kamery: pochylenie (pitch) + automatyczna kolizja
var _camera: Camera3D

# Model i pivoty kończyn (zawiasy bark/biodro) — animacja chodu + obrót w kierunku ruchu.
# KOŃCZYNY 2-SEGMENTOWE: górny pivot (bark/biodro) trzyma dolny pivot (łokieć/kolano)
# zagnieżdżony, więc rotation.x dolnego zgina kończynę w stawie. Górny segment (ramię/udo)
# wisi pod górnym pivotem; dolny segment (przedramię+dłoń / łydka+but) pod dolnym pivotem.
var _model: Node3D            # cały model (obrót yaw w kierunku ruchu)
var _torso: Node3D            # tułów+głowa razem — dla body-bob / lean / twist
var _head: Node3D             # sama głowa — stabilizacja/oscylacja niezależna od tułowia
var _arm_l: Node3D            # pivot barku L
var _arm_r: Node3D            # pivot barku R
var _arm_l_lo: Node3D         # pivot łokcia L (dziecko _arm_l)
var _arm_r_lo: Node3D         # pivot łokcia R (dziecko _arm_r)
var _leg_l: Node3D            # pivot biodra L
var _leg_r: Node3D            # pivot biodra R
var _leg_l_lo: Node3D         # pivot kolana L (dziecko _leg_l)
var _leg_r_lo: Node3D         # pivot kolana R (dziecko _leg_r)
var _walk_phase: float = 0.0
# Stan animacji proceduralnej (frame-rate independent, wygładzane lerpami).
var _idle_phase: float = 0.0  # niezależny zegar dla oddychania/weight-shift w idle
var _anim_bob: float = 0.0    # bieżący pionowy bob tułowia (m), wygładzany
var _land_squash: float = 0.0 # 0..1 chwilowy „przysiad" przy lądowaniu, gaśnie
# Logiczne wysokości pivotów (w voxelach) — używane przy budowie i do anim offsetów.
const _HIP_Y: int = 8
const _KNEE_Y: int = 4
const _SHOULDER_Y: int = 14
const _ELBOW_Y: int = 10

# --- GAME FEEL (Faza 0C) ---
@export var ground_accel: float = 55.0     # przyspieszenie na ziemi (m/s^2)
@export var air_accel: float = 14.0        # słabsza kontrola w powietrzu
@export var coyote_time: float = 0.12      # okno skoku tuż po zejściu z krawędzi
@export var jump_buffer_time: float = 0.12 # bufor wciśnięcia skoku przed lądowaniem
@export var fall_gravity_mult: float = 1.5 # mocniejsze opadanie (mniej „księżycowo")
# Auto-step: pokonuj TYLKO niskie progi (~1 voxel). Wyższe ściany/strome zbocza NIE są
# pokonywane (postać się zatrzyma) — koniec „wspinania się po terenie, gdzie nie powinna".
@export var step_height: float = 0.6       # maks. wysokość progu do automatycznego wejścia (m)
@export var step_boost: float = 5.5        # impuls w górę przy wejściu na próg (m/s)
@export var cam_follow: float = 14.0       # szybkość podążania kamery (lag)
@export var trauma_decay: float = 1.6      # zanik wstrząsu kamery /s
@export var shake_pos: float = 0.18        # amplituda przesunięcia kamery
@export var shake_roll: float = 0.06       # amplituda przechyłu kamery (rad)
var _move_vel: Vector3 = Vector3.ZERO      # wygładzona prędkość pozioma (akceleracja)
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _space_was: bool = false
var _trauma: float = 0.0
var _shake_time: float = 0.0
var _shake_noise: FastNoiseLite
var _was_on_floor: bool = true
var _hitstop_active: bool = false

# --- JUICE RUCHU (FOV kick + walk-bob kamery + pył lądowania) ---
@export var base_fov: float = 75.0          # bazowe FOV kamery
@export var sprint_fov_add: float = 9.0     # ile FOV dokładamy przy biegu
@export var fov_lerp: float = 8.0           # szybkość zmiany FOV
@export var cam_bob_amount: float = 0.035   # amplituda walk-bob kamery (m) — MAŁA, by nie mdliło
var _cam_bob_phase: float = 0.0             # faza walk-bob kamery (czas*tempo)
var _land_dust: GPUParticles3D              # one-shot pył przy lądowaniu (reuse wzorca z Main)

func _ready() -> void:
	_build_body()     # kształt kolizji + widoczny model (kapsuła)
	_build_camera()   # kamera 3rd-person z ramieniem

	# --- Inicjalizacja walki (ETAP 3) ---
	add_to_group("player")          # by wrogowie mogli nas znaleźć fallbackiem (get_first_node_in_group)
	# Warstwy kolizji: gracz na warstwie 2, ale zderza się WYŁĄCZNIE z terenem (warstwa 1).
	# Dzięki temu stado wrogów (warstwa 3) nie spycha gracza — AI i tak działa po dystansie XZ,
	# a chód/auto-podskok po terenie zostają nienaruszone.
	collision_layer = 1 << 1        # warstwa 2 (bit 1) = gracz
	collision_mask = 1              # maska = tylko teren (warstwa 1, bit 0)
	hp = max_hp
	stamina = max_stamina
	# Punkt odrodzenia = miejsce startu. Main ustawia position PRZED add_child, więc w _ready()
	# global_position jest już poprawne (na terenie z 2 m zapasu). Main może to też nadpisać.
	respawn_point = global_position
	# Emisja startowa w call_deferred — HUD podłącza sygnały dopiero po _ready() gracza.
	call_deferred("emit_signal", "hp_changed", hp, max_hp)
	call_deferred("emit_signal", "stamina_changed", stamina, max_stamina)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # chowamy i łapiemy kursor

func _build_body() -> void:
	# Kolizja (kapsuła), przesunięta tak, by stała "stopami" na ziemi.
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 2.0
	capsule.radius = 0.4
	shape.shape = capsule
	shape.position = Vector3(0.0, 1.0, 0.0)
	add_child(shape)

	# Widoczny model: voxelowa postać z małych kostek (styl Cube World).
	_build_voxel_character()

# ============================================================================
#  DETALICZNA POSTAĆ Z MALUTKICH VOXELI (styl Cube World, chibi adventurer)
# ============================================================================
# Każda grupa ciała = jeden zbatchowany ArrayMesh z drobnych kostek (vertex color),
# z cullingiem wewnętrznych ścian (przez VoxelModel). Głowa+tułów statyczne na _model;
# ręce/nogi na pivotach (bark/biodro) -> istniejąca animacja chodu/ataku BEZ ZMIAN.
# Materiał: StandardMaterial3D z vertex_color_use_as_albedo, by _flash_hit() (rzut
# `as StandardMaterial3D`) działał dalej, a kolory były wbudowane w jeden materiał.
#
# Skala: VS = 0.09 m/voxel (~5.5× drobniej niż teren 0,5 m) => kontrast Cube World.
# Siatka logiczna (Vector3i, oś Y od stóp): najwyższy voxel to „ahoge" na logicznym y=25
# (czapa włosów sięga y=24), więc górna ściana modelu = 26 × VS = 26 × 0,09 ≈ 2,34 m. Kapsuła
# kolizji ma height=2.0 (środek y=1.0 => biegun na y=2.0), więc CZUBEK GŁOWY wystaje ~0,34 m
# PONAD kapsułę. To CELOWE i bezpieczne: kapsuła służy tylko kolizji (stopy poprawnie na y=0,
# postać nie wnika w teren); jedynie pod bardzo niskim nawisem czubek włosów mógłby wizualnie
# przeniknąć sufit. Chcąc pełnego zamknięcia w kapsule: ustaw capsule.height=2.4 i
# shape.position.y=1.2 w _build_body(), albo zbij VS do ~0.077 (26×0.077≈2,00 m).
const VS: float = 0.09

# Buduje voxelową postać. Tułów+głowa na _torso/_head (anim bob/lean/twist + stabilizacja głowy);
# ręce i nogi jako 2-segmentowe łańcuchy pivotów (bark->łokieć, biodro->kolano).
func _build_voxel_character() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	var mat := _make_char_material()

	# --- TUŁÓW (węzeł animowany: bob/lean/twist) — pivot w pasie (y=_HIP_Y), by lean/twist
	#     obracał się od bioder, a głowa siedziała wyżej. Geometria tułowia bake'owana z
	#     offsetem -_HIP_Y, więc pas leży w (0,0,0) węzła _torso.
	_torso = _make_pivot(_model, Vector3(0.0, float(_HIP_Y) * VS, 0.0))
	var torso := VoxelModel.VoxelDef.new()
	_sculpt_torso(torso)
	_add_model_mesh(_torso, torso, mat, Vector3i(0, _HIP_Y, 0))

	# --- GŁOWA (osobny węzeł na szczycie tułowia: stabilizacja/oscylacja) — pivot u nasady
	#     szyi (y=_SHOULDER_Y), dziecko _torso, więc dziedziczy bob/lean, a dokłada własny ruch.
	_head = _make_pivot(_torso, Vector3(0.0, float(_SHOULDER_Y - _HIP_Y) * VS, 0.0))
	var head := VoxelModel.VoxelDef.new()
	_sculpt_head(head)
	_add_model_mesh(_head, head, mat, Vector3i(0, _SHOULDER_Y, 0))

	# --- NOGI (2 segmenty): biodro (y=_HIP_Y) -> kolano (y=_KNEE_Y zagnieżdżony) ---
	# Udo bake'owane pod biodrem (offset -_HIP_Y). Łydka+but pod kolanem (offset -_KNEE_Y),
	# a sam pivot kolana jest dzieckiem biodra na wysokości (_KNEE_Y-_HIP_Y)*VS poniżej.
	_leg_l = _make_pivot(_model, Vector3(-2.0 * VS, float(_HIP_Y) * VS, 0.0))
	_leg_r = _make_pivot(_model, Vector3( 2.0 * VS, float(_HIP_Y) * VS, 0.0))
	_leg_l_lo = _make_pivot(_leg_l, Vector3(0.0, float(_KNEE_Y - _HIP_Y) * VS, 0.0))
	_leg_r_lo = _make_pivot(_leg_r, Vector3(0.0, float(_KNEE_Y - _HIP_Y) * VS, 0.0))
	var thigh_l := VoxelModel.VoxelDef.new(); _sculpt_thigh(thigh_l, -1)
	var thigh_r := VoxelModel.VoxelDef.new(); _sculpt_thigh(thigh_r, 1)
	var shin_l := VoxelModel.VoxelDef.new(); _sculpt_shin(shin_l, -1)
	var shin_r := VoxelModel.VoxelDef.new(); _sculpt_shin(shin_r, 1)
	# Udo: geometria liczona w globalnych X (x0 zależny od side), więc pivot w X przesuwamy
	#      kompensacyjnie — patrz offset z PEŁNYM Vector3i (x = ±2) by zawias leżał w osi nogi.
	_add_model_mesh(_leg_l, thigh_l, mat, Vector3i(-2, _HIP_Y, 0))
	_add_model_mesh(_leg_r, thigh_r, mat, Vector3i( 2, _HIP_Y, 0))
	_add_model_mesh(_leg_l_lo, shin_l, mat, Vector3i(-2, _KNEE_Y, 0))
	_add_model_mesh(_leg_r_lo, shin_r, mat, Vector3i( 2, _KNEE_Y, 0))

	# --- RĘCE (2 segmenty): bark (y=_SHOULDER_Y) -> łokieć (y=_ELBOW_Y zagnieżdżony) ---
	_arm_l = _make_pivot(_model, Vector3(-5.0 * VS, float(_SHOULDER_Y) * VS, 0.0))
	_arm_r = _make_pivot(_model, Vector3( 5.0 * VS, float(_SHOULDER_Y) * VS, 0.0))
	_arm_l_lo = _make_pivot(_arm_l, Vector3(0.0, float(_ELBOW_Y - _SHOULDER_Y) * VS, 0.0))
	_arm_r_lo = _make_pivot(_arm_r, Vector3(0.0, float(_ELBOW_Y - _SHOULDER_Y) * VS, 0.0))
	var uarm_l := VoxelModel.VoxelDef.new(); _sculpt_upper_arm(uarm_l, -1)
	var uarm_r := VoxelModel.VoxelDef.new(); _sculpt_upper_arm(uarm_r, 1)
	var farm_l := VoxelModel.VoxelDef.new(); _sculpt_forearm(farm_l, -1)
	var farm_r := VoxelModel.VoxelDef.new(); _sculpt_forearm(farm_r, 1)
	_add_model_mesh(_arm_l, uarm_l, mat, Vector3i(-5, _SHOULDER_Y, 0))
	_add_model_mesh(_arm_r, uarm_r, mat, Vector3i( 5, _SHOULDER_Y, 0))
	_add_model_mesh(_arm_l_lo, farm_l, mat, Vector3i(-5, _ELBOW_Y, 0))
	_add_model_mesh(_arm_r_lo, farm_r, mat, Vector3i( 5, _ELBOW_Y, 0))

# Bakuje JEDNĄ grupę voxeli do zbatchowanego ArrayMesh i wiesza pod 'parent'.
# pivot_vox = logiczny punkt obrotu (w voxelach); geometrię przesuwamy o -pivot*VS,
# żeby zawias leżał w (0,0,0) węzła (animacja rotation.x bez zmian).
func _add_model_mesh(parent: Node3D, def: VoxelModel.VoxelDef, mat: Material, pivot_vox: Vector3i) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelModel.build_mesh(def, VS, -Vector3(pivot_vox) * VS)
	# KAŻDY segment dostaje WŁASNĄ kopię materiału (duplicate) — zgodnie z kontraktem opisanym
	# przy _make_char_material(). _flash_hit() i tak iteruje per mesh (idempotentnie), ale własna
	# kopia umożliwia per-segment albedo/emisję (np. tint jednej kończyny) bez wpływu na resztę.
	mi.material_override = mat.duplicate()
	parent.add_child(mi)

# Materiał postaci: vertex-color jako albedo, matowy. To WZORZEC — _add_model_mesh() robi
# .duplicate() na każdy segment, więc KAŻDA grupa ma WŁASNĄ kopię materiału (per-mesh albedo/
# emisja możliwe niezależnie; _flash_hit() ustawia emisję per mesh).
func _make_char_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true   # spójnie z paletą sRGB (Blocks)
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat

# Tworzy węzeł-zawias (pivot) kończyny w danym punkcie modelu.
func _make_pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p

# --- RZEŹBIENIE GRUP CIAŁA (siatka voxeli całkowitych, y=0 = poziom stóp) ---
# Konwencja: x = lewo(-)/prawo(+) WIDZA, y = w górę, z = przód(-)/tył(+). Front twarzy = -Z.

# Paleta postaci (sRGB; vertex_color_is_srgb=true w materiale).
const _C_SKIN    := Color(0.95, 0.78, 0.62)
const _C_SKIN_SH := Color(0.86, 0.68, 0.53)   # cień skóry (szyja/nos)
const _C_BLUSH   := Color(0.93, 0.62, 0.55)
const _C_HAIR    := Color(0.40, 0.24, 0.12)
const _C_HAIR_HI := Color(0.52, 0.33, 0.17)
const _C_EYE_W   := Color(0.97, 0.97, 0.98)
const _C_IRIS    := Color(0.20, 0.46, 0.72)
const _C_PUPIL   := Color(0.05, 0.05, 0.07)
const _C_MOUTH   := Color(0.62, 0.34, 0.34)
const _C_TUNIC   := Color(0.20, 0.52, 0.36)
const _C_TUNIC_SH := Color(0.15, 0.40, 0.28)
const _C_TRIM    := Color(0.86, 0.78, 0.42)   # złota lamówka/naramiennik
const _C_BELT    := Color(0.34, 0.22, 0.12)
const _C_BUCKLE  := Color(0.82, 0.72, 0.34)
const _C_PANTS   := Color(0.28, 0.32, 0.50)
const _C_PANTS_SH := Color(0.22, 0.25, 0.40)
const _C_BOOTS   := Color(0.26, 0.18, 0.12)
const _C_BOOTS_HI := Color(0.36, 0.26, 0.17)
const _C_SOLE    := Color(0.16, 0.12, 0.09)   # ciemna podeszwa (czytelny styk z ziemią)
const _C_CAPE    := Color(0.62, 0.20, 0.22)   # peleryna (akcent koloru z tyłu)
const _C_CAPE_SH := Color(0.48, 0.14, 0.16)
const _C_LEATHER := Color(0.45, 0.30, 0.18)   # rękawice/naramiennik skórzany
const _C_EAR     := _C_SKIN

# GŁOWA (chibi-Veloren: duża, wyrazista) — czaszka + włosy + uszy + twarz. Logiczny y 14..26.
func _sculpt_head(d: VoxelModel.VoxelDef) -> void:
	# Czaszka 9×9×9 (x[-4..4], y[15..23], z[-4..4]).
	d.fill_box(Vector3i(-4, 15, -4), Vector3i(5, 24, 5), _C_SKIN)
	# Szyja (krótka, ciemniejsza skóra) łączy z tułowiem.
	d.fill_box(Vector3i(-2, 14, -2), Vector3i(2, 15, 2), _C_SKIN_SH)
	# Ścięcie 4 górnych rogów + dolnych przednich rogów szczęki (mniej „pudełkowo", lekki podbródek).
	for cx in [-4, 4]:
		for cz in [-4, 4]:
			d.cells.erase(Vector3i(cx, 23, cz))
	for cx in [-4, 4]:
		d.cells.erase(Vector3i(cx, 15, -4))   # zwężenie szczęki u dołu z przodu
	# USZY (boczne, skóra) — 1 voxel wystający na y17..18, czytelny zarys.
	d.set_voxel(Vector3i(-5, 17, 0), _C_EAR); d.set_voxel(Vector3i(-5, 18, 0), _C_EAR)
	d.set_voxel(Vector3i( 5, 17, 0), _C_EAR); d.set_voxel(Vector3i( 5, 18, 0), _C_EAR)
	# WŁOSY: czapa na górze + boki/tył + grzywka warstwowa + 1 kosmyk „ahoge".
	d.fill_box(Vector3i(-4, 22, -4), Vector3i(5, 25, 5), _C_HAIR)   # czapa (y22..24)
	d.fill_box(Vector3i(-4, 16, 3), Vector3i(5, 24, 5), _C_HAIR)    # tył (+Z), aż pod czapę
	d.fill_box(Vector3i(-4, 16, -4), Vector3i(-3, 24, 5), _C_HAIR)  # lewy bok
	d.fill_box(Vector3i(4, 16, -4), Vector3i(5, 24, 5), _C_HAIR)    # prawy bok
	d.fill_box(Vector3i(-4, 20, -5), Vector3i(5, 23, -4), _C_HAIR)  # grzywka na czole (front -Z)
	# Warstwowe kosmyki grzywki (nierówny dolny brzeg = mniej „kask").
	for hx in [-4, -1, 3]:
		d.set_voxel(Vector3i(hx, 19, -5), _C_HAIR)                  # dłuższe kosmyki opadające niżej
	for hx in [-3, 0, 2, 4]:
		d.set_voxel(Vector3i(hx, 20, -5), _C_HAIR_HI)              # rozjaśnione pasemka (połysk)
	d.set_voxel(Vector3i(0, 25, -1), _C_HAIR_HI)                   # ahoge — pojedynczy kosmyk na czubku
	# Połysk na czubku czapy (kierunek światła z góry-przodu).
	for hx in [-2, 0, 2]:
		d.set_voxel(Vector3i(hx, 24, -3), _C_HAIR_HI)
	# TWARZ (front -Z, warstwa z=-5 jako „naklejka" na lico z=-4).
	# Oczy duże (sygnatura chibi): białko 2×szer na y17..19 z górną kreską rzęs.
	for ex in [-3, 2]:
		d.fill_box(Vector3i(ex, 17, -5), Vector3i(ex + 2, 20, -4), _C_EYE_W)
	# Tęczówki (2 wys.) + źrenice + górne podkreślenie (rzęsy). Patrzą lekko do środka.
	d.set_voxel(Vector3i(-2, 17, -5), _C_IRIS); d.set_voxel(Vector3i(-2, 18, -5), _C_PUPIL)
	d.set_voxel(Vector3i( 2, 17, -5), _C_IRIS); d.set_voxel(Vector3i( 2, 18, -5), _C_PUPIL)
	d.set_voxel(Vector3i(-2, 19, -5), _C_PUPIL); d.set_voxel(Vector3i(2, 19, -5), _C_PUPIL)  # kreska rzęs (góra oka)
	# Brwi (kreska włosów nad oczami, lekko uniesione = przyjazny wyraz).
	d.set_voxel(Vector3i(-3, 20, -5), _C_HAIR); d.set_voxel(Vector3i(-2, 20, -5), _C_HAIR)
	d.set_voxel(Vector3i( 2, 20, -5), _C_HAIR); d.set_voxel(Vector3i( 3, 20, -5), _C_HAIR)
	# Rumieńce (pod oczami, na policzkach).
	d.set_voxel(Vector3i(-3, 16, -5), _C_BLUSH); d.set_voxel(Vector3i(3, 16, -5), _C_BLUSH)
	# NOS: grzbiet 2 voxele (y16..17) z cieniem — daje głębię profilu.
	d.set_voxel(Vector3i(0, 17, -5), _C_SKIN); d.set_voxel(Vector3i(0, 16, -5), _C_SKIN_SH)
	# USTA: lekki uśmiech (3 voxele, środek niżej).
	d.set_voxel(Vector3i(-1, 15, -5), _C_MOUTH); d.set_voxel(Vector3i(1, 15, -5), _C_MOUTH)
	d.set_voxel(Vector3i(0, 15, -5), _C_MOUTH)

# TUŁÓW (tunika + pasek + lamówka + naramienniki + peleryna). Logiczny y 8..15.
func _sculpt_torso(d: VoxelModel.VoxelDef) -> void:
	# Tunika x[-4..4] (9 voxeli, środek 0 — symetria z głową), y[8..14], z[-2..1].
	d.fill_box(Vector3i(-4, 8, -2), Vector3i(5, 15, 2), _C_TUNIC)
	# Zwężenie w pasie (talia): ścinamy skrajne X w dolnym rzędzie -> sylwetka „klepsydra".
	for cz in range(-2, 2):
		d.cells.erase(Vector3i(-4, 8, cz)); d.cells.erase(Vector3i(4, 8, cz))
	# Klatka szersza u góry: dołóż barki (y13..14) na pełną szerokość rękawów.
	d.fill_box(Vector3i(-5, 13, -2), Vector3i(6, 15, 2), _C_TUNIC)
	# Cień/fałdy (bryła nie jest płaska).
	d.fill_box(Vector3i(-4, 8, 1), Vector3i(5, 15, 2), _C_TUNIC_SH)    # plecy (+Z)
	d.fill_box(Vector3i(-4, 8, -2), Vector3i(-3, 13, 2), _C_TUNIC_SH)  # lewy bok
	d.fill_box(Vector3i(4, 8, -2), Vector3i(5, 13, 2), _C_TUNIC_SH)    # prawy bok
	# Złota lamówka pod szyją (dekolt w V) + rząd 3 guzików na froncie (z=-3 „nakładka").
	d.fill_box(Vector3i(-2, 14, -3), Vector3i(3, 15, -2), _C_TRIM)
	d.set_voxel(Vector3i(0, 13, -3), _C_TRIM)
	d.set_voxel(Vector3i(0, 12, -3), _C_TRIM)
	d.set_voxel(Vector3i(0, 11, -3), _C_TRIM)
	# Naramienniki (złoto na szczycie barków, y14) — akcent „zbroja lekka".
	d.fill_box(Vector3i(-5, 14, -2), Vector3i(-3, 15, 2), _C_TRIM)
	d.fill_box(Vector3i(3, 14, -2), Vector3i(5, 15, 2), _C_TRIM)
	# Pasek (y8..9) dookoła + klamra na froncie. x[-3..3] (po zwężeniu talii).
	d.fill_box(Vector3i(-3, 8, -3), Vector3i(4, 9, 2), _C_BELT)
	d.set_voxel(Vector3i(0, 8, -3), _C_BUCKLE)
	d.set_voxel(Vector3i(-1, 8, -3), _C_BUCKLE)
	# PELERYNKA: warstwa na plecach (+Z), od barków w dół, akcent koloru i ruch sylwetki.
	d.fill_box(Vector3i(-4, 8, 2), Vector3i(5, 15, 3), _C_CAPE)
	d.fill_box(Vector3i(-4, 8, 2), Vector3i(-2, 15, 3), _C_CAPE_SH)    # cień fałdy (lewa)
	d.fill_box(Vector3i(2, 8, 2), Vector3i(5, 15, 3), _C_CAPE_SH)      # cień fałdy (prawa)
	# Zapinka peleryny na barkach (złoto).
	d.set_voxel(Vector3i(-3, 14, 2), _C_TRIM); d.set_voxel(Vector3i(3, 14, 2), _C_TRIM)

# UDO (górny segment nogi, w spodniach). side = -1 (lewa) / +1 (prawa). Logiczny y 4..8.
# X-zakres: lewa [-3..-1], prawa [1..2] -> 2 voxele szer. (spójnie z biodrem/kolanem).
func _sculpt_thigh(d: VoxelModel.VoxelDef, side: int) -> void:
	var x0 := (-3 if side < 0 else 1)
	# Udo: y4..7 (zwęża się ku kolanu — przednia ściana pełna, tył w cieniu).
	d.fill_box(Vector3i(x0, 4, -1), Vector3i(x0 + 2, 8, 2), _C_PANTS)
	d.fill_box(Vector3i(x0, 4, 1), Vector3i(x0 + 2, 8, 2), _C_PANTS_SH)   # cień z tyłu
	# Boczna kieszeń/fałda (1 voxel akcentu na zewnętrznej stronie uda).
	var outer := (x0 if side < 0 else x0 + 1)
	d.set_voxel(Vector3i(outer, 6, -1), _C_PANTS_SH)

# ŁYDKA + BUT (dolny segment nogi). side = -1/+1. Logiczny y 0..4 (kolano u góry).
func _sculpt_shin(d: VoxelModel.VoxelDef, side: int) -> void:
	var x0 := (-3 if side < 0 else 1)
	# Łydka w spodniach: y2..3 (nad cholewką buta).
	d.fill_box(Vector3i(x0, 2, -1), Vector3i(x0 + 2, 4, 2), _C_PANTS)
	d.fill_box(Vector3i(x0, 2, 1), Vector3i(x0 + 2, 4, 2), _C_PANTS_SH)   # cień z tyłu
	# But: y0..2, dłuższy w przód (czubek na -Z, palce); cholewka (y2) ciemniejsza.
	d.fill_box(Vector3i(x0, 1, -2), Vector3i(x0 + 2, 3, 2), _C_BOOTS)
	d.fill_box(Vector3i(x0, 2, -1), Vector3i(x0 + 2, 3, 2), _C_BOOTS_HI)   # rant cholewki (połysk)
	d.fill_box(Vector3i(x0, 1, -2), Vector3i(x0 + 2, 2, -1), _C_BOOTS_HI)  # czubek buta (palce)
	# Podeszwa (y0) — ciemna, czytelny styk z gruntem (foot-plant feel).
	d.fill_box(Vector3i(x0, 0, -2), Vector3i(x0 + 2, 1, 2), _C_SOLE)

# RAMIĘ górne (rękaw tuniki + naramiennik). side = -1/+1. Logiczny y 10..14 (bark u góry).
# X tuż obok tułowia: lewa [-6..-5], prawa [4..5].
func _sculpt_upper_arm(d: VoxelModel.VoxelDef, side: int) -> void:
	var x0 := (-6 if side < 0 else 4)
	# Rękaw tuniki: y10..13 (od barku do łokcia).
	d.fill_box(Vector3i(x0, 10, -1), Vector3i(x0 + 2, 14, 2), _C_TUNIC)
	d.fill_box(Vector3i(x0, 10, 1), Vector3i(x0 + 2, 14, 2), _C_TUNIC_SH)  # cień rękawa
	d.fill_box(Vector3i(x0, 13, -2), Vector3i(x0 + 2, 14, 2), _C_TRIM)     # naramiennik (złoto)

# PRZEDRAMIĘ + DŁOŃ (dolny segment ręki). side = -1/+1. Logiczny y 6..10 (łokieć u góry).
func _sculpt_forearm(d: VoxelModel.VoxelDef, side: int) -> void:
	var x0 := (-6 if side < 0 else 4)
	# Przedramię w skórzanym karwaszu: y8..9.
	d.fill_box(Vector3i(x0, 8, -1), Vector3i(x0 + 2, 10, 2), _C_LEATHER)
	d.fill_box(Vector3i(x0, 8, 1), Vector3i(x0 + 2, 10, 2), _C_TUNIC_SH)   # cień z tyłu
	# DŁOŃ (skóra): y6..8, z zarysem KCIUKA (1 voxel po wewnętrznej stronie, ku tułowiu).
	d.fill_box(Vector3i(x0, 6, -1), Vector3i(x0 + 2, 8, 1), _C_SKIN)
	var thumb_x := (x0 + 2 if side < 0 else x0 - 1)   # kciuk od strony tułowia
	d.set_voxel(Vector3i(thumb_x, 7, 0), _C_SKIN)
	# Zaciśnięte palce (kostki) — drobny cień na grzbiecie dłoni (przód -Z).
	d.set_voxel(Vector3i(x0, 6, -1), _C_SKIN_SH); d.set_voxel(Vector3i(x0 + 1, 6, -1), _C_SKIN_SH)

func _build_camera() -> void:
	# Pivot: obraca się tylko w poziomie (yaw). NIE obracamy całej postaci,
	# żeby kamera i ruch się nie "biły".
	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	_pivot.position = Vector3(0.0, 1.6, 0.0)  # na wysokości "głowy"
	add_child(_pivot)

	# SpringArm: odsuwa kamerę do tyłu i automatycznie ją przysuwa,
	# gdy coś zasłoni (np. ściana), żeby nie patrzeć przez geometrię.
	_spring = SpringArm3D.new()
	_spring.spring_length = 5.0
	_pivot.add_child(_spring)

	_camera = Camera3D.new()
	_camera.fov = base_fov           # bazowe FOV (sprint kick podbija je w _process)
	_spring.add_child(_camera)
	_camera.current = true

	# Pył lądowania (one-shot GPUParticles, wzorzec jak ambient w Main): tworzony raz, ponownie
	# „odpalany" przez restart() przy każdym lądowaniu. local_coords=false — pył zostaje w świecie.
	_land_dust = _make_land_dust()
	add_child(_land_dust)

	# Game feel (0C): kamera ODPIĘTA od gracza (top_level) — podąża z wygładzeniem w _process.
	_pivot.top_level = true
	_pivot.global_position = global_position + Vector3(0.0, 1.6, 0.0)
	# Interpolacja fizyki jest WŁ. globalnie, ale pivot pozycjonujemy ręcznie w _process
	# (już w tempie klatek) — wyłączamy go z interpolacji silnika, by nie był wygładzany
	# podwójnie (co dawałoby lag/smużenie kamery). Dzieci (spring/kamera) dziedziczą OFF.
	_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_shake_noise = FastNoiseLite.new()
	_shake_noise.seed = 7
	_shake_noise.frequency = 1.0

# Tworzy one-shot „obłoczek" pyłu pod stopami (wzorzec GPUParticles jak ambient w Main.gd).
# emitting=false na starcie; lądowanie woła restart()+emitting=true (one_shot sam wygasza).
func _make_land_dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 0.9       # cały burst naraz (puff), nie strużka
	p.local_coords = false      # pył zostaje w świecie, gdy postać biegnie dalej
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.gravity = Vector3(0.0, -1.2, 0.0)         # lekko opada
	pm.direction = Vector3(0.0, 0.3, 0.0)
	pm.spread = 75.0                              # rozłazi się na boki (płaski obłok)
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.4
	pm.damping_min = 2.0
	pm.damping_max = 4.0                          # szybko hamuje (puff, nie eksplozja)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.16, 0.16)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.74, 0.68, 0.56, 0.7)   # piaskowy kurz
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = mat
	p.draw_pass_1 = mesh
	return p

# Odpala obłoczek pyłu u stóp (siła ~ prędkość upadku). Wołane z _physics_process przy lądowaniu.
func _spawn_land_dust(strength: float) -> void:
	if _land_dust == null:
		return
	_land_dust.global_position = global_position    # u stóp (origin postaci = y=0)
	_land_dust.amount = int(clampf(10.0 + strength * 22.0, 10.0, 28.0))
	_land_dust.restart()
	_land_dust.emitting = true

func _unhandled_input(event: InputEvent) -> void:
	# Ruch myszy obraca kamerę (gdy kursor jest złapany).
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		_spring.rotate_x(-event.relative.y * mouse_sensitivity)
		# Ogranicz pochylenie, żeby nie "przekręcić" kamery.
		_spring.rotation.x = clampf(_spring.rotation.x, deg_to_rad(-70.0), deg_to_rad(30.0))

	# ESC: pokaż/ukryj kursor (przydatne, żeby wyjść z gry).
	if event.is_action_pressed("ui_cancel"):
		_toggle_mouse()

	# --- WALKA: klik myszy (tylko gdy kursor złapany, by klik w odsłoniętym kursorze nie atakował) ---
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_attack()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_try_dodge()

func _toggle_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# Game feel (0C): kamera podąża z wygładzeniem/lagiem + trauma-shake + (JUICE) FOV kick i walk-bob.
func _update_camera(delta: float) -> void:
	if _pivot == null:
		return
	# Podążaj za INTERPOLOWANĄ pozycją gracza (gładką między krokami fizyki), nie za
	# surową global_position (skokową w tempie fizyki) — inaczej kamera „skacze".
	var target := get_global_transform_interpolated().origin + Vector3(0.0, 1.6, 0.0)
	_pivot.global_position = _pivot.global_position.lerp(target, 1.0 - exp(-cam_follow * delta))
	_trauma = maxf(0.0, _trauma - trauma_decay * delta)
	var s := _trauma * _trauma
	if _camera == null:
		return

	# JUICE: SPRINT FOV KICK — przy biegu FOV rośnie (poczucie pędu), wraca przy chodzie/staniu.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var is_sprint := hspeed > speed + 0.6 and is_on_floor()
	var fov_target := base_fov + (sprint_fov_add if is_sprint else 0.0)
	_camera.fov = lerpf(_camera.fov, fov_target, _sm(fov_lerp, delta))

	# JUICE: WALK-BOB kamery (MAŁY) — pionowe „tętno" kroku, tylko przy ruchu po ziemi.
	var bob_off := Vector3.ZERO
	if hspeed > 0.6 and is_on_floor():
		_cam_bob_phase += delta * hspeed * 1.9
		var amp := cam_bob_amount * clampf(hspeed / sprint_speed, 0.4, 1.0)
		bob_off.y = -absf(sin(_cam_bob_phase)) * amp       # opada na każdym kroku
		bob_off.x = sin(_cam_bob_phase) * amp * 0.4        # delikatne kołysanie boczne
	else:
		_cam_bob_phase = 0.0

	if s > 0.0:
		# Wstrząs dominuje nad walk-bobem (lądowanie/trafienie) — krótkie, więc OK.
		_shake_time += delta
		var nx := _shake_noise.get_noise_2d(_shake_time * 50.0, 0.0)
		var ny := _shake_noise.get_noise_2d(0.0, _shake_time * 50.0)
		var nr := _shake_noise.get_noise_2d(_shake_time * 50.0, 99.0)
		_camera.position = Vector3(nx, ny, 0.0) * s * shake_pos + bob_off
		_camera.rotation.z = nr * s * shake_roll
	else:
		_camera.position = _camera.position.lerp(bob_off, _sm(12.0, delta))
		_camera.rotation.z = lerpf(_camera.rotation.z, 0.0, _sm(12.0, delta))

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

# ============================================================================
#  ANIMACJA PROCEDURALNA (Veloren-feel: ciężar, foot-plant, przeciwfaza, zgięcia)
# ============================================================================
# Cała animacja jest FRAME-RATE INDEPENDENT:
#  * ruch cykliczny = sin/cos(_walk_phase), gdzie _walk_phase += delta*tempo (czas, nie klatki),
#  * wygładzanie/dosztywnianie = lerp z czynnikiem 1-exp(-k*delta) (stała szybkość niezależna od FPS).
# Konwencja stawów. Segmenty WISZĄ poniżej swoich pivotów (y<0 względem zawiasu). Obrót wokół
# +X: z' = y*sinθ, więc dla y<0: θ>0 => z'<0 (segment do PRZODU, -Z), θ<0 => z'>0 (do TYŁU, +Z).
# Stąd kierunki naturalnych zgięć:
#   * udo/bark w PRZÓD  => rotation.x DODATNI (a w tył => ujemny),
#   * KOLANO (pięta ku górze, do TYŁU) => rotation.x UJEMNY na dolnym pivocie,
#   * ŁOKIEĆ (dłoń ku twarzy, do PRZODU) => rotation.x DODATNI na dolnym pivocie.
# (Zachowujemy fazowanie hip = -sin(phase), zgodne z oryginalnym, działającym chodem.)

# Wygładzanie wykładnicze (frame-rate independent): zwraca alpha do lerp(a,b,alpha).
func _sm(k: float, delta: float) -> float:
	return 1.0 - exp(-k * delta)

# Wizualne: wybór stanu animacji + tułów (bob/lean/twist) + stabilizacja głowy. Sterownik główny.
func _process(delta: float) -> void:
	_update_camera(delta)
	if _model == null:
		return

	# --- Regeneracja staminy w czasie (po krótkiej ciszy od ostatniego wydatku), gdy gracz żyje ---
	if not is_dead:
		_stamina_idle += delta
		if _stamina_idle >= stamina_regen_delay and stamina < max_stamina:
			stamina = minf(max_stamina, stamina + stamina_regen * delta)
			stamina_changed.emit(stamina, max_stamina)

	# --- Pomiary stanu ---
	var hvel := Vector2(velocity.x, velocity.z)
	var hspeed := hvel.length()
	var on_floor := is_on_floor()
	var sprinting := hspeed > speed + 0.6        # próg „bieg" (powyżej zwykłej prędkości chodu)
	_idle_phase += delta                          # zegar idle (oddychanie) — biegnie zawsze
	# Gaśnięcie przysiadu lądowania (squash) — niezależne od FPS.
	_land_squash = maxf(0.0, _land_squash - delta * 4.0)

	# --- OBRÓT MODELU w stronę ruchu (lub w stronę kamery podczas ataku) ---
	if is_attacking:
		_model.rotation.y = lerp_angle(_model.rotation.y, _pivot.rotation.y, _sm(18.0, delta))
	elif hspeed > 0.5:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, _sm(12.0, delta))

	# --- WYBÓR STANU NÓG/RĄK ---
	# Priorytet: powietrze > chód/bieg > idle. Atak nadpisuje TYLKO ręce (nogi grają normalnie).
	if not on_floor:
		_anim_air(delta, hspeed)
	elif hspeed > 0.6:
		_anim_locomotion(delta, hspeed, sprinting)
	else:
		_anim_idle(delta)

	# Atak nadpisuje ramiona (po wyliczeniu lokomocji/idle dla nóg i tułowia).
	if is_attacking:
		_anim_attack_arms(delta)

	# --- TUŁÓW: pionowy bob + lean (do przodu wg prędkości) + twist (wg fazy kroku) ---
	_animate_torso(delta, hspeed, on_floor, sprinting)
	# --- GŁOWA: stabilizacja (kompensuje bob/lean tułowia) + subtelny oddech-nod ---
	_animate_head(delta, hspeed)

# --- CHÓD / BIEG -----------------------------------------------------------
# Zamach ramion w PRZECIWFAZIE do nóg; kolano/łokieć zginają się w fazie PRZENOSZENIA nogi;
# stopa „trzyma" (foot-plant) w fazie podporu (zgięcie kolana ~0, gdy noga z tyłu/pod ciałem).
func _anim_locomotion(delta: float, hspeed: float, sprinting: bool) -> void:
	# Tempo kroku rośnie z prędkością; bieg ma większą amplitudę zamachu.
	_walk_phase += delta * hspeed * (2.0 if sprinting else 1.8)
	var swing := (0.95 if sprinting else 0.6)          # amplituda zamachu uda/ramienia (rad)
	var ph := _walk_phase
	var s := sin(ph)

	# NOGI — górne pivoty (biodra): przeciwne fazy L/R.
	var hip_l := -s * swing
	var hip_r :=  s * swing
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, hip_l, _sm(20.0, delta))
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, hip_r, _sm(20.0, delta))
	# KOLANA — zginają się TYLKO w fazie przenoszenia (noga unoszona z tyłu, pięta ku górze).
	# Kolano zgina się DO TYŁU => UJEMNY rotation.x (segment poniżej pivota: <0 = +Z/tył).
	# max(0,...) zeruje zgięcie w fazie podporu => stopa „trzyma" grunt (foot-plant feel).
	var bend := (1.7 if sprinting else 1.2)            # maks. zgięcie kolana (rad)
	# Kolano zgina się w fazie PRZENOSZENIA (udo idzie do PRZODU). Udo L jedzie do przodu, gdy
	# hip_l = -sin(ph) > 0, czyli sin(ph) < 0; szczyt wymachu przy ph=3π/2 (mid-swing). Funkcja
	# -cos(ph) > 0 dokładnie na (π/2, 3π/2) z pikiem w ph=π => bend pokrywa się z mid-swingiem,
	# a podczas podporu (udo do tyłu) kolano jest PROSTE => stopa „trzyma" grunt (foot-plant).
	var knee_l := -maxf(0.0, -cos(ph)) * bend          # L: zgięcie w fazie przenoszenia (mid-swing)
	var knee_r := -maxf(0.0,  cos(ph)) * bend          # R: przeciwfaza
	_leg_l_lo.rotation.x = lerpf(_leg_l_lo.rotation.x, knee_l, _sm(22.0, delta))
	_leg_r_lo.rotation.x = lerpf(_leg_r_lo.rotation.x, knee_r, _sm(22.0, delta))

	# RĘCE — barki w przeciwfazie do nóg (ramię L z nogą R). Atak nadpisze je później, jeśli trwa.
	if not is_attacking:
		var arm_sw := swing * (0.9 if sprinting else 0.75)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x,  s * arm_sw, _sm(18.0, delta))
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -s * arm_sw, _sm(18.0, delta))
		# ŁOKCIE — stałe lekkie zgięcie + dodatkowe na wymachu WŁASNEGO barku DO PRZODU (ręka „pompuje").
		# Bark L napiera do przodu, gdy s>0 (_arm_l = +s); bark R, gdy s<0 (_arm_r = -s). Stąd flex
		# parujemy z dodatnim wkładem WŁASNEGO barku — łokieć dosztywnia się dokładnie przy napieraniu.
		var base_elbow := (0.55 if sprinting else 0.35)
		var elbow_l := base_elbow + maxf(0.0,  s) * (0.5 if sprinting else 0.3)
		var elbow_r := base_elbow + maxf(0.0, -s) * (0.5 if sprinting else 0.3)
		_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, elbow_l, _sm(18.0, delta))
		_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, elbow_r, _sm(18.0, delta))

# --- IDLE: oddychanie + przestępowanie (weight-shift) ----------------------
func _anim_idle(delta: float) -> void:
	_walk_phase = 0.0
	# Bardzo subtelny ruch kończyn: lekkie „rozluźnienie" + minimalny oddech.
	var breath := sin(_idle_phase * 1.6) * 0.04        # wolny oddech
	# Nogi prawie proste; minimalne przestępowanie (weight-shift L/R co kilka s).
	var shift := sin(_idle_phase * 0.7)
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, breath * 0.5, _sm(6.0, delta))
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -breath * 0.5, _sm(6.0, delta))
	# Kolano nogi „odciążonej" lekko ugięte do tyłu (ujemne) — luźna postawa, na zmianę L/R.
	_leg_l_lo.rotation.x = lerpf(_leg_l_lo.rotation.x, -maxf(0.0, shift) * 0.12, _sm(6.0, delta))
	_leg_r_lo.rotation.x = lerpf(_leg_r_lo.rotation.x, -maxf(0.0, -shift) * 0.12, _sm(6.0, delta))
	# Ręce zwisają z minimalnym kołysaniem + lekko zgięte łokcie (naturalna sylwetka).
	if not is_attacking:
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, breath, _sm(6.0, delta))
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -breath, _sm(6.0, delta))
		_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, 0.18, _sm(6.0, delta))
		_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, 0.18, _sm(6.0, delta))

# --- SKOK / SPADANIE: pozy w powietrzu --------------------------------------
func _anim_air(delta: float, _hspeed: float) -> void:
	_walk_phase = 0.0
	var rising := velocity.y > 0.5
	if rising:
		# SKOK (wznoszenie): UDA do PRZODU/kolana w górę (hip DODATNI), KOLANA podkulone DO TYŁU
		# (pięty pod pośladki => UJEMNE). Asymetria L/R = lekki „dynamiczny" tuck, nie sztywny.
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.6, _sm(12.0, delta))
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.35, _sm(12.0, delta))
		_leg_l_lo.rotation.x = lerpf(_leg_l_lo.rotation.x, -1.0, _sm(12.0, delta))
		_leg_r_lo.rotation.x = lerpf(_leg_r_lo.rotation.x, -0.6, _sm(12.0, delta))
		# Bramka po _attack_anim_t (nie is_attacking): is_attacking gaśnie klatkę później w
		# _physics_process, więc na klatce przełączenia uniknęlibyśmy konkurencyjnego zapisu
		# ramion (drobny twitch) — _anim_attack_arms i tak nadpisze ramiona, gdy atak trwa.
		if _attack_anim_t <= 0.0:
			# Ramiona w GÓRĘ-PRZÓD (zryw): bark do przodu (dodatni) + zgięte łokcie (dodatni).
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.6, _sm(10.0, delta))
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.6, _sm(10.0, delta))
			_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, 0.6, _sm(10.0, delta))
			_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, 0.6, _sm(10.0, delta))
	else:
		# SPADANIE: nogi rozłożone w dół (gotowe na ląd.) — lekko rozkrok, KOLANA delikatnie ugięte
		# do tyłu (amortyzacja). Ręce nieco w bok/przód dla balansu.
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, -0.12, _sm(10.0, delta))
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.2, _sm(10.0, delta))
		_leg_l_lo.rotation.x = lerpf(_leg_l_lo.rotation.x, -0.3, _sm(10.0, delta))
		_leg_r_lo.rotation.x = lerpf(_leg_r_lo.rotation.x, -0.18, _sm(10.0, delta))
		if _attack_anim_t <= 0.0:   # patrz uwaga w gałęzi „rising" — bramka po _attack_anim_t
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.3, _sm(8.0, delta))
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.3, _sm(8.0, delta))
			_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, 0.45, _sm(8.0, delta))
			_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, 0.45, _sm(8.0, delta))

# --- ATAK: zamach prawą ręką (nadpisuje ramiona po lokomocji/idle) ----------
func _anim_attack_arms(delta: float) -> void:
	var t := 1.0 - (_attack_anim_t / attack_anim_time)   # 0..1 postęp animacji
	var swing := sin(t * PI)                              # 0->1->0 parabola
	# Bark: szeroki zamach do przodu; łokieć: prostuje się na uderzeniu (cios „tnie").
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -2.2 * swing, _sm(28.0, delta))
	_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, 0.9 * (1.0 - swing), _sm(28.0, delta))
	# Lewa ręka: kontra w tył dla balansu (lekkie zgięcie łokcia).
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.35, _sm(14.0, delta))
	_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, 0.4, _sm(14.0, delta))

# --- TUŁÓW: body-bob (2× tempo kroku), lean wg prędkości, twist wg fazy ------
func _animate_torso(delta: float, hspeed: float, on_floor: bool, sprinting: bool) -> void:
	# 1) Pionowy bob: szczyt 2× na cykl kroku (ciało unosi się na każdym kroku). Amplituda z prędkości.
	var bob_amp := clampf(hspeed / sprint_speed, 0.0, 1.0) * (0.06 if sprinting else 0.045)
	var target_bob := -absf(sin(_walk_phase)) * bob_amp if (on_floor and hspeed > 0.6) else 0.0
	# Idle: minimalne unoszenie z oddechu.
	if on_floor and hspeed <= 0.6:
		target_bob = sin(_idle_phase * 1.6) * 0.012
	# Lądowanie: przysiad (squash) zaniża tułów chwilowo.
	target_bob -= _land_squash * 0.10
	_anim_bob = lerpf(_anim_bob, target_bob, _sm(16.0, delta))
	_torso.position.y = float(_HIP_Y) * VS + _anim_bob

	# 2) Lean do przodu proporcjonalny do prędkości (bieg pochyla mocniej). W powietrzu mniejszy.
	var lean := clampf(hspeed / sprint_speed, 0.0, 1.0) * (0.28 if sprinting else 0.16)
	if not on_floor:
		lean *= 0.4
	# 3) Twist (skręt barków wokół osi pionowej, przeciwnie do bioder) — naturalny rytm chodu.
	var twist := sin(_walk_phase) * (0.14 if sprinting else 0.09) if (on_floor and hspeed > 0.6) else 0.0
	# 4) Boczny przechył (roll) w idle przy weight-shift.
	var roll := 0.0
	if on_floor and hspeed <= 0.6:
		roll = sin(_idle_phase * 0.7) * 0.03
	_torso.rotation.x = lerpf(_torso.rotation.x, lean, _sm(10.0, delta))
	_torso.rotation.y = lerp_angle(_torso.rotation.y, twist, _sm(14.0, delta))
	_torso.rotation.z = lerpf(_torso.rotation.z, roll, _sm(8.0, delta))

# --- GŁOWA: stabilizacja (kontra do leanu/twistu tułowia) + drobny nod ------
func _animate_head(delta: float, hspeed: float) -> void:
	# Głowa częściowo KOMPENSUJE pochylenie tułowia (wzrok trzyma się horyzontu) —
	# to klasyczny „head stabilization": ujemny ułamek leanu/twistu tułowia.
	var counter_pitch := -_torso.rotation.x * 0.55
	var counter_twist := -_torso.rotation.y * 0.4
	# Drobny nod w rytm kroku (głowa lekko „kiwa" przy bieganiu) + oddech w idle.
	if hspeed > 0.6:
		counter_pitch += sin(_walk_phase * 2.0) * 0.02
	else:
		counter_pitch += sin(_idle_phase * 1.6) * 0.025
	_head.rotation.x = lerpf(_head.rotation.x, counter_pitch, _sm(12.0, delta))
	_head.rotation.y = lerp_angle(_head.rotation.y, counter_twist, _sm(12.0, delta))

func _physics_process(delta: float) -> void:
	# ----------------------------------------------------------------------
	#  TIKI WALKI (odliczanie czasu) — na samym początku, przed grawitacją
	# ----------------------------------------------------------------------
	_attack_cd      = maxf(0.0, _attack_cd - delta)
	_dodge_cd       = maxf(0.0, _dodge_cd - delta)
	_iframes        = maxf(0.0, _iframes - delta)
	_attack_anim_t  = maxf(0.0, _attack_anim_t - delta)
	if _attack_anim_t <= 0.0:
		is_attacking = false
	if _combo_timer > 0.0:
		_combo_timer = maxf(0.0, _combo_timer - delta)
		if _combo_timer == 0.0:
			_combo_count = 0          # okno combo wygasło
			combo_changed.emit(_combo_count)   # HUD: schowaj "Combo xN"
	if _dodge_t > 0.0:
		_dodge_t = maxf(0.0, _dodge_t - delta)
		if _dodge_t == 0.0:
			is_dodging = false
	# Obsługa KEY_Q jako alternatywy uniku (debounce) — tylko gdy kursor złapany.
	var q_down := Input.is_physical_key_pressed(KEY_Q) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if q_down and not _q_was_down:
		_try_dodge()
	_q_was_down = q_down

	# 1) Grawitacja (mocniejsza przy opadaniu — mniej „księżycowy" skok)
	if not is_on_floor():
		var g := _gravity * (fall_gravity_mult if velocity.y < 0.0 else 1.0)
		velocity.y -= g * delta

	# 2) Skok z game feel (0C): coyote time + bufor wejścia + jump-cut.
	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote = maxf(0.0, _coyote - delta)
	var space_down := Input.is_physical_key_pressed(KEY_SPACE) and not is_dead
	if space_down and not _space_was:
		_jump_buffer = jump_buffer_time
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
	# jump-cut: puszczenie spacji w fazie wznoszenia skraca skok (lepsza kontrola wysokości).
	if not space_down and velocity.y > 0.0:
		velocity.y = minf(velocity.y, jump_velocity * 0.35)
	_space_was = space_down

	# 3) Kierunek z klawiszy WASD (lokalny: x = bok, y = przód/tył)
	var input_dir := Vector2.ZERO
	if not is_dead:
		if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1.0
		if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1.0
	input_dir = input_dir.normalized()

	# (Auto-step przeniesiony niżej — wymaga policzonego `direction`/`current_speed`, a do tego
	#  jest BRAMKOWANY test_move, żeby wchodzić tylko na niskie progi, nie na strome ściany.)

	# 4) Obróć kierunek o yaw kamery — "przód" zawsze tam, gdzie patrzysz.
	var yaw := _pivot.rotation.y
	var direction := Vector3(input_dir.x, 0.0, input_dir.y).rotated(Vector3.UP, yaw)

	# 5) Prędkość pozioma (bieg z shiftem; bramkowanie staminą) + knockback (gaśnie)
	var moving := input_dir != Vector2.ZERO
	var can_sprint := Input.is_physical_key_pressed(KEY_SHIFT) and stamina > 0.0
	var current_speed := sprint_speed if can_sprint else speed
	# Akceleracja/wyhamowanie (0C): płynny rozpęd zamiast natychmiastowej prędkości.
	var accel := ground_accel if is_on_floor() else air_accel
	_move_vel.x = move_toward(_move_vel.x, direction.x * current_speed, accel * delta)
	_move_vel.z = move_toward(_move_vel.z, direction.z * current_speed, accel * delta)
	velocity.x = _move_vel.x + _knockback.x
	velocity.z = _move_vel.z + _knockback.z

	# 5a) AUTO-STEP (naprawione): wejdź TYLKO na niski próg (~1 voxel), NIE na strome ściany.
	# Test: podnieś transform o step_height i sprawdź, czy ruch w przód jest WOLNY. Jeśli tak =>
	# to niski stopień => mały impuls w górę. Jeśli wciąż blokuje => ściana => brak podskoku
	# (postać się zatrzyma, zamiast „wspinać się" po terenie, gdzie nie powinna).
	if is_on_floor() and is_on_wall() and moving and _knockback.y <= 0.0 and _dodge_t <= 0.0:
		var probe := direction * 0.35   # jak daleko w przód sprawdzamy kolizję progu
		var raised := global_transform
		raised.origin.y += step_height
		if not test_move(raised, probe):
			velocity.y = maxf(velocity.y, step_boost)

	# Sprint pobiera staminę tylko gdy faktycznie biegniemy i się ruszamy:
	if can_sprint and moving and stamina > 0.0:
		stamina = maxf(0.0, stamina - sprint_stamina_cost * delta)
		_stamina_idle = 0.0
		stamina_changed.emit(stamina, max_stamina)

	# 5b) UNIK (dash): nadpisuje poziomą prędkość zrywem (po zwykłej prędkości, przed move_and_slide).
	# Respektuje grawitację (nie zerujemy velocity.y) — można unikać w powietrzu, ale nie "latać".
	if _dodge_t > 0.0:
		velocity.x = _dodge_dir.x * dodge_speed
		velocity.z = _dodge_dir.z * dodge_speed
		_move_vel.x = velocity.x   # po dashu kontynuuj płynnie (bez „szarpnięcia")
		_move_vel.z = velocity.z

	# 5c) Knockback w pionie: jednorazowy impuls w górę przy trafieniu (dodawany do velocity.y).
	if _knockback.y > 0.0:
		velocity.y += _knockback.y
		_knockback.y = 0.0
	# Wygaszanie knockbacku w poziomie.
	_knockback.x = move_toward(_knockback.x, 0.0, 18.0 * delta)
	_knockback.z = move_toward(_knockback.z, 0.0, 18.0 * delta)

	# Gdy martwy — wygaszamy ruch poziomy (grawitacja zostaje, by nie wisiał w powietrzu).
	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)

	# 6) Wykonaj ruch z uwzględnieniem kolizji
	var pre_vy := velocity.y
	move_and_slide()

	# Lądowanie (0C + JUICE): trzask kamery + przysiad (squash) + pył, skalowane prędkością upadku.
	if is_on_floor() and not _was_on_floor and pre_vy < -3.0:
		var fall := -pre_vy
		add_trauma(clampf(fall / 30.0, 0.0, 0.35))
		# Squash: krótki przysiad ciała (anim _animate_torso zaniża tułów wg _land_squash).
		_land_squash = clampf(fall / 16.0, 0.15, 1.0)
		# Pył pod stopami przy mocniejszym lądowaniu (próg, by drobne kroki nie kurzyły).
		if fall > 5.0:
			_spawn_land_dust(clampf(fall / 16.0, 0.0, 1.0))
	_was_on_floor = is_on_floor()

# ============================================================================
#  WALKA — ATAK
# ============================================================================

func _try_attack() -> void:
	if is_dead or _attack_cd > 0.0 or is_dodging:
		return
	_attack_cd = attack_cooldown
	_attack_anim_t = attack_anim_time   # start animacji zamachu
	is_attacking = true

	# WARIANT A (rekomendacja): pierwszy cios serii już z 15% przebicia.
	# Inkrement combo PRZED pętlą trafień (pudło zresetuje go do 0 poniżej).
	_combo_count += 1

	# Cios idzie TAM, GDZIE PATRZY KAMERA (yaw pivota), nie w kierunku modelu.
	# Model obraca się do kamery dopiero przez kolejne klatki (lerp w _process), więc
	# liczenie trafienia z forward modelu pudłowało, gdy gracz stał i obrócił kamerę
	# na wroga. Liczymy forward z yaw kamery — natychmiast celne. Dla spójności wizualnej
	# od razu ustawiamy yaw modelu na yaw kamery (animacja zamachu startuje "w stronę celu").
	var fyaw := _pivot.rotation.y
	var forward := Vector3(-sin(fyaw), 0.0, -cos(fyaw)).normalized()
	_model.rotation.y = fyaw
	var origin := global_position

	var hit_any := false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not (enemy is Node3D):
			continue
		var to_enemy: Vector3 = (enemy as Node3D).global_position - origin
		to_enemy.y = 0.0                  # liczymy w płaszczyźnie (ignoruj różnicę wysokości)
		var dist := to_enemy.length()
		if dist > attack_range or dist < 0.05:
			continue
		if forward.dot(to_enemy / dist) < attack_arc_dot:   # poza przednim łukiem
			continue
		_deal_damage_to(enemy)
		hit_any = true

	if hit_any:
		_combo_timer = combo_window       # odśwież okno combo
		_hitstop(0.06)                    # juice: krótki bezczas przy trafieniu
		add_trauma(0.12)                  # lekki trzask kamery przy trafieniu
	else:
		_combo_count = 0                  # pudło = reset combo (kasuje wcześniejszy inkrement)
		_combo_timer = 0.0
	combo_changed.emit(_combo_count)      # HUD: pokaż/ukryj "Combo xN"

# Zadaje obrażenia jednemu wrogowi z uwzględnieniem combo→przebicia i jego pancerza.
func _deal_damage_to(enemy: Node) -> void:
	# _combo_count jest już zinkrementowane (wariant A) — pierwszy cios = 15% przebicia.
	var pierce := minf(armor_pierce_max, float(_combo_count) * armor_pierce_per_combo)
	var armor := 0.0
	if "armor" in enemy:                       # wróg może mieć pole 0..1 (% redukcji)
		armor = clampf(enemy.armor, 0.0, 1.0)
	var effective_armor := armor * (1.0 - pierce)
	var dmg := attack_damage * (1.0 - effective_armor)
	if enemy.has_method("take_damage"):
		enemy.take_damage(dmg, self)           # kontrakt wroga: take_damage(amount, from)

# Hitstop (0C): krótki bezczas przy trafieniu — najsilniejszy „juice" walki.
func _hitstop(dur: float) -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(dur, true, false, true).timeout  # ignore_time_scale=true (realny czas)
	Engine.time_scale = 1.0
	_hitstop_active = false

# ============================================================================
#  WALKA — UNIK (dash z i-frames)
# ============================================================================

func _try_dodge() -> void:
	if is_dead or _dodge_cd > 0.0 or is_dodging or stamina < dodge_stamina_cost:
		return
	stamina -= dodge_stamina_cost
	_stamina_idle = 0.0
	stamina_changed.emit(stamina, max_stamina)
	_dodge_cd = dodge_cooldown
	_dodge_t = dodge_time
	_iframes = maxf(_iframes, dodge_iframes)
	is_dodging = true
	is_attacking = false           # unik przerywa atak (priorytet ucieczki)
	_attack_anim_t = 0.0

	# Kierunek: WASD jeśli się ruszasz, inaczej forward modelu; fallback = forward kamery.
	var dir := _wish_direction()
	if dir.length() < 0.1:
		dir = -_model.global_transform.basis.z
		dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3(-sin(_pivot.rotation.y), 0.0, -cos(_pivot.rotation.y))
	_dodge_dir = dir.normalized()

# Zwraca świat-kierunek z WASD+yaw kamery (ta sama logika co w _physics_process).
func _wish_direction() -> Vector3:
	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1.0
	input_dir = input_dir.normalized()
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO
	var yaw := _pivot.rotation.y
	return Vector3(input_dir.x, 0.0, input_dir.y).rotated(Vector3.UP, yaw)

# ============================================================================
#  HP, OBRAŻENIA, ŚMIERĆ, RESPAWN
# ============================================================================

# PUBLICZNA — wołana przez wrogów: take_damage(amount, from).
# 'from' to węzeł źródła (Enemy przekazuje self). Z jego pozycji liczymy knockback.
func take_damage(amount: float, from: Node = null) -> void:
	if is_dead:
		return
	if _iframes > 0.0:        # nietykalność (unik / po respawnie) — ignoruj cios
		return
	hp = maxf(0.0, hp - amount)
	hp_changed.emit(hp, max_hp)
	_flash_hit()              # błysk koloru modelu (czerwień)

	# Knockback: odpychamy w bok OD źródła trafienia (poziomo) + lekko w górę.
	var src := global_position
	if from != null and from is Node3D:
		src = (from as Node3D).global_position
	var dir := global_position - src
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = -global_transform.basis.z    # gdy pozycje się nakładają — pchnij do tyłu
		dir.y = 0.0
	_knockback = dir.normalized() * 6.0
	_knockback.y = 3.0

	if hp <= 0.0:
		_die()

func _die() -> void:
	is_dead = true
	is_attacking = false
	is_dodging = false
	_attack_anim_t = 0.0
	_dodge_t = 0.0
	died.emit()
	# Uwaga: faktyczny respawn z opóźnieniem steruje Main (timer + wywołanie respawn()).

func respawn() -> void:
	is_dead = false
	hp = max_hp
	stamina = max_stamina
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_combo_count = 0
	_combo_timer = 0.0
	_attack_cd = 0.0
	_attack_anim_t = 0.0
	_dodge_t = 0.0
	_dodge_cd = 0.0
	is_attacking = false
	is_dodging = false
	_iframes = respawn_iframes   # nietykalność po odrodzeniu
	global_position = respawn_point
	# Teleport: wyzeruj interpolację, żeby postać nie „smużyła" z punktu śmierci do respawnu.
	reset_physics_interpolation()
	if _pivot != null:
		_pivot.global_position = global_position + Vector3(0.0, 1.6, 0.0)
	hp_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)
	combo_changed.emit(_combo_count)   # HUD: wyzeruj wskaźnik combo po respawnie
	respawned.emit()

# ============================================================================
#  BŁYSK TRAFIENIA (emisja na całym modelu, gasnąca przez Tween)
# ============================================================================

# Krótki czerwony błysk emisji na całym modelu (ok. 0,18 s). NIE rusza albedo.
func _flash_hit() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	var meshes := _collect_meshes(_model)
	for mi in meshes:
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.15, 0.1)
		mat.emission_energy_multiplier = 2.0
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	for mi in meshes:
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		# Wygaszamy mnożnik emisji do 0 — model wraca do normalnych kolorów.
		_flash_tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.18)
	# Po wygaśnięciu błysku WYŁĄCZAMY emisję na meshach (chain() = sekwencyjnie po
	# równoległych tweenach powyżej). Bez tego emission_enabled zostałoby na stałe true
	# na każdym meshu modelu (mnożnik 0 = niewidoczne, ale to ukryta zmiana stanu, która
	# mogłaby zaskoczyć przy dokładaniu kolejnych efektów emisji).
	_flash_tween.chain().tween_callback(func() -> void:
		for mi in meshes:
			var m := mi.material_override as StandardMaterial3D
			if m != null:
				m.emission_enabled = false
	)

# Zbiera wszystkie MeshInstance3D z poddrzewa modelu (tułów, głowa, kończyny).
func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node == null:
		return out
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_collect_meshes(child))
	return out

# ============================================================================
#  GETTERY dla HUD
# ============================================================================

func get_hp_ratio() -> float:
	return 0.0 if max_hp <= 0.0 else hp / max_hp

func get_stamina_ratio() -> float:
	return 0.0 if max_stamina <= 0.0 else stamina / max_stamina

func get_combo() -> int:
	return _combo_count
