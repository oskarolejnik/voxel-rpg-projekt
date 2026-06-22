class_name LootDrop
extends Node3D
## LootDrop.gd — fizyczna encja lootu w swiecie (Etap 2). Spawnowana na smierc wroga
## (LootService.drop_for) i podnoszona przez gracza (dystans/Area3D na warstwie interactable).
##
## Wizual: voxelowy szescian + halo w KOLORZE RZADKOSCI (LootService.rarity_color) + delikatne
## unoszenie i obrot (czytelnosc w chaosie hordy). Zloto = osobny, zolty wariant (bez ItemInstance).
##
## Pickup: gdy gracz (grupa "player") zblizy sie na pickup_radius -> przekazujemy ItemInstance do
## jego InventoryComponent (plecak) albo zloto do GameState/save, i emitujemy `picked_up` (toast).
## Pickup rozstrzyga AUTORYTET (NetManager.has_authority) — w SP zawsze lokalnie; w Etapie 7 host.
##
## Spawn helpera: LootDrop.spawn_item(parent, pos, instance) / spawn_gold(parent, pos, amount).

signal picked_up(drop: LootDrop)

const PICKUP_RADIUS_DEFAULT: float = 1.8
const INTERACTABLE_LAYER: int = 1 << 7        # TDD 5: bit 7 = interactable (loot/wejscia/bestie)
const DESPAWN_AFTER: float = 120.0            # s — loot znika po czasie (anti-bloat)

@export var pickup_radius: float = PICKUP_RADIUS_DEFAULT

## Zawartosc dropu: dokladnie JEDNO z ponizszych jest ustawione.
var item: ItemInstance = null                 # drop itemu
var gold: int = 0                             # drop zlota (gdy item == null)

var _age: float = 0.0
var _spin: float = 0.0
var _base_y: float = 0.0
var _picked: bool = false
var _mesh: MeshInstance3D
var _halo: MeshInstance3D


# ============================================================================
#  FABRYKI (spawn w kodzie — bez .tscn, jak reszta encji w tym projekcie)
# ============================================================================

static func spawn_item(parent: Node, pos: Vector3, instance: ItemInstance) -> LootDrop:
	var d := LootDrop.new()
	d.item = instance
	parent.add_child(d)
	d.global_position = pos
	return d


static func spawn_gold(parent: Node, pos: Vector3, amount: int) -> LootDrop:
	var d := LootDrop.new()
	d.gold = amount
	parent.add_child(d)
	d.global_position = pos
	return d


# ============================================================================
#  CYKL ZYCIA
# ============================================================================

func _ready() -> void:
	add_to_group("loot_drops")
	_base_y = global_position.y
	_build_visual()
	_build_pickup_area()


func _process(delta: float) -> void:
	_age += delta
	_spin += delta * 1.6
	# Unoszenie (sin) + obrot — czytelny "loot beacon".
	if _mesh != null:
		_mesh.rotation.y = _spin
		_mesh.position.y = 0.45 + sin(_age * 2.4) * 0.12
	if _halo != null:
		_halo.rotation.y = -_spin * 0.5
	# Despawn po czasie (gdy nikt nie podniesie).
	if _age >= DESPAWN_AFTER and not _picked:
		queue_free()


# ============================================================================
#  WIZUAL: voxelowy szescian + halo w kolorze rzadkosci
# ============================================================================

func _build_visual() -> void:
	var col := _drop_color()

	# Rdzen — maly szescian z emisja koloru rzadkosci (swieci, czytelny w mgle/nocy).
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.32, 0.32)
	_mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.4
	_mesh.material_override = mat
	_mesh.position.y = 0.45
	add_child(_mesh)

	# Halo — plaski, polprzezroczysty kwadrat pod itemem (slup swiatla "tanio").
	_halo = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.9, 0.9)
	_halo.mesh = qm
	_halo.rotation_degrees.x = -90.0
	_halo.position.y = 0.05
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(col.r, col.g, col.b, 0.35)
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.emission_enabled = true
	hmat.emission = col
	hmat.emission_energy_multiplier = 0.8
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_halo.material_override = hmat
	add_child(_halo)


## Kolor dropu: zloto -> zloty; item -> kolor rzadkosci (LootService).
func _drop_color() -> Color:
	if item != null:
		return LootService.rarity_color(item.rarity)
	return Color(0.95, 0.78, 0.20)   # zloto


# ============================================================================
#  PICKUP: Area3D na warstwie interactable + sprawdzenie dystansu
# ============================================================================

func _build_pickup_area() -> void:
	var area := Area3D.new()
	area.collision_layer = INTERACTABLE_LAYER
	area.collision_mask = 1 << 1               # wykrywa cialo gracza (warstwa 2, bit 1)
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = pickup_radius
	cs.shape = sph
	cs.position.y = 0.45
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _picked:
		return
	if not (body != null and body.is_in_group("player")):
		return
	# Pickup rozstrzyga autorytet (anti-desync). W SP zawsze true.
	if not NetManager.has_authority(self):
		return
	_try_pickup(body)


## Probuje podniesc loot do ekwipunku gracza. Item -> InventoryComponent.add_to_backpack; zloto ->
## GameState.add_gold (jesli istnieje). Emituje picked_up (toast) i znika.
func _try_pickup(player: Node) -> void:
	if item != null:
		var inv := _find_inventory(player)
		if inv == null:
			return   # brak ekwipunku -> nie podnosimy (item zostaje)
		inv.add_to_backpack(item)
	elif gold > 0:
		if GameState != null and GameState.has_method("add_gold"):
			GameState.add_gold(gold)
	_picked = true
	picked_up.emit(self)
	queue_free()


func _find_inventory(player: Node) -> InventoryComponent:
	for c in player.get_children():
		if c is InventoryComponent:
			return c as InventoryComponent
	return null
