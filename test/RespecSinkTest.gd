extends Node
## RespecSinkTest.gd — headless test luki "darmowego respecu" (audyt 2026-06-24).
## Uruchomienie: godot --headless res://test/RespecSinkTest.tscn
##
## PROBLEM (zamkniety): deallocate() zwracal punkt BEZ kosztu waluty, wiec gracz mogl rozebrac
## caly build za darmo, omijajac platny respec(). Teraz cofniecie POJEDYNCZEGO wezla pobiera
## walute (Orb Drobny), inaczej moze byc odrzucone.
##
## Sprawdza:
##  (1) deallocate z pula waluty < koszt -> ODMOWA (false), wezel ZOSTAJE, punkt NIE wraca.
##  (2) deallocate z pula >= koszt -> sukces: POBIERA dokladnie `cost`, ZWRACA punkt, wezel znika.
##  (3) deallocate z allow_free=false i BEZ puli -> ODMOWA (twarda sciezka platna).
##  (4) deallocate domyslny (bez waluty, allow_free=true) -> nadal dziala (wsteczna zgodnosc).
##  (5) orb_drobny_cost_for() = uamek orb_cost_for, min 1.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[SINK] ...".

var _failures: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[SINK] FAIL: %s" % msg)


## Minimalny stos: StatsComponent + LevelComponent + SkillTreeComponent z malym drzewkiem.
## Zwraca [stats, level, tree].
func _make_stack() -> Array:
	var stats := StatsComponent.new()
	stats.base = StatBlock.new()
	add_child(stats)
	var level := LevelComponent.new()
	add_child(level)
	var tree := SkillTreeComponent.new()
	add_child(tree)
	tree.setup(_make_test_tree(), level)
	stats.register_provider(tree)
	return [stats, level, tree]


## Drzewko: pojedynczy korzen (cost 1, +5 dmg FLAT) — wystarczy do testu cofniecia liscia.
func _make_test_tree() -> SkillTreeResource:
	var t := SkillTreeResource.new()
	t.class_id = &"test"
	var root := PassiveNodeResource.new()
	root.id = &"root"
	root.display_name = "Korzen"
	root.cost_points = 1
	root.modifiers = [StatModifier.make(&"damage", StatModifier.Op.FLAT, 5.0, [], &"tree", &"root")]
	t.nodes = [root]
	return t


func _free_stack(stack: Array) -> void:
	for n in stack:
		if n is Node:
			n.queue_free()


