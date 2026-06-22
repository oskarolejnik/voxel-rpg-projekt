extends Node
## Etap2Test.gd — mini-test HEADLESS Etapu 2 (DoD loot). NIE rusza działającej gry (Main.tscn).
## Uruchomienie: godot --headless res://test/Etap2Test.tscn
##
## Sprawdza DoD Etapu 2 (ROADMAP 5 / GDD 6 / TDD 2.4-3):
##  (1) roll_item DETERMINISTYCZNY: ten sam seed -> ten sam item (afiksy/sockety/enchant).
##  (2) Tier -> liczba afiksów (COMMON=1 ... RARE=3) zgodna z GDD 6.2.
##  (3) EQUIP itemu zmienia StatsComponent.get_stat() (afiksy wpięte przez InventoryComponent).
##  (4) SOCKET klejnotu zmienia get_stat() (klejnot wpięty przez InventoryComponent).
##  (5) Bonus SETU (2/4-cz.) wchodzi do puli, gdy założone wystarczająco części.
##  (6) ENCHANT (RARE+) dorzuca modyfikator do get_stat().
##  (7) drop_for(enemy) zwraca item (HOST-ONLY, w SP autorytet = true).
##  (8) ilvl skaluje wartość afiksu (ten sam afiks z wyższym ilvl jest mocniejszy).
##  (9) Serializacja ItemInstance round-trip (seed/sockety/enchant) zachowana.
## (10) PEŁNA pętla pickupu w świecie: LootDrop.spawn_item -> Area3D.body_entered(gracz) ->
##      _try_pickup -> InventoryComponent.add_to_backpack (warstwy kolizji 2/bit1 + grupa "player").
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[E2] ..." + ALL OK + quit.

const EPS: float = 0.0001

var _failures: int = 0


func _ready() -> void:
	print("[E2] === Etap 2 mini-test start ===")
	# Test sam tworzy swoje pule afiksów/klejnotów w ItemDB (nie zależy od plików .tres na dysku),
	# żeby był odporny i powtarzalny niezależnie od stanu data/db.
	_inject_test_db()

	_test_roll_deterministic()
	_test_tier_affix_count()
	_test_equip_changes_stat()
	_test_socket_changes_stat()
	_test_set_bonus()
	_test_enchant()
	_test_drop_for()
	_test_ilvl_scaling()
	_test_serialization_roundtrip()
	_test_equip_unwearable_keeps_item()   # regresja: item-loss przy niewdziewalnym slocie
	await _test_world_pickup()   # pelna petla w-swiecie: LootDrop -> Area3D -> add_to_backpack

	if _failures == 0:
		print("[E2] ALL OK")
	else:
		printerr("[E2] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[E2] FAIL: %s" % msg)


# ---------------------------------------------------------------------------
#  Wstrzykuje deterministyczne pule do ItemDB (afiksy/klejnoty/sety/itemy) na czas testu.
# ---------------------------------------------------------------------------
func _inject_test_db() -> void:
	var ALL := [ItemResource.Slot.WEAPON, ItemResource.Slot.HELM, ItemResource.Slot.CHEST,
		ItemResource.Slot.LEGS, ItemResource.Slot.BOOTS, ItemResource.Slot.TRINKET]

	ItemDB.affixes.clear()
	ItemDB.affixes[&"t_sharp"] = _aff(&"t_sharp", &"damage", StatModifier.Op.INCREASED, 0.1, 0.2, [ItemResource.Slot.WEAPON])
	ItemDB.affixes[&"t_vital"] = _aff(&"t_vital", &"max_hp", StatModifier.Op.FLAT, 20.0, 40.0, ALL)
	ItemDB.affixes[&"t_armor"] = _aff(&"t_armor", &"armor", StatModifier.Op.FLAT, 5.0, 15.0, ALL)
	ItemDB.affixes[&"t_crit"] = _aff(&"t_crit", &"crit_chance", StatModifier.Op.FLAT, 0.02, 0.05, ALL)
	ItemDB.affixes[&"t_speed"] = _aff(&"t_speed", &"attack_speed", StatModifier.Op.INCREASED, 0.05, 0.1, [ItemResource.Slot.WEAPON])

	ItemDB.gems.clear()
	var ruby := GemResource.new()
	ruby.id = &"t_ruby"
	ruby.modifiers = [StatModifier.make(&"fire_damage", StatModifier.Op.FLAT, 7.0, [&"fire"], &"gem", &"t_ruby")] as Array[StatModifier]
	ItemDB.gems[&"t_ruby"] = ruby

	ItemDB.sets.clear()
	var sset := SetResource.new()
	sset.id = &"t_set"
	sset.bonuses = {
		2: [StatModifier.make(&"armor", StatModifier.Op.INCREASED, 0.5, [&"set"], &"set", &"t_set")] as Array[StatModifier],
	}
	ItemDB.sets[&"t_set"] = sset

	ItemDB.items.clear()
	var chest := ItemResource.new()
	chest.id = &"t_set_chest"
	chest.slot = ItemResource.Slot.CHEST
	chest.set_id = &"t_set"
	ItemDB.items[&"t_set_chest"] = chest
	var helm := ItemResource.new()
	helm.id = &"t_set_helm"
	helm.slot = ItemResource.Slot.HELM
	helm.set_id = &"t_set"
	ItemDB.items[&"t_set_helm"] = helm


