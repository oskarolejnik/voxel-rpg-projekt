class_name DungeonRun
extends Node3D
## DungeonRun.gd — INSTANCJA (efemeryczna) proceduralnego dungeonu (ETAP 5, GDD 8 / TDD 7.3).
##
## Osobna przestrzen voxelowa (pokoje + korytarze) zbudowana z DungeonGen z `entrance_seed`.
## Geometria pokoi/korytarzy budowana W WATKU (WorkerThreadPool — jak streaming swiata, BEZ
## zacinania glownego watku); finalize (add_child + create_trimesh_shape kolizji) na glownym.
##
## Zawartosc (reuse Etapow 0-4):
##  - spawn wrogow per pokoj (EnemyDB + tier dungeonu/biomu; skala ilvl lootu glebia),
##  - BOSS = mocny wariant Enemy (HP/dmg podbite, threat_tier boss),
##  - LOOT przez LootService (drop z wrogow -> loot_dropped -> Main spawnuje LootDrop DO POSTACI),
##  - ZAMEK-KLUCZ: pickup klucza w key_room; drzwi do BOSS otwieraja sie po zebraniu klucza.
##
## Instancja EFEMERYCZNA: po pokonaniu bossa / wyjsciu -> Main niszczy DungeonRun, gracz wraca do
## swiata na zapamietana pozycje. Loot/postep zostaja NA POSTACI (SaveManager — zapis hybrydowy).
##
## Determinizm (Etap 7): host generuje entrance_seed, klienci buduja TEN SAM uklad lokalnie
## (build_layout to czysta funkcja DungeonGen). Spawn wrogow uzywa LOKALNEGO RNG(seed,room) =>
## ten sam seed -> ci sami wrogowie w tych samych pokojach (gotowe pod wspoldzielona instancje party).

signal boss_defeated()                 ## emitowany gdy boss runu zginie (Main -> powrot do swiata)
signal key_collected()                 ## gracz zebral klucz (drzwi bossa sie otwieraja)
signal build_finished()                ## geometria gotowa (wszystkie pokoje/korytarze w drzewie)
signal loot_dropped(world_pos: Vector3, drops: Array)  ## przekaz dropu wroga do Main (LootDrop)
signal enemy_died(e: Node)             ## wrog runu zginal (Main: XP/licznik)

const EnemyScript := preload("res://src/Enemy.gd")

# Salty lokalnego RNG zawartosci (rozlaczne "rzuty": ile wrogow / ktory / gdzie).
const SALT_ROOM_COUNT: int = 0x5101
const SALT_ROOM_PICK: int = 0x5202
const SALT_ROOM_POS: int = 0x5303

## ODSEPAROWANIE PRZESTRZENNE INSTANCJI OD SWIATA (review #BLOCKER): cala instancja dungeonu
## zyje w DALEKIM rejonie, ktorego strumieniowany teren swiata NIGDY nie dotyka. Teren swiata ma
## surface_y max ~44 m i kill plane y=-8 m, wiec offset y=4000 m gwarantuje, ze kolizyjne chunki
## terenu (StaticBody3D warstwa 1) nie przecinaja podlog/scian pokoi (te tez sa na warstwie 1).
## XZ przesuniecie dodatkowo odsuwa od regionu spawnu swiata (chunk 0,0). Geometria pokoi/korytarzy
## ORAZ drzwi/klucz uzywaja LOKALNEGO node.position (dziedzicza offset rodzica), a position CALEGO
## DungeonRun = DUNGEON_ORIGIN => global_position dzieci = origin + local. Jedynie pozycje ustawiane
## przez global_position (wrogowie/boss po add_child) ORAZ entrance_point (czytany przez Main jako
## globalny) dostaja offset jawnie przez _world_point()/DUNGEON_ORIGIN. Determinizm ukladu NIE zalezy
## od offsetu (DungeonGen liczy lokalnie), wiec offset jest czysto przestrzenny — testy ukladu bez zmian.
const DUNGEON_ORIGIN: Vector3 = Vector3(0.0, 4000.0, 100000.0)

