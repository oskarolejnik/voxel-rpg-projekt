class_name FeelFX
extends Node3D
## FeelFX.gd — CENTRALNA warstwa "odczucia" walki (BATCH Fastest High-Impact Fixes).
## Czysto WIZUALNA: spina sie pod DamageService.hit_resolved i HealthComponent.damaged, a po
## potwierdzonym trafieniu spawnuje:
##   1) HIT-VFX w punkcie kontaktu (GPUParticles3D one-shot, kolor wg tagu ciosu),
##   2) krotki blysk swiatla (OmniLight3D pulse ~0.08 s) na pozycji trafienia,
##   4) plywajaca liczbe obrazen (Label3D) nad celem (krytyk = wiekszy + zloty + pop).
##
## AUTORYTET: NIC tu nie zmienia HP/smierci. hit_resolved przychodzi PO autorytatywnym
## rozstrzygnieciu (host/SP); u klienta DamageService emituje predykcje final_damage=0 — wtedy
## pokazujemy tylko iskre (bez liczby), zeby nie klamac wartoscia. To znaczy: bezpieczne w co-opie.
##
## TANIO NA 4GB: wszystkie nody FX sa POOLOWANE (re-use), one-shot, billboard, unshaded/additive.
## Brak alokacji per-cios w hot-path (tylko restart() + ustawienie koloru/pozycji).
##
## Wzorzec czastek skopiowany z Main._make_particles / Player._make_land_dust.

# --- HIT-VFX (iskra/blysk) — pula one-shot emiterow ---
const SPARK_POOL: int = 6
var _sparks: Array[GPUParticles3D] = []
var _spark_next: int = 0

# --- PULS SWIATLA (OmniLight3D) — pula krotkich blyskow ---
const LIGHT_POOL: int = 4
const LIGHT_PULSE_TIME: float = 0.08
var _lights: Array[OmniLight3D] = []
var _light_t: Array[float] = []      # pozostaly czas pulsu (s) rownolegly do _lights
var _light_next: int = 0

# --- DAMAGE NUMBERS (Label3D) — pula plywajacych liczb ---
const NUM_POOL: int = 12
const NUM_LIFE: float = 0.8
var _numbers: Array[Label3D] = []
var _num_t: Array[float] = []        # pozostaly czas zycia (s)
var _num_vel: Array[Vector3] = []    # predkosc unoszenia (swiat)
var _num_next: int = 0

# Kolory FX wg tagu ciosu (fizyczny bialo-zolty / ogien pomarancz / mroz blekit).
const COL_PHYS: Color = Color(1.0, 0.96, 0.6)
const COL_FIRE: Color = Color(1.0, 0.55, 0.18)
const COL_FROST: Color = Color(0.55, 0.82, 1.0)
const COL_CRIT_NUM: Color = Color(1.0, 0.85, 0.25)   # liczba krytyka (zlota)
const COL_HIT_NUM: Color = Color(1.0, 0.95, 0.9)     # liczba zwyklego ciosu


func _ready() -> void:
	# Pule tworzymy RAZ (zero alokacji w hot-path). Wszystko jako dzieci tego wezla (world-space).
	for i in SPARK_POOL:
		var s := _make_spark()
		add_child(s)
		_sparks.append(s)
	for i in LIGHT_POOL:
		var l := _make_light()
		add_child(l)
		_lights.append(l)
		_light_t.append(0.0)
	for i in NUM_POOL:
		var n := _make_number()
		add_child(n)
		_numbers.append(n)
		_num_t.append(0.0)
		_num_vel.append(Vector3.ZERO)


## Spina sie pod centralne wejscie walki. Wolane przez Main po spawnie (jeden raz).
func connect_damage_service() -> void:
	if DamageService != null and not DamageService.hit_resolved.is_connected(_on_hit_resolved):
		DamageService.hit_resolved.connect(_on_hit_resolved)


