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
var _model: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _walk_phase: float = 0.0

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
# Siatka logiczna (Vector3i, oś Y od stóp): najwyższy voxel (czapa włosów) to logiczne
# y=24, więc realna wysokość modelu ≈ 24 × 0,09 ≈ 2,16 m. Kapsuła kolizji ma height=2.0
# (środek y=1.0 => biegun na y=2.0), więc CZUBEK GŁOWY wystaje ~0,16 m PONAD kapsułę.
# To CELOWE i bezpieczne: kapsuła służy tylko kolizji (stopy poprawnie na y=0, postać nie
# wnika w teren); jedynie pod bardzo niskim nawisem czubek włosów mógłby wizualnie przeniknąć
# sufit. Chcąc pełnego zamknięcia w kapsule: zbij VS do ~0.083 (24×0.083≈1,99 m) albo
# podnieś capsule.height=2.2 i shape.position.y=1.1 w _build_body().
const VS: float = 0.09

# Buduje voxelową postać. Tułów/głowa statyczne; ręce i nogi na pivotach do animacji chodu.
func _build_voxel_character() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	var mat := _make_char_material()

	# --- Statyczne: głowa + tułów -> jeden mesh dziecko _model ---
	var body := VoxelModel.VoxelDef.new()
	_sculpt_head(body)
	_sculpt_torso(body)
	_add_model_mesh(_model, body, mat, Vector3i.ZERO)

	# --- Nogi: pivoty (zawiasy) w biodrach (logiczny y=8), kończyny schodzą w -Y, stopy na y=0 ---
	# Pivot w METRACH = pivot_voxel * VS. Geometria każdej grupy przesuwana o -pivot przy
	# bake'u, więc zawias ląduje w (0,0,0) węzła -> rotation.x zgina od biodra/barku.
	_leg_l = _make_pivot(_model, Vector3(-2.0 * VS, 8.0 * VS, 0.0))
	_leg_r = _make_pivot(_model, Vector3( 2.0 * VS, 8.0 * VS, 0.0))
	var leg_l := VoxelModel.VoxelDef.new(); _sculpt_leg(leg_l, -1)
	var leg_r := VoxelModel.VoxelDef.new(); _sculpt_leg(leg_r, 1)
	_add_model_mesh(_leg_l, leg_l, mat, Vector3i(-2, 8, 0))
	_add_model_mesh(_leg_r, leg_r, mat, Vector3i( 2, 8, 0))

	# --- Ręce: pivoty (zawiasy) w barkach (logiczny y=14), kończyny zwisają ---
	_arm_l = _make_pivot(_model, Vector3(-5.0 * VS, 14.0 * VS, 0.0))
	_arm_r = _make_pivot(_model, Vector3( 5.0 * VS, 14.0 * VS, 0.0))
	var arm_l := VoxelModel.VoxelDef.new(); _sculpt_arm(arm_l, -1)
	var arm_r := VoxelModel.VoxelDef.new(); _sculpt_arm(arm_r, 1)
	_add_model_mesh(_arm_l, arm_l, mat, Vector3i(-5, 14, 0))
	_add_model_mesh(_arm_r, arm_r, mat, Vector3i( 5, 14, 0))

# Bakuje JEDNĄ grupę voxeli do zbatchowanego ArrayMesh i wiesza pod 'parent'.
# pivot_vox = logiczny punkt obrotu (w voxelach); geometrię przesuwamy o -pivot*VS,
# żeby zawias leżał w (0,0,0) węzła (animacja rotation.x bez zmian).
func _add_model_mesh(parent: Node3D, def: VoxelModel.VoxelDef, mat: Material, pivot_vox: Vector3i) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelModel.build_mesh(def, VS, -Vector3(pivot_vox) * VS)
	mi.material_override = mat
	parent.add_child(mi)

# Materiał postaci: vertex-color jako albedo, matowy. KAŻDA grupa dostaje WŁASNĄ kopię,
# bo _flash_hit() modyfikuje material_override per mesh (gdyby był współdzielony, błysk
# by się zdublował na tym samym obiekcie — niegroźne, ale duplicate() jest czystsze).
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

