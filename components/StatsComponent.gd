class_name StatsComponent
extends Node
## StatsComponent.gd (komponent) — JEDYNE zrodlo finalnej wartosci statu (TDD 3).
##
## Pipeline (TDD 3.1): final = (base + sum FLAT) * (1 + sum INCREASED) * prod(1 + MORE).
## base z StatBlock; modyfikatory zbierane z 4 zrodel (TDD 3.2): InventoryComponent / drzewko /
## BuffComponent / AbilityComponent. W Etapie 0 te komponenty jeszcze nie istnieja, wiec
## zbieranie jest GENERYCZNE: rejestrujemy "providery" (dowolny Node z metoda collect_modifiers()
## -> Array[StatModifier]) i/lub wstrzykujemy modyfikatory wprost (add_modifiers) na potrzeby
## mini-testu DoD. W Etapie 1 sibling-komponenty po prostu rejestruja sie jako providery — rdzen
## get_stat/rebuild/cache/sygnal NIE zmienia sie.
##
## Memoizacja: _cache czyszczony na _dirty; rebuild_modifiers() -> invalidacja + stats_changed.
## Determinizm: identyczne dane -> identyczny wynik na hoscie i kliencie (brak desyncu staty).

@export var base: StatBlock

signal stats_changed

var _mods: Array[StatModifier] = []          # zaglomerowane modyfikatory (po rebuild)
var _cache: Dictionary = {}                  # StringName -> float (memoizacja)
var _dirty: bool = true

## Providery modyfikatorow: Node-y z metoda `collect_modifiers() -> Array[StatModifier]`.
## Etap 1: InventoryComponent/BuffComponent/AbilityComponent/drzewko rejestruja sie tu.
var _providers: Array[Node] = []

## Modyfikatory wstrzykniete WPROST (bez providera) — np. mini-test DoD albo proste przypadki.
var _injected: Array[StatModifier] = []


func _ready() -> void:
	# Zapewnij wlasny StatBlock, jesli nie przypisano w inspektorze (encja zawsze ma base).
	if base == null:
		base = StatBlock.new()
	rebuild_modifiers()


# ============================================================================
#  Rejestracja zrodel modyfikatorow (Etap 1 podpina komponenty; Etap 0 — opcjonalnie)
# ============================================================================

## Rejestruje provider (Node z collect_modifiers()). Idempotentne. Wola rebuild.
func register_provider(p: Node) -> void:
	if p == null or _providers.has(p):
		return
	_providers.append(p)
	rebuild_modifiers()


func unregister_provider(p: Node) -> void:
	if _providers.has(p):
		_providers.erase(p)
		rebuild_modifiers()


## Wstrzykuje modyfikatory wprost (poza providerami). Uzywane przez mini-test DoD i proste hooki.
func add_modifiers(mods: Array[StatModifier]) -> void:
	_injected.append_array(mods)
	rebuild_modifiers()


## Usuwa wstrzykniete modyfikatory po source_id (np. wygasly buff). Wola rebuild gdy cos usunieto.
func remove_modifiers_by_source(source_id: StringName) -> void:
	var before := _injected.size()
	_injected = _injected.filter(func(m: StatModifier) -> bool: return m.source_id != source_id)
	if _injected.size() != before:
		rebuild_modifiers()


# ============================================================================
#  Rdzen pipeline'u (TDD 3.3) — memoizacja + invalidacja
# ============================================================================

## Przebudowuje zaglomerowana liste modyfikatorow ze WSZYSTKICH zrodel, invaliduje cache
## i emituje stats_changed (HUD + HealthComponent.max_hp reaguja). TDD 3.3.
func rebuild_modifiers() -> void:
	_mods.clear()
	for p in _providers:
		if is_instance_valid(p) and p.has_method("collect_modifiers"):
			var got = p.collect_modifiers()
			if got is Array:
				_mods.append_array(got)
	_mods.append_array(_injected)
	_dirty = true
	stats_changed.emit()


## Finalna wartosc statu wg pipeline'u. JEDYNE wejscie odczytu staty (nikt nie czyta afiksu wprost).
func get_stat(stat: StringName) -> float:
	if _dirty:
		_cache.clear()
		_dirty = false
	if _cache.has(stat):
		return _cache[stat]
	var b := _base_value(stat)
	var flat := 0.0
	var inc := 0.0
	var more := 1.0
	for m in _mods:
		if m == null or m.stat != stat:
			continue
		match m.op:
			StatModifier.Op.FLAT:      flat += m.value
			StatModifier.Op.INCREASED: inc += m.value
			StatModifier.Op.MORE:      more *= (1.0 + m.value)
	var fin := (b + flat) * (1.0 + inc) * more
	_cache[stat] = fin
	return fin


## Wartosc bazowa statu z StatBlock (TDD 3.1 "base"). Brak base -> 0.0.
func _base_value(stat: StringName) -> float:
	if base == null:
		return 0.0
	return base.get_base(stat)
