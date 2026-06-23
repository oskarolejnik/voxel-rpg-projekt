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
##  (9) RANGED ALLY PET: oswojona bestia ranged celuje pociskiem we WROGA rozwiazanego przez AIComponent
##      (nie w niejednoznaczne _target/gracza). Pocisk leci ku wrogowi; mask == enemy_body (bit2), NIE
##      player_body (bit1). Pulapka latentna pod ranged-pety (dzis jedyny oswajalny goblin jest melee).
## (10) LOOT PIPELINE: oswajalna bestia DROPI tame_charm (LootService.drop_for) + TameSystem ZUZYWA
##      go z InventoryComponentu gracza (charm_peek/charm_provider), a NIE z licznika charm_count.
## Kod wyjscia: 0 = ALL OK, 1 = FAIL. Print "[E6] ..." + ALL OK + quit.

var _failures: int = 0


func _ready() -> void:
	print("[E6] === Etap 6 mini-test start ===")
	if EnemyDB != null:
		EnemyDB.reload()
	# (10) potrzebuje definicji tame_charm w ItemDB (drop_for buduje ItemInstance po base_id).
	if ItemDB != null:
		ItemDB.reload()

	# await miedzy testami: queue_free() leftover encji musi sie dokonczyc, inaczej martwe goblliny
	# zostaja w grupie "enemies" i mylą skan _nearest_enemy w kolejnym tescie (izolacja testow).
	_test_gate_level();              await _settle()
	_test_gate_hp();                 await _settle()
	_test_gate_no_item();            await _settle()
	_test_success_becomes_ally();    await _settle()
	_test_ally_targets_enemy_not_player(); await _settle()
	_test_ranged_pet_aims_at_enemy(); await _settle()
	_test_pet_scaling();             await _settle()
	_test_save_roundtrip();          await _settle()
	await _test_one_active_pet();    await _settle()
	_test_charm_drop_and_inventory_consume(); await _settle()

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
#  (9) Ranged ALLY pet celuje pociskiem we WROGA (nie w gracza)
# ---------------------------------------------------------------------------
## REGRESJA latentnej pulapki: ranged pet musi celowac we wroga rozwiazanego przez AIComponent, a nie
## w Enemy._target (ten dla peta bywa graczem — fallback _physics_process — albo atakujacym wrogiem —
## take_damage). Dzis jedyny oswajalny goblin jest melee, wiec budujemy RANGED+tameable bestie runtime.
func _test_ranged_pet_aims_at_enemy() -> void:
	var player := _make_player(5)
	player.global_position = Vector3.ZERO
	var tame := _player_tame(player)
	tame.charm_count = 1

	# "Oznacz ranged bestie jako oswajalna": rejestrujemy runtime EnemyResource w EnemyDB (bez .tres,
	# nie zanieczyszcza DB innych testow — reload() bylo tylko raz w _ready).
	var res := _ranged_tameable_resource()
	if EnemyDB != null:
		EnemyDB.enemies[res.id] = res

	# Pet (oswojona bestia ranged) tuz przy graczu (w ZERO+X).
	var pet := _make_enemy_from_res(res, Vector3(1, 0, 0), 0.2)  # <35% HP -> da sie oswoic
	_check(pet.ai_profile == &"ranged", "(9) testowa bestia nie jest ranged (jest '%s')" % pet.ai_profile)
	var ok := tame.try_tame(pet)
	_check(ok, "(9) nie udalo sie oswoic ranged bestii")
	_check(pet.allegiance == Enemy.Allegiance.ALLY, "(9) ranged bestia nie jest ALLY po oswojeniu")

	# Wrog-cel +Z od peta (gracz jest -X od peta) -> kierunki pet->wrog i pet->gracz sa ROZNE,
	# wiec test ROZROZNI czy pocisk celuje we wroga czy w gracza.
	var foe := _make_goblin(Vector3(1, 0, 6), 1.0)
	_check(foe.is_in_group("enemies"), "(9) wrog-cel nie w grupie enemies")

	# PULAPKA: ustawiamy _target peta na GRACZA (tak jak zrobilby fallback _physics_process). Poprawka
	# MUSI to zignorowac i wziac cel z AIComponent.
	pet.set_target(player)
	var ai := _ai_of(pet)
	_check(ai != null and ai.current_target() == foe,
		"(9) AIComponent.current_target nie wskazal wroga (wskazal %s)" % (ai.current_target() if ai != null else null))

	# Odpal spawn pocisku (jedyna sciezka ranged ataku). Policz pociski przed/po.
	var before := _all_projectiles().size()
	pet._spawn_projectile()
	var projectiles := _all_projectiles()
	_check(projectiles.size() == before + 1, "(9) ranged pet NIE zespawnowal pocisku (przed=%d, po=%d)" % [before, projectiles.size()])
	if projectiles.size() > before:
		var proj: Projectile = projectiles[projectiles.size() - 1]
		# (a) MASKA: teren|enemy_body (bit2) wlaczone; player_body (bit1) NIGDY (pet nie trafia gracza).
		_check((proj.collide_mask & (1 << 2)) != 0,
			"(9) pocisk peta nie ma maski enemy_body (bit2) (mask=%d)" % proj.collide_mask)
		_check((proj.collide_mask & (1 << 1)) == 0,
			"(9) pocisk peta MA maske player_body (bit1) -> moglby trafic gracza (mask=%d)" % proj.collide_mask)
		# (b) KIERUNEK: leci ku WROGOWI, nie ku graczowi. Liczymy na plaszczyznie XZ z origin pocisku.
		var origin := pet.global_position + Vector3(0.0, 1.0, 0.0)
		var to_foe := foe.global_position - origin; to_foe.y = 0.0
		var to_player := player.global_position - origin; to_player.y = 0.0
		var vel := proj._velocity; vel.y = 0.0
		var dot_foe := vel.normalized().dot(to_foe.normalized())
		var dot_player := vel.normalized().dot(to_player.normalized())
		_check(dot_foe > 0.9, "(9) pocisk peta NIE leci ku wrogowi (dot=%.2f)" % dot_foe)
		_check(dot_player < 0.5, "(9) pocisk peta leci ku GRACZOWI (dot=%.2f)" % dot_player)
		proj.queue_free()

	player.queue_free()
	pet.queue_free()
	foe.queue_free()
	if EnemyDB != null:
		EnemyDB.enemies.erase(res.id)
	print("[E6] (9) ranged ALLY pet celuje we WROGA (mask enemy_body, nie gracz) OK")


