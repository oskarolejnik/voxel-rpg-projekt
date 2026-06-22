class_name HazardZone
extends Area3D
## HazardZone.gd (Area3D) — trwala strefa tykajaca obrazeniami (TDD 6.4, ROADMAP 4 krok 5/6).
## Pod magie obszarowa (kaluze) ORAZ telegrafy elite/boss (tryb preview = sam wizual, bez dmg).
##
## duration: jak dlugo strefa zyje (s; <=0 = stala do recznego usuniecia).
## tick_interval: co ile sekund zadaje obrazenia kazdej encji wewnatrz.
## preview: gdy true -> TYLKO wizual (telegraf), zero obrazen (faza zapowiedzi ataku). Po
##          arm() przechodzi w tryb aktywny. Tyka (dmg) WYLACZNIE na hoscie (TDD 6.4).
##
## Obrazenia ida przez DamageService.request_hit (jedno zrodlo). HitData buduje zrodlo (hit_builder).

signal expired()
signal armed()

@export var radius: float = 2.5
@export var duration: float = 3.0
@export var tick_interval: float = 0.5
@export var preview: bool = false             # true = telegraf (bez dmg), false = aktywna strefa
@export var preview_color: Color = Color(1.0, 0.4, 0.1, 0.35)
@export var active_color: Color = Color(1.0, 0.25, 0.1, 0.45)

## Maska wykrywania cel. Domyslnie cialo gracza (strefa wroga). Strefa gracza -> cialo wroga.
@export_flags_3d_physics var target_mask: int = (1 << 1)

var _source: Node = null
var _hit_builder: Callable = Callable()
var _age: float = 0.0
var _tick_left: float = 0.0
var _decal: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _shape: CollisionShape3D = null


func setup(p_source: Node, hit_builder: Callable, p_mask: int = -1) -> void:
	_source = p_source
	_hit_builder = hit_builder
	if p_mask >= 0:
		target_mask = p_mask


func _ready() -> void:
	monitoring = not preview      # telegraf nie monitoruje (zero dmg/query)
	monitorable = false
	collision_layer = 0
	collision_mask = target_mask
	_tick_left = tick_interval
	_build_shape()
	_build_decal()
	_refresh_color()


func _build_shape() -> void:
	_shape = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 4.0                # wysoki walec — lapie cel niezaleznie od drobnych roznic Y
	_shape.shape = cyl
	add_child(_shape)


func _build_decal() -> void:
	# Plaski dysk na ziemi jako czytelny znacznik strefy/telegrafu.
	_decal = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.05
	_decal.mesh = cyl
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = preview_color
	_mat.emission_enabled = true
	_mat.emission = Color(active_color.r, active_color.g, active_color.b)
	_mat.emission_energy_multiplier = 0.6
	_decal.material_override = _mat
	_decal.position.y = 0.03
	add_child(_decal)


func _refresh_color() -> void:
	if _mat != null:
		_mat.albedo_color = preview_color if preview else active_color


## Uzbraja telegraf: preview -> aktywna strefa (wlacza monitorowanie + obrazenia).
## UWAGA (review #minor): jesli strefa nie ma waznego _hit_builder, po uzbrojeniu _do_tick nie zada
## obrazen (is_valid()==false). Telegrafy elite/boss z Enemy._spawn_telegraph sa CZYSTO WIZUALNE
## (dmg idzie hitboxem/Projectile) i NIE wolno ich arm() — ostrzegamy, by ewentualne przyszle
## uzycie arm() na takim telegrafie nie "zjadlo" ciosu po cichu.
func arm() -> void:
	if not preview:
		return
	if not _hit_builder.is_valid():
		push_warning("HazardZone.arm() bez waznego hit_builder — strefa nie zada obrazen (telegraf czysto wizualny?).")
	preview = false
	monitoring = true
	_age = 0.0
	_tick_left = 0.0          # pierwszy tick od razu po uzbrojeniu
	_refresh_color()
	armed.emit()


func _physics_process(delta: float) -> void:
	_age += delta
	if duration > 0.0 and _age >= duration:
		expired.emit()
		queue_free()
		return

	if preview:
		# Pulsowanie telegrafu (czytelnosc zapowiedzi). Bez obrazen.
		if _mat != null:
			var p := 0.25 + 0.15 * sin(_age * 8.0)
			_mat.albedo_color = Color(preview_color.r, preview_color.g, preview_color.b, p)
		return

	# Tylko autorytet zadaje obrazenia (TDD 6.4: strefa tyka na hoscie, wizual replikowany).
	if NetManager != null and not NetManager.has_authority(_source):
		return

	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = tick_interval
		_do_tick()


func _do_tick() -> void:
	for body in get_overlapping_bodies():
		var target := _entity_of(body)
		if target == null or target == _source:
			continue
		if _hit_builder.is_valid():
			var hit = _hit_builder.call(target)
			if hit != null:
				DamageService.request_hit(_source, target, hit)


func _entity_of(node: Node) -> Node:
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
