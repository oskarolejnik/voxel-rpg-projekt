extends Node
## HotbarTest.gd — HEADLESS test hotbara (Krok 2): API slotów HUD + getter cooldownu gracza.
## Uruchomienie: godot --headless res://test/HotbarTest.tscn
##  (1) HUD: set_skill_slot/set_skill_cooldown/set_item_slot zapisują dane; indeks poza zakresem = no-op.
##  (2) Player: skill_cd(which) zwraca Vector2(frac 0..1, secs>=0); nieznany skill -> ZERO.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[HOTBAR] ..." + ALL OK + quit.

const HUDScript := preload("res://src/HUD.gd")
const PlayerScript := preload("res://src/Player.gd")

var _failures: int = 0


func _ready() -> void:
	print("[HOTBAR] === test hotbara (API HUD + cooldown gracza) start ===")
	await _test_hud_slots()
	await _test_player_cooldown()
	if _failures == 0:
		print("[HOTBAR] ALL OK")
	else:
		printerr("[HOTBAR] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[HOTBAR] FAIL: %s" % msg)


func _test_hud_slots() -> void:
	var hud = HUDScript.new()
	add_child(hud)
	await get_tree().process_frame   # _ready buduje sloty (puste)

	_check(hud._skill_slots.size() == hud.SKILL_SLOTS, "HUD: zła liczba slotów skilli (%d)" % hud._skill_slots.size())
	_check(hud._item_slots.size() == hud.ITEM_SLOTS, "HUD: zła liczba slotów przedmiotów (%d)" % hud._item_slots.size())

	hud.set_skill_slot(0, "whirl", "1")
	_check(String(hud._skill_slots[0]["icon"]) == "whirl", "set_skill_slot: ikona nie zapisana")
	_check(String(hud._skill_slots[0]["key"]) == "1", "set_skill_slot: klawisz nie zapisany")

	hud.set_skill_cooldown(0, 0.5, 2.0)
	_check(absf(float(hud._skill_slots[0]["cd"]) - 0.5) < 0.001, "set_skill_cooldown: frac nie zapisany")
	_check(absf(float(hud._skill_slots[0]["secs"]) - 2.0) < 0.001, "set_skill_cooldown: secs nie zapisane")
	hud.set_skill_cooldown(0, 5.0, 1.0)   # frac klampowany do 1
	_check(float(hud._skill_slots[0]["cd"]) <= 1.0, "set_skill_cooldown: frac NIE klampowany do 1")

	hud.set_item_slot(0, "potion", 3)
	_check(String(hud._item_slots[0]["icon"]) == "potion", "set_item_slot: ikona nie zapisana")
	_check(int(hud._item_slots[0]["count"]) == 3, "set_item_slot: licznik nie zapisany")

	hud.set_skill_slot(99, "x", "x")      # poza zakresem = no-op (brak crasha)
	hud.set_item_slot(-1, "x", 1)
	_check(not _hotbar_icon_empty(hud, "whirl"), "ikona 'whirl' nieznana (powinna istnieć)")
	for ic in ["dash", "bolt", "flame", "potion", "shield", "arrow", "ice", "aura"]:
		_check(not _hotbar_icon_empty(hud, ic), "ikona '%s' powinna istnieć (loadouty klas)" % ic)
	_check(_hotbar_icon_empty(hud, "nieistnieje"), "nieznana ikona powinna dać pusty dict")
	print("[HOTBAR] (1) API slotów HUD: skille/cooldown/przedmioty zapisują, bounds-safe OK")
	hud.queue_free()
	await get_tree().process_frame


func _hotbar_icon_empty(hud, name: String) -> bool:
	return (hud._hotbar_icon(name) as Dictionary).is_empty()


func _test_player_cooldown() -> void:
	var p = PlayerScript.new()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(p.has_method("skill_cd"), "Player nie ma metody skill_cd")
	var d: Vector2 = p.skill_cd(&"dash")
	_check(d.x >= 0.0 and d.x <= 1.0, "skill_cd(dash): frac poza [0,1] (%.2f)" % d.x)
	_check(d.y >= 0.0, "skill_cd(dash): secs ujemne (%.2f)" % d.y)
	var f: Vector2 = p.skill_cd(&"finisher")
	_check(f.x >= 0.0 and f.x <= 1.0, "skill_cd(finisher): frac poza [0,1] (%.2f)" % f.x)
	var z: Vector2 = p.skill_cd(&"nieistnieje")
	_check(z == Vector2.ZERO, "skill_cd(nieznany) powinno być ZERO (jest %s)" % str(z))
	print("[HOTBAR] (2) Player.skill_cd: dash=%.2f finisher=%.2f, nieznany=ZERO OK" % [d.x, f.x])
	p.queue_free()
	await get_tree().process_frame
