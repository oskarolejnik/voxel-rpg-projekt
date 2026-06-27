class_name InventoryComponent
extends Node
## InventoryComponent.gd (komponent) — ekwipunek gracza (TDD 1.2 / 3.2 / 6.3). 7 slotow noszonych
## + plecak (Array[ItemInstance]). JEDNO miejsce, ktore zbiera modyfikatory z ekwipunku i wpina je
## do StatsComponent (rejestruje sie jako provider; collect_modifiers() -> Array[StatModifier]).
##
## Zrodla modyfikatorow z ZALOZONEGO itemu (TDD 3.2 pkt 1):
##   - implicit (ItemResource.base_modifiers z ItemDB, jesli base_id wskazuje definicje),
##   - rolled_affixes + explicit_modifiers (ItemInstance.collect_modifiers()),
##   - klejnoty w socketach (GemResource.modifiers z ItemDB.gems),
##   - enchant ({enchant_id, rank} -> LootService.enchant_modifiers()),
##   - bonusy setow (liczba zalozonych czesci danego set_id -> SetResource.bonuses).
##
## DoD Etapu 2: equip(item) zmienia StatsComponent.get_stat(); socket_gem() zmienia stat; wszystko
## przez rebuild_modifiers() (cache invalidacja + stats_changed). Serializacja do/z SaveData.

## Sloty noszone (GDD 6.3 + rozszerzenie). Trinket ma 2 fizyczne bays. ZAPIS: int(slot) jest kluczem w
## equipment_to_save -> WOLNO TYLKO DOPISYWAĆ NA KOŃCU (stare zapisy 0..6 zachowują znaczenie). Rękawice/
## naramienniki/pas/peleryna/amulet dopisane jako 7..11. Pierścień/charm/relikt = ItemResource.Slot.TRINKET.
enum EquipSlot { WEAPON, HELM, CHEST, LEGS, BOOTS, TRINKET_1, TRINKET_2, GLOVES, SHOULDERS, BELT, CLOAK, AMULET }

const EQUIP_SLOT_COUNT: int = 12

signal inventory_changed                       # plecak/ekwipunek zmieniony (UI odswieza)
signal item_equipped(slot: int, item: ItemInstance)
signal item_unequipped(slot: int, item: ItemInstance)

## NodePath do StatsComponent (sibling). Pusty -> szuka brata po typie.
@export var stats_path: NodePath

## Slot noszony -> ItemInstance (lub brak klucza = pusty). Klucz: EquipSlot.
var equipment: Dictionary = {}
## Plecak: lista ItemInstance (kolejnosc = porzadek zbierania).
var backpack: Array[ItemInstance] = []

var _stats: StatsComponent = null
## Sibling LevelComponent (jesli jest) — zrodlo poziomu nosiciela do progu req_level przy equip.
## Pusty -> brak progu (equip nie odrzuca po poziomie; wsteczna zgodnosc dla bytow bez poziomu).
var _level: LevelComponent = null


func _ready() -> void:
	_stats = _resolve_stats()
	if _stats != null:
		_stats.register_provider(self)   # rebuild + stats_changed
	_level = _resolve_level()


func _resolve_stats() -> StatsComponent:
	if stats_path != NodePath() and has_node(stats_path):
		return get_node(stats_path) as StatsComponent
	var parent := get_parent()
	if parent != null:
		for child in parent.get_children():
			if child is StatsComponent:
				return child
	return null


## Szuka brata typu LevelComponent (zrodlo poziomu nosiciela). null gdy brak.
func _resolve_level() -> LevelComponent:
	var parent := get_parent()
	if parent != null:
		for child in parent.get_children():
			if child is LevelComponent:
				return child
	return null


## Poziom nosiciela do progu req_level. Najpierw sibling LevelComponent; gdy brak — testy/UI moga
## wstrzyknac poziom przez set_wearer_level(). Zwraca -1 gdy poziom NIEUSTALONY (equip wtedy NIE
## odrzuca — wsteczna zgodnosc: byty bez poziomu zakladaja wszystko).
func wearer_level() -> int:
	if _override_level >= 0:
		return _override_level
	if _level == null:
		_level = _resolve_level()       # lazy: komponent moglby dojsc po _ready
	if _level != null:
		return _level.level
	return -1


