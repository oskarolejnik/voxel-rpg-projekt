extends Node
## Etap5Test.gd — mini-test HEADLESS Etapu 5 (DoD: dungeony instancjonowane).
## Uruchomienie: godot --headless res://test/Etap5Test.tscn
##
## _ready() jest KORUTYNĄ (await) — testy geometrii/instancji czekają na watkowe budowanie
## (WorkerThreadPool) i klatki sceny. await zawiesza _ready() do końca testu, więc _failures jest
## KOMPLETNE przed quit() (wzorzec z Etap4Test).
##
## Sprawdza DoD Etapu 5 (ROADMAP 5 / GDD 8 / TDD 7.2-7.3):
##  (1) DungeonGen DETERMINISTYCZNY: ten sam entrance_seed -> ten sam układ (liczba/typy pokoi,
##      pozycja bossa, pokój klucza). Inny seed -> (zwykle) inny układ.
##  (2) Graf SPÓJNY od wejścia: każdy pokój (w tym BOSS) osiągalny od ENTRANCE (BFS).
##  (3) ZAMEK-KLUCZ: pokój klucza istnieje, ma depth < depth(boss) i jest osiągalny PRZED bossem.
##  (4) Pokój BOSS istnieje, jest dokładnie jeden, ma zablokowane wejście (is_locked).
##  (5) DungeonEntrance DETERMINISTYCZNY: ten sam chunk -> ten sam entrance_seed; różne chunki różny.
##      chunk_has_entrance deterministyczny (ten sam wynik dla tego samego chunka).
##  (6) Loot tier rośnie z głębią/tierem dungeonu (model CW: głębiej = mocniej).
##  (7) Skalowanie tierem: wyższy tier -> >= pokoi walki (więcej zawartości).
##  (8) GEOMETRIA: build_room_mesh daje niepusty ArrayMesh; otwory na drzwi redukują liczbę ścian.
##  (9) INSTANCJA (DungeonRun): buduje się w watku (build_finished), pokój wejścia osiągalny,
##      zamek-klucz działa (collect_key otwiera drzwi bossa), boss istnieje.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[E5] ..." + ALL OK + quit.

const EPS: float = 0.0001

var _failures: int = 0
var _world: VoxelWorld = null


func _ready() -> void:
	print("[E5] === Etap 5 mini-test start ===")
	_world = VoxelWorld.new()
	add_child(_world)
	if EnemyDB != null:
		EnemyDB.reload()

	_test_layout_deterministic()
	_test_graph_connected()
	_test_lock_key_before_boss()
	_test_boss_room()
	_test_entrance_deterministic()
	_test_loot_tier_by_depth()
	_test_tier_scaling()
	_test_room_geometry()
	await _test_dungeon_run_instance()
	await _test_world_dungeon_transition()
	await _test_dungeon_floor_physics()

	# Settle: pozwol deferred queue_free (DungeonRun/MeshInstance3D) dokonczyc sie PRZED quit(),
	# inaczej silnik raportuje przeciek RID dummy-mesha (artefakt headless: free nie zdazyl pod quit).
	for _f in 8:
		await get_tree().process_frame

	if _failures == 0:
		print("[E5] ALL OK")
	else:
		printerr("[E5] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[E5] FAIL: %s" % msg)