func _aff(id: StringName, stat: StringName, op: int, vmin: float, vmax: float, slots: Array) -> AffixResource:
	var a := AffixResource.new()
	a.id = id
	a.stat = stat
	a.op = op
	a.value_min = vmin
	a.value_max = vmax
	var sl: Array[int] = []
	for s in slots: sl.append(int(s))
	a.allowed_slots = sl
	a.ilvl_min = 1
	a.weight = 1.0
	return a


func _make_player_stack(max_hp: float = 100.0, damage: float = 18.0) -> Dictionary:
	# Encja gracza-atrapa: StatsComponent + InventoryComponent (rejestruje się jako provider).
	var ent := Node.new()
	add_child(ent)
	var stats := StatsComponent.new()
	var block := StatBlock.new()
	block.max_hp = max_hp
	block.damage = damage
	stats.base = block
	ent.add_child(stats)
	var inv := InventoryComponent.new()
	ent.add_child(inv)
	return { "ent": ent, "stats": stats, "inv": inv }


# (1) DETERMINIZM: ten sam seed/kontekst -> identyczny item (afiksy/sockety/enchant).
func _test_roll_deterministic() -> void:
	var a := LootService.roll_item(12345, 10, &"verdant", ItemResource.Rarity.RARE, ItemResource.Slot.WEAPON)
	var b := LootService.roll_item(12345, 10, &"verdant", ItemResource.Rarity.RARE, ItemResource.Slot.WEAPON)
	_check(a.rolled_affixes.size() == b.rolled_affixes.size(), "determinizm: różna liczba afiksów")
	var same := true
	for i in a.rolled_affixes.size():
		var ma: StatModifier = a.rolled_affixes[i]
		var mb: StatModifier = b.rolled_affixes[i]
		if ma.stat != mb.stat or absf(ma.value - mb.value) > EPS or ma.op != mb.op:
			same = false
	_check(same, "determinizm: ten sam seed dał RÓŻNE afiksy")
	_check(a.sockets.size() == b.sockets.size(), "determinizm: różna liczba socketów")
	_check(JSON.stringify(a.enchant) == JSON.stringify(b.enchant), "determinizm: różny enchant")
	# Inny seed -> (prawie na pewno) inny wynik wartości.
	var c := LootService.roll_item(99999, 10, &"verdant", ItemResource.Rarity.RARE, ItemResource.Slot.WEAPON)
	var diff := a.rolled_affixes.size() != c.rolled_affixes.size()
	for i in mini(a.rolled_affixes.size(), c.rolled_affixes.size()):
		if absf((a.rolled_affixes[i] as StatModifier).value - (c.rolled_affixes[i] as StatModifier).value) > EPS:
			diff = true
	print("[E2] determinizm: ten sam seed identyczny=%s, inny seed różny=%s" % [str(same), str(diff)])
	_check(diff, "różny seed dał identyczny item (RNG nie działa per-seed)")


