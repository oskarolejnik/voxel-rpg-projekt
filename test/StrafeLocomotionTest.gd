extends Node
## StrafeLocomotionTest.gd — headless test STRAFE LOCOMOTION (lock-on circling, item #6).
## Uruchomienie: godot --headless res://test/StrafeLocomotionTest.tscn
##
## PROBLEM: przy lock-onie model patrzy na cel, a ciało jedzie BOKIEM — sagittalna animacja
## nóg szuruje stopami. Fix: _anim_locomotion czyta LOKALNĄ składową X prędkości i steruje nią
## bocznym krokiem (foot IK target.x) + abdukcją bioder (hip.rotation.z).
##
## Sprawdza:
##  (1) STRAFE — ruch BOCZNY względem twarzy (lokalny X) daje NIEZEROWĄ boczną składową kroku
##      (_loco_side != 0) oraz lateralne wychylenie nogi (hip.rotation.z != 0).
##  (2) BRAK REGRESJI — czysty ruch DO PRZODU względem twarzy daje ~zerową boczną składową
##      (_loco_side ≈ 0, hip.rotation.z ≈ 0) => zwykła lokomocja sagittalna NIENARUSZONA.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[STRAFE] ...".

const PlayerScript := preload("res://src/Player.gd")

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[STRAFE] FAIL: %s" % msg)


## Buduje gotowego Playera (po _ready) i ustawia stałe wagi lokomocji, by stride był niezerowy.
func _make_player() -> CharacterBody3D:
	var p: CharacterBody3D = PlayerScript.new()
	add_child(p)        # _ready -> _build_model (pivoty nóg) + komponenty
	# Pełna lokomocja: stride/lift = f(_gait,_run_blend); bez nich krok=0 i test byłby pusty.
	p._gait = 1.0
	p._run_blend = 1.0
	# Model patrzy „na wprost" (yaw=0): lokalny X = oś świata X, lokalny -Z = przód.
	p._model.rotation.y = 0.0
	return p


## Wymusza wiele klatek animacji, by wygładzane wartości (_loco_side, rotation.z) zdążyły narosnąć.
func _drive(p: CharacterBody3D, vel: Vector3, frames: int) -> void:
	p.velocity = vel
	for i in frames:
		p._anim_locomotion(0.05, Vector2(vel.x, vel.z).length(), true)


func _ready() -> void:
	print("[STRAFE] === Strafe locomotion test start ===")
	_test_strafe_produces_lateral()
	_test_forward_no_lateral_regression()
	if _failures == 0:
		print("[STRAFE] ALL OK")
	else:
		printerr("[STRAFE] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


# ---------------------------------------------------------------------------
#  (1) STRAFE — ruch boczny względem twarzy => niezerowa boczna składowa kroku + abdukcja biodra
# ---------------------------------------------------------------------------
func _test_strafe_produces_lateral() -> void:
	var p := _make_player()
	# Twarz na wprost (yaw=0), ciało jedzie w PRAWO (świat +X) => czysty lokalny +X (strafe w prawo).
	_drive(p, Vector3(6.0, 0.0, 0.0), 40)
	_check(p._loco_side > 0.2,
		"strafe w prawo nie dał dodatniej bocznej składowej (_loco_side=%.3f, oczek. >0.2)" % p._loco_side)
	# Abdukcja: lateralny cel stopy wymusza obrót biodra w bok (rotation.z). +X => niezerowe wychylenie.
	_check(absf(p._leg_l.rotation.z) > 0.01,
		"brak abdukcji biodra przy strafe (leg_l.rotation.z=%.4f, oczek. |.|>0.01)" % p._leg_l.rotation.z)
	_check(absf(p._leg_r.rotation.z) > 0.01,
		"brak abdukcji biodra R przy strafe (leg_r.rotation.z=%.4f)" % p._leg_r.rotation.z)
	p.queue_free()
	print("[STRAFE] (1) strafe => boczny krok + abdukcja biodra OK (_loco_side=%.3f, z=%.4f)"
		% [p._loco_side, p._leg_l.rotation.z])


# ---------------------------------------------------------------------------
#  (2) BRAK REGRESJI — czysty ruch do przodu => ~zerowa boczna składowa (lokomocja sagittalna nietknięta)
# ---------------------------------------------------------------------------
func _test_forward_no_lateral_regression() -> void:
	var p := _make_player()
	# Twarz na wprost (yaw=0), ciało biegnie DO PRZODU (świat -Z = lokalny przód) => lokalny X≈0.
	_drive(p, Vector3(0.0, 0.0, -6.0), 40)
	_check(absf(p._loco_side) < 0.05,
		"czysty bieg do przodu wprowadził boczną składową (_loco_side=%.3f, oczek. ≈0)" % p._loco_side)
	# Bramka |_loco_side|>0.2 => side_amt=0 => foot_x=0 => abdukcja wraca do 0 (zero regresji).
	_check(absf(p._leg_l.rotation.z) < 0.02,
		"bieg do przodu wprowadził abdukcję biodra (leg_l.rotation.z=%.4f, oczek. ≈0)" % p._leg_l.rotation.z)
	p.queue_free()
	print("[STRAFE] (2) bieg do przodu => zero bocznej składowej (brak regresji) OK (_loco_side=%.3f)"
		% p._loco_side)
