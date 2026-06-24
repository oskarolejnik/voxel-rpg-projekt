extends Node
## Etap0Test.gd — mini-test HEADLESS Etapu 0 (DoD). NIE dotyka Player.gd ani dzialajacej gry.
## Uruchomienie: godot --headless res://test/Etap0Test.tscn
##
## Sprawdza:
##  (a) pipeline StatsComponent: StatBlock damage=18 + StatModifier(&"damage", INCREASED, 0.2)
##      -> get_stat(&"damage") == 21.6  (18 * 1.2). Print "[E0] damage=...".
##  (b) SaveManager round-trip POSTACI: zapis -> wczytaj -> porownanie pol. Print "[E0] save OK".
##  (c) NetManager stub: has_authority()==true (kontrakt SP).
## Na koniec ustawia kod wyjscia (0=OK / 1=FAIL) i wola get_tree().quit().

const EPS: float = 0.0001

var _failures: int = 0


func _ready() -> void:
	print("[E0] === Etap 0 mini-test start ===")
	_test_pipeline()
	_test_net_stub()
	_test_save_roundtrip()

	if _failures == 0:
		print("[E0] ALL OK")
	else:
		printerr("[E0] FAILURES: %d" % _failures)
	# Kod wyjscia dla CI/headless (0 = sukces).
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[E0] FAIL: %s" % msg)


# (a) PIPELINE DoD: 18 -> INCREASED 0.2 -> 21.6
func _test_pipeline() -> void:
	var stats := StatsComponent.new()
	var block := StatBlock.new()
	block.damage = 18.0
	stats.base = block
	add_child(stats)   # _ready() ustawi base/rebuild

	# Testowy item z modyfikatorem (TDD/ROADMAP: StatModifier(&"damage", INCREASED, 0.2)).
	var item := ItemInstance.new()
	item.base_id = &"test_blade"
	item.explicit_modifiers = [
		StatModifier.make(&"damage", StatModifier.Op.INCREASED, 0.2, [], &"gear", &"test_blade"),
	]
	# Etap 0: wstrzykujemy modyfikatory itemu wprost (w Etapie 1 zrobi to InventoryComponent provider).
	stats.add_modifiers(item.collect_modifiers())

	var dmg := stats.get_stat(&"damage")
	print("[E0] damage=%s (oczekiwane 21.6)" % str(dmg))
	_check(absf(dmg - 21.6) < EPS, "damage pipeline: %f != 21.6" % dmg)

	# Dodatkowy dowod pipeline'u: kolejnosc FLAT->INCREASED->MORE.
	# (18 + 2) * (1 + 0.2) * (1 + 0.5) = 20 * 1.2 * 1.5 = 36.0
	stats.add_modifiers([
		StatModifier.make(&"damage", StatModifier.Op.FLAT, 2.0),
		StatModifier.make(&"damage", StatModifier.Op.MORE, 0.5),
	])
	var dmg2 := stats.get_stat(&"damage")
	print("[E0] damage(flat+inc+more)=%s (oczekiwane 36.0)" % str(dmg2))
	_check(absf(dmg2 - 36.0) < EPS, "pipeline FLAT/INC/MORE: %f != 36.0" % dmg2)

	stats.queue_free()


# (c) NetManager stub SP
func _test_net_stub() -> void:
	_check(NetManager.has_authority() == true, "NetManager.has_authority() != true")
	_check(NetManager.is_host() == true, "NetManager.is_host() != true")
	_check(NetManager.local_peer_id() == 1, "NetManager.local_peer_id() != 1")
	print("[E0] net stub: has_authority=true, is_host=true, peer=1")


