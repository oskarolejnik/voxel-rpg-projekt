class_name Enemy
extends CharacterBody3D
## Enemy.gd — pierwszy wróg (Goblin Critter) + AI (ETAP 3, RUNDA 1).
##
## Mały, krępy stwór z voxeli (BoxMesh przez _cube). Maszyna stanów:
##   IDLE → PATROL → CHASE → ATTACK, z leashem (powrotem do domu) i histerezą.
## Rozdział obowiązków jak u gracza:
##   _physics_process — fizyka: grawitacja, wybór stanu, ruch, auto-podskok, move_and_slide,
##   _process         — wizuale: obrót modelu w stronę celu/ruchu, kołysanie kończyn, błysk.
##
## Kontrakt z graczem: gracz jest w grupie "player", ma metodę take_damage(amount, from).
## Wróg jest w grupie "enemies" i ma opcjonalne pole armor (0..1) + metodę take_damage —
## czyta je rdzeń walki gracza (combo→przebicie pancerza).

signal died(enemy: Enemy)        # emitowany tuż przed queue_free() — Main liczy ubitych

# ============================================================================
#  STATYSTYKI (eksporty — łatwy tuning)
# ============================================================================
@export var max_hp: float = 30.0
@export var move_speed: float = 3.5           # wolniejszy od gracza (speed=6) → da się uciec
@export var attack_damage: float = 8.0
@export var attack_range: float = 2.0         # zasięg ataku w zwarciu
@export var attack_cooldown: float = 1.2      # s między atakami
@export var attack_windup: float = 0.35       # s "zamachu" przed zadaniem dmg (można odskoczyć)
@export var attack_entry_delay: float = 0.35  # s zwłoki PRZED pierwszym ciosem po wejściu w zwarcie
                                              # (gracz ma okno na unik, zanim padnie pierwsze trafienie)
@export var aggro_radius: float = 12.0        # promień wykrycia gracza → CHASE
@export var leash_radius: float = 18.0        # gracz dalej niż to → powrót do PATROL
@export var patrol_radius: float = 6.0        # promień drobnego błądzenia wokół domu
@export var turn_speed: float = 10.0          # szybkość obrotu modelu (lerp_angle)
@export var knockback_force: float = 5.0      # odrzut przy trafieniu
@export var hit_flash_time: float = 0.12      # s mignięcia na biało

# Opcjonalny pancerz (0..1 = % redukcji obrażeń). Czyta go gracz (przebicie combo).
@export var armor: float = 0.0

# ============================================================================
#  STAN
# ============================================================================
enum State { IDLE, PATROL, CHASE, ATTACK }
var _state: State = State.IDLE

var hp: float = 30.0
var _target: Node3D = null                    # gracz (push z Main lub fallback z grupy)
var _home: Vector3 = Vector3.ZERO             # punkt startu (środek patrolu / leash)
var _patrol_target: Vector3 = Vector3.ZERO
var _face_dir: Vector3 = Vector3.ZERO         # kierunek do obrotu modelu w _process

var _idle_timer: float = 0.0
var _patrol_timer: float = 0.0
var _attack_timer: float = 0.0                # cooldown między atakami
var _windup_timer: float = 0.0
var _attacking: bool = false                  # czy trwa cykl zamachu
var _flash_timer: float = 0.0
var _walk_phase: float = 0.0

# Knockback jako gasnący wektor (jak u gracza) — przeżywa nadpisanie velocity przez AI.
# Doliczany do velocity PO wyborze stanu i wygaszany przez move_toward.
var _knockback: Vector3 = Vector3.ZERO
@export var knockback_decay: float = 18.0     # tempo wygaszania odrzutu (jednostki/s)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)

# Model i pivoty kończyn.
var _model: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D

# Materiały + bazowe kolory do błysku trafienia (TYPOWANE — pułapka "Cannot infer type").
var _mats: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []

func _ready() -> void:
	add_to_group("enemies")        # świat liczy, gracz wykrywa
	# Warstwy kolizji: wróg na warstwie 3, zderza się WYŁĄCZNIE z terenem (warstwa 1).
	# Dzięki temu wrogowie nie wpychają się nawzajem ani w gracza (warstwa 2) — AI działa
	# po dystansie XZ, a chód po terenie zostaje nienaruszony.
	collision_layer = 1 << 2       # warstwa 3 (bit 2) = wrogowie
	collision_mask = 1             # maska = tylko teren (warstwa 1, bit 0)
	hp = max_hp
	_home = global_position
	_patrol_target = _home
	_idle_timer = randf_range(1.5, 3.5)
	_build_body()

