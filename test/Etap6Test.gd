extends Node
## Etap6Test.gd — mini-test HEADLESS Etapu 6 (DoD: oswojona bestia walczy u boku gracza i skaluje
## sie z graczem). Uruchomienie: godot --headless res://test/Etap6Test.tscn
##
## Sprawdza DoD Etapu 6 (ROADMAP 6 / GDD 9 / TDD 7.4):
##  (1) GATE lvl<5 blokuje oswojenie (cel <35% HP, item jest) -> false + tame_failed(&"level").
##  (2) GATE HP>=35% blokuje (lvl 5, item jest) -> false + tame_failed(&"hp").
##  (3) Brak item-oswajacza blokuje (lvl 5, HP<35%) -> false + tame_failed(&"no_item").
##  (4) SUKCES (lvl 5, HP<35%, item) -> true; cel: allegiance==ALLY, grupa "pets", NIE "enemies",
##      collision_layer == player_body.
##  (5) ALLY namierza WROGA, nie gracza: AIComponent._resolve_target zwraca wroga; pet hitbox ma
##      mask == enemy_body (nie player_body) -> nie moze trafic gracza; tick -> CHASE/ATTACK na wroga.
##  (6) Pet SKALUJE sie wg pet_damage/pet_hp gracza (damage/max_hp peta * mnozniki gracza).
##  (7) SAVE round-trip: pet_id przez to_dict/from_dict; load_pet_from_save odtwarza ALLY tego typu.
##  (8) 1 AKTYWNY PET: drugie oswojenie zastepuje pierwszego (stary znika, typ w stajni).
## Kod wyjscia: 0 = ALL OK, 1 = FAIL. Print "[E6] ..." + ALL OK + quit.

var _failures: int = 0


func _ready() -> void:
	print("[E6] === Etap 6 mini-test start ===")
	if EnemyDB != null:
		EnemyDB.reload()

	# await miedzy testami: queue_free() leftover encji musi sie dokonczyc, inaczej martwe goblliny
	# zostaja w grupie "enemies" i mylą skan _nearest_enemy w kolejnym tescie (izolacja testow).
	_test_gate_level();              await _settle()
	_test_gate_hp();                 await _settle()
	_test_gate_no_item();            await _settle()
	_test_success_becomes_ally();    await _settle()
	_test_ally_targets_enemy_not_player(); await _settle()
	_test_pet_scaling();             await _settle()
	_test_save_roundtrip();          await _settle()
	await _test_one_active_pet();    await _settle()

	# Settle: pozwol deferred queue_free dokonczyc sie przed quit (free Enemy/komponentow).
	for _f in 6:
		await get_tree().process_frame

	if _failures == 0:
		print("[E6] ALL OK")
	else:
		printerr("[E6] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[E6] FAIL: %s" % msg)


## Pozwala dokonczyc queue_free() encji z poprzedniego testu (izolacja grupy "enemies"/"pets").
func _settle() -> void:
	for _f in 3:
		await get_tree().process_frame


# ---------------------------------------------------------------------------
#  Pomocniki budowy sceny testowej (gracz-stub + tame + wrog)
# ---------------------------------------------------------------------------

## Buduje minimalny "stos gracza": Node3D + LevelComponent + StatsComponent (z pet_*), TameSystem.
## level -> poziom gracza; pet_damage/pet_hp -> mnozniki skalowania peta.
func _make_player(level: int, pet_damage: float = 0.0, pet_hp: float = 0.0) -> Node3D:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)

	var lvl := LevelComponent.new()
	player.add_child(lvl)
	lvl.load_from(level, 0)

	var stats := StatsComponent.new()
	var sb := StatBlock.new()
	sb.pet_damage = pet_damage
	sb.pet_hp = pet_hp
	stats.base = sb
	player.add_child(stats)

	var tame := TameSystem.new()
	player.add_child(tame)
	tame.setup(player, lvl, stats)
	return player


func _player_tame(player: Node3D) -> TameSystem:
	for c in player.get_children():
		if c is TameSystem:
			return c as TameSystem
	return null


## Spawnuje goblina (oswajalnego) przy pozycji. hp_fraction ustawia HP wzgledem max (po _ready).
func _make_goblin(pos: Vector3, hp_fraction: float) -> Enemy:
	var e := Enemy.new()
	var res: EnemyResource = EnemyDB.enemy(&"goblin") if EnemyDB != null else null
	if res != null:
		e.configure_from_resource(res)
	add_child(e)                       # _ready buduje komponenty (Stats/Health/AI/hitbox/hurtbox)
	e.global_position = pos
	# Ustaw HP przez HealthComponent (jedno zrodlo) na ulamek maxa.
	if e._health != null:
		e._health.current_hp = e._health.max_hp() * hp_fraction
		e.hp = e._health.current_hp
	else:
		e.hp = e.max_hp * hp_fraction
	return e