# ---------------------------------------------------------------------------
#  (1) DungeonGen deterministyczny — ten sam seed ten sam układ
# ---------------------------------------------------------------------------
func _test_layout_deterministic() -> void:
	var seeds := [12345, 0xABCDEF, 777, 999999]
	for s in seeds:
		var a := DungeonGen.generate(s, 2)
		var b := DungeonGen.generate(s, 2)
		_check(_layout_signature(a) == _layout_signature(b),
			"DungeonGen niedeterministyczny dla seed %d:\n  %s\n  %s" % [s, _layout_signature(a), _layout_signature(b)])
		# Pozycja bossa identyczna.
		var ba := DungeonGen._room_by_id(a["rooms"], int(a["boss_id"]))
		var bb := DungeonGen._room_by_id(b["rooms"], int(b["boss_id"]))
		_check((ba["center"] as Vector3).is_equal_approx(bb["center"] as Vector3),
			"pozycja bossa niedeterministyczna dla seed %d" % s)
		# Pokój klucza identyczny.
		_check(int(a["key_room_id"]) == int(b["key_room_id"]),
			"pokój klucza niedeterministyczny dla seed %d" % s)
	# Inny seed -> (zwykle) inny układ. Sprawdzamy że NIE wszystkie są identyczne.
	var sig0 := _layout_signature(DungeonGen.generate(1, 2))
	var diff := false
	for s in [2, 3, 4, 5, 6, 7, 8]:
		if _layout_signature(DungeonGen.generate(s, 2)) != sig0:
			diff = true
			break
	_check(diff, "różne seedy dają TEN SAM układ (brak różnorodności)")
	# Invariant RÓŻNORODNOŚCI pilnowany, nie tylko deklarowany (review #minor): N seedów daje
	# wiele DISTINCT sygnatur. Próg konserwatywny — sekwencja typów jest stała (liniowa ścieżka),
	# różnice to combat_count/odnogi/klucz; >=15 distinct na 100 seedów chroni przed regresją (np.
	# zamrożeniem RNG/odnog), nie wymuszając pełnego BSP.
	var sigs := {}
	for s in range(1000, 1100):
		sigs[_layout_signature(DungeonGen.generate(s, 2))] = true
	_check(sigs.size() >= 15, "za mało różnorodności układów: %d distinct na 100 seedów (próg 15)" % sigs.size())
	# Twardy cap combat_count (review #minor): nawet tier 8 nie przekracza 6 pokoi walki.
	for s in [1, 12345, 0xBEEF, 777]:
		for t in [6, 7, 8]:
			var cc: int = DungeonGen.generate(s, t)["combat_count"]
			_check(cc <= 6, "combat_count > 6 dla tier %d seed %d: %d" % [t, s, cc])
	print("[E5] (1) DungeonGen deterministyczny + różnorodność (%d distinct/100) + cap combat OK" % sigs.size())


## Sygnatura układu do porównań: typy pokoi (po id) + krawędzie + boss/klucz/treasure.
func _layout_signature(layout: Dictionary) -> String:
	var types: Array = []
	for r in layout["rooms"]:
		types.append("%d:%d:%s" % [int(r["id"]), int(r["type"]), str(r["grid"])])
	var edges: Array = []
	for e in layout["edges"]:
		edges.append(str(e))
	return "T[%s] E[%s] B%d K%d Tr%d" % [
		",".join(types), ",".join(edges),
		int(layout["boss_id"]), int(layout["key_room_id"]), int(layout["treasure_id"])]


# ---------------------------------------------------------------------------
#  (2) Graf spójny od wejścia — boss osiągalny
# ---------------------------------------------------------------------------
func _test_graph_connected() -> void:
	for s in [1, 12345, 0xBEEF, 42, 100000]:
		for tier in [1, 2, 3]:
			var layout := DungeonGen.generate(s, tier)
			_check(DungeonGen.is_connected_from_entrance(layout),
				"graf NIESPÓJNY od wejścia (seed %d tier %d)" % [s, tier])
			# Boss konkretnie osiągalny od wejścia.
			_check(DungeonGen.is_reachable(layout, int(layout["entrance_id"]), int(layout["boss_id"])),
				"BOSS nieosiągalny od wejścia (seed %d tier %d)" % [s, tier])
	print("[E5] (2) graf spójny od wejścia (boss osiągalny) OK")


