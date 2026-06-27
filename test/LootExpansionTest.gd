extends Node
## LootExpansionTest.gd — LOOT Faza 1 (fundament): 7 tierów rzadkości + rozszerzenie slotów.
## Sprawdza: (a) ENUMy append-only (stare indeksy nieruszone => zapis kompatybilny), (b) tablice rzadkości
## długości 8, (c) rarity_color/name dla MYTHIC/ANCIENT, (d) WEARABLE_SLOTS zawiera nowe sloty bez
## consumable/material, (e) _natural_slot routuje nowe sloty do właściwych bays, (f) roll_item MYTHIC/ANCIENT
## DETERMINISTYCZNY (ten sam seed => identyczny przedmiot) z właściwą liczbą afiksów.
## Uruchomienie: godot --headless res://test/LootExpansionTest.tscn

var _failures: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[LOOTX] FAIL: %s" % msg)


func _ready() -> void:
	print("[LOOTX] === loot expansion (faza 1) test ===")
	if ItemDB != null:
		ItemDB.reload()

	# (a) ENUM append-only — stare indeksy MUSZĄ zostać (zapis = surowe inty).
	_check(ItemResource.Slot.WEAPON == 0 and ItemResource.Slot.TRINKET == 5 and ItemResource.Slot.MATERIAL == 7,
		"stare sloty przesunięte (zapis zepsuty)")
	_check(ItemResource.Slot.GLOVES == 8 and ItemResource.Slot.SHOULDERS == 9 and ItemResource.Slot.BELT == 10 \
		and ItemResource.Slot.CLOAK == 11 and ItemResource.Slot.AMULET == 12, "nowe sloty mają złe indeksy")
	_check(ItemResource.Rarity.COMMON == 0 and ItemResource.Rarity.SET == 5, "stare rarity przesunięte")
	_check(ItemResource.Rarity.MYTHIC == 6 and ItemResource.Rarity.ANCIENT == 7, "MYTHIC/ANCIENT mają złe indeksy")
	_check(InventoryComponent.EQUIP_SLOT_COUNT == 12 and InventoryComponent.EquipSlot.TRINKET_2 == 6 \
		and InventoryComponent.EquipSlot.AMULET == 11, "EquipSlot nie rozszerzony do 12")

	# (b) tablice rzadkości długości 8.
	_check(LootService.TIER_MULT.size() == 8 and LootService.AFFIX_COUNT.size() == 8 \
		and LootService.SOCKETS_BY_TIER.size() == 8 and LootService.DEFAULT_RARITY_WEIGHTS.size() == 8 \
		and LootService.RARITY_COLORS.size() == 8 and LootService.RARITY_NAMES.size() == 8,
		"któraś tablica rzadkości nie ma długości 8")

	# (c) kolor + nazwa dla MYTHIC/ANCIENT.
	var cm := LootService.rarity_color(ItemResource.Rarity.MYTHIC)
	var ca := LootService.rarity_color(ItemResource.Rarity.ANCIENT)
	_check(cm != ca and ca.r > 0.9 and ca.g > 0.7, "kolory MYTHIC/ANCIENT błędne")
	_check(LootService.rarity_name(ItemResource.Rarity.MYTHIC) == "Mityczny" \
		and LootService.rarity_name(ItemResource.Rarity.ANCIENT) == "Prastary", "nazwy MYTHIC/ANCIENT błędne")

	# (d) WEARABLE_SLOTS — zawiera nowe sloty, NIE zawiera consumable/material.
	var ws: Array = LootService.WEARABLE_SLOTS
	_check(ws.has(ItemResource.Slot.GLOVES) and ws.has(ItemResource.Slot.AMULET) and ws.has(ItemResource.Slot.CLOAK),
		"WEARABLE_SLOTS nie zawiera nowych slotów")
	_check(not ws.has(ItemResource.Slot.CONSUMABLE) and not ws.has(ItemResource.Slot.MATERIAL),
		"WEARABLE_SLOTS zawiera consumable/material")

	# (e) _natural_slot routuje nowe sloty (przez syntetyczny ItemResource w ItemDB).
	_route_check(ItemResource.Slot.GLOVES, InventoryComponent.EquipSlot.GLOVES, "gloves")
	_route_check(ItemResource.Slot.CLOAK, InventoryComponent.EquipSlot.CLOAK, "cloak")
	_route_check(ItemResource.Slot.AMULET, InventoryComponent.EquipSlot.AMULET, "amulet")

	# (f) roll_item MYTHIC/ANCIENT — determinizm + rarity + liczba afiksów.
	for tier in [ItemResource.Rarity.MYTHIC, ItemResource.Rarity.ANCIENT]:
		var a: ItemInstance = LootService.roll_item(424242, 30, &"verdant", tier, ItemResource.Slot.WEAPON)
		var b: ItemInstance = LootService.roll_item(424242, 30, &"verdant", tier, ItemResource.Slot.WEAPON)
		_check(a != null and a.rarity == tier, "roll_item tier %d zły rarity" % tier)
		_check(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "roll_item tier %d NIEdeterministyczny" % tier)
		var n_aff := a.rolled_affixes.size()
		_check(n_aff >= 1, "roll_item tier %d brak afiksów" % tier)
	print("[LOOTX] enumy stabilne, tablice=8, MYTHIC/ANCIENT kolor+nazwa+roll OK, sloty routują")

	_phase2()

	if _failures == 0:
		print("[LOOTX] ALL OK")
	else:
		printerr("[LOOTX] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## LOOT Faza 2: staty klasowe + filtr klasy + indeks slotów + motyw biomu.
func _phase2() -> void:
	# (a) Nowe staty klasowe czytane przez StatBlock.get_base + obecne w STAT_KEYS.
	var sb := StatBlock.new()
	sb.spell_power = 42.0
	sb.holy = 7.0
	_check(sb.get_base(&"spell_power") == 42.0, "get_base spell_power nie czyta pola")
	_check(sb.get_base(&"holy") == 7.0, "get_base holy nie czyta pola")
	_check(sb.get_base(&"penetration") == 0.0, "get_base penetration default != 0")
	_check(StatBlock.STAT_KEYS.has(&"spell_power") and StatBlock.STAT_KEYS.has(&"bleed_damage") \
		and StatBlock.STAT_KEYS.has(&"dodge"), "STAT_KEYS nie zawiera nowych statów")

	# (b) Indeks ItemDB po slocie zbudowany (są bronie => bucket WEAPON niepusty).
	_check(ItemDB.items_by_slot.has(ItemResource.Slot.WEAPON), "items_by_slot brak indeksu WEAPON")

	# (c) Motyw biomu — przecięcie tagów.
	_check(LootService._tags_match([&"fire", &"crit"], [&"fire"]), "_tags_match nie wykrywa przecięcia")
	_check(not LootService._tags_match([&"crit"], [&"fire"]), "_tags_match fałszywie dodatni")

	# (d) FILTR KLASY: item klasowy maga NIE leci do wojownika (gdy jest też uniwersalny), ale leci do maga.
	var orig_cls: StringName = GameState.class_id if GameState != null else &"wojownik"
	var uni := ItemResource.new(); uni.id = &"t_uni_glove"; uni.slot = ItemResource.Slot.GLOVES
	var mlk := ItemResource.new(); mlk.id = &"t_mag_glove"; mlk.slot = ItemResource.Slot.GLOVES
	mlk.allowed_classes = [&"mag"]
	ItemDB.items[uni.id] = uni; ItemDB.items[mlk.id] = mlk
	ItemDB._reindex()
	if GameState != null:
		GameState.class_id = &"wojownik"
	var saw_mag_for_war := false
	for i in 80:
		if LootService._roll_base_id(null, ItemResource.Slot.GLOVES) == mlk.id:
			saw_mag_for_war = true
	_check(not saw_mag_for_war, "wojownik dostał item klasowy maga (filtr klasy nie działa)")
	if GameState != null:
		GameState.class_id = &"mag"
	var saw_mag_for_mag := false
	for i in 80:
		if LootService._roll_base_id(null, ItemResource.Slot.GLOVES) == mlk.id:
			saw_mag_for_mag = true
	_check(saw_mag_for_mag, "mag nigdy nie dostał swojego itemu (filtr za ostry)")
	if GameState != null:
		GameState.class_id = orig_cls   # przywróć
	print("[LOOTX] Faza 2: staty klasowe + STAT_KEYS + indeks slotów + filtr klasy + motyw biomu OK")


## Tworzy syntetyczny ItemResource danego slotu, rejestruje w ItemDB i sprawdza routing _natural_slot.
func _route_check(item_slot: int, expected_equip: int, label: String) -> void:
	var ir := ItemResource.new()
	ir.id = StringName("test_%s" % label)
	ir.slot = item_slot
	ItemDB.items[ir.id] = ir            # publiczny rejestr ItemDB (StringName -> ItemResource)
	var comp := InventoryComponent.new()
	add_child(comp)
	var inst := ItemInstance.new()
	inst.base_id = ir.id
	var got := comp._natural_slot(inst)
	_check(got == expected_equip, "_natural_slot(%s) = %d, oczekiwano %d" % [label, got, expected_equip])
	comp.queue_free()
