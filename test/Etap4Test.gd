extends Node
## Etap4Test.gd — mini-test HEADLESS Etapu 4 (DoD: biomy + wrogowie + deterministyczny spawn).
## _ready() jest KORUTYNĄ (await) — test (9) telegrafu czeka na klatkę fizyki; bez await na
## NIE rusza działającej gry (Main.tscn). Uruchomienie: godot --headless res://test/Etap4Test.tscn
##
## Sprawdza DoD Etapu 4 (ROADMAP 5/6 / GDD 7 / TDD):
##  (1) get_biome DETERMINISTYCZNY: ten sam (x,z) -> ten sam biom; wszystkie pasma osiągalne dystansem.
##  (2) get_biome zwraca tylko prawidłowe id (pełne 7 biomów); pokrycie wszystkich pasm na mapie.
##  (3) BiomeResource (3 .tres) wczytane przez EnemyDB; loot_tier 1/2/3; spawn table niepusta.
##  (4) EnemyResource warianty (Goblin/Brute/Slinger) — staty zgodne z ROADMAP 6.
##  (5) Enemy.configure_from_resource mapuje staty zasobu na encję (HP/dmg/armor/profil/threat_tier).
##  (6) Warianty biomowe (ember/frost) — reskin (skin/eye/element) + threat_tier z zasobu.
##  (7) Deterministyczny SPAWN: region_seed ten sam (base,region) -> ten sam seed; różne regiony różne.
##  (8) Tabela spawnu deterministyczna: ten sam seed/region -> TA SAMA lista (typy+kolejność).
##  (9) Telegraf wg threat_tier: elite/boss spawnuje HazardZone preview; trash nie.
## (10) Biome loot tier dostępny + spójny z dystansem (distance_tier rośnie z odległością).
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[E4] ..." + ALL OK + quit.

const EPS: float = 0.0001

var _failures: int = 0
var _world: VoxelWorld = null


func _ready() -> void:
	print("[E4] === Etap 4 mini-test start ===")

	# Świat (szum biomów) — _ready konfiguruje _biome_noise/_humid_noise.
	_world = VoxelWorld.new()
	add_child(_world)
	# DB biomów/wrogów — przeładuj na wypadek pustego skanu przy starcie autoloadu.
	if EnemyDB != null:
		EnemyDB.reload()

	_test_get_biome_deterministic()
	_test_get_biome_three_zones()
	# BIOME PROGRESSION (redesign dystansowy) — kontrakt: las na starcie, dalej=trudniej w kolejności,
	# organiczne granice. Te testy FAILowałyby na starym modelu czystego szumu klimatu.
	_test_biome_spawn_is_forest()
	_test_biome_progression_by_distance()
	_test_biome_borders_organic()
	_test_biome_resources_loaded()
	_test_enemy_variant_stats()
	_test_configure_from_resource()
	_test_biome_variant_reskin()
	_test_region_seed_deterministic()
	_test_spawn_table_deterministic()
	# WAŻNE (review #MAJOR — integralność testu): test (9) zawiera `await get_tree().process_frame`.
	# BEZ `await` poniżej korutyna zawiesza się i oddaje sterowanie do _ready(), które natychmiast
	# leci do sprawdzenia `_failures` i `quit()` — druga połowa testu (9) (asercja "trash NIE
	# telegrafuje") wykonałaby się PO policzeniu wyniku i byłaby cicho połknięta. `await` zawiesza
	# _ready() na CAŁY czas testu (9), więc _failures jest KOMPLETNE przed quit().
	await _test_telegraph_by_threat_tier()
	_test_distance_tier_and_loot_tier()
	# (11) BEHAWIORALNA weryfikacja loot_tier biomu (review #MAJOR): realna różnica w dropie
	# (rzadkość/ilvl) między verdant (tier1) a frosthelm (tier3) przy tym samym dystansie.
	_test_biome_loot_tier_behaviour()

	if _failures == 0:
		print("[E4] ALL OK")
	else:
		printerr("[E4] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[E4] FAIL: %s" % msg)


