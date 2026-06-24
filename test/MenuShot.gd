extends Node
## MenuShot.gd — narzędzie (NIE test): zrzut menu z globalnym motywem drewno-złoto.
## MENU=main|settings  godot --path <proj> res://test/MenuShot.tscn  -> _menu_<which>.png

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	var which := OS.get_environment("MENU")
	var node: Node
	if which == "settings":
		node = load("res://src/SettingsMenu.gd").new()
		add_child(node)
		if node is CanvasItem:
			(node as CanvasItem).visible = true
	else:
		which = "main"
		node = load("res://src/MainMenu.gd").new()
		add_child(node)
	for i in 50:
		await get_tree().process_frame
	get_tree().paused = false
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/oskar/Downloads/voxel-rpg/_menu_%s.png" % which)
	print("[MENUSHOT] zapisano _menu_%s.png" % which)
	get_tree().quit()
