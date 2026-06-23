extends Node
## Feel3Test.gd — HEADLESS test FAZY 3 (VISUAL IDENTITY): material contrast, emisyjne akcenty,
## per-biom paleta + post, sylwetki wrogow, preset HIGH vs LOW. Uruchomienie:
##   godot --headless res://test/Feel3Test.tscn
##
## NIE rusza dzialajacej gry — instancjuje REALNE klasy (Player/Enemy/LootDrop) i czyta dane
## (Blocks.biome_modulate, GameSettings.apply_graphics). Weryfikuje KONTRAKT FAZY 3:
##  (1) SHADERY: terrain/props/water kompiluja sie (laduje .gdshader, sprawdza brak bledu).
##  (2) PRESET HIGH != LOW: apply_graphics(LOW) i (HIGH) ustawiaja ROZNE property Environment
##      (volumetric_fog/sdfgi/ssr/ssil + ssao_radius/glow_intensity premium na HIGH).
##  (3) PER-BIOM PALETA: Blocks.biome_modulate daje ROZNY kolor per biom (Ember cieplejszy/
##      bardziej nasycony, Frost chlodniejszy/wyblakly) — biom czyta sie jako MIEJSCE.
##  (4) EMISYJNE AKCENTY: wrog ma emisyjne oczy/akcent (material z emission_enabled); gracz ma
##      mini-meshe blysku oczu (emisyjne); loot-glow ROSNIE z rzadkoscia + BEAM od RARE w gore.
##  (5) SYLWETKI WROGOW: Goblin/Brute/Slinger maja ROZNE sylwetki (rozna liczba/proporcja kostek
##      modelu) => czytaja sie z daleka jako inne archetypy.
## Kod wyjscia: 0 = ALL OK, 1 = FAIL. Print "[FEEL3] ..." + ALL OK + quit.

const PlayerScript := preload("res://src/Player.gd")
const EnemyScript := preload("res://src/Enemy.gd")
const LootDropScript := preload("res://src/LootDrop.gd")
const ItemInstanceScript := preload("res://data/resources/ItemInstance.gd")

var _failures: int = 0


func _ready() -> void:
	print("[FEEL3] === Faza 3 (VISUAL IDENTITY) mini-test start ===")
	_test_shaders_compile()
	_test_preset_high_vs_low()
	_test_biome_palette()
	_test_biome_cache()
	await _test_emissive_accents()
	await _test_enemy_silhouettes()

	if _failures == 0:
		print("[FEEL3] ALL OK")
	else:
		printerr("[FEEL3] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[FEEL3] FAIL: %s" % msg)


# ============================================================================
#  (1) SHADERY — terrain/props/water kompiluja sie (load + brak bledu kompilacji)
# ============================================================================
func _test_shaders_compile() -> void:
	for path in ["res://src/world/terrain.gdshader", "res://src/world/props.gdshader", "res://src/world/water.gdshader"]:
		var sh: Shader = load(path)
		_check(sh != null, "SHADER: nie zaladowano %s" % path)
		if sh != null:
			# Material z shaderem -> zmusza silnik do kompilacji. Brak crasha = OK (jak FeelTest (6)).
			var m := ShaderMaterial.new()
			m.shader = sh
			_check(m.shader == sh, "SHADER: ShaderMaterial nie przyjal %s" % path)
	print("[FEEL3] (1) shadery terrain/props/water kompiluja sie OK")


