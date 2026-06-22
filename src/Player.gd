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
# Dodatkowy stan dla NATURALNEJ animacji (wygładzane „blend weights" 0..1 i fazy).
var _gait: float = 0.0        # 0=idle/stoi, 1=pełny chód — wygładzona „siła" lokomocji (anti-pop)
var _run_blend: float = 0.0   # 0=chód, 1=bieg — wygładzone przejście chód<->bieg (amplitudy/tempo)
var _air_blend: float = 0.0   # 0=na ziemi, 1=w powietrzu — wygładza wejście/wyjście z pozy lotu
# Wspólny próg prędkości wejścia w lokomocję (nogi) i startu narastania _gait — JEDNO źródło,
# by nogi i tułów/głowa zaczynały „chodzić" razem (bez rozjazdu progów).
const _LOCO_MIN_SPEED: float = 0.4
# ============================================================================
#  PARAMETRY PROPORCJI POSTACI (STROJENIE WIZUALNE — ZMIENIAJ TYLKO LICZBY)
# ============================================================================
# To JEDYNE miejsce, gdzie definiujemy budowę sylwetki. Cała geometria (_sculpt_*)
# i wszystkie pivoty wyliczają się z tych nazwanych eksportów — integrator może
# stroić proporcje zmieniając wartości BEZ przepisywania logiki budowy.
#
# Jednostka: VOXEL (całkowity, oś Y od stóp y=0). Skala metryczna VS jest WYLICZANA
# z P_HEIGHT_M / P_HEIGHT_VOX, więc model trzyma realny wzrost niezależnie od siatki.
# Kierunek wzroku: -Z (twarz z przodu). x = lewo(-)/prawo(+) widza.
#
# CEL: zgrabny bohater „pośredni" (między chibi a realizmem) — ~1,8 m, ~4,5 głowy
# wysokości, głowa UMIARKOWANA, smukły tułów, proporcjonalne kończyny.
@export_group("Proporcje postaci")
@export var P_HEIGHT_M: float = 1.80          # docelowy wzrost w metrach (świat 0,5 m/voxel)
@export var P_HEIGHT_VOX: int = 36            # pełna wysokość modelu w voxelach (czubek włosów)
                                              # NADPISYWANE w _compute_proportions realną sumą (auto=37);
                                              # 37 vox / ~8-voxelowa renderowana głowa ≈ 4,6 „głowy" — pośrednie

# --- GŁOWA (umiarkowana, NIE chibi) ---
# CEL pomiarowy (zweryfikowany sondą AABB): renderowana głowa (czaszka+włosy) ~= 0,21 wzrostu
# => ~4,8 „głowy"; czaszka WĘŻSZA od barków (head_w/shoulder_w ~0,64). Stąd niższa i smuklejsza
# czaszka + nieco szersze barki (P_SHOULDER_W=11), co dodatkowo wyszczupla głowę w sylwetce.
@export var P_HEAD_H: int = 7                 # wysokość czaszki+twarzy (voxele) — „1 głowa" = jednostka proporcji
@export var P_HEAD_W: int = 7                 # szerokość głowy (nieparzysta => symetria wokół x=0; < barków)
@export var P_HEAD_D: int = 6                 # głębokość głowy
@export var P_HAIR_TOP: int = 1               # ile voxeli czapy włosów STERCZY ponad czaszkę

# --- SZYJA ---
@export var P_NECK_H: int = 2                 # wysokość szyi (voxele) — łączy głowę z barkami
@export var P_NECK_W: int = 3                 # szerokość szyi (smukła)

# --- TUŁÓW (smukły, lekka klepsydra) ---
@export var P_TORSO_H: int = 11               # wysokość tułowia (pas -> nasada szyi)
@export var P_SHOULDER_W: int = 11            # szerokość barków (najszerszy punkt korpusu, nieparzysta)
                                              # head_w(7)/shoulder_w(11) ≈ 0,64 => smukła głowa, heroiczne barki
@export var P_WAIST_W: int = 7                # szerokość w pasie (< barków => talia)
@export var P_TORSO_D: int = 5                # głębokość tułowia (przód-tył)

# --- NOGI (2 segmenty: udo + łydka/but) ---
@export var P_THIGH_H: int = 8                # długość uda (biodro -> kolano)
@export var P_SHIN_H: int = 6                 # długość łydki (kolano -> kostka, nad butem)
@export var P_FOOT_H: int = 2                 # wysokość buta (kostka -> podeszwa y=0)
@export var P_LEG_W: int = 3                  # szerokość nogi (voxele)
@export var P_LEG_GAP: int = 1                # przerwa między nogami (od osi do wewn. krawędzi: P_LEG_GAP)
@export var P_FOOT_FWD: int = 2               # o ile but wystaje w przód (-Z, palce)

# --- RĘCE (2 segmenty: ramię + przedramię/dłoń) ---
# Dłuższe niż dawniej: na wiarygodnym bohaterze palce sięgają ~połowy uda (poniżej pasa),
# a nie kończą się na linii bioder. Dół dłoni ląduje ~vox 11-12 (między kolanem=8 a biodrem=16).
@export var P_UARM_H: int = 7                 # długość ramienia (bark -> łokieć)
@export var P_FARM_H: int = 8                 # długość przedramienia+dłoni (łokieć -> palce)
@export var P_ARM_W: int = 3                  # szerokość ręki (smuklejsza od nogi lub równa)
@export var P_ARM_GAP: int = 0               # odstęp ręki od boku tułowia (0 = tuż przy barku)

# --- GŁĘBOKOŚĆ KOŃCZYN (wspólna dla rąk i nóg) ---
@export var P_LIMB_D: int = 3                 # głębokość (oś Z) kończyn — lekko > szer. = owalny przekrój

# ----------------------------------------------------------------------------
#  WYLICZONE wysokości pivotów + skala (NIE strój ręcznie — liczone z parametrów).
#  Ustawiane w _compute_proportions() PRZED _build_voxel_character().
#  Konwencja Y (od stóp): 0 = podeszwa, _ANKLE_Y = kostka (wierzch buta),
#  _KNEE_Y = kolano, _HIP_Y = biodro/pas, _SHOULDER_Y = bark, _NECK_TOP = nasada głowy.
# ----------------------------------------------------------------------------
var VS: float = 0.05          # bok voxela postaci (m) — WYLICZANY: P_HEIGHT_M / P_HEIGHT_VOX
var _ANKLE_Y: int = 2         # = P_FOOT_H
var _KNEE_Y: int = 8          # = P_FOOT_H + P_SHIN_H
var _HIP_Y: int = 16          # = P_FOOT_H + P_SHIN_H + P_THIGH_H
var _SHOULDER_Y: int = 27     # = _HIP_Y + P_TORSO_H
var _ELBOW_Y: int = 21        # = _SHOULDER_Y - P_UARM_H
var _NECK_TOP: int = 29       # = _SHOULDER_Y + P_NECK_H (nasada głowy)
var _HEAD_TOP: int = 37       # = _NECK_TOP + P_HEAD_H (+ czapa włosów osobno)
# Wyliczone pozycje X zawiasów (środek nogi/ręki) — używane przy budowie i animacji.
var _LEG_X: int = 2           # |x| środka nogi = P_LEG_GAP + P_LEG_W/2
var _ARM_X: int = 5           # |x| środka ręki = P_SHOULDER_W/2 + P_ARM_GAP + P_ARM_W/2

