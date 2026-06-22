class_name DungeonManager
extends Node
## DungeonManager.gd (komponent) — ORKIESTRACJA wejsc + przejscia swiat<->dungeon (ETAP 5).
##
## Spina trzy elementy Etapu 5 w jeden punkt podpiety pod Main (minimalna inwazyjnosc w Main.gd):
##  1) SKANER WEJSC: co interwal sprawdza chunki wokol gracza (DungeonEntrance.chunk_has_entrance —
##     deterministyczne z feature_hash), stawia voxelowy prefab wejscia (DungeonEntrance) raz/chunk.
##  2) WEJSCIE: gdy gracz wcisnie [E] przy wejsciu -> enter_requested -> _enter_dungeon: zapamietaj
##     pozycje gracza w SWIECIE (GameState), wylacz spawner swiata + ukryj swiat, zbuduj DungeonRun
##     (geometria w WATKU), przenies gracza do pokoju ENTRANCE. Loot z runu leci do tych samych
##     slotow Main co loot swiata (LootDrop DO POSTACI).
##  3) WYJSCIE: boss pokonany (DungeonRun.boss_defeated) LUB gracz wroci do pokoju wejscia ->
##     _exit_dungeon: znisz DungeonRun (efemeryczna), wlacz swiat, postaw gracza na zapamietanej
##     pozycji, zapisz hybrydowo (swiat trwaly; postac juz ma loot). GameState.exit_run().
##
## Reuse: WorldSpawner (pauza w dungeonie), EnemyDB/Enemy/LootService (przez DungeonRun), Main sloty
## lootu/XP. Co-op (Etap 7): host wola _enter_dungeon, klienci dostaja (seed,tier) i buduja lokalnie.

const DungeonEntranceScript := preload("res://src/world/DungeonEntrance.gd")
const DungeonRunScript := preload("res://src/world/DungeonRun.gd")

## Co ile sekund skanujemy chunki wokol gracza po wejscia (tani throttling, jak WorldSpawner).
const SCAN_INTERVAL: float = 1.0
## Promien (w chunkach) skanowania wejsc wokol gracza.
const SCAN_RADIUS: int = 2

var _world: VoxelWorld = null
var _player: Node3D = null
var _spawner: WorldSpawner = null
var _main: Node = null                 # wlasciciel (Main) — sloty lootu/XP/HUD

# Callbacki Main (te same co WorldSpawner) — podpiecie lootu/smierci wrogow runu.
var _on_loot: Callable = Callable()
var _on_enemy_died: Callable = Callable()

## Krotki cooldown po wyjsciu z dungeonu — gracz laduje DOKLADNIE na portalu (world_return_position),
## wiec _in_range wejscia jest true; bez cooldownu moglby wpasc z powrotem w tej samej klatce.
const REENTRY_COOLDOWN: float = 0.75

var _scan_left: float = 0.0
var _entrance_chunks: Dictionary = {}  # Vector2i -> DungeonEntrance (postawione, by nie dublowac)
var _run: DungeonRun = null
var _spawner_was_processing: bool = true
var _world_visible: bool = true
var _world_was_processing: bool = true   # czy VoxelWorld strumieniowal przed wejsciem (przywrocenie)
var _reentry_cooldown: float = 0.0       # po wyjsciu: ignoruj enter_requested przez chwile


## Wstrzykuje zaleznosci (Main wola po _spawn_player/_spawn_enemies).
func setup(world: VoxelWorld, player: Node3D, spawner: WorldSpawner, main: Node,
		on_loot: Callable = Callable(), on_enemy_died: Callable = Callable()) -> void:
	_world = world
	_player = player
	_spawner = spawner
	_main = main
	_on_loot = on_loot
	_on_enemy_died = on_enemy_died


func _process(delta: float) -> void:
	# W dungeonie NIE skanujemy wejsc swiata (gracz jest w instancji). Skan tylko w otwartym swiecie.
	if _run != null:
		return
	if _reentry_cooldown > 0.0:
		_reentry_cooldown -= delta
	if _world == null or _player == null or not is_instance_valid(_player):
		return
	_scan_left -= delta
	if _scan_left > 0.0:
		return
	_scan_left = SCAN_INTERVAL
	_scan_entrances()


