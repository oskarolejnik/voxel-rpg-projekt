class_name SkillTreeComponent
extends Node
## SkillTreeComponent.gd (komponent) — alokacja pasywow z drzewka (Etap 3, GDD 10 / TDD 2.3 / 3.2).
##
## DoD Etapu 3:
##  - alokacja wezla (PassiveNodeResource) ZMIENIA get_stat() przez StatsComponent;
##  - cofniecie/respec USUWA te modyfikatory (po source &"tree" + source_id = id wezla);
##  - respec ZWRACA wszystkie punkty za walute (Orby Przemiany / Zloto — koszt schodkowy).
##
## JAK WPINA SIE W STATSCOMPONENT (TDD 3.2 pkt 2): komponent rejestruje sie jako PROVIDER
## (jak InventoryComponent). collect_modifiers() zwraca modyfikatory tylko z ZAALOKOWANYCH wezlow,
## kazdy oznaczony source=&"tree", source_id=<id wezla>. Po allocate/deallocate wolamy
## StatsComponent.rebuild_modifiers() -> pula sie przelicza -> get_stat() inny -> stats_changed (HUD).
## Cofniecie pojedynczego wezla nie wymaga recznego usuwania modyfikatorow: rebuild po prostu
## NIE zbiera juz modyfikatorow odalokowanego wezla (source_id znika z puli).
##
## WALIDACJA alokacji (TDD 2.3): (1) wezel istnieje w drzewku; (2) nie jest juz wziety;
## (3) sa wolne punkty (LevelComponent.available_points); (4) prerekwizyty `requires` sa wziete
## (lub wezel jest korzeniem bez prereq); (5) poziom postaci >= node.min_level (keystone=25).
##
## Stan = Array[StringName] zaalokowanych id (przenosny przez SaveData.allocated_passives).

signal allocation_changed(node_id: StringName, allocated: bool, points_left: int)
signal respec_done(points_refunded: int, cost_paid: int)
signal respec_failed(reason: String)

@export var stats_path: NodePath          # do StatsComponent (sibling). Pusty -> brat po typie.

## Drzewko klasy (z SkillDB po class_id) — graf wezlow + layout. Ustawiane przez encje (setup()).
var tree: SkillTreeResource = null

## Komponent poziomu — zrodlo dostepnych punktow i poziomu postaci (gate wezlow).
var level_component: LevelComponent = null

## Zaalokowane wezly (id). Set przez Dictionary(bool) dla O(1) lookupu; kolejnosc nieistotna.
var _allocated: Dictionary = {}           # StringName(id) -> true

var _stats: StatsComponent = null
var _node_by_id: Dictionary = {}          # StringName(id) -> PassiveNodeResource (cache z tree.nodes)


func _ready() -> void:
	_stats = _resolve_stats()
	if _stats != null:
		_stats.register_provider(self)    # rebuild + stats_changed


## Konfiguracja przez encje: drzewko + LevelComponent (+ ewentualnie wstepna alokacja z save).
func setup(p_tree: SkillTreeResource, p_level: LevelComponent, preallocated: Array[StringName] = []) -> void:
	tree = p_tree
	level_component = p_level
	_index_nodes()
	_allocated.clear()
	# Wstepna alokacja z save — bez walidacji punktow (save to fakt), ale tylko znane wezly.
	for nid in preallocated:
		if _node_by_id.has(nid):
			_allocated[nid] = true
	_sync_spent_points()
	if _stats != null:
		_stats.rebuild_modifiers()


func _index_nodes() -> void:
	_node_by_id.clear()
	if tree == null:
		return
	for n in tree.nodes:
		if n != null and n.id != &"":
			_node_by_id[n.id] = n


func _resolve_stats() -> StatsComponent:
	if stats_path != NodePath() and has_node(stats_path):
		return get_node(stats_path) as StatsComponent
	var parent := get_parent()
	if parent != null:
		for child in parent.get_children():
			if child is StatsComponent:
				return child as StatsComponent
	return null


# ============================================================================
#  Odpytania
# ============================================================================

func is_allocated(node_id: StringName) -> bool:
	return _allocated.has(node_id)


func allocated_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _allocated:
		out.append(k)
	return out


func node(node_id: StringName) -> PassiveNodeResource:
	return _node_by_id.get(node_id, null)


func points_left() -> int:
	return level_component.available_points() if level_component != null else 0


## Powod, dla ktorego wezla NIE da sie teraz wziac ("" = mozna). Uzywane przez UI (tooltip) i allocate.
func cannot_allocate_reason(node_id: StringName) -> String:
	var n: PassiveNodeResource = _node_by_id.get(node_id, null)
	if n == null:
		return "nieznany wezel"
	if _allocated.has(node_id):
		return "juz wziety"
	if level_component != null and level_component.available_points() < n.cost_points:
		return "brak punktow"
	var lvl := level_component.level if level_component != null else 1
	if lvl < n.min_level:
		return "wymaga poziomu %d" % n.min_level
	if not _requirements_met(n):
		return "brak prerekwizytu"
	return ""


## Czy prerekwizyty wezla sa spelnione: wszystkie `requires` zaalokowane (pusta lista = korzen).
func _requirements_met(n: PassiveNodeResource) -> bool:
	for req in n.requires:
		if not _allocated.has(req):
			return false
	return true


func can_allocate(node_id: StringName) -> bool:
	return cannot_allocate_reason(node_id) == ""