# --- GAME FEEL (Faza 0C) ---
@export var ground_accel: float = 55.0     # przyspieszenie na ziemi (m/s^2)
@export var air_accel: float = 14.0        # słabsza kontrola w powietrzu
@export var coyote_time: float = 0.12      # okno skoku tuż po zejściu z krawędzi
@export var jump_buffer_time: float = 0.12 # bufor wciśnięcia skoku przed lądowaniem
@export var fall_gravity_mult: float = 1.5 # mocniejsze opadanie (mniej „księżycowo")
# Auto-step: pokonuj TYLKO niskie progi (~1 voxel). Wyższe ściany/strome zbocza NIE są
# pokonywane (postać się zatrzyma) — koniec „wspinania się po terenie, gdzie nie powinna".
@export var step_height: float = 0.6       # maks. wysokość progu do automatycznego wejścia (m)
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
	_compute_proportions()  # WYLICZ VS + wysokości pivotów z parametrów (PRZED budową modelu)
	_build_body()     # kształt kolizji + widoczny model (kapsuła)
	_build_camera()   # kamera 3rd-person z ramieniem

	# --- Inicjalizacja walki (ETAP 3) ---
	add_to_group("player")          # by wrogowie mogli nas znaleźć fallbackiem (get_first_node_in_group)
	# Warstwy kolizji: gracz na warstwie 2, ale zderza się WYŁĄCZNIE z terenem (warstwa 1).
	# Dzięki temu stado wrogów (warstwa 3) nie spycha gracza — AI i tak działa po dystansie XZ,
	# a chód/auto-podskok po terenie zostają nienaruszone.
	collision_layer = 1 << 1        # warstwa 2 (bit 1) = gracz
	collision_mask = 1              # maska = tylko teren (warstwa 1, bit 0)
	# Gładkie poruszanie po schodkach voxela (0,5 m): snap do podłoża przy SCHODZENIU (bez
	# odrywania się/odpalania lądowania co stopień). floor_max_angle 50° (wierzchy voxeli płaskie;
	# pionowe ściany to wciąż ściany). floor_constant_speed = stała prędkość na zboczach.
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	hp = max_hp
	stamina = max_stamina
	# Punkt odrodzenia = miejsce startu. Main ustawia position PRZED add_child, więc w _ready()
	# global_position jest już poprawne (na terenie z 2 m zapasu). Main może to też nadpisać.
	respawn_point = global_position
	# Emisja startowa w call_deferred — HUD podłącza sygnały dopiero po _ready() gracza.
	call_deferred("emit_signal", "hp_changed", hp, max_hp)
	call_deferred("emit_signal", "stamina_changed", stamina, max_stamina)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # chowamy i łapiemy kursor

# ============================================================================
#  WYLICZENIE PROPORCJI: pivoty + skala VS z parametrów P_* (wołane w _ready
#  PRZED _build_body). To JEDYNE miejsce, gdzie liczby z panelu zamieniają się
#  na wysokości zawiasów i metryczny rozmiar voxela — sculpt-y i animacja czytają
#  TYLKO wyniki (_HIP_Y, _SHOULDER_Y, VS, ...), więc strojenie = zmiana liczb P_*.
# ============================================================================
func _compute_proportions() -> void:
	# --- PIONOWY STOS (od stóp y=0 w górę) ---
	_ANKLE_Y    = P_FOOT_H                                  # wierzch buta (kostka)
	_KNEE_Y     = _ANKLE_Y + P_SHIN_H                       # pivot kolana
	_HIP_Y      = _KNEE_Y + P_THIGH_H                       # pivot biodra/pasa
	_SHOULDER_Y = _HIP_Y + P_TORSO_H                        # pivot barku
	_ELBOW_Y    = _SHOULDER_Y - P_UARM_H                    # pivot łokcia (w połowie wysokości ramienia)
	_NECK_TOP   = _SHOULDER_Y + P_NECK_H                    # nasada głowy (wierzch szyi)
	_HEAD_TOP   = _NECK_TOP + P_HEAD_H                      # czubek czaszki (bez włosów)
	# --- POPRZECZNE pozycje zawiasów (środek nogi/ręki w X) ---
	_LEG_X = P_LEG_GAP + int(P_LEG_W / 2.0 + 0.5)          # noga tuż przy osi (wąski rozkrok, smukło)
	_ARM_X = int(P_SHOULDER_W / 2.0) + P_ARM_GAP + int(P_ARM_W / 2.0 + 0.5)  # ramię tuż przy barku
	# --- SKALA: VS dobrane tak, by PEŁNA wysokość (z czapą włosów) = P_HEIGHT_M ---
	# P_HEIGHT_VOX nadpisujemy realną sumą (czubek włosów), więc P_HEIGHT_VOX*VS == P_HEIGHT_M
	# DOKŁADNIE, niezależnie od tego, jak integrator zmieni pojedyncze segmenty.
	P_HEIGHT_VOX = _HEAD_TOP + P_HAIR_TOP
	VS = P_HEIGHT_M / float(maxi(1, P_HEIGHT_VOX))          # bok voxela postaci (m)

func _build_body() -> void:
	# Kolizja (kapsuła) — smuklejsza (smukły bohater), stoi „stopami" na y=0.
	# Wysokość kapsuły dopasowana do realnego wzrostu modelu (P_HEIGHT_M), więc czubek
	# głowy mieści się w kapsule (środek = połowa wzrostu, biegun = wzrost). Stopy na y=0
	# pozostają niezmienione: floor_snap, auto-step i kamera działają jak dotąd.
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	# height kapsuły = realny wzrost (bez czapy włosów, by nie zawadzała o niskie nawisy),
	# clamp na 2*radius (minimalna sensowna kapsuła). Środek = height/2 => stopy na y=0.
	var body_h := maxf(2.0 * capsule.radius + 0.01, P_HEIGHT_M)
	capsule.height = body_h
	shape.shape = capsule
	shape.position = Vector3(0.0, body_h * 0.5, 0.0)
	add_child(shape)

	# Widoczny model: voxelowa postać z małych kostek (styl Cube World).
	_build_voxel_character()