# ============================================================================
#  (2) PRESET HIGH != LOW — apply_graphics ustawia ROZNE property Environment
# ============================================================================
func _test_preset_high_vs_low() -> void:
	if GameSettings == null:
		_check(false, "PRESET: brak autoloadu GameSettings")
		return
	var env_low := Environment.new()
	var env_high := Environment.new()
	var prev: int = GameSettings.graphics_preset

	GameSettings.graphics_preset = GameSettings.GraphicsPreset.LOW
	GameSettings.apply_graphics(null, env_low)
	GameSettings.graphics_preset = GameSettings.GraphicsPreset.HIGH
	GameSettings.apply_graphics(null, env_high)
	GameSettings.graphics_preset = prev   # przywroc (nie psuj globalnego stanu sesji)

	# Ciezkie efekty: OFF na LOW, ON na HIGH (4GB-safe LOW; premium HIGH).
	_check(env_low.volumetric_fog_enabled == false and env_high.volumetric_fog_enabled == true,
		"PRESET: volumetric_fog nie rozni LOW/HIGH (low=%s high=%s)" % [env_low.volumetric_fog_enabled, env_high.volumetric_fog_enabled])
	_check(env_low.sdfgi_enabled == false and env_high.sdfgi_enabled == true,
		"PRESET: sdfgi nie rozni LOW/HIGH")
	_check(env_low.ssr_enabled == false and env_high.ssr_enabled == true,
		"PRESET: ssr nie rozni LOW/HIGH")
	_check(env_low.ssil_enabled == false and env_high.ssil_enabled == true,
		"PRESET: ssil nie rozni LOW/HIGH")
	# Premium FEEL 3: HIGH podbija SSAO/glow ponad baseline LOW (i LOW je sciaga z powrotem).
	_check(env_high.ssao_radius > env_low.ssao_radius,
		"PRESET: ssao_radius HIGH nie wiekszy niz LOW (low=%.2f high=%.2f)" % [env_low.ssao_radius, env_high.ssao_radius])
	_check(env_high.glow_intensity > env_low.glow_intensity,
		"PRESET: glow_intensity HIGH nie wiekszy niz LOW (low=%.2f high=%.2f)" % [env_low.glow_intensity, env_high.glow_intensity])
	print("[FEEL3] (2) preset HIGH!=LOW: volfog/sdfgi/ssr/ssil + ssao(%.2f->%.2f)/glow(%.2f->%.2f) OK" %
		[env_low.ssao_radius, env_high.ssao_radius, env_low.glow_intensity, env_high.glow_intensity])


# ============================================================================
#  (3) PER-BIOM PALETA — Blocks.biome_modulate daje rozny kolor per biom
# ============================================================================
func _test_biome_palette() -> void:
	# Baza neutralna (szary kamien) — modulacja biomu ma ja przesunac w temat MIEJSCA.
	var base := Color(0.46, 0.46, 0.50)
	var verdant := Blocks.biome_modulate(base, &"verdant")
	var ember := Blocks.biome_modulate(base, &"emberwaste")
	var frost := Blocks.biome_modulate(base, &"frosthelm")

	# Trzy biomy daja TRZY rozne kolory (nie ta sama paleta).
	_check(not verdant.is_equal_approx(ember), "BIOM: Verdant == Emberwaste (paleta nie rozni biomow)")
	_check(not verdant.is_equal_approx(frost), "BIOM: Verdant == Frosthelm (paleta nie rozni biomow)")
	_check(not ember.is_equal_approx(frost), "BIOM: Emberwaste == Frosthelm (paleta nie rozni biomow)")

	# Emberwaste CIEPLEJSZY: R/B wyzszy niz w Frosthelm (rdzawy spiek vs zimny blekit).
	_check(ember.r > frost.r, "BIOM: Emberwaste nie cieplejszy w R niz Frosthelm (e=%.3f f=%.3f)" % [ember.r, frost.r])
	# Frosthelm CHLODNIEJSZY: B wyzszy niz R (przesyp blekitny).
	_check(frost.b > frost.r, "BIOM: Frosthelm nie chlodny (B<=R: b=%.3f r=%.3f)" % [frost.b, frost.r])
	# Emberwaste CIEPLY: R wyzszy niz B (przesyp rdzawy).
	_check(ember.r > ember.b, "BIOM: Emberwaste nie cieply (R<=B: r=%.3f b=%.3f)" % [ember.r, ember.b])

	# Frosthelm DESATUROWANY vs Emberwaste (mniejszy rozrzut kanalow = blizej szarosci).
	var spread_ember := _chan_spread(ember)
	var spread_frost := _chan_spread(frost)
	_check(spread_frost < spread_ember, "BIOM: Frosthelm nie bardziej wyblakly niz Emberwaste (sf=%.3f se=%.3f)" % [spread_frost, spread_ember])
	print("[FEEL3] (3) per-biom paleta: V=%s E=%s F=%s (rozne, Ember cieply, Frost zimny/wyblakly) OK" %
		[_cs(verdant), _cs(ember), _cs(frost)])


