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
	# Lockstep UI: etykiety slotów MUSZĄ mieć tyle wpisów co EQUIP_SLOT_COUNT (inaczej crash przy nowych slotach).
	_check(InventoryUI.EQUIP_LABELS.size() == InventoryComponent.EQUIP_SLOT_COUNT,
		"EQUIP_LABELS (%d) != EQUIP_SLOT_COUNT (%d)" % [InventoryUI.EQUIP_LABELS.size(), InventoryComponent.EQUIP_SLOT_COUNT])

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
	_phase4()

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


## LOOT Faza 4: efekty wyposażenia (procy) — EffectResource + collect_effects + host-only EffectComponent.
## Sprawdza: (a) Trigger enum append-only, (b) ember_heart.tres wczytany z proc'iem (serializacja .tres),
## (c) collect_effects zbiera proc z założonego itemu, (d) ON_HIT (chance=1.0) nakłada burn na cel,
## (e) cooldown blokuje natychmiastowe powtórzenie, (f) ON_CRIT odpala TYLKO na krytyku,
## (g) bramka autorytetu — na kliencie (nie-host) proc to no-op.
func _phase4() -> void:
	# (a) Trigger enum append-only (.tres zapisuje trigger jako surowy int => reorder = ciche przemapowanie).
	_check(EffectResource.Trigger.ON_HIT == 0 and EffectResource.Trigger.ON_CRIT == 1 \
		and EffectResource.Trigger.ON_KILL == 2, "EffectResource.Trigger indeksy przestawione")

	# (b) ember_heart.tres wczytany z proc'iem => serializacja Array[EffectResource] w .tres działa.
	var emb := ItemDB.item(&"ember_heart")
	_check(emb != null, "ember_heart.tres nie wczytany")
	if emb != null:
		_check(emb.equip_effects.size() == 1 and emb.equip_effects[0] is EffectResource,
			"ember_heart nie ma equip_effects")
		if emb.equip_effects.size() == 1:
			var pe: EffectResource = emb.equip_effects[0]
			_check(pe.payload == &"burn" and pe.trigger == EffectResource.Trigger.ON_HIT,
				"ember_heart proc ma zły payload/trigger")

	# (c) collect_effects() zbiera proc z założonego itemu.
	var owner_c0 := _mk_entity()
	var inv0 := _mk_inv_on(owner_c0, &"t_proc_item", _mk_effect(EffectResource.Trigger.ON_HIT, &"burn", 1.0, 0.0))
	var got := inv0.collect_effects()
	_check(got.size() == 1 and got[0].payload == &"burn", "collect_effects nie zebrał proc'a")

	# (d) EffectComponent: ON_HIT (chance=1.0) => burn na celu.
	var owner_a := _mk_entity()
	var ia := _mk_inv_on(owner_a, &"t_hit", _mk_effect(EffectResource.Trigger.ON_HIT, &"burn", 1.0, 60.0))
	_mk_effect_comp(owner_a, ia)
	var ta := _mk_target()
	DamageService.hit_resolved.emit(owner_a, ta, 10.0, false)
	_check(_target_has_burn(ta), "ON_HIT proc nie nałożył burn na cel")
	# (e) cooldown blokuje natychmiastowe powtórzenie (drugi cel nie dostaje burn).
	var tb := _mk_target()
	DamageService.hit_resolved.emit(owner_a, tb, 10.0, false)
	_check(not _target_has_burn(tb), "cooldown nie zablokował drugiego proc'a")

	# (f) ON_CRIT: nie odpala na nie-krytyku, odpala na krytyku.
	var owner_cr := _mk_entity()
	var icr := _mk_inv_on(owner_cr, &"t_crit", _mk_effect(EffectResource.Trigger.ON_CRIT, &"burn", 1.0, 0.0))
	_mk_effect_comp(owner_cr, icr)
	var tc := _mk_target()
	DamageService.hit_resolved.emit(owner_cr, tc, 10.0, false)   # nie-krytyk
	_check(not _target_has_burn(tc), "ON_CRIT odpalił na nie-krytyku")
	DamageService.hit_resolved.emit(owner_cr, tc, 10.0, true)    # krytyk
	_check(_target_has_burn(tc), "ON_CRIT nie odpalił na krytyku")

	# (g) BRAMKA AUTORYTETU: na kliencie (nie-host) proc to no-op (skutek przyjdzie przez replikację).
	var owner_g := _mk_entity()
	var ig := _mk_inv_on(owner_g, &"t_gate", _mk_effect(EffectResource.Trigger.ON_HIT, &"burn", 1.0, 0.0))
	_mk_effect_comp(owner_g, ig)
	var tg := _mk_target()
	var prev_mode: int = NetManager.mode
	NetManager.mode = NetManager.Mode.CLIENT
	DamageService.hit_resolved.emit(owner_g, tg, 10.0, false)
	NetManager.mode = prev_mode
	_check(not _target_has_burn(tg), "proc odpalił na NIE-autorytecie (klient) — bramka nie działa")

	print("[LOOTX] Faza 4: EffectResource + .tres + collect_effects + ON_HIT/ON_CRIT + cooldown + bramka autorytetu OK")


# ── Faza 4 — pomocnicze ──────────────────────────────────────────────────────
func _mk_effect(trigger: int, payload: StringName, chance: float, cooldown: float) -> EffectResource:
	var e := EffectResource.new()
	e.trigger = trigger
	e.payload = payload
	e.chance = chance
	e.cooldown = cooldown
	e.magnitude = 5.0
	e.duration = 3.0
	return e


func _mk_entity() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	return n


## Rejestruje syntetyczną definicję z equip_effects w ItemDB i zakłada jej instancję w slot WEAPON.
func _mk_inv_on(owner_node: Node, base_id: StringName, eff: EffectResource) -> InventoryComponent:
	var ir := ItemResource.new()
	ir.id = base_id
	ir.slot = ItemResource.Slot.WEAPON
	var arr: Array[EffectResource] = [eff]
	ir.equip_effects = arr
	ItemDB.items[base_id] = ir
	ItemDB._reindex()
	var inv := InventoryComponent.new()
	owner_node.add_child(inv)
	var inst := ItemInstance.new()
	inst.base_id = base_id
	inv.equipment[InventoryComponent.EquipSlot.WEAPON] = inst
	return inv


func _mk_effect_comp(owner_node: Node, inv: InventoryComponent) -> EffectComponent:
	var ec := EffectComponent.new()
	owner_node.add_child(ec)
	ec.setup(owner_node, inv)
	return ec


func _mk_target() -> Node3D:
	var t := Node3D.new()
	add_child(t)
	var st := StatusEffectComponent.new()
	t.add_child(st)
	return t


func _target_has_burn(t: Node) -> bool:
	for c in t.get_children():
		if c is StatusEffectComponent:
			return (c as StatusEffectComponent).has(StatusEffectComponent.Kind.BURN)
	return false
