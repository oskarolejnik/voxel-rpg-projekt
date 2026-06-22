class_name WorldSpawner
extends Node
## WorldSpawner.gd (komponent) — DETERMINISTYCZNY spawn wrogów wg biomu + seeda (ETAP 4, DoD).
##
## Zastępuje stały 3× spawn w Main._spawn_enemies. Model „Cube World”: świat podzielony na
## REGIONY (kwadraty REGION_SIZE m). Dla każdego regionu w promieniu wokół gracza losujemy
## ZAWARTOŚĆ deterministycznie z (session_seed, region_x, region_z) — TEN SAM seed/region ZAWSZE
## daje tych samych wrogów (DoD). Region „aktywuje się” raz: po wejściu gracza w jego pobliże
## spawnujemy jego wrogów (o ile mieścimy się w limicie aktywnych); martwy/usunięty wróg NIE
## wraca, dopóki region nie zostanie zapomniany i ponownie aktywowany (świeży spawn z tego samego
## ziarna => znów ci sami wrogowie — pełna powtarzalność).
##
## ZASADY WYDAJNOŚCI (nie psuć 2A/2B): TWARDY limit MAX_ACTIVE aktywnych wrogów (spawn nie zaleje
## sceny); aktywacja max regionów/klatkę; throttling przez interwał. Wrogowie spawnują tylko gdy
## teren regionu jest „gotowy” (height_at zwraca grunt) — VoxelWorld i tak primuje okolicę gracza.
##
## DOBÓR WROGÓW: biom regionu (VoxelWorld.get_biome) -> BiomeResource.enemy_spawn_table (lista
## {enemy_id, weight, max_alive}). Wagi losowane z LOKALNEGO RNG regionu (deterministyczne).
## ilvl/poziom wrogów rośnie z dystansem od spawnu (VoxelWorld.distance_tier — model CW).

## Rozmiar regionu spawnu w METRACH (kwadrat). 48 m ~ pokrywa near_dist (3 chunki × 16 m).
const REGION_SIZE: float = 48.0
## Promień regionów (w komórkach) aktywowanych wokół gracza. 1 => siatka 3×3 regionów.
const REGION_RADIUS: int = 1
## Twardy limit jednocześnie żywych wrogów (anti-flood; chroni FPS 2A/2B).
const MAX_ACTIVE: int = 16
## Ile NOWYCH wrogów spawnujemy max w jednej aktywacji (rozłożenie kosztu add_child).
const MAX_SPAWN_PER_TICK: int = 6
## Co ile sekund przeliczamy regiony (nie co klatkę — tani throttling).
const TICK_INTERVAL: float = 0.5
## Bufor wysokości spawnu nad gruntem (osiadanie na teren).
const SPAWN_Y_OFFSET: float = 1.0
## Min. odległość spawnu od gracza (nie rodzić wroga na głowie).
const MIN_SPAWN_DIST: float = 6.0

## Salty strumienia regionu (rozłączne „rzuty”: ile wrogów, który wróg, gdzie).
const SALT_COUNT: int = 0x51A1
const SALT_PICK: int = 0x71B2
const SALT_POS: int = 0x93C3

var _world: VoxelWorld = null
var _player: Node3D = null
var _active: int = 0                       # aktualnie żywi wrogowie (z tego spawnera)
var _activated: Dictionary = {}            # Vector2i(region) -> true (już zaktywowany, nie dubluj)
var _tick_left: float = 0.0
## Callbacki właściciela (Main) — podpięcie sygnałów wroga (śmierć/loot) jak w starym _spawn_enemies.
var _on_died: Callable = Callable()
var _on_loot: Callable = Callable()


## Wstrzykuje zależności. base_seed: ziarno determinizmu (domyślnie RNGService.world_seed()).
## on_died/on_loot: opcjonalne Callable(enemy) wołane po spawnie do podpięcia sygnałów.
func setup(world: VoxelWorld, player: Node3D, on_died: Callable = Callable(),
		on_loot: Callable = Callable()) -> void:
	_world = world
	_player = player
	_on_died = on_died
	_on_loot = on_loot


func _process(delta: float) -> void:
	if _world == null or _player == null or not is_instance_valid(_player):
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK_INTERVAL
	_update_regions()