# ---------------------------------------------------------------------------
#  (3) Zamek-klucz — klucz osiągalny PRZED bossem (depth < boss_depth)
# ---------------------------------------------------------------------------
func _test_lock_key_before_boss() -> void:
	for s in [1, 7, 12345, 0xABCDEF, 555, 909090]:
		for tier in [1, 2, 3]:
			var layout := DungeonGen.generate(s, tier)
			var boss := DungeonGen._room_by_id(layout["rooms"], int(layout["boss_id"]))
			var key := DungeonGen._room_by_id(layout["rooms"], int(layout["key_room_id"]))
			_check(not key.is_empty(), "brak pokoju klucza (seed %d tier %d)" % [s, tier])
			if key.is_empty():
				continue
			# DoD: klucz lezy na sciezce osiagalnej PRZED drzwiami bossa.
			_check(int(key["depth"]) < int(boss["depth"]),
				"klucz NIE przed bossem: key depth %d >= boss depth %d (seed %d tier %d)" %
				[int(key["depth"]), int(boss["depth"]), s, tier])
			# Klucz osiągalny od wejścia.
			_check(DungeonGen.is_reachable(layout, int(layout["entrance_id"]), int(key["id"])),
				"klucz nieosiągalny od wejścia (seed %d tier %d)" % [s, tier])
			# Pokój klucza ma flagę has_key.
			_check(bool(key.get("has_key", false)), "pokój klucza bez flagi has_key (seed %d)" % s)
	print("[E5] (3) zamek-klucz: klucz osiągalny PRZED bossem OK")


# ---------------------------------------------------------------------------
#  (4) Pokój BOSS — dokładnie jeden, z zablokowanym wejściem
# ---------------------------------------------------------------------------
func _test_boss_room() -> void:
	for s in [1, 333, 0xCAFE, 88888]:
		var layout := DungeonGen.generate(s, 2)
		var boss_count := 0
		var entrance_count := 0
		for r in layout["rooms"]:
			if int(r["type"]) == DungeonGen.RoomType.BOSS:
				boss_count += 1
				_check(bool(r["is_locked"]), "pokój bossa NIE zablokowany (seed %d)" % s)
			if int(r["type"]) == DungeonGen.RoomType.ENTRANCE:
				entrance_count += 1
		_check(boss_count == 1, "liczba pokoi BOSS != 1 (jest %d, seed %d)" % [boss_count, s])
		_check(entrance_count == 1, "liczba pokoi ENTRANCE != 1 (jest %d, seed %d)" % [entrance_count, s])
		# Boss to najgłębszy pokój na ścieżce krytycznej.
		var boss := DungeonGen._room_by_id(layout["rooms"], int(layout["boss_id"]))
		var max_depth := 0
		for r in layout["rooms"]:
			max_depth = maxi(max_depth, int(r["depth"]))
		_check(int(boss["depth"]) == max_depth, "boss nie jest najgłębszym pokojem (seed %d)" % s)
	print("[E5] (4) pokój BOSS (1×, zablokowany, najgłębszy) OK")