# GŁOWA (chibi: duża) — czaszka + włosy + twarz. Logiczny y 14..25.
func _sculpt_head(d: VoxelModel.VoxelDef) -> void:
	# Czaszka 9×9×9 (x[-4..4], y[15..23], z[-4..4]).
	d.fill_box(Vector3i(-4, 15, -4), Vector3i(5, 24, 5), _C_SKIN)
	# Szyja (krótka, ciemniejsza skóra) łączy z tułowiem.
	d.fill_box(Vector3i(-2, 14, -2), Vector3i(2, 15, 2), _C_SKIN_SH)
	# Ścięcie górnych rogów czaszki (mniej „pudełkowo").
	for cx in [-4, 4]:
		for cz in [-4, 4]:
			d.cells.erase(Vector3i(cx, 23, cz))
	# WŁOSY: czapa na górze + boki/tył + grzywka.
	d.fill_box(Vector3i(-4, 22, -4), Vector3i(5, 25, 5), _C_HAIR)   # czapa (y22..24)
	d.fill_box(Vector3i(-4, 16, 3), Vector3i(5, 23, 5), _C_HAIR)    # tył (+Z)
	d.fill_box(Vector3i(-4, 16, -4), Vector3i(-3, 23, 5), _C_HAIR)  # lewy bok
	d.fill_box(Vector3i(4, 16, -4), Vector3i(5, 23, 5), _C_HAIR)    # prawy bok
	d.fill_box(Vector3i(-4, 21, -5), Vector3i(5, 23, -4), _C_HAIR)  # grzywka na czole (front -Z)
	for hx in [-4, -2, 0, 2, 4]:
		d.set_voxel(Vector3i(hx, 21, -5), _C_HAIR_HI)               # opadające kosmyki (y21, by nie kolidowały z brwiami y20)
	# TWARZ (front -Z, warstwa z=-5 jako „naklejka" na lico z=-4).
	# Oczy duże (sygnatura chibi): białko 2×2 na y18..19.
	for ex in [-3, 2]:
		d.fill_box(Vector3i(ex, 18, -5), Vector3i(ex + 2, 20, -4), _C_EYE_W)
	# Tęczówki + źrenice (patrzą lekko do środka).
	d.set_voxel(Vector3i(-2, 18, -5), _C_IRIS); d.set_voxel(Vector3i(-2, 19, -5), _C_PUPIL)
	d.set_voxel(Vector3i( 2, 18, -5), _C_IRIS); d.set_voxel(Vector3i( 2, 19, -5), _C_PUPIL)
	# Brwi (kreska włosów nad oczami).
	d.set_voxel(Vector3i(-3, 20, -5), _C_HAIR); d.set_voxel(Vector3i(-2, 20, -5), _C_HAIR)
	d.set_voxel(Vector3i( 2, 20, -5), _C_HAIR); d.set_voxel(Vector3i( 3, 20, -5), _C_HAIR)
	# Rumieńce.
	d.set_voxel(Vector3i(-3, 17, -5), _C_BLUSH); d.set_voxel(Vector3i(3, 17, -5), _C_BLUSH)
	# Nos (1 voxel) i usta (2 voxele).
	d.set_voxel(Vector3i(0, 17, -5), _C_SKIN_SH)
	d.set_voxel(Vector3i(-1, 16, -5), _C_MOUTH); d.set_voxel(Vector3i(0, 16, -5), _C_MOUTH)

# TUŁÓW (tunika + pasek + lamówka). Logiczny y 8..15.
func _sculpt_torso(d: VoxelModel.VoxelDef) -> void:
	# Tunika x[-4..4] (9 voxeli, środek 0 — symetria z głową), y[8..14], z[-2..1].
	d.fill_box(Vector3i(-4, 8, -2), Vector3i(5, 15, 2), _C_TUNIC)
	# Cień/fałdy (bryła nie jest płaska).
	d.fill_box(Vector3i(-4, 8, 1), Vector3i(5, 15, 2), _C_TUNIC_SH)    # plecy (+Z)
	d.fill_box(Vector3i(-4, 8, -2), Vector3i(-3, 15, 2), _C_TUNIC_SH)  # lewy bok (x=-4)
	d.fill_box(Vector3i(4, 8, -2), Vector3i(5, 15, 2), _C_TUNIC_SH)    # prawy bok (x=4, symetrycznie)
	# Złota lamówka pod szyją (dekolt) + 2 guziki na froncie (z=-3 „nakładka").
	d.fill_box(Vector3i(-2, 14, -3), Vector3i(2, 15, -2), _C_TRIM)
	d.set_voxel(Vector3i(0, 13, -3), _C_TRIM)
	d.set_voxel(Vector3i(0, 11, -3), _C_TRIM)
	# Pasek (y8) dookoła + klamra na froncie. x[-4..4] spójnie z tuniką.
	d.fill_box(Vector3i(-4, 8, -3), Vector3i(5, 9, 2), _C_BELT)
	d.set_voxel(Vector3i(0, 8, -3), _C_BUCKLE)
	d.set_voxel(Vector3i(-1, 8, -3), _C_BUCKLE)

# NOGA (udo/łydka w spodniach + but). side = -1 (lewa) / +1 (prawa). Logiczny y 0..8.
# X-zakres: lewa [-3..-1], prawa [1..2] -> 2 voxele szer.
func _sculpt_leg(d: VoxelModel.VoxelDef, side: int) -> void:
	var x0 := (-3 if side < 0 else 1)
	# Nogawka spodni: y1..7 (stopa nad podeszwą buta).
	d.fill_box(Vector3i(x0, 1, -1), Vector3i(x0 + 2, 8, 2), _C_PANTS)
	d.fill_box(Vector3i(x0, 1, 1), Vector3i(x0 + 2, 8, 2), _C_PANTS_SH)   # cień z tyłu
	# But: y0..1, dłuższy w przód (czubek na -Z); podeszwa (y0) najjaśniejsza.
	d.fill_box(Vector3i(x0, 0, -2), Vector3i(x0 + 2, 2, 2), _C_BOOTS)
	d.fill_box(Vector3i(x0, 0, -2), Vector3i(x0 + 2, 1, 2), _C_BOOTS_HI)

