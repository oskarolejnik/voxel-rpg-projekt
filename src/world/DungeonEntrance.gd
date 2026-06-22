class_name DungeonEntrance
extends Node3D
## DungeonEntrance.gd — WEJSCIA dungeonow w otwartym swiecie (ETAP 5, GDD 8 / TDD 7.2).
##
## Wejscia sa DETERMINISTYCZNE z seeda chunka: kazdy klient liczy je identycznie (po sieci nic
## nie leci poza seed+tier przy wejsciu — Etap 7). chunk_has_entrance() reuzuje VoxelWorld.
## feature_hash (to samo, juz deterministyczne zrodlo co roslinnosc/biom — TDD 7.1) z wlasnym
## SALT, a entrance_seed() z innym SALT. Szansa per chunk = BiomeResource.entrance_chance biomu.
##
## DZIALANIE (instancja w scenie): EntranceManager (wezel pod Main) skanuje chunki wokol gracza,
## stawia voxelowy prefab wejscia (krag runiczny + portal) z Area3D na warstwie interactable;
## gdy gracz jest blisko i wcisnie klawisz (E) -> sygnal enter_requested(entrance_seed, tier, biome)
## -> Main robi fade + przejscie do DungeonRun. CZYSTE helpery (static) sa testowalne headless
## (DoD: ten sam chunk -> ten sam entrance_seed; rozne chunki -> rozny).

# Salty feature_hash (rozlaczne wzgledem Chunk.SALT_* i WorldSpawner.SALT_*).
const SALT_DUNGEON: int = 0xD001        # czy chunk ma wejscie
const SALT_DUNGEON_SEED: int = 0xD002   # entrance_seed (uklad dungeonu)

## ====================================================================
##  CZYSTE HELPERY (deterministyczne, testowalne headless)
## ====================================================================

## Czy chunk (cx, cz) ma wejscie dungeonu. roll = feature_hash(cx,cz,SALT_DUNGEON) < entrance_chance
## biomu chunka. biome -> BiomeResource.entrance_chance (Verdant 1% / Ember 3% / Frost 5% wg .tres).
## Brak BiomeResource -> fallback 1%. DETERMINISTYCZNY (czysta funkcja feature_hash + DB).
static func chunk_has_entrance(world: VoxelWorld, cx: int, cz: int) -> bool:
	if world == null:
		return false
	var roll := world.feature_hash(cx, cz, SALT_DUNGEON)
	var chance := _entrance_chance(world, cx, cz)
	return roll < chance


## entrance_seed dla chunka (DETERMINISTYCZNY uklad: ten sam chunk -> ten sam dungeon). Wyprowadzony
## z feature_hash innym saltem; mapowany na duzy int (zakres jak feature_hash * 2^30).
static func entrance_seed(world: VoxelWorld, cx: int, cz: int) -> int:
	if world == null:
		return 0
	return int(world.feature_hash(cx, cz, SALT_DUNGEON_SEED) * float(0x40000000))


## Tier dungeonu dla chunka (model CW: glebiej od spawnu = wyzszy tier). Bazuje na distance_tier
## swiata (1..5) + premia loot_tier biomu (Frosthelm > Emberwaste > Verdant). Skaluje uklad/loot.
static func entrance_tier(world: VoxelWorld, cx: int, cz: int) -> int:
	if world == null:
		return 1
	var wx := float(cx * VoxelWorld.CHUNK_SIZE) * VoxelWorld.VOXEL_SIZE
	var wz := float(cz * VoxelWorld.CHUNK_SIZE) * VoxelWorld.VOXEL_SIZE
	var dtier := world.distance_tier(wx, wz)
	var biome_id := world.get_biome(int(wx), int(wz))
	var b_bonus := 0
	if EnemyDB != null:
		var br: BiomeResource = EnemyDB.biome(biome_id)
		if br != null:
			b_bonus = maxi(0, br.loot_tier - 1)
	return clampi(dtier + b_bonus, 1, 8)


## Biom chunka (do doboru wrogow/lootu dungeonu). Srodek chunka w metrach -> VoxelWorld.get_biome.
static func entrance_biome(world: VoxelWorld, cx: int, cz: int) -> StringName:
	if world == null:
		return &"verdant"
	var span := float(VoxelWorld.CHUNK_SIZE) * VoxelWorld.VOXEL_SIZE
	var wx := int((float(cx) + 0.5) * span)
	var wz := int((float(cz) + 0.5) * span)
	return world.get_biome(wx, wz)