# ============================================================================
#  POSTAĆ Z MALUTKICH VOXELI — ZGRABNY BOHATER „POŚREDNI" (~1,8 m, ~4,5 głowy)
# ============================================================================
# Każda grupa ciała = jeden zbatchowany ArrayMesh z drobnych kostek (vertex color),
# z cullingiem wewnętrznych ścian (przez VoxelModel). Tułów+głowa na _torso/_head;
# ręce/nogi jako 2-segmentowe łańcuchy pivotów (bark->łokieć, biodro->kolano).
# Materiał: StandardMaterial3D z vertex_color_use_as_albedo, by _flash_hit() (rzut
# `as StandardMaterial3D`) działał dalej, a kolory były wbudowane w jeden materiał.
#
# PROPORCJE są PARAMETRYCZNE: cała geometria poniżej liczy zakresy voxeli z eksportów
# P_* (sekcja „Proporcje postaci"). Skala VS = P_HEIGHT_M / P_HEIGHT_VOX, więc model
# trzyma realny wzrost (~1,8 m) niezależnie od gęstości siatki. Stopy na y=0, twarz -Z.

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
	# Zawias biodra w X = ±_LEG_X (wyliczone z P_LEG_*). Udo bake'owane pod biodrem
	# (offset -_HIP_Y, -_LEG_X). Łydka+but pod kolanem (offset -_KNEE_Y, -_LEG_X). Pivot
	# kolana jest dzieckiem biodra (ten sam X), na wysokości (_KNEE_Y-_HIP_Y)*VS poniżej.
	_leg_l = _make_pivot(_model, Vector3(float(-_LEG_X) * VS, float(_HIP_Y) * VS, 0.0))
	_leg_r = _make_pivot(_model, Vector3(float( _LEG_X) * VS, float(_HIP_Y) * VS, 0.0))
	_leg_l_lo = _make_pivot(_leg_l, Vector3(0.0, float(_KNEE_Y - _HIP_Y) * VS, 0.0))
	_leg_r_lo = _make_pivot(_leg_r, Vector3(0.0, float(_KNEE_Y - _HIP_Y) * VS, 0.0))
	var thigh_l := VoxelModel.VoxelDef.new(); _sculpt_thigh(thigh_l, -1)
	var thigh_r := VoxelModel.VoxelDef.new(); _sculpt_thigh(thigh_r, 1)
	var shin_l := VoxelModel.VoxelDef.new(); _sculpt_shin(shin_l, -1)
	var shin_r := VoxelModel.VoxelDef.new(); _sculpt_shin(shin_r, 1)
	# Pivot w X przesuwamy kompensacyjnie o ±_LEG_X (geometria liczona w globalnych X),
	# by zawias leżał DOKŁADNIE w osi nogi.
	_add_model_mesh(_leg_l, thigh_l, mat, Vector3i(-_LEG_X, _HIP_Y, 0))
	_add_model_mesh(_leg_r, thigh_r, mat, Vector3i( _LEG_X, _HIP_Y, 0))
	_add_model_mesh(_leg_l_lo, shin_l, mat, Vector3i(-_LEG_X, _KNEE_Y, 0))
	_add_model_mesh(_leg_r_lo, shin_r, mat, Vector3i( _LEG_X, _KNEE_Y, 0))

	# --- RĘCE (2 segmenty): bark (y=_SHOULDER_Y) -> łokieć (y=_ELBOW_Y zagnieżdżony) ---
	# Zawias barku w X = ±_ARM_X (za krawędzią barków, z P_SHOULDER_W/P_ARM_*).
	_arm_l = _make_pivot(_model, Vector3(float(-_ARM_X) * VS, float(_SHOULDER_Y) * VS, 0.0))
	_arm_r = _make_pivot(_model, Vector3(float( _ARM_X) * VS, float(_SHOULDER_Y) * VS, 0.0))
	_arm_l_lo = _make_pivot(_arm_l, Vector3(0.0, float(_ELBOW_Y - _SHOULDER_Y) * VS, 0.0))
	_arm_r_lo = _make_pivot(_arm_r, Vector3(0.0, float(_ELBOW_Y - _SHOULDER_Y) * VS, 0.0))
	var uarm_l := VoxelModel.VoxelDef.new(); _sculpt_upper_arm(uarm_l, -1)
	var uarm_r := VoxelModel.VoxelDef.new(); _sculpt_upper_arm(uarm_r, 1)
	var farm_l := VoxelModel.VoxelDef.new(); _sculpt_forearm(farm_l, -1)
	var farm_r := VoxelModel.VoxelDef.new(); _sculpt_forearm(farm_r, 1)
	_add_model_mesh(_arm_l, uarm_l, mat, Vector3i(-_ARM_X, _SHOULDER_Y, 0))
	_add_model_mesh(_arm_r, uarm_r, mat, Vector3i( _ARM_X, _SHOULDER_Y, 0))
	_add_model_mesh(_arm_l_lo, farm_l, mat, Vector3i(-_ARM_X, _ELBOW_Y, 0))
	_add_model_mesh(_arm_r_lo, farm_r, mat, Vector3i( _ARM_X, _ELBOW_Y, 0))

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

