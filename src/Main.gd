extends Node3D
## Main.gd — buduje świat startowy.
## Etap 2: zamiast płaskiej podłogi mamy proceduralny, chunkowany teren voxelowy.
## Etap A: żywy świat — roślinność/obiekty (w Chunk.gd) + cykl dnia i nocy (DayNight).
## Etap 3 (R1): spawn wrogów (Enemy) blisko gracza + HUD walki (HP/stamina + ekran śmierci).
##
## Cały świat tworzymy w KODZIE (a nie klikając w edytorze), z dwóch powodów:
##  1) projekt na pewno się uruchomi, nawet jeśli czegoś nie kliknąłeś w edytorze,
##  2) możesz przeczytać linijka po linijce, co i dlaczego powstaje.

# Wczytujemy skrypt gracza, żeby móc go „doczepić” do tworzonej w kodzie postaci.
const PlayerScript := preload("res://src/Player.gd")
# Wczytujemy menedżera świata voxelowego (teren generowany proceduralnie).
const VoxelWorldScript := preload("res://src/world/VoxelWorld.gd")
# Wczytujemy sterownik cyklu dnia i nocy (animuje słońce/niebo/ambient/mgłę).
const DayNightScript := preload("res://src/DayNight.gd")
# Wróg (Goblin Critter) + AI. Po imporcie class_name można też Enemy.new().
const EnemyScript := preload("res://src/Enemy.gd")
# Skrypt HUD-a walki (paski HP/stamina + ekran śmierci).
const HUDScript := preload("res://src/HUD.gd")
# ETAP 2: ekran ekwipunku + toast lootu (osobna warstwa CanvasLayer) i encja lootu w świecie.
const InventoryUIScript := preload("res://src/InventoryUI.gd")
const SkillTreeUIScript := preload("res://src/SkillTreeUI.gd")
const LootDropScript := preload("res://src/LootDrop.gd")
const InventoryComponentScript := preload("res://components/InventoryComponent.gd")

# Referencje przechowywane jako pola — VoxelWorld potrzebuje gracza do streamingu.
var _world: VoxelWorld
var _player_ref: CharacterBody3D

# Referencje środowiska — trzymane jako pola, bo DayNight je animuje co klatkę.
var _sun: DirectionalLight3D
var _sky_mat: ProceduralSkyMaterial
var _environment: Environment
var _day_night: DayNight

# Cząsteczki ambient (Faza 1C): pył w dzień, świetliki nocą.
var _ambient_day: GPUParticles3D
var _fireflies: GPUParticles3D

# HUD walki + licznik żywych wrogów.
var _hud: CanvasLayer
var _enemies_alive: int = 0
# ETAP 4: deterministyczny spawner wrogów wg biomu + seeda (zastępuje stały 3×).
var _spawner: WorldSpawner
# ETAP 5: orkiestracja wejść dungeonów + przejście świat<->dungeon (instancja efemeryczna).
var _dungeon_mgr: DungeonManager

# ETAP 2: ekran ekwipunku/toast lootu + ekwipunek gracza (komponent).
var _inv_ui: InventoryUI
var _inventory: InventoryComponent
# ETAP 3: ekran drzewka umiejetnosci (toggle K).
var _tree_ui: SkillTreeUI

# Licznik FPS (diagnostyka wydajności) — róg ekranu, aktualizowany w _process.
var _fps_label: Label

# Opóźnienie respawnu gracza po śmierci (s). Wystawione jako eksport, by nie było
# magiczną stałą rozjeżdżającą się z respawn_iframes gracza (1,5 s nietykalności).
# Zasada strojenia: i-frames gracza powinny być >= czasu od respawnu do odzyskania
# kontroli — inaczej tuż po odrodzeniu można od razu oberwać.
@export var respawn_delay: float = 1.6

func _ready() -> void:
	# KOLEJNOŚĆ (Faza 2B): świat PRZED środowiskiem — _setup_environment liczy zasięg mgły
	# (fog_depth_end) z RZECZYWISTEGO far_dist instancji VoxelWorld (review #minor: wcześniej
	# far_m był zahardkodowanym literałem 112 m i NIE śledził zmiany far_dist w inspektorze).
	# _setup_world tworzy tylko węzeł + konfiguruje szum/materiały w _ready — zero zależności
	# od Environment, więc reorder jest bezpieczny.
	_setup_world()         # proceduralny teren voxelowy (zastępuje płaską podłogę)
	_setup_environment()   # słońce + niebo + światło otoczenia + cykl dnia i nocy
	_spawn_player()        # nasza postać — stawiana NA terenie przez height_at()
	_spawn_enemies()       # 3 wrogów blisko gracza (po prime() terenu wokół spawnu)
	_setup_hud()           # podpowiedź ze sterowaniem + HUD walki
	_setup_vignette()      # Faza 0B: winieta (przyciemnienie krawędzi ekranu)
	_setup_ambient_fx()    # Faza 1C: świetliki nocą / pył w dzień
	_setup_fps_counter()   # diagnostyka: licznik FPS w rogu (do strojenia wydajności)
	# Sonda zrzutów tylko gdy uruchomione z VOXEL_PROBE != "" — normalne F5 gra bez sondy.
	if OS.get_environment("VOXEL_PROBE") != "":
		if OS.get_environment("VOXEL_PROBE") == "stress":
			_stress_run()   # test wątkowego streamingu pod ruchem (FPS + wycieki chunków)
		elif OS.get_environment("VOXEL_PROBE") == "walk":
			_walk_test()    # test traversalu: wciska W, loguje pozycję (utykanie / wchodzenie na progi)
		else:
			_probe_shot()