# ---------------------------------------------------------------------------
#  (5) DungeonEntrance deterministyczny — ten sam chunk ten sam seed
# ---------------------------------------------------------------------------
func _test_entrance_deterministic() -> void:
	var chunks := [Vector2i(0, 0), Vector2i(12, -7), Vector2i(-99, 42), Vector2i(500, 500)]
	for c in chunks:
		var s1 := DungeonEntrance.entrance_seed(_world, c.x, c.y)
		var s2 := DungeonEntrance.entrance_seed(_world, c.x, c.y)
		_check(s1 == s2, "entrance_seed niedeterministyczny @ %s: %d != %d" % [c, s1, s2])
		var h1 := DungeonEntrance.chunk_has_entrance(_world, c.x, c.y)
		var h2 := DungeonEntrance.chunk_has_entrance(_world, c.x, c.y)
		_check(h1 == h2, "chunk_has_entrance niedeterministyczny @ %s" % c)
	# Różne chunki -> różne seedy (prawie zawsze).
	_check(DungeonEntrance.entrance_seed(_world, 0, 0) != DungeonEntrance.entrance_seed(_world, 1, 0),
		"entrance_seed identyczny dla różnych chunków")
	# Druga instancja świata daje TEN SAM seed (deterministyczny feature_hash z kodu).
	var w2 := VoxelWorld.new()
	add_child(w2)
	for c in chunks:
		_check(DungeonEntrance.entrance_seed(_world, c.x, c.y) == DungeonEntrance.entrance_seed(w2, c.x, c.y),
			"entrance_seed nie powtarzalny między instancjami świata @ %s" % c)
	w2.queue_free()
	# entrance_seed -> deterministyczny układ (spójność warstw): ten sam chunk -> ten sam layout.
	var es := DungeonEntrance.entrance_seed(_world, 7, 7)
	var et := DungeonEntrance.entrance_tier(_world, 7, 7)
	_check(_layout_signature(DungeonGen.generate(es, et)) == _layout_signature(DungeonGen.generate(es, et)),
		"layout z entrance_seed niedeterministyczny")
	_check(et >= 1, "entrance_tier < 1")
	print("[E5] (5) DungeonEntrance deterministyczny (seed/has_entrance/tier) OK")


# ---------------------------------------------------------------------------
#  (6) Loot tier rośnie z głębią/tierem dungeonu (model CW)
# ---------------------------------------------------------------------------
func _test_loot_tier_by_depth() -> void:
	# loot_tier dungeonu = tier; ilvl wrogów rośnie z głębią pokoju (depth + tier*2) — sprawdzamy
	# że głębsze pokoje mają większy depth (a więc większy ilvl w DungeonRun._spawn_room_enemies).
	var layout := DungeonGen.generate(0xABCDEF, 2)
	var entrance := DungeonGen._room_by_id(layout["rooms"], int(layout["entrance_id"]))
	var boss := DungeonGen._room_by_id(layout["rooms"], int(layout["boss_id"]))
	_check(int(boss["depth"]) > int(entrance["depth"]),
		"głębia bossa nie większa od wejścia (loot tier nie rośnie)")
	# loot_tier wyższego tieru dungeonu jest większy (mocniejszy loot głębiej w świecie).
	var lt1: int = DungeonGen.generate(0xABCDEF, 1)["loot_tier"]
	var lt3: int = DungeonGen.generate(0xABCDEF, 3)["loot_tier"]
	_check(lt3 > lt1, "loot_tier dungeonu nie rośnie z tierem (%d <= %d)" % [lt3, lt1])
	# Symulacja ilvl jak w DungeonRun: ilvl = depth + tier*2. Boss głębiej -> wyższy ilvl.
	var ilvl_entrance := int(entrance["depth"]) + 2 * 2
	var ilvl_boss := int(boss["depth"]) + 2 * 2
	_check(ilvl_boss > ilvl_entrance, "ilvl lootu nie rośnie z głębią (%d <= %d)" % [ilvl_boss, ilvl_entrance])
	print("[E5] (6) loot tier rośnie z głębią/tierem (entrance ilvl %d < boss ilvl %d) OK" % [ilvl_entrance, ilvl_boss])


# ---------------------------------------------------------------------------
#  (7) Skalowanie tierem — wyższy tier >= pokoi walki
# ---------------------------------------------------------------------------
func _test_tier_scaling() -> void:
	var seed := 0xBEEF
	var c1: int = DungeonGen.generate(seed, 1)["combat_count"]
	var c3: int = DungeonGen.generate(seed, 3)["combat_count"]
	_check(c3 >= c1, "tier 3 nie ma >= pokoi walki niż tier 1 (%d < %d)" % [c3, c1])
	# Liczba pokoi rośnie (lub równa) z tierem.
	var n1: int = (DungeonGen.generate(seed, 1)["rooms"] as Array).size()
	var n3: int = (DungeonGen.generate(seed, 3)["rooms"] as Array).size()
	_check(n3 >= n1, "tier 3 nie ma >= pokoi niż tier 1 (%d < %d)" % [n3, n1])
	print("[E5] (7) skalowanie tierem (combat %d->%d, pokoje %d->%d) OK" % [c1, c3, n1, n3])


