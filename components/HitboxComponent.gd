class_name HitboxComponent
extends Area3D
## HitboxComponent.gd (komponent, Area3D) — zadaje obrazenia: okno czasowe (active frames) +
## lista juz-trafionych (czyszczona na starcie okna) + dociecie filtrem dot() (luk ataku) ->
## DamageService po stronie autorytetu (TDD 1.2 / 5, ROADMAP 4 krok 2).
##
## Zastepuje recznie pisana petle get_nodes_in_group("enemies")+dot() w Player._try_attack().
## Zasada: hitbox zyje na warstwie atakow, jego MASKA pyta cial/hurtboxow przeciwnika. Gdy okno
## aktywne, w kazdym kroku fizyki zbieramy nakladajace sie ciala, filtrujemy lukiem i wolamy
## DamageService.request_hit(source, target, HitData). Kazdy cel trafiony RAZ na okno (hit-list).
##
## Buduje HitData przez Callable `hit_builder` wstrzykiwany przez encje (Player/Enemy) — dzieki
## temu pierce/krytyk/lifesteal/tagi licza sie ZE STATSCOMPONENT/combo encji, a hitbox jest glupi.

## Bity warstw walki (TDD 5) — wspolne z HurtboxComponent.
const LAYER_PLAYER_HITBOX: int = 1 << 3
const LAYER_ENEMY_HITBOX: int = 1 << 5
const MASK_ENEMY_BODY: int = 1 << 2       # gracz pyta ciala wrogow (warstwa 3)
const MASK_PLAYER_BODY: int = 1 << 1      # wrog pyta ciala gracza (warstwa 2)

## Emitowany gdy hitbox cokolwiek trafil w danym oknie (do juice: hitstop/shake/combo).
signal hit_landed(target: Node)
signal window_ended(hit_count: int)

## Root encji-zrodla (atakujacy). Pusta -> get_parent().
@export var owner_path: NodePath
## Prog dot() laczacy luk ataku (reuse Player.attack_arc_dot). <= -1 wylacza filtr (pelne 360°).
@export var arc_dot: float = 0.3
## Czy w ogole dociecie lukiem (false = AoE dookola, np. Wir Ostrzy).
@export var use_arc: bool = true

var _owner_entity: Node = null
## Builder HitData: func(target: Node) -> HitData. Wstrzykiwany przez encje (zna staty/combo).
var _hit_builder: Callable = Callable()
## Kierunek "przodu" do filtra luku (XZ). Ustawiany per atak przez encje (yaw kamery/celu).
var _forward: Vector3 = Vector3.ZERO

var _active: bool = false
var _window_left: float = 0.0
var _already_hit: PackedInt64Array = PackedInt64Array()
var _window_hits: int = 0


func _ready() -> void:
	monitoring = true
	monitorable = false       # hitbox nie jest celem; tylko wykrywa
	# Domyslnie wylaczony do czasu okna ataku (zero kosztu w spoczynku).
	_set_enabled(false)
	_owner_entity = _resolve_owner()


func _resolve_owner() -> Node:
	if owner_path != NodePath() and has_node(owner_path):
		return get_node(owner_path)
	return get_parent()


func get_owner_entity() -> Node:
	if _owner_entity == null or not is_instance_valid(_owner_entity):
		_owner_entity = _resolve_owner()
	return _owner_entity


## Wstrzykuje builder HitData (encja zna staty/combo/krytyk). Wolane raz w _ready encji.
func set_hit_builder(cb: Callable) -> void:
	_hit_builder = cb


func setup_as_player(p_arc_dot: float = 0.3) -> void:
	collision_layer = LAYER_PLAYER_HITBOX
	collision_mask = MASK_ENEMY_BODY
	arc_dot = p_arc_dot


func setup_as_enemy(p_arc_dot: float = -1.0) -> void:
	collision_layer = LAYER_ENEMY_HITBOX
	collision_mask = MASK_PLAYER_BODY
	arc_dot = p_arc_dot
	use_arc = p_arc_dot > -1.0