## Pozwala testom/UI podac poziom nosiciela wprost (gdy nie ma LevelComponent jako brata).
## Ujemna wartosc = brak nadpisania (powrot do siblinga/„brak progu").
var _override_level: int = -1

func set_wearer_level(p_level: int) -> void:
	_override_level = p_level


## Czy item moze byc zalozony przez nosiciela (prog req_level). True gdy poziom nieustalony (-1)
## albo req_level <= poziom. Host-authoritative: equip i tak wykonuje sie lokalnie.
func can_equip(item: ItemInstance) -> bool:
	if item == null:
		return false
	var lvl := wearer_level()
	if lvl < 0:
		return true                     # poziom nieustalony -> brak progu (wsteczna zgodnosc)
	return item.req_level <= lvl


# ============================================================================
#  PROVIDER: zbieranie modyfikatorow z calego ekwipunku (TDD 3.2 / 3.3)
# ============================================================================

## Wolane przez StatsComponent.rebuild_modifiers(). Zbiera WSZYSTKIE modyfikatory z zalozonych
## itemow: implicit + afiksy/explicit + klejnoty + enchant + bonusy setow. Plecak NIE liczy sie.
func collect_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	var set_counts: Dictionary = {}            # set_id(StringName) -> int (liczba zalozonych czesci)

	for slot in equipment:
		var item: ItemInstance = equipment[slot]
		if item == null:
			continue
		# 1) implicit z definicji (ItemDB) — base_modifiers.
		var ir := ItemDB.item(item.base_id)
		if ir != null:
			for bm in ir.base_modifiers:
				if bm is StatModifier:
					out.append(_tag(bm, &"gear", item.base_id))
		# Przynaleznosc do setu: najpierw z ROLLED instancji (ItemInstance.set_id), fallback na definicje
		# bazy (ItemResource.set_id). NAPRAWA (audyt #2): wczesniej liczono TYLKO z bazy WEWNATRZ `if ir`,
		# wiec rolled SET item (set_id na instancji, base pusty/bez setu) NIGDY nie liczyl sie do progu 2/4-cz.
		var eff_set_id: StringName = item.set_id
		if eff_set_id == &"" and ir != null:
			eff_set_id = ir.set_id
		if eff_set_id != &"":
			set_counts[eff_set_id] = int(set_counts.get(eff_set_id, 0)) + 1

		# 2) afiksy + explicit (ItemInstance.collect_modifiers()).
		out.append_array(item.collect_modifiers())

		# 3) klejnoty w socketach (GemResource.modifiers).
		for gem_id in item.sockets:
			if gem_id == &"":
				continue
			var gem := ItemDB.gem(gem_id)
			if gem != null:
				for gm in gem.modifiers:
					if gm is StatModifier:
						out.append(_tag(gm, &"gem", gem_id))

		# 4) enchant ({enchant_id, rank}) -> LootService.enchant_modifiers() (autoload).
		if not item.enchant.is_empty():
			for em in LootService.enchant_modifiers(item.enchant):
				if em is StatModifier:
					out.append(em)

	# 5) bonusy setow: dla kazdego set_id sprawdz, ktore progi (2/4/...) sa osiagniete.
	for set_id in set_counts:
		var sdef := ItemDB.set_def(set_id)
		if sdef == null:
			continue
		var have := int(set_counts[set_id])
		for threshold in sdef.bonuses:
			if have >= int(threshold):
				for sm in sdef.bonuses[threshold]:
					if sm is StatModifier:
						out.append(_tag(sm, &"set", set_id))

	return out