# GŁOWA — UMIARKOWANA (NIE chibi): owalna czaszka + schludne włosy + uszy + CZYTELNA twarz.
# Cała geometria liczona z parametrów: czaszka zajmuje y[_NECK_TOP.._HEAD_TOP), szer. P_HEAD_W,
# głęb. P_HEAD_D. Twarz to „naklejka" na froncie (-Z). Oczy PROPORCJONALNE (małe), nie gigantyczne.
# NIE: wielka kula głowy, oczy na pół twarzy, sterczący ahoge — to dawało „pokraczny" chibi-look.
func _sculpt_head(d: VoxelModel.VoxelDef) -> void:
	var hw := P_HEAD_W / 2                       # półszerokość (np. 7/2=3 => x[-3..3])
	var hd := P_HEAD_D / 2                       # półgłębokość
	var y0 := _NECK_TOP                          # dół czaszki = wierzch szyi
	var y1 := _HEAD_TOP                          # czubek czaszki (bez włosów)
	var fz := -hd - 1                            # warstwa „naklejki" twarzy (1 przed licem)
	# CZASZKA (skóra) — owalna: pełny blok, potem ścięte 4 pionowe krawędzie i górne rogi.
	d.fill_box(Vector3i(-hw, y0, -hd), Vector3i(hw + 1, y1, hd + 1), _C_SKIN)
	# Ścięcie 4 pionowych krawędzi (mniej „pudełkowo") na całej wysokości oprócz środka.
	for ey in range(y0 + 1, y1 - 1):
		d.cells.erase(Vector3i(-hw,  ey, -hd)); d.cells.erase(Vector3i(hw,  ey, -hd))
		d.cells.erase(Vector3i(-hw,  ey,  hd)); d.cells.erase(Vector3i(hw,  ey,  hd))
	# Ścięcie górnych rogów (kopuła czaszki) i dolnych-przednich (lekki, zwężony podbródek).
	for cx in [-hw, hw]:
		for cz in [-hd, hd]:
			d.cells.erase(Vector3i(cx, y1 - 1, cz))
		d.cells.erase(Vector3i(cx, y0, -hd))     # zwężenie szczęki u dołu z przodu
	# SZYJA (ciemniejsza skóra) — smukła, łączy głowę z barkami. y[_SHOULDER_Y.._NECK_TOP).
	var nw := P_NECK_W / 2
	d.fill_box(Vector3i(-nw, _SHOULDER_Y, -nw), Vector3i(nw + 1, _NECK_TOP, nw + 1), _C_SKIN_SH)
	# USZY — wtopione w bok czaszki (x=±hw, NIE ±hw-1 ani ±hw+1), na wys. oczu. Świadomie NIE
	# wystają poza skroń: gdyby sterczały (±hw+1), poszerzałyby SYLWETKĘ głowy do szer. barków
	# (chibi „wielka głowa"); recesja trzyma head_w/shoulder_w ≈ 0,64 (cel 0,6-0,7). Lekki cień
	# (_C_SKIN_SH) na dolnym voxelu daje czytelny zarys małżowiny bez dokładania szerokości.
	var ear_y := y0 + (P_HEAD_H / 2) - 1
	d.set_voxel(Vector3i(-hw, ear_y, 1), _C_EAR);     d.set_voxel(Vector3i(-hw, ear_y + 1, 1), _C_SKIN_SH)
	d.set_voxel(Vector3i( hw, ear_y, 1), _C_EAR);     d.set_voxel(Vector3i( hw, ear_y + 1, 1), _C_SKIN_SH)
	# WŁOSY: schludna czapa (P_HAIR_TOP nad czaszką), boki/tył do połowy głowy, grzywka na czole.
	var hair_lo := y0 + (P_HEAD_H * 2) / 3       # włosy schodzą do ~2/3 wysokości głowy (czoło odsłonięte niżej)
	d.fill_box(Vector3i(-hw, y1 - 1, -hd), Vector3i(hw + 1, y1 + P_HAIR_TOP, hd + 1), _C_HAIR)  # czapa + naddatek
	d.fill_box(Vector3i(-hw, hair_lo, hd, ), Vector3i(hw + 1, y1, hd + 1), _C_HAIR)             # tył (+Z)
	d.fill_box(Vector3i(-hw, hair_lo, -hd), Vector3i(-hw + 1, y1, hd + 1), _C_HAIR)             # lewy bok
	d.fill_box(Vector3i( hw, hair_lo, -hd), Vector3i(hw + 1, y1, hd + 1), _C_HAIR)              # prawy bok
	d.fill_box(Vector3i(-hw, y1 - 2, -hd - 1), Vector3i(hw + 1, y1, -hd), _C_HAIR)              # grzywka (front -Z)
	# Pasemka połysku na czapie (światło z góry-przodu) — bez sterczących kosmyków.
	for hx in range(-hw + 1, hw, 2):
		d.set_voxel(Vector3i(hx, y1 + P_HAIR_TOP - 1, -hd + 1), _C_HAIR_HI)
		d.set_voxel(Vector3i(hx, y1 - 1, -hd - 1), _C_HAIR_HI)   # rozjaśnienie grzywki
	# --- TWARZ (front -Z) — CZYTELNA i proporcjonalna. Linia oczu na ~55% wysokości głowy. ---
	# WSZYSTKO liczone z hw/P_HEAD_H, więc twarz skaluje się ze zmianą proporcji głowy
	# (przy head_w=7 => hw=3: oczy przy x=±2; przy zwężeniu head_w=5 => hw=2: oczy przy x=±1).
	var eye_y := y0 + (P_HEAD_H * 11) / 20       # ~0,55 wysokości głowy
	var ex := maxi(1, hw - 1)                    # |x| oka: tuż przy krawędzi, ale nie na samym brzegu
	# OCZY: małe (tęczówka 1 voxel + źrenica nad nią), rozstawione symetrycznie. NIE gigantyczne.
	d.set_voxel(Vector3i(-ex, eye_y, fz), _C_IRIS);  d.set_voxel(Vector3i(-ex, eye_y + 1, fz), _C_PUPIL)
	d.set_voxel(Vector3i( ex, eye_y, fz), _C_IRIS);  d.set_voxel(Vector3i( ex, eye_y + 1, fz), _C_PUPIL)
	# Białko jako wąski błysk w kąciku oka (od strony skroni) — ożywia spojrzenie bez „wielkich oczu".
	d.set_voxel(Vector3i(-ex - 1, eye_y, fz), _C_EYE_W) if ex + 1 <= hw else d.set_voxel(Vector3i(-ex, eye_y, fz), _C_IRIS)
	d.set_voxel(Vector3i( ex + 1, eye_y, fz), _C_EYE_W) if ex + 1 <= hw else d.set_voxel(Vector3i( ex, eye_y, fz), _C_IRIS)
	# BRWI: krótka kreska nad każdym okiem (lekko uniesiona = sympatyczny wyraz).
	d.set_voxel(Vector3i(-ex, eye_y + 2, fz), _C_HAIR)
	d.set_voxel(Vector3i( ex, eye_y + 2, fz), _C_HAIR)
	# NOS: krótki grzbiet (1 voxel) z cieniem na osi — głębia profilu bez „ryjka".
	d.set_voxel(Vector3i(0, eye_y - 1, fz), _C_SKIN_SH)
	# USTA: subtelny uśmiech (3 voxele) poniżej nosa.
	var mouth_y := eye_y - 2
	d.set_voxel(Vector3i(-1, mouth_y, fz), _C_MOUTH); d.set_voxel(Vector3i(0, mouth_y, fz), _C_MOUTH)
	d.set_voxel(Vector3i( 1, mouth_y, fz), _C_MOUTH)
	# Rumieńce (drobny akcent na policzkach, po bokach ust).
	d.set_voxel(Vector3i(-ex, mouth_y, fz), _C_BLUSH); d.set_voxel(Vector3i(ex, mouth_y, fz), _C_BLUSH)