# (2) Tier -> liczba afiksów (GDD 6.2): COMMON=1, UNCOMMON=2, RARE=3, EPIC=4.
func _test_tier_affix_count() -> void:
	var common := LootService.roll_item(7, 5, &"verdant", ItemResource.Rarity.COMMON, ItemResource.Slot.CHEST)
	var rare := LootService.roll_item(7, 5, &"verdant", ItemResource.Rarity.RARE, ItemResource.Slot.CHEST)
	print("[E2] afiksy: COMMON=%d (ozcz 1), RARE=%d (ozcz 3)" % [common.rolled_affixes.size(), rare.rolled_affixes.size()])
	_check(common.rolled_affixes.size() == 1, "COMMON powinien mieć 1 afiks (ma %d)" % common.rolled_affixes.size())
	_check(rare.rolled_affixes.size() == 3, "RARE powinien mieć 3 afiksy (ma %d)" % rare.rolled_affixes.size())


# (3) EQUIP zmienia get_stat() (DoD: założenie itemu zmienia stat).
func _test_equip_changes_stat() -> void:
	var pk := _make_player_stack(100.0, 18.0)
	var stats: StatsComponent = pk["stats"]
	var inv: InventoryComponent = pk["inv"]
	var before := stats.get_stat(&"damage")

	# Item z gwarantowanym afiksem damage: budujemy ręcznie (jeden afiks INCREASED damage).
	var item := ItemInstance.new()
	item.rarity = ItemResource.Rarity.UNCOMMON
	item.ilvl = 1
	item.rolled_affixes = [StatModifier.make(&"damage", StatModifier.Op.INCREASED, 0.5, [], &"gear", &"t")]
	inv.equip(item, InventoryComponent.EquipSlot.WEAPON)
	var after := stats.get_stat(&"damage")
	print("[E2] equip +50%% damage: %.2f -> %.2f (ozcz 27)" % [before, after])
	_check(absf(before - 18.0) < EPS, "damage przed equip != 18 (%.2f)" % before)
	_check(absf(after - 27.0) < EPS, "equip nie zmienił damage (%.2f != 27)" % after)

	# Unequip wraca do bazy.
	inv.unequip(InventoryComponent.EquipSlot.WEAPON)
	_check(absf(stats.get_stat(&"damage") - 18.0) < EPS, "unequip nie cofnął statu")
	(pk["ent"] as Node).queue_free()


# (4) SOCKET klejnotu zmienia get_stat() (DoD: klejnot w sockecie działa).
func _test_socket_changes_stat() -> void:
	var pk := _make_player_stack()
	var stats: StatsComponent = pk["stats"]
	var inv: InventoryComponent = pk["inv"]

	# Item z 1 pustym socketem, założony w WEAPON.
	var item := ItemInstance.new()
	item.rarity = ItemResource.Rarity.RARE
	item.sockets = [&""] as Array[StringName]
	inv.equip(item, InventoryComponent.EquipSlot.WEAPON)
	var before := stats.get_stat(&"fire_damage")
	_check(absf(before) < EPS, "fire_damage przed socketem != 0 (%.2f)" % before)

	# Wkładamy Rubin (t_ruby z ItemDB: +7 fire_damage).
	var ok := inv.socket_gem(InventoryComponent.EquipSlot.WEAPON, 0, &"t_ruby")
	var after := stats.get_stat(&"fire_damage")
	print("[E2] socket Rubin +7 fire: %.2f -> %.2f" % [before, after])
	_check(ok, "socket_gem zwrócił false")
	_check(absf(after - 7.0) < EPS, "socket nie zmienił fire_damage (%.2f != 7)" % after)

	# Wyjęcie klejnotu cofa stat.
	inv.unsocket_gem(InventoryComponent.EquipSlot.WEAPON, 0)
	_check(absf(stats.get_stat(&"fire_damage")) < EPS, "unsocket nie cofnął statu")
	(pk["ent"] as Node).queue_free()


