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
	_phase5()

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


## LOOT Faza 5: sety + procy setów (SetResource.procs) + active_set_thresholds + EffectComponent ON_HURT/aura.
## Sprawdza: (a) 6 setów wczytanych z procem 6-cz (.tres), (b) WALIDACJA kluczy statów (martwe staty),
## (c) active_set_thresholds zlicza, proc 6-cz pojawia się przy 6 a NIE 5 (recompute z liczby części),
## (d) 6pc bonus STAT przez collect_modifiers, (e) proc setu (fire_nova) FIRES przez EffectComponent,
## (f) ON_HURT shield leczy tylko przy niskim HP, (g) ON_EQUIP_AURA HoT leczy właściciela.
func _phase5() -> void:
	var set_ids: Array[StringName] = [&"desert_flame", &"shadow_hunter", &"wall_defender",
		&"mountain_wrath", &"frost_whisper", &"covenant_light"]

	# (a) Wszystkie 6 setów wczytane z procem 6-cz => serializacja SetResource.procs w .tres działa.
	for sid in set_ids:
		var sdef := ItemDB.set_def(sid)
		_check(sdef != null, "set %s nie wczytany" % sid)
		if sdef != null:
			_check(sdef.procs.has(6), "set %s nie ma proca 6-cz" % sid)
			if sdef.procs.has(6):
				var arr: Array = sdef.procs[6]
				_check(arr.size() >= 1 and arr[0] is EffectResource, "set %s proc 6-cz nie jest EffectResource" % sid)

	# (b) WALIDACJA kluczy statów — żaden bonus/fixed setu nie celuje w martwy stat (jak dawne crit_damage).
	for sid in set_ids:
		var sdef := ItemDB.set_def(sid)
		if sdef == null:
			continue
		for m in sdef.fixed_modifiers:
			if m is StatModifier:
				_check(StatBlock.STAT_KEYS.has((m as StatModifier).stat),
					"set %s fixed stat '%s' spoza STAT_KEYS (martwy)" % [sid, (m as StatModifier).stat])
		for thr in sdef.bonuses:
			for m in sdef.bonuses[thr]:
				if m is StatModifier:
					_check(StatBlock.STAT_KEYS.has((m as StatModifier).stat),
						"set %s %dpc stat '%s' spoza STAT_KEYS (martwy)" % [sid, thr, (m as StatModifier).stat])

	# (c) active_set_thresholds + collect_effects: proc 6-cz przy 6 częściach, znika przy 5 (recompute).
	var setC := SetResource.new()
	setC.id = &"t_set_c"
	var procC := _mk_effect(EffectResource.Trigger.ON_HIT, &"fire_nova", 1.0, 0.0)
	procC.radius = 6.0
	var pcarr: Array[EffectResource] = [procC]
	setC.procs = { 6: pcarr }
	ItemDB.sets[&"t_set_c"] = setC
	var invC := _mk_set_inv(&"t_set_c", [0, 1, 2, 8, 4, 12])
	_check(int(invC.active_set_thresholds().get(&"t_set_c", 0)) == 6, "active_set_thresholds nie zliczył 6 części")
	_check(_has_proc(invC.collect_effects(), &"fire_nova"), "collect_effects: brak proca setu przy 6 częściach")
	invC.equipment.erase(12)   # 6 -> 5
	_check(not _has_proc(invC.collect_effects(), &"fire_nova"), "proc setu został przy 5 częściach (zła recompute)")
	invC.queue_free()

	# (d) 6pc bonus STAT zbierany przez collect_modifiers (kumulatywne 2/4/6).
	var setD := SetResource.new()
	setD.id = &"t_set_d"
	var m6 := StatModifier.new()
	m6.stat = &"damage"
	m6.value = 99.0   # unikalny znacznik (collect_modifiers przepuszcza wartość przez _tag, source_id zmienia)
	setD.bonuses = { 2: [], 4: [], 6: [m6] }
	ItemDB.sets[&"t_set_d"] = setD
	var invD := _mk_set_inv(&"t_set_d", [0, 1, 2, 8, 4, 12])
	var has6 := false
	for sm in invD.collect_modifiers():
		if sm is StatModifier and (sm as StatModifier).stat == &"damage" and is_equal_approx((sm as StatModifier).value, 99.0):
			has6 = true
	_check(has6, "collect_modifiers nie dodał bonusu 6-cz setu")
	invD.queue_free()

	# (e) Proc setu (fire_nova) FIRES przez EffectComponent — pełny set => fire/burn na wrogu w AoE.
	var setE := SetResource.new()
	setE.id = &"t_set_e"
	var procE := _mk_effect(EffectResource.Trigger.ON_HIT, &"fire_nova", 1.0, 0.0)
	procE.radius = 6.0
	var pearr: Array[EffectResource] = [procE]
	setE.procs = { 6: pearr }
	ItemDB.sets[&"t_set_e"] = setE
	var ownerE := _mk_set_owner(&"t_set_e", [0, 1, 2, 8, 4, 12])
	_mk_effect_comp(ownerE, _inv_of(ownerE))
	var enemyE := _mk_target()
	enemyE.add_to_group("enemies")
	DamageService.hit_resolved.emit(ownerE, enemyE, 10.0, false)
	_check(_target_has_burn(enemyE), "proc setu (fire_nova) nie nałożył fire/burn na wroga w AoE")

	# (f) ON_HURT shield — leczy TYLKO przy niskim HP (<35%), inaczej no-op.
	var ownerF := _mk_stat_entity(100.0)
	var shieldEff := _mk_effect(EffectResource.Trigger.ON_HURT, &"shield", 1.0, 0.0)
	shieldEff.magnitude = 45.0
	var invF := _mk_inv_on(ownerF, &"t_shield", shieldEff)
	_mk_effect_comp(ownerF, invF)
	var hpF := _health_of(ownerF)
	hpF.current_hp = 20.0   # 20% < 35% => tarcza odpala
	hpF.damaged.emit(5.0, null, 20.0)
	_check(hpF.current_hp > 20.0, "ON_HURT shield nie zadziałał przy niskim HP")
	hpF.current_hp = 90.0   # 90% > 35% => no-op
	hpF.damaged.emit(5.0, null, 90.0)
	_check(is_equal_approx(hpF.current_hp, 90.0), "shield odpalił powyżej progu HP (powinien no-op)")

	# (g) ON_EQUIP_AURA HoT — tyk aury leczy właściciela.
	var ownerG := _mk_stat_entity(100.0)
	var auraEff := _mk_effect(EffectResource.Trigger.ON_EQUIP_AURA, &"heal", 1.0, 0.0)
	auraEff.magnitude = 6.0
	var invG := _mk_inv_on(ownerG, &"t_aura", auraEff)
	var ecG := _mk_effect_comp(ownerG, invG)
	_check(ecG._auras.size() == 1, "aura nie trafiła do _auras po rebuild")
	var hpG := _health_of(ownerG)
	hpG.current_hp = 50.0
	ecG._aura_tick()
	_check(hpG.current_hp > 50.0, "ON_EQUIP_AURA HoT nie uleczył właściciela")

	# (h) OSIĄGALNOŚĆ 6 części: każdy realny set ma >=6 itemów w ItemDB, w >=6 RÓŻNYCH slotach (inaczej
	# proc 6-cz nigdy nie wystrzeli w grze). Liczymy z prawdziwych .tres (po set_id z DEFINICJI bazy).
	var real_counts: Dictionary = {}     # set_id -> { count:int, slots:Dictionary }
	for iid in ItemDB.items:
		var ir: ItemResource = ItemDB.items[iid]
		if ir == null or ir.set_id == &"":
			continue
		if not real_counts.has(ir.set_id):
			real_counts[ir.set_id] = { "count": 0, "slots": {} }
		real_counts[ir.set_id]["count"] += 1
		real_counts[ir.set_id]["slots"][int(ir.slot)] = true
	for sid in set_ids:
		var rc: Dictionary = real_counts.get(sid, { "count": 0, "slots": {} })
		_check(int(rc["count"]) >= 6, "set %s ma %d części (<6, proc 6-cz nieosiągalny)" % [sid, int(rc["count"])])
		_check((rc["slots"] as Dictionary).size() >= 6, "set %s pokrywa %d różnych slotów (<6)" % [sid, (rc["slots"] as Dictionary).size()])

	print("[LOOTX] Faza 5: 6 setów+proc(.tres) + walidacja statów + thresholds + 6pc stat + fire_nova FIRES + ON_HURT + aura + osiągalność 6cz OK")


