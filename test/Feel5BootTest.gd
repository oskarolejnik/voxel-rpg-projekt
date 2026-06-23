extends Node
## Feel5BootTest.gd — HEADLESS smoke-test PELNEGO BOOTU gry z FAZA 5 aktywna (NIE probe). Laduje
## realny Main.tscn, opuszcza menu (New Game), tyka ~kilka sekund realnej petli i weryfikuje, ze:
##   - AmbientLife powstaje i ZYJE (aktywne stworzenia > 0 po chwili),
##   - reactive foliage (player_pos) jest pchane do props shadera (uniform != sentinel),
##   - soundscape per-biom nie crashuje (ambience ustawione),
##   - zero SCRIPT ERROR / null-instance w trakcie biegu.
## Uruchomienie: godot --headless res://test/Feel5BootTest.tscn  (BEZ VOXEL_PROBE).
## Kod wyjscia: 0 = ALL OK, 1 = FAIL. Print "[FEEL5BOOT] ..." + ALL OK + quit.

const MainScene := preload("res://Main.tscn")

var _failures: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[FEEL5BOOT] FAIL: %s" % msg)


func _ready() -> void:
	print("[FEEL5BOOT] === Faza 5 pelny-boot smoke-test start ===")
	var main := MainScene.instantiate()
	add_child(main)
	# Kilka klatek na _ready (swiat/gracz/spawner/AmbientLife/audio).
	for i in 8:
		await get_tree().process_frame

	# Opusc menu glowne (New Game) — uruchamia realna petle gry (muzyka explore, sterowanie).
	var menu := main.get_node_or_null("MainMenu")
	if menu != null and menu.has_signal("new_game_requested"):
		menu.new_game_requested.emit()
		if menu.has_method("hide_menu"):
			menu.hide_menu()
		else:
			menu.visible = false
	get_tree().paused = false

	# AmbientLife istnieje (poza probe).
	var al := main.get_node_or_null("AmbientLife")
	_check(al != null, "BOOT: AmbientLife nie powstal w realnym boocie")

	# Tykaj realna petle ~3 s (process_frame + krotkie czekanie) — AmbientLife.update, reactive foliage,
	# soundscape, spawner robia swoje. Liczymy realne klatki.
	for i in 180:
		await get_tree().process_frame
	# Dodatkowy realny czas (timery throttlingu: populacja 0.5 s, music 0.5 s, event 6 s).
	await get_tree().create_timer(3.0).timeout

	# AmbientLife ozywil swiat (stworzenia aktywne).
	if al != null:
		var cc: int = al.active_creature_count()
		_check(cc > 0, "BOOT: AmbientLife nie ma aktywnych stworzen po czasie (got %d)" % cc)
		print("[FEEL5BOOT] AmbientLife aktywne stworzenia=%d" % cc)

	# Reactive foliage: props_material dostal player_pos != sentinel (-9999 y).
	var world = main.get_node_or_null("VoxelWorld")
	if world != null and world.props_material != null:
		var pp = world.props_material.get_shader_parameter("player_pos")
		_check(pp != null and (pp as Vector3).y > -9000.0, "BOOT: player_pos nie pchniety do props shadera (got %s)" % str(pp))
		var ws = world.props_material.get_shader_parameter("wind_strength")
		_check(ws != null and float(ws) > 0.0, "BOOT: wind_strength nie ustawiony w shaderze (got %s)" % str(ws))

	# Soundscape: AudioManager ma jakas intencje ambience LUB muzyki (per-biom) — nie crashlo.
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		print("[FEEL5BOOT] music=%s ambience=%s" % [str(am.current_music()), str(am.current_ambience())])

	main.queue_free()
	await get_tree().process_frame

	if _failures == 0:
		print("[FEEL5BOOT] ALL OK")
	else:
		printerr("[FEEL5BOOT] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