## Skanuje chunki wokol gracza; dla chunkow z wejsciem (deterministycznie) stawia prefab raz.
func _scan_entrances() -> void:
	var center := _world.world_to_chunk(_player.global_position)
	for dx in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
		for dz in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
			var cx := center.x + dx
			var cz := center.y + dz
			var coord := Vector2i(cx, cz)
			if _entrance_chunks.has(coord):
				continue
			if not DungeonEntranceScript.chunk_has_entrance(_world, cx, cz):
				continue
			_place_entrance(cx, cz)


## Stawia voxelowy prefab wejscia w danym chunku. Pozycja = srodek chunka, na gruncie (height_at).
func _place_entrance(cx: int, cz: int) -> void:
	var span := float(VoxelWorld.CHUNK_SIZE) * VoxelWorld.VOXEL_SIZE
	var wx := (float(cx) + 0.5) * span
	var wz := (float(cz) + 0.5) * span
	var wy := _world.height_at(wx, wz)
	var ent := DungeonEntranceScript.new()
	var seed := DungeonEntranceScript.entrance_seed(_world, cx, cz)
	var tier := DungeonEntranceScript.entrance_tier(_world, cx, cz)
	var biome := DungeonEntranceScript.entrance_biome(_world, cx, cz)
	ent.setup(seed, tier, biome, _player)
	ent.position = Vector3(wx, wy, wz)
	# Rodzic = wlasciciel (Main/swiat), by wejscie zylo niezaleznie od managera.
	var parent := _main if _main != null else self
	parent.add_child(ent)
	ent.global_position = Vector3(wx, wy, wz)
	ent.enter_requested.connect(_on_enter_requested)
	_entrance_chunks[Vector2i(cx, cz)] = ent


## Gracz zazadal wejscia (klawisz E przy wejsciu). HOST-ONLY w co-opie (Etap 7): host buduje,
## RPC seed/tier do klientow. W SP wchodzimy od razu.
func _on_enter_requested(seed: int, tier: int, biome: StringName) -> void:
	if _run != null:
		return                              # juz w dungeonie
	if _reentry_cooldown > 0.0:
		return                              # tuz po wyjsciu — nie wpadaj z powrotem na tym samym portalu
	_enter_dungeon(seed, tier, biome)


## WEJSCIE: zapamietaj pozycje w swiecie, zatrzymaj spawner + ukryj swiat, zbuduj DungeonRun,
## przenies gracza do pokoju wejscia. Publiczne (Main/test moze wywolac wprost).
func _enter_dungeon(seed: int, tier: int, biome: StringName) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# 1) Zapamietaj pozycje powrotu (GameState — zapis hybrydowy: swiat trwaly).
	GameState.enter_run(seed, tier, biome, _player.global_position)

	# 2) Zatrzymaj spawner swiata (wrogowie swiata nie tykaja w dungeonie) + ZATRZYMAJ STREAMING
	#    swiata + ukryj swiat (FPS/czytelnosc/odseparowanie fizyki).
	#    KRYTYCZNE (review #BLOCKER+#MAJOR): VoxelWorld._process musi stanac. Inaczej swiat dalej
	#    strumieniuje kolizyjne chunki terenu wokol pozycji gracza ORAZ marnuje wspoldzielona
	#    WorkerThreadPool, ktorej DungeonRun uzywa do budowy geometrii (wolniejsze wejscie/FPS).
	#    Sam offset DungeonRun (DUNGEON_ORIGIN) odsuwa instancje od terenu, a pauza gwarantuje, ze
	#    swiat nie dobuduje niczego w nowym, dalekim rejonie i odda cala pule budowie dungeonu.
	if _spawner != null and is_instance_valid(_spawner):
		_spawner_was_processing = _spawner.is_processing()
		_spawner.set_process(false)
	if _world != null and is_instance_valid(_world):
		_world_was_processing = _world.is_processing()
		_world.set_process(false)
		_world_visible = _world.visible
		_world.visible = false
	# Usun wrogow SWIATA aktywnych przy wejsciu (nie maja co robic w dungeonie; znikna z instancja).
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()
	# queue_free() NIE emituje Enemy.died -> WorldSpawner._on_enemy_died nie zdejmuje licznika; bez
	# tego _active zostaje zawyzone (do MAX_ACTIVE) i spawner po powrocie robi early-return, nie
	# spawnujac wrogow (regresja progresji Etapu 4). Zerujemy licznik recznie (review #MAJOR).
	if _spawner != null and is_instance_valid(_spawner) and _spawner.has_method("reset_active"):
		_spawner.reset_active()

	# 3) Zbuduj instancje (geometria w WATKU). Loot/smierc wrogow -> sloty Main (DO POSTACI).
	_run = DungeonRunScript.new()
	_run.name = "DungeonRun"
	_run.setup(seed, tier, biome, _player)
	var parent := _main if _main != null else self
	parent.add_child(_run)
	if _on_loot.is_valid():
		_run.loot_dropped.connect(_on_loot)
	if _on_enemy_died.is_valid():
		_run.enemy_died.connect(_on_enemy_died)
	_run.boss_defeated.connect(_on_boss_defeated)
	_run.build_finished.connect(_on_run_built)

	# 4) Przenies gracza do pokoju wejscia (entrance_point gotowy w _ready DungeonRun).
	_teleport_player(_run.entrance_point)