# ---------------------------------------------------------------------------
#  (1) Gate lvl < 5 blokuje
# ---------------------------------------------------------------------------
func _test_gate_level() -> void:
	var player := _make_player(4)
	var tame := _player_tame(player)
	tame.charm_count = 1
	var goblin := _make_goblin(player.global_position + Vector3(2, 0, 0), 0.2)  # <35% HP

	var reason := [&""]
	tame.tame_failed.connect(func(r: StringName) -> void: reason[0] = r)
	var ok := tame.try_tame(goblin)

	_check(not ok, "(1) oswojenie udane mimo lvl 4 (powinno byc zablokowane)")
	_check(reason[0] == &"level", "(1) tame_failed reason != 'level' (jest '%s')" % reason[0])
	_check(goblin.allegiance == Enemy.Allegiance.HOSTILE, "(1) goblin zmienil allegiance mimo blokady")
	_check(goblin.is_in_group("enemies"), "(1) goblin wypadl z grupy enemies mimo blokady")

	player.queue_free()
	goblin.queue_free()
	print("[E6] (1) gate lvl<5 blokuje oswojenie OK")


# ---------------------------------------------------------------------------
#  (2) Gate HP >= 35% blokuje
# ---------------------------------------------------------------------------
func _test_gate_hp() -> void:
	var player := _make_player(5)
	var tame := _player_tame(player)
	tame.charm_count = 1
	var goblin := _make_goblin(player.global_position + Vector3(2, 0, 0), 0.5)  # 50% HP -> za duzo

	var reason := [&""]
	tame.tame_failed.connect(func(r: StringName) -> void: reason[0] = r)
	var ok := tame.try_tame(goblin)

	_check(not ok, "(2) oswojenie udane mimo HP 50% (powinno byc zablokowane)")
	_check(reason[0] == &"hp", "(2) tame_failed reason != 'hp' (jest '%s')" % reason[0])
	_check(goblin.allegiance == Enemy.Allegiance.HOSTILE, "(2) goblin stal sie petem mimo HP>=35%")

	player.queue_free()
	goblin.queue_free()
	print("[E6] (2) cel HP>=35%% blokuje oswojenie OK")


# ---------------------------------------------------------------------------
#  (3) Brak itemu blokuje
# ---------------------------------------------------------------------------
func _test_gate_no_item() -> void:
	var player := _make_player(5)
	var tame := _player_tame(player)
	tame.charm_count = 0               # brak item-oswajacza
	var goblin := _make_goblin(player.global_position + Vector3(2, 0, 0), 0.2)

	var reason := [&""]
	tame.tame_failed.connect(func(r: StringName) -> void: reason[0] = r)
	var ok := tame.try_tame(goblin)

	_check(not ok, "(3) oswojenie udane bez item-oswajacza")
	_check(reason[0] == &"no_item", "(3) tame_failed reason != 'no_item' (jest '%s')" % reason[0])
	_check(goblin.allegiance == Enemy.Allegiance.HOSTILE, "(3) goblin stal sie petem bez itemu")

	player.queue_free()
	goblin.queue_free()
	print("[E6] (3) brak item-oswajacza blokuje OK")


# ---------------------------------------------------------------------------
#  (4) Sukces -> ALLY
# ---------------------------------------------------------------------------
func _test_success_becomes_ally() -> void:
	var player := _make_player(5)
	var tame := _player_tame(player)
	tame.charm_count = 1
	var goblin := _make_goblin(player.global_position + Vector3(2, 0, 0), 0.2)

	var changed := [&""]
	tame.pet_changed.connect(func(pid: StringName) -> void: changed[0] = pid)
	var ok := tame.try_tame(goblin)

	_check(ok, "(4) oswojenie NIE udane mimo spelnionych warunkow (lvl5, HP20%, item)")
	_check(goblin.allegiance == Enemy.Allegiance.ALLY, "(4) goblin nie jest ALLY po oswojeniu")
	_check(goblin.is_in_group("pets"), "(4) pet nie w grupie 'pets'")
	_check(not goblin.is_in_group("enemies"), "(4) pet nadal w grupie 'enemies' (psuje loot/licznik)")
	_check(goblin.collision_layer == (1 << 1), "(4) pet collision_layer != player_body (jest %d)" % goblin.collision_layer)
	_check(changed[0] == &"goblin", "(4) pet_changed nie niesie pet_id 'goblin' (jest '%s')" % changed[0])
	_check(tame.charm_count == 0, "(4) item-oswajacz nie zuzyty (charm_count=%d)" % tame.charm_count)
	_check(tame.active_pet() == goblin, "(4) active_pet != oswojony goblin")

	player.queue_free()
	goblin.queue_free()
	print("[E6] (4) sukces: bestia staje sie ALLY petem OK")


