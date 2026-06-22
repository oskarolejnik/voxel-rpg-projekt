class_name BuffComponent
extends Node
## BuffComponent.gd (komponent) — czasowe StatModifiery wpinane do StatsComponent (TDD 3.2 pkt 3).
## Etap 1 krok (DoD): "buff testowy zmienia staty przez pipeline".
##
## Dodaje/usuwa modyfikatory po source_id, trzyma timery i po wygasnieciu wola
## StatsComponent.rebuild_modifiers() (invalidacja cache -> stats_changed -> HUD/HealthComponent).
## Rejestruje sie w StatsComponent jako PROVIDER (collect_modifiers), wiec rdzen get_stat NIE
## zmienia sie — to dokladnie kontrakt z StatsComponent.gd (register_provider).

@export var stats_path: NodePath          # do StatsComponent (sibling). Pusta -> szuka brata.

signal buff_added(source_id: StringName, duration: float)
signal buff_removed(source_id: StringName)

var _stats: StatsComponent = null
## source_id -> { mods: Array[StatModifier], time_left: float, permanent: bool }
var _buffs: Dictionary = {}


func _ready() -> void:
	_stats = _resolve_stats()
	if _stats != null:
		_stats.register_provider(self)   # StatsComponent zbiera nasze mody przez collect_modifiers()


func _resolve_stats() -> StatsComponent:
	if stats_path != NodePath() and has_node(stats_path):
		return get_node(stats_path) as StatsComponent
	var parent := get_parent()
	if parent != null:
		for child in parent.get_children():
			if child is StatsComponent:
				return child as StatsComponent
	return null


func _process(delta: float) -> void:
	if _buffs.is_empty():
		return
	var expired: Array[StringName] = []
	for sid in _buffs:
		var b: Dictionary = _buffs[sid]
		if b.get("permanent", false):
			continue
		b["time_left"] = float(b["time_left"]) - delta
		if float(b["time_left"]) <= 0.0:
			expired.append(sid)
	for sid in expired:
		_buffs.erase(sid)
		buff_removed.emit(sid)
	if not expired.is_empty():
		_rebuild()


## Dodaje buff: lista StatModifier pod source_id na `duration` s (<=0 = stale do recznego zdjecia).
## Nadpisuje istniejacy buff o tym samym source_id (refresh) — typowe dla stacku/odnowienia.
func apply_buff(source_id: StringName, mods: Array, duration: float = 0.0) -> void:
	if source_id == &"":
		return
	var typed: Array[StatModifier] = []
	for m in mods:
		if m is StatModifier:
			# Stempel source_id (do zdejmowania) i source &"buff" — spojnosc z TDD 3.2.
			(m as StatModifier).source_id = source_id
			if (m as StatModifier).source == &"":
				(m as StatModifier).source = &"buff"
			typed.append(m)
	_buffs[source_id] = {
		"mods": typed,
		"time_left": duration,
		"permanent": duration <= 0.0,
	}
	buff_added.emit(source_id, duration)
	_rebuild()


func remove_buff(source_id: StringName) -> void:
	if _buffs.has(source_id):
		_buffs.erase(source_id)
		buff_removed.emit(source_id)
		_rebuild()


func has_buff(source_id: StringName) -> bool:
	return _buffs.has(source_id)


func clear_all() -> void:
	if _buffs.is_empty():
		return
	_buffs.clear()
	_rebuild()


## Kontrakt providera StatsComponent (TDD 3.3): zwraca wszystkie aktywne modyfikatory.
func collect_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for sid in _buffs:
		var b: Dictionary = _buffs[sid]
		out.append_array(b.get("mods", []))
	return out


func _rebuild() -> void:
	if _stats != null:
		_stats.rebuild_modifiers()