# ---------------------------------------------------------------------------
#  (1) get_biome deterministyczny — ten sam coord ten sam biom
# ---------------------------------------------------------------------------
func _test_get_biome_deterministic() -> void:
	var coords := [Vector2i(0, 0), Vector2i(1234, -567), Vector2i(-9999, 4242), Vector2i(50000, 50000)]
	for c in coords:
		var b1 := _world.get_biome(c.x, c.y)
		var b2 := _world.get_biome(c.x, c.y)
		_check(b1 == b2, "get_biome niedeterministyczny dla %s: %s != %s" % [c, b1, b2])
		_check(_is_valid_biome(b1), "get_biome zwrocil nieznany biom: %s @ %s" % [b1, c])
	# Drugi, świeży świat z tym samym kodem szumu daje TEN SAM podział (seedy szumu w kodzie).
	var w2 := VoxelWorld.new()
	add_child(w2)
	for c in coords:
		_check(_world.get_biome(c.x, c.y) == w2.get_biome(c.x, c.y),
			"get_biome nie powtarzalny miedzy instancjami swiata @ %s" % c)
	w2.queue_free()
	print("[E4] (1) get_biome deterministyczny OK")


# ---------------------------------------------------------------------------
#  (2) PEŁNE 7 biomów — skan dużej mapy musi pokryć WSZYSTKIE pasma progresji.
#      Kontrakt po #9: get_biome zwraca tylko id z BIOME_PROGRESSION i każde pasmo jest osiągalne.
#      Siatka rozszerzona, by sięgnąć ostatniego pasma (volcanic ~band 6 => d≥4200 m): krok 64 m,
#      150×150 próbek => narożnik d≈6788 m (clamp do ostatniego pasma => volcanic obecny).
# ---------------------------------------------------------------------------
func _test_get_biome_three_zones() -> void:
	var seen := {}
	for ix in range(-75, 75):
		for iz in range(-75, 75):
			var b := _world.get_biome(ix * 64, iz * 64)
			seen[b] = true
			_check(_is_valid_biome(b), "get_biome zwrocil id spoza progresji: %s" % b)
	# Każde z 7 pasm progresji musi być pokryte na mapie (wszystkie osiągalne dystansem).
	for expected in VoxelWorld.BIOME_PROGRESSION:
		_check(seen.has(expected), "brak strefy %s na mapie" % expected)
	_check(seen.size() == VoxelWorld.BIOME_PROGRESSION.size(),
		"get_biome zwraca inne biomy niz %d zdefiniowanych (znalezione: %d)" % [VoxelWorld.BIOME_PROGRESSION.size(), seen.size()])
	print("[E4] (2) wszystkie %d pasm biomow obecne OK" % seen.size())


func _is_valid_biome(b: StringName) -> bool:
	return VoxelWorld.BIOME_PROGRESSION.has(b)


## Indeks biomu w progresji trudności (0=start/las .. N=najdalszy). -1 = nieznany.
func _biome_progression_index(b: StringName) -> int:
	return VoxelWorld.BIOME_PROGRESSION.find(b)


# ---------------------------------------------------------------------------
#  (1b) PROGRESJA — start to ZAWSZE las (verdant), a najbliższa okolica spawnu też.
#       "starting biome = forest, beginner friendly". Stary model (czysty szum) tego NIE gwarantował.
# ---------------------------------------------------------------------------
func _test_biome_spawn_is_forest() -> void:
	_check(_world.get_biome(0, 0) == VoxelWorld.BIOME_VERDANT, "spawn (0,0) nie jest lasem (verdant)")
	# Cała najbliższa okolica (≤ ~300 m, dobrze wewnątrz pasma 0 nawet z maks. warpem) musi być lasem.
	for p in [Vector2i(200, 0), Vector2i(-200, 0), Vector2i(0, 250), Vector2i(150, 150), Vector2i(-180, -120)]:
		var b := _world.get_biome(p.x, p.y)
		_check(b == VoxelWorld.BIOME_VERDANT, "okolica spawnu %s nie jest lasem (jest %s)" % [p, b])
	print("[E4] (1b) spawn + okolica = las (verdant) OK")


