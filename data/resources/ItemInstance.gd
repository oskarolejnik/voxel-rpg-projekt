class_name ItemInstance
extends Resource
## ItemInstance.gd — INSTANCJA itemu (w plecaku/save/sync). TDD 2.4.
## Afiksy klient odtwarza deterministycznie z seed + ilvl + rarity. base_id -> ItemResource w ItemDB.
##
## Etap 0: schemat + helper collect_modifiers() uzywany przez mini-test DoD
## (testowy item z StatModifier(&"damage", INCREASED, 0.2)). W Etapie 2 doloza sie
## odtwarzanie afiksow z seed; tu modyfikatory trzymamy wprost w rolled_affixes/explicit_modifiers.

@export var base_id: StringName = &""                 # -> ItemResource w ItemDB
@export var rarity: int = 0                           # ItemResource.Rarity
@export var ilvl: int = 1
## Minimalny poziom postaci do zalozenia (derywowany z ilvl w LootService.roll_item). 1 = brak progu.
## InventoryComponent.equip odrzuca item, gdy req_level > poziom nosiciela (jesli poziom da sie odczytac).
@export var req_level: int = 1
@export var seed: int = 0                             # deterministyczne odtworzenie afiksow u klienta
@export var rolled_affixes: Array = []                # [StatModifier] LUB [{affix_id, value}] (odtwarzane z seed)
@export var sockets: Array[StringName] = []           # gem_id lub &"" (pusty)
@export var enchant: Dictionary = {}                  # {enchant_id, rank}
## Przynaleznosc do setu (ustawiane przy rolled SET-tier). &"" = brak setu. Bez tego pola rolled
## set item NIGDY nie liczyl sie do progu 2/4-cz (InventoryComponent liczyl sety tylko z bazy).
@export var set_id: StringName = &""

## Etap 0: jawne modyfikatory tej instancji (testowy item / implicit przed pelnym lootem).
## W Etapie 2 wieksza czesc przejdzie na odtwarzanie z seed + ItemDB, ale ten kanal zostaje
## dla implicit/unikatow. NIE @export jako typed[StatModifier] zewnetrznie wymagane — trzymamy
## jako Array[StatModifier], by InventoryComponent.collect_modifiers() mialo skad brac.
@export var explicit_modifiers: Array[StatModifier] = []


## Zbiera WSZYSTKIE modyfikatory tej instancji (Etap 0: explicit + jawne wartosci rolled_affixes
## ktore juz niosa gotowy StatModifier). Implicit z ItemResource.base_modifiers dolacza
## InventoryComponent przez ItemDB (rozdzial odpowiedzialnosci). Zwraca kopie referencji.
func collect_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	out.append_array(explicit_modifiers)
	for entry in rolled_affixes:
		if entry is StatModifier:
			out.append(entry)
		elif entry is Dictionary and entry.has("modifier") and entry["modifier"] is StatModifier:
			out.append(entry["modifier"])
	return out


func to_dict() -> Dictionary:
	return {
		"base_id": String(base_id),
		"rarity": rarity,
		"ilvl": ilvl,
		"req_level": req_level,
		"seed": seed,
		"rolled_affixes": rolled_affixes.map(func(e):
			return e.to_dict() if (e is StatModifier) else e),
		"sockets": sockets.map(func(s: StringName) -> String: return String(s)),
		"enchant": enchant,
		"set_id": String(set_id),
		"explicit_modifiers": explicit_modifiers.map(func(m: StatModifier) -> Dictionary: return m.to_dict()),
	}


static func from_dict(d: Dictionary) -> ItemInstance:
	var it := ItemInstance.new()
	it.base_id = StringName(d.get("base_id", ""))
	it.rarity = int(d.get("rarity", 0))
	it.ilvl = int(d.get("ilvl", 1))
	it.req_level = int(d.get("req_level", 1))   # brak klucza (stary save) -> 1 (brak progu, wsteczna zgodnosc)
	it.seed = int(d.get("seed", 0))
	# Symetria z to_dict(): wpisy bedace StatModifierem zapisuja sie przez e.to_dict() (slownik
	# z kluczami stat/op/value/...). Tu odtwarzamy je z powrotem do StatModifier, by collect_modifiers()
	# (galaz `entry is StatModifier`) je widzialo i 'op' wrocilo jako enum (a nie float). Slowniki
	# w formacie {affix_id, value} (odtwarzane z seed w Etapie 2) przepuszczamy bez zmian.
	var ra: Array = []
	for e in d.get("rolled_affixes", []):
		if e is Dictionary and e.has("stat") and e.has("op") and e.has("value"):
			ra.append(StatModifier.from_dict(e))
		else:
			ra.append(e)
	it.rolled_affixes = ra
	var sk: Array[StringName] = []
	for s in d.get("sockets", []):
		sk.append(StringName(s))
	it.sockets = sk
	it.enchant = d.get("enchant", {})
	it.set_id = StringName(d.get("set_id", ""))
	var em: Array[StatModifier] = []
	for md in d.get("explicit_modifiers", []):
		em.append(StatModifier.from_dict(md))
	it.explicit_modifiers = em
	return it