# ---------------------------------------------------------------------------
#  (5) ALLY namierza WROGA, nie gracza
# ---------------------------------------------------------------------------
func _test_ally_targets_enemy_not_player() -> void:
	var player := _make_player(5)
	player.global_position = Vector3.ZERO
	var tame := _player_tame(player)
	tame.charm_count = 1

	# Pet (oswojony goblin) tuz przy graczu.
	var pet := _make_goblin(Vector3(1, 0, 0), 0.2)
	var ok := tame.try_tame(pet)
	_check(ok, "(5) nie udalo sie oswoic peta do testu targetowania")

	# Wrog-cel w zasiegu aggro peta (PET_AGGRO_RADIUS=14), w grupie "enemies".
	var foe := _make_goblin(Vector3(4, 0, 0), 1.0)
	_check(foe.is_in_group("enemies"), "(5) wrog-cel nie w grupie enemies")
	_check(pet.allegiance == Enemy.Allegiance.ALLY, "(5) pet nie jest ALLY")

	# AIComponent peta: _resolve_target powinien zwrocic WROGA (foe), nie gracza.
	var ai := _ai_of(pet)
	_check(ai != null, "(5) pet nie ma AIComponent")
	if ai != null:
		var resolved: Node3D = ai._resolve_target(pet.global_position)
		_check(resolved == foe, "(5) pet _resolve_target nie wskazal wroga (wskazal %s)" % resolved)
		_check(resolved != player, "(5) pet namierzyl GRACZA zamiast wroga")
		# Tick kilka klatek: FOLLOW -> CHASE (wrog w zasiegu).
		var state := AIComponent.State.FOLLOW
		for _i in 5:
			state = ai.tick(0.1) as AIComponent.State
		_check(state == AIComponent.State.CHASE or state == AIComponent.State.ATTACK,
			"(5) pet nie wszedl w CHASE/ATTACK na wroga (stan=%d)" % state)

	# WARSTWY: hitbox peta bije WROGOW (mask enemy_body=bit2), nie gracza (player_body=bit1).
	_check(pet._hitbox != null, "(5) pet nie ma hitboxa")
	if pet._hitbox != null:
		_check(pet._hitbox.collision_mask == (1 << 2),
			"(5) pet hitbox mask != enemy_body (jest %d) -> moglby bic gracza" % pet._hitbox.collision_mask)
		_check(pet._hitbox.collision_layer == (1 << 3),
			"(5) pet hitbox layer != player_hitbox (jest %d)" % pet._hitbox.collision_layer)
	# HURTBOX peta na warstwie gracza (bity przez wrogow, nie przez gracza/sojusznikow).
	_check(pet._hurtbox != null and pet._hurtbox.collision_layer == (1 << 1),
		"(5) pet hurtbox nie na warstwie player_body")

	player.queue_free()
	pet.queue_free()
	foe.queue_free()
	print("[E6] (5) ALLY namierza WROGA (nie gracza) + warstwy hitboxa OK")


func _ai_of(e: Enemy) -> AIComponent:
	for c in e.get_children():
		if c is AIComponent:
			return c as AIComponent
	return null