## Wejscie/wyjscie gracza: srodek pokoju ENTRANCE (GLOBALNE metry = DUNGEON_ORIGIN + local).
## Main stawia tu gracza po wejsciu (global_position).
var entrance_point: Vector3 = Vector3.ZERO

var _seed: int = 0
var _tier: int = 1
var _biome: StringName = &"verdant"
var _layout: Dictionary = {}
var _player: Node3D = null

# Material wspoldzielony pokoi/korytarzy (vertex-color albedo — jak teren). Jeden na cały run.
var _mat: Material = null

# Stan zamka-klucza.
var _has_key: bool = false
var _boss_door: StaticBody3D = null      # blokada wejscia do pokoju bossa (znika po kluczu)
var _boss_door_mi: MeshInstance3D = null

# Boss + licznik wrogow runu.
var _boss: Node = null
var _boss_dead: bool = false
var _enemies_alive: int = 0

# Watkowe budowanie geometrii (reuse WorkerThreadPool jak VoxelWorld). coord -> {node, task, kind}.
var _pending_builds: Array = []          # Array[Dictionary]: { node:Node3D, task:int, mesh:ArrayMesh, collide:bool }
var _build_done: bool = false
var _spawned_content: bool = false


## Konfiguruje run PRZED add_child. seed = entrance_seed (deterministyczny uklad), tier = tier
## dungeonu (skaluje liczbe pokoi, ilvl/rzadkosc lootu, sile bossa). biome = biom wejscia (dobor
## wrogow + temat lootu). player = encja gracza (cel wrogow, srodek ladowania).
func setup(p_seed: int, p_tier: int, p_biome: StringName, player: Node3D) -> void:
	_seed = p_seed
	_tier = maxi(1, p_tier)
	_biome = p_biome if p_biome != &"" else &"verdant"
	_player = player


func _ready() -> void:
	# Instancja zyje w dalekim rejonie (offset) — z dala od strumieniowanego terenu swiata.
	# Geometria pokoi/korytarzy budowana jest LOKALNIE; ten position przenosi calosc na offset.
	position = DUNGEON_ORIGIN
	# Layout liczony deterministycznie z seeda (czysta funkcja — zero kosztu watku).
	_layout = DungeonGen.generate(_seed, _tier)
	_mat = _make_material()
	# Punkt wejscia = srodek pokoju ENTRANCE w GLOBALNYCH metrach (offset + local). Gracz tam laduje,
	# tam wraca przy wyjsciu (Main ustawia _player.global_position = entrance_point).
	var ent := DungeonGen._room_by_id(_layout["rooms"], int(_layout["entrance_id"]))
	if not ent.is_empty():
		entrance_point = DUNGEON_ORIGIN + (ent["center"] as Vector3) + Vector3(
			float(DungeonGen.ROOM_W) * DungeonGen.VOXEL_SIZE * 0.5, 1.0,
			float(DungeonGen.ROOM_D) * DungeonGen.VOXEL_SIZE * 0.5)
	# Zacznij budowac geometrie w watku (pokoje + korytarze). Spawn zawartosci PO finalize.
	_start_build()


## Wspoldzielony material pokoi: prosty vertex-color albedo (kolory voxeli z DungeonGen).
## NIE uzywamy terrain.gdshader (zalezy od mgly/biomu swiata) — wlasny StandardMaterial3D,
## by instancja byla samodzielna i czytelna w headless/teach.
func _make_material() -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.metallic = 0.0
	return m


# ============================================================================
#  BUDOWA GEOMETRII (watkowa — reuse WorkerThreadPool jak VoxelWorld streaming)
# ============================================================================

