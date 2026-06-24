extends Node
## ConsumableTest.gd — HEADLESS test mikstur (Krok 7): startowe consumable w plecaku, use_consumable
## leczy/uzupełnia zasób + dekrementuje licznik; consumable_count odzwierciedla plecak.
## Uruchomienie: godot --headless res://test/ConsumableTest.tscn. Print "[CONSUM] ..." + ALL OK.

const PlayerScript := preload("res://src/Player.gd")
const InvScript := preload("res://components/InventoryComponent.gd")

var _failures: int = 0


func _ready() -> void:
	print("[CONSUM] === test mikstur (krok 7) start ===")
	await _test()
	if _failures == 0:
		print("[CONSUM] ALL OK")
	else:
		printerr("[CONSUM] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[CONSUM] FAIL: %s" % msg)


func _test() -> void:
	var p = PlayerScript.new()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	var inv = InvScript.new()
	p.add_child(inv)                      # _find_inventory() znajdzie InventoryComponent wśród dzieci
	await get_tree().process_frame

	# Startowe mikstury.
	p.grant_starting_consumables()
	_check(p.consumable_count(&"healing_potion") == 3, "oczekiwano 3 mikstur leczenia (jest %d)" % p.consumable_count(&"healing_potion"))
	_check(p.consumable_count(&"stamina_potion") == 2, "oczekiwano 2 mikstur wytrwałości (jest %d)" % p.consumable_count(&"stamina_potion"))
	p.grant_starting_consumables()        # idempotencja — drugie wywołanie nic nie dodaje
	_check(p.consumable_count(&"healing_potion") == 3, "grant NIE idempotentny (jest %d)" % p.consumable_count(&"healing_potion"))

	# Leczenie: obniż HP, użyj mikstury -> HP rośnie, licznik -1.
	if p._health != null:
		p._health.current_hp = 20.0
	p.hp = 20.0
	var ok := p.use_consumable(&"healing_potion")
	_check(ok, "use_consumable(healing) powinno zwrócić true")
	_check(p.consumable_count(&"healing_potion") == 2, "licznik leczenia nie zdekrementowany (jest %d)" % p.consumable_count(&"healing_potion"))
	var hp_now: float = p._health.current_hp if p._health != null else p.hp
	_check(hp_now > 20.0, "HP nie wzrosło po użyciu mikstury (jest %.1f)" % hp_now)

	# Wytrwałość: obniż staminę, użyj -> rośnie, licznik -1.
	p.stamina = 10.0
	p.use_consumable(&"stamina_potion")
	_check(p.stamina > 10.0, "stamina nie wzrosła po miksturze (jest %.1f)" % p.stamina)
	_check(p.consumable_count(&"stamina_potion") == 1, "licznik wytrwałości nie -1 (jest %d)" % p.consumable_count(&"stamina_potion"))

	# Brak itemu -> false, brak efektu.
	_check(not p.use_consumable(&"nieistnieje"), "use nieistniejącego powinno = false")
	print("[CONSUM] (1) mikstury: grant 3/2 (idempotentny), leczenie+wytrwałość działają, dekrement OK")
	p.queue_free()
	await get_tree().process_frame
