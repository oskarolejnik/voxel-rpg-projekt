extends Node
## CaveGenTest.gd — headless test JASKINIE (worm-tunnels carve) + RUDY (ore).
## Sprawdza:
##  (a) jaskinie ISTNIEJĄ — kieszenie AIR pod powierzchnią w rozsądnym zakresie gęstości, z pionowym
##      przejściem >=2 voxele (proxy chodliwości),
##  (b) BEDROCK (y<=CAVE_BEDROCK_TOP) nigdy nie wycięty + SKÓRA powierzchni (depth<MIN) nietknięta,
##  (c) DETERMINIZM — dwie instancje świata dają identyczny carve+ore; is_cave/ore_at czyste,
##  (d) WODA — kolumny pod morzem niewydrążone (realny chunk: brak AIR pod taflą),
##  (e) RUDY — w pasmach głębokości z rosnącą rzadkością (copper>iron>gold) + KOLOR rudy NIEZALEŻNY
##      od biomu (early-return w _solid_color pomija biome_modulate),
##  (f) WIRING — realny VoxelChunk faktycznie wycina AIR tam, gdzie is_cave==true, a bedrock zostaje stały.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[CAVE] ...".
## Uruchomienie: godot --headless res://test/CaveGenTest.tscn

var _failures: int = 0
var _world: VoxelWorld = null


func _ready() -> void:
	print("[CAVE] === Cave gen test start ===")
	_world = VoxelWorld.new()
	add_child(_world)

	_test_caves_exist_and_walkable()
	_test_bedrock_and_surface_intact()
	_test_determinism()
	_test_chunk_wiring()
	_test_water_no_carve()
	_test_ore_bands_and_color()

	if _failures == 0:
		print("[CAVE] ALL OK")
	else:
		printerr("[CAVE] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[CAVE] FAIL: %s" % msg)


# (a) Jaskinie istnieją + chodliwe ----------------------------------------------------------------
func _test_caves_exist_and_walkable() -> void:
	var SEA := VoxelWorld.SEA_LEVEL
	var MIND := VoxelWorld.CAVE_MIN_DEPTH
	var BTOP := VoxelWorld.CAVE_BEDROCK_TOP
	var subsurface := 0
	var carved := 0
	var cols := 0
	var has_walkable_run := false
	for wx in range(0, 64):
		for wz in range(0, 64):
			var sy := _world.surface_height(wx, wz)
			if sy <= SEA + 10:
				continue
			cols += 1
			var run := 0
			for wy in range(BTOP + 1, sy - MIND + 1):
				subsurface += 1
				if _world.is_cave(wx, wy, wz, sy):
					carved += 1
					run += 1
					if run >= 2:
						has_walkable_run = true
				else:
					run = 0
	_check(cols > 0, "brak kolumn nad poziomem morza w skanie")
	_check(subsurface > 0, "puste pasmo podpowierzchniowe")
	var frac := float(carved) / float(maxi(1, subsurface))
	_check(frac > 0.01, "jaskinie nie powstają (carved=%.3f%% — martwy generator)" % (frac * 100.0))
	_check(frac < 0.6, "świat nadmiernie wydrążony (carved=%.1f%%)" % (frac * 100.0))
	_check(has_walkable_run, "brak pionowego przejścia >=2 voxele (jaskinie nie są chodliwe)")
	print("[CAVE] (a) jaskinie: %.1f%% pasma wycięte, chodliwe przejścia OK (%d kolumn)" % [frac * 100.0, cols])


# (b) Bedrock + skóra powierzchni nienaruszone -----------------------------------------------------
func _test_bedrock_and_surface_intact() -> void:
	var MIND := VoxelWorld.CAVE_MIN_DEPTH
	var BTOP := VoxelWorld.CAVE_BEDROCK_TOP
	var bedrock_violations := 0
	var surface_violations := 0
	for wx in range(0, 64):
		for wz in range(0, 64):
			var sy := _world.surface_height(wx, wz)
			for wy in range(0, BTOP + 1):                 # bedrock 0..BTOP
				if _world.is_cave(wx, wy, wz, sy):
					bedrock_violations += 1
			for wy in range(maxi(0, sy - MIND + 1), sy + 1):   # skóra: depth < MIND
				if _world.is_cave(wx, wy, wz, sy):
					surface_violations += 1
	_check(bedrock_violations == 0, "bedrock wycięty %d razy (y<=%d musi być stały)" % [bedrock_violations, BTOP])
	_check(surface_violations == 0, "skóra powierzchni wycięta %d razy (depth<%d)" % [surface_violations, MIND])
	print("[CAVE] (b) bedrock (y<=%d) + skóra (depth<%d) nienaruszone OK" % [BTOP, MIND])