# ---------------------------------------------------------------------------
#  (8) Geometria pokoju — niepusty mesh; drzwi redukują ściany
# ---------------------------------------------------------------------------
func _test_room_geometry() -> void:
	var no_doors := DungeonGen.build_room_mesh(DungeonGen.RoomType.COMBAT, 0)
	_check(no_doors != null and no_doors.get_surface_count() > 0, "build_room_mesh pusty (bez drzwi)")
	var verts_no := _mesh_vertex_count(no_doors)
	_check(verts_no > 0, "mesh pokoju bez wierzchołków")
	# Z otworami na drzwi: mniej ścian (mniej wierzchołków) niż pełne ściany.
	var with_doors := DungeonGen.build_room_mesh(DungeonGen.RoomType.COMBAT, 0xF)  # wszystkie 4 kierunki
	var verts_doors := _mesh_vertex_count(with_doors)
	_check(verts_doors < verts_no, "otwory drzwi NIE redukują geometrii (%d >= %d)" % [verts_doors, verts_no])
	# Boss/skarbiec też budują się (inny kolor podłogi, ta sama topologia).
	var boss_mesh := DungeonGen.build_room_mesh(DungeonGen.RoomType.BOSS, 2)
	_check(boss_mesh != null and boss_mesh.get_surface_count() > 0, "build_room_mesh BOSS pusty")
	# Korytarz buduje się niepusty.
	var corr := DungeonGen.build_corridor_mesh(Vector3.ZERO, Vector3(24, 0, 0))
	_check(corr != null and corr.get_surface_count() > 0, "build_corridor_mesh pusty")
	print("[E5] (8) geometria pokoju/korytarza (drzwi redukują ściany %d<%d) OK" % [verts_doors, verts_no])


func _mesh_vertex_count(m: ArrayMesh) -> int:
	if m == null or m.get_surface_count() == 0:
		return 0
	var arr := m.surface_get_arrays(0)
	if arr.is_empty():
		return 0
	var v = arr[Mesh.ARRAY_VERTEX]
	return v.size() if v != null else 0