## Geometria runu gotowa — nic dodatkowego (gracz juz na entrance_point). Hook pod fade-in/HUD.
func _on_run_built() -> void:
	pass


## Boss pokonany -> wyjscie (powrot do swiata). Loot/postep juz na postaci.
func _on_boss_defeated() -> void:
	_exit_dungeon()


## WYJSCIE: znisz instancje (efemeryczna), wlacz swiat, postaw gracza na zapamietanej pozycji,
## zapisz hybrydowo. Publiczne (Main/test moze wywolac przy recznym wyjsciu).
func _exit_dungeon() -> void:
	var return_pos := GameState.world_return_position
	# 1) Znisz instancje runu (efemeryczna — nic do zapisania).
	if _run != null and is_instance_valid(_run):
		_run.queue_free()
	_run = null

	# 2) Wlacz swiat (render) + streaming + spawner z powrotem. Streaming PRZED prime()/teleportem,
	#    by VoxelWorld._process znow primowal okolice powrotu (analogicznie do pauzy w _enter_dungeon).
	if _world != null and is_instance_valid(_world):
		_world.visible = _world_visible
		_world.set_process(_world_was_processing)
	if _spawner != null and is_instance_valid(_spawner):
		_spawner.set_process(_spawner_was_processing)

	# 3) Postaw gracza na zapamietanej pozycji w swiecie (prime terenu, by nie spadl).
	if _world != null and is_instance_valid(_world):
		_world.prime(_world.world_to_chunk(return_pos), 1)
	_teleport_player(return_pos)

	# 4) Cooldown re-entry (review #minor): gracz laduje na portalu, _in_range=true; bez tego moglby
	#    natychmiast wejsc z powrotem. Resetujemy tez skan wejsc, by stan byl swiezy po powrocie.
	_reentry_cooldown = REENTRY_COOLDOWN
	_scan_left = SCAN_INTERVAL

	# 5) Zapis hybrydowy: swiat trwaly (host) + postac (loot/postep). Runa NIE jest zapisywana.
	GameState.exit_run()
	if _main != null and _main.has_method("save_after_dungeon"):
		_main.save_after_dungeon()


## Teleport gracza na pozycje (zeruje ped + interpolacje, jak respawn). Bezpieczne na rozne typy.
func _teleport_player(pos: Vector3) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.global_position = pos
	if "velocity" in _player:
		_player.set("velocity", Vector3.ZERO)
	if _player.has_method("reset_physics_interpolation"):
		_player.reset_physics_interpolation()


## Czy aktywna runa (gracz w dungeonie).
func in_dungeon() -> bool:
	return _run != null


## Referencja do aktywnego runu (Main/HUD/diagnostyka).
func current_run() -> DungeonRun:
	return _run