## Test traversalu terenu: wstrzykuje wciśnięcie W i loguje pozycję — weryfikuje, czy postać
## PŁYNNIE idzie po voxelowych schodkach (movedXZ>0, Y rośnie) bez utykania i bez skakania.
func _walk_test() -> void:
	_day_night.running = false
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().create_timer(2.0).timeout   # prime terenu wokół spawnu
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)   # „trzymaj W" — gracz idzie w -Z (yaw kamery = 0)
	var t0 := Time.get_ticks_msec()
	var last_pos := _player_ref.global_position
	var stuck := 0
	var max_stuck := 0
	for i in 24:
		for _f in 12:
			await get_tree().process_frame
		var p := _player_ref.global_position
		var moved := Vector2(p.x - last_pos.x, p.z - last_pos.z).length()
		if moved < 0.03:
			stuck += 1; max_stuck = maxi(max_stuck, stuck)
		else:
			stuck = 0
		print("[WALK] t=%.1f pos=(%.1f,%.1f,%.1f) movedXZ=%.2f floor=%s vy=%.2f stuck=%d" % [
			float(Time.get_ticks_msec() - t0) / 1000.0, p.x, p.y, p.z, moved,
			str(_player_ref.is_on_floor()), _player_ref.velocity.y, stuck])
		last_pos = p
	print("[WALK] DONE max_kolejnych_stuck=", max_stuck)
	get_tree().quit()

## Test 2A: teleportuje gracza przez świat (wymusza streaming w ruchu) i loguje FPS +
## liczbę chunków loaded/pending/abandoned. Wyciek = monotoniczny wzrost loaded/abandoned.
func _stress_run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # prawdziwy FPS, bez capu 60
	_day_night.running = false
	await get_tree().create_timer(2.0).timeout   # pozwól prime + pierwszym chunkom dopłynąć
	# Bieg PACOWANY CZASEM: 8 m/s (realny gracz) niezależnie od FPS. ~8 s ruchu.
	var speed := 8.0
	var t0 := Time.get_ticks_msec()
	var loaded_min := 99999
	var next_log := 0
	while true:
		var elapsed := float(Time.get_ticks_msec() - t0) / 1000.0
		if elapsed > 8.0:
			break
		var px := speed * elapsed
		var gy := _world.height_at(px, 0.0) + 3.0
		_player_ref.global_position = Vector3(px, gy, 0.0)
		await get_tree().process_frame
		var loaded: int = _world._loaded.size()
		if loaded < loaded_min: loaded_min = loaded
		if int(elapsed) >= next_log:
			next_log += 1
			print("[STRESS] t=", int(elapsed), "s x=", int(px), " fps=", Engine.get_frames_per_second(),
				" loaded=", loaded, " pending=", _world._pending.size(),
				" abandoned=", _world._abandoned.size(), " queue=", _world._build_queue.size())
	print("[STRESS] MOVE_DONE loaded_min_during_run=", loaded_min)
	# Faza osiadania: STOP ruchu, pozwól dokończyć taski i zreapować porzucone.
	# Poprawnie: abandoned->0, pending->0, loaded->~49 (chunki wokół ostatniej pozycji).
	print("[STRESS] settling 180 frames (no movement)...")
	for _s in 180:
		await get_tree().process_frame
	print("[STRESS] AFTER_SETTLE loaded=", _world._loaded.size(),
		" pending=", _world._pending.size(),
		" abandoned=", _world._abandoned.size(),
		" queue=", _world._build_queue.size())
	get_tree().quit()

# Licznik FPS w rogu — prosty wskaźnik do strojenia wydajności (diagnostyka; można usunąć).
func _setup_fps_counter() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10   # nad HUD-em
	_fps_label = Label.new()
	_fps_label.text = "FPS: --"
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.position = Vector2(-118.0, 30.0)   # prawy-górny róg, pod licznikiem wrogów
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.add_theme_font_size_override("font_size", 18)
	layer.add_child(_fps_label)
	add_child(layer)

# Winieta — pełnoekranowy ColorRect z shaderem, pod HUD-em walki.
func _setup_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/vignette.gdshader")
	cr.material = mat
	layer.add_child(cr)
	add_child(layer)

# --- Faza 1C: cząsteczki ambient (świetliki nocą + pył w dzień), podążają za graczem ---
func _setup_ambient_fx() -> void:
	_fireflies = _make_particles(44, Vector3(14, 7, 14), 0.22, Color(0.85, 1.0, 0.45), 7.0, 0.05, 0.22, 5.0)
	_ambient_day = _make_particles(46, Vector3(15, 9, 15), 0.05, Color(1.0, 0.95, 0.8), 1.2, 0.04, 0.18, 8.0)