# ---------------------------------------------------------------------------
#  (9) Instancja DungeonRun — budowa w watku, zamek-klucz, boss
# ---------------------------------------------------------------------------
func _test_dungeon_run_instance() -> void:
	var seed := DungeonEntrance.entrance_seed(_world, 3, 3)
	var run := DungeonRun.new()
	# Atrapa gracza (cel wrogów, środek ładowania).
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	run.setup(seed, 2, &"verdant", player)
	add_child(run)

	# Czekaj na watkowe zbudowanie geometrii. Odpytujemy is_build_done() (getter) ZAMIAST polegac
	# wylacznie na sygnale build_finished — connect po add_child mogby przegapic emisje w tej samej
	# klatce. Maks ~10 s zabezpieczenie (watki potrzebuja realnego czasu).
	var guard := 0
	while not run.is_build_done() and guard < 1200:
		await get_tree().process_frame
		guard += 1
	_check(run.is_build_done(), "DungeonRun NIE zbudował geometrii w czasie (watek), frames=%d" % guard)

	# entrance_point = GLOBALNY srodek pokoju ENTRANCE (offset DUNGEON_ORIGIN + lokalny srodek +
	# (4,1,4)). Realna asercja (review #minor — wczesniej "X or true" zawsze przechodzilo).
	var layout := run.layout()
	var ent_room := DungeonGen._room_by_id(layout["rooms"], int(layout["entrance_id"]))
	_check(not ent_room.is_empty(), "brak pokoju ENTRANCE w layoucie runu")
	if not ent_room.is_empty():
		var expected := DungeonRun.DUNGEON_ORIGIN + (ent_room["center"] as Vector3) + Vector3(
			float(DungeonGen.ROOM_W) * DungeonGen.VOXEL_SIZE * 0.5, 1.0,
			float(DungeonGen.ROOM_D) * DungeonGen.VOXEL_SIZE * 0.5)
		_check(run.entrance_point.is_equal_approx(expected),
			"entrance_point != srodek pokoju wejscia (%s != %s)" % [run.entrance_point, expected])
	# Instancja zyje w dalekim rejonie (odseparowanie od terenu swiata): entrance_point.y wysoko.
	_check(run.entrance_point.y > 1000.0,
		"entrance_point.y nie w dalekim rejonie dungeonu (%s) — ryzyko kolizji z terenem swiata" % run.entrance_point.y)
	# Layout runu spójny (boss osiągalny).
	_check(DungeonGen.is_connected_from_entrance(layout), "layout runu niespójny")

	# Zamek-klucz: na starcie brak klucza; collect_key otwiera drzwi (idempotentnie).
	_check(not run.has_key(), "run startuje z kluczem (powinien być zamknięty)")
	run.collect_key()
	_check(run.has_key(), "collect_key NIE ustawił klucza (drzwi nie otwarte)")
	run.collect_key()  # idempotencja
	_check(run.has_key(), "collect_key niestabilny po drugim wywołaniu")

	# Boss istnieje w drzewie runu (mocny wariant Enemy). Szukamy po threat_tier=boss.
	var boss_found := false
	for c in run.get_children():
		if c is Enemy and (c as Enemy).threat_tier == &"boss":
			boss_found = true
			break
	_check(boss_found, "BOSS nie został zespawnowany w instancji")

	run.queue_free()
	player.queue_free()
	print("[E5] (9) instancja DungeonRun (budowa watkowa + zamek-klucz + boss) OK")