## Aktywuje regiony w promieniu wokół gracza (deterministyczny spawn). Region raz aktywowany
## nie spawnuje ponownie (dopóki nie zapomniany). Limit aktywnych pilnuje, by nie zalać sceny.
func _update_regions() -> void:
	if _active >= MAX_ACTIVE:
		return
	var pr := _region_of(_player.global_position)
	for dx in range(-REGION_RADIUS, REGION_RADIUS + 1):
		for dz in range(-REGION_RADIUS, REGION_RADIUS + 1):
			var region := Vector2i(pr.x + dx, pr.y + dz)
			if _activated.has(region):
				continue
			_activate_region(region)
			if _active >= MAX_ACTIVE:
				return


## Region -> Vector2i (komórka kwadratowej siatki REGION_SIZE m).
func _region_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / REGION_SIZE), floori(pos.z / REGION_SIZE))


## DETERMINISTYCZNY spawn zawartości regionu. Buduje LOKALNY RNG z (base_seed, region) — ten sam
## seed/region => identyczna lista wrogów (kolejność, typy, pozycje). Wpina ich do drzewa (rodzic =
## właściciel spawnera, tj. Main), ustawia cel/loot/ilvl. Limit aktywnych i MAX_SPAWN_PER_TICK.
func _activate_region(region: Vector2i) -> void:
	_activated[region] = true
	var biome_id := _region_biome(region)
	var table := _spawn_table_for(biome_id)
	if table.is_empty():
		return

	var rng := _region_rng(region)
	# Ile wrogów w regionie: 0..MAX_PER_REGION (gęstość rośnie lekko z dystansem; deterministyczne).
	var center := _region_center(region)
	var dtier := _world.distance_tier(center.x, center.z)
	var max_in_region := mini(3 + dtier, MAX_SPAWN_PER_TICK)
	var count := rng.randi_range(0, max_in_region)

	var spawned := 0
	for _i in count:
		if _active >= MAX_ACTIVE or spawned >= MAX_SPAWN_PER_TICK:
			break
		var entry := _weighted_pick(rng, table)
		if entry.is_empty():
			break
		var enemy_id := StringName(entry.get("enemy_id", &""))
		if _world == null:
			break
		var ppos := _spawn_pos(rng, region)
		# Nie rodzić na graczu.
		if _player != null and is_instance_valid(_player):
			if Vector2(ppos.x - _player.global_position.x, ppos.z - _player.global_position.z).length() < MIN_SPAWN_DIST:
				continue
		_spawn_enemy(enemy_id, ppos, biome_id, dtier)
		spawned += 1