func _make_particles(amount: int, box: Vector3, msize: float, col: Color, emis: float, vmin: float, vmax: float, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false   # cząsteczki zostają w świecie, gdy emiter (gracz) się rusza
	p.preprocess = life      # od razu widoczne (nie czekamy na spawn)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.gravity = Vector3.ZERO
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 180.0
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	p.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(msize, msize)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = emis
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = mat
	p.draw_pass_1 = mesh
	add_child(p)
	return p

func _process(_delta: float) -> void:
	if _fps_label != null:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	# ETAP 4: HUD licznika wrogów śledzi DYNAMICZNY spawn (regiony aktywują się w czasie).
	if _spawner != null and _hud != null and _hud.has_method("set_enemy_count"):
		var n := _spawner.active_count()
		if n != _enemies_alive:
			_enemies_alive = n
			_hud.set_enemy_count(n)
	if _player_ref == null or _fireflies == null:
		return
	var pos := _player_ref.global_position
	_fireflies.global_position = pos
	_ambient_day.global_position = pos
	var t: float = _day_night.time_of_day if _day_night else 0.5
	var night := t < 0.18 or t > 0.82
	_fireflies.emitting = night
	_ambient_day.emitting = not night

# TYMCZASOWE: stała sceneria do porównań before/after (stała pora + kąt kamery), zrzut, wyjście.
func _probe_shot() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_day_night.running = false
	var _pt := OS.get_environment("VOXEL_PROBE")
	_day_night.set_time(0.0 if _pt == "night" else (0.76 if _pt == "gold" else 0.40))
	var mode := OS.get_environment("VOXEL_PROBE")

	# Tryb "char": usuń wrogów (spawnują przy graczu), by nie oberwać (czerwony flash) podczas pozowania.
	if mode == "char":
		for e in get_tree().get_nodes_in_group("enemies"):
			e.queue_free()

	# Tryb "water": przenieś gracza nad najniższy punkt terenu w okolicy (tam stoi woda).
	var water_yaw_deg := 35.0   # domyślny yaw kamery (tryb nie-woda)
	if mode == "water":
		# Szukamy BRZEGU: ląd tuż nad poziomem morza, z wodą w sąsiedztwie — gracz stoi
		# na lądzie, a kamera patrzy W STRONĘ wody pod małym kątem (grazing → fresnel/piana).
		var sea := 24  # SEA_LEVEL w voxelach
		var spot := Vector2.ZERO
		var spot_y := 20.0
		var wdir := Vector2(1, 0)
		var found := false
		for gx in range(-256, 257, 6):
			for gz in range(-256, 257, 6):
				var sv := _world.surface_height(gx, gz)
				if sv > sea and sv <= sea + 4:
					if _world.surface_height(gx + 4, gz) < sea: wdir = Vector2(1, 0)
					elif _world.surface_height(gx - 4, gz) < sea: wdir = Vector2(-1, 0)
					elif _world.surface_height(gx, gz + 4) < sea: wdir = Vector2(0, 1)
					elif _world.surface_height(gx, gz - 4) < sea: wdir = Vector2(0, -1)
					else: continue
					spot = Vector2(gx, gz)
					spot_y = _world.height_at(float(gx), float(gz))
					found = true
					break
			if found:
				break
		# Stań nieco cofnięty od wody; yaw kamery skierowany na wodę (przód = -Z).
		_player_ref.global_position = Vector3(spot.x - wdir.x * 1.0, spot_y + 2.0, spot.y - wdir.y * 1.0)
		_world.prime(_world.world_to_chunk(_player_ref.global_position), 3)
		water_yaw_deg = rad_to_deg(atan2(-wdir.x, -wdir.y))
		print("[PROBE] shore spot=", spot, " surface_y=", spot_y, " wdir=", wdir, " found=", found)

	# Tryb "tree": znajdź kafel z drzewem (odtworzenie warunku z Chunk._place_features) i stań obok.
	if mode == "tree":
		var tm := VoxelChunk.TREE_MARGIN
		var tfound := false
		for gx in range(-160, 161):
			for gz in range(-160, 161):
				var sy := _world.surface_height(gx, gz)
				if sy <= VoxelChunk.BEACH_MAX_Y or sy >= VoxelChunk.ROCK_MIN_Y:
					continue   # tylko trawa (nie plaża/skała/śnieg)
				var lx := ((gx % VoxelChunk.CHUNK_SIZE) + VoxelChunk.CHUNK_SIZE) % VoxelChunk.CHUNK_SIZE
				var lz := ((gz % VoxelChunk.CHUNK_SIZE) + VoxelChunk.CHUNK_SIZE) % VoxelChunk.CHUNK_SIZE
				if lx < tm or lx > VoxelChunk.CHUNK_SIZE - 1 - tm or lz < tm or lz > VoxelChunk.CHUNK_SIZE - 1 - tm:
					continue
				if _world.feature_hash(gx, gz, VoxelChunk.SALT_TREE) < VoxelChunk.TREE_PROB:
					_player_ref.global_position = Vector3(float(gx), _world.height_at(float(gx), float(gz)) + 2.0, float(gz))
					tfound = true
					break
			if tfound: break
		_world.prime(_world.world_to_chunk(_player_ref.global_position), 3)
		print("[PROBE] tree found=", tfound, " pos=", _player_ref.global_position)

	await get_tree().create_timer(6.0).timeout
	var ppos := _player_ref.global_position
	if mode == "char" or mode == "props" or mode == "vista" or mode == "tree":
		# Dedykowana kamera — omija gameplayowy SpringArm (który cofa się przy kolizji),
		# daje deterministyczny kadr zbliżenia. Przód postaci = -Z (oczy/twarz tam).
		var cam := Camera3D.new()
		add_child(cam)
		if mode == "char":
			# Wyłącz pętle gracza, by _animate nie nadpisał pozy; ustaw POZĘ CHODU ręcznie
			# (L noga w przód ze zgiętym kolanem, R w tył prosto; ręce przeciwnie) — weryfikacja rigu.
			_player_ref.set_process(false)
			_player_ref.set_physics_process(false)
			var P := _player_ref
			var pl := P.get("_leg_l") as Node3D
			if pl: pl.rotation.x = 0.5
			var pll := P.get("_leg_l_lo") as Node3D
			if pll: pll.rotation.x = -0.85
			var pr := P.get("_leg_r") as Node3D
			if pr: pr.rotation.x = -0.4
			var prl := P.get("_leg_r_lo") as Node3D
			if prl: prl.rotation.x = -0.05
			var al := P.get("_arm_l") as Node3D
			if al: al.rotation.x = -0.4
			var ar := P.get("_arm_r") as Node3D
			if ar: ar.rotation.x = 0.45
			var arl := P.get("_arm_r_lo") as Node3D
			if arl: arl.rotation.x = -0.55
			cam.global_position = ppos + Vector3(0.8, 1.25, -2.3)   # ciaśniej, od przodu/boku
			cam.look_at(ppos + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		elif mode == "vista":
			cam.global_position = ppos + Vector3(0.0, 36.0, 0.0)    # wysoko: odsłoń strefę LOD
			cam.look_at(ppos + Vector3(90.0, 6.0, 90.0), Vector3.UP)  # w dal nad styk NEAR|FAR (szczeliny?)
		elif mode == "tree":
			cam.global_position = ppos + Vector3(6.0, 7.0, -6.0)    # z boku/góry na koronę (ppos=baza+2)
			cam.look_at(ppos + Vector3(0.0, 4.5, 0.0), Vector3.UP)  # celuj w środek korony nad pniem
		else:
			cam.global_position = ppos + Vector3(0.0, 2.2, -2.4)   # z góry-przodu na runo
			cam.look_at(ppos + Vector3(0.0, 0.1, 0.6), Vector3.UP)  # patrz w dół na grunt z propami
		cam.current = true
	else:
		var spring := _find_node_of_type(_player_ref, "SpringArm3D")
		if spring:
			spring.spring_length = (6.0 if mode == "water" else 7.0)
			spring.rotation.x = deg_to_rad(-28.0 if mode == "water" else -20.0)
			var pivot := spring.get_parent()
			if pivot is Node3D: (pivot as Node3D).rotation.y = deg_to_rad(water_yaw_deg)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/oskar/Downloads/voxel-rpg/_shot.png")
	print("[PROBE] shot saved")
	get_tree().quit()

func _find_node_of_type(n: Node, type_name: String) -> Node:
	for c in n.get_children():
		if c.is_class(type_name): return c
		var r := _find_node_of_type(c, type_name)
		if r: return r
	return null

func _setup_environment() -> void:
	# --- Słońce: ciepła barwa, miękkie cienie. Trzymamy w polu _sun (DayNight je animuje). ---
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-45.0, -120.0, 0.0)
	_sun.light_color = Color(1.0, 0.95, 0.85)  # ciepłe światło dnia
	_sun.light_energy = 1.0   # umiarkowane słońce => kolory się nie „przepalają”
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.shadow_blur = 1.0  # ostrzejszy cień (Faza 0A)
	# Zasięg cieni = render_distance 4 (64 m). 80 m daje gęstsze teksele cienia niż 120.
	_sun.directional_shadow_max_distance = 80.0
	_sun.directional_shadow_blend_splits = true  # płynne przejścia między kaskadami
	add_child(_sun)

	# Fill light (Faza 0B): drugie, BEZCIENIOWE „słońce" z przeciwnej strony — wypełnia
	# cienie kierunkowo (tani zamiennik bounce GI), chłodna barwa dla kontrastu z ciepłym słońcem.
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-30.0, 60.0, 0.0)
	fill.light_color = Color(0.60, 0.72, 0.95)
	fill.light_energy = 0.12
	fill.shadow_enabled = false
	add_child(fill)

	# --- Niebo proceduralne. Materiał w polu _sky_mat (DayNight zmienia kolory). ---
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = Color(0.18, 0.42, 0.78)
	_sky_mat.sky_horizon_color = Color(0.72, 0.84, 0.95)
	_sky_mat.ground_horizon_color = Color(0.72, 0.84, 0.95)
	_sky_mat.ground_bottom_color = Color(0.22, 0.25, 0.28)
	_sky_mat.sun_angle_max = 12.0
	var sky := Sky.new()
	sky.sky_material = _sky_mat

	# --- Środowisko: oświetlenie globalne + atmosfera + kolor filmowy. Pole _environment. ---
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_energy = 0.25   # delikatne wypełnienie, żeby cienie nie były czarne
	# KLUCZOWE dla cyklu dnia/nocy: udział nieba w świetle otoczenia < 1.0, żeby
	# ambient_light_energy (animowane przez DayNight._AMBIENT) realnie działało.
	# Przy domyślnym 1.0 ambient brałby się WYŁĄCZNIE z nieba — a że DayNight ściemnia
	# niebo nocą do granatu, scena zgasłaby do czerni mimo _AMBIENT. Z 0.6 noc pozostaje
	# czytelna (część ambientu pochodzi z energii sterowanej przez cykl doby).
	_environment.ambient_light_sky_contribution = 0.6

	# SDFGI (globalne oświetlenie w czasie rzeczywistym) WYŁĄCZONE: zalewało scenę bladym
	# światłem (efekt „mlecznej mgły”) i mocno obciążało laptopowy GPU 4 GB.
	# Zamiast niego: kontrastowe słońce + umiarkowane światło otoczenia z nieba.
	_environment.sdfgi_enabled = false

	# Ambient occlusion — delikatne cienie w stykach i zagłębieniach (głębia).
	_environment.ssao_enabled = true
	_environment.ssao_intensity = 1.4
	_environment.ssao_radius = 0.8   # dostrojone do voxela 0,5 m (Faza 0A)
	_environment.ssao_power = 1.5
	_environment.ssao_horizon = 0.06

	# Bloom/poświata na jasnych powierzchniach.
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.2
	_environment.glow_bloom = 0.1
	_environment.glow_hdr_threshold = 1.0   # tylko realnie jasne miejsca świecą (bez „mleka”)
	_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# --- Atmospheric perspective (Faza 2B): daleka krawędź LOD FAR ma ROZPUŚCIĆ się w mgle ---
	# koloru nieba => niewidoczny „fog wall”, panorama jak Cube World. BEZ przygniatania bliży.
	# DWIE rozdzielone warstwy: (1) depth fog = GŁÓWNE narzędzie głębi/krawędzi (tania, per-pixel),
	# (2) volumetric = tylko bliska atmosfera + god rays.
	#
	# ZASIĘG liczony z RZECZYWISTEJ instancji świata (review #minor): far_m = far_dist * CHUNK_SIZE
	# * VOXEL_SIZE. Dzięki temu zmiana far_dist w inspektorze przelicza początek/koniec mgły sama
	# (krawędź zawsze ginie tuż za ostatnim pierścieniem; brak „fog wall” gdy ktoś podniesie zasięg).
	var far_m: float = float(_world.far_dist) * float(_world.CHUNK_SIZE) * _world.VOXEL_SIZE   # 112 m @ far=7
	var near_m: float = float(_world.near_dist) * float(_world.CHUNK_SIZE) * _world.VOXEL_SIZE  # 64 m @ near=4

	# (2) Mgła wolumetryczna — TYLKO bliska atmosfera + god rays (NIE chowanie krawędzi: robi to
	# depth fog). length ogranicza ZASIĘG froxeli (dystans, na jaki liczona jest objętość), nie VRAM.
	# UWAGA (review #minor — sprostowanie): KOSZT VRAM froxeli zależy od ROZDZIELCZOŚCI siatki froxeli,
	# a NIE od length. W Godot 4.7 sterują nią PROJECT SETTINGS (nie property Environment!):
	# rendering/environment/volumetric_fog/volume_size oraz .../volume_depth. Realne dźwignie budżetu
	# 4GB to: zmniejszyć te dwa ustawienia projektu ALBO wyłączyć volumetric (sama depth fog +
	# fog_depth_* rozpuszcza krawędź praktycznie za darmo). length zostaje wyłącznie jako zakres głębi.
	# WYŁĄCZONE na 4GB: mgła wolumetryczna (froxele) to jeden z najdroższych efektów GPU,
	# a atmosferę dali daje już TANIA depth fog (fog_depth_* z 2B). Wyłączenie zauważalnie
	# podnosi FPS na słabszym GPU, prawie nie zmieniając looku. (Włącz z powrotem na mocniejszym.)
	_environment.volumetric_fog_enabled = false
	_environment.volumetric_fog_density = 0.018
	_environment.volumetric_fog_albedo = Color(0.80, 0.86, 0.95)   # ~dzienny horyzont; DayNight nadpisze
	_environment.volumetric_fog_length = 48.0     # zakres GŁĘBI froxeli (nie VRAM); VRAM tnij volume_size/depth
	_environment.volumetric_fog_anisotropy = 0.4  # rozprasza światło słońca => tanie god rays
	_environment.volumetric_fog_ambient_inject = 0.15   # zbite z 0.2: mniej „mlecznej plamy” pod AGX
	_environment.volumetric_fog_sky_affect = 0.0        # nie zamglaj nieba wolumetrykiem (góra kadru czysta)
	_environment.volumetric_fog_gi_inject = 0.0         # SDFGI off => nie marnuj

	# (1) Mgła dystansowa w trybie GŁĘBI (review #MAJOR — żeby NIE przygniatała bliży): FOG_MODE_DEPTH
	# liczy krycie LINIOWO/krzywą od fog_depth_begin do fog_depth_end (a NIE wykładniczo od kamery jak
	# FOG_MODE_EXPONENTIAL, który zaczyna mglić już od 0 m i blakł cały pierścień NEAR). Dzięki temu:
	#   - bliż 0..begin (cały NEAR + zapas) = CZYSTA, ostra (look CW: ostry bliski plan),
	#   - od begin do end krycie rośnie do pełnego => daleka krawędź FAR rozpuszcza się w kolorze nieba.
	# begin = near_m * 0.7 (~45 m, ZA pierścieniem detalu, jeszcze przed jego końcem 64 m, miękki start),
	# end = far_m (112 m): ostatni budowany pierścień osiąga PEŁNE krycie dokładnie tam, gdzie geometria
	# się urywa => szwu/„fog wall” nie widać. depth_curve > 1 dosuwa większość gęstnienia ku końcowi
	# (bliż dłużej czysta, dopiero daleko gwałtownie tonie w niebie).
	_environment.fog_enabled = true
	_environment.fog_mode = Environment.FOG_MODE_DEPTH
	_environment.fog_depth_begin = near_m * 0.7   # ~45 m @ near=4: początek mgły ZA bliskim planem
	_environment.fog_depth_end = far_m            # 112 m: pełne krycie na krawędzi FAR (krawędź ginie)
	_environment.fog_depth_curve = 2.0            # krzywa: bliż dłużej czysta, gęstnienie ku końcowi
	# fog_density w trybie DEPTH skaluje MAKSYMALNE krycie na fog_depth_end (1.0 = pełne zlanie z niebem
	# na końcu). DayNight nadpisuje fog_density i fog_light_color per pora => krawędź ginie o KAŻDEJ porze.
	_environment.fog_density = 1.0
	# aerial_perspective=1.0: mgła w dali przyjmuje kolor NIEBA W DANYM KIERUNKU (nie płaski kolor)
	# => dolny pas terenu zlewa się z jasnym horyzontem, zenit kadru zostaje czysty (NIE przygniata).
	_environment.fog_aerial_perspective = 1.0
	_environment.fog_sky_affect = 0.0     # samego nieba NIE zamglamy (inaczej AGX+glow => mleczna płaskość)
	_environment.fog_sun_scatter = 0.08   # lekki rozbłysk wokół słońca w mgle (nie przepalać)
	# Mgła wysokościowa: gęstsza nisko (doliny/jeziora), rzadsza wysoko => szczyty wystają z mgły
	# jak w panoramie CW, a bliski teren na wysokości oczu pozostaje czysty (gracz zwykle na grzbiecie).
	_environment.fog_height = 12.0          # ~poziom morza (SEA_LEVEL 24 voxele × 0,5 = 12 m)
	_environment.fog_height_density = 0.06  # dodatkowa gęstość przy/pod fog_height (mgliste doliny)

	# Mapowanie tonalne AGX — żywsze, lepiej trzyma nasycone barwy, nie wypala bieli/wody.
	_environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_environment.tonemap_exposure = 0.85
	_environment.tonemap_white = 6.0

	# Color grading (autorski look za grosze): lekki kontrast + nasycenie.
	_environment.adjustment_enabled = true
	_environment.adjustment_contrast = 1.05
	_environment.adjustment_saturation = 1.12
	_environment.adjustment_brightness = 1.0

	var world_env := WorldEnvironment.new()
	world_env.environment = _environment
	add_child(world_env)

	# --- Cykl dnia i nocy: węzeł DayNight dostaje gotowe referencje i animuje je. ---
	# Wartości startowe powyżej i tak zostaną nadpisane przez DayNight.setup() w klatce 0.
	_day_night = DayNightScript.new()
	_day_night.name = "DayNight"
	add_child(_day_night)
	_day_night.setup(_sun, _environment, _sky_mat)

