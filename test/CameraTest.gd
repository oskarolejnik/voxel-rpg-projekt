extends Node
## CameraTest.gd — HEADLESS test KAMERY (fix drgań + łagodny zoom na terenie).
## Uruchomienie: godot --headless res://test/CameraTest.tscn
##
## NIE rusza działającej gry. Instancjuje REALNEGO Player.gd (kamera budowana w _ready) i weryfikuje
## KONTRAKT poprawki kamery:
##  (1) STRUKTURA: ramię startuje na pełnej długości (_cam_dist == spring_length); kamera jest
##      potomkiem SpringArm; SpringArm ma shape (shapecast) + jawną maskę = teren (1).
##  (2) ASYMETRIA BOOM: _smooth_boom „do środka" (teren wchodzi) reaguje SZYBCIEJ niż „na zewnątrz"
##      (teren znika) — anty-clip szybki, zoom-out łagodny. Test czysto deterministyczny.
##  (3) BRAK DRGAŃ (regresja z-fight): stojąc w miejscu, po ustabilizowaniu _camera.position.z jest
##      STAŁE klatka-do-klatki (dawniej oscylowało: SpringArm vs nadpisywanie z=0), a offset x/y ~0
##      (brak walk-bobu gdy gracz stoi). Boom-Z ujemny lub 0 (nigdy „przed" graczem).
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[CAMERA] ..." + ALL OK + quit.

const PlayerScript := preload("res://src/Player.gd")

var _failures: int = 0


func _ready() -> void:
	print("[CAMERA] === test kamery (drgania + zoom) start ===")
	await _test_structure()
	_test_boom_asymmetry()
	await _test_no_jitter_standing()
	await _test_tps_facing()

	if _failures == 0:
		print("[CAMERA] ALL OK")
	else:
		printerr("[CAMERA] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[CAMERA] FAIL: %s" % msg)


func _make_player() -> Node:
	var p = PlayerScript.new()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	return p


# ============================================================================
#  (1) STRUKTURA — ramię na pełnej długości, kamera pod SpringArm, shapecast+maska
# ============================================================================
func _test_structure() -> void:
	var p = await _make_player()
	_check(p._spring != null and p._camera != null, "brak _spring/_camera po _ready")
	_check(is_equal_approx(p._cam_dist, p._spring.spring_length), \
		"_cam_dist (%.2f) != spring_length (%.2f) na starcie" % [p._cam_dist, p._spring.spring_length])
	_check(p._camera.get_parent() == p._spring, "kamera NIE jest dzieckiem SpringArm (boom)")
	_check(p._spring.shape != null, "SpringArm bez shape (shapecast) — raczej raycast (więcej drgań na voxelach)")
	_check(p._spring.collision_mask == 1, "maska SpringArm != 1 (powinien kolidować TYLKO z terenem)")
	print("[CAMERA] (1) struktura: boom=%.2f m, shapecast=%s, maska=%d OK" \
		% [p._cam_dist, p._spring.shape != null, p._spring.collision_mask])
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (2) ASYMETRIA BOOM — „do środka" szybciej niż „na zewnątrz" (deterministyczne)
# ============================================================================
func _test_boom_asymmetry() -> void:
	var p = PlayerScript.new()
	add_child(p)
	# Pola @export i _cam_dist dostępne od razu; _smooth_boom nie wymaga zbudowanej kamery.
	var dt := 1.0 / 60.0
	var rest := 5.6

	# „Do środka": teren wchodzi (hit 5.6 -> 2.0). Jeden krok — duży skok (szybko, anty-clip).
	p._cam_dist = rest
	var d_in := rest - p._smooth_boom(2.0, dt)        # ile skróciliśmy w jednym kroku

	# „Na zewnątrz": teren znika (hit 2.0 -> 5.6), ta sama luka 3.6. Jeden krok — mały skok (łagodnie).
	p._cam_dist = 2.0
	var d_out := p._smooth_boom(5.6, dt) - 2.0        # ile wysunęliśmy w jednym kroku

	_check(d_in > d_out, "boom NIE asymetryczny: in=%.4f <= out=%.4f (zoom-in ma być szybszy)" % [d_in, d_out])
	_check(d_in > 0.0 and d_out > 0.0, "boom nie reaguje (in=%.4f out=%.4f)" % [d_in, d_out])
	# Zbieżność: po wielu krokach „do środka" dochodzi do celu.
	p._cam_dist = rest
	for i in 120:
		p._smooth_boom(2.0, dt)
	_check(absf(p._cam_dist - 2.0) < 0.05, "boom nie zbiega do celu (po 120 krokach _cam_dist=%.3f)" % p._cam_dist)
	print("[CAMERA] (2) asymetria boom: in=%.4f m/krok > out=%.4f m/krok, zbieżność OK" % [d_in, d_out])
	p.queue_free()


