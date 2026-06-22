class_name HealthComponent
extends Node
## HealthComponent.gd (komponent) — stan HP encji (TDD 1.2). current_hp pochodzi z
## StatsComponent.get_stat(&"max_hp"); reaguje na stats_changed (zmiana max_hp -> klamrowanie).
## Mutacja HP w Etapie 1 idzie przez DamageService (host-authoritative); tu wystawiamy
## apply_damage/heal jako kontrakt + sygnaly damaged/died (hook pod loot/HUD).
##
## Etap 0: dziala samodzielnie (bez Player), bez kolizji z istniejacym Player.gd (nie ruszamy go).

@export var stats_path: NodePath          # sciezka do StatsComponent (sibling). Pusta -> szuka brata.

signal damaged(amount: float, from: Node, current_hp: float)
signal healed(amount: float, current_hp: float)
signal died(from: Node)
signal hp_changed(current_hp: float, max_hp: float)

var current_hp: float = 0.0
var is_dead: bool = false

## Opcjonalna BRAMKA obrażeń (i-frames/unik/perfect-dodge gracza). func(amount, from) -> bool:
## zwróć true, by ZABLOKOWAĆ to trafienie (HP nietknięte). Pozwala encji trzymać nietykalność,
## a HealthComponentowi pozostać JEDYNYM źródłem HP. Pusta -> brak bramki (zawsze przyjmuje cios).
var damage_gate: Callable = Callable()

var _stats: StatsComponent = null


func _ready() -> void:
	_stats = _resolve_stats()
	if _stats != null:
		if not _stats.stats_changed.is_connected(_on_stats_changed):
			_stats.stats_changed.connect(_on_stats_changed)
	# Pelne HP na starcie (z max_hp pipeline'u).
	current_hp = max_hp()
	hp_changed.emit(current_hp, max_hp())


func _resolve_stats() -> StatsComponent:
	if stats_path != NodePath() and has_node(stats_path):
		return get_node(stats_path) as StatsComponent
	# Fallback: szukaj brata StatsComponent.
	var parent := get_parent()
	if parent != null:
		for child in parent.get_children():
			if child is StatsComponent:
				return child
	return null


## Maksymalne HP z pipeline'u (jedno zrodlo prawdy). Brak stats -> 0.
func max_hp() -> float:
	if _stats != null:
		return _stats.get_stat(&"max_hp")
	return 0.0


## Reakcja na zmiane staty (np. zalozenie itemu z +max_hp). Klamruje current_hp do nowego maxa.
## Nie leczy "za darmo" przy spadku maxa — tylko przycina gore.
func _on_stats_changed() -> void:
	var mx := max_hp()
	if current_hp > mx:
		current_hp = mx
	hp_changed.emit(current_hp, mx)


## Zadaje obrazenia (juz policzone przez DamageService w Etapie 1). Etap 0: prosta redukcja HP.
func apply_damage(amount: float, from: Node = null) -> void:
	if is_dead or amount <= 0.0:
		return
	# Bramka nietykalności (i-frames/perfect-dodge): encja może zawetować trafienie (HP nietknięte).
	if damage_gate.is_valid() and bool(damage_gate.call(amount, from)):
		return
	current_hp = maxf(current_hp - amount, 0.0)
	damaged.emit(amount, from, current_hp)
	hp_changed.emit(current_hp, max_hp())
	if current_hp <= 0.0:
		is_dead = true
		died.emit(from)


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_hp = minf(current_hp + amount, max_hp())
	healed.emit(amount, current_hp)
	hp_changed.emit(current_hp, max_hp())


## Pelne odnowienie (respawn/start). Zdejmuje flage smierci.
func revive_full() -> void:
	is_dead = false
	current_hp = max_hp()
	hp_changed.emit(current_hp, max_hp())
