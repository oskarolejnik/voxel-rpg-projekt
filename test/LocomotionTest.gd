extends Node
## LocomotionTest.gd — HEADLESS test animacji lokomocji (Krok 1: backpedal + turn-in-place).
## Uruchomienie: godot --headless res://test/LocomotionTest.tscn
##
## Animacja w grze jest bramkowana is_on_floor() (headless = brak podłogi -> tylko _anim_air), więc
## wołamy funkcje animacji BEZPOŚREDNIO na realnym Player.gd i sprawdzamy KONTRAKT:
##  (1) BACKPEDAL: ruch DO TYŁU względem twarzy -> _loco_fwd ujemny (krok odwrócony); w przód -> dodatni.
##  (2) TURN-IN-PLACE: _anim_turn_in_place postępuje fazą kroku (przestępowanie zamiast ślizgu) bez błędu.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[LOCO] ..." + ALL OK + quit.

const PlayerScript := preload("res://src/Player.gd")

var _failures: int = 0


func _ready() -> void:
	print("[LOCO] === test lokomocji (backpedal + turn-in-place) start ===")
	await _test_backpedal()
	await _test_turn_in_place()
	if _failures == 0:
		print("[LOCO] ALL OK")
	else:
		printerr("[LOCO] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[LOCO] FAIL: %s" % msg)


func _make_player() -> Node:
	var p = PlayerScript.new()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	return p


# ============================================================================
#  (1) BACKPEDAL — kierunek kroku vs twarz (ruch w tył -> _loco_fwd ujemny)
# ============================================================================
func _test_backpedal() -> void:
	var p = await _make_player()
	var dt := 1.0 / 60.0

	# Twarz w -Z (przód modelu). Ruch w +Z = DO TYŁU względem twarzy -> backpedal.
	p._model.rotation.y = 0.0
	p.velocity = Vector3(0.0, 0.0, 4.0)
	for i in 80:
		p._anim_locomotion(dt, 4.0, false)
	_check(p._loco_fwd < -0.15, "BACKPEDAL: _loco_fwd nie ujemny przy ruchu w tył (%.2f)" % p._loco_fwd)

	# Ruch w -Z = DO PRZODU względem twarzy -> _loco_fwd dodatni (krok normalny).
	p.velocity = Vector3(0.0, 0.0, -4.0)
	for i in 80:
		p._anim_locomotion(dt, 4.0, false)
	_check(p._loco_fwd > 0.5, "FORWARD: _loco_fwd nie dodatni przy ruchu w przód (%.2f)" % p._loco_fwd)
	print("[LOCO] (1) kierunek kroku: tył->backpedal, przód->normalnie (fwd=%.2f) OK" % p._loco_fwd)
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (2) TURN-IN-PLACE — przestępowanie zamiast ślizgu przy obrocie w miejscu
# ============================================================================
func _test_turn_in_place() -> void:
	var p = await _make_player()
	var dt := 1.0 / 60.0
	var ph0: float = p._walk_phase
	for i in 40:
		p._anim_turn_in_place(dt, 5.0)        # symulujemy szybki obrót twarzy
	_check(p._walk_phase > ph0 + 0.5, "TURN-IN-PLACE: faza kroku nie postępuje (Δ=%.3f)" % (p._walk_phase - ph0))
	_check(p._leg_l != null and p._leg_r != null, "brak nóg do animacji turn-in-place")
	# Próg w wyborze stanu: turn_rate 1.8 to granica idle/turn-in-place.
	print("[LOCO] (2) turn-in-place: faza postępuje (Δ=%.2f), nogi przestępują OK" % (p._walk_phase - ph0))
	p.queue_free()
	await get_tree().process_frame