# ---------------------------------------------------------------------------
#  (1c) PROGRESJA — dalej = trudniejszy biom w STAŁEJ kolejności (verdant<ember<frost).
#       Punkty oddalone DUŻO bardziej niż jitter granicy => kolejność musi być ściśle rosnąca.
# ---------------------------------------------------------------------------
func _test_biome_progression_by_distance() -> void:
	# Checkpointy wzdłuż +X, rozstawione >> jitter (90 m), więc ranga jest jednoznaczna.
	var near_i := _biome_progression_index(_world.get_biome(0, 0))        # ~las
	var mid_i := _biome_progression_index(_world.get_biome(1000, 0))      # ~ember
	var far_i := _biome_progression_index(_world.get_biome(2000, 0))      # ~frost
	_check(near_i == 0, "biom @spawn nie jest pierwszym w progresji (indeks %d)" % near_i)
	_check(mid_i > near_i, "biom @1000m nie jest dalszy w progresji niż start (%d <= %d)" % [mid_i, near_i])
	_check(far_i > mid_i, "biom @2000m nie jest dalszy w progresji niż @1000m (%d <= %d)" % [far_i, mid_i])
	# Determinizm progresji w innym kierunku (–Z) — ta sama ranga na tym samym dystansie ± jitter.
	var far_negz := _biome_progression_index(_world.get_biome(0, -2000))
	_check(far_negz >= 1, "biom @2000m w –Z zbyt blisko startu progresji (indeks %d)" % far_negz)
	print("[E4] (1c) progresja dystansem (start<mid<far: %d<%d<%d) OK" % [near_i, mid_i, far_i])


# ---------------------------------------------------------------------------
#  (1d) PROGRESJA — granice są ORGANICZNE (warp szumem), nie idealne okręgi. Na pierścieniu
#       blisko granicy pasma 0/1 (~700 m) próbkowanie po kątach musi dać OBA pasma.
# ---------------------------------------------------------------------------
func _test_biome_borders_organic() -> void:
	var seen_bands := {}
	var samples := 64
	var radius := VoxelWorld.BIOME_BAND_METERS   # dokładnie na granicy pasma 0/1
	for i in samples:
		var ang := TAU * float(i) / float(samples)
		var x := int(round(cos(ang) * radius))
		var z := int(round(sin(ang) * radius))
		seen_bands[_biome_progression_index(_world.get_biome(x, z))] = true
	_check(seen_bands.size() >= 2,
		"granica pasm na r=%.0f m NIE jest organiczna (warp martwy): widziano %d pasm" % [radius, seen_bands.size()])
	print("[E4] (1d) organiczne granice biomów (warp szumem, %d pasm na pierścieniu) OK" % seen_bands.size())


# ---------------------------------------------------------------------------
#  (3) BiomeResource (.tres) wczytane; loot_tier 1/2/3; spawn table niepusta
# ---------------------------------------------------------------------------
func _test_biome_resources_loaded() -> void:
	var expect := {
		&"verdant": 1,
		&"emberwaste": 2,
		&"frosthelm": 3,
	}
	for id in expect:
		var br: BiomeResource = EnemyDB.biome(id)
		_check(br != null, "BiomeResource brak w EnemyDB: %s" % id)
		if br == null:
			continue
		_check(br.loot_tier == expect[id], "loot_tier %s != %d (jest %d)" % [id, expect[id], br.loot_tier])
		_check(not br.enemy_spawn_table.is_empty(), "spawn table pusta dla biomu %s" % id)
		# Każdy wpis tabeli ma enemy_id istniejący w EnemyDB.
		for e in br.enemy_spawn_table:
			var eid := StringName((e as Dictionary).get("enemy_id", &""))
			_check(EnemyDB.enemy(eid) != null, "spawn table %s -> nieznany enemy_id %s" % [id, eid])
	print("[E4] (3) BiomeResource x3 + loot_tier + spawn table OK")