## Submituje budowanie mesha kazdego pokoju + korytarza do WorkerThreadPool. Mesh (ArrayMesh)
## liczony OFF-THREAD (SurfaceTool jest lokalny per task — thread-safe, jak Chunk.build_data),
## kolizja (create_trimesh_shape) DOPIERO w finalize na glownym watku (godot#69076).
func _start_build() -> void:
	var rooms: Array = _layout["rooms"]
	# 1) Pokoje: kazdy jako StaticBody3D z wlasnym meshem (otwory na drzwi wg sasiadow w grafie).
	for r in rooms:
		var node := StaticBody3D.new()
		node.name = "Room_%d" % int(r["id"])
		node.collision_layer = 1            # warstwa terenu (gracz/wrog koliduja jak ze swiatem)
		node.collision_mask = 0
		node.position = r["center"]
		var door_dirs := _door_mask_for_room(int(r["id"]))
		var rtype := int(r["type"])
		var task := WorkerThreadPool.add_task(
			_build_room_task.bind(node, rtype, door_dirs),
			false, "dungeon_room_%d" % int(r["id"]))
		_pending_builds.append({ "node": node, "task": task, "collide": true })

	# 2) Korytarze: jeden mesh per krawedz grafu (laczy srodki pokoi). Bezkolizyjne sciany,
	#    ale podloga korytarza MA kolizje (gracz po niej chodzi) -> traktujemy jak pokoj (collide).
	for e in _layout["edges"]:
		var a := DungeonGen._room_by_id(rooms, (e as Vector2i).x)
		var b := DungeonGen._room_by_id(rooms, (e as Vector2i).y)
		if a.is_empty() or b.is_empty():
			continue
		var ac := _room_floor_center(a)
		var bc := _room_floor_center(b)
		var node := StaticBody3D.new()
		node.name = "Corridor_%d_%d" % [(e as Vector2i).x, (e as Vector2i).y]
		node.collision_layer = 1
		node.collision_mask = 0
		var task := WorkerThreadPool.add_task(
			_build_corridor_task.bind(node, ac, bc),
			false, "dungeon_corr_%d_%d" % [(e as Vector2i).x, (e as Vector2i).y])
		_pending_builds.append({ "node": node, "task": task, "collide": true })


## OFF-THREAD: liczy mesh pokoju i zapisuje go na wezel (pole _pending_mesh). Czysta arytmetyka +
## lokalny SurfaceTool (DungeonGen.build_room_mesh). NIE dotyka drzewa sceny.
func _build_room_task(node: StaticBody3D, room_type: int, door_dirs: int) -> void:
	node.set_meta("_mesh", DungeonGen.build_room_mesh(room_type, door_dirs))


func _build_corridor_task(node: StaticBody3D, a_center: Vector3, b_center: Vector3) -> void:
	# Korytarz liczony w przestrzeni LOKALNEJ wezla (origin = a_center). build_corridor_mesh
	# przyjmuje pozycje SWIATOWE — przesuwamy o -a_center i ustawiamy node.position = a_center.
	node.position = a_center
	node.set_meta("_mesh", DungeonGen.build_corridor_mesh(Vector3.ZERO, b_center - a_center))


func _process(_delta: float) -> void:
	if not _build_done:
		_poll_builds()


## Odbiera ukonczone taski (nieblokujaco), finalizuje na glownym watku (add_child + mesh + kolizja).
func _poll_builds() -> void:
	var still: Array = []
	for entry in _pending_builds:
		var task: int = entry["task"]
		if not WorkerThreadPool.is_task_completed(task):
			still.append(entry)
			continue
		WorkerThreadPool.wait_for_task_completion(task)   # ukonczony => natychmiast, zwalnia uchwyt
		var node: StaticBody3D = entry["node"]
		var mesh: ArrayMesh = node.get_meta("_mesh", null)
		if mesh != null and mesh.get_surface_count() > 0:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = _mat
			node.add_child(mi)
			add_child(node)
			# Kolizja: trimesh ze stalej geometrii — na glownym watku (godot#69076), jak Chunk.finalize.
			if bool(entry.get("collide", false)):
				var shape := mesh.create_trimesh_shape()
				if shape != null:
					var col := CollisionShape3D.new()
					col.shape = shape
					node.add_child(col)
		else:
			node.free()
	_pending_builds = still
	if _pending_builds.is_empty():
		_build_done = true
		_on_build_finished()


