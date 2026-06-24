extends Node
## ProgressionPowerTest.gd — headless test BACKLOG #12: bazowa moc per poziom + plastry drzewek klas.
## Uruchomienie: godot --headless res://test/ProgressionPowerTest.tscn
##
## Sprawdza:
##  (1) BAZOWA MOC: LevelComponent.collect_modifiers() na lvl 1 jest PUSTE (wsteczna zgodnosc bazy).
##  (2) BAZOWA MOC: po awansach lista modyfikatorow rosnie (max_hp + damage, INCREASED, skalowane).
##  (3) WPIECIE: LevelComponent.attach_stats(StatsComponent) -> awans -> get_stat(max_hp) WYZSZE
##      niz na lvl 1 (pula statow przelicza sie po awansie).
##  (4) DRZEWKA: SkillDB.tree(mage/ranger/rogue) wczytane i NIEPUSTE (maja wezly), z poprawnym class_id.
##  (5) DRZEWKO INTEGRACJA: SkillTreeComponent z plastrem mage'a pozwala wziac KORZEN (niepusty graf).
## Kod wyjscia: 0 = ALL OK, 1 = FAIL. Print "[PROG] ...".

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[PROG] FAIL: %s" % msg)


func _ready() -> void:
	print("[PROG] === Progression power (baseline + tree slice) test start ===")
	_test_baseline_empty_at_level_1()
	_test_baseline_grows_with_levels()
	_test_baseline_raises_get_stat()
	_test_class_trees_loaded()
	_test_tree_component_can_allocate_root()
	if _failures == 0:
		print("[PROG] ALL OK")
	else:
		printerr("[PROG] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


# ---------------------------------------------------------------------------
#  (1) Bazowa moc PUSTA na lvl 1 (wsteczna zgodnosc — baza bez bonusu)
# ---------------------------------------------------------------------------
func _test_baseline_empty_at_level_1() -> void:
	var lvl := LevelComponent.new()
	add_child(lvl)
	var mods := lvl.collect_modifiers()
	_check(mods.is_empty(), "lvl 1: collect_modifiers powinno byc puste, jest %d" % mods.size())
	lvl.queue_free()
	print("[PROG] (1) bazowa moc pusta na lvl 1 OK")


# ---------------------------------------------------------------------------
#  (2) Bazowa moc ROSNIE z poziomami (max_hp + damage INCREASED)
# ---------------------------------------------------------------------------
func _test_baseline_grows_with_levels() -> void:
	var lvl := LevelComponent.new()
	add_child(lvl)
	# Dosyp duzo XP -> wiele awansow (krzywa: 1->2 = 50 XP, kilka poziomow to ~setki XP).
	lvl.grant_xp(5000)
	_check(lvl.level > 1, "grant_xp nie awansowal (level=%d)" % lvl.level)
	var mods := lvl.collect_modifiers()
	_check(mods.size() == 2, "po awansach oczekiwano 2 modyfikatorow bazowych, jest %d" % mods.size())
	var has_hp := false
	var has_dmg := false
	var hp_val := 0.0
	for m in mods:
		if m.stat == &"max_hp":
			has_hp = true
			hp_val = m.value
			_check(m.op == StatModifier.Op.INCREASED, "max_hp bazowy nie jest INCREASED")
			_check(m.source == &"level", "max_hp bazowy ma zly source (%s)" % m.source)
		elif m.stat == &"damage":
			has_dmg = true
			_check(m.op == StatModifier.Op.INCREASED, "damage bazowy nie jest INCREASED")
	_check(has_hp, "brak modyfikatora bazowego max_hp")
	_check(has_dmg, "brak modyfikatora bazowego damage")
	# Skalowanie: lvl_above = level-1, +1% max_hp/poziom -> wartosc dokladnie (level-1)*0.01.
	var expected_hp := float(lvl.level - 1) * LevelComponent.BASELINE_HP_PER_LEVEL
	_check(is_equal_approx(hp_val, expected_hp),
		"max_hp bazowy %.4f != oczekiwane %.4f (level=%d)" % [hp_val, expected_hp, lvl.level])
	lvl.queue_free()
	print("[PROG] (2) bazowa moc rosnie z poziomami OK (lvl %d, +%.1f%% max_hp)" % [lvl.level, hp_val * 100.0])


# ---------------------------------------------------------------------------
#  (3) Wpiecie w StatsComponent: awans podnosi get_stat(max_hp)
# ---------------------------------------------------------------------------
func _test_baseline_raises_get_stat() -> void:
	var stats := StatsComponent.new()
	stats.base = StatBlock.new()              # baza max_hp = 100
	add_child(stats)                          # _ready -> rebuild
	var lvl := LevelComponent.new()
	add_child(lvl)
	lvl.attach_stats(stats)                   # rejestruje provider + rebuild
	var hp_before := stats.get_stat(&"max_hp")
	_check(is_equal_approx(hp_before, 100.0),
		"lvl 1: max_hp powinno byc baza 100, jest %.2f" % hp_before)
	lvl.grant_xp(5000)                        # awanse -> _notify_stats -> rebuild
	var hp_after := stats.get_stat(&"max_hp")
	_check(hp_after > hp_before,
		"po awansach max_hp nie wzroslo (%.2f -> %.2f)" % [hp_before, hp_after])
	# Sanity: wzrost ~ (level-1)*1% bazy 100.
	var expected := 100.0 * (1.0 + float(lvl.level - 1) * LevelComponent.BASELINE_HP_PER_LEVEL)
	_check(is_equal_approx(hp_after, expected),
		"max_hp po awansach %.2f != oczekiwane %.2f" % [hp_after, expected])
	lvl.queue_free()
	stats.queue_free()
	print("[PROG] (3) bazowa moc podnosi get_stat(max_hp) %.1f -> %.1f OK" % [hp_before, hp_after])


# ---------------------------------------------------------------------------
#  (4) Nowe plastry drzewek wczytane i niepuste (mage/ranger/rogue)
# ---------------------------------------------------------------------------
func _test_class_trees_loaded() -> void:
	if SkillDB == null:
		_check(false, "brak autoload SkillDB")
		return
	SkillDB.reload()
	for cid in [&"mage", &"ranger", &"rogue"]:
		var t: SkillTreeResource = SkillDB.tree(cid)
		_check(t != null, "SkillDB.tree(&\"%s\") == null (plaster nie wczytany)" % cid)
		if t == null:
			continue
		_check(t.class_id == cid, "drzewko %s ma zly class_id (%s)" % [cid, t.class_id])
		_check(t.nodes.size() > 0, "drzewko %s jest puste (0 wezlow)" % cid)
		_check(t.nodes.size() >= 7, "drzewko %s ma za malo wezlow (%d, oczekiwano ~8)" % [cid, t.nodes.size()])
		# Korzen = wezel bez prerekwizytow.
		var has_root := false
		for n in t.nodes:
			if n != null and n.requires.is_empty():
				has_root = true
				break
		_check(has_root, "drzewko %s nie ma korzenia (wezla bez 'requires')" % cid)
	# Warrior nadal dziala (wsteczna zgodnosc) — drzewko istnialo przed #12.
	var w: SkillTreeResource = SkillDB.tree(&"warrior")
	_check(w != null and w.nodes.size() > 0, "drzewko warrior zepsute po #12")
	print("[PROG] (4) plastry drzewek mage/ranger/rogue wczytane i niepuste OK")


# ---------------------------------------------------------------------------
#  (5) SkillTreeComponent z plastrem mage'a — korzen da sie wziac
# ---------------------------------------------------------------------------
func _test_tree_component_can_allocate_root() -> void:
	if SkillDB == null:
		return
	var t: SkillTreeResource = SkillDB.tree(&"mage")
	if t == null:
		_check(false, "brak drzewka mage do testu integracyjnego (5)")
		return
	var stats := StatsComponent.new()
	stats.base = StatBlock.new()
	add_child(stats)
	var lvl := LevelComponent.new()
	add_child(lvl)
	lvl.grant_xp(5000)                        # daj punkty (awanse 2..level -> punkty)
	var tree_comp := SkillTreeComponent.new()
	add_child(tree_comp)                      # _ready resolwuje stats (sibling)
	tree_comp.setup(t, lvl)
	# Znajdz korzen (bez requires) i sprobuj wziac.
	var root_id: StringName = &""
	for n in t.nodes:
		if n != null and n.requires.is_empty():
			root_id = n.id
			break
	_check(root_id != &"", "drzewko mage bez korzenia do alokacji")
	if root_id != &"":
		var ok := tree_comp.allocate(root_id)
		_check(ok, "nie udalo sie wziac korzenia mage'a (%s): %s"
			% [root_id, tree_comp.cannot_allocate_reason(root_id)])
		_check(tree_comp.is_allocated(root_id), "korzen mage'a nie jest zaalokowany po allocate")
	tree_comp.queue_free()
	lvl.queue_free()
	stats.queue_free()
	print("[PROG] (5) SkillTreeComponent bierze korzen plastra mage OK")
