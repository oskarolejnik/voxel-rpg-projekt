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

# Buduje voxelową postać z kostek jako dzieci węzła "Model".
# Tułów/głowa są statyczne; ręce i nogi wiszą na pivotach (zawiasach) do animacji chodu.
func _build_voxel_character() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	# Paleta (albedo_color jest sRGB w Godocie — kolory dobieramy normalnie).
	var skin := Color(0.93, 0.76, 0.60)
	var tunic := Color(0.18, 0.46, 0.32)   # zielona tunika
	var belt := Color(0.32, 0.22, 0.12)    # pasek
	var pants := Color(0.26, 0.30, 0.46)   # spodnie
	var boots := Color(0.20, 0.16, 0.12)   # buty
	var hair := Color(0.34, 0.20, 0.10)    # włosy
	var eyes := Color(0.06, 0.06, 0.08)    # oczy

	# --- Tułów (tunika + pasek) — statyczny ---
	_cube(_model, Vector3(0.66, 0.62, 0.40), Vector3(0.0, 1.05, 0.0), tunic)
	_cube(_model, Vector3(0.68, 0.10, 0.42), Vector3(0.0, 0.78, 0.0), belt)

	# --- Głowa + włosy + oczy — statyczne ---
	# Większa głowa + większe oczy = sylwetka „chibi" (sygnatura looku Cube World, Faza 2D).
	_cube(_model, Vector3(0.66, 0.62, 0.62), Vector3(0.0, 1.72, 0.0), skin)
	_cube(_model, Vector3(0.70, 0.18, 0.66), Vector3(0.0, 2.04, 0.0), hair)   # czapka włosów
	_cube(_model, Vector3(0.70, 0.50, 0.16), Vector3(0.0, 1.78, 0.28), hair)  # tył głowy (+Z)
	_cube(_model, Vector3(0.15, 0.18, 0.05), Vector3(-0.16, 1.74, -0.33), eyes)
	_cube(_model, Vector3(0.15, 0.18, 0.05), Vector3(0.16, 1.74, -0.33), eyes)

	# --- Nogi: pivoty (zawiasy) w biodrach y=0.78; kończyny zwisają, stopy na y=0 ---
	_leg_l = _make_pivot(_model, Vector3(-0.17, 0.78, 0.0))
	_leg_r = _make_pivot(_model, Vector3(0.17, 0.78, 0.0))
	for leg in [_leg_l, _leg_r]:
		_cube(leg, Vector3(0.26, 0.56, 0.28), Vector3(0.0, -0.28, 0.0), pants)       # noga
		_cube(leg, Vector3(0.30, 0.22, 0.36), Vector3(0.0, -0.67, -0.03), boots)     # but (spód na y=0)

	# --- Ręce: pivoty (zawiasy) w barkach y=1.37; kończyny zwisają ---
	_arm_l = _make_pivot(_model, Vector3(-0.45, 1.37, 0.0))
	_arm_r = _make_pivot(_model, Vector3(0.45, 1.37, 0.0))
	for arm in [_arm_l, _arm_r]:
		_cube(arm, Vector3(0.20, 0.50, 0.24), Vector3(0.0, -0.25, 0.0), tunic)       # rękaw
		_cube(arm, Vector3(0.22, 0.18, 0.26), Vector3(0.0, -0.57, 0.0), skin)        # dłoń

# Tworzy węzeł-zawias (pivot) kończyny w danym punkcie modelu.
func _make_pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p

# Pomocnik: dodaje jedną kostkę (rozmiar w metrach, środek, kolor) do rodzica.
func _cube(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

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
	var target := global_position + Vector3(0.0, 1.6, 0.0)
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

	# 3b) Auto-podskok: gdy idziemy i blokuje nas NISKI stopień (np. 1-blokowy teren
	# voxelowy), lekko podskakujemy, żeby go pokonać — jak auto-jump w grach blokowych.
	# is_on_floor()/is_on_wall() odnoszą się do ostatniego move_and_slide() (poprz. klatka).
	# Pomijamy auto-podskok, gdy czeka pionowy impuls knockbacku (_knockback.y > 0),
	# inaczej trafienie pod ścianą dałoby podwójny wyskok (6.5 + 3.0).
	if is_on_floor() and is_on_wall() and input_dir != Vector2.ZERO and _knockback.y <= 0.0:
		velocity.y = 6.5

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