# ============================================================================
#  REAKCJA NA TRAFIENIE (hit_resolved: source, target, final_damage, was_crit)
# ============================================================================
func _on_hit_resolved(_source: Node, target: Node, final_damage: float, was_crit: bool) -> void:
	if target == null or not is_instance_valid(target) or not (target is Node3D):
		return
	# Punkt kontaktu: srodek tulowia celu (origin + ~0.9 m). hit_position z HitData rzadko ustawiane,
	# wiec celujemy w cel — wizualnie tam, gdzie patrzy gracz. Lekki jitter, by serie nie nakladaly sie.
	var base_pos: Vector3 = (target as Node3D).global_position + Vector3(0.0, 0.9, 0.0)
	var jitter := Vector3(randf_range(-0.12, 0.12), randf_range(-0.1, 0.1), randf_range(-0.12, 0.12))
	var pos := base_pos + jitter

	var col := _color_for_target(target)
	spawn_hit_vfx(pos, col, was_crit)

	# Liczba obrazen TYLKO gdy realnie zadano (>0). Predykcja klienta (final_damage==0) -> bez liczby
	# (autorytatywna wartosc przyjdzie z hosta jako kolejny hit_resolved). Zero klamstwa liczbowego.
	if final_damage > 0.0:
		spawn_damage_number(base_pos + Vector3(0.0, 0.35, 0.0), final_damage, was_crit)


## Dobiera kolor iskry wg tagow ostatniego ciosu celu, jesli da sie je odczytac; inaczej fizyczny.
## Tu nie mamy HitData (hit_resolved go nie niesie), wiec heurystyka: element wroga/cel -> kolor.
func _color_for_target(target: Node) -> Color:
	# Wrog z wariantem zywiolowym (Enemy.element: &"fire"/&"frost") koloruje iskre pod biom.
	if "element" in target:
		var e: StringName = target.element
		if e == &"fire":
			return COL_FIRE
		if e == &"frost":
			return COL_FROST
	return COL_PHYS


# ============================================================================
#  1) HIT-VFX — iskra/blysk w punkcie kontaktu + 2) puls swiatla
# ============================================================================
func spawn_hit_vfx(pos: Vector3, col: Color, big: bool) -> void:
	var s := _sparks[_spark_next]
	_spark_next = (_spark_next + 1) % _sparks.size()
	s.global_position = pos
	var mat := s.draw_pass_1.surface_get_material(0) if s.draw_pass_1 != null else null
	if mat == null:
		mat = (s.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	if mat is StandardMaterial3D:
		(mat as StandardMaterial3D).albedo_color = col
		(mat as StandardMaterial3D).emission = col
	s.amount = 18 if big else 11
	s.restart()
	s.emitting = true
	# Puls swiatla w tym samym miejscu (kolor iskry, krytyk = jasniej/wiekszy).
	spawn_light_pulse(pos, col, big)


func spawn_light_pulse(pos: Vector3, col: Color, big: bool) -> void:
	var l := _lights[_light_next]
	var idx := _light_next
	_light_next = (_light_next + 1) % _lights.size()
	l.global_position = pos
	l.light_color = col
	l.light_energy = (5.5 if big else 3.5)
	l.omni_range = (3.6 if big else 2.6)
	l.visible = true
	_light_t[idx] = LIGHT_PULSE_TIME


# ============================================================================
#  4) DAMAGE NUMBERS — plywajaca liczba nad celem
# ============================================================================
func spawn_damage_number(pos: Vector3, amount: float, was_crit: bool) -> void:
	var n := _numbers[_num_next]
	var idx := _num_next
	_num_next = (_num_next + 1) % _numbers.size()
	n.global_position = pos
	n.text = str(int(round(amount)))
	if was_crit:
		n.modulate = COL_CRIT_NUM
		n.font_size = 64
		n.outline_size = 14
		n.text += "!"
		_num_vel[idx] = Vector3(randf_range(-0.3, 0.3), 2.6, 0.0)   # krytyk wyzej (pop)
	else:
		n.modulate = COL_HIT_NUM
		n.font_size = 40
		n.outline_size = 8
		_num_vel[idx] = Vector3(randf_range(-0.4, 0.4), 1.9, 0.0)
	n.modulate.a = 1.0
	n.scale = Vector3.ONE * (1.6 if was_crit else 1.0)   # pop scale (zjedzie do 1 w _process)
	n.visible = true
	_num_t[idx] = NUM_LIFE


# ============================================================================
#  PETLA: wygaszanie pulsow swiatla + unoszenie/zanik liczb (bez Tweenow per-cios)
# ============================================================================
func _process(delta: float) -> void:
	# Pulsy swiatla: energia gasnie liniowo, znika przy 0 (krotkie, tanie).
	for i in _lights.size():
		if _light_t[i] > 0.0:
			_light_t[i] = maxf(0.0, _light_t[i] - delta)
			var k := _light_t[i] / LIGHT_PULSE_TIME
			_lights[i].light_energy = _lights[i].light_energy * k if k > 0.0 else 0.0
			if _light_t[i] == 0.0:
				_lights[i].visible = false

	# Liczby: unosza sie, zwalniaja, fade-out w ostatniej polowie zycia; pop-scale -> 1.0.
	for i in _numbers.size():
		if _num_t[i] > 0.0:
			_num_t[i] = maxf(0.0, _num_t[i] - delta)
			var life := _num_t[i] / NUM_LIFE
			var n := _numbers[i]
			n.global_position += _num_vel[i] * delta
			_num_vel[i] = _num_vel[i].lerp(Vector3.ZERO, clampf(delta * 3.5, 0.0, 1.0))
			n.modulate.a = clampf(life * 2.0, 0.0, 1.0)   # fade w ostatniej polowie
			# Pop: scala od startowej do 1.0 w pierwszych ~0.12 s.
			var sc := n.scale.x
			n.scale = Vector3.ONE * lerpf(sc, 1.0, clampf(delta * 12.0, 0.0, 1.0))
			if _num_t[i] == 0.0:
				n.visible = false


# ============================================================================
#  FABRYKI NODOW (pula) — wzorzec GPUParticles jak Main._make_particles / land_dust
# ============================================================================
func _make_spark() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.34
	p.one_shot = true
	p.explosiveness = 1.0          # caly burst naraz (iskra), nie struzka
	p.local_coords = false
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.gravity = Vector3(0.0, -3.0, 0.0)
	pm.direction = Vector3(0.0, 0.4, 0.0)
	pm.spread = 180.0               # iskry rozpryskuja sie na wszystkie strony
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 6.0
	pm.damping_min = 4.0
	pm.damping_max = 8.0
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	p.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.13, 0.13)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COL_PHYS
	mat.emission_enabled = true
	mat.emission = COL_PHYS
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = mat
	p.draw_pass_1 = mesh
	return p