## Geometria gotowa: spawn zawartosci (drzwi bossa, klucz, wrogowie, boss) RAZ.
func _on_build_finished() -> void:
	if _spawned_content:
		return
	_spawned_content = true
	_spawn_boss_door()
	_spawn_enemies()
	build_finished.emit()


# ============================================================================
#  ZAMEK-KLUCZ + DRZWI BOSSA
# ============================================================================

## Stawia fizyczna blokade (sciana) w otworze prowadzacym do pokoju BOSS oraz pickup KLUCZA w
## pokoju klucza (key_room_id). Po zebraniu klucza blokada znika (drzwi sie otwieraja).
func _spawn_boss_door() -> void:
	var rooms: Array = _layout["rooms"]
	var boss := DungeonGen._room_by_id(rooms, int(_layout["boss_id"]))
	if boss.is_empty():
		return
	# Blokada: cienka sciana w srodku pokoju bossa, od strony wejscia (–X, czyli mniejsza glebia).
	var bc := _room_floor_center(boss)
	var door := StaticBody3D.new()
	door.name = "BossDoor"
	door.collision_layer = 1
	door.collision_mask = 0
	door.position = bc + Vector3(-float(DungeonGen.ROOM_W) * DungeonGen.VOXEL_SIZE * 0.5, 0.0, 0.0)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, float(DungeonGen.ROOM_H) * DungeonGen.VOXEL_SIZE,
		float(DungeonGen.CORRIDOR_W) * DungeonGen.VOXEL_SIZE)
	mi.mesh = bm
	mi.position = Vector3(0.0, bm.size.y * 0.5, 0.0)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = DungeonGen.COL_DOOR_LOCKED
	dm.emission_enabled = true
	dm.emission = DungeonGen.COL_DOOR_LOCKED
	dm.emission_energy_multiplier = 0.6
	mi.material_override = dm
	door.add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bm.size
	cs.shape = box
	cs.position = Vector3(0.0, bm.size.y * 0.5, 0.0)
	door.add_child(cs)
	add_child(door)
	_boss_door = door
	_boss_door_mi = mi

	# Pickup klucza w pokoju klucza (key_room_id). Area3D na warstwie interactable; gracz wchodzi -> klucz.
	var key_room := DungeonGen._room_by_id(rooms, int(_layout["key_room_id"]))
	if not key_room.is_empty():
		_spawn_key_pickup(_room_floor_center(key_room))


## Pickup KLUCZA: swiecaca kostka + Area3D wykrywajaca cialo gracza (warstwa 2). Po wejsciu ->
## collect_key (drzwi bossa znikaja). Deterministyczna pozycja (srodek pokoju klucza).
func _spawn_key_pickup(pos: Vector3) -> void:
	var area := Area3D.new()
	area.name = "KeyPickup"
	area.collision_layer = 0
	area.collision_mask = (1 << 1)        # cialo gracza (warstwa 2, bit1)
	area.position = pos + Vector3(0.0, 0.6, 0.0)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.35, 0.35, 0.12)
	mi.mesh = bm
	var km := StandardMaterial3D.new()
	km.albedo_color = DungeonGen.COL_DOOR_LOCKED
	km.emission_enabled = true
	km.emission = DungeonGen.COL_DOOR_LOCKED
	km.emission_energy_multiplier = 1.4
	mi.material_override = km
	area.add_child(mi)
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.0
	cs.shape = sph
	area.add_child(cs)
	area.body_entered.connect(func(b: Node) -> void:
		if b != null and (b.is_in_group("player") or b == _player):
			collect_key()
			area.queue_free())
	add_child(area)


## Zbiera klucz: otwiera drzwi bossa (usuwa blokade). Idempotentne. Wolane przez pickup LUB recznie
## (test). Emituje key_collected (Main: toast/HUD opcjonalnie).
func collect_key() -> void:
	if _has_key:
		return
	_has_key = true
	if _boss_door != null and is_instance_valid(_boss_door):
		_boss_door.queue_free()
	_boss_door = null
	key_collected.emit()