# (c) Determinizm + czystość -----------------------------------------------------------------------
func _test_determinism() -> void:
	var MIND := VoxelWorld.CAVE_MIN_DEPTH
	var BTOP := VoxelWorld.CAVE_BEDROCK_TOP
	var SEA := VoxelWorld.SEA_LEVEL
	var w2 := VoxelWorld.new()
	add_child(w2)
	var cave_mism := 0
	var ore_mism := 0
	var purity_mism := 0
	for wx in range(0, 48):
		for wz in range(0, 48):
			var sy := _world.surface_height(wx, wz)
			if sy != w2.surface_height(wx, wz):
				cave_mism += 1
				continue
			if sy <= SEA + 10:
				continue
			for wy in range(BTOP + 1, sy - MIND + 1):
				if _world.is_cave(wx, wy, wz, sy) != w2.is_cave(wx, wy, wz, sy):
					cave_mism += 1
				if _world.ore_at(wx, wy, wz, sy) != w2.ore_at(wx, wy, wz, sy):
					ore_mism += 1
			var wym := (BTOP + 1 + sy - MIND) / 2          # środek pasma — sprawdź czystość (2× to samo wywołanie)
			if _world.is_cave(wx, wym, wz, sy) != _world.is_cave(wx, wym, wz, sy):
				purity_mism += 1
	w2.queue_free()
	_check(cave_mism == 0, "determinizm jaskiń złamany (%d niezgodności między światami)" % cave_mism)
	_check(ore_mism == 0, "determinizm rudy złamany (%d niezgodności)" % ore_mism)
	_check(purity_mism == 0, "is_cave nie jest czyste (%d)" % purity_mism)
	print("[CAVE] (c) determinizm jaskiń + rudy (dwa światy) + czystość OK")


# (f) Wiring: realny chunk faktycznie wycina AIR ---------------------------------------------------
func _test_chunk_wiring() -> void:
	var cs := VoxelWorld.CHUNK_SIZE
	var BTOP := VoxelWorld.CAVE_BEDROCK_TOP
	var hit := _find_carved_voxel()
	_check(not hit.is_empty(), "nie znaleziono wyciętego voxela do testu wiringu chunku")
	if hit.is_empty():
		return
	var wx: int = hit.wx
	var wz: int = hit.wz
	var wy: int = hit.wy
	var cx := wx / cs
	var cz := wz / cs
	var ch := VoxelChunk.new()
	ch.build_data(Vector2i(cx, cz), _world, 1)
	var lx := wx - cx * cs
	var lz := wz - cz * cs
	_check(ch.get_voxel(lx, wy, lz) == Blocks.Type.AIR,
		"chunk NIE wyciął AIR tam gdzie is_cave==true (wiring _generate_data zerwany)")
	var bedrock_air := 0
	for x in range(0, cs):
		for z in range(0, cs):
			for y in range(0, BTOP + 1):
				if ch.get_voxel(x, y, z) == Blocks.Type.AIR:
					bedrock_air += 1
	ch.free()
	_check(bedrock_air == 0, "bedrock w realnym chunku ma AIR (%d voxeli)" % bedrock_air)
	print("[CAVE] (f) realny chunk wycina AIR (wiring) + bedrock stały OK")


# (d) Woda: kolumny pod morzem niewydrążone --------------------------------------------------------
func _test_water_no_carve() -> void:
	var cs := VoxelWorld.CHUNK_SIZE
	var SEA := VoxelWorld.SEA_LEVEL
	var col := _find_submerged_col()
	if col.is_empty():
		print("[CAVE] (d) brak kolumny pod morzem w skanie — pomijam (świat lokalnie wzniesiony)")
		return
	var cx: int = int(col.wx) / cs
	var cz: int = int(col.wz) / cs
	var ch := VoxelChunk.new()
	ch.build_data(Vector2i(cx, cz), _world, 1)
	var sub_air := 0
	var cols := 0
	for x in range(0, cs):
		for z in range(0, cs):
			var sy := _world.surface_height(cx * cs + x, cz * cs + z)
			if sy >= SEA:
				continue
			cols += 1
			for y in range(1, sy):                         # pod powierzchnią, nad dnem
				if ch.get_voxel(x, y, z) == Blocks.Type.AIR:
					sub_air += 1
	ch.free()
	_check(cols > 0, "chunk nie zawiera kolumny pod morzem")
	_check(sub_air == 0, "AIR pod taflą w kolumnie podwodnej (%d) — woda wlałaby się do jaskini" % sub_air)
	print("[CAVE] (d) kolumny pod wodą (%d) niewydrążone OK" % cols)