## Buduje runtime EnemyResource: ranged + tameable (StatBlock jak goblin: hp30/dmg8). Nie dotyka .tres.
func _ranged_tameable_resource() -> EnemyResource:
	var sb := StatBlock.new()
	sb.max_hp = 30.0
	sb.damage = 8.0
	sb.attack_speed = 0.833
	sb.move_speed = 3.5
	var res := EnemyResource.new()
	res.id = &"ranged_test"
	res.display_name = "Test Slinger"
	res.stats = sb
	res.ai_profile = &"ranged"
	res.threat_tier = &"trash"          # bez telegrafu (czysty test pocisku)
	res.tameable = true
	res.tame_difficulty_mult = 1.0      # oswojenie pewne przy spelnionych warunkach
	res.variant_meta = {
		"attack_windup": 0.35,
		"attack_range": 8.0,            # ranged: szerszy zasieg niz melee
		"attack_entry_delay": 0.35,
		"projectile_speed": 16.0,
	}
	return res


## Wrog z runtime EnemyResource (analog _make_goblin): konfiguruje, dodaje do drzewa, ustawia HP-ulamek.
func _make_enemy_from_res(res: EnemyResource, pos: Vector3, hp_fraction: float) -> Enemy:
	var e := Enemy.new()
	e.configure_from_resource(res)
	add_child(e)                        # _ready buduje komponenty (Stats/Health/AI/hitbox/hurtbox)
	e.global_position = pos
	if e._health != null:
		e._health.current_hp = e._health.max_hp() * hp_fraction
		e.hp = e._health.current_hp
	else:
		e.hp = e.max_hp * hp_fraction
	return e