func _chan_spread(c: Color) -> float:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	return mx - mn

func _cs(c: Color) -> String:
	return "(%.2f,%.2f,%.2f)" % [c.r, c.g, c.b]


# ============================================================================
#  (3b) BIOME CACHE (review #minor perf) — _biomemap policzony raz na kolumne w _generate_data
#       MUSI zwracac DOKLADNIE to samo co world.get_biome (poprawnosc optymalizacji hot-path).
#       Eliminuje do 12 zbednych probek szumu/voxel (get_biome bylo wolane per ŚCIANA).
# ============================================================================
func _test_biome_cache() -> void:
	var world := VoxelWorld.new()
	add_child(world)   # _ready konfiguruje szumy biomu/wilgotnosci
	# Realny chunk NEAR: build_data(lod=1) wola _generate_data -> wypelnia _biomemap.
	var chunk := VoxelChunk.new()
	add_child(chunk)
	chunk.build_data(Vector2i(7, -3), world, 1)
	var cs: int = VoxelChunk.CHUNK_SIZE
	var mismatches := 0
	# Probkujemy SIATKE kolumn (nie wszystkie 1024 — wystarczy gesto, by zlapac granice biomu w chunku).
	for lx in range(0, cs, 4):
		for lz in range(0, cs, 4):
			var wx: int = 7 * cs + lx
			var wz: int = -3 * cs + lz
			var cached: StringName = chunk._biome_at(world, lx, lz, wx, wz)
			var live: StringName = world.get_biome(wx, wz)
			if cached != live:
				mismatches += 1
	_check(mismatches == 0, "BIOME CACHE: _biome_at != world.get_biome dla %d kolumn (cache niespojny)" % mismatches)
	# Fallback FAR: swiezy chunk BEZ build_data => _biomemap pusty => _biome_at musi siegnac do world.get_biome.
	var far_chunk := VoxelChunk.new()
	add_child(far_chunk)
	far_chunk._coord = Vector2i(2, 2)
	var fb: StringName = far_chunk._biome_at(world, 0, 0, 99, 99)
	_check(fb == world.get_biome(99, 99), "BIOME CACHE: fallback (pusty _biomemap) nie zgadza sie z get_biome")
	chunk.queue_free(); far_chunk.queue_free(); world.queue_free()
	print("[FEEL3] (3b) biome cache: _biomemap == get_biome dla wszystkich probkowanych kolumn + fallback FAR OK")


# ============================================================================
#  (4) EMISYJNE AKCENTY — wrog (oczy/akcent), gracz (blysk oczu), loot-glow wg rzadkosci + beam
# ============================================================================
func _test_emissive_accents() -> void:
	# --- WROG: co najmniej jeden material emisyjny (oczy/rdzen/kula) ---
	var e = EnemyScript.new()
	add_child(e)
	await get_tree().process_frame
	await get_tree().process_frame
	var emissive_mats := 0
	for m in e._mats:
		if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled:
			emissive_mats += 1
	_check(emissive_mats >= 1, "EMIT wrog: brak emisyjnych akcentow (oczy/rdzen) — emissive_mats=%d" % emissive_mats)
	e.queue_free()
	await get_tree().process_frame

	# --- GRACZ: mini-meshe blysku oczu (emisyjne dzieci _head) ---
	var p = PlayerScript.new()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	var head: Node3D = p.get("_head")
	var glints := 0
	if head != null:
		for c in head.get_children():
			if c is MeshInstance3D:
				var mm := (c as MeshInstance3D).material_override
				if mm is StandardMaterial3D and (mm as StandardMaterial3D).emission_enabled:
					glints += 1
	_check(glints >= 2, "EMIT gracz: brak >=2 emisyjnych blyskow oczu (glints=%d)" % glints)
	p.queue_free()
	await get_tree().process_frame

	# --- LOOT-GLOW wg rzadkosci: COMMON < LEGENDARY emisja rdzenia; BEAM od RARE w gore ---
	var common_drop = _make_loot(0)   # COMMON
	add_child(common_drop)
	await get_tree().process_frame
	var legendary_drop = _make_loot(4)   # LEGENDARY
	add_child(legendary_drop)
	await get_tree().process_frame

	var em_common: float = _core_emission(common_drop)
	var em_legend: float = _core_emission(legendary_drop)
	_check(em_legend > em_common, "LOOT: legendarny glow nie mocniejszy niz common (c=%.2f l=%.2f)" % [em_common, em_legend])
	# BEAM: COMMON nie ma slupa; RARE+ ma.
	_check(common_drop._beam == null, "LOOT: COMMON ma beam (powinien tylko RARE+)")
	var rare_drop = _make_loot(2)   # RARE
	add_child(rare_drop)
	await get_tree().process_frame
	_check(rare_drop._beam != null, "LOOT: RARE nie ma beam (slup swiatla od RARE w gore)")
	common_drop.queue_free(); legendary_drop.queue_free(); rare_drop.queue_free()
	await get_tree().process_frame
	print("[FEEL3] (4) emisja: wrog emissive=%d, gracz blyski=%d, loot glow %.2f(common)->%.2f(legend) + beam RARE OK" %
		[emissive_mats, glints, em_common, em_legend])


