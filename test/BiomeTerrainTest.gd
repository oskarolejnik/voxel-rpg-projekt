extends Node
## BiomeTerrainTest.gd — headless test BIOME #8 (biome-aware heightmap) + #9 (4 nowe biomy).
## Uruchomienie: godot --headless res://test/BiomeTerrainTest.tscn
##
## Sprawdza:
##  (a) surface_height ma RÓŻNĄ sylwetkę między pasmem płaskim (plains) a postrzępionym (mountains):
##      ten sam lokalny szum, ale inny profil => inny zakres/rozrzut wysokości (teren NIE jest identyczny).
##  (b) Wszystkie 7 id biomów (BIOME_PROGRESSION) jest osiągalne dystansem od spawnu.
##  (c) Determinizm: ten sam (x,z) -> ta sama wysokość i ten sam biom (dwie instancje świata też zgodne).
##  (d) 4 nowe BiomeResource .tres (plains/swamp/mountains/volcanic) wczytane przez EnemyDB.biome(id),
##      każdy z NIEPUSTĄ tabelą spawnu o znanych enemy_id.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[BT] ...".

var _failures: int = 0
var _world: VoxelWorld = null


func _ready() -> void:
	print("[BT] === Biome terrain test start ===")
	_world = VoxelWorld.new()
	add_child(_world)
	if EnemyDB != null:
		EnemyDB.reload()

	_test_terrain_differs_by_biome()
	_test_all_biomes_reachable()
	_test_determinism()
	_test_new_biome_resources()

	if _failures == 0:
		print("[BT] ALL OK")
	else:
		printerr("[BT] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[BT] FAIL: %s" % msg)


## Znajduje pierwszy punkt na osi +X należący do danego biomu (skan co 32 m do 6 km).
## Zwraca world_x (int) albo -1 gdy nie znaleziono.
func _find_x_for_biome(biome: StringName) -> int:
	for step in range(0, 200):
		var x := step * 32
		if _world.get_biome(x, 0) == biome:
			return x
	return -1


## Statystyka sylwetki terenu wokół punktu (wx,0): [min, max, rozrzut] z siatki próbek.
## Próbkujemy lokalny kwadrat (mały względem szerokości pasma 700 m), więc cały leży w jednym biomie.
func _terrain_stats(wx: int) -> Array:
	var lo := 999
	var hi := -999
	for dx in range(-24, 25, 4):
		for dz in range(-24, 25, 4):
			var h := _world.surface_height(wx + dx, dz)
			lo = mini(lo, h)
			hi = maxi(hi, h)
	return [lo, hi, hi - lo]


# ---------------------------------------------------------------------------
#  (a) Teren różni się sylwetką: plains (płaski) vs mountains (postrzępiony, wyższy)
# ---------------------------------------------------------------------------
func _test_terrain_differs_by_biome() -> void:
	var x_plains := _find_x_for_biome(VoxelWorld.BIOME_PLAINS)
	var x_mtn := _find_x_for_biome(VoxelWorld.BIOME_MOUNTAINS)
	_check(x_plains >= 0, "nie znaleziono pasma plains na osi +X")
	_check(x_mtn >= 0, "nie znaleziono pasma mountains na osi +X")
	if x_plains < 0 or x_mtn < 0:
		return
	var sp := _terrain_stats(x_plains)
	var sm := _terrain_stats(x_mtn)
	# Góry mają WIĘKSZY rozrzut wysokości (postrzępione) niż równiny (płaskie) — sylwetki istotnie różne.
	_check(sm[2] > sp[2] + 4, "rozrzut gór (%d) nie jest istotnie wiekszy od rownin (%d)" % [sm[2], sp[2]])
	# Szczyty gór wybijają wyżej niż maks. równin (inny BASE+AMP profil).
	_check(sm[1] > sp[1], "maks. wysokosc gor (%d) nie wieksza od rownin (%d)" % [sm[1], sp[1]])
	# Twarda asercja "nie identyczne": kolumna w plains vs mountains daje różną wysokość.
	_check(_world.surface_height(x_plains, 0) != _world.surface_height(x_mtn, 0)
		or sp != sm, "teren plains i mountains jest identyczny (profil biomu martwy)")
	print("[BT] (a) sylwetka plains[lo%d hi%d sp%d] != mountains[lo%d hi%d sp%d] OK" % [sp[0], sp[1], sp[2], sm[0], sm[1], sm[2]])