# ── Faza 5 — pomocnicze ──────────────────────────────────────────────────────
func _has_proc(effs: Array, payload: StringName) -> bool:
	for e in effs:
		if e is EffectResource and (e as EffectResource).payload == payload:
			return true
	return false


## Buduje InventoryComponent z N syntetycznymi częściami setu w podanych slotach (do testów thresholds).
func _mk_set_inv(set_id: StringName, slots: Array) -> InventoryComponent:
	var inv := InventoryComponent.new()
	add_child(inv)
	_populate_set_pieces(inv, set_id, slots)
	return inv


func _mk_set_owner(set_id: StringName, slots: Array) -> Node3D:
	var owner_node := _mk_entity()
	var inv := InventoryComponent.new()
	owner_node.add_child(inv)
	_populate_set_pieces(inv, set_id, slots)
	return owner_node


func _populate_set_pieces(inv: InventoryComponent, set_id: StringName, slots: Array) -> void:
	for i in range(slots.size()):
		var ir := ItemResource.new()
		ir.id = StringName("%s_p%d" % [set_id, i])
		ir.slot = int(slots[i])
		ir.set_id = set_id
		ItemDB.items[ir.id] = ir
		var inst := ItemInstance.new()
		inst.base_id = ir.id
		inv.equipment[int(slots[i])] = inst
	ItemDB._reindex()


func _inv_of(owner_node: Node) -> InventoryComponent:
	for c in owner_node.get_children():
		if c is InventoryComponent:
			return c
	return null


## Encja z StatsComponent(max_hp) + HealthComponent (current_hp = max na starcie). Do testów shield/aura.
func _mk_stat_entity(max_hp: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var stats := StatsComponent.new()
	var block := StatBlock.new()
	block.max_hp = max_hp
	stats.base = block
	n.add_child(stats)
	var health := HealthComponent.new()
	n.add_child(health)
	return n


func _health_of(owner_node: Node) -> HealthComponent:
	for c in owner_node.get_children():
		if c is HealthComponent:
			return c
	return null