# TUŁÓW — SMUKŁY kaftan/tunika z lekką talią (klepsydra), pasek, naramienniki, peleryna.
# Geometria parametryczna: y[_HIP_Y.._SHOULDER_Y), barki szer. P_SHOULDER_W (góra), pas P_WAIST_W
# (dół), głęb. P_TORSO_D. NIE: beczkowaty/szeroki korpus — sylwetka ma być wysmuklona, „na nogach".
func _sculpt_torso(d: VoxelModel.VoxelDef) -> void:
	var y0 := _HIP_Y                             # pas (dół tułowia)
	var y1 := _SHOULDER_Y                        # bark (góra tułowia)
	var sw := P_SHOULDER_W / 2                   # półszerokość barków (x[-sw..sw])
	var ww := P_WAIST_W / 2                      # półszerokość pasa
	var dz := P_TORSO_D / 2                      # półgłębokość (z[-dz..dz])
	var mid := (y0 + y1) / 2                     # wysokość talii (najwęższy punkt)
	# Korpus warstwami: szerokość interpoluje od pasa (dół) przez talię (najwęziej) do barków (góra).
	for yy in range(y0, y1):
		var t: float = float(yy - mid) / float(maxi(1, y1 - mid))   # 0 w talii -> 1 na barkach
		var half: int = ww if yy <= mid else ww + int(round(float(sw - ww) * t))
		half = clampi(half, ww - 1, sw)         # delikatne wcięcie talii o 1 poniżej środka
		if yy < mid:
			half = ww - 1 if yy == mid - 1 else ww     # zaznaczona talia tuż nad paskiem
		d.fill_box(Vector3i(-half, yy, -dz), Vector3i(half + 1, yy + 1, dz + 1), _C_TUNIC)
		d.fill_box(Vector3i(-half, yy, dz), Vector3i(half + 1, yy + 1, dz + 1), _C_TUNIC_SH)  # cień pleców
	# Boki w cieniu (bryła nie jest płaska) — lewa/prawa kolumna.
	d.fill_box(Vector3i(-sw, mid, -dz), Vector3i(-sw + 1, y1, dz + 1), _C_TUNIC_SH)
	d.fill_box(Vector3i( sw, mid, -dz), Vector3i( sw + 1, y1, dz + 1), _C_TUNIC_SH)
	# Złota lamówka pod szyją (dekolt w V) + rząd guzików na froncie (warstwa z=-dz-1 „nakładka").
	d.fill_box(Vector3i(-2, y1 - 1, -dz - 1), Vector3i(3, y1, -dz), _C_TRIM)
	for gy in range(y0 + 2, y1 - 1, 2):
		d.set_voxel(Vector3i(0, gy, -dz - 1), _C_TRIM)            # guziki
	# Naramienniki (złota „lekka zbroja" na szczycie barków).
	d.fill_box(Vector3i(-sw, y1 - 1, -dz), Vector3i(-sw + 2, y1, dz + 1), _C_TRIM)
	d.fill_box(Vector3i( sw - 1, y1 - 1, -dz), Vector3i(sw + 1, y1, dz + 1), _C_TRIM)
	# PASEK (2 dolne rzędy) dookoła pasa + klamra na froncie.
	d.fill_box(Vector3i(-ww, y0, -dz - 1), Vector3i(ww + 1, y0 + 2, dz + 1), _C_BELT)
	d.set_voxel(Vector3i(0, y0, -dz - 1), _C_BUCKLE)
	d.set_voxel(Vector3i(0, y0 + 1, -dz - 1), _C_BUCKLE)
	# PELERYNKA: warstwa na plecach (+Z) od barków w dół — akcent koloru i ruch sylwetki.
	d.fill_box(Vector3i(-sw + 1, y0, dz + 1), Vector3i(sw, y1, dz + 2), _C_CAPE)
	d.fill_box(Vector3i(-sw + 1, y0, dz + 1), Vector3i(-1, y1, dz + 2), _C_CAPE_SH)   # cień fałdy (lewa)
	d.fill_box(Vector3i(1, y0, dz + 1), Vector3i(sw, y1, dz + 2), _C_CAPE_SH)         # cień fałdy (prawa)
	# Zapinki peleryny na barkach (złoto).
	d.set_voxel(Vector3i(-sw + 1, y1 - 1, dz + 1), _C_TRIM); d.set_voxel(Vector3i(sw - 1, y1 - 1, dz + 1), _C_TRIM)

# UDO (górny segment nogi, w spodniach). side=-1(L)/+1(R). y[_KNEE_Y.._HIP_Y).
# Bryła CENTROWANA na zawiasie biodra (x=±_LEG_X), szer. P_LEG_W, głęb. P_LIMB_D -> owalny przekrój.
# NIE: zbyt grube udo (klocek) — noga ma być wyraźna, lecz smukła.
func _sculpt_thigh(d: VoxelModel.VoxelDef, side: int) -> void:
	var cx := side * _LEG_X                       # środek nogi w X (zawias biodra)
	var x0 := cx - P_LEG_W / 2                    # lewy brzeg bryły
	var x1 := x0 + P_LEG_W                        # prawy brzeg (wyłączny)
	var dz := P_LIMB_D / 2
	# Udo (spodnie): pełny przód, tył w cieniu.
	d.fill_box(Vector3i(x0, _KNEE_Y, -dz), Vector3i(x1, _HIP_Y, dz + 1), _C_PANTS)
	d.fill_box(Vector3i(x0, _KNEE_Y, dz), Vector3i(x1, _HIP_Y, dz + 1), _C_PANTS_SH)   # cień z tyłu
	# Boczna fałda/szew (akcent na zewnętrznej stronie uda).
	var outer := (x0 if side < 0 else x1 - 1)
	d.fill_box(Vector3i(outer, _KNEE_Y + 1, -dz), Vector3i(outer + 1, _HIP_Y - 1, dz), _C_PANTS_SH)

# ŁYDKA + BUT (dolny segment nogi). side=-1/+1. y[0.._KNEE_Y): but [0.._ANKLE_Y), łydka wyżej.
func _sculpt_shin(d: VoxelModel.VoxelDef, side: int) -> void:
	var cx := side * _LEG_X
	var x0 := cx - P_LEG_W / 2
	var x1 := x0 + P_LEG_W
	var dz := P_LIMB_D / 2
	var fwd := P_FOOT_FWD                         # o ile but wystaje w przód (-Z)
	# Łydka (spodnie): od kostki do kolana.
	d.fill_box(Vector3i(x0, _ANKLE_Y, -dz), Vector3i(x1, _KNEE_Y, dz + 1), _C_PANTS)
	d.fill_box(Vector3i(x0, _ANKLE_Y, dz), Vector3i(x1, _KNEE_Y, dz + 1), _C_PANTS_SH)   # cień z tyłu
	# BUT: y[1.._ANKLE_Y+1), dłuższy w przód (czubek/palce na -Z). Cholewka (góra) rozjaśniona.
	d.fill_box(Vector3i(x0, 1, -dz - fwd), Vector3i(x1, _ANKLE_Y + 1, dz + 1), _C_BOOTS)
	d.fill_box(Vector3i(x0, _ANKLE_Y, -dz, ), Vector3i(x1, _ANKLE_Y + 1, dz + 1), _C_BOOTS_HI)  # rant cholewki
	d.fill_box(Vector3i(x0, 1, -dz - fwd), Vector3i(x1, 2, -dz), _C_BOOTS_HI)             # czubek (palce)
	# PODESZWA (y0) — ciemna, czytelny styk z gruntem (foot-plant feel). Sięga pod czubek.
	d.fill_box(Vector3i(x0, 0, -dz - fwd), Vector3i(x1, 1, dz + 1), _C_SOLE)

# RAMIĘ górne (rękaw kaftana + naramiennik). side=-1/+1. y[_ELBOW_Y.._SHOULDER_Y).
# Bryła CENTROWANA na zawiasie barku (x=±_ARM_X), szer. P_ARM_W. NIE: za cienkie „patyki".
func _sculpt_upper_arm(d: VoxelModel.VoxelDef, side: int) -> void:
	var cx := side * _ARM_X
	var x0 := cx - P_ARM_W / 2
	var x1 := x0 + P_ARM_W
	var dz := P_LIMB_D / 2
	# Rękaw kaftana (od barku do łokcia).
	d.fill_box(Vector3i(x0, _ELBOW_Y, -dz), Vector3i(x1, _SHOULDER_Y, dz + 1), _C_TUNIC)
	d.fill_box(Vector3i(x0, _ELBOW_Y, dz), Vector3i(x1, _SHOULDER_Y, dz + 1), _C_TUNIC_SH)  # cień rękawa
	d.fill_box(Vector3i(x0, _SHOULDER_Y - 1, -dz), Vector3i(x1, _SHOULDER_Y, dz + 1), _C_TRIM)  # naramiennik