## Buduje LOKALNY deterministyczny RNG regionu z base_seed + współrzędnych (jak feature_hash).
func _region_rng(region: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = region_seed(_base_seed(), region)
	return rng


## Publiczny, czysty helper (testowalny): deterministyczny seed regionu z bazowego seeda + coord.
## Integerowy mix (jak feature_hash) — ten sam (base, region) ZAWSZE ten sam seed.
static func region_seed(base: int, region: Vector2i) -> int:
	var h: int = base
	h = (h * 73856093) ^ (region.x * 19349663)
	h = (h * 83492791) ^ (region.y * 50331653)
	h ^= (h >> 13)
	h = h * 1274126177
	h ^= (h >> 16)
	return h & 0x7FFFFFFFFFFFFFFF


## Bazowy seed determinizmu — z RNGService (jedno źródło seeda z VoxelWorld/sesją).
func _base_seed() -> int:
	if RNGService != null:
		return RNGService.world_seed()
	return VoxelWorld.FEATURE_SEED


## Biom regionu = biom jego środka (spójny z get_biome świata; cały region = jeden biom).
func _region_biome(region: Vector2i) -> StringName:
	var c := _region_center(region)
	return _world.get_biome(int(floor(c.x)), int(floor(c.z)))


func _region_center(region: Vector2i) -> Vector3:
	return Vector3((float(region.x) + 0.5) * REGION_SIZE, 0.0, (float(region.y) + 0.5) * REGION_SIZE)


## Tabela spawnu dla biomu z BiomeResource (EnemyDB). Pusta -> [] (region bez wrogów).
func _spawn_table_for(biome_id: StringName) -> Array:
	if EnemyDB == null:
		return []
	var br: BiomeResource = EnemyDB.biome(biome_id)
	if br == null:
		return []
	return br.enemy_spawn_table


## Ważony wybór wpisu {enemy_id, weight,...} z tabeli (LOKALNY RNG => deterministyczny).
func _weighted_pick(rng: RandomNumberGenerator, table: Array) -> Dictionary:
	var total := 0.0
	for e in table:
		total += maxf(0.0, float((e as Dictionary).get("weight", 1.0)))
	if total <= 0.0:
		return {}
	var r := rng.randf() * total
	var acc := 0.0
	for e in table:
		acc += maxf(0.0, float((e as Dictionary).get("weight", 1.0)))
		if r < acc:
			return e
	return table[table.size() - 1]


## Deterministyczna pozycja spawnu w regionie (offset z RNG) z gruntem z height_at. Wołać tylko
## gdy _world != null (caller sprawdza) — zwraca konkretny Vector3 (typowany, brak Variant).
func _spawn_pos(rng: RandomNumberGenerator, region: Vector2i) -> Vector3:
	var ox := rng.randf() * REGION_SIZE
	var oz := rng.randf() * REGION_SIZE
	var wx := float(region.x) * REGION_SIZE + ox
	var wz := float(region.y) * REGION_SIZE + oz
	var wy := _world.height_at(wx, wz) + SPAWN_Y_OFFSET
	return Vector3(wx, wy, wz)


## Tworzy Enemy z EnemyResource (EnemyDB), konfiguruje PRZED add_child (staty wejdą do komponentów),
## ustawia loot (ilvl wg dystansu, biom regionu), cel = gracz, sygnały. Zlicza aktywnych.
func _spawn_enemy(enemy_id: StringName, pos: Vector3, biome_id: StringName, dtier: int) -> void:
	var res: EnemyResource = EnemyDB.enemy(enemy_id) if EnemyDB != null else null
	var e := Enemy.new()
	e.configure_from_resource(res)       # PRZED add_child -> _build_components widzi docelowe staty
	# Loot: ilvl skaluje się z dystansem (model CW), biom regionu filtruje afiksy tematyczne.
	# ETAP 4 (review #MAJOR — loot_tier biomu wpięty BEHAWIORALNIE, nie tylko deklaratywnie):
	# pobieramy BiomeResource.loot_tier i (a) PODBIJAMY ilvl o (loot_tier-1)*2 — bogatszy biom daje
	# mocniejsze itemy, (b) przekazujemy loot_tier_bonus do wroga — LootService._roll_rarity przesuwa
	# wagi rzadkości ku górze. Wcześniej loot_tier był martwy (czytany tylko w teście, nie w dropie).
	var b_tier := 1
	if EnemyDB != null:
		var br: BiomeResource = EnemyDB.biome(biome_id)
		if br != null:
			b_tier = maxi(1, br.loot_tier)
	e.loot_ilvl = maxi(1, dtier * 2 + (b_tier - 1) * 2)
	e.loot_biome = biome_id
	e.loot_tier_bonus = b_tier - 1
	e.position = pos
	var parent := get_parent()
	if parent == null:
		e.free()
		return
	parent.add_child(e)
	e.global_position = pos
	if _player != null and is_instance_valid(_player):
		e.set_target(_player)
	# Podpięcie sygnałów: lokalny licznik + ewentualne callbacki właściciela (Main HUD/loot).
	e.died.connect(_on_enemy_died)
	if _on_loot.is_valid():
		e.loot_dropped.connect(_on_loot)
	if _on_died.is_valid():
		e.died.connect(_on_died)
	_active += 1


func _on_enemy_died(_e: Enemy) -> void:
	_active = maxi(0, _active - 1)


## Diagnostyka: liczba aktywnych wrogów z tego spawnera.
func active_count() -> int:
	return _active


## Zeruje licznik aktywnych wrogów (review #MAJOR). Wołane przez DungeonManager przy wejściu do
## dungeonu PO usunięciu wrogów świata (queue_free NIE emituje Enemy.died, więc _on_enemy_died nie
## zdejmuje licznika — bez tego _active zostaje zawyżone i _update_regions robi early-return na
## _active >= MAX_ACTIVE, blokując spawn po powrocie). Po wyjściu spawner znów aktywuje regiony.
## NIE czyści _activated: odwiedzone regiony świata pozostają „zapamiętane” (świeży spawn z tego
## samego ziarna => ci sami wrogowie dopiero po zapomnieniu regionu — kontrakt determinizmu Etapu 4).
func reset_active() -> void:
	_active = 0
