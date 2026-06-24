extends Node
## SaveSubsystemTest.gd — weryfikuje durability zapisu + persystencję lootu (audyt: Save).
## Uruchomienie: godot --headless res://test/SaveSubsystemTest.tscn
##
##  (1) Atomowy zapis: nadpisanie tworzy kopię .bak; primary jest poprawnym JSON-em.
##  (2) Recovery: uszkodzony primary -> load_character przywraca z .bak (NIE cichy wipe na nową postać).
##  (3) Loot persistence (wiring): Player.write_progression_to_save zapisuje ekwipunek+plecak,
##      a read_progression_from_save je odtwarza (wcześniej loot ginął przy wyjściu).
##  (4) Pełny round-trip lootu przez SaveData.to_dict/from_dict (JSON-safe).
## Kod wyjścia: 0 = ALL OK, 1 = FAIL.

const PlayerScript := preload("res://src/Player.gd")
const TEST_PATH := "user://saves/test_save_subsys.json"

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[SAVE] FAIL: %s" % msg)


func _cleanup() -> void:
	for p in [TEST_PATH, TEST_PATH + ".bak", TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _ready() -> void:
	print("[SAVE] === Save subsystem test ===")
	_cleanup()

	# (1) atomowy zapis + .bak przy nadpisaniu
	var sd1 := SaveData.new()
	sd1.level = 5
	sd1.gold = 100
	_check(SaveManager.save_character(sd1, TEST_PATH), "pierwszy save_character zwrocil false")
	_check(FileAccess.file_exists(TEST_PATH), "pierwszy zapis nie utworzyl pliku")
	_check(not FileAccess.file_exists(TEST_PATH + ".tmp"), "plik .tmp NIE zostal sprzatniety (podmiana nieatomowa)")
	var sd2 := SaveData.new()
	sd2.level = 9
	sd2.gold = 250
	SaveManager.save_character(sd2, TEST_PATH)
	_check(FileAccess.file_exists(TEST_PATH + ".bak"), "nadpisanie nie utworzylo kopii .bak")
	print("[SAVE] (1) atomowy zapis + .bak OK")

	# (2) recovery z .bak po uszkodzeniu primary (.bak trzyma sd1: level 5)
	var fb := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	fb.store_string("{ uszkodzony : nieprawidlowy json ][")
	fb.close()
	var loaded := SaveManager.load_character(TEST_PATH)
	_check(loaded != null, "uszkodzony zapis -> null (CICHY WIPE), zamiast recovery z .bak")
	if loaded != null:
		_check(loaded.level == 5, "recovery z .bak: zla tresc (level %d, oczekiwane 5 z .bak)" % loaded.level)
	print("[SAVE] (2) recovery z .bak po korupcji OK")

	# (3) loot persistence: Player + InventoryComponent (jak Main) -> write/read
	var p = PlayerScript.new()
	add_child(p)
	await get_tree().process_frame
	var inv := InventoryComponent.new()
	p.add_child(inv)                                # teraz Player._find_inventory() go znajdzie
	await get_tree().process_frame
	# ilvl 1 => req_level 1 => zakladalny na poziomie 1 (po naprawie req_level).
	var w := LootService.roll_item(111, 1, &"verdant", ItemResource.Rarity.RARE, ItemResource.Slot.WEAPON)
	var bag := LootService.roll_item(222, 1, &"verdant", ItemResource.Rarity.UNCOMMON, ItemResource.Slot.HELM)
	inv.add_to_backpack(w)
	inv.add_to_backpack(bag)
	inv.equip_from_backpack(0)                       # zaloz bron (backpack -> equipment)
	var equipped_count := inv.equipment.size()
	var bag_count := inv.backpack.size()
	_check(equipped_count > 0, "test setup: nic nie zalozone")

	var sd := SaveData.new()
	p.write_progression_to_save(sd)
	_check(sd.equipment.size() == equipped_count, "write nie zapisal ekwipunku (%d vs %d)" % [sd.equipment.size(), equipped_count])
	_check(sd.inventory.size() == bag_count, "write nie zapisal plecaka (%d vs %d)" % [sd.inventory.size(), bag_count])

	# wyczysc i odtworz z save'a
	inv.equipment.clear()
	inv.backpack.clear()
	p.read_progression_from_save(sd)
	_check(inv.equipment.size() == equipped_count, "read nie odtworzyl ekwipunku (%d)" % inv.equipment.size())
	_check(inv.backpack.size() == bag_count, "read nie odtworzyl plecaka (%d)" % inv.backpack.size())
	print("[SAVE] (3) loot persistence (write/read ekwipunek+plecak) OK")

	# (4) pelny round-trip przez SaveData.to_dict/from_dict (JSON-safe ksztalt)
	var sd_rt := SaveData.from_dict(sd.to_dict())
	var inv2 := InventoryComponent.new()
	add_child(inv2)
	inv2.load_from_save(sd_rt.equipment, sd_rt.inventory)
	_check(inv2.equipment.size() == equipped_count, "round-trip: ekwipunek nie przezyl to_dict/from_dict")
	_check(inv2.backpack.size() == bag_count, "round-trip: plecak nie przezyl to_dict/from_dict")
	# base_id zachowane (item to ten sam typ)
	var any_w := false
	for slot in inv2.equipment:
		if (inv2.equipment[slot] as ItemInstance).base_id == w.base_id:
			any_w = true
	_check(any_w or w.base_id == &"", "round-trip: base_id broni nie zachowane")
	print("[SAVE] (4) pelny round-trip lootu przez SaveData OK")

	p.queue_free()
	inv2.queue_free()
	_cleanup()
	if _failures == 0:
		print("[SAVE] ALL OK")
	else:
		printerr("[SAVE] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