# ---------------------------------------------------------------------------
#  (4) EnemyResource warianty — staty zgodne z ROADMAP 6
# ---------------------------------------------------------------------------
func _test_enemy_variant_stats() -> void:
	# {id: [hp, dmg, armor, speed]}
	var expect := {
		&"goblin": [30.0, 8.0, 0.0, 3.5],
		&"brute": [120.0, 18.0, 0.3, 2.8],
		&"slinger": [45.0, 12.0, 0.0, 3.0],
	}
	for id in expect:
		var res: EnemyResource = EnemyDB.enemy(id)
		_check(res != null, "EnemyResource brak: %s" % id)
		if res == null or res.stats == null:
			_check(res != null and res.stats != null, "EnemyResource/stats null: %s" % id)
			continue
		var sb: StatBlock = res.stats
		var ex: Array = expect[id]
		_check(absf(sb.max_hp - ex[0]) < EPS, "%s HP %.1f != %.1f" % [id, sb.max_hp, ex[0]])
		_check(absf(sb.damage - ex[1]) < EPS, "%s dmg %.1f != %.1f" % [id, sb.damage, ex[1]])
		_check(absf(sb.armor - ex[2]) < EPS, "%s armor %.2f != %.2f" % [id, sb.armor, ex[2]])
		_check(absf(sb.move_speed - ex[3]) < EPS, "%s speed %.1f != %.1f" % [id, sb.move_speed, ex[3]])
	# Profile/threat_tier wariantów.
	_check(EnemyDB.enemy(&"goblin").threat_tier == &"trash", "goblin threat_tier != trash")
	_check(EnemyDB.enemy(&"brute").threat_tier == &"elite", "brute threat_tier != elite")
	_check(EnemyDB.enemy(&"slinger").ai_profile == &"ranged", "slinger ai_profile != ranged")
	_check(EnemyDB.enemy(&"brute").ai_profile == &"melee", "brute ai_profile != melee")
	print("[E4] (4) staty wariantow Goblin/Brute/Slinger (ROADMAP 6) OK")


# ---------------------------------------------------------------------------
#  (5) configure_from_resource mapuje staty zasobu na encję
# ---------------------------------------------------------------------------
func _test_configure_from_resource() -> void:
	var brute_res: EnemyResource = EnemyDB.enemy(&"brute")
	var e := Enemy.new()
	e.configure_from_resource(brute_res)
	# PRZED add_child: eksporty już ustawione (komponenty zobaczą je w _ready).
	_check(absf(e.max_hp - 120.0) < EPS, "configure: Brute max_hp %.1f != 120" % e.max_hp)
	_check(absf(e.attack_damage - 18.0) < EPS, "configure: Brute dmg %.1f != 18" % e.attack_damage)
	_check(absf(e.armor - 0.3) < EPS, "configure: Brute armor %.2f != 0.3" % e.armor)
	_check(absf(e.attack_windup - 0.55) < EPS, "configure: Brute windup %.2f != 0.55" % e.attack_windup)
	_check(e.threat_tier == &"elite", "configure: Brute threat_tier != elite")
	_check(e.ai_profile == &"melee", "configure: Brute ai_profile != melee")
	_check(e.variant_id == &"brute", "configure: variant_id != brute")
	# Po wejściu do drzewa HealthComponent powinien przejąć HP z max_hp (DoD Etapu 1 nadal działa).
	add_child(e)
	_check(absf(e.hp - 120.0) < 0.5, "configure: Brute hp po _ready %.1f != 120" % e.hp)
	e.queue_free()

	# Slinger -> ranged, attack_range duży (pocisk).
	var sl := Enemy.new()
	sl.configure_from_resource(EnemyDB.enemy(&"slinger"))
	_check(sl.ai_profile == &"ranged", "configure: Slinger ai_profile != ranged")
	_check(sl.attack_range >= 8.0, "configure: Slinger attack_range %.1f za maly (ranged)" % sl.attack_range)
	_check(absf(sl.max_hp - 45.0) < EPS, "configure: Slinger HP %.1f != 45" % sl.max_hp)
	sl.free()
	print("[E4] (5) configure_from_resource -> encja OK")


