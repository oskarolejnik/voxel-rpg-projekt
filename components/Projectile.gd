class_name Projectile
extends Node3D
## Projectile.gd — wlasny pocisk z CCD (TDD 5/6.4, ROADMAP 4 krok 5). Pod Slingera (ranged)
## i luk Rangera. NIE jest CharacterBody3D — ruch i kolizje liczymy RECZNIE raycastem prev->new
## (continuous collision detection), zeby szybki pocisk nie "przeskoczyl" cienkiej sciany/wroga.
##
## Zasada (host-authoritative): ruch i CCD liczy autorytet (w SP = lokalnie). Maska CCD to
## teren | cialo_celu. Pierce N: po trafieniu zmniejsza licznik; gdy 0 -> impakt i znika.
## Trafienie idzie przez DamageService.request_hit (jedno zrodlo obrazen) — pocisk nie liczy HP.
##
## Spawn: Slinger/luk tworzy Projectile, ustawia setup(...) i dodaje do drzewa (Main/world).

signal impacted(position: Vector3, hit_target: Node)

@export var speed: float = 22.0
@export var gravity: float = 0.0              # 0 = prosty pocisk; >0 = luk/strzala z opadaniem
@export var lifetime: float = 5.0             # s do auto-despawn (bezpiecznik)
@export var radius: float = 0.18              # promien wizualu + tolerancja CCD (sphere cast)
@export var pierce: int = 0                   # ile DODATKOWYCH celow przebija (0 = pierwszy i koniec)
@export var hit_terrain_stops: bool = true    # czy teren zatrzymuje pocisk

## Maska CCD. Domyslnie teren(bit0) + cialo wroga(bit2). Slinger (wrog) nadpisze na cialo gracza.
@export_flags_3d_physics var collide_mask: int = (1 << 0) | (1 << 2)

const LAYER_TERRAIN: int = 1 << 0
const LAYER_PLAYER_BODY: int = 1 << 1
const LAYER_ENEMY_BODY: int = 1 << 2

var _source: Node = null                       # kto wystrzelil (do DamageService + ignore self)
var _hit_builder: Callable = Callable()        # func(target) -> HitData (jak w HitboxComponent)
var _velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _pierced_ids: PackedInt64Array = PackedInt64Array()
var _mesh: MeshInstance3D = null
var _dead: bool = false


## Konfiguracja przed dodaniem do drzewa. dir znormalizowany; hit_builder buduje HitData per cel.
func setup(p_source: Node, dir: Vector3, p_speed: float, hit_builder: Callable,
		p_mask: int = -1, p_gravity: float = -1.0, p_pierce: int = -1) -> void:
	_source = p_source
	_hit_builder = hit_builder
	if p_speed > 0.0:
		speed = p_speed
	if p_mask >= 0:
		collide_mask = p_mask
	if p_gravity >= 0.0:
		gravity = p_gravity
	if p_pierce >= 0:
		pierce = p_pierce
	var d := dir
	d = d.normalized() if d.length() > 0.001 else Vector3.FORWARD
	_velocity = d * speed


func _ready() -> void:
	_build_visual()


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	_mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.8, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.15)
	mat.emission_energy_multiplier = 2.0
	_mesh.material_override = mat
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_age += delta
	if _age >= lifetime:
		_despawn(global_position, null)
		return

	# Tylko autorytet liczy ruch/CCD/obrazenia (Etap 7: klienci interpoluja replike).
	if NetManager != null and not NetManager.has_authority(_source):
		# Klient i tak przesunie wizual prosto (kosmetyka), ale bez CCD/dmg.
		global_position += _velocity * delta
		return

	if gravity > 0.0:
		_velocity.y -= gravity * delta

	var from := global_position
	var to := from + _velocity * delta
	if _step_ccd(from, to):
		return                              # impakt obsluzony w _step_ccd (despawn lub pierce)
	global_position = to
	# Orientacja wizualu wzdluz lotu (estetyka strzaly/kuli).
	if _velocity.length_squared() > 0.001 and _mesh != null:
		look_at(to + _velocity, Vector3.UP)


## CCD: raycast/shapecast prev->new. Zwraca true jesli pocisk zniknal (impakt terenu/limit pierce).
## Przy pierce: trafia cel, zadaje dmg, doda go do _pierced_ids i LECI DALEJ (false), o ile zostal pierce.
func _step_ccd(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to, collide_mask)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	# Ignoruj wlasne cialo zrodla (gdyby pocisk startowal w kapsule strzelca).
	if _source is CollisionObject3D:
		params.exclude = [(_source as CollisionObject3D).get_rid()]

	var result := space.intersect_ray(params)
	if result.is_empty():
		return false

	var collider: Object = result.get("collider")
	var hit_pos: Vector3 = result.get("position", to)

	# Teren?
	if collider is CollisionObject3D and ((collider as CollisionObject3D).collision_layer & LAYER_TERRAIN) != 0:
		if hit_terrain_stops:
			_despawn(hit_pos, null)
			return true
		return false

	# Encja (cialo gracza/wroga). Wyznacz root encji (collider moze byc samym cialem).
	var target := _entity_of(collider as Node)
	if target == null or target == _source:
		return false
	var oid := target.get_instance_id()
	if _pierced_ids.has(oid):
		return false   # juz przebity ten cel — nie bij dwa razy

	# Obrazenia przez DamageService (jedno zrodlo). HitData buduje zrodlo (zna staty).
	if _hit_builder.is_valid():
		var hit = _hit_builder.call(target)
		if hit != null:
			DamageService.request_hit(_source, target, hit)
	_pierced_ids.append(oid)

	if pierce > 0:
		pierce -= 1
		global_position = hit_pos          # kontynuuj zza celu
		return false
	_despawn(hit_pos, target)
	return true


func _entity_of(node: Node) -> Node:
	if node == null:
		return null
	if node is HurtboxComponent:
		return (node as HurtboxComponent).get_owner_entity()
	if node.has_method("take_damage") or _has_health(node):
		return node
	var p := node.get_parent()
	if p != null and (p.has_method("take_damage") or _has_health(p)):
		return p
	return node


func _has_health(n: Node) -> bool:
	for c in n.get_children():
		if c is HealthComponent:
			return true
	return false


func _despawn(pos: Vector3, target: Node) -> void:
	if _dead:
		return
	_dead = true
	impacted.emit(pos, target)
	queue_free()