# (5) Bonus SETU (2-cz.) wchodzi do puli po założeniu 2 części tego samego setu.
func _test_set_bonus() -> void:
	var pk := _make_player_stack()
	var stats: StatsComponent = pk["stats"]
	var inv: InventoryComponent = pk["inv"]

	var chest := ItemInstance.new()
	chest.base_id = &"t_set_chest"          # set_id=t_set (z ItemDB)
	chest.rarity = ItemResource.Rarity.SET
	var helm := ItemInstance.new()
	helm.base_id = &"t_set_helm"
	helm.rarity = ItemResource.Rarity.SET

	inv.equip(chest, InventoryComponent.EquipSlot.CHEST)
	var with_one := stats.get_stat(&"armor")     # 1 część -> bonus 2cz NIEaktywny
	inv.equip(helm, InventoryComponent.EquipSlot.HELM)
	var with_two := stats.get_stat(&"armor")     # 2 części -> +50% armor (INCREASED) na bazie 0 = 0...

	# Baza armor=0, więc INCREASED nie pokaże się na armor (0 * 1.5 = 0). Sprawdzamy obecność
	# modyfikatora setowego inaczej: dodajemy bazowy armor przez afiks i patrzymy na mnożnik.
	# Prościej: ustaw bazę armor > 0 i porównaj.
	(stats.base as StatBlock).armor = 10.0
	stats.rebuild_modifiers()
	var two_with_base := stats.get_stat(&"armor")  # 10 * (1 + 0.5) = 15
	print("[E2] set 2cz: armor (baza10) = %.2f (ozcz 15)" % two_with_base)
	_check(absf(two_with_base - 15.0) < EPS, "bonus setu 2cz nie zadziałał (%.2f != 15)" % two_with_base)
	# Zdjęcie 1 części -> bonus znika (10 * 1.0 = 10).
	inv.unequip(InventoryComponent.EquipSlot.HELM)
	var one_with_base := stats.get_stat(&"armor")
	_check(absf(one_with_base - 10.0) < EPS, "bonus setu nie zniknął po zdjęciu części (%.2f != 10)" % one_with_base)
	(pk["ent"] as Node).queue_free()


# (6) ENCHANT (RARE+) dorzuca modyfikator do get_stat().
func _test_enchant() -> void:
	var pk := _make_player_stack()
	var stats: StatsComponent = pk["stats"]
	var inv: InventoryComponent = pk["inv"]

	var item := ItemInstance.new()
	item.rarity = ItemResource.Rarity.RARE
	item.enchant = { "enchant_id": "cool_down", "rank": 2 }   # cdr FLAT 0.05 * 2 = 0.10
	inv.equip(item, InventoryComponent.EquipSlot.HELM)
	var cdr := stats.get_stat(&"cdr")
	print("[E2] enchant cool_down r2: cdr=%.3f (ozcz 0.10)" % cdr)
	_check(absf(cdr - 0.10) < EPS, "enchant nie wpiął cdr (%.3f != 0.10)" % cdr)
	(pk["ent"] as Node).queue_free()


# (7) drop_for(enemy) zwraca item (HOST-ONLY; w SP NetManager.has_authority=true).
func _test_drop_for() -> void:
	# Atrapa wroga: Node z polami loot_ilvl/loot_biome (LootService je czyta). Bez loot_table ->
	# LootService daje sensowny default. Wymuszamy wiele prób, by mieć pewność trafienia itemu.
	var enemy := Node.new()
	enemy.set_script(preload("res://test/LootDummyEnemy.gd"))
	enemy.loot_ilvl = 5
	enemy.loot_biome = &"verdant"
	add_child(enemy)

	var got_item := false
	var got_any := false
	for _i in 50:
		var drops := LootService.drop_for(enemy)
		if not drops.is_empty():
			got_any = true
		for d in drops:
			if d.get("kind", "") == "item" and d.get("instance", null) is ItemInstance:
				got_item = true
	print("[E2] drop_for: got_any=%s, got_item=%s" % [str(got_any), str(got_item)])
	_check(got_any, "drop_for nigdy nic nie zwrócił")
	_check(got_item, "drop_for nigdy nie zwrócił itemu w 50 próbach")
	enemy.queue_free()