# PRZEDRAMIĘ + DŁOŃ (dolny segment ręki). side=-1/+1. y[0(=łokieć-baza).._ELBOW_Y w skali pivota).
# UWAGA: bryła liczona w GLOBALNYCH y; segment wisi pod pivotem łokcia (_ELBOW_Y), więc dłoń
# spada poniżej. Karwasz (skóra/skórzany) + zarys dłoni z kciukiem od strony tułowia.
func _sculpt_forearm(d: VoxelModel.VoxelDef, side: int) -> void:
	var cx := side * _ARM_X
	var x0 := cx - P_ARM_W / 2
	var x1 := x0 + P_ARM_W
	var dz := P_LIMB_D / 2
	var hand_h := 2                               # wysokość dłoni (dolny fragment segmentu)
	var y_bot := _ELBOW_Y - P_FARM_H              # dolny koniec przedramienia+dłoni
	var y_wrist := y_bot + hand_h                 # nadgarstek (nad dłonią)
	# Przedramię w skórzanym karwaszu (od nadgarstka do łokcia).
	d.fill_box(Vector3i(x0, y_wrist, -dz), Vector3i(x1, _ELBOW_Y, dz + 1), _C_LEATHER)
	d.fill_box(Vector3i(x0, y_wrist, dz), Vector3i(x1, _ELBOW_Y, dz + 1), _C_TUNIC_SH)   # cień z tyłu
	# DŁOŃ (skóra) na dole segmentu.
	d.fill_box(Vector3i(x0, y_bot, -dz), Vector3i(x1, y_wrist, dz), _C_SKIN)
	# KCIUK (1 voxel po wewnętrznej stronie, ku tułowiu).
	var thumb_x := (x1 if side < 0 else x0 - 1)
	d.set_voxel(Vector3i(thumb_x, y_bot + 1, 0), _C_SKIN)
	# Cień kostek na grzbiecie dłoni (przód -Z).
	d.fill_box(Vector3i(x0, y_bot, -dz), Vector3i(x1, y_bot + 1, -dz + 1), _C_SKIN_SH)

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

	# --- BLEND WEIGHTS (wygładzane, anti-pop): przejścia idle<->chód<->bieg<->lot bez „strzału" ---
	# Te trzy wagi są FAKTYCZNIE czytane przez _anim_locomotion/_animate_torso/_animate_head
	# (mnożą amplitudy / interpolują pary chód-bieg / cross-fade ziemia-powietrze):
	# _gait: 0 gdy stoi, 1 przy pełnej prędkości chodu — wygładza WEJŚCIE w cykl kroku, by nogi nie
	#        „skakały" z pozy idle do pełnego zamachu (mnoży swing/bend/lean/twist/roll/bob/łokcie).
	# _run_blend: 0=chód, 1=bieg — interpoluje WSZYSTKIE pary amplitud/tempo (koniec popu na progu biegu).
	# _air_blend: 0=ziemia, 1=powietrze — cross-fade rytmu kroku tułowia/głowy i skali leanu w locie.
	var gait_target := clampf((hspeed - _LOCO_MIN_SPEED) / maxf(0.1, speed - _LOCO_MIN_SPEED), 0.0, 1.0) if on_floor else 0.0
	var run_target := clampf((hspeed - speed) / maxf(0.5, sprint_speed - speed), 0.0, 1.0)
	_gait = lerpf(_gait, gait_target, _sm(8.0, delta))
	_run_blend = lerpf(_run_blend, run_target, _sm(6.0, delta))
	_air_blend = lerpf(_air_blend, 0.0 if on_floor else 1.0, _sm(10.0, delta))

	# --- WYBÓR STANU NÓG/RĄK ---
	# Priorytet: powietrze > chód/bieg > idle. Atak nadpisuje TYLKO ręce (nogi grają normalnie).
	# Cykl kroku liczymy na ziemi powyżej _LOCO_MIN_SPEED (ten sam próg co start narastania _gait),
	# a _gait skaluje amplitudę — start/stop ruchu jest płynny (nogi „rozkręcają się", nie skaczą).
	# Tułów/głowa NIE mają osobnego progu prędkości — mieszają się przez _gait/_air_blend, więc
	# nogi i tułów wchodzą w lokomocję RAZEM (koniec rozjazdu progów nogi vs tułów).
	if not on_floor:
		_anim_air(delta, hspeed)
	elif hspeed > _LOCO_MIN_SPEED:
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
# Naturalny, WAŻONY krok: biodra w przeciwfazie, ramiona w przeciwfazie do nóg, kolana
# zginają się TYLKO w fazie przenoszenia (foot-plant w podporze), łokcie „pompują" w rytm
# barku. Amplitudy narastają płynnie z prędkością. ANTY-„POŁAMANE": kolano gnie się WYŁĄCZNIE
# do tyłu (clamp na ujemne), nigdy nie odwraca stawu w drugą stronę.
#
# ANTY-POP (kluczowe): wszystkie amplitudy/tempo czytają WYGŁADZONE wagi z _process zamiast
# surowej prędkości i twardego boola „sprinting":
#   * _gait (0->1, idle->pełny chód) MNOŻY wszystkie amplitudy => nogi/ręce ROZKRĘCAJĄ się z idle,
#     a nie skaczą w pełny zamach (eliminuje „klik" kolana i przeskok zamachu na starcie ruchu),
#   * _run_blend (0->1, chód->bieg) INTERPOLUJE pary chód/bieg (swing/bend/tempo/łokcie) =>
#     na progu biegu (hspeed≈speed) nic nie przeskakuje skokowo — przejście jest ciągłe.
func _anim_locomotion(delta: float, _hspeed: float, _sprinting: bool) -> void:
	# Kadencja (tempo): interpolowana chód<->bieg wagą _run_blend (bez skoku na progu biegu).
	# Tempo skaluje z fazą kroku; przy starcie z idle _gait dławi prędkość rozwoju fazy, więc
	# faza nie „strzela" od zera (nogi wchodzą w cykl miękko).
	var cadence := lerpf(1.8, 2.05, _run_blend)
	_walk_phase += delta * sprint_speed * lerpf(0.55, 1.0, _gait) * cadence * (0.6 + 0.4 * _run_blend)
	# Amplitudy: para chód/bieg wybierana _run_blend, całość skalowana _gait (rozruch z idle).
	var swing := lerpf(0.62, 0.95, _run_blend) * _gait              # zamach uda/ramienia (rad)
	var ph := _walk_phase
	var s := sin(ph)

	# NOGI — biodra: przeciwne fazy L/R. Udo do przodu => rotation.x DODATNI (konwencja stawów).
	var hip_l := -s * swing
	var hip_r :=  s * swing
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, hip_l, _sm(20.0, delta))
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, hip_r, _sm(20.0, delta))
	# KOLANA — gną się w fazie PRZENOSZENIA (udo w przód, pięta podrywa się => UJEMNY rot.x = tył).
	# W podporze kolano niemal proste => stopa „trzyma" grunt (foot-plant). -cos(ph)>0 na
	# (π/2,3π/2) z pikiem w π pokrywa się z mid-swingiem nogi L (analogicznie +cos dla R).
	var bend := lerpf(1.25, 1.7, _run_blend) * _gait               # maks. zgięcie kolana (rad)
	var knee_l := -maxf(0.0, -cos(ph)) * bend
	var knee_r := -maxf(0.0,  cos(ph)) * bend
	# Minimalne zgięcie podporowe (kolano nigdy idealnie sztywne — żywsza amortyzacja ciężaru).
	# Start od idle: schodzi z -0.02 (= stały offset kolana w idle) do -0.05 przy pełnym chodzie,
	# więc kolano NIE prostuje się chwilowo na progu ruchu (łączy się czysto z pozą idle).
	var knee_floor := lerpf(-0.02, -0.05, _gait)
	knee_l = minf(knee_l, knee_floor)
	knee_r = minf(knee_r, knee_floor)
	_leg_l_lo.rotation.x = lerpf(_leg_l_lo.rotation.x, knee_l, _sm(22.0, delta))
	_leg_r_lo.rotation.x = lerpf(_leg_r_lo.rotation.x, knee_r, _sm(22.0, delta))

	# RĘCE — barki w PRZECIWFAZIE do nóg (ramię L z nogą R). Atak nadpisze je później, jeśli trwa.
	if not is_attacking:
		var arm_sw := swing * lerpf(0.7, 0.85, _run_blend)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x,  s * arm_sw, _sm(18.0, delta))
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -s * arm_sw, _sm(18.0, delta))
		# ŁOKCIE — lekkie zgięcie (rośnie z _gait) + „pompa", gdy WŁASNY bark napiera do przodu.
		# Bark L do przodu, gdy s>0 (_arm_l=+s); R, gdy s<0. Flex parujemy z dodatnim wkładem barku.
		var base_elbow := lerpf(0.18, lerpf(0.4, 0.55, _run_blend), _gait)
		var pump := lerpf(0.32, 0.5, _run_blend) * _gait
		var elbow_l := base_elbow + maxf(0.0,  s) * pump
		var elbow_r := base_elbow + maxf(0.0, -s) * pump
		_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, elbow_l, _sm(18.0, delta))
		_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, elbow_r, _sm(18.0, delta))