func _setup_world() -> void:
	# Tworzymy menedżera świata. Materiały i szum konfiguruje sam w _ready().
	_world = VoxelWorldScript.new()
	_world.name = "VoxelWorld"
	add_child(_world)
	# add_child uruchamia _ready() VoxelWorld synchronicznie, więc szum/materiały
	# są już gotowe — można od razu pytać o height_at() i wołać prime().

func _spawn_player() -> void:
	var player := CharacterBody3D.new()
	player.set_script(PlayerScript)
	player.name = "Player"

	# Punkt startowy w metrach. Najpierw budujemy teren wokół spawnu (prime),
	# żeby gracz nie spadł przez jeszcze niezaladowane chunki w pierwszej klatce.
	var spawn_x := 0.0
	var spawn_z := 0.0
	var center := _world.world_to_chunk(Vector3(spawn_x, 0.0, spawn_z))
	_world.prime(center, 1)   # kwadrat 3×3 chunków wokół gracza — od ręki

	var spawn_y := _world.height_at(spawn_x, spawn_z) + 2.0  # 2 m zapasu, spadnie na grunt
	player.position = Vector3(spawn_x, spawn_y, spawn_z)
	add_child(player)

	# Punkt odrodzenia = miejsce startu (na terenie). respawn() tu wraca.
	# Ustawiamy WPROST na grunt + 1 m, żeby respawn nie spadał z 2 m zapasu.
	player.respawn_point = Vector3(spawn_x, _world.height_at(spawn_x, spawn_z) + 1.0, spawn_z)

	_player_ref = player
	# Podajemy referencję gracza do streamingu (od teraz świat śledzi jego pozycję).
	_world.set_player(_player_ref)

	# ETAP 2: ekwipunek gracza (komponent). Rejestruje się jako provider StatsComponentu gracza
	# (collect_modifiers z założonych itemów -> get_stat). GameState.local_player potrzebny m.in.
	# do magic_find w LootService.
	_inventory = InventoryComponentScript.new()
	_player_ref.add_child(_inventory)
	if GameState != null:
		GameState.set_local_player(_player_ref)

	# ETAP 3: jesli istnieje zapis postaci — wczytaj progresje (poziom/xp/alokacja/waluty). Brak
	# zapisu = swiezy start (lvl 1) jak dotad. Ustaw klase z save PRZED budowa zasobu (juz zbudowany
	# w Player._ready, wiec read_progression tylko odtwarza poziom/drzewko/waluty — bezpiecznie).
	if SaveManager != null and _player_ref.has_method("read_progression_from_save"):
		var sd: SaveData = SaveManager.load_character()
		if sd != null:
			_player_ref.read_progression_from_save(sd)