func _make_light() -> OmniLight3D:
	var l := OmniLight3D.new()
	l.omni_range = 2.8
	l.light_energy = 0.0
	l.shadow_enabled = false        # tanio: blysk bez cieni
	l.visible = false
	# distance fade, by daleki blysk nie kosztowal (4GB-friendly).
	l.distance_fade_enabled = true
	l.distance_fade_begin = 30.0
	l.distance_fade_length = 8.0
	return l


func _make_number() -> Label3D:
	var n := Label3D.new()
	n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.no_depth_test = true          # liczba zawsze czytelna (nad geometria)
	n.fixed_size = true             # staly rozmiar na ekranie niezaleznie od dystansu
	n.pixel_size = 0.0008
	n.font_size = 40
	n.outline_size = 8
	n.modulate = COL_HIT_NUM
	n.outline_modulate = Color(0, 0, 0, 0.85)
	n.text = ""
	n.visible = false
	return n


# ============================================================================
#  3) HITSTOP TIERED — czysta funkcja (testowalna): waga ciosu -> czas bezczasu
# ============================================================================
## Zwraca dlugosc hitstopu (s) wg wagi ciosu. Mocniej na CIEZKIM/KRYTYKU, lekko na zwyklym.
## Uzywane przez Player._hitstop_for(...) — trzymamy logike tu, by test feel zweryfikowal tiery.
##   light  -> 0.04 s   (zwykly cios)
##   heavy  -> 0.10 s   (ciezka bron / AoE — tag &"heavy"/&"aoe")
##   crit   -> 0.14 s   (krytyk dominuje nad waga)
static func hitstop_for(was_crit: bool, is_heavy: bool) -> float:
	if was_crit:
		return 0.14
	if is_heavy:
		return 0.10
	return 0.04