# ---------------------------------------------------------------------------
#  (6) Pet skaluje sie wg pet_damage/pet_hp gracza
# ---------------------------------------------------------------------------
func _test_pet_scaling() -> void:
	# Baza goblina: damage 8, max_hp 30. Gracz: pet_damage=0.5 (+50%), pet_hp=1.0 (+100%).
	var player := _make_player(5, 0.5, 1.0)
	var tame := _player_tame(player)
	tame.charm_count = 1
	var goblin := _make_goblin(player.global_position + Vector3(2, 0, 0), 0.2)

	var base_dmg: float = goblin._stats.get_stat(&"damage")
	var base_hp: float = goblin._health.max_hp()
	_check(absf(base_dmg - 8.0) < 0.01, "(6) baza damage goblina != 8 (jest %s)" % base_dmg)
	_check(absf(base_hp - 30.0) < 0.01, "(6) baza max_hp goblina != 30 (jest %s)" % base_hp)

	var ok := tame.try_tame(goblin)
	_check(ok, "(6) oswojenie do testu skalowania nie udane")

	var scaled_dmg: float = goblin._stats.get_stat(&"damage")
	var scaled_hp: float = goblin._health.max_hp()
	_check(absf(scaled_dmg - 12.0) < 0.01, "(6) pet damage != 8*1.5=12 (jest %s)" % scaled_dmg)
	_check(absf(scaled_hp - 60.0) < 0.01, "(6) pet max_hp != 30*2.0=60 (jest %s)" % scaled_hp)
	_check(absf(goblin._health.current_hp - scaled_hp) < 0.01,
		"(6) pet nie pelny po skalowaniu (current %s != max %s)" % [goblin._health.current_hp, scaled_hp])
	# Skalowanie zalezy od gracza: silniejszy gracz => silniejszy pet.
	_check(scaled_dmg > base_dmg and scaled_hp > base_hp, "(6) pet nie wzmocniony przez staty gracza")

	player.queue_free()
	goblin.queue_free()
	print("[E6] (6) pet skaluje sie (dmg 8->%.0f, hp 30->%.0f) OK" % [scaled_dmg, scaled_hp])


# ---------------------------------------------------------------------------
#  (7) Save round-trip pet_id + odtworzenie ALLY
# ---------------------------------------------------------------------------
func _test_save_roundtrip() -> void:
	# Round-trip czystego SaveData (pet_id + stajnia).
	var sd := SaveData.new()
	sd.pet_id = &"goblin"
	sd.pet_stable = [&"goblin"] as Array[StringName]
	var d := sd.to_dict()
	var sd2 := SaveData.from_dict(d)
	_check(sd2.pet_id == &"goblin", "(7) pet_id nie przetrwal round-trip (jest '%s')" % sd2.pet_id)
	_check(sd2.pet_stable.size() == 1 and sd2.pet_stable[0] == &"goblin",
		"(7) pet_stable nie przetrwal round-trip (%s)" % str(sd2.pet_stable))

	# load_pet_from_save odtwarza Enemy ALLY tego typu przy graczu.
	var player := _make_player(5)
	var tame := _player_tame(player)
	tame.load_pet_from_save(sd2)
	var pet := tame.active_pet()
	_check(pet != null, "(7) load_pet_from_save NIE odtworzyl peta")
	if pet != null:
		_check((pet as Enemy).allegiance == Enemy.Allegiance.ALLY, "(7) odtworzony pet nie jest ALLY")
		_check(StringName((pet as Enemy).variant_id) == &"goblin", "(7) odtworzony pet zlego typu")
		_check((pet as Enemy).is_in_group("pets"), "(7) odtworzony pet nie w grupie pets")

	# write_pet_to_save odwzorowuje aktywny typ z powrotem.
	var sd3 := SaveData.new()
	tame.write_pet_to_save(sd3)
	_check(sd3.pet_id == &"goblin", "(7) write_pet_to_save nie zapisal aktywnego peta (jest '%s')" % sd3.pet_id)

	player.queue_free()
	print("[E6] (7) save round-trip pet_id + odtworzenie ALLY OK")


# ---------------------------------------------------------------------------
#  (8) 1 aktywny pet — drugie oswojenie zastepuje pierwszego
# ---------------------------------------------------------------------------
func _test_one_active_pet() -> void:
	var player := _make_player(5)
	var tame := _player_tame(player)
	tame.charm_count = 2
	var g1 := _make_goblin(player.global_position + Vector3(2, 0, 0), 0.2)
	var g2 := _make_goblin(player.global_position + Vector3(-2, 0, 0), 0.2)

	_check(tame.try_tame(g1), "(8) pierwsze oswojenie nie udane")
	_check(tame.active_pet() == g1, "(8) aktywny pet != g1 po pierwszym oswojeniu")
	_check(tame.try_tame(g2), "(8) drugie oswojenie nie udane")
	_check(tame.active_pet() == g2, "(8) drugi pet nie zastapil pierwszego (active != g2)")
	# g1 powinien zostac zwolniony (queue_free) — zastapiony.
	await get_tree().process_frame
	_check(not is_instance_valid(g1) or g1.is_queued_for_deletion(),
		"(8) stary pet (g1) NIE usuniety po nowym oswojeniu (>1 aktywny pet)")
	# Stajnia trzyma oba typy oswojone (tu obie 'goblin' -> jeden wpis).
	_check(tame.stable().has(&"goblin"), "(8) stajnia nie zawiera oswojonego typu")

	player.queue_free()
	if is_instance_valid(g2):
		g2.queue_free()
	print("[E6] (8) 1 aktywny pet (zamiana przy nowym oswojeniu) OK")
