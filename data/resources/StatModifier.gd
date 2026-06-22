class_name StatModifier
extends Resource
## StatModifier.gd — pojedynczy modyfikator statystyki (Etap 0).
##
## KANON op (TDD 2.1 / 3.1): FLAT (added, +N) | INCREASED (+N% sumowane w jednej puli) |
## MORE (xN% multiplikatywne, kazde osobno). Pipeline w StatsComponent:
##   final = (base + sum FLAT) * (1 + sum INCREASED) * prod(1 + MORE)
##
## Klucz statu to StringName (&"damage", &"max_hp"...). source/source_id sluza do
## zbierania (TDD 3.2) i usuwania (np. wygasly buff po source_id) w pozniejszych etapach.

enum Op { FLAT, INCREASED, MORE }   # +N (added) | +N% sumowane | xN% multiplikatywne

@export var stat: StringName = &""                 # &"damage", &"max_hp", &"crit_chance", &"fire_damage"...
@export var op: Op = Op.FLAT
@export var value: float = 0.0
@export var tags: Array[StringName] = []           # &"fire"/&"melee"/&"set"/&"unique" — filtry/synergie
@export var source: StringName = &""               # &"gear"/&"gem"/&"enchant"/&"set"/&"tree"/&"buff"
@export var source_id: StringName = &""            # do usuwania (id buffa/itemu)


## Wygodny konstruktor — uzywany przez mini-test i pozniej przez loot/buffy.
## NIE jest @export (to fabryka), trzyma sygnature zgodna z DoD Etapu 0.
static func make(p_stat: StringName, p_op: Op, p_value: float,
		p_tags: Array[StringName] = [], p_source: StringName = &"",
		p_source_id: StringName = &"") -> StatModifier:
	var m := StatModifier.new()
	m.stat = p_stat
	m.op = p_op
	m.value = p_value
	m.tags = p_tags
	m.source = p_source
	m.source_id = p_source_id
	return m


## Serializacja do JSON (SaveManager / RPC w pozniejszych etapach).
func to_dict() -> Dictionary:
	return {
		"stat": String(stat),
		"op": int(op),
		"value": value,
		"tags": tags.map(func(t: StringName) -> String: return String(t)),
		"source": String(source),
		"source_id": String(source_id),
	}


static func from_dict(d: Dictionary) -> StatModifier:
	var m := StatModifier.new()
	m.stat = StringName(d.get("stat", ""))
	m.op = int(d.get("op", Op.FLAT)) as Op
	m.value = float(d.get("value", 0.0))
	var tg: Array[StringName] = []
	for t in d.get("tags", []):
		tg.append(StringName(t))
	m.tags = tg
	m.source = StringName(d.get("source", ""))
	m.source_id = StringName(d.get("source_id", ""))
	return m