## Otwiera okno trafienia na `duration` sekund, z kierunkiem przodu `forward` (XZ) do filtra luku.
## Czysci liste trafionych (nowy zamach = nowy zestaw celow). Pierwsze zbieranie OD RAZU (ta klatka).
func open_window(duration: float, forward: Vector3 = Vector3.ZERO) -> void:
	_already_hit.clear()
	_window_hits = 0
	_forward = forward
	_forward.y = 0.0
	_active = true
	_window_left = maxf(duration, 0.0)
	_set_enabled(true)
	# Substep: oprocz polling w _physics_process, zbierz natychmiast (waskie/szybkie ataki).
	_collect_and_resolve()


func close_window() -> void:
	if not _active:
		return
	_active = false
	_window_left = 0.0
	_set_enabled(false)
	window_ended.emit(_window_hits)


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_window_left -= delta
	_collect_and_resolve()
	if _window_left <= 0.0:
		close_window()


## Zbiera nakladajace sie ciala/hurtboxy, filtruje lukiem + dystansem do roota, wola DamageService.
func _collect_and_resolve() -> void:
	# Zbieramy trafienia gdy jestesmy WLASCICIELEM RUCHU atakujacego (host nad wszystkim; klient nad
	# wlasna postacia). Klient-wlasciciel DETEKTUJE trafienie i wysyla request_attack do hosta przez
	# DamageService (ktory sam bramkuje has_state_authority -> klient nie liczy HP, tylko prosi).
	# Host symulujacy CUDZA postac tez tu wejdzie (ma autorytet), wiec ciosy zdalnego gracza dzialaja.
	if NetManager != null and not NetManager.is_movement_owner(get_owner_entity()):
		return
	var src := get_owner_entity()
	var origin: Vector3 = (src as Node3D).global_position if src is Node3D else global_position

	# Zbieramy zarowno ciala (CharacterBody3D wrogow/gracza) jak i HurtboxComponenty.
	var candidates: Array = []
	candidates.append_array(get_overlapping_bodies())
	candidates.append_array(get_overlapping_areas())

	for node in candidates:
		var target := _entity_of(node)
		if target == null or target == src:
			continue
		var oid := target.get_instance_id()
		if _already_hit.has(oid):
			continue
		# Filtr luku (XZ) wzgledem _forward — wierna kopia logiki z Player._try_attack.
		if use_arc and _forward.length_squared() > 0.0001:
			var to: Vector3 = (target as Node3D).global_position - origin if target is Node3D else Vector3.ZERO
			to.y = 0.0
			var d := to.length()
			if d > 0.05 and _forward.normalized().dot(to / d) < arc_dot:
				continue
		var hit: HitData = _build_hit(target)
		if hit == null:
			continue
		_already_hit.append(oid)
		_window_hits += 1
		DamageService.request_hit(src, target, hit)
		hit_landed.emit(target)


## Z dowolnego nakladajacego wezla wyciaga root encji (przez HurtboxComponent albo wprost cialo).
func _entity_of(node: Node) -> Node:
	if node is HurtboxComponent:
		return (node as HurtboxComponent).get_owner_entity()
	# Cialo wprost (CharacterBody3D z take_damage / komponentami) — root encji.
	if node is Node3D and (node.has_method("take_damage") or _has_health(node)):
		return node
	# Hurtbox bez typu albo ksztalt-dziecko: wejdz po rodzicu.
	var p := node.get_parent()
	if p != null and (p.has_method("take_damage") or _has_health(p)):
		return p
	return node


func _has_health(n: Node) -> bool:
	for c in n.get_children():
		if c is HealthComponent:
			return true
	return false


func _build_hit(target: Node) -> HitData:
	if _hit_builder.is_valid():
		return _hit_builder.call(target) as HitData
	return null


func _set_enabled(on: bool) -> void:
	# Wlacz/wylacz wszystkie ksztalty + monitorowanie (zero kosztu poza oknem ataku).
	monitoring = on
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = not on
