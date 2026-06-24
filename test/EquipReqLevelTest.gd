extends Node
## EquipReqLevelTest.gd — weryfikuje quick-win: req_level przy equip + honor authored max_sockets.
## Uruchomienie: godot --headless res://test/EquipReqLevelTest.tscn
##
##  (1) roll_item ustawia req_level skalujace z ilvl (maxi(1, ilvl - REQ_LEVEL_OFFSET)).
##  (2) round-trip req_level przez to_dict/from_dict; stary save bez klucza -> 1 (wsteczna zgodnosc).
##  (3) InventoryComponent ODRZUCA item ponad poziom nosiciela (equip -> null, slot pusty).
##  (4) InventoryComponent ZAKLADA item w zasiegu poziomu.
##  (5) equip_from_backpack: item za wysoki ZOSTAJE w plecaku (nie ginie).
##  (6) brak ustalonego poziomu -> brak progu (zaklada wszystko; wsteczna zgodnosc).
##  (7) _roll_sockets honoruje authored ItemResource.max_sockets (clamp ponizej tieru).
## Kod wyjscia: 0 = ALL OK, 1 = FAIL.

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[REQ] FAIL: %s" % msg)


## Item z danym req_level (do testow equip — bez przechodzenia przez roll_item).
func _item(req_level: int) -> ItemInstance:
	var it := ItemInstance.new()
	it.rarity = ItemResource.Rarity.UNCOMMON
	it.ilvl = 1
	it.req_level = req_level
	return it


func _ready() -> void:
	print("[REQ] === req_level / max_sockets test ===")
	if LootService == null:
		_check(false, "brak LootService")
		get_tree().quit(1)
		return

	# (1) roll_item ustawia req_level skalujace z ilvl.
	var lo: ItemInstance = LootService.roll_item(111, 1, &"verdant", ItemResource.Rarity.COMMON, ItemResource.Slot.WEAPON)
	var hi: ItemInstance = LootService.roll_item(222, 40, &"verdant", ItemResource.Rarity.COMMON, ItemResource.Slot.WEAPON)
	_check(lo != null and hi != null, "roll_item zwrocil null")
	if lo != null and hi != null:
		_check(lo.req_level == 1, "ilvl 1 powinno dac req_level 1 (jest %d)" % lo.req_level)
		_check(hi.req_level == maxi(1, 40 - LootService.REQ_LEVEL_OFFSET),
			"ilvl 40 zle skaluje req_level (jest %d, oczekiwane %d)" % [hi.req_level, maxi(1, 40 - LootService.REQ_LEVEL_OFFSET)])
		_check(hi.req_level > lo.req_level, "req_level nie rosnie z ilvl")

	# (2) round-trip req_level + stary save bez klucza.
	var rt := ItemInstance.from_dict(_item(17).to_dict())
	_check(rt.req_level == 17, "req_level nie przezyl to_dict/from_dict (jest %d)" % rt.req_level)
	var legacy := ItemInstance.from_dict({"base_id": "x", "ilvl": 5})   # brak klucza req_level
	_check(legacy.req_level == 1, "stary save bez req_level powinien dac 1 (jest %d)" % legacy.req_level)

	# (3) equip ODRZUCA item ponad poziom nosiciela.
	var inv := InventoryComponent.new()
	add_child(inv)            # inv._ready szuka brata LevelComponent — tu go nie ma, dlatego...
	inv.set_wearer_level(10)  # ...wstrzykujemy poziom wprost (test bez pelnego stacka).
	var over := _item(15)
	var prev := inv.equip(over, InventoryComponent.EquipSlot.WEAPON)
	_check(prev == null, "equip ponad poziom nie zwrocil null")
	_check(inv.get_equipped(InventoryComponent.EquipSlot.WEAPON) == null,
		"item za wysoki ZAlozyl sie mimo progu (slot niepusty)")

	# (4) equip ZAKLADA item w zasiegu poziomu.
	var ok_item := _item(10)
	inv.equip(ok_item, InventoryComponent.EquipSlot.WEAPON)
	_check(inv.get_equipped(InventoryComponent.EquipSlot.WEAPON) == ok_item,
		"item req_level==poziom NIE zalozyl sie (powinien)")

	# (5) equip_from_backpack: item za wysoki zostaje w plecaku (nie ginie).
	inv.add_to_backpack(_item(99))
	var bp_before := inv.backpack.size()
	var res := inv.equip_from_backpack(0, InventoryComponent.EquipSlot.HELM)
	_check(res == false, "equip_from_backpack ponad poziom powinien zwrocic false")
	_check(inv.backpack.size() == bp_before, "item za wysoki zniknal z plecaka (powinien zostac)")
	inv.queue_free()

	# (6) brak ustalonego poziomu -> brak progu (zaklada wszystko).
	var inv_nolvl := InventoryComponent.new()
	add_child(inv_nolvl)      # brak LevelComponent jako brata, brak override -> wearer_level() == -1
	_check(inv_nolvl.wearer_level() == -1, "bez poziomu wearer_level powinno byc -1 (jest %d)" % inv_nolvl.wearer_level())
	inv_nolvl.equip(_item(99), InventoryComponent.EquipSlot.WEAPON)
	_check(inv_nolvl.get_equipped(InventoryComponent.EquipSlot.WEAPON) != null,
		"bez ustalonego poziomu equip powinien przepuscic (wsteczna zgodnosc)")
	inv_nolvl.queue_free()

	# (7) _roll_sockets honoruje authored max_sockets (clamp ponizej tieru).
	# LEGENDARY ma w SOCKETS_BY_TIER staly 2 socket; wstrzykujemy ItemResource z max_sockets=0,
	# wiec rolled item z tym base_id MUSI miec 0 socketow. Bez base -> standardowo 2.
	if ItemDB != null:
		var capped := ItemResource.new()
		capped.id = &"_test_no_sockets"
		capped.slot = ItemResource.Slot.WEAPON
		capped.max_sockets = 0
		ItemDB.items[capped.id] = capped
		var with_base: ItemInstance = LootService.roll_item(
			777, 30, &"verdant", ItemResource.Rarity.LEGENDARY, ItemResource.Slot.WEAPON, capped.id)
		_check(with_base != null and with_base.sockets.size() == 0,
			"authored max_sockets=0 nie zclampowal socketow (jest %d)" % (with_base.sockets.size() if with_base != null else -1))
		var no_base: ItemInstance = LootService.roll_item(
			777, 30, &"verdant", ItemResource.Rarity.LEGENDARY, ItemResource.Slot.WEAPON)
		_check(no_base != null and no_base.sockets.size() == 2,
			"bez base LEGENDARY powinien miec 2 sockety (jest %d)" % (no_base.sockets.size() if no_base != null else -1))
		ItemDB.items.erase(capped.id)   # sprzatamy po sobie (nie zatruwamy innych testow)

	if _failures == 0:
		print("[REQ] ALL OK")
	else:
		printerr("[REQ] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