# ============================================================================
#  Alokacja / dealokacja
# ============================================================================

## Bierze wezel (jesli walidacja przejdzie). Wpina modyfikatory przez rebuild StatsComponentu.
## Zwraca true przy sukcesie.
func allocate(node_id: StringName) -> bool:
	if not can_allocate(node_id):
		return false
	_allocated[node_id] = true
	_sync_spent_points()
	if _stats != null:
		_stats.rebuild_modifiers()        # collect_modifiers zbierze nowe wezly -> get_stat inny
	allocation_changed.emit(node_id, true, points_left())
	return true


## Cofa pojedynczy wezel — ale TYLKO jesli zaden wziety wezel nie zalezy od niego (spojnosc grafu).
## Zwrot punktu nastepuje przez sam fakt dealokacji (available_points = granted - spent). Walute
## za pojedynczy wezel (Orb Drobny) pobiera warstwa wyzej, jesli zechce; tu dealokacja jest darmowa
## strukturalnie (pelny platny reset to respec()). Zwraca true przy sukcesie.
func deallocate(node_id: StringName) -> bool:
	if not _allocated.has(node_id):
		return false
	# Spojnosc: nie da sie cofnac wezla, na ktorym stoi inny wziety wezel.
	for other_id in _allocated:
		if other_id == node_id:
			continue
		var other: PassiveNodeResource = _node_by_id.get(other_id, null)
		if other != null and node_id in other.requires:
			return false
	_allocated.erase(node_id)
	_sync_spent_points()
	if _stats != null:
		_stats.rebuild_modifiers()        # pula bez source_id tego wezla -> modyfikatory znikaja
	allocation_changed.emit(node_id, false, points_left())
	return true


# ============================================================================
#  RESPEC (pelny reset za walute) — GDD 10: koszt schodkowy Orby / alternatywa Zloto
# ============================================================================

## Koszt schodkowy respecu w Orbach Przemiany wg liczby dotychczasowych respecow (GDD 10):
## 500 -> 1500 -> 4000 -> +4000 (cap). respec_index = ile razy juz respecowano.
const ORB_COST_STEPS: Array[int] = [500, 1500, 4000]
const ORB_COST_CAP_STEP: int = 4000

static func orb_cost_for(respec_index: int) -> int:
	if respec_index < ORB_COST_STEPS.size():
		return ORB_COST_STEPS[respec_index]
	# Po wyczerpaniu schodkow: ostatni schodek + (n-2)*cap, ale GDD mowi "+4000 cap" -> staly przyrost.
	return ORB_COST_STEPS[ORB_COST_STEPS.size() - 1] + (respec_index - ORB_COST_STEPS.size() + 1) * ORB_COST_CAP_STEP


## Alternatywny tani respec za Zloto (GDD 10): koszt = level * 50.
static func gold_cost_for(level: int) -> int:
	return maxi(0, level) * 50


## Pelny respec: zwraca WSZYSTKIE punkty (czysci alokacje) w zamian za walute.
##   currency_pool: Callable() -> int          (ile mamy danej waluty)
##   currency_spend: Callable(amount:int) -> void
##   cost: ile waluty kosztuje ten respec (policz orb_cost_for/gold_cost_for po stronie wolajacego)
## Zwraca liczbe zwroconych punktow (0 = nie wykonano: za malo waluty lub nic do zwrotu).
func respec(cost: int, currency_pool: Callable, currency_spend: Callable) -> int:
	if _allocated.is_empty():
		respec_failed.emit("nic do zresetowania")
		return 0
	if cost > 0:
		var have := 0
		if currency_pool.is_valid():
			have = int(currency_pool.call())
		if have < cost:
			respec_failed.emit("za malo waluty (%d/%d)" % [have, cost])
			return 0
		if currency_spend.is_valid():
			currency_spend.call(cost)
	var refunded := _allocated.size()
	_allocated.clear()
	_sync_spent_points()
	if _stats != null:
		_stats.rebuild_modifiers()        # cala pula drzewka znika -> staty wracaja do bazy+loot
	respec_done.emit(refunded, cost)
	return refunded


# ============================================================================
#  Provider StatsComponentu (TDD 3.2 pkt 2) — modyfikatory z zaalokowanych wezlow
# ============================================================================

## Zbiera modyfikatory ze WSZYSTKICH zaalokowanych wezlow. Kazdy modyfikator dostaje source=&"tree"
## i source_id = id wezla (do filtrowania/usuwania). Wartosci z PassiveNodeResource.modifiers
## sa kopiowane (StatModifier.make) — NIE mutujemy definicji z DB.
func collect_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for node_id in _allocated:
		var n: PassiveNodeResource = _node_by_id.get(node_id, null)
		if n == null:
			continue
		for m in n.modifiers:
			if m is StatModifier:
				out.append(StatModifier.make(m.stat, m.op, m.value, m.tags, &"tree", node_id))
	return out


## Liczba faktycznie wydanych punktow = suma cost_points zaalokowanych wezlow. Synchronizuje
## LevelComponent (available_points = granted - spent), wiec zwrot punktu jest automatyczny.
func _sync_spent_points() -> void:
	var spent := 0
	for node_id in _allocated:
		var n: PassiveNodeResource = _node_by_id.get(node_id, null)
		if n != null:
			spent += n.cost_points
	if level_component != null:
		level_component.set_spent_points(spent)
