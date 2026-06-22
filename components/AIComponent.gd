class_name AIComponent
extends Node
## AIComponent.gd (komponent) — maszyna stanow wroga/peta (idle/patrol/chase/attack/leash),
## HOST-ONLY (TDD 1.2 / 6.2: AI liczone tylko na hoscie; klient widzi wynik przez sync).
## Refaktor istniejacej logiki z Enemy.gd na komponent: ta sama histereza, leash, entry-delay,
## ale decyzje ataku ida przez AbilityComponent (TDD 1.2), a wartosci czyta z eksportow encji.
##
## KONTRAKT z encja (Enemy/pet) — komponent jest "mozgiem", encja "cialem":
##   host.ai_get_position() -> Vector3
##   host.ai_get_target() -> Node3D (lub null)
##   host.ai_move_towards(point: Vector3, speed: float)   # ustawia velocity.xz
##   host.ai_stop()                                        # velocity.xz = 0
##   host.ai_face(dir: Vector3)                            # kierunek modelu
##   host.ai_attack(target: Node3D)                        # 1 cios (przez AbilityComponent/hitbox)
##   host.ai_can_attack() -> bool                          # CD ataku zszedl
## Komponent zwraca w tick() wybrany stan (do animacji/diagnostyki). Brak autorytetu -> NO-OP.

enum State { IDLE, PATROL, CHASE, ATTACK }

## Parametry zachowania — domyslne = obecny Goblin z Enemy.gd; encja moze nadpisac przez configure().
var move_speed: float = 3.5
var attack_range: float = 2.0
var aggro_radius: float = 12.0
var leash_radius: float = 18.0
var patrol_radius: float = 6.0
var attack_entry_delay: float = 0.35

var allegiance_hostile: bool = true        # pet (ALLY) celuje w HOSTILE; HOSTILE celuje w gracza

var _state: State = State.IDLE
var _home: Vector3 = Vector3.ZERO
var _patrol_target: Vector3 = Vector3.ZERO
var _idle_timer: float = 0.0
var _patrol_timer: float = 0.0
var _entry_delay_left: float = 0.0

var _host: Node = null


func _ready() -> void:
	_host = get_parent()
	_idle_timer = randf_range(1.5, 3.5)


## Wstrzykuje parametry z eksportow encji (zeby tuning zostal w Enemy.gd/EnemyResource).
func configure(p: Dictionary) -> void:
	move_speed = float(p.get("move_speed", move_speed))
	attack_range = float(p.get("attack_range", attack_range))
	aggro_radius = float(p.get("aggro_radius", aggro_radius))
	leash_radius = float(p.get("leash_radius", leash_radius))
	patrol_radius = float(p.get("patrol_radius", patrol_radius))
	attack_entry_delay = float(p.get("attack_entry_delay", attack_entry_delay))
	allegiance_hostile = bool(p.get("allegiance_hostile", allegiance_hostile))


func set_home(h: Vector3) -> void:
	_home = h
	_patrol_target = h


func get_state() -> State:
	return _state


## Wybudzenie przez trafienie (z Enemy.take_damage): wymusza pogon.
func wake_to_chase() -> void:
	if _state == State.IDLE or _state == State.PATROL:
		_state = State.CHASE


## Glowny krok AI (wolany z _physics_process encji). HOST-ONLY. Zwraca biezacy stan.
func tick(delta: float) -> int:
	# HOST-ONLY (TDD 6.2). W SP has_authority == true -> dziala lokalnie; klient -> NO-OP (sync).
	if NetManager != null and not NetManager.has_authority(_host):
		return _state
	if _host == null or not is_instance_valid(_host):
		return _state

	var pos: Vector3 = _host.ai_get_position()
	var target: Node3D = _host.ai_get_target()
	var has_target := target != null and is_instance_valid(target)
	var dist := INF
	if has_target:
		var d: Vector3 = target.global_position - pos
		dist = Vector2(d.x, d.z).length()

	match _state:
		State.IDLE:    _idle(delta, has_target, dist)
		State.PATROL:  _patrol(delta, has_target, dist, pos)
		State.CHASE:   _chase(has_target, dist, target)
		State.ATTACK:  _attack(delta, has_target, dist, target, pos)
	return _state


func _idle(delta: float, has_target: bool, dist: float) -> void:
	_host.ai_stop()
	if has_target and dist <= aggro_radius:
		_state = State.CHASE
		return
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_pick_patrol_target()
		_patrol_timer = 5.0
		_state = State.PATROL


func _patrol(delta: float, has_target: bool, dist: float, pos: Vector3) -> void:
	if has_target and dist <= aggro_radius:
		_state = State.CHASE
		return
	_host.ai_move_towards(_patrol_target, move_speed)
	_patrol_timer -= delta
	var to := _patrol_target - pos
	to.y = 0.0
	if to.length() < 0.8 or _patrol_timer <= 0.0:
		_idle_timer = randf_range(1.5, 3.5)
		_state = State.IDLE


func _chase(has_target: bool, dist: float, target: Node3D) -> void:
	if not has_target:
		_patrol_target = _home
		_state = State.PATROL
		return
	if dist > leash_radius:
		_patrol_target = _home
		_state = State.PATROL
		return
	if dist <= attack_range:
		_host.ai_stop()
		_entry_delay_left = attack_entry_delay   # okno na unik przed pierwszym ciosem
		_state = State.ATTACK
		return
	_host.ai_move_towards(target.global_position, move_speed)


func _attack(delta: float, has_target: bool, dist: float, target: Node3D, pos: Vector3) -> void:
	_host.ai_stop()
	if not has_target:
		_patrol_target = _home
		_state = State.PATROL
		return
	if dist > leash_radius:                       # leash ma priorytet nawet w ataku
		_patrol_target = _home
		_state = State.PATROL
		return

	# Patrz na cel.
	var to := target.global_position - pos
	to.y = 0.0
	if to.length() > 0.01:
		_host.ai_face(to.normalized())

	# Entry-delay (gracz ma okno na unik), potem cios gdy CD zszedl i cel w zasiegu (histereza 1.3).
	_entry_delay_left = maxf(0.0, _entry_delay_left - delta)
	if _entry_delay_left <= 0.0 and _host.ai_can_attack() and dist <= attack_range * 1.3:
		_host.ai_attack(target)

	# Wyjscie do CHASE z histereza, by stany nie migotaly na granicy.
	if dist > attack_range * 1.3:
		_state = State.CHASE


func _pick_patrol_target() -> void:
	var ang := randf() * TAU
	var r := randf() * patrol_radius
	_patrol_target = _home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