# ---------------------------------------------------------------------------
#  (b) Wszystkie 7 pasm osiągalne dystansem
# ---------------------------------------------------------------------------
func _test_all_biomes_reachable() -> void:
	var seen := {}
	# Skan promienisty co 32 m do 6 km w 16 kierunkach — pokrywa wszystkie pasma + warp granic.
	for ri in range(0, 200):
		var r := ri * 32
		for ai in range(0, 16):
			var ang := TAU * float(ai) / 16.0
			var x := int(round(cos(ang) * r))
			var z := int(round(sin(ang) * r))
			seen[_world.get_biome(x, z)] = true
	for expected in VoxelWorld.BIOME_PROGRESSION:
		_check(seen.has(expected), "biom %s nieosiagalny dystansem" % expected)
	_check(seen.size() == VoxelWorld.BIOME_PROGRESSION.size(),
		"get_biome zwraca id spoza progresji (znaleziono %d, oczekiwano %d)" % [seen.size(), VoxelWorld.BIOME_PROGRESSION.size()])
	print("[BT] (b) wszystkie %d pasm osiagalne OK" % seen.size())


# ---------------------------------------------------------------------------
#  (c) Determinizm: ten sam (x,z) -> ta sama wysokosc i biom; dwie instancje swiata zgodne
# ---------------------------------------------------------------------------
func _test_determinism() -> void:
	var pts := [Vector2i(0, 0), Vector2i(800, -300), Vector2i(-1500, 1200), Vector2i(3000, 0), Vector2i(-2200, -2200)]
	var w2 := VoxelWorld.new()
	add_child(w2)
	for p in pts:
		var h1 := _world.surface_height(p.x, p.y)
		var h2 := _world.surface_height(p.x, p.y)
		_check(h1 == h2, "surface_height niedeterministyczny @ %s: %d != %d" % [p, h1, h2])
		_check(_world.surface_height(p.x, p.y) == w2.surface_height(p.x, p.y),
			"surface_height nie powtarzalny miedzy instancjami @ %s" % p)
		var b1 := _world.get_biome(p.x, p.y)
		_check(b1 == _world.get_biome(p.x, p.y), "get_biome niedeterministyczny @ %s" % p)
		_check(b1 == w2.get_biome(p.x, p.y), "get_biome nie powtarzalny miedzy instancjami @ %s" % p)
		# Wysokosc w prawidlowym zakresie (kontrakt: [1, WORLD_HEIGHT-1]).
		_check(h1 >= 1 and h1 <= VoxelWorld.WORLD_HEIGHT - 1, "surface_height poza zakresem @ %s: %d" % [p, h1])
	w2.queue_free()
	print("[BT] (c) determinizm surface_height + get_biome OK")


# ---------------------------------------------------------------------------
#  (d) 4 nowe BiomeResource .tres wczytane przez EnemyDB.biome, spawn table niepusta
# ---------------------------------------------------------------------------
func _test_new_biome_resources() -> void:
	var new_ids: Array[StringName] = [
		VoxelWorld.BIOME_PLAINS, VoxelWorld.BIOME_SWAMP,
		VoxelWorld.BIOME_MOUNTAINS, VoxelWorld.BIOME_VOLCANIC,
	]
	for id in new_ids:
		var br: BiomeResource = EnemyDB.biome(id)
		_check(br != null, "EnemyDB.biome(%s) == null (nowy .tres nie wczytany)" % id)
		if br == null:
			continue
		_check(br.id == id, "BiomeResource.id %s != %s" % [br.id, id])
		_check(br.loot_tier >= 1, "loot_tier %s < 1" % id)
		_check(not br.enemy_spawn_table.is_empty(), "spawn table pusta dla biomu %s" % id)
		for e in br.enemy_spawn_table:
			var eid := StringName((e as Dictionary).get("enemy_id", &""))
			_check(EnemyDB.enemy(eid) != null, "spawn table %s -> nieznany enemy_id %s" % [id, eid])
	print("[BT] (d) 4 nowe BiomeResource .tres + spawn table OK")
