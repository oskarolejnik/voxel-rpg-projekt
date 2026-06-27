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

## ETAP 7b: net_id replikacji (0 = SP / niezarejestrowany). Host nadaje przy host_spawn_loot;
## klient prosi hosta o pickup po tym id (request_loot_pickup). W SP zostaje 0 (pickup lokalny).
var net_id: int = 0

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
		# ETAP 7b (review #minor): w co-opie timeout MUSI isc przez autorytatywny despawn hosta, inaczej
		# (a) rejestr hosta _world_entities/_entity_spawn_data przecieka (czyszczony tylko przy pickup),
		# (b) host i klient zwalniaja replike niezaleznie (rozjazd o klatke). HOST -> host_despawn_entity
		# (RPC despawn u wszystkich + unregister). SP/KLIENT -> goly queue_free (SP IDENTYCZNY; replika
		# klienta i tak dostanie _rpc_despawn_entity od hosta lub zwolni sie po wlasnym timerze).
		if net_id > 0 and NetManager != null and NetManager.has_network() and NetManager.is_host():
			NetManager.host_despawn_entity(net_id)
		else:
			queue_free()


# ============================================================================
#  WIZUAL: voxelowy szescian + halo w kolorze rzadkosci
# ============================================================================

# FEEL 3: GLOW lootu skaluje sie z RZADKOSCIA — wyzsza rzadkosc => mocniejsza emisja, wieksze halo,
# a od RARE w gore PIONOWY BEAM (slup swiatla) widoczny z daleka w hordzie/mgle. Czytelnosc "co warto
# podniesc" bez UI. Indeks rzadkosci 0..5 (COMMON..SET); zloto traktujemy jak UNCOMMON-tier blask.
const _LOOT_BEAM_FROM_RARITY: int = 2     # RARE i wyzej dostaja pionowy slup swiatla
var _beam: MeshInstance3D = null

## Indeks rzadkosci dropu (0..5). Zloto bez itemu -> 1 (lekki, zauwazalny blask, nie szary common).
func _rarity_index() -> int:
	if item != null:
		# LOOT: 7 tierów — clamp do liczby kolorów rzadkości (0..7), żeby MYTHIC/ANCIENT miały własny blask.
		return clampi(item.rarity, 0, LootService.RARITY_COLORS.size() - 1)
	return 1   # zloto ~ UNCOMMON-tier blask

func _build_visual() -> void:
	var col := _drop_color()
	var r := _rarity_index()
	# Skala glow rosnie z rzadkoscia (COMMON niski, SET mocny). Trzymane pod glow_hdr_threshold=1.0
	# (energia ~1.2..3.0) => legenda swieci wyraznie, common nie robi flara.
	var emis_core := 1.2 + float(r) * 0.38       # 1.20 (common) .. 3.10 (set)
	var halo_scale := 0.85 + float(r) * 0.14     # 0.85 .. 1.55 m
	var emis_halo := 0.6 + float(r) * 0.22       # 0.60 .. 1.70

	# Rdzen — maly szescian z emisja koloru rzadkosci (swieci, czytelny w mgle/nocy).
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.32, 0.32)
	_mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = emis_core
	_mesh.material_override = mat
	_mesh.position.y = 0.45
	add_child(_mesh)

	# Halo — plaski, polprzezroczysty kwadrat pod itemem (slup swiatla "tanio"). Rozmiar ~ rzadkosc.
	_halo = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(halo_scale, halo_scale)
	_halo.mesh = qm
	_halo.rotation_degrees.x = -90.0
	_halo.position.y = 0.05
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(col.r, col.g, col.b, 0.35)
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.emission_enabled = true
	hmat.emission = col
	hmat.emission_energy_multiplier = emis_halo
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_halo.material_override = hmat
	add_child(_halo)

	# FEEL 3: PIONOWY BEAM od RARE w gore — wysoki, waski, additywny slup w kolorze rzadkosci.
	# Billboard-y wokol osi Y (QuadMesh w 2 skrzyzowanych plaszczyznach) => widoczny z kazdego kata.
	# Tani (2 quady, unshaded, additive, bez cieni). Anti-bloat: tylko dla wartosciowego lootu.
	if r >= _LOOT_BEAM_FROM_RARITY:
		_beam = MeshInstance3D.new()
		var beam_h := 2.2 + float(r - _LOOT_BEAM_FROM_RARITY) * 0.5   # RARE 2.2 .. SET 3.7 m
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3(0.10, beam_h, 0.10)
		_beam.mesh = bmesh
		_beam.position.y = beam_h * 0.5
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(col.r, col.g, col.b, 0.5)
		bmat.emission_enabled = true
		bmat.emission = col
		bmat.emission_energy_multiplier = 1.6 + float(r) * 0.2
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		bmat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y   # zawsze zwrocony do kamery (oś Y)
		_beam.material_override = bmat
		add_child(_beam)


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
	# ETAP 7b: pickup rozstrzyga AUTORYTET (anti-desync/anti-dup).
	#  - SP (brak peera): jak dotad — lokalnie i natychmiast (IDENTYCZNIE z Etapem 2).
	#  - HOST: podnosi lokalnie (host = autorytet) + despawn repliki u klientow przez net_id.
	#  - KLIENT: NIE podnosi lokalnie — prosi hosta (host waliduje dystans/istnienie, przyznaje,
	#    despawnuje u wszystkich). Bez tego klient nigdy nie podnioslby lootu (stara bramka).
	if NetManager == null or not NetManager.has_network():
		_try_pickup(body)                              # SP
		return
	if NetManager.is_host():
		_host_grant_pickup(body)                       # HOST: lokalny grant + replikacja despawnu
	else:
		var pid := NetManager.local_peer_id()
		NetManager.request_loot_pickup(net_id, pid)    # KLIENT: prosba do hosta