# (8) ilvl skaluje wartość afiksu (ilvl_scale = 1 + (ilvl-1)*0.04).
func _test_ilvl_scaling() -> void:
	# Pula z JEDNYM afiksem (t_sharp na WEAPON) i stałym seedem -> roll wartości identyczny;
	# różni się tylko ilvl_scale. Czyścimy pulę do jednego afiksu na czas testu.
	var saved := ItemDB.affixes.duplicate()
	ItemDB.affixes.clear()
	ItemDB.affixes[&"t_only"] = _aff(&"t_only", &"damage", StatModifier.Op.FLAT, 10.0, 10.0, [ItemResource.Slot.WEAPON])

	var low := LootService.roll_item(555, 1, &"verdant", ItemResource.Rarity.COMMON, ItemResource.Slot.WEAPON)
	var high := LootService.roll_item(555, 50, &"verdant", ItemResource.Rarity.COMMON, ItemResource.Slot.WEAPON)
	var vlow := (low.rolled_affixes[0] as StatModifier).value
	var vhigh := (high.rolled_affixes[0] as StatModifier).value
	# COMMON mult 0.7. low ilvl=1: 10*0.7*1.0 = 7. high ilvl=50: 10*0.7*(1+49*0.04)=10*0.7*2.96=20.72.
	print("[E2] ilvl scaling: ilvl1=%.2f, ilvl50=%.2f" % [vlow, vhigh])
	_check(vhigh > vlow + EPS, "wyższy ilvl nie dał wyższej wartości afiksu (%.2f !> %.2f)" % [vhigh, vlow])
	_check(absf(vlow - 7.0) < 0.01, "ilvl1 wartość != 7 (%.2f) — TIER_MULT/ilvl_scale rozjechane" % vlow)

	ItemDB.affixes = saved


# (9) Serializacja ItemInstance round-trip (seed/sockety/enchant zachowane).
func _test_serialization_roundtrip() -> void:
	var item := LootService.roll_item(424242, 12, &"emberwaste", ItemResource.Rarity.EPIC, ItemResource.Slot.WEAPON)
	var d := item.to_dict()
	var back := ItemInstance.from_dict(d)
	_check(back.seed == item.seed, "round-trip: seed zmieniony")
	_check(back.rarity == item.rarity, "round-trip: rarity zmienione")
	_check(back.ilvl == item.ilvl, "round-trip: ilvl zmieniony")
	_check(back.sockets.size() == item.sockets.size(), "round-trip: sockety zmienione")
	_check(JSON.stringify(back.enchant) == JSON.stringify(item.enchant), "round-trip: enchant zmieniony")
	# Modyfikatory powinny dać tę samą sumę wartości.
	var sum_a := 0.0
	for m in item.collect_modifiers(): sum_a += (m as StatModifier).value
	var sum_b := 0.0
	for m in back.collect_modifiers(): sum_b += (m as StatModifier).value
	print("[E2] round-trip: suma mod a=%.3f b=%.3f" % [sum_a, sum_b])
	_check(absf(sum_a - sum_b) < EPS, "round-trip: suma modyfikatorów różna (%.3f != %.3f)" % [sum_a, sum_b])