# RĘKA (rękaw tuniki + naramiennik + dłoń). side = -1/+1. Logiczny y 6..14.
# X tuż obok tułowia: lewa [-6..-5], prawa [4..5].
func _sculpt_arm(d: VoxelModel.VoxelDef, side: int) -> void:
	var x0 := (-6 if side < 0 else 4)
	# Rękaw tuniki: y8..13 (zwisa od barku w dół).
	d.fill_box(Vector3i(x0, 8, -1), Vector3i(x0 + 2, 14, 2), _C_TUNIC)
	d.fill_box(Vector3i(x0, 8, 1), Vector3i(x0 + 2, 14, 2), _C_TUNIC_SH)   # cień rękawa
	d.fill_box(Vector3i(x0, 13, -2), Vector3i(x0 + 2, 14, 2), _C_TRIM)     # naramiennik (złoto)
	# Dłoń (skóra): y6..7.
	d.fill_box(Vector3i(x0, 6, -1), Vector3i(x0 + 2, 8, 1), _C_SKIN)

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
	_spring.add_child(_camera)
	_camera.current = true

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

# Game feel (0C): kamera podąża z wygładzeniem/lagiem + trauma-shake.
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
	if s > 0.0:
		_shake_time += delta
		var nx := _shake_noise.get_noise_2d(_shake_time * 50.0, 0.0)
		var ny := _shake_noise.get_noise_2d(0.0, _shake_time * 50.0)
		var nr := _shake_noise.get_noise_2d(_shake_time * 50.0, 99.0)
		_camera.position = Vector3(nx, ny, 0.0) * s * shake_pos
		_camera.rotation.z = nr * s * shake_roll
	else:
		_camera.position = _camera.position.lerp(Vector3.ZERO, 12.0 * delta)
		_camera.rotation.z = lerpf(_camera.rotation.z, 0.0, 12.0 * delta)

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

# Wizualne: obrót modelu w kierunku ruchu + animacja chodu (kołysanie kończyn).
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

	# --- ATAK ma priorytet nad chodem na RĘKACH (nogi animują się normalnie) ---
	# Jedyny właściciel rotation.x rąk, gdy is_attacking == true — chód NIGDY ich tu nie dotyka.
	if is_attacking:
		var t := 1.0 - (_attack_anim_t / attack_anim_time)   # 0..1 postęp animacji
		# Szybki zamach prawą ręką: w dół-do-przodu i powrót (parabola sin).
		var swing := sin(t * PI) * 2.2                        # rad, ~126° wymachu
		_arm_r.rotation.x = -swing                            # ręka leci do przodu (-X obrót)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.2, 12.0 * delta)  # lewa lekko w tył (balans)
		# Obróć model w stronę celu/kamery podczas ciosu, żeby cios szedł "tam gdzie patrzymy".
		_model.rotation.y = lerp_angle(_model.rotation.y, _pivot.rotation.y, 18.0 * delta)
		# Nogi: niech chód działa dalej.
		_animate_legs_only(delta)
		return

	# --- Standardowy chód/spoczynek (BEZ ZMIAN względem oryginału) ---
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.5:
		# Obrót modelu w stronę ruchu (przód = -Z), płynnie przez lerp_angle.
		var target_yaw := atan2(-velocity.x, -velocity.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, 12.0 * delta)
		# Wahadłowe kołysanie kończyn; ręce w przeciwfazie do nóg (jak w chodzie).
		_walk_phase += delta * hspeed * 1.8
		var swing := sin(_walk_phase) * 0.6
		_arm_l.rotation.x = swing
		_arm_r.rotation.x = -swing
		_leg_l.rotation.x = -swing
		_leg_r.rotation.x = swing
	else:
		# Powrót kończyn do spoczynku.
		_walk_phase = 0.0
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.0, 10.0 * delta)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.0, 10.0 * delta)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, 10.0 * delta)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, 10.0 * delta)

# Animacja samych NÓG (wyjęta z _process), używana podczas ataku, by nogi nadal chodziły,
# a ręce były "zajęte" zamachem. Tułów/głowa statyczne.
func _animate_legs_only(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.5:
		_walk_phase += delta * hspeed * 1.8
		var swing := sin(_walk_phase) * 0.6
		_leg_l.rotation.x = -swing
		_leg_r.rotation.x = swing
	else:
		_walk_phase = 0.0
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, 10.0 * delta)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, 10.0 * delta)

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

	# Lądowanie (0C): trzask kamery proporcjonalny do prędkości upadku (przed wyzerowaniem vy).
	if is_on_floor() and not _was_on_floor and pre_vy < -4.0:
		add_trauma(clampf(-pre_vy / 30.0, 0.0, 0.35))
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