# (e) Rudy: pasma + rzadkość + kolor niezależny od biomu -------------------------------------------
func _test_ore_bands_and_color() -> void:
	var SEA := VoxelWorld.SEA_LEVEL
	var MIND := VoxelWorld.CAVE_MIN_DEPTH
	var BTOP := VoxelWorld.CAVE_BEDROCK_TOP
	var copper := 0
	var iron := 0
	var gold := 0
	var gold_band_ok := true
	for wx in range(0, 80):
		for wz in range(0, 80):
			var sy := _world.surface_height(wx, wz)
			if sy <= SEA + 16:
				continue
			for wy in range(BTOP + 1, sy - MIND + 1):
				var o := _world.ore_at(wx, wy, wz, sy)
				if o == Blocks.Type.ORE_COPPER:
					copper += 1
				elif o == Blocks.Type.ORE_IRON:
					iron += 1
				elif o == Blocks.Type.ORE_GOLD:
					gold += 1
					if wy > BTOP + 14:
						gold_band_ok = false
	_check(copper > 0, "brak rudy miedzi w skanie")
	_check(iron > 0, "brak rudy żelaza w skanie")
	_check(gold_band_ok, "ruda złota poza pasmem głębokości (wy>%d)" % (BTOP + 14))
	_check(copper >= iron, "miedź nie częstsza od żelaza (copper=%d iron=%d)" % [copper, iron])
	_check(iron >= gold, "żelazo nie częstsze od złota (iron=%d gold=%d)" % [iron, gold])
	print("[CAVE] (e) rudy: copper=%d iron=%d gold=%d, pasma+rzadkość OK" % [copper, iron, gold])
	_test_ore_color_biome_independent()


## Kolor ORE_COPPER w kolumnie Frosthelm NIE może być zmodulowany biomem (frost = błękit/desat).
## To bezpośrednio łapie pominięcie early-return w _solid_color.
func _test_ore_color_biome_independent() -> void:
	var cs := VoxelWorld.CHUNK_SIZE
	var fx := _find_x_for_biome(&"frosthelm")
	if fx < 0:
		print("[CAVE] (e2) frosthelm nieosiągalny w skanie — pomijam test koloru")
		return
	var cx := fx / cs
	var ch := VoxelChunk.new()
	ch.build_data(Vector2i(cx, 0), _world, 1)
	var base := Blocks.color_of(Blocks.Type.ORE_COPPER)
	var got: Color = ch._solid_color(_world, Blocks.Type.ORE_COPPER, fx - cx * cs, 8, 0)
	ch.free()
	var frosted := Blocks.biome_modulate(base, &"frosthelm")
	var d_base := _col_dist(got, base)
	var d_frost := _col_dist(got, frosted)
	_check(d_base < d_frost,
		"kolor rudy zmodulowany biomem (frost) — brak early-return w _solid_color (d_base=%.3f d_frost=%.3f)" % [d_base, d_frost])
	_check(d_base <= 0.12, "kolor rudy odbiega od bazy o %.3f (oczekiwany tylko mikro-tint)" % d_base)
	print("[CAVE] (e2) kolor rudy niezależny od biomu (d_base=%.3f << d_frost=%.3f) OK" % [d_base, d_frost])


# --- Helpery ---------------------------------------------------------------------------------------
func _find_carved_voxel() -> Dictionary:
	var SEA := VoxelWorld.SEA_LEVEL
	var MIND := VoxelWorld.CAVE_MIN_DEPTH
	var BTOP := VoxelWorld.CAVE_BEDROCK_TOP
	for wx in range(0, 64):
		for wz in range(0, 64):
			var sy := _world.surface_height(wx, wz)
			if sy <= SEA + 10:
				continue
			for wy in range(BTOP + 1, sy - MIND + 1):
				if _world.is_cave(wx, wy, wz, sy):
					return {"wx": wx, "wy": wy, "wz": wz, "sy": sy}
	return {}


func _find_submerged_col() -> Dictionary:
	var SEA := VoxelWorld.SEA_LEVEL
	for wx in range(0, 192):
		for wz in range(0, 192):
			if _world.surface_height(wx, wz) < SEA:
				return {"wx": wx, "wz": wz}
	return {}


## Pierwszy world_x na osi +X o danym biomie (skan co 32 m). -1 gdy nieosiągalny.
func _find_x_for_biome(biome: StringName) -> int:
	for step in range(0, 300):
		var x := step * 32
		if _world.get_biome(x, 0) == biome:
			return x
	return -1


func _col_dist(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