# ============================================================================
#  BUDOWA: kolizja + model voxelowy
# ============================================================================
func _build_body() -> void:
	# Kolizja (kapsuła, mniejsza niż gracz; stopy na y=0).
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.3
	capsule.radius = 0.35
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.65, 0.0)
	add_child(shape)

	_build_voxel_goblin()

func _build_voxel_goblin() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	# Paleta goblina (albedo sRGB — kolory normalnie).
	var skin := Color(0.30, 0.55, 0.22)    # zielona skóra
	var skin_d := Color(0.22, 0.42, 0.16)  # ciemniejsza (kończyny/uszy)
	var eyes := Color(1.00, 0.85, 0.10)    # świecące żółte oczy
	var mouth := Color(0.10, 0.06, 0.05)   # paszcza
	var loin := Color(0.35, 0.24, 0.14)    # przepaska brązowa

	# --- Tułów (krępy) + przepaska — statyczne ---
	_cube(_model, Vector3(0.56, 0.46, 0.36), Vector3(0.0, 0.78, 0.0), skin)
	_cube(_model, Vector3(0.58, 0.12, 0.38), Vector3(0.0, 0.56, 0.0), loin)

	# --- Głowa (duża) + uszy + oczy (świecące) + paszcza ---
	_cube(_model, Vector3(0.62, 0.56, 0.56), Vector3(0.0, 1.30, 0.0), skin)
	_cube(_model, Vector3(0.12, 0.26, 0.10), Vector3(-0.36, 1.42, 0.0), skin_d)  # ucho L
	_cube(_model, Vector3(0.12, 0.26, 0.10), Vector3(0.36, 1.42, 0.0), skin_d)   # ucho R
	_cube(_model, Vector3(0.13, 0.10, 0.05), Vector3(-0.14, 1.34, -0.29), eyes, true)  # oko L (przód = -Z)
	_cube(_model, Vector3(0.13, 0.10, 0.05), Vector3(0.14, 1.34, -0.29), eyes, true)   # oko R
	_cube(_model, Vector3(0.34, 0.08, 0.05), Vector3(0.0, 1.14, -0.29), mouth)   # paszcza

	# --- Nogi: pivoty w biodrach y=0.56; krótkie, stopy ~y=0 ---
	_leg_l = _make_pivot(_model, Vector3(-0.16, 0.56, 0.0))
	_leg_r = _make_pivot(_model, Vector3(0.16, 0.56, 0.0))
	for leg in [_leg_l, _leg_r]:
		_cube(leg, Vector3(0.22, 0.46, 0.24), Vector3(0.0, -0.28, 0.0), skin_d)

	# --- Ręce: pivoty w barkach y=0.98; długie szpony ---
	_arm_l = _make_pivot(_model, Vector3(-0.36, 0.98, 0.0))
	_arm_r = _make_pivot(_model, Vector3(0.36, 0.98, 0.0))
	for arm in [_arm_l, _arm_r]:
		_cube(arm, Vector3(0.18, 0.50, 0.20), Vector3(0.0, -0.25, 0.0), skin)     # ramię
		_cube(arm, Vector3(0.20, 0.14, 0.22), Vector3(0.0, -0.55, 0.0), skin_d)   # dłoń/szpon

func _make_pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p