func _make_loot(rarity: int):
	var inst = ItemInstanceScript.new()
	inst.rarity = rarity
	var d = LootDropScript.new()
	d.item = inst
	return d

func _core_emission(drop) -> float:
	if drop._mesh == null:
		return 0.0
	var m := drop._mesh.material_override as StandardMaterial3D
	return m.emission_energy_multiplier if m != null else 0.0


# ============================================================================
#  (5) SYLWETKI WROGOW — Goblin/Brute/Slinger maja ROZNE sylwetki (rozna liczba kostek)
# ============================================================================
func _test_enemy_silhouettes() -> void:
	var counts := {}
	for kind in [&"goblin", &"brute", &"slinger"]:
		var e = EnemyScript.new()
		e.variant_id = kind
		add_child(e)
		await get_tree().process_frame
		await get_tree().process_frame
		# Liczba kostek modelu = "zlozonosc sylwetki" (proxy proporcji/akcentow). Liczymy MeshInstance3D.
		counts[kind] = _count_meshes(e._model)
		# Kazdy wariant MUSI miec komplet pivotow (rig dziala bez zmian).
		_check(e._arm_l != null and e._arm_r != null and e._leg_l != null and e._leg_r != null,
			"SYLWETKA %s: brak pivotow rigu (arm/leg)" % kind)
		e.queue_free()
		await get_tree().process_frame

	# Trzy sylwetki = trzy ROZNE liczby kostek (inny ksztalt; nie ten sam model w 3 skalach).
	_check(counts[&"goblin"] != counts[&"brute"], "SYLWETKA: Goblin == Brute (ta sama liczba kostek %d)" % counts[&"goblin"])
	_check(counts[&"goblin"] != counts[&"slinger"], "SYLWETKA: Goblin == Slinger (ta sama liczba kostek)")
	_check(counts[&"brute"] != counts[&"slinger"], "SYLWETKA: Brute == Slinger (ta sama liczba kostek)")
	# Brute = najbardziej masywny/zlozony (bary+rdzen+maczuga) => najwiecej kostek.
	_check(counts[&"brute"] > counts[&"goblin"], "SYLWETKA: Brute nie masywniejszy niz Goblin (b=%d g=%d)" % [counts[&"brute"], counts[&"goblin"]])
	print("[FEEL3] (5) sylwetki: goblin=%d brute=%d slinger=%d kostek (rozne archetypy) OK" %
		[counts[&"goblin"], counts[&"brute"], counts[&"slinger"]])


func _count_meshes(n: Node) -> int:
	if n == null:
		return 0
	var c := 0
	for ch in n.get_children():
		if ch is MeshInstance3D:
			c += 1
		c += _count_meshes(ch)
	return c