## Czy klucz zebrany (drzwi otwarte). Test/Main czytaja stan zamka.
func has_key() -> bool:
	return _has_key


# ============================================================================
#  SPAWN WROGOW + BOSS (reuse EnemyDB / Enemy / LootService — jak WorldSpawner)
# ============================================================================

## Spawnuje wrogow w pokojach walki/miniboss oraz BOSSA w pokoju bossa. Deterministyczne:
## LOKALNY RNG(seed, room_id) -> ta sama zawartosc dla tego samego seeda (kontrakt party Etap 7).
## ilvl lootu rosnie z glebia pokoju i tierem (model CW: glebiej = mocniej).
func _spawn_enemies() -> void:
	var rooms: Array = _layout["rooms"]
	var biome_res: BiomeResource = EnemyDB.biome(_biome) if EnemyDB != null else null
	var table: Array = biome_res.enemy_spawn_table if biome_res != null else []
	for r in rooms:
		var rtype := int(r["type"])
		if rtype == RoomType_BOSS():
			_spawn_boss(r)
			continue
		if rtype != RoomType_COMBAT() and rtype != RoomType_MINIBOSS():
			continue
		_spawn_room_enemies(r, table)


## Spawn wrogow walki w jednym pokoju. Liczba/typy z LOKALNEGO RNG (deterministyczne); miniboss
## dostaje jednego mocniejszego (elite). ilvl wg glebi+tieru.
func _spawn_room_enemies(room: Dictionary, table: Array) -> void:
	if table.is_empty():
		return
	var room_id := int(room["id"])
	var depth := int(room["depth"])
	var rtype := int(room["type"])
	var rng := RandomNumberGenerator.new()
	rng.seed = _content_seed(room_id, SALT_ROOM_COUNT)
	# Miniboss: 1 elite. Combat: 1..(2+tier) trash/mix.
	var count := 1 if rtype == RoomType_MINIBOSS() else rng.randi_range(1, 2 + _tier)
	var center := _room_floor_center(room)
	var ilvl := maxi(1, depth + _tier * 2)
	for i in count:
		var enemy_id := _pick_enemy(rng, table, rtype == RoomType_MINIBOSS())
		if enemy_id == &"":
			continue
		var off := _enemy_offset(room_id, i)
		var pos := center + off
		_spawn_one_enemy(enemy_id, pos, ilvl, false)


## BOSS: mocny wariant Enemy (HP/dmg podbite, threat_tier boss). Stoi w srodku pokoju bossa. Jego
## smierc -> boss_defeated (Main: powrot do swiata). Loot bossa = wyzszy ilvl (gwarant lepszej nagrody).
func _spawn_boss(room: Dictionary) -> void:
	var biome_res: BiomeResource = EnemyDB.biome(_biome) if EnemyDB != null else null
	var table: Array = biome_res.enemy_spawn_table if biome_res != null else []
	# Baza bossa: najciezszy wrog z tabeli biomu (elite/boss), wzmocniony skalą bossa.
	var base_id := _pick_boss_base(table)
	var center := _room_floor_center(room)
	var ilvl := maxi(1, int(room["depth"]) + _tier * 3)
	# Offset pionowy jak u zwyklych wrogow (review #minor): kapsula bossa wstaje nad podloga (y=0),
	# nie wbija sie polowa w trimesh przy spawnie. Boss to kluczowy moment — czysto nad podloga.
	_boss = _spawn_one_enemy(base_id, center + Vector3(0.0, 0.5, 0.0), ilvl, true)