func _spawn_enemies() -> void:
	# ETAP 4: DETERMINISTYCZNY spawn wg biomu + seeda (WorldSpawner) zamiast stałego 3×.
	# Spawner aktywuje regiony wokół gracza z LOKALNEGO RNG (base_seed = RNGService.world_seed()),
	# dobiera wrogów z BiomeResource.enemy_spawn_table biomu regionu, skaluje ilvl dystansem, i pilnuje
	# TWARDEGO limitu aktywnych (anti-flood — nie psuje FPS 2A/2B). Sygnały wroga (śmierć/loot) lecą
	# do tych samych slotów Main co wcześniej (HUD licznik + spawn LootDrop). Teren wokół spawnu jest
	# już sprimowany w _spawn_player(), więc pierwsze regiony mają grunt pod height_at().
	_spawner = WorldSpawner.new()
	_spawner.name = "WorldSpawner"
	add_child(_spawner)
	_spawner.setup(_world, _player_ref,
		Callable(self, "_on_enemy_died"),
		Callable(self, "_on_enemy_loot_dropped"))
	# Pierwszy tick natychmiast (zamiast czekać TICK_INTERVAL) — gracz od razu ma towarzystwo.
	_spawner._update_regions()
	_enemies_alive = _spawner.active_count()

	# ETAP 5: menedżer dungeonów — skanuje wejścia (deterministyczne z seeda chunka), obsługuje
	# wejście [E] -> instancja DungeonRun -> boss -> loot DO POSTACI -> powrót na zapamiętaną pozycję.
	# Loot/śmierć wrogów RUNU lecą do TYCH SAMYCH slotów Main co świat (LootDrop + XP).
	_dungeon_mgr = DungeonManager.new()
	_dungeon_mgr.name = "DungeonManager"
	add_child(_dungeon_mgr)
	_dungeon_mgr.setup(_world, _player_ref, _spawner, self,
		Callable(self, "_on_enemy_loot_dropped"),
		Callable(self, "_on_enemy_died"))