# --- IDLE: spokojny oddech + powolne przestępowanie (weight-shift) ----------
# Sylwetka STOI WYSOKO: kolana niemal proste (stały offset ~-0.02, dopasowany do startowej
# „podłogi" kolana w lokomocji, by przejście idle->chód nie klikało), bez stałego przysiadu.
# Tylko przejściowy weight-shift dokłada drobne ugięcie odciążonej nogi.
func _anim_idle(delta: float) -> void:
	_walk_phase = 0.0
	# Wolny oddech (klatka unosi się) + bardzo powolny weight-shift L/R — postać „żyje".
	var breath := sin(_idle_phase * 1.5) * 0.035       # oddech (rad) — subtelny
	var shift := sin(_idle_phase * 0.6)                # przenoszenie ciężaru (wolne)
	# Nogi prawie proste; noga „odciążona" minimalnie w przód — luźna, naturalna, WYPROSTOWANA postawa.
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x,  breath * 0.4 + maxf(0.0,  shift) * 0.025, _sm(5.0, delta))
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -breath * 0.4 + maxf(0.0, -shift) * 0.025, _sm(5.0, delta))
	# Stały offset kolana tylko -0.02 (prawie prosto) + drobne przejściowe ugięcie z weight-shiftu.
	_leg_l_lo.rotation.x = lerpf(_leg_l_lo.rotation.x, -maxf(0.0,  shift) * 0.08 - 0.02, _sm(5.0, delta))
	_leg_r_lo.rotation.x = lerpf(_leg_r_lo.rotation.x, -maxf(0.0, -shift) * 0.08 - 0.02, _sm(5.0, delta))
	# Ręce zwisają swobodnie z minimalnym kołysaniem oddechu + naturalnie lekko zgięte łokcie.
	if not is_attacking:
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x,  breath * 0.8, _sm(5.0, delta))
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -breath * 0.8, _sm(5.0, delta))
		_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, 0.16, _sm(5.0, delta))
		_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, 0.16, _sm(5.0, delta))