# (b) SaveManager round-trip POSTACI
func _test_save_roundtrip() -> void:
	var data := SaveData.new()
	data.char_name = "Berserker Testowy"
	data.class_id = &"wojownik"
	data.level = 7
	data.xp = 1234
	data.gold = 5000
	data.dust = 12
	data.essence = 3
	data.orbs = 1
	data.allocated_passives = [&"battle_fury", &"toughness"]
	data.equipped_skills = [&"basic_attack", &"whirlwind"]
	data.pet_id = &"goblin_pet"
	data.pet_stable = [&"goblin_pet", &"wolf"]

	var app := CharacterAppearance.new()
	app.class_id = &"wojownik"
	app.body_color = Color(0.6, 0.4, 0.3, 1.0)
	app.height_scale = 1.05
	data.appearance = app

	# Item w ekwipunku (round-trip ItemInstance + StatModifier wewnatrz).
	var blade := ItemInstance.new()
	blade.base_id = &"test_blade"
	blade.rarity = ItemResource.Rarity.RARE
	blade.ilvl = 12
	blade.seed = 987654
	blade.explicit_modifiers = [
		StatModifier.make(&"damage", StatModifier.Op.INCREASED, 0.2, [&"melee"], &"gear", &"test_blade"),
	]
	# Regresja (review MAJOR): StatModifier w rolled_affixes MUSI przetrwac round-trip save/load.
	# Wczesniej from_dict gubilo go po cichu (to_dict serializowal -> from_dict wczytywal surowo).
	blade.rolled_affixes = [
		StatModifier.make(&"crit_chance", StatModifier.Op.FLAT, 0.1, [&"crit"], &"gear", &"test_blade"),
	]
	data.inventory = [blade]
	data.equipment = { ItemResource.Slot.WEAPON: blade }

	var path := "user://saves/etap0_test_character.json"
	var ok := SaveManager.save_character(data, path)
	_check(ok, "save_character zwrocilo false")

	var loaded := SaveManager.load_character(path)
	_check(loaded != null, "load_character zwrocilo null")
	if loaded == null:
		return

	# Porownanie kluczowych pol (round-trip).
	_check(loaded.version == data.version, "version mismatch")
	_check(loaded.char_name == data.char_name, "char_name mismatch")
	_check(loaded.class_id == data.class_id, "class_id mismatch")
	_check(loaded.level == data.level, "level mismatch")
	_check(loaded.xp == data.xp, "xp mismatch")
	_check(loaded.gold == data.gold, "gold mismatch")
	_check(loaded.allocated_passives == data.allocated_passives, "allocated_passives mismatch")
	_check(loaded.equipped_skills == data.equipped_skills, "equipped_skills mismatch")
	_check(loaded.pet_stable == data.pet_stable, "pet_stable mismatch")
	_check(loaded.appearance != null, "appearance null po wczytaniu")
	if loaded.appearance != null:
		_check(loaded.appearance.class_id == app.class_id, "appearance.class_id mismatch")
		_check(absf(loaded.appearance.height_scale - app.height_scale) < EPS, "height_scale mismatch")

	# Item round-trip: instancja + jej modyfikator INCREASED 0.2.
	_check(loaded.inventory.size() == 1, "inventory size mismatch")
	if loaded.inventory.size() == 1 and loaded.inventory[0] is ItemInstance:
		var li: ItemInstance = loaded.inventory[0]
		_check(li.base_id == blade.base_id, "item base_id mismatch")
		_check(li.rarity == blade.rarity, "item rarity mismatch")
		_check(li.ilvl == blade.ilvl, "item ilvl mismatch")
		_check(li.seed == blade.seed, "item seed mismatch")
		# Po round-tripie: 1 explicit (damage INCREASED 0.2) + 1 rolled (crit_chance FLAT 0.1).
		var mods := li.collect_modifiers()
		_check(mods.size() == 2, "item modifiers count mismatch (oczekiwane 2: explicit+rolled)")
		# Znajdz po stat (kolejnosc: collect_modifiers daje najpierw explicit, potem rolled).
		var dmg_mod: StatModifier = null
		var crit_mod: StatModifier = null
		for m in mods:
			if m.stat == &"damage":
				dmg_mod = m
			elif m.stat == &"crit_chance":
				crit_mod = m
		_check(dmg_mod != null, "brak explicit damage mod po round-trip")
		if dmg_mod != null:
			_check(dmg_mod.op == StatModifier.Op.INCREASED, "item mod op mismatch")
			_check(absf(dmg_mod.value - 0.2) < EPS, "item mod value mismatch")
		# Regresja MAJOR: rolled StatModifier nie moze zniknac ani wrocic jako goly Dictionary.
		_check(crit_mod != null, "rolled_affixes StatModifier ZGUBIONY po round-trip (regresja)")
		if crit_mod != null:
			_check(crit_mod.op == StatModifier.Op.FLAT, "rolled mod op mismatch (op jako float? regresja)")
			_check(absf(crit_mod.value - 0.1) < EPS, "rolled mod value mismatch")

	# Dowod, ze wczytany item dziala w pipeline (18 -> 21.6) po round-tripie.
	if loaded.inventory.size() == 1 and loaded.inventory[0] is ItemInstance:
		var stats2 := StatsComponent.new()
		var b2 := StatBlock.new()
		b2.damage = 18.0
		stats2.base = b2
		add_child(stats2)
		stats2.add_modifiers((loaded.inventory[0] as ItemInstance).collect_modifiers())
		var d := stats2.get_stat(&"damage")
		_check(absf(d - 21.6) < EPS, "po round-trip damage %f != 21.6" % d)
		stats2.queue_free()

	if _failures == 0:
		print("[E0] save OK")
	else:
		print("[E0] save round-trip mial bledy (patrz wyzej)")