func _setup_hud() -> void:
	# --- Stara podpowiedź ze sterowaniem (przeniesiona na dół, by nie kryła pasków) ---
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "WASD – ruch  |  mysz – kamera  |  LMB – atak  |  RMB / Q – unik  |  R – finisher  |  I – ekwipunek  |  K – drzewko  |  spacja – skok  |  shift – bieg  |  ESC – kursor"
	label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	label.position = Vector2(16.0, -28.0)   # przy dolnej krawędzi, nie koliduje z paskami u góry
	layer.add_child(label)
	add_child(layer)

	# --- HUD walki: paski HP/stamina + ekran śmierci ---
	_hud = HUDScript.new()
	_hud.name = "CombatHUD"
	add_child(_hud)

	# Podłączamy sygnały gracza do slotów HUD-a. Gracz już istnieje (spawn przed _setup_hud).
	if _player_ref != null:
		_player_ref.hp_changed.connect(_hud.on_hp_changed)
		_player_ref.stamina_changed.connect(_hud.on_stamina_changed)
		_player_ref.died.connect(_hud.on_player_died)
		_player_ref.respawned.connect(_hud.on_player_respawned)
		# Combo: spina getter/sygnał gracza z osobną etykietą combo w HUD (wcześniej martwy kod).
		if _hud.has_method("set_combo"):
			_player_ref.combo_changed.connect(_hud.set_combo)
		# Respawn po śmierci: Main steruje opóźnieniem (HUD tylko pokazuje napis).
		_player_ref.died.connect(_on_player_died)

		# ETAP 3: pasek zasobu klasy (Mana/Furia/Combo+Focus) + poziom/XP na HUD.
		if _hud.has_method("setup_class_resource"):
			var cr = _player_ref.class_resource_component()
			if cr != null:
				_hud.setup_class_resource(cr.display_label(), cr.bar_color(), cr.max_value())
				_hud.on_class_resource_changed(cr.resource_name(), cr.current_value(), cr.max_value())
		if _hud.has_method("on_class_resource_changed"):
			_player_ref.class_resource_changed.connect(_hud.on_class_resource_changed)
		if _hud.has_method("on_level_changed"):
			_player_ref.level_changed.connect(_hud.on_level_changed)
			_hud.on_level_changed(_player_ref.get_level(), _player_ref.get_xp(),
				LevelComponent.xp_to_next(_player_ref.get_level()))
		if _hud.has_method("on_leveled_up"):
			_player_ref.leveled_up.connect(_hud.on_leveled_up)

		# ETAP 3: autosave progresji na awansie i po kazdej zmianie alokacji drzewka / respec.
		# Razem z zapisem na zamknieciu okna (_notification) daje to trwala progresje w realnej grze.
		_player_ref.leveled_up.connect(func(_lv: int, _pts: int) -> void: _save_progression())
		var tc = _player_ref.skill_tree_component()
		if tc != null:
			tc.allocation_changed.connect(func(_id: StringName, _a: bool, _l: int) -> void: _save_progression())
			tc.respec_done.connect(func(_r: int, _c: int) -> void: _save_progression())

	# Startowy licznik wrogów.
	if _hud.has_method("set_enemy_count"):
		_hud.set_enemy_count(_enemies_alive)

	# --- ETAP 2: ekran ekwipunku + toast lootu (OSOBNA warstwa CanvasLayer, nad HUD walki) ---
	_inv_ui = InventoryUIScript.new()
	_inv_ui.name = "InventoryUI"
	add_child(_inv_ui)
	if _inventory != null:
		_inv_ui.bind_inventory(_inventory)

	# --- ETAP 3: ekran drzewka umiejetnosci (toggle K) ---
	_tree_ui = SkillTreeUIScript.new()
	_tree_ui.name = "SkillTreeUI"
	add_child(_tree_ui)
	if _player_ref != null:
		_tree_ui.bind_player(_player_ref)