## Tworzy i konfiguruje jedna encje Enemy. is_boss podbija staty (boss = "mocny wariant Enemy",
## GDD 8). loot_ilvl wg pokoju (glebia+tier). Cel = gracz. Sygnaly: smierc/loot -> przekaz Main.
func _spawn_one_enemy(enemy_id: StringName, pos: Vector3, ilvl: int, is_boss: bool) -> Node:
	var res: EnemyResource = EnemyDB.enemy(enemy_id) if EnemyDB != null else null
	var e := EnemyScript.new()
	e.configure_from_resource(res)
	if is_boss:
		# Wzmocnienie bossa: skala HP/dmg z tierem (czytelna walka koncowa). Reuse istniejacych pol.
		e.max_hp = e.max_hp * (3.0 + float(_tier))
		e.hp = e.max_hp
		e.attack_damage = e.attack_damage * (1.5 + 0.25 * float(_tier))
		e.body_scale = maxf(e.body_scale, 1.0) * 1.6
		e.threat_tier = &"boss"
		e.armor = clampf(e.armor + 0.15, 0.0, 0.9)
	# Loot: ilvl rosnie z glebia/tierem; biom dungeonu filtruje afiksy; tier_bonus przesuwa rzadkosc.
	e.loot_ilvl = ilvl
	e.loot_biome = _biome
	e.loot_tier_bonus = maxi(0, _tier - 1) + (2 if is_boss else 0)
	# pos jest LOKALNE (z _room_floor_center, ktore liczy wzgledem origin DungeonRun). Instancja stoi
	# na DUNGEON_ORIGIN, wiec globalna pozycja wroga = origin + local. Ustawiamy global po add_child.
	e.position = pos
	add_child(e)
	e.global_position = _world_point(pos)
	if _player != null and is_instance_valid(_player):
		e.set_target(_player)
	e.died.connect(_on_enemy_died)
	e.loot_dropped.connect(func(wp: Vector3, drops: Array) -> void: loot_dropped.emit(wp, drops))
	if is_boss:
		e.died.connect(_on_boss_died)
	_enemies_alive += 1
	return e


func _on_enemy_died(e) -> void:
	_enemies_alive = maxi(0, _enemies_alive - 1)
	enemy_died.emit(e)


func _on_boss_died(_e) -> void:
	if _boss_dead:
		return
	_boss_dead = true
	boss_defeated.emit()


## Czy boss runu pokonany (Main: powrot do swiata).
func is_boss_dead() -> bool:
	return _boss_dead


## Czy geometria gotowa (wszystkie pokoje/korytarze w drzewie + zawartosc zespawnowana). Test/Main
## moga odpytac stan zamiast czekac na sygnal build_finished (uniknicie wyscigu connect-po-add_child).
func is_build_done() -> bool:
	return _build_done and _spawned_content


func enemies_alive() -> int:
	return _enemies_alive


func layout() -> Dictionary:
	return _layout


# ============================================================================
#  POMOCNIKI
# ============================================================================

## Maska kierunkow drzwi pokoju (bity 0=+X,1=-X,2=+Z,3=-Z) wyliczona z SASIADOW w grafie:
## dla kazdej krawedzi z udzialem tego pokoju ustawiamy bit ku sasiadowi (kierunek z roznicy gridu).
func _door_mask_for_room(room_id: int) -> int:
	var rooms: Array = _layout["rooms"]
	var me := DungeonGen._room_by_id(rooms, room_id)
	if me.is_empty():
		return 0
	var my_grid: Vector2i = me["grid"]
	var mask := 0
	for e in _layout["edges"]:
		var ev := e as Vector2i
		var other_id := -1
		if ev.x == room_id:
			other_id = ev.y
		elif ev.y == room_id:
			other_id = ev.x
		else:
			continue
		var other := DungeonGen._room_by_id(rooms, other_id)
		if other.is_empty():
			continue
		var og: Vector2i = other["grid"]
		var dx := og.x - my_grid.x
		var dz := og.y - my_grid.y
		if dx > 0: mask |= 1          # +X
		elif dx < 0: mask |= 2        # -X
		if dz > 0: mask |= 4          # +Z
		elif dz < 0: mask |= 8        # -Z
	return mask