# Pomocnik: dodaje jedną kostkę. Opcjonalny 'emit' włącza emisję (świecące oczy).
# Zapamiętuje materiał + bazowy kolor do błysku trafienia.
func _cube(parent: Node3D, size: Vector3, pos: Vector3, color: Color, emit: bool = false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	if emit:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.5   # delikatna poświata oczu
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	# Do błysku trafienia (interpolacja albedo do bieli i z powrotem).
	_mats.append(mat)
	_base_colors.append(color)

# ============================================================================
#  REFERENCJA DO CELU
# ============================================================================
func set_target(t: Node3D) -> void:
	_target = t

# ============================================================================
#  FIZYKA + AI
# ============================================================================
func _physics_process(delta: float) -> void:
	# 1) Grawitacja
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# 2) Fallback: brak celu → szukaj gracza w grupie (autonomia przy streamingu)
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player") as Node3D

	# Liczniki ataku zawsze tykają.
	_attack_timer = maxf(0.0, _attack_timer - delta)

	# Pionowy impuls knockbacku (jednorazowy, jak u gracza) — dodawany do velocity.y.
	if _knockback.y > 0.0:
		velocity.y += _knockback.y
		_knockback.y = 0.0

	# 3) Dystans XZ do gracza (różnice wysokości terenu nie fałszują aggro/leash)
	var has_target := _target != null and is_instance_valid(_target)
	var dist := INF
	if has_target:
		var d := _target.global_position - global_position
		dist = Vector2(d.x, d.z).length()

	# 4) Wybór stanu + 5) ruch poziomy wg stanu
	match _state:
		State.IDLE:
			_state_idle(delta, has_target, dist)
		State.PATROL:
			_state_patrol(delta, has_target, dist)
		State.CHASE:
			_state_chase(delta, has_target, dist)
		State.ATTACK:
			_state_attack(delta, has_target, dist)

	# 5b) Knockback poziomy: doliczamy PO wyborze stanu (stany nadpisują/zerują velocity.x/z),
	# żeby odrzut był widoczny mimo logiki AI. Wygaszamy go przez move_toward co klatkę.
	velocity.x += _knockback.x
	velocity.z += _knockback.z
	_knockback.x = move_toward(_knockback.x, 0.0, knockback_decay * delta)
	_knockback.z = move_toward(_knockback.z, 0.0, knockback_decay * delta)

	# 6) Auto-podskok po terenie voxelowym (gdy się porusza i napotka 1-blokowy stopień).
	# Pomijamy podczas knockbacku, by trafienie pod ścianą nie dawało podwójnego wyskoku.
	if is_on_floor() and is_on_wall() and (absf(velocity.x) + absf(velocity.z)) > 0.1 and _knockback.length_squared() < 0.01:
		velocity.y = 6.5

	# 7) Ruch z kolizją
	move_and_slide()

# --- IDLE: stoi, tyka licznik, potem PATROL. Aggro → CHASE. ---
func _state_idle(delta: float, has_target: bool, dist: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if has_target and dist <= aggro_radius:
		_state = State.CHASE
		return
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_pick_patrol_target()
		_patrol_timer = 5.0
		_state = State.PATROL

# --- PATROL: idzie do losowego punktu wokół domu. Aggro → CHASE. ---
func _state_patrol(delta: float, has_target: bool, dist: float) -> void:
	if has_target and dist <= aggro_radius:
		_state = State.CHASE
		return
	_move_towards(_patrol_target, move_speed)
	_patrol_timer -= delta
	var to := _patrol_target - global_position
	to.y = 0.0
	if to.length() < 0.8 or _patrol_timer <= 0.0:
		_idle_timer = randf_range(1.5, 3.5)
		_state = State.IDLE

# --- CHASE: idzie do gracza. W zasięgu → ATTACK. Za daleko (leash) → powrót do domu. ---
func _state_chase(_delta: float, has_target: bool, dist: float) -> void:
	if not has_target:
		_patrol_target = _home
		_state = State.PATROL
		return
	if dist > leash_radius:
		_patrol_target = _home
		_state = State.PATROL
		return
	if dist <= attack_range:
		velocity.x = 0.0
		velocity.z = 0.0
		# Mała zwłoka przed pierwszym ciosem: gracz dostaje okno na unik/odskok,
		# zanim padnie pierwsze trafienie (bez tego cios szedł już po samym windupie).
		# maxf, by nie skrócić ewentualnego trwającego cooldownu.
		_attack_timer = maxf(_attack_timer, attack_entry_delay)
		_state = State.ATTACK
		return
	_move_towards(_target.global_position, move_speed)

# --- ATTACK: stoi, patrzy na gracza, wykonuje cykl windup→hit→cooldown. Histereza wyjścia. ---
func _state_attack(delta: float, has_target: bool, dist: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	if not has_target:
		_attacking = false
		_patrol_target = _home
		_state = State.PATROL
		return
	# Leash ma priorytet — nawet w trakcie ataku.
	if dist > leash_radius:
		_attacking = false
		_patrol_target = _home
		_state = State.PATROL
		return

	# Patrz na gracza (kierunek do obrotu modelu w _process).
	var to := _target.global_position - global_position
	to.y = 0.0
	if to.length() > 0.01:
		_face_dir = to.normalized()

	# Cykl ataku.
	if not _attacking and _attack_timer <= 0.0:
		_attacking = true
		_windup_timer = attack_windup
		# (opcjonalnie: unieś prawą rękę — robi to _process gdy _attacking)
	if _attacking:
		_windup_timer -= delta
		if _windup_timer <= 0.0:
			# Zadaj dmg TYLKO jeśli gracz nadal w zasięgu (mógł odskoczyć). Histereza *1.3.
			if dist <= attack_range * 1.3 and _target.has_method("take_damage"):
				_target.take_damage(attack_damage, self)
			_attacking = false
			_attack_timer = attack_cooldown

	# Wyjście do CHASE z histerezą, by stany nie migotały na granicy.
	if not _attacking and dist > attack_range * 1.3:
		_state = State.CHASE

# Ruch w stronę punktu (XZ). Zapamiętuje kierunek do obrotu modelu.
func _move_towards(point: Vector3, spd: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length() > 0.05:
		var dir := to.normalized()
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
		_face_dir = dir
	else:
		velocity.x = 0.0
		velocity.z = 0.0

# Losowy punkt patrolu w promieniu patrol_radius wokół domu.
func _pick_patrol_target() -> void:
	var ang := randf() * TAU
	var r := randf() * patrol_radius
	_patrol_target = _home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)

# ============================================================================
#  WIZUALE: obrót modelu + chód + błysk + zamach
# ============================================================================
func _process(delta: float) -> void:
	if _model == null:
		return

	# Obrót modelu w stronę _face_dir (przód = -Z), płynnie.
	if _face_dir.length() > 0.01:
		var target_yaw := atan2(-_face_dir.x, -_face_dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, turn_speed * delta)

	# Animacja: zamach (gdy _attacking) ma priorytet na PRAWEJ ręce; reszta = chód.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if _attacking:
		# Unieś prawą rękę do przodu — szybki, czytelny "zamach szponem".
		var t := 1.0
		if attack_windup > 0.0:
			t = clampf(1.0 - (_windup_timer / attack_windup), 0.0, 1.0)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.6 * t, 14.0 * delta)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.0, 10.0 * delta)
		# Nogi nadal mogą się kołysać, jeśli (rzadko) idzie; tu zwykle stoi → spoczynek.
		_animate_legs(delta, hspeed)
	elif hspeed > 0.3:
		_walk_phase += delta * hspeed * 2.2
		var swing := sin(_walk_phase) * 0.6
		_arm_l.rotation.x = swing
		_arm_r.rotation.x = -swing
		_leg_l.rotation.x = -swing
		_leg_r.rotation.x = swing
	else:
		# Powrót do spoczynku (lerp do 0).
		_walk_phase = 0.0
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.0, 10.0 * delta)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.0, 10.0 * delta)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, 10.0 * delta)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, 10.0 * delta)

	# Błysk trafienia: interpoluj albedo do bieli wg _flash_timer, potem przywróć.
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		var k := _flash_timer / hit_flash_time   # 1 → 0
		for i in _mats.size():
			_mats[i].albedo_color = _base_colors[i].lerp(Color.WHITE, k)
		if _flash_timer == 0.0:
			# Pełny powrót do bazowych kolorów.
			for i in _mats.size():
				_mats[i].albedo_color = _base_colors[i]

