extends Node3D
## CreatureShot.gd — narzędzie (NIE test): renderuje POJEDYNCZEGO wroga wg PROBE_ENEMY i zapisuje PNG.
## Samowystarczalne (bez generacji świata): ziemia + światło + kamera + Enemy.new() z variant_id.
## Uruchom W OKNIE: PROBE_ENEMY=frost_spider godot --path <proj> res://test/CreatureShot.tscn
## Weryfikacja sylwetek rostera (spider/scorpion/serpent/frog/treant/golem/wyvern/spirit/worm).

const EnemyScript := preload("res://src/Enemy.gd")


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(900, 900))

	# Ziemia (mesh + kolizja), by wróg stał, nie spadał.
	var ground := StaticBody3D.new()
	var gm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(24.0, 24.0)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.40, 0.52, 0.34)
	pm.material = gmat
	gm.mesh = pm
	ground.add_child(gm)
	var gcol := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(24.0, 0.2, 24.0)
	gcol.shape = bs
	gcol.position = Vector3(0.0, -0.1, 0.0)
	ground.add_child(gcol)
	add_child(ground)

	# Światło + środowisko (ciepły dzień, miękki ambient — czytelne kolory/glow akcentów).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -38.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.56, 0.69, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.67, 0.74)
	env.ambient_light_energy = 0.65
	env.glow_enabled = true
	we.environment = env
	add_child(we)

	# Kamera: ¾ z przodu (przód wroga = -Z), celuje w środek sylwetki. look_at MUSI być PO add_child
	# (działa na global_transform — w drzewie), inaczej kamera patrzy w domyślne -Z i kadr ucieka w bok.
	var cam := Camera3D.new()
	cam.position = Vector3(1.7, 1.7, 4.9)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	cam.current = true

	# Wróg wg PROBE_ENEMY (sylwetka z variant_id -> _enemy_kind). Domyślna paleta (zielony, bez reskinu).
	var vid := OS.get_environment("PROBE_ENEMY")
	if vid == "":
		vid = "goblin"
	var e := EnemyScript.new()
	e.variant_id = StringName(vid)
	add_child(e)
	e.global_position = Vector3.ZERO
	await get_tree().process_frame
	await get_tree().process_frame
	e.set_physics_process(false)   # zamroź ruch/grawitację (model już zbudowany w _ready); _process zostaje (hover)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/oskar/Downloads/voxel-rpg/_shot.png")
	print("[CREATURE] shot saved: ", vid)
	get_tree().quit()