## LOOT Faza 4+5 — zbiera AKTYWNE efekty (procy) z założonych itemów ORAZ z setów przy osiągniętym
## progu. Bliźniak collect_modifiers, ale kanał EFEKTÓW (EffectResource, definicyjne/referowane =>
## save-free). Wykonuje host-only EffectComponent (subskrybuje rebuild ekwipunku, pobiera świeżą listę).
## Plecak NIE liczy się. Set odtwarza się z liczby założonych części (active_set_thresholds), NIE z zapisu.
func collect_effects() -> Array[EffectResource]:
	var out: Array[EffectResource] = []
	# 1) procy z definicji założonych itemów (ItemResource.equip_effects) — legendy/mythic.
	for slot in equipment:
		var item: ItemInstance = equipment[slot]
		if item == null:
			continue
		var ir := ItemDB.item(item.base_id)
		if ir == null:
			continue
		for ef in ir.equip_effects:
			if ef is EffectResource:
				out.append(ef)
	# 2) procy setów (SetResource.procs) przy osiągniętym progu — kumulatywnie, jak bonuses (2/4/6).
	var counts := active_set_thresholds()
	for set_id in counts:
		var sdef := ItemDB.set_def(set_id)
		if sdef == null:
			continue
		var have := int(counts[set_id])
		for threshold in sdef.procs:
			if have >= int(threshold):
				for pe in sdef.procs[threshold]:
					if pe is EffectResource:
						out.append(pe)
	return out


## LOOT Faza 5 — liczba ZAŁOŻONYCH części każdego setu (set_id(StringName) -> int). Wspólne źródło dla
## bonusów statów (collect_modifiers), procy (collect_effects) i UI (get_active_set_bonuses). Przynależność:
## najpierw ROLLED instancja (ItemInstance.set_id), fallback na definicję bazy (ItemResource.set_id).
func active_set_thresholds() -> Dictionary:
	var counts: Dictionary = {}
	for slot in equipment:
		var item: ItemInstance = equipment[slot]
		if item == null:
			continue
		var eff_set_id: StringName = item.set_id
		if eff_set_id == &"":
			var ir := ItemDB.item(item.base_id)
			if ir != null:
				eff_set_id = ir.set_id
		if eff_set_id != &"":
			counts[eff_set_id] = int(counts.get(eff_set_id, 0)) + 1
	return counts


## LOOT Faza 5 — akcesor UI: aktywne sety z liczbą części i osiągniętymi progami (do tooltipów/panelu).
## Zwraca Array[Dictionary] { set_id, display_name, have:int, thresholds_met:Array[int] }.
func get_active_set_bonuses() -> Array:
	var out: Array = []
	var counts := active_set_thresholds()
	for set_id in counts:
		var sdef := ItemDB.set_def(set_id)
		if sdef == null:
			continue
		var have := int(counts[set_id])
		var thr_met: Array = []
		for t in sdef.bonuses:
			if have >= int(t) and not thr_met.has(int(t)):
				thr_met.append(int(t))
		for t in sdef.procs:
			if have >= int(t) and not thr_met.has(int(t)):
				thr_met.append(int(t))
		thr_met.sort()
		out.append({
			"set_id": set_id,
			"display_name": sdef.display_name,
			"have": have,
			"thresholds_met": thr_met,
		})
	return out


# ============================================================================
#  EQUIP / UNEQUIP / SOCKET (DoD: zmieniaja get_stat przez rebuild)
# ============================================================================

## Zaklada item w jego naturalny slot (lub wskazany). Zwraca poprzednio zalozony item (do plecaka
## woła caller lub auto). Wola rebuild -> get_stat sie zmienia (DoD). target_slot=-1 -> auto.
func equip(item: ItemInstance, target_slot: int = -1) -> ItemInstance:
	if item == null:
		return null
	if not can_equip(item):
		return null                     # za niski poziom nosiciela -> odmowa (item zostaje u callera)
	var slot := target_slot
	if slot < 0:
		slot = _natural_slot(item)
	if slot < 0 or slot >= EQUIP_SLOT_COUNT:
		return null
	var prev: ItemInstance = equipment.get(slot, null)
	equipment[slot] = item
	_rebuild()
	item_equipped.emit(slot, item)
	inventory_changed.emit()
	return prev