# Animacja samych nóg (używana podczas zamachu).
func _animate_legs(delta: float, hspeed: float) -> void:
	if hspeed > 0.3:
		_walk_phase += delta * hspeed * 2.2
		var swing := sin(_walk_phase) * 0.6
		_leg_l.rotation.x = -swing
		_leg_r.rotation.x = swing
	else:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, 10.0 * delta)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, 10.0 * delta)

# ============================================================================
#  HP, OBRAŻENIA, ŚMIERĆ
# ============================================================================
func take_damage(amount: float, from: Node = null) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash_timer = hit_flash_time          # mignięcie na biało (w _process)

	# Trafienie wybudza wroga do pościgu, nawet jeśli źródło poza aggro.
	if from != null and from is Node3D:
		_target = from as Node3D
	if _state == State.IDLE or _state == State.PATROL:
		_state = State.CHASE

	# Odrzut: w kierunku OD źródła trafienia (XZ) + lekkie podbicie.
	# Ustawiamy gasnący wektor _knockback (nie velocity wprost), bo w następnej klatce
	# match _state nadpisałby velocity (CHASE→ku graczowi, IDLE/PATROL/ATTACK→zero) i odrzut
	# byłby niewidoczny. _physics_process dolicza _knockback PO wyborze stanu i wygasza go.
	if from != null and from is Node3D:
		var away := global_position - (from as Node3D).global_position
		away.y = 0.0
		if away.length() > 0.01:
			_knockback = away.normalized() * knockback_force
			_knockback.y = 3.0         # jednorazowy impuls w górę (zerowany po doliczeniu)

	if hp <= 0.0:
		_die()

func _die() -> void:
	died.emit(self)          # Main/świat policzy ubitych
	queue_free()