# REGRESJA (review #1, item-loss): equip_from_backpack na NIEWDZIEWALNY slot (CONSUMABLE/MATERIAL
# lub poza zakresem) NIE może zniszczyć itemu. Item musi zostać w plecaku, a funkcja zwrócić false.
func _test_equip_unwearable_keeps_item() -> void:
	var pk := _make_player_stack()
	var inv: InventoryComponent = pk["inv"]

	# Definicja itemu CONSUMABLE w ItemDB (żeby _natural_slot zwrócił -1).
	var potion := ItemResource.new()
	potion.id = &"t_potion"
	potion.slot = ItemResource.Slot.CONSUMABLE
	ItemDB.items[&"t_potion"] = potion

	var inst := ItemInstance.new()
	inst.base_id = &"t_potion"
	inst.rarity = ItemResource.Rarity.COMMON
	inv.add_to_backpack(inst)
	_check(inv.backpack.size() == 1, "setup: plecak powinien mieć 1 item (ma %d)" % inv.backpack.size())

	# Klik z UI: target_slot=-1 -> _natural_slot zwraca -1 (CONSUMABLE) -> bail, item zostaje.
	var ret := inv.equip_from_backpack(0)
	print("[E2] item-loss guard (CONSUMABLE): ret=%s, backpack=%d (ozcz false,1)" % [str(ret), inv.backpack.size()])
	_check(ret == false, "equip_from_backpack(CONSUMABLE) powinien zwrócić false (zwrócił %s)" % str(ret))
	_check(inv.backpack.size() == 1, "ITEM-LOSS: item zniknął z plecaka (size=%d != 1)" % inv.backpack.size())
	_check(inv.backpack.size() > 0 and inv.backpack[0] == inst, "item w plecaku to nie ten sam obiekt (zgubiony/podmieniony)")

	# Drugi wektor: jawny target_slot poza zakresem (>= EQUIP_SLOT_COUNT) — też nie wolno zgubić.
	var ret2 := inv.equip_from_backpack(0, InventoryComponent.EQUIP_SLOT_COUNT + 3)
	_check(ret2 == false, "equip_from_backpack(slot poza zakresem) powinien zwrócić false")
	_check(inv.backpack.size() == 1, "ITEM-LOSS: item zniknął przy slocie poza zakresem (size=%d != 1)" % inv.backpack.size())

	ItemDB.items.erase(&"t_potion")
	(pk["ent"] as Node).queue_free()


# (10) PEŁNA pętla pickupu w świecie: LootDrop (Area3D na warstwie interactable, mask=bit1) wykrywa
#      ciało gracza (CharacterBody3D na collision_layer=bit1, grupa "player") i ląduje item w plecaku.
#      To łapie regresje warstw kolizji/grupy/monitoringu, których osobne testy drop_for/add_to_backpack
#      by przeoczyły. Wymaga klatek fizyki (Area3D wykrywa wejście ciała), więc test jest async.
func _test_world_pickup() -> void:
	# Atrapa gracza: CharacterBody3D na warstwie kolizji bit1 (warstwa 2), w grupie "player",
	# z dzieckiem InventoryComponent (LootDrop._find_inventory go znajdzie).
	var player := CharacterBody3D.new()
	player.collision_layer = 1 << 1     # bit 1 = warstwa 2 (LootDrop.area.collision_mask = 1<<1)
	player.collision_mask = 0
	player.add_to_group("player")
	var body_cs := CollisionShape3D.new()
	var body_shape := SphereShape3D.new()
	body_shape.radius = 0.5
	body_cs.shape = body_shape
	player.add_child(body_cs)
	var inv := InventoryComponent.new()
	player.add_child(inv)
	add_child(player)
	player.global_position = Vector3(0, 0, 0)

	# Drop itemu DOKŁADNIE w pozycji gracza -> Area3D powinno wykryć wejście ciała.
	var instance := LootService.roll_item(31337, 5, &"verdant", ItemResource.Rarity.RARE, ItemResource.Slot.WEAPON)
	var drop := LootDrop.spawn_item(self, Vector3(0, 0, 0), instance)
	# Flaga w tablicy (typ referencyjny) — lambda GDScript kopiuje zwykłe lokalne po WARTOŚCI,
	# więc bool by się nie zaktualizował; Array współdzieli referencję i widzi zmianę z sygnału.
	var picked := [false]
	drop.picked_up.connect(func(_d: LootDrop) -> void: picked[0] = true)

	# Kilka klatek fizyki: Area3D rejestruje overlap dopiero po kroku silnika fizyki.
	for _i in 6:
		await get_tree().physics_frame

	print("[E2] world pickup: picked=%s, backpack=%d, drop_freed=%s" %
		[str(picked[0]), inv.backpack.size(), str(not is_instance_valid(drop))])
	_check(picked[0], "pickup w świecie nie wyemitował picked_up (warstwy kolizji/grupa zepsute?)")
	_check(inv.backpack.size() == 1, "pickup nie dodał itemu do plecaka (size=%d != 1)" % inv.backpack.size())
	player.queue_free()