## Zdejmuje item ze slotu -> do plecaka. Zwraca zdjety item (lub null).
func unequip(slot: int) -> ItemInstance:
	var item: ItemInstance = equipment.get(slot, null)
	if item == null:
		return null
	equipment.erase(slot)
	backpack.append(item)
	_rebuild()
	item_unequipped.emit(slot, item)
	inventory_changed.emit()
	return item


## Zaklada item Z PLECAKA (po indeksie). Poprzedni z tego slotu wraca do plecaka. Wygodne dla UI.
## ROZWIAZUJEMY i WALIDUJEMY slot PRZED wyjeciem itemu z plecaka — jesli slot jest niewdziewalny
## (np. CONSUMABLE/MATERIAL albo poza zakresem), bailujemy i item ZOSTAJE w plecaku (nie gubimy go).
func equip_from_backpack(backpack_index: int, target_slot: int = -1) -> bool:
	if backpack_index < 0 or backpack_index >= backpack.size():
		return false
	var item := backpack[backpack_index]
	if not can_equip(item):
		return false   # za niski poziom nosiciela -> item ZOSTAJE w plecaku (sprawdzamy PRZED wyjeciem)
	var slot := target_slot
	if slot < 0:
		slot = _natural_slot(item)
	if slot < 0 or slot >= EQUIP_SLOT_COUNT:
		return false   # niewdziewalny slot -> item zostaje w plecaku (nie gubimy go)
	backpack.remove_at(backpack_index)
	var prev := equip(item, slot)
	if prev != null:
		backpack.append(prev)
		inventory_changed.emit()
	return true


## Wklada klejnot do socketu zalozonego itemu. Zwraca true przy sukcesie. Wola rebuild (DoD: stat
## sie zmienia po wlozeniu klejnotu). gem_id musi istniec w ItemDB.gems (lub byc dowolnym StringName
## w tescie — modyfikatory dolozy collect tylko jesli ItemDB go zna).
func socket_gem(slot: int, socket_index: int, gem_id: StringName) -> bool:
	var item: ItemInstance = equipment.get(slot, null)
	if item == null:
		return false
	if socket_index < 0 or socket_index >= item.sockets.size():
		return false
	item.sockets[socket_index] = gem_id
	_rebuild()
	inventory_changed.emit()
	return true


## Wyjmuje klejnot (zwraca gem_id lub &""). Klejnot nie ginie (GDD 6.5) — caller moze go odlozyc.
func unsocket_gem(slot: int, socket_index: int) -> StringName:
	var item: ItemInstance = equipment.get(slot, null)
	if item == null:
		return &""
	if socket_index < 0 or socket_index >= item.sockets.size():
		return &""
	var prev := item.sockets[socket_index]
	item.sockets[socket_index] = &""
	if prev != &"":
		_rebuild()
		inventory_changed.emit()
	return prev


## Dodaje item do plecaka (pickup z LootDrop). Wola inventory_changed (UI/toast).
func add_to_backpack(item: ItemInstance) -> void:
	if item == null:
		return
	backpack.append(item)
	inventory_changed.emit()


## Liczy itemy w PLECAKU o danym base_id (np. tame_charm). Zalozone (equipment) NIE licza sie —
## konsumpcyjne/materialy leza w plecaku. Uzywane m.in. przez TameSystem (peek item-oswajacza).
func count_item(base_id: StringName) -> int:
	var n := 0
	for it in backpack:
		if it != null and it.base_id == base_id:
			n += 1
	return n


## Czy plecak ma >=1 item o danym base_id (peek, BEZ zuzycia). Para z consume_item().
func has_item(base_id: StringName) -> bool:
	return count_item(base_id) > 0


