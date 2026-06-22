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

# Opóźnienie respawnu gracza po śmierci (s). Wystawione jako eksport, by nie było
# magiczną stałą rozjeżdżającą się z respawn_iframes gracza (1,5 s nietykalności).
# Zasada strojenia: i-frames gracza powinny być >= czasu od respawnu do odzyskania
# kontroli — inaczej tuż po odrodzeniu można od razu oberwać.
@export var respawn_delay: float = 1.6

func _ready() -> void:
	_setup_environment()   # słońce + niebo + światło otoczenia + cykl dnia i nocy
	_setup_world()         # proceduralny teren voxelowy (zastępuje płaską podłogę)
	_spawn_player()        # nasza postać — stawiana NA terenie przez height_at()
	_spawn_enemies()       # 3 wrogów blisko gracza (po prime() terenu wokół spawnu)
	_setup_hud()           # podpowiedź ze sterowaniem + HUD walki
	_setup_vignette()      # Faza 0B: winieta (przyciemnienie krawędzi ekranu)
	_setup_ambient_fx()    # Faza 1C: świetliki nocą / pył w dzień
	# Sonda zrzutów tylko gdy uruchomione z VOXEL_PROBE != "" — normalne F5 gra bez sondy.
	if OS.get_environment("VOXEL_PROBE") != "":
		_probe_shot()

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

	await get_tree().create_timer(6.0).timeout
	var ppos := _player_ref.global_position
	if mode == "char" or mode == "props":
		# Dedykowana kamera — omija gameplayowy SpringArm (który cofa się przy kolizji),
		# daje deterministyczny kadr zbliżenia. Przód postaci = -Z (oczy/twarz tam).
		var cam := Camera3D.new()
		add_child(cam)
		if mode == "char":
			cam.global_position = ppos + Vector3(0.9, 1.5, -3.2)   # od przodu, lekko z góry/boku
			cam.look_at(ppos + Vector3(0.0, 1.0, 0.0), Vector3.UP)  # celuj w tułów/twarz
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

	# Mgła wolumetryczna — atmosfera, głębia w dali i darmowy „fade” doładowywanych chunków.
	_environment.volumetric_fog_enabled = true
	_environment.volumetric_fog_density = 0.002   # delikatna atmosfera w dali
	_environment.volumetric_fog_albedo = Color(0.8, 0.86, 0.95)
	_environment.volumetric_fog_length = 64.0     # nie licz froxeli do horyzontu (oszczędność)
	_environment.volumetric_fog_anisotropy = 0.4  # rozprasza światło słońca => tanie god rays
	_environment.volumetric_fog_ambient_inject = 0.2

	# Mgła dystansowa (aerial perspective): dal przyjmuje barwę nieba => głębia + maskuje
	# krawędź doczytywanych chunków. Najtańszy efekt głębi; śledzi cykl dobowy (kolor z nieba).
	_environment.fog_enabled = true
	_environment.fog_density = 0.006
	_environment.fog_aerial_perspective = 1.0
	_environment.fog_sky_affect = 0.0   # samego nieba nie zamglamy
	_environment.fog_sun_scatter = 0.1

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

func _spawn_enemies() -> void:
	# 3 wrogów wokół gracza (offsety 6–10 m). Teren wokół spawnu jest już sprimowany
	# w _spawn_player(), więc height_at() da grunt; +1 m zapasu na osiadnięcie.
	var offsets: Array[Vector2] = [
		Vector2(7.0, 0.0),
		Vector2(-6.0, 6.0),
		Vector2(2.0, -9.0),
	]
	for off in offsets:
		var ex := off.x
		var ez := off.y
		var e := EnemyScript.new()
		e.position = Vector3(ex, _world.height_at(ex, ez) + 1.0, ez)
		add_child(e)
		e.set_target(_player_ref)
		e.died.connect(_on_enemy_died)
		_enemies_alive += 1

func _setup_hud() -> void:
	# --- Stara podpowiedź ze sterowaniem (przeniesiona na dół, by nie kryła pasków) ---
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "WASD – ruch  |  mysz – kamera  |  LMB – atak  |  RMB / Q – unik  |  spacja – skok  |  shift – bieg  |  ESC – kursor"
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

	# Startowy licznik wrogów.
	if _hud.has_method("set_enemy_count"):
		_hud.set_enemy_count(_enemies_alive)

# Po śmierci gracza: chwila na ekran śmierci, potem respawn na punkcie startowym.
func _on_player_died() -> void:
	var t := get_tree().create_timer(respawn_delay)
	t.timeout.connect(func() -> void:
		if is_instance_valid(_player_ref):
			_player_ref.respawn()
	)

# Wróg zginął: dekrementuj licznik i odśwież HUD.
func _on_enemy_died(_e: Enemy) -> void:
	_enemies_alive = maxi(0, _enemies_alive - 1)
	if _hud != null and _hud.has_method("set_enemy_count"):
		_hud.set_enemy_count(_enemies_alive)