# ---------------------------------------------------------------------------
# (10) Pełna pętla świat<->dungeon (DungeonManager): wejście zapamiętuje pozycję,
#      wyjście (boss) wraca gracza + GameState.in_dungeon() przełącza się poprawnie.
# ---------------------------------------------------------------------------
func _test_world_dungeon_transition() -> void:
	# Atrapa gracza w "świecie" + spawner (pauzowany w dungeonie).
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	var world_pos := Vector3(50.0, 5.0, -30.0)
	add_child(player)
	player.global_position = world_pos

	var spawner := WorldSpawner.new()
	add_child(spawner)
	spawner.setup(_world, player)

	var mgr := DungeonManager.new()
	add_child(mgr)
	mgr.setup(_world, player, spawner, self)

	_check(not GameState.in_dungeon(), "GameState.in_dungeon() true PRZED wejściem")
	# WEJŚCIE: zapamiętaj pozycję świata, zbuduj run, przenieś gracza.
	var seed := DungeonEntrance.entrance_seed(_world, 5, 5)
	mgr._enter_dungeon(seed, 2, &"verdant")
	_check(GameState.in_dungeon(), "GameState.in_dungeon() false PO wejściu")
	_check(mgr.in_dungeon(), "DungeonManager.in_dungeon() false PO wejściu")
	_check(GameState.world_return_position.is_equal_approx(world_pos),
		"pozycja powrotu nie zapamiętana (%s != %s)" % [GameState.world_return_position, world_pos])
	_check(not spawner.is_processing(), "spawner świata NIE spauzowany w dungeonie")
	# STREAMING świata ZATRZYMANY w dungeonie (review #BLOCKER+#MAJOR): inaczej świat dobudowuje
	# kolizyjne chunki terenu w bryle dungeonu + marnuje wspólną WorkerThreadPool.
	_check(not _world.is_processing(), "VoxelWorld._process NIE spauzowany w dungeonie (streaming gryzie się z instancją)")
	# ODSEPAROWANIE PRZESTRZENNE: gracz teleportowany do DALEKIEGO rejonu (offset DUNGEON_ORIGIN),
	# z dala od terenu świata (surface_y max ~44 m). entrance_point.y wysoko => brak kolizji z terenem.
	_check(player.global_position.y > 1000.0,
		"gracz w dungeonie NIE w dalekim rejonie (y=%s) — ryzyko kolizji z terenem świata" % player.global_position.y)
	# Gracz przeniesiony do pokoju wejścia (nie w pozycji świata).
	_check(not player.global_position.is_equal_approx(world_pos), "gracz NIE przeniesiony do dungeonu")

	# Poczekaj na zbudowanie runu (geometria + boss).
	var run := mgr.current_run()
	_check(run != null, "brak aktywnego runu po wejściu")
	var guard := 0
	while run != null and not run.is_build_done() and guard < 1200:
		await get_tree().process_frame
		guard += 1

	# Spawner świata: licznik aktywnych wyzerowany przy wejściu (review #MAJOR — queue_free wrogów
	# świata nie emituje died, więc DungeonManager musi ręcznie zresetować _active, inaczej spawner
	# po powrocie robi early-return na MAX_ACTIVE i nie spawnuje). active_count == 0 po wejściu.
	_check(spawner.active_count() == 0, "spawner._active nie wyzerowany przy wejściu (%d) — leak licznika" % spawner.active_count())

	# WYJŚCIE: symuluj pokonanie bossa (boss_defeated -> _exit_dungeon).
	mgr._exit_dungeon()
	_check(not GameState.in_dungeon(), "GameState.in_dungeon() true PO wyjściu")
	_check(not mgr.in_dungeon(), "DungeonManager.in_dungeon() true PO wyjściu")
	_check(spawner.is_processing(), "spawner świata NIE wznowiony po wyjściu")
	_check(_world.is_processing(), "VoxelWorld._process NIE wznowiony po wyjściu (świat nie strumieniuje)")
	_check(_world.visible, "świat niewidoczny po powrocie")
	# Gracz z powrotem na zapamiętanej pozycji świata.
	_check(player.global_position.is_equal_approx(world_pos),
		"gracz NIE wrócił na pozycję świata (%s != %s)" % [player.global_position, world_pos])
	# Spawner po powrocie znów może spawnować (licznik 0 => _update_regions nie robi early-return).
	_check(spawner.active_count() == 0, "spawner._active != 0 po wyjściu (%d)" % spawner.active_count())

	mgr.queue_free()
	spawner.queue_free()
	player.queue_free()
	print("[E5] (10) pełna pętla świat<->dungeon (wejście/zapamiętanie/wyjście/powrót + pauza streamingu + licznik spawnera) OK")