## Zuzywa (usuwa z plecaka) `count` itemow o danym base_id. ATOMOWE: gdy w plecaku jest mniej niz
## `count`, NIC nie usuwa i zwraca false (caller nie placi czesciowo). Usuwa od konca (stabilnie),
## emituje inventory_changed tylko gdy faktycznie cos zniklo. Zwraca true przy pelnym zuzyciu.
func consume_item(base_id: StringName, count: int = 1) -> bool:
	if count <= 0:
		return true
	if count_item(base_id) < count:
		return false
	var removed := 0
	var i := backpack.size() - 1
	while i >= 0 and removed < count:
		var it := backpack[i]
		if it != null and it.base_id == base_id:
			backpack.remove_at(i)
			removed += 1
		i -= 1
	if removed > 0:
		inventory_changed.emit()
	return removed == count


func get_equipped(slot: int) -> ItemInstance:
	return equipment.get(slot, null)


# ============================================================================
#  POMOCNIKI
# ============================================================================

## Naturalny slot noszony dla itemu wg jego ItemResource.Slot. TRINKET -> pierwszy wolny trinket.
func _natural_slot(item: ItemInstance) -> int:
	var ir := ItemDB.item(item.base_id)
	var base_slot := ir.slot if ir != null else _slot_from_instance(item)
	match base_slot:
		ItemResource.Slot.WEAPON: return EquipSlot.WEAPON
		ItemResource.Slot.HELM:   return EquipSlot.HELM
		ItemResource.Slot.CHEST:  return EquipSlot.CHEST
		ItemResource.Slot.LEGS:   return EquipSlot.LEGS
		ItemResource.Slot.BOOTS:  return EquipSlot.BOOTS
		ItemResource.Slot.TRINKET:
			if equipment.get(EquipSlot.TRINKET_1, null) == null:
				return EquipSlot.TRINKET_1
			return EquipSlot.TRINKET_2
		# Rozszerzenie slotów (LOOT): pancerz/akcesoria w dedykowanych bays.
		ItemResource.Slot.GLOVES:    return EquipSlot.GLOVES
		ItemResource.Slot.SHOULDERS: return EquipSlot.SHOULDERS
		ItemResource.Slot.BELT:      return EquipSlot.BELT
		ItemResource.Slot.CLOAK:     return EquipSlot.CLOAK
		ItemResource.Slot.AMULET:    return EquipSlot.AMULET
		_:
			return -1


## Fallback slot, gdy item nie ma base_id w ItemDB (proceduralny). Domyslnie WEAPON
## (vertical slice item proceduralny czesto jest bronia). Test moze podac target_slot wprost.
func _slot_from_instance(_item: ItemInstance) -> int:
	return ItemResource.Slot.WEAPON


func _tag(m: StatModifier, source: StringName, source_id: StringName) -> StatModifier:
	# Kopia, by nie mutowac definicji z DB (source/source_id ustawiane per instancja).
	return StatModifier.make(m.stat, m.op, m.value, m.tags.duplicate(), source, source_id)


func _rebuild() -> void:
	if _stats != null:
		_stats.rebuild_modifiers()


# ============================================================================
#  SERIALIZACJA (SaveData.equipment / inventory)
# ============================================================================

## Zapis ekwipunku do slownika {EquipSlot(int) -> ItemInstance} (SaveData.equipment ksztalt).
func equipment_to_save() -> Dictionary:
	var out: Dictionary = {}
	for slot in equipment:
		var it: ItemInstance = equipment[slot]
		if it != null:
			out[int(slot)] = it
	return out


## Plecak jako Array[ItemInstance] (SaveData.inventory ksztalt; SaveData.to_dict serializuje dalej).
func backpack_to_save() -> Array:
	var out: Array = []
	for it in backpack:
		out.append(it)
	return out


## Wczytuje stan z SaveData (equipment: Slot->ItemInstance, inventory: Array[ItemInstance]).
## Wola JEDEN rebuild na koncu (nie per item).
func load_from_save(equipment_dict: Dictionary, inventory_arr: Array) -> void:
	equipment.clear()
	for k in equipment_dict:
		var v = equipment_dict[k]
		if v is ItemInstance:
			equipment[int(k)] = v
	backpack.clear()
	for it in inventory_arr:
		if it is ItemInstance:
			backpack.append(it)
	_rebuild()
	inventory_changed.emit()