static func _entrance_chance(world: VoxelWorld, cx: int, cz: int) -> float:
	var span := float(VoxelWorld.CHUNK_SIZE) * VoxelWorld.VOXEL_SIZE
	var wx := int((float(cx) + 0.5) * span)
	var wz := int((float(cz) + 0.5) * span)
	var biome_id := world.get_biome(wx, wz)
	if EnemyDB != null:
		var br: BiomeResource = EnemyDB.biome(biome_id)
		if br != null:
			return maxf(0.0, br.entrance_chance)
	return 0.01


## ====================================================================
##  INSTANCJA W SCENIE: voxelowy prefab wejscia + interakcja gracza
## ====================================================================

signal enter_requested(seed: int, tier: int, biome: StringName)

## Promien interakcji (metry) — gracz blizej niz to widzi podpowiedz i moze wejsc klawiszem.
const INTERACT_RADIUS: float = 3.0

var _seed: int = 0
var _tier: int = 1
var _biome: StringName = &"verdant"
var _player: Node3D = null
var _prompt: Label3D = null
var _in_range: bool = false


## Konfiguruje wejscie PRZED add_child. seed/tier/biome z helperow powyzej; player do dystansu.
func setup(p_seed: int, p_tier: int, p_biome: StringName, player: Node3D) -> void:
	_seed = p_seed
	_tier = maxi(1, p_tier)
	_biome = p_biome if p_biome != &"" else &"verdant"
	_player = player


func _ready() -> void:
	add_to_group("dungeon_entrances")
	_build_visual()
	_build_prompt()


## Voxelowy prefab: krag runiczny (pierscien kamieni) + ciemny "portal" w srodku. Czytelny,
## tani (kilkanascie BoxMesh). Material wlasny (nie zalezy od swiata).
func _build_visual() -> void:
	var ring_col := Color(0.30, 0.28, 0.34)
	var rune_col := Color(0.45, 0.85, 1.0)
	var n := 10
	var radius := 1.6
	for i in n:
		var ang := float(i) / float(n) * TAU
		var p := Vector3(cos(ang) * radius, 0.0, sin(ang) * radius)
		var h := 0.6 + (0.4 if i % 2 == 0 else 0.0)
		_pillar(p, h, ring_col, i % 3 == 0, rune_col)
	# Portal: ciemna, lekko swiecaca tafla na ziemi (wizualna wskazowka wejscia).
	var portal := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.8
	cyl.bottom_radius = radius * 0.8
	cyl.height = 0.05
	portal.mesh = cyl
	portal.position = Vector3(0.0, 0.05, 0.0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.05, 0.02, 0.12)
	pm.emission_enabled = true
	pm.emission = Color(0.25, 0.10, 0.5)
	pm.emission_energy_multiplier = 1.2
	portal.material_override = pm
	add_child(portal)

	# Area3D interakcji (warstwa interactable bit7) — opcjonalne wykrywanie ciala gracza.
	var area := Area3D.new()
	area.name = "InteractArea"
	area.collision_layer = (1 << 7)       # interactable
	area.collision_mask = (1 << 1)        # cialo gracza
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = INTERACT_RADIUS
	cs.shape = sph
	area.add_child(cs)
	area.body_entered.connect(func(b: Node) -> void:
		if b != null and (b.is_in_group("player") or b == _player):
			_in_range = true)
	area.body_exited.connect(func(b: Node) -> void:
		if b != null and (b.is_in_group("player") or b == _player):
			_in_range = false)
	add_child(area)


func _pillar(pos: Vector3, h: float, col: Color, glow: bool, glow_col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, h, 0.4)
	mi.mesh = bm
	mi.position = pos + Vector3(0.0, h * 0.5, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if glow:
		m.emission_enabled = true
		m.emission = glow_col
		m.emission_energy_multiplier = 0.8
	mi.material_override = m
	add_child(mi)


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.text = "[E] Wejdz do dungeonu (T%d)" % _tier
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.position = Vector3(0.0, 2.4, 0.0)
	_prompt.modulate = Color(0.8, 0.95, 1.0)
	_prompt.outline_size = 6
	_prompt.visible = false
	add_child(_prompt)


func _process(_delta: float) -> void:
	# Dystans XZ do gracza (fallback gdy Area3D nie zdazyl). Pokaz podpowiedz w zasiegu.
	if _player != null and is_instance_valid(_player):
		var d := _player.global_position - global_position
		var dist := Vector2(d.x, d.z).length()
		_in_range = dist <= INTERACT_RADIUS
	if _prompt != null:
		_prompt.visible = _in_range


## Input: klawisz E w zasiegu -> zazadaj wejscia (Main przejmuje przejscie do DungeonRun).
func _unhandled_input(event: InputEvent) -> void:
	if not _in_range:
		return
	if GameState != null and GameState.ui_capturing_input:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_E:
		enter_requested.emit(_seed, _tier, _biome)


func get_seed() -> int: return _seed
func get_tier() -> int: return _tier
func get_biome() -> StringName: return _biome