# ETAP 3 — TRWALY zapis progresji w trakcie gry (review: sciezka zapisu nie byla wolana). Zapisujemy
# na: (1) zamknieciu okna, (2) awansie, (3) zmianie alokacji drzewka / respec. Tak XP/poziom/pasywy/
# waluty przezywaja wyjscie z gry (DoD: poziom/xp/punkty/waluta/alokacja w save — teraz pelne, nie tylko load).
func _save_progression() -> void:
	if _player_ref != null and _player_ref.has_method("save_progression"):
		_player_ref.save_progression()

# ETAP 5 — ZAPIS HYBRYDOWY po wyjściu z dungeonu (DungeonManager woła to przez save_after_dungeon).
# Postać (loot/postęp zdobyte w runie) trafia do save'a postaci; świat (host) zapisuje swój seed +
# zmiany. Runa jest EFEMERYCZNA — NIE zapisujemy jej (GDD 8). Autosave na evencie "wyjście z dungeonu"
# (TDD 8). Bezpieczne na brak metod/autoloadów (headless/test).
func save_after_dungeon() -> void:
	# 1) Postać (przenośna): loot/poziom/waluty zebrane w dungeonie zostają na postaci.
	_save_progression()
	# 2) Świat (tylko host): seed + ewentualne zmiany. Runa NIE wchodzi do world_entities (efemeryczna).
	if SaveManager == null or NetManager == null or not NetManager.is_host():
		return
	var sd := SaveData.new()
	sd.world_seed = RNGService.world_seed() if RNGService != null else VoxelWorld.FEATURE_SEED
	SaveManager.save_world(sd)