# ---------------------------------------------------------------------------
#  (6) Warianty biomowe (ember/frost) — reskin + element + threat_tier
# ---------------------------------------------------------------------------
func _test_biome_variant_reskin() -> void:
	var ember: EnemyResource = EnemyDB.enemy(&"ember_brute")
	var frost: EnemyResource = EnemyDB.enemy(&"frost_brute")
	_check(ember != null and frost != null, "warianty biomowe brak (ember_brute/frost_brute)")
	if ember == null or frost == null:
		return
	var e := Enemy.new()
	e.configure_from_resource(ember)
	_check(e.element == &"fire", "ember_brute element != fire (jest %s)" % e.element)
	_check(e.skin_tint.a > 0.0, "ember_brute brak reskinu skory")
	_check(e.threat_tier == &"elite", "ember_brute threat_tier != elite")
	e.free()
	var f := Enemy.new()
	f.configure_from_resource(frost)
	_check(f.element == &"frost", "frost_brute element != frost (jest %s)" % f.element)
	_check(f.threat_tier == &"boss", "frost_brute threat_tier != boss")
	_check(f.body_scale > 1.0, "frost_brute body_scale <= 1 (powinien byc wiekszy)")
	f.free()
	# Warianty biomowe są przypisane do właściwych biomów w spawn table.
	_check(_biome_table_has(&"emberwaste", &"ember_brute"), "emberwaste table bez ember_brute")
	_check(_biome_table_has(&"frosthelm", &"frost_brute"), "frosthelm table bez frost_brute")
	print("[E4] (6) warianty biomowe (reskin/element/threat_tier) OK")


func _biome_table_has(biome: StringName, enemy_id: StringName) -> bool:
	var br: BiomeResource = EnemyDB.biome(biome)
	if br == null:
		return false
	for e in br.enemy_spawn_table:
		if StringName((e as Dictionary).get("enemy_id", &"")) == enemy_id:
			return true
	return false


# ---------------------------------------------------------------------------
#  (7) region_seed deterministyczny — ten sam (base,region) ten sam seed
# ---------------------------------------------------------------------------
func _test_region_seed_deterministic() -> void:
	var base := 0xABCDEF
	var r := Vector2i(3, -7)
	var s1 := WorldSpawner.region_seed(base, r)
	var s2 := WorldSpawner.region_seed(base, r)
	_check(s1 == s2, "region_seed niedeterministyczny: %d != %d" % [s1, s2])
	_check(s1 >= 0, "region_seed ujemny (powinien byc maskowany dodatni): %d" % s1)
	# Różne regiony => (prawie zawsze) różne seedy.
	_check(WorldSpawner.region_seed(base, Vector2i(3, -7)) != WorldSpawner.region_seed(base, Vector2i(3, -8)),
		"region_seed identyczny dla roznych regionow")
	_check(WorldSpawner.region_seed(base, r) != WorldSpawner.region_seed(base + 1, r),
		"region_seed identyczny dla roznych base seedow")
	print("[E4] (7) region_seed deterministyczny OK")


# ---------------------------------------------------------------------------
#  (8) Tabela spawnu deterministyczna — ten sam seed/region -> TA SAMA lista
# ---------------------------------------------------------------------------
func _test_spawn_table_deterministic() -> void:
	var br: BiomeResource = EnemyDB.biome(&"verdant")
	_check(br != null and not br.enemy_spawn_table.is_empty(), "brak tabeli verdant do testu")
	if br == null:
		return
	var table := br.enemy_spawn_table
	var base := 0x1357
	var region := Vector2i(2, 5)
	var seq_a := _simulate_picks(base, region, table, 20)
	var seq_b := _simulate_picks(base, region, table, 20)
	_check(seq_a == seq_b, "spawn picks niedeterministyczne dla tego samego seeda/regionu:\n  %s\n  %s" % [seq_a, seq_b])
	# Inny region -> (zwykle) inna sekwencja. NIE asercja (różnorodność nie jest gwarantowana
	# dla małej tabeli) — tylko print informacyjny. Determinizm (seq_a==seq_b) to klucz DoD.
	var seq_c := _simulate_picks(base, Vector2i(9, 9), table, 20)
	if seq_a == seq_c:
		print("[E4] (8) uwaga: region (9,9) dał tę samą sekwencję co (2,5) (OK przy małej tabeli)")
	# Wszystkie wybory to prawidłowe enemy_id z tabeli.
	for eid in seq_a:
		_check(EnemyDB.enemy(StringName(eid)) != null, "spawn pick nieznany enemy_id: %s" % eid)
	print("[E4] (8) spawn table deterministyczny (ten sam seed -> ta sama lista) OK: %s" % str(seq_a.slice(0, 6)))