# ---------------------------------------------------------------------------
# (11) FIZYKA PODŁOGI DUNGEONU (review #BLOCKER): realny CharacterBody3D (warstwa 2, maska teren)
#      spada na podłogę pokoju i NIE przepada / NIE utyka. Body chodzi przez kilka pokoi po
#      ścieżce krytycznej — Y trzyma się blisko podłogi pokoju (offset DUNGEON_ORIGIN), brak
#      blokady niewidzialnym terenem. Headless ma realny krok fizyki (process_frame -> _physics).
# ---------------------------------------------------------------------------
func _test_dungeon_floor_physics() -> void:
	var run := DungeonRun.new()
	var target := CharacterBody3D.new()      # cel wrogów (nie testowane cialo)
	target.add_to_group("player")
	add_child(target)
	run.setup(DungeonEntrance.entrance_seed(_world, 9, 9), 2, &"verdant", target)
	add_child(run)
	# Czekaj na geometrię (kolizja podłóg gotowa).
	var guard := 0
	while not run.is_build_done() and guard < 1200:
		await get_tree().process_frame
		guard += 1
	_check(run.is_build_done(), "DungeonRun (fizyka) nie zbudowany w czasie")

	# Testowe cialo: warstwa 2 (gracz), maska teren (warstwa 1) — jak Player. Spada grawitacja.
	var body := CharacterBody3D.new()
	body.collision_layer = 1 << 1
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.2
	cs.shape = cap
	cs.position = Vector3(0.0, 0.65, 0.0)     # kapsula nad origin ciała (jak Player)
	body.add_child(cs)
	add_child(body)

	var origin: Vector3 = DungeonRun.DUNGEON_ORIGIN
	var floor_origin_y := origin.y            # podłogi pokoi na y=0 lokalnie => origin.y globalnie
	# Przejdź po ścieżce krytycznej (ENTRANCE -> ... -> najgłębszy przed bossem). Dla każdego pokoju:
	# postaw ciało 2 m nad podłogą, opuść fizyką, sprawdź że osiadło ~na podłodze (nie przepadło,
	# nie zawisło na ukrytym terenie). Pomijamy BOSS (za drzwiami) — chodzimy po dostępnych pokojach.
	var layout := run.layout()
	var rooms: Array = layout["rooms"]
	var checked := 0
	var min_y := 1.0e20
	var max_y := -1.0e20
	for r in rooms:
		if int(r["type"]) == DungeonGen.RoomType.BOSS:
			continue
		# Lokalny środek podłogi -> globalny (offset). Body origin na podłodze => global y ~ floor_origin_y.
		var local_center: Vector3 = (r["center"] as Vector3) + Vector3(
			float(DungeonGen.ROOM_W) * DungeonGen.VOXEL_SIZE * 0.5, 0.0,
			float(DungeonGen.ROOM_D) * DungeonGen.VOXEL_SIZE * 0.5)
		var spawn := origin + local_center + Vector3(0.0, 2.0, 0.0)
		body.global_position = spawn
		body.velocity = Vector3.ZERO
		# Symulacja fizyki: grawitacja + move_and_slide opuszczają ciało na podłogę pokoju.
		for _f in 40:
			body.velocity.y -= 9.8 * (1.0 / 60.0)
			body.move_and_slide()
			if body.is_on_floor():
				body.velocity.y = 0.0
				break
			await get_tree().physics_frame
		# INVARIANT BLOCKERA: ciało osiadło na podłodze pokoju (offset DUNGEON_ORIGIN) i NIE przepadło
		# ani nie zawisło na niewidzialnym terenie. Mierzymy stabilność: po osiadnięciu kolejne klatki
		# NIE zmieniają znacząco Y (gdyby przepadało, Y leciałby w dół; gdyby blokował teren powyżej,
		# Y stałoby wysoko). y-offset od podłogi w wąskim oknie [-0.2, 1.2] (grubość kapsuły) = stoi.
		var y_before := body.global_position.y
		for _f in 6:
			body.velocity.y -= 9.8 * (1.0 / 60.0)
			body.move_and_slide()
			await get_tree().physics_frame
		var y_after := body.global_position.y
		var dy := y_after - floor_origin_y
		_check(absf(y_after - y_before) < 0.05,
			"ciało NIE stabilne na podłodze pokoju id=%d (przepada/ślizga: Δy=%s)" % [int(r["id"]), y_after - y_before])
		_check(dy > -0.2 and dy < 1.2,
			"ciało NIE na podłodze pokoju id=%d: y-offset od podłogi = %s (przepadł lub utknął na terenie)" % [int(r["id"]), dy])
		min_y = minf(min_y, y_after)
		max_y = maxf(max_y, y_after)
		checked += 1
	_check(checked >= 2, "za mało dostępnych pokoi do testu fizyki (%d)" % checked)

	body.queue_free()
	target.queue_free()
	run.queue_free()
	print("[E5] (11) fizyka podłogi dungeonu (%d pokoi, body na podłodze, brak przepadania, y∈[%.1f,%.1f]) OK" % [checked, min_y, max_y])