## SP: pelny lokalny pickup (item -> plecak, zloto -> GameState) + toast + despawn. Bez sieci.
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


## HOST (co-op): gracz (host lub replika klienta) wszedl w loot. Host przyznaje zawartosc lokalnie
## (gdy to host podnosi: item -> jego plecak, zloto -> jego GameState) i rozsyla despawn do klientow.
## Gdy w loot wszedl gracz KLIENTA (replika u hosta), faktyczne przyznanie do plecaka klienta robi
## kanal RPC w NetManager._rpc_request_pickup (host nie ma prawdziwego plecaka klienta) — tu host
## jedynie despawnuje encje u wszystkich (klient sam prosi przez request_loot_pickup, gdy to jego
## lokalny gracz wejdzie w loot u niego). Dla gracza-hosta: pelny lokalny grant.
func _host_grant_pickup(player: Node) -> void:
	if _picked:
		return
	# Czy to LOKALNY gracz hosta? (host ma prawdziwy plecak tylko swojego gracza.)
	var local_p = GameState.local_player if (GameState != null and "local_player" in GameState) else null
	if player == local_p:
		_try_pickup(player)                            # host podnosi dla siebie (lokalny plecak)
	else:
		# Replika gracza klienta wpadla w loot u hosta — przyznaj klientowi przez kanal RPC po jego peer.
		var peer := _peer_of_player(player)
		if peer > 0 and NetManager != null:
			grant_to(player)
			if item != null:
				NetManager._rpc_inventory_add.rpc_id(peer, item.to_dict())
			elif gold > 0:
				NetManager._rpc_grant_gold.rpc_id(peer, gold)
		mark_picked()
	# Despawn repliki u klientow + sprzataj rejestr (idempotentne).
	if net_id > 0 and NetManager != null:
		NetManager.host_despawn_entity(net_id)


## Znajduje peer-wlasciciela encji gracza (po NetManager rosterze). 0 gdy nieznany.
func _peer_of_player(player: Node) -> int:
	if NetManager == null:
		return 0
	for pid in NetManager.peer_ids():
		if NetManager.player_for_peer(int(pid)) == player:
			return int(pid)
	return 0


## ETAP 7b: przyznaje zawartosc lootu graczowi PO STRONIE HOSTA (autorytet). Item -> plecak gracza
## (gdy host ma jego prawdziwy InventoryComponent, tj. gracz-host); zloto -> GameState. Dla repliki
## klienta plecak jest po stronie klienta — host woła to dla spojnosci, a realne dodanie robi RPC.
func grant_to(player: Node) -> void:
	if item != null:
		var inv := _find_inventory(player)
		if inv != null:
			inv.add_to_backpack(item)
	elif gold > 0:
		if GameState != null and GameState.has_method("add_gold"):
			GameState.add_gold(gold)


## Czy loot zostal juz podniesiony (host/klient czyta przed grantem — anti-dup).
func is_picked() -> bool:
	return _picked


## Oznacza loot jako podniesiony + emituje picked_up (rejestr/toast). Idempotentne.
func mark_picked() -> void:
	if _picked:
		return
	_picked = true
	picked_up.emit(self)


## ETAP 7b: toast lokalny u gracza, ktory podniosl loot w co-opie (host rozstrzyga, ale toast pokazuje
## sie tylko wlascicielowi). Main podpina picked_up do toastu; tu emitujemy je dla spojnosci kanalu.
func show_local_toast() -> void:
	picked_up.emit(self)


func _find_inventory(player: Node) -> InventoryComponent:
	for c in player.get_children():
		if c is InventoryComponent:
			return c as InventoryComponent
	return null