# ============================================================================
#  (3) BRAK DRGAŃ STOJĄC — z stabilne klatka-do-klatki + brak bobu (regresja z-fight)
# ============================================================================
func _test_no_jitter_standing() -> void:
	var p = await _make_player()
	p.velocity = Vector3.ZERO
	var dt := 1.0 / 60.0

	# Stabilizacja: kilkadziesiąt klatek na ustalenie się boomu.
	for i in 80:
		p._update_camera(dt)

	# Pomiar: kolejne klatki muszą dać IDENTYCZNĄ pozycję z (brak oscylacji fizyka↔render).
	var z_min := 1e9
	var z_max := -1e9
	var off_max := 0.0
	for i in 20:
		p._update_camera(dt)
		z_min = minf(z_min, p._camera.position.z)
		z_max = maxf(z_max, p._camera.position.z)
		off_max = maxf(off_max, Vector2(p._camera.position.x, p._camera.position.y).length())

	_check(z_max - z_min < 1.0e-3, "DRGANIA: z waha się o %.5f m między klatkami (powinno być ~0)" % (z_max - z_min))
	# SpringArm umieszcza kamerę ZA pivotem = DODATNI z (lokalnie). z<0 = kamera przed graczem (błąd!).
	_check(z_min >= -0.0001, "kamera nie jest ZA graczem (z=%.3f, oczekiwane >= 0 = +Z za pivotem)" % z_min)
	_check(off_max < 1.0e-3, "stojąc występuje offset x/y %.5f (powinien być ~0, brak walk-bobu)" % off_max)
	print("[CAMERA] (3) brak drgań stojąc: z stałe (Δ=%.6f m, z=%.2f), offset x/y=%.6f OK" \
		% [z_max - z_min, z_max, off_max])
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (4) TPS FACING — postać obraca się do yaw kamery (nie do kierunku ruchu)
# ============================================================================
func _test_tps_facing() -> void:
	var p = await _make_player()
	p.velocity = Vector3.ZERO              # stoi: w starym modelu NIE obracałby się; w TPS — obraca do kamery
	p._set_lock_target(null)               # bez locka (inaczej patrzyłby na cel)
	p._pivot.rotation.y = 1.0              # „obróć kamerę" o 1 rad
	for i in 150:
		p._process(1.0 / 60.0)
	var diff := absf(wrapf(p._model.rotation.y - 1.0, -PI, PI))
	_check(diff < 0.05, "TPS: model nie patrzy w yaw kamery stojąc (Δ=%.3f rad)" % diff)

	# Obrót kamery w drugą stronę — model nadąża (twarz zawsze ku kamerze/celownikowi).
	p._pivot.rotation.y = -0.8
	for i in 150:
		p._process(1.0 / 60.0)
	var diff2 := absf(wrapf(p._model.rotation.y - (-0.8), -PI, PI))
	_check(diff2 < 0.05, "TPS: model nie nadążył za obrotem kamery (Δ=%.3f rad)" % diff2)
	print("[CAMERA] (4) TPS facing: model śledzi yaw kamery stojąc (Δ=%.3f / %.3f rad) OK" % [diff, diff2])
	p.queue_free()
	await get_tree().process_frame
