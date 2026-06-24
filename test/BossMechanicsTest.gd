extends Node
## BossMechanicsTest.gd — headless test UNIKATOWEJ MECHANIKI BOSSA (#11): faza ENRAGE poniżej 50% HP.
## Uruchomienie: godot --headless res://test/BossMechanicsTest.tscn
##
## Sprawdza:
##  (1) Boss (threat_tier boss + set_boss_mechanics) z HP >50% — NIE jest enraged.
##  (2) Spadek HP <=50% (przez HealthComponent.apply_damage) -> _enraged true ORAZ buff statow
##      (attack_damage i move_speed wzrosly, attack_cooldown skrocony).
##  (3) Enrage jest JEDNORAZOWY: dalsze obrazenia nie podbijaja statow drugi raz.
##  (4) Zwykly (non-boss) wrog z wlaczona flaga NIGDY nie enrage (gating na threat_tier==boss).
##  (5) Boss bez set_boss_mechanics (default off) NIE enrage (wsteczna zgodnosc).
## Kod wyjscia: 0 = ALL OK, 1 = FAIL. Print "[BOSS] ...".

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[BOSS] FAIL: %s" % msg)


## Buduje gotowego Enemy w drzewie (po _ready -> komponenty wpiete). max_hp/threat_tier ustawiamy PRZED
## add_child, by _build_components zbudowal HealthComponent z docelowym maxem.
func _make_enemy(max_hp: float, tier: StringName, boss_mech: bool) -> Enemy:
	var e := Enemy.new()
	e.max_hp = max_hp
	e.hp = max_hp
	e.attack_damage = 10.0
	e.move_speed = 3.0
	e.attack_cooldown = 1.2
	e.threat_tier = tier
	if boss_mech:
		e.set_boss_mechanics(true)
	add_child(e)        # _ready -> _build_components -> HealthComponent.current_hp = max_hp
	return e


func _ready() -> void:
	print("[BOSS] === Boss mechanics (enrage) test start ===")
	_test_boss_no_enrage_above_half()
	_test_boss_enrages_below_half()
	_test_enrage_is_one_shot()
	_test_non_boss_never_enrages()
	_test_boss_without_mechanics_never_enrages()
	if _failures == 0:
		print("[BOSS] ALL OK")
	else:
		printerr("[BOSS] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


# ---------------------------------------------------------------------------
#  (1) Boss z HP >50% — nie enraged
# ---------------------------------------------------------------------------
func _test_boss_no_enrage_above_half() -> void:
	var e := _make_enemy(100.0, &"boss", true)
	_check(e._health != null, "boss nie zbudowal HealthComponent po _ready")
	# Zdejmij 40% (HP -> 60, wciaz >50%).
	if e._health != null:
		e._health.apply_damage(40.0)
	_check(not e.is_enraged(), "boss enrage przy HP>50%% (HP=%.0f)" % e.hp)
	e.queue_free()
	print("[BOSS] (1) boss HP>50%% nie enrage OK")


# ---------------------------------------------------------------------------
#  (2) Spadek <=50% -> enraged + buff statow
# ---------------------------------------------------------------------------
func _test_boss_enrages_below_half() -> void:
	var e := _make_enemy(100.0, &"boss", true)
	var dmg0 := e.attack_damage
	var spd0 := e.move_speed
	var cd0 := e.attack_cooldown
	_check(not e.is_enraged(), "boss enraged ZANIM oberwal (start)")
	# Zbij HP na 50% (HP -> 50.0 <= 100*0.5).
	if e._health != null:
		e._health.apply_damage(50.0)
	_check(e.is_enraged(), "boss NIE enrage przy HP<=50%% (HP=%.0f)" % e.hp)
	_check(e.attack_damage > dmg0,
		"enrage nie podbil attack_damage (%.2f -> %.2f)" % [dmg0, e.attack_damage])
	_check(e.move_speed > spd0,
		"enrage nie podbil move_speed (%.2f -> %.2f)" % [spd0, e.move_speed])
	_check(e.attack_cooldown < cd0,
		"enrage nie skrocil attack_cooldown (%.3f -> %.3f)" % [cd0, e.attack_cooldown])
	e.queue_free()
	print("[BOSS] (2) boss HP<=50%% enrage + buff statow OK")


# ---------------------------------------------------------------------------
#  (3) Enrage jednorazowy — dalsze obrazenia nie podbijaja statow drugi raz
# ---------------------------------------------------------------------------
func _test_enrage_is_one_shot() -> void:
	var e := _make_enemy(100.0, &"boss", true)
	if e._health != null:
		e._health.apply_damage(60.0)        # HP -> 40 (<=50%) => enrage
	_check(e.is_enraged(), "boss nie enrage po pierwszym progu")
	var dmg_after_first := e.attack_damage
	if e._health != null:
		e._health.apply_damage(10.0)        # HP -> 30, dalej ponizej progu
	_check(is_equal_approx(e.attack_damage, dmg_after_first),
		"enrage zadzialal DRUGI raz (dmg %.2f -> %.2f)" % [dmg_after_first, e.attack_damage])
	e.queue_free()
	print("[BOSS] (3) enrage jednorazowy OK")


# ---------------------------------------------------------------------------
#  (4) Zwykly (non-boss) wrog z flaga NIGDY nie enrage (gating na threat_tier==boss)
# ---------------------------------------------------------------------------
func _test_non_boss_never_enrages() -> void:
	# trash z bledne wlaczona flaga — gating na tier blokuje enrage.
	var e := _make_enemy(100.0, &"trash", true)
	var dmg0 := e.attack_damage
	if e._health != null:
		e._health.apply_damage(80.0)        # HP -> 20 (<=50%)
	_check(not e.is_enraged(), "non-boss (trash) enrage mimo gatingu")
	_check(is_equal_approx(e.attack_damage, dmg0), "non-boss podbil dmg (nie powinien)")
	e.queue_free()
	# elite tez nie (tylko boss ma enrage).
	var el := _make_enemy(100.0, &"elite", true)
	if el._health != null:
		el._health.apply_damage(80.0)
	_check(not el.is_enraged(), "elite enrage mimo gatingu (tylko boss)")
	el.queue_free()
	print("[BOSS] (4) non-boss (trash/elite) nigdy nie enrage OK")


# ---------------------------------------------------------------------------
#  (5) Boss bez set_boss_mechanics (default off) nie enrage (wsteczna zgodnosc)
# ---------------------------------------------------------------------------
func _test_boss_without_mechanics_never_enrages() -> void:
	var e := _make_enemy(100.0, &"boss", false)   # boss tier, ale mechanika OFF
	_check(not e.boss_mechanics, "boss_mechanics powinno byc OFF domyslnie")
	var dmg0 := e.attack_damage
	if e._health != null:
		e._health.apply_damage(80.0)        # HP -> 20
	_check(not e.is_enraged(), "boss bez wlaczonej mechaniki enrage (default powinien byc off)")
	_check(is_equal_approx(e.attack_damage, dmg0), "boss bez mechaniki podbil dmg")
	e.queue_free()
	print("[BOSS] (5) boss bez mechaniki nie enrage (default off) OK")