## Srodek PODLOGI pokoju w metrach LOKALNYCH (wzgledem origin DungeonRun = DUNGEON_ORIGIN).
## origin pokoju = rog; srodek = +pol-szerokosci w XZ, y=0. Uzywany jako node.position (local)
## dla korytarzy/drzwi/klucza ORAZ jako baza pozycji wrogow (te konwertowane na global _world_point).
func _room_floor_center(room: Dictionary) -> Vector3:
	return (room["center"] as Vector3) + Vector3(
		float(DungeonGen.ROOM_W) * DungeonGen.VOXEL_SIZE * 0.5, 0.0,
		float(DungeonGen.ROOM_D) * DungeonGen.VOXEL_SIZE * 0.5)


## Konwersja punktu LOKALNEGO instancji na GLOBALNY (offset rejonu dungeonu). Uzywane gdy ustawiamy
## global_position dziecka (Enemy) po add_child — local node.position juz dziedziczy offset rodzica.
func _world_point(local: Vector3) -> Vector3:
	return DUNGEON_ORIGIN + local


## Deterministyczny seed zawartosci pokoju (z entrance_seed + tier + room_id + salt).
func _content_seed(room_id: int, salt: int) -> int:
	var h := _seed
	h = (h * 73856093) ^ (room_id * 19349663)
	h = (h * 83492791) ^ ((_tier ^ salt) * 50331653)
	h ^= (h >> 13)
	h = h * 1274126177
	h ^= (h >> 16)
	return h & 0x7FFFFFFFFFFFFFFF


## Deterministyczny offset pozycji wroga w pokoju (rozrzut wokol srodka, w obrebie pokoju).
func _enemy_offset(room_id: int, i: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = _content_seed(room_id * 97 + i, SALT_ROOM_POS)
	var span := float(DungeonGen.ROOM_W - 4) * DungeonGen.VOXEL_SIZE * 0.5
	return Vector3(rng.randf_range(-span, span), 0.5, rng.randf_range(-span, span))


## Wazony wybor enemy_id z tabeli biomu. prefer_elite=true -> faworyzuj elite/boss threat_tier.
func _pick_enemy(rng: RandomNumberGenerator, table: Array, prefer_elite: bool) -> StringName:
	if table.is_empty():
		return &""
	if prefer_elite:
		# Wybierz pierwszego elite/bossa z tabeli (deterministycznie); fallback do wazonego.
		for e in table:
			var eid := StringName((e as Dictionary).get("enemy_id", &""))
			var res: EnemyResource = EnemyDB.enemy(eid) if EnemyDB != null else null
			if res != null and (res.threat_tier == &"elite" or res.threat_tier == &"boss"):
				return eid
	var total := 0.0
	for e in table:
		total += maxf(0.0, float((e as Dictionary).get("weight", 1.0)))
	if total <= 0.0:
		return StringName((table[0] as Dictionary).get("enemy_id", &""))
	var r := rng.randf() * total
	var acc := 0.0
	for e in table:
		acc += maxf(0.0, float((e as Dictionary).get("weight", 1.0)))
		if r < acc:
			return StringName((e as Dictionary).get("enemy_id", &""))
	return StringName((table[table.size() - 1] as Dictionary).get("enemy_id", &""))


## Baza bossa: najciezszy (elite/boss) wrog z tabeli biomu; fallback do pierwszego/goblina.
func _pick_boss_base(table: Array) -> StringName:
	var best := &"goblin"
	var best_hp := -1.0
	for e in table:
		var eid := StringName((e as Dictionary).get("enemy_id", &""))
		var res: EnemyResource = EnemyDB.enemy(eid) if EnemyDB != null else null
		if res == null or res.stats == null:
			continue
		if res.stats.max_hp > best_hp:
			best_hp = res.stats.max_hp
			best = eid
	return best


# Pomocnicze stale enum (DungeonGen.RoomType) jako funkcje — unikaja "Could not resolve class"
# przy odwolaniu do enuma innej klasy z class_name w niektorych sciezkach parsera 4.7.
func RoomType_COMBAT() -> int: return DungeonGen.RoomType.COMBAT
func RoomType_MINIBOSS() -> int: return DungeonGen.RoomType.MINIBOSS
func RoomType_BOSS() -> int: return DungeonGen.RoomType.BOSS
