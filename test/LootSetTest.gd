extends Node
## LootSetTest.gd — weryfikuje naprawę: rolled SET items NADAJĄ bonusy setu (audyt rank #2).
## Uruchomienie: godot --headless res://test/LootSetTest.tscn
##
##  (1) 2 założone części tego samego setu -> bonus 2-cz. obecny w collect_modifiers (BEZ naprawy: brak).
##  (2) 1 część -> brak bonusu 2-cz.
##  (3) 4 części -> obecny też bonus 4-cz.
##  (4) roll_item(SET) zapamiętuje set_id na instancji.
##  (5) round-trip to_dict/from_dict zachowuje set_id.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL.

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[SET] FAIL: %s" % msg)


func _set_item(sid: StringName) -> ItemInstance:
	var it := ItemInstance.new()
	it.set_id = sid
	it.rarity = ItemResource.Rarity.SET
	return it


## Czy w zebranych modyfikatorach jest taki z danego setu i statu (bonus setu tagowany source_id=set).
func _has_set_mod(mods: Array, sid: StringName, stat: StringName) -> bool:
	for m in mods:
		if m is StatModifier and m.source_id == sid and m.stat == stat:
			return true
	return false


func _ready() -> void:
	print("[SET] === Loot set-bonus test ===")
	if ItemDB == null:
		_check(false, "brak ItemDB")
		get_tree().quit(1)
		return
	ItemDB.reload()
	# wall_defender: bonus 2-cz = armor INCREASED, 4-cz = max_hp MORE (data/db/sets/wall_defender.tres).
	var SID := &"wall_defender"

	# (1) 2 części -> bonus 2-cz.
	var inv2 := InventoryComponent.new()
	add_child(inv2)
	inv2.equipment[InventoryComponent.EquipSlot.HELM] = _set_item(SID)
	inv2.equipment[InventoryComponent.EquipSlot.CHEST] = _set_item(SID)
	var m2 := inv2.collect_modifiers()
	_check(_has_set_mod(m2, SID, &"armor"), "2 części setu NIE dają bonusu 2-cz (armor) — naprawa nie działa")

	# (2) 1 część -> brak bonusu 2-cz.
	var inv1 := InventoryComponent.new()
	add_child(inv1)
	inv1.equipment[InventoryComponent.EquipSlot.HELM] = _set_item(SID)
	var m1 := inv1.collect_modifiers()
	_check(not _has_set_mod(m1, SID, &"armor"), "1 część setu NIE powinna dawać bonusu 2-cz")

	# (3) 4 części -> bonus 4-cz (max_hp) też obecny.
	var inv4 := InventoryComponent.new()
	add_child(inv4)
	inv4.equipment[InventoryComponent.EquipSlot.HELM] = _set_item(SID)
	inv4.equipment[InventoryComponent.EquipSlot.CHEST] = _set_item(SID)
	inv4.equipment[InventoryComponent.EquipSlot.LEGS] = _set_item(SID)
	inv4.equipment[InventoryComponent.EquipSlot.BOOTS] = _set_item(SID)
	var m4 := inv4.collect_modifiers()
	_check(_has_set_mod(m4, SID, &"armor"), "4 części: brak bonusu 2-cz (armor)")
	_check(_has_set_mod(m4, SID, &"max_hp"), "4 części: brak bonusu 4-cz (max_hp)")

	# (4) roll_item(SET) zapamiętuje set_id (jeśli są zdefiniowane sety).
	if LootService != null:
		var rolled: ItemInstance = LootService.roll_item(12345, 10, &"verdant", ItemResource.Rarity.SET, ItemResource.Slot.CHEST)
		_check(rolled != null, "roll_item zwrócił null")
		if rolled != null:
			_check(rolled.set_id != &"", "roll_item(SET) nie ustawił set_id (jest pusty)")

	# (5) round-trip set_id przez to_dict/from_dict.
	var rt := ItemInstance.from_dict(_set_item(SID).to_dict())
	_check(rt.set_id == SID, "set_id nie przeżył to_dict/from_dict (jest '%s')" % rt.set_id)

	inv1.queue_free()
	inv2.queue_free()
	inv4.queue_free()
	if _failures == 0:
		print("[SET] ALL OK")
	else:
		printerr("[SET] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