# --- SKOK / SPADANIE: pozy w powietrzu (NATURALNE, ważone fazą lotu) ---------
# WZBICIE: dynamiczny „tuck" (udo do przodu, pięta podkulona) najmocniejszy zaraz po odbiciu,
# rozluźniany ku APEKSOWI (apex = velocity.y≈0). SPADANIE: nogi „sięgają" w dół ku ziemi tym
# bardziej, im szybciej opadamy (gotowość do amortyzacji), kolana lekko ugięte. Konwencja stawów:
# udo do przodu = DODATNI hip, kolano (pięta do tyłu/góry) = UJEMNY, łokieć (zgięcie) = DODATNI.
# Wszystko wygładzane (_sm) — wejście/wyjście z lotu nie „strzela".
func _anim_air(delta: float, _hspeed: float) -> void:
	_walk_phase = 0.0
	var rising := velocity.y > 0.5
	if rising:
		# tuck 1 na odbiciu -> 0 przy apeksie (rozluźnienie nóg u szczytu skoku).
		var tuck := clampf(velocity.y / maxf(1.0, jump_velocity), 0.0, 1.0)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, lerpf(0.25, 0.65, tuck), _sm(12.0, delta))
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, lerpf(0.15, 0.40, tuck), _sm(12.0, delta))
		_leg_l_lo.rotation.x = lerpf(_leg_l_lo.rotation.x, lerpf(-0.45, -1.05, tuck), _sm(12.0, delta))
		_leg_r_lo.rotation.x = lerpf(_leg_r_lo.rotation.x, lerpf(-0.30, -0.65, tuck), _sm(12.0, delta))
		# Bramka po _attack_anim_t: is_attacking gaśnie klatkę później (unikamy twitcha ramion).
		if _attack_anim_t <= 0.0:
			# Ramiona lekko w górę-przód (zryw): bark DODATNI + zgięte łokcie (DODATNI).
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.5, _sm(10.0, delta))
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.5, _sm(10.0, delta))
			_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, 0.55, _sm(10.0, delta))
			_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, 0.55, _sm(10.0, delta))
	else:
		# SPADANIE: im szybciej w dół, tym bardziej nogi „sięgają" ku ziemi (reach), gotowe
		# amortyzować. reach 0 (apex) -> 1 (szybkie opadanie). Lekki rozkrok przód/tył + ugięte kolana.
		var reach := clampf(-velocity.y / 12.0, 0.0, 1.0)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, lerpf(-0.05, -0.20, reach), _sm(10.0, delta))
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, lerpf( 0.10,  0.28, reach), _sm(10.0, delta))
		_leg_l_lo.rotation.x = lerpf(_leg_l_lo.rotation.x, lerpf(-0.18, -0.40, reach), _sm(10.0, delta))
		_leg_r_lo.rotation.x = lerpf(_leg_r_lo.rotation.x, lerpf(-0.12, -0.26, reach), _sm(10.0, delta))
		if _attack_anim_t <= 0.0:
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.28, _sm(8.0, delta))
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.28, _sm(8.0, delta))
			_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, 0.42, _sm(8.0, delta))
			_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, 0.42, _sm(8.0, delta))

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
# ANTY-POP: amplitudy lean/twist/roll/bob czytają WYGŁADZONE wagi (_gait dławi rozruch z idle,
# _run_blend interpoluje pary chód/bieg), więc na progu biegu i na starcie ruchu nic nie strzela.
# _air_blend wycisza rytm kroku w locie i skaluje lean w powietrzu (bez twardego if on_floor).
func _animate_torso(delta: float, _hspeed: float, _on_floor: bool, _sprinting: bool) -> void:
	var ground := 1.0 - _air_blend                # 1 na ziemi, 0 w powietrzu (cross-fade)
	# 1) Pionowy bob: szczyt 2× na cykl kroku (ciało unosi się na każdym kroku). Amplituda przez wagi.
	var bob_amp := lerpf(0.045, 0.06, _run_blend) * _gait
	var target_bob := -absf(sin(_walk_phase)) * bob_amp * ground
	# Idle: minimalne unoszenie z oddechu (gdy lokomocja praktycznie wygaszona).
	target_bob += sin(_idle_phase * 1.6) * 0.012 * (1.0 - _gait) * ground
	# Lądowanie: przysiad (squash) zaniża tułów chwilowo.
	target_bob -= _land_squash * 0.10
	_anim_bob = lerpf(_anim_bob, target_bob, _sm(16.0, delta))
	_torso.position.y = float(_HIP_Y) * VS + _anim_bob

	# 2) Lean do przodu: chód<->bieg przez _run_blend, skala przez _gait. W powietrzu wytłumiony.
	var lean := lerpf(0.16, 0.28, _run_blend) * _gait
	lean *= lerpf(0.4, 1.0, ground)               # w locie ~0,4× (zamiast twardego if not on_floor)
	# 3) Twist (skręt barków wokół osi pionowej, przeciwnie do bioder) — naturalny rytm chodu.
	var twist := sin(_walk_phase) * lerpf(0.09, 0.14, _run_blend) * _gait * ground
	# 4) Boczny przechył (roll): w chodzie WAŻONY — ciało przenosi się nad nogę podporową
	#    (w fazie z bobem), w idle delikatny weight-shift.
	var roll := sin(_walk_phase) * lerpf(0.045, 0.07, _run_blend) * _gait * ground
	roll += sin(_idle_phase * 0.6) * 0.03 * (1.0 - _gait) * ground   # idle weight-shift
	_torso.rotation.x = lerpf(_torso.rotation.x, lean, _sm(10.0, delta))
	_torso.rotation.y = lerp_angle(_torso.rotation.y, twist, _sm(14.0, delta))
	_torso.rotation.z = lerpf(_torso.rotation.z, roll, _sm(9.0, delta))

# --- GŁOWA: stabilizacja (kontra do leanu/twistu tułowia) + drobny nod ------
func _animate_head(delta: float, _hspeed: float) -> void:
	# Głowa częściowo KOMPENSUJE pochylenie tułowia (wzrok trzyma się horyzontu) —
	# to klasyczny „head stabilization": ujemny ułamek leanu/twistu tułowia.
	var counter_pitch := -_torso.rotation.x * 0.55
	var counter_twist := -_torso.rotation.y * 0.4
	# Nod kroku i oddech idle MIESZANE wagą _gait (bez twardego progu hspeed) — spójne z nogami/tułowiem.
	var ground := 1.0 - _air_blend
	counter_pitch += sin(_walk_phase * 2.0) * 0.02 * _gait * ground         # nod w rytm kroku
	counter_pitch += sin(_idle_phase * 1.6) * 0.025 * (1.0 - _gait) * ground # oddech w idle
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

	# (AUTO-STEP wykonujemy PO move_and_slide — _try_step_up() algorytmem góra->przód->dół.
	#  Niezawodne wchodzenie na schodki voxela 0,5 m bez skakania, BEZ wspinania po ścianach.)

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

	# 6a) AUTO-STEP po ruchu: jeśli zablokował nas NISKI próg (schodek voxela), wnieś postać
	# na niego płynnie (góra->przód->dół). Wysokie ściany/strome zbocza => brak (postać staje).
	if moving and is_on_floor() and not is_dead and _dodge_t <= 0.0:
		_try_step_up(direction, current_speed, delta)

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

## Gładkie wchodzenie na NISKIE progi (schodki voxela ~0,5 m) bez skakania — algorytm
## góra->przód->dół. Jeśli w przód blokuje, a po podniesieniu o step_height przód jest WOLNY
## i pod spodem jest grunt, podnosimy postać na próg. Wyższa ściana/strome zbocze => nic
## (postać się zatrzymuje — koniec „wspinania się tam, gdzie nie powinna" i „ciągłego skakania").
func _try_step_up(dir: Vector3, spd: float, delta: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		return
	var horiz := flat.normalized() * maxf(spd * delta + 0.06, 0.12)   # jak daleko w przód testujemy
	# 1) Czy w przód na OBECNEJ wysokości coś blokuje? Jeśli nie — nie ma progu, koniec.
	if not test_move(global_transform, horiz):
		return
	# 2) Podniesiony o step_height: czy w przód WOLNO? Jeśli nie => ściana, NIE wchodzimy.
	var up_t := global_transform
	up_t.origin += Vector3.UP * step_height
	if test_move(up_t, horiz):
		return
	# 3) Z przodu-na-górze rzut w DÓŁ — znajdź wierzch progu (musi być grunt, nie przepaść).
	var fwd_t := up_t
	fwd_t.origin += horiz
	var down := KinematicCollision3D.new()
	if not test_move(fwd_t, Vector3.DOWN * (step_height + 0.05), down):
		return   # brak gruntu pod progiem => krawędź/dziura, nie wnosimy w powietrze
	var rise := step_height - down.get_travel().length()
	if rise > 0.02:
		global_position.y += rise          # wejdź na próg (move_and_slide w nast. klatce niesie w przód)
		if velocity.y < 0.0:
			velocity.y = 0.0               # nie „spadaj" w tej klatce po wejściu

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