## Odtwarza dobór wrogów jak WorldSpawner: lokalny RNG(region_seed) -> ważony pick z tabeli.
func _simulate_picks(base: int, region: Vector2i, table: Array, n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldSpawner.region_seed(base, region)
	var out: Array = []
	for _i in n:
		out.append(String(_weighted_pick(rng, table)))
	return out


func _weighted_pick(rng: RandomNumberGenerator, table: Array) -> StringName:
	var total := 0.0
	for e in table:
		total += maxf(0.0, float((e as Dictionary).get("weight", 1.0)))
	if total <= 0.0:
		return &""
	var r := rng.randf() * total
	var acc := 0.0
	for e in table:
		acc += maxf(0.0, float((e as Dictionary).get("weight", 1.0)))
		if r < acc:
			return StringName((e as Dictionary).get("enemy_id", &""))
	return StringName((table[table.size() - 1] as Dictionary).get("enemy_id", &""))


# ---------------------------------------------------------------------------
#  (9) Telegraf wg threat_tier — elite/boss spawnuje HazardZone preview, trash nie
# ---------------------------------------------------------------------------
func _test_telegraph_by_threat_tier() -> void:
	# Elite (Brute) — po ai_attack powinien istnieć telegraf-preview pod tym samym rodzicem.
	var brute := Enemy.new()
	brute.configure_from_resource(EnemyDB.enemy(&"brute"))
	add_child(brute)
	var dummy := _make_dummy_target(Vector3(2.0, 0.0, 0.0))
	add_child(dummy)
	brute._face_dir = Vector3(1, 0, 0)
	brute.ai_attack(dummy)
	var elite_tz := _find_hazard_preview(self)
	_check(elite_tz != null, "elite (Brute) NIE pokazal telegrafu (HazardZone preview)")
	brute.queue_free()
	if elite_tz != null:
		elite_tz.queue_free()

	# Trash (Goblin) — nie powinien telegrafować.
	# Usuń ewentualne pozostałości telegrafów z poprzedniej fazy.
	await get_tree().process_frame
	var goblin := Enemy.new()
	goblin.configure_from_resource(EnemyDB.enemy(&"goblin"))
	add_child(goblin)
	var dummy2 := _make_dummy_target(Vector3(2.0, 0.0, 0.0))
	add_child(dummy2)
	goblin._face_dir = Vector3(1, 0, 0)
	goblin.ai_attack(dummy2)
	var trash_tz := _find_hazard_preview(self)
	_check(trash_tz == null, "trash (Goblin) NIE powinien telegrafowac, a pokazal HazardZone")
	goblin.queue_free()
	dummy.queue_free()
	dummy2.queue_free()
	if trash_tz != null:
		trash_tz.queue_free()
	print("[E4] (9) telegraf wg threat_tier (elite TAK / trash NIE) OK")


func _make_dummy_target(pos: Vector3) -> CharacterBody3D:
	var d := CharacterBody3D.new()
	d.add_to_group("player")
	d.position = pos
	return d


func _find_hazard_preview(root: Node) -> HazardZone:
	for c in root.get_children():
		if c is HazardZone and (c as HazardZone).preview and is_instance_valid(c):
			# Pomiń te oznaczone do zwolnienia (queue_free planowany).
			if not (c as HazardZone).is_queued_for_deletion():
				return c as HazardZone
	return null


# ---------------------------------------------------------------------------
# (10) distance_tier rośnie z dystansem + loot tier biomu dostępny
# ---------------------------------------------------------------------------
func _test_distance_tier_and_loot_tier() -> void:
	var t_near := _world.distance_tier(0.0, 0.0)
	var t_mid := _world.distance_tier(120.0, 0.0)
	var t_far := _world.distance_tier(400.0, 0.0)
	_check(t_near == 1, "distance_tier @spawn != 1 (jest %d)" % t_near)
	_check(t_mid > t_near, "distance_tier nie rosnie z dystansem (%d <= %d)" % [t_mid, t_near])
	_check(t_far >= t_mid, "distance_tier nie monotoniczny (%d < %d)" % [t_far, t_mid])
	_check(t_far <= VoxelWorld.DISTANCE_TIER_MAX, "distance_tier przekroczyl max")
	# Loot tier biomu czytelny i rosnący verdant<ember<frost.
	var lt_v: int = EnemyDB.biome(&"verdant").loot_tier
	var lt_e: int = EnemyDB.biome(&"emberwaste").loot_tier
	var lt_f: int = EnemyDB.biome(&"frosthelm").loot_tier
	_check(lt_v < lt_e and lt_e < lt_f, "loot_tier biomow nie rosnacy: %d/%d/%d" % [lt_v, lt_e, lt_f])
	print("[E4] (10) distance_tier + loot_tier biomow OK (dist %d/%d/%d, loot %d/%d/%d)" % [t_near, t_mid, t_far, lt_v, lt_e, lt_f])


# ---------------------------------------------------------------------------
# (11) BEHAWIORALNA weryfikacja loot_tier biomu (review #MAJOR)
#   loot_tier biomu MUSI realnie wpływać na drop, nie tylko być polem w .tres. Porównujemy
#   ROZKŁAD rzadkości realnych dropów (LootService.drop_for) między verdant (tier1, bonus 0)
#   a frosthelm (tier3, bonus 2) przy TYM SAMYM ilvl i tym samym seedzie startowym strumienia.
#   Frost (wyższy tier) powinien dać WYŻSZĄ średnią rzadkość. Gdyby loot_tier był martwy
#   (jak przed poprawką), obie średnie byłyby identyczne i test by FAILował.
# ---------------------------------------------------------------------------
func _test_biome_loot_tier_behaviour() -> void:
	if LootService == null or RNGService == null or EnemyDB == null:
		_check(false, "brak autoloadow do testu (11)")
		return
	var samples := 600
	var ilvl := 10            # identyczny dla obu biomow -> izolujemy WPLYW loot_tier na rzadkosc
	# Bonusy z BiomeResource.loot_tier (to samo wyliczenie co WorldSpawner: loot_tier-1).
	var bonus_v: int = maxi(0, EnemyDB.biome(&"verdant").loot_tier - 1)
	var bonus_f: int = maxi(0, EnemyDB.biome(&"frosthelm").loot_tier - 1)
	_check(bonus_f > bonus_v, "frosthelm bonus (%d) nie wiekszy od verdant (%d)" % [bonus_f, bonus_v])
	var avg_v := _avg_drop_rarity(&"verdant", bonus_v, ilvl, samples)
	var avg_f := _avg_drop_rarity(&"frosthelm", bonus_f, ilvl, samples)
	_check(avg_f > avg_v + EPS,
		"loot_tier biomu NIE wplywa na drop (martwe pole): srednia rzadkosc frost %.4f <= verdant %.4f" % [avg_f, avg_v])
	# Sanity: ilvl spawnera tez rosnie z loot_tier (dtier=1 -> verdant=2, frost=2+2*2=6).
	var ilvl_v := maxi(1, 1 * 2 + bonus_v * 2)
	var ilvl_f := maxi(1, 1 * 2 + bonus_f * 2)
	_check(ilvl_f > ilvl_v, "ilvl spawnera nie rosnie z loot_tier (%d <= %d)" % [ilvl_f, ilvl_v])
	print("[E4] (11) loot_tier biomu BEHAWIORALNIE OK (srednia rzadkosc verdant %.3f < frost %.3f; ilvl %d<%d)"
		% [avg_v, avg_f, ilvl_v, ilvl_f])


## Liczy srednia rzadkosc (indeks 0..5) realnych dropow itemowych dla atrapy wroga o danym biomie
## i premii loot_tier. Reseeduje strumien loot do tego samego seeda przed kazda seria — porownanie
## verdant vs frost jest wtedy uczciwe (ta sama sekwencja losowan, rozni je TYLKO premia tieru).
func _avg_drop_rarity(biome: StringName, tier_bonus: int, ilvl: int, n: int) -> float:
	RNGService.seed_session(0xBADA55)
	var dummy := Node.new()
	dummy.set_script(load("res://test/LootDummyEnemy.gd"))
	dummy.loot_ilvl = ilvl
	dummy.loot_biome = biome
	dummy.loot_tier_bonus = tier_bonus
	add_child(dummy)
	var sum := 0.0
	var cnt := 0
	for _i in n:
		var drops: Array = LootService.drop_for(dummy)
		for d in drops:
			if (d as Dictionary).get("kind", "") == "item":
				var inst: ItemInstance = (d as Dictionary).get("instance", null)
				if inst != null:
					sum += float(inst.rarity)
					cnt += 1
	dummy.queue_free()
	return sum / float(maxi(1, cnt))
