extends Node
## MinimapHudTest.gd — headless test KOMPASU + RADARU w HUD (item #10 nawigacja).
## Uruchomienie: godot --headless res://test/MinimapHudTest.tscn
##
## Sprawdza:
##  (1) HUD buduje się i dodaje do drzewa bez błędu (preload res://src/HUD.gd).
##  (2) heading_label(yaw) zwraca poprawne rumby kardynalne (0->"N", PI/2->"E", PI->"S", 3PI/2->"W").
##  (3) Metody nawigacji są null-safe gdy brak referencji gracza/świata (kompas/radar/blipy),
##      a _paint po add_child + klatce nie crashuje (HUD budowany zanim istnieją referencje).
##  (4) Z wpiętym graczem + atrapą wrogów radar zbiera blipy (offsety względem gracza) bez crasha.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[MINIMAP] ...".

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[MINIMAP] FAIL: %s" % msg)


func _ready() -> void:
	print("[MINIMAP] === Minimap/compass HUD test start ===")
	await _test_build()
	_test_heading_labels()
	await _test_nullsafe_nav()
	await _test_blips_with_player()
	if _failures == 0:
		print("[MINIMAP] ALL OK")
	else:
		printerr("[MINIMAP] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


# ---------------------------------------------------------------------------
#  (1) Budowa HUD + klatka (bez referencji nawigacji = stan startowy).
# ---------------------------------------------------------------------------
func _build_hud() -> CanvasLayer:
	var HUDScript = preload("res://src/HUD.gd")
	var hud: CanvasLayer = HUDScript.new()
	add_child(hud)
	return hud


func _test_build() -> void:
	var hud := _build_hud()
	_check(hud != null, "HUD nie zbudowany z preload")
	await get_tree().process_frame
	# Druga klatka — _paint odpalany przez queue_redraw w _process; brak crasha = sukces.
	await get_tree().process_frame
	_check(is_instance_valid(hud), "HUD znikł/crash po klatkach")
	hud.queue_free()
	print("[MINIMAP] (1) HUD buduje się i renderuje bez crasha OK")


# ---------------------------------------------------------------------------
#  (2) heading_label — czysta funkcja rumbów kardynalnych.
# ---------------------------------------------------------------------------
func _test_heading_labels() -> void:
	var hud := _build_hud()
	_check(hud.heading_label(0.0) == "N",
		"yaw 0 != 'N' (jest '%s')" % hud.heading_label(0.0))
	_check(hud.heading_label(PI * 0.5) == "E",
		"yaw PI/2 != 'E' (jest '%s')" % hud.heading_label(PI * 0.5))
	_check(hud.heading_label(PI) == "S",
		"yaw PI != 'S' (jest '%s')" % hud.heading_label(PI))
	_check(hud.heading_label(PI * 1.5) == "W",
		"yaw 3PI/2 != 'W' (jest '%s')" % hud.heading_label(PI * 1.5))
	# Owijanie ujemnego yaw (-PI/2 == 3PI/2 -> "W").
	_check(hud.heading_label(-PI * 0.5) == "W",
		"yaw -PI/2 != 'W' (jest '%s')" % hud.heading_label(-PI * 0.5))
	hud.queue_free()
	print("[MINIMAP] (2) heading_label rumby kardynalne OK")


# ---------------------------------------------------------------------------
#  (3) Null-safe: brak gracza/świata — tint domyślny, brak blipów, brak crasha.
# ---------------------------------------------------------------------------
func _test_nullsafe_nav() -> void:
	var hud := _build_hud()
	# Bez set_nav_refs: _gather_enemy_blips puste, _biome_tint domyślny.
	var blips: Array = hud._gather_enemy_blips()
	_check(blips.is_empty(), "blipy niepuste bez gracza (jest %d)" % blips.size())
	var tint: Color = hud._biome_tint()
	_check(tint == hud.COMPASS_TINT_DEFAULT,
		"_biome_tint bez świata != domyślny")
	# Wpięcie samych nulli nie może crashować.
	hud.set_nav_refs(null, null)
	await get_tree().process_frame
	_check(is_instance_valid(hud), "HUD crash po set_nav_refs(null,null)")
	hud.queue_free()
	print("[MINIMAP] (3) nawigacja null-safe (brak gracza/świata) OK")


# ---------------------------------------------------------------------------
#  (4) Z graczem + atrapami wrogów: radar zbiera blipy względem gracza.
# ---------------------------------------------------------------------------
func _test_blips_with_player() -> void:
	var hud := _build_hud()
	var player := Node3D.new()
	add_child(player)
	player.global_position = Vector3(10.0, 0.0, 10.0)
	# Dwa wrogi w grupie "enemies" w zasięgu radaru.
	var e1 := Node3D.new(); add_child(e1); e1.add_to_group("enemies")
	e1.global_position = Vector3(15.0, 0.0, 10.0)   # +5 m na +x od gracza
	var e2 := Node3D.new(); add_child(e2); e2.add_to_group("enemies")
	e2.global_position = Vector3(10.0, 0.0, 4.0)    # -6 m na z od gracza
	# Wróg poza zasięgiem (RADAR_RANGE) — _radar go pominie (clamp), ale _gather i tak zbiera.
	hud.set_nav_refs(player, null)
	await get_tree().process_frame
	var blips: Array = hud._gather_enemy_blips()
	_check(blips.size() == 2, "oczekiwano 2 blipy, jest %d" % blips.size())
	_check(is_instance_valid(hud), "HUD crash z graczem+wrogami")
	# Heading z yaw gracza po wpięciu.
	player.global_rotation.y = 0.0
	hud.set_nav_refs(player, null)
	_check(hud.heading_label(hud._compass_yaw) == "N",
		"heading z yaw=0 gracza != 'N'")
	player.queue_free(); e1.queue_free(); e2.queue_free()
	hud.queue_free()
	print("[MINIMAP] (4) radar zbiera blipy względem gracza OK")