# Zamkniecie okna (X) / zadanie wyjscia: zapisz progresje ZANIM silnik zwolni sceny.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_save_progression()

# Po śmierci gracza: chwila na ekran śmierci, potem respawn na punkcie startowym.
func _on_player_died() -> void:
	var t := get_tree().create_timer(respawn_delay)
	t.timeout.connect(func() -> void:
		if is_instance_valid(_player_ref):
			_player_ref.respawn()
	)

# Wróg zginął: zsynchronizuj licznik z aktywnymi w spawnerze (ETAP 4 — spawn jest dynamiczny,
# nie stała trójka), przyznaj XP graczowi (ETAP 3) i odśwież HUD.
func _on_enemy_died(e: Enemy) -> void:
	# ETAP 5: w dungeonie licznik bierzemy z aktywnej runy (spawner świata jest spauzowany), inaczej
	# ze spawnera świata. Spawner/run dekrementuje swój licznik w SWOIM callbacku PRZED tym (connect
	# kolejnościowo), więc odczyt jest już aktualny.
	if _dungeon_mgr != null and _dungeon_mgr.in_dungeon():
		var run := _dungeon_mgr.current_run()
		_enemies_alive = run.enemies_alive() if run != null else _enemies_alive
	elif _spawner != null:
		_enemies_alive = _spawner.active_count()
	else:
		_enemies_alive = maxi(0, _enemies_alive - 1)
	if _hud != null and _hud.has_method("set_enemy_count"):
		_hud.set_enemy_count(_enemies_alive)
	# ETAP 3: XP za zabicie wroga (hook smierci -> grant_xp). Skala wg HP (goblin HP 30 -> 12 XP).
	if _player_ref != null and _player_ref.has_method("grant_xp"):
		_player_ref.grant_xp(_xp_reward_for(e))
	# ETAP 3: Orby Przemiany za zabicie wroga -> waluta respecu (GDD 10.1). Bez tego GameState.orbs
	# zostawalo 0 i przycisk RESPEC w drzewku byl nieosiagalny w realnej grze (review). Vertical slice:
	# placeholder ~kilka Orb za wroga (mocniejsi/elity wiecej), by respec byl realnie testowalny.
	if GameState != null:
		GameState.add_orbs(_orb_reward_for(e))

# Nagroda XP za wroga (ETAP 3). Skala z max_hp (goblin HP 30 -> 12; Brute HP 120 -> 48). Bazowy
# fallback 12, gdy brak referencji. Etap 4 podlaczy poziom/biom wroga zamiast plaskiego HP.
func _xp_reward_for(e: Enemy) -> int:
	if e == null:
		return 12
	# Skala z max_hp wroga (Brute HP 120 da wiecej niz goblin HP 30) — proste, deterministyczne.
	return maxi(1, int(round(e.max_hp * 0.4)))

# Nagroda Orb za wroga (ETAP 3 — waluta respecu). Placeholder vertical slice: ~HP/15 (goblin HP 30 ->
# 2 Orby), min 1. Etap 4 ograniczy drop do elit/bossow (GDD 10.1) i doda losowosc; tu staly drop
# z kazdego wroga, by RESPEC byl osiagalny end-to-end w slice (koszt #0 = 500 Orb).
func _orb_reward_for(e: Enemy) -> int:
	if e == null:
		return 1
	return maxi(1, int(round(e.max_hp / 15.0)))

# ETAP 2: wróg zrzucił loot -> spawn encji LootDrop w świecie (pod Main, nie pod zwalnianym wrogiem).
# Item -> LootDrop z ItemInstance; zloto -> LootDrop zlota. Toast pokazujemy DOPIERO przy podniesieniu
# (LootDrop.picked_up), żeby gracz wiedział, co faktycznie wpadło do plecaka.
func _on_enemy_loot_dropped(world_pos: Vector3, drops: Array) -> void:
	var i := 0
	for d in drops:
		# Lekki rozrzut, by kilka dropów nie nakładało się w jednym punkcie.
		var jitter := Vector3(cos(float(i) * 2.1) * 0.6, 0.0, sin(float(i) * 2.1) * 0.6)
		var pos := world_pos + jitter
		var drop: LootDrop = null
		if d.get("kind", "") == "item" and d.get("instance", null) is ItemInstance:
			drop = LootDropScript.spawn_item(self, pos, d["instance"])
		elif d.get("kind", "") == "gold":
			drop = LootDropScript.spawn_gold(self, pos, int(d.get("amount", 0)))
		if drop != null:
			drop.picked_up.connect(_on_loot_picked_up)
		i += 1

# ETAP 2: gracz podniósł loot -> toast w kolorze rzadkości (item) lub złoty (złoto).
func _on_loot_picked_up(drop: LootDrop) -> void:
	if _inv_ui == null:
		return
	if drop.item != null:
		_inv_ui.show_item_toast(drop.item)
	elif drop.gold > 0:
		_inv_ui.show_gold_toast(drop.gold)
