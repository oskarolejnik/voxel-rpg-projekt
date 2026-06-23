extends Control
## HudShot.gd — narzędzie (NIE test): renderuje nowy HUD nad tłem udającym świat i zapisuje PNG.
## Uruchom W OKNIE (bez --headless): godot --path <proj> res://test/HudShot.tscn
## Pokazuje: panel statystyk (HP z ghost-trail + liczbą, Stamina, Furia), Poziom/XP, licznik wrogów,
## Combo melee, celownik. Zapisuje do _hud_shot.png i wychodzi.

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	await get_tree().process_frame

	# Tło udające jasny, zróżnicowany świat (test czytelności konturów).
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.43, 0.58, 0.39)
	add_child(bg)
	var sky := ColorRect.new()      # górny pas jaśniejszy (niebo)
	sky.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sky.offset_bottom = 300.0
	sky.color = Color(0.62, 0.74, 0.85)
	add_child(sky)
	var rock := ColorRect.new()     # ciemniejsza plama pod panelem (test kontrastu)
	rock.position = Vector2(0.0, 60.0)
	rock.size = Vector2(420.0, 240.0)
	rock.color = Color(0.20, 0.22, 0.20, 0.85)
	add_child(rock)

	var hud = preload("res://src/HUD.gd").new()
	add_child(hud)
	await get_tree().process_frame

	# Stan początkowy PEŁNY — paski zdążą się wypełnić.
	hud.on_hp_changed(100, 100)
	hud.on_stamina_changed(100, 100)
	hud.setup_class_resource("FURIA", Color(0.92, 0.42, 0.16), 100)
	hud.on_class_resource_changed(&"furia", 100, 100)
	hud.on_level_changed(7, 320, 800)
	hud.set_enemy_count(4)
	if hud.has_method("select_hotbar_slot"):
		hud.select_hotbar_slot(3)   # zaznacz slot 4 (jak na referencji)
	await _wait(0.55)

	# Trafienie: HP spada (pokaże ghost-trail), zasób/stamina częściowe, combo.
	hud.on_hp_changed(58, 100)
	hud.on_stamina_changed(63, 100)
	hud.on_class_resource_changed(&"furia", 46, 100)
	hud.set_combo(3)
	await _wait(0.20)             # HP dogoniło cel, ghost jeszcze zostaje → widoczny ślad

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("C:/Users/oskar/Downloads/voxel-rpg/_hud_shot.png")
	get_tree().quit()

func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()