## Wszystkie zywe Projectile w drzewie testu (pociski spawnuja sie jako dzieci rodzica peta == ten Node).
func _all_projectiles() -> Array:
	var out: Array = []
	for c in get_children():
		if c is Projectile and not c.is_queued_for_deletion():
			out.append(c)
	return out


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


# ---------------------------------------------------------------------------
#  (10) Loot pipeline: bestia DROPI tame_charm + TameSystem zuzywa go z EKWIPUNKU
# ---------------------------------------------------------------------------
func _test_charm_drop_and_inventory_consume() -> void:
	# --- (a) Oswajalna bestia (goblin) potrafi dropic tame_charm przez LootService.drop_for ---
	# configure_from_resource kopiuje goblin_loot.tres (item_drops: tame_charm) do enemy.loot_table.
	# Szansa per-drop = 0.5, wiec petla do ~60 prob praktycznie gwarantuje trafienie (P(miss)~1e-18).
	var beast := _make_goblin(Vector3(30, 0, 0), 1.0)
	var dropped_charm := false
	for _i in 60:
		for d in LootService.drop_for(beast):
			if (d as Dictionary).get("kind", "") == "item":
				var inst: ItemInstance = (d as Dictionary).get("instance", null)
				if inst != null and inst.base_id == TameSystem.TAME_CHARM_ITEM:
					dropped_charm = true
		if dropped_charm:
			break
	_check(dropped_charm, "(10) oswajalny goblin NIE dropnal tame_charm przez drop_for (item_drops martwe?)")
	beast.queue_free()

	# --- (b) charm_peek/charm_provider wpiete w InventoryComponent: oswojenie ZUZYWA charm z plecaka ---
	var player := _make_player(5)
	var tame := _player_tame(player)
	var inv := InventoryComponent.new()
	player.add_child(inv)
	# Wpiecie jak w Player.gd, ale na lokalny inv (stub testowy bez Main). charm_count=0 dowodzi,
	# ze zrodlem oswajacza jest EKWIPUNEK, nie licznik-fallback.
	tame.charm_peek = func() -> bool: return inv.has_item(TameSystem.TAME_CHARM_ITEM)
	tame.charm_provider = func() -> bool: return inv.consume_item(TameSystem.TAME_CHARM_ITEM)
	tame.charm_count = 0

	# Pusty plecak -> blokada no_item (peek widzi brak charma PRZED rzutem szansy).
	var reason := [&""]
	tame.tame_failed.connect(func(r: StringName) -> void: reason[0] = r)
	var goblin_empty := _make_goblin(player.global_position + Vector3(2, 0, 0), 0.2)
	_check(not tame.try_tame(goblin_empty), "(10) oswojenie udane mimo pustego plecaka (brak tame_charm)")
	_check(reason[0] == &"no_item", "(10) brak charma w plecaku -> reason != 'no_item' (jest '%s')" % reason[0])
	goblin_empty.queue_free()

	# Dorzucamy tame_charm do plecaka (jak pickup z LootDrop) i oswajamy ponownie.
	var charm := ItemInstance.new()
	charm.base_id = TameSystem.TAME_CHARM_ITEM
	inv.add_to_backpack(charm)
	_check(inv.count_item(TameSystem.TAME_CHARM_ITEM) == 1, "(10) setup: plecak nie ma 1 tame_charm")
	var goblin := _make_goblin(player.global_position + Vector3(2, 0, 0), 0.2)
	var ok := tame.try_tame(goblin)
	_check(ok, "(10) oswojenie nie udane mimo tame_charm w plecaku")
	_check(inv.count_item(TameSystem.TAME_CHARM_ITEM) == 0,
		"(10) tame_charm NIE zuzyty z plecaka (count=%d)" % inv.count_item(TameSystem.TAME_CHARM_ITEM))
	_check(tame.charm_count == 0, "(10) charm_count ruszony mimo zrodla z ekwipunku (=%d)" % tame.charm_count)
	_check(goblin.allegiance == Enemy.Allegiance.ALLY, "(10) goblin nie zostal petem po oswojeniu z plecaka")

	player.queue_free()
	if is_instance_valid(goblin):
		goblin.queue_free()
	print("[E6] (10) drop tame_charm + zuzycie z InventoryComponent OK")