func _ready() -> void:
	print("[SINK] === Respec sink (deallocate cost) test start ===")
	_test_reject_when_too_poor()
	_test_charges_and_refunds()
	_test_no_pool_no_free_rejected()
	_test_default_free_path_backward_compatible()
	_test_cost_helper()
	if _failures == 0:
		print("[SINK] ALL OK")
	else:
		printerr("[SINK] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


# ---------------------------------------------------------------------------
#  (1) Za malo waluty -> ODMOWA, wezel zostaje, punkt nie wraca
# ---------------------------------------------------------------------------
func _test_reject_when_too_poor() -> void:
	var stack := _make_stack()
	var level: LevelComponent = stack[1]
	var tree: SkillTreeComponent = stack[2]
	level.grant_xp(LevelComponent.total_xp_for_level(5))   # ma wolne punkty
	_check(tree.allocate(&"root"), "alokacja root OK (przygotowanie)")
	var pts_before := level.available_points()
	var orbs := 0   # pusta sakwa Orbow Drobnych
	var pool := func() -> int: return orbs
	var spend := func(_a: int) -> void: pass
	var ok := tree.deallocate(&"root", 1, pool, spend, false)
	_check(not ok, "deallocate z 0 Orbow -> ODMOWA (luka darmowego respecu zamknieta)")
	_check(tree.is_allocated(&"root"), "po odmowie wezel ZOSTAJE zaalokowany")
	_check(level.available_points() == pts_before, "po odmowie punkt NIE wraca (%d)" % level.available_points())
	print("[SINK] (1) za malo waluty -> odmowa, build nietkniety OK")
	_free_stack(stack)


# ---------------------------------------------------------------------------
#  (2) Stac na koszt -> sukces: pobiera dokladnie cost, zwraca punkt, wezel znika
# ---------------------------------------------------------------------------
func _test_charges_and_refunds() -> void:
	var stack := _make_stack()
	var level: LevelComponent = stack[1]
	var tree: SkillTreeComponent = stack[2]
	level.grant_xp(LevelComponent.total_xp_for_level(5))
	_check(tree.allocate(&"root"), "alokacja root OK (przygotowanie)")
	var pts_after_alloc := level.available_points()
	# Stan w jednoelementowych tablicach: lambdy GDScript przechwytują lokalne PRZEZ WARTOŚĆ, więc
	# mutowalny licznik musi być typem referencyjnym (Array), inaczej spend nie wpłynąłby na outer.
	var orbs := [3]
	var spent := [0]
	var pool := func() -> int: return orbs[0]
	var spend := func(a: int) -> void:
		orbs[0] -= a
		spent[0] += a
	var cost := 1
	var ok := tree.deallocate(&"root", cost, pool, spend, false)
	_check(ok, "deallocate ze stanem 3 Orby -> sukces")
	_check(spent[0] == cost, "pobrano dokladnie %d Orb(ow) (spent=%d)" % [cost, spent[0]])
	_check(orbs[0] == 2, "pula po oplacie = 2 (jest %d)" % orbs[0])
	_check(not tree.is_allocated(&"root"), "wezel cofniety (znika z alokacji)")
	_check(level.available_points() == pts_after_alloc + 1, "punkt zwrocony po cofnieciu")
	print("[SINK] (2) oplata pobrana, punkt zwrocony, wezel cofniety OK")
	_free_stack(stack)


# ---------------------------------------------------------------------------
#  (3) Brak puli + allow_free=false -> ODMOWA (twarda sciezka platna)
# ---------------------------------------------------------------------------
func _test_no_pool_no_free_rejected() -> void:
	var stack := _make_stack()
	var level: LevelComponent = stack[1]
	var tree: SkillTreeComponent = stack[2]
	level.grant_xp(LevelComponent.total_xp_for_level(5))
	_check(tree.allocate(&"root"), "alokacja root OK (przygotowanie)")
	var ok := tree.deallocate(&"root", 1, Callable(), Callable(), false)
	_check(not ok, "brak zrodla waluty + allow_free=false -> ODMOWA")
	_check(tree.is_allocated(&"root"), "wezel zostaje przy odmowie")
	print("[SINK] (3) brak puli + allow_free=false -> odmowa OK")
	_free_stack(stack)


# ---------------------------------------------------------------------------
#  (4) Domyslne wywolanie (dawni wolajacy, bez waluty) -> nadal dziala (wsteczna zgodnosc)
# ---------------------------------------------------------------------------
func _test_default_free_path_backward_compatible() -> void:
	var stack := _make_stack()
	var level: LevelComponent = stack[1]
	var tree: SkillTreeComponent = stack[2]
	level.grant_xp(LevelComponent.total_xp_for_level(5))
	_check(tree.allocate(&"root"), "alokacja root OK (przygotowanie)")
	var pts_after_alloc := level.available_points()
	var ok := tree.deallocate(&"root")   # dawna sygnatura: allow_free=true domyslnie
	_check(ok, "deallocate(node) bez waluty nadal dziala (dawni wolajacy/UI)")
	_check(not tree.is_allocated(&"root"), "wezel cofniety (sciezka darmowa dozwolona)")
	_check(level.available_points() == pts_after_alloc + 1, "punkt zwrocony (wsteczna zgodnosc)")
	print("[SINK] (4) domyslne deallocate bez waluty -> wsteczna zgodnosc OK")
	_free_stack(stack)


# ---------------------------------------------------------------------------
#  (5) orb_drobny_cost_for = uamek orb_cost_for, min 1
# ---------------------------------------------------------------------------
func _test_cost_helper() -> void:
	var c0 := SkillTreeComponent.orb_drobny_cost_for(0)   # orb_cost_for(0)=500 -> 5
	var c2 := SkillTreeComponent.orb_drobny_cost_for(2)   # orb_cost_for(2)=4000 -> 40
	_check(c0 == 5, "orb_drobny_cost_for(0)=5 (jest %d)" % c0)
	_check(c2 == 40, "orb_drobny_cost_for(2)=40 (jest %d)" % c2)
	_check(SkillTreeComponent.orb_drobny_cost_for(0) >= 1, "koszt drobny zawsze >= 1")
	print("[SINK] (5) orb_drobny_cost_for = uamek orb_cost_for OK")
