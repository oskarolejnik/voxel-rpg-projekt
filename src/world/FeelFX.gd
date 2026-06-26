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

# --- FAZA 4 (1) SLASH-TRAIL — pula smug-luku za ostrzem (ACTIVE faza ataku) ---
# Tani: ImmediateMesh-luk zbudowany RAZ w fabryce; spawn = pozycja/orientacja/kolor/alfa. Gasnie
# szybko (TRAIL_LIFE ~ dlugosc ACTIVE+overshoot z Fazy 2). One-shot, unlit/additive, brak rebuildu.
const TRAIL_POOL: int = 4
const TRAIL_LIFE: float = 0.16
var _trails: Array[MeshInstance3D] = []
var _trail_t: Array[float] = []      # pozostaly czas zycia (s)
var _trail_next: int = 0

# --- FAZA 4 (3) ABILITY AURY — pula pierscieni/rozblyskow kastowania skilla (wg SkillResource) ---
# Reuse meshe (TorusMesh/CylinderMesh) skalowane od malego do aura_radius + fade. One-shot, pooled.
const AURA_POOL: int = 3
const AURA_LIFE: float = 0.30
var _auras: Array[MeshInstance3D] = []
var _aura_t: Array[float] = []           # pozostaly czas zycia (s)
var _aura_max_scale: Array[float] = []   # docelowa skala (radius aury w XZ)
var _aura_next: int = 0

# Kolory FX wg tagu ciosu (fizyczny bialo-zolty / ogien pomarancz / mroz blekit).
const COL_PHYS: Color = Color(1.0, 0.96, 0.6)
const COL_FIRE: Color = Color(1.0, 0.55, 0.18)
const COL_FROST: Color = Color(0.55, 0.82, 1.0)
const COL_CRIT_NUM: Color = Color(1.0, 0.85, 0.25)   # liczba krytyka (zlota)
const COL_HIT_NUM: Color = Color(1.0, 0.95, 0.9)     # liczba zwyklego ciosu

# FAZA 4 — domyslny kolor smugi broni (bialo-stalowy; Player nadpisuje wg broni/elementu).
const TRAIL_COL_DEFAULT: Color = Color(0.85, 0.92, 1.0)

# FAZA 4 (5) — opcjonalny HUD do screen-flasha. Ustawiany przez Main (set_hud); brak -> ciche no-op.
# FeelFX zostaje Node3D bez twardej zaleznosci od HUD (luzne sprzezenie przez duck-typed referencje).
var _hud: Node = null


## FAZA 4: Main wstrzykuje HUD (CanvasLayer) do screen-flasha. Brak -> flash to no-op (headless/test).
func set_hud(hud: Node) -> void:
	_hud = hud


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
	for i in TRAIL_POOL:
		var tr := _make_trail()
		add_child(tr)
		_trails.append(tr)
		_trail_t.append(0.0)
	for i in AURA_POOL:
		var au := _make_aura()
		add_child(au)
		_auras.append(au)
		_aura_t.append(0.0)
		_aura_max_scale.append(1.0)


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
	# FAZA 4 (5) CRIT BURST: krytyk = wyrazny "POW" — wiekszy iskra-burst + mocniejszy puls swiatla
	# (hitstop/shake zostaja po stronie Player; kamery tu nie mamy). Krytyk znany TYLKO autorytatywnie
	# (final_damage>0). Predykcja klienta (final_damage==0, was_crit zawsze false) -> zwykla iskra.
	if was_crit:
		spawn_crit_burst(pos, col)
	else:
		spawn_hit_vfx(pos, col, false)

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
#  FAZA 4 (1) SLASH-TRAIL — smuga/luk za ostrzem w fazie ACTIVE ataku
# ============================================================================
## Spawnuje smuge broni u barku gracza, zorientowana wzdluz `forward` (XZ). Wolane z Player w
## _enter_attack_active (faza ACTIVE) oraz w finisherze — NIGDY w ANTICIPATION (gwarancja testu).
## `big` = szerszy/wiekszy luk (finisher/Wir Ostrzy). Gasnie liniowo w _process (TRAIL_LIFE).
func spawn_slash_trail(origin: Vector3, forward: Vector3, col: Color, big: bool = false) -> void:
	if _trails.is_empty():
		return
	var tr := _trails[_trail_next]
	var idx := _trail_next
	_trail_next = (_trail_next + 1) % _trails.size()
	tr.global_position = origin
	var fwd := forward
	fwd.y = 0.0
	if fwd.length_squared() > 0.0001:
		# Orientacja luku wzdluz kierunku ciosu (look_at w plaszczyznie XZ; up=Y).
		tr.look_at(origin + fwd.normalized(), Vector3.UP)
	var mat := tr.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(col.r, col.g, col.b, 1.0)
		mat.emission = Color(col.r, col.g, col.b)
		mat.emission_energy_multiplier = 3.0
	tr.scale = Vector3.ONE * (1.5 if big else 1.0)
	tr.visible = true
	_trail_t[idx] = TRAIL_LIFE


# ============================================================================
#  FAZA 4 (3) ABILITY AURY — pierscien/rozblysk kastowania skilla (wg SkillResource)
# ============================================================================
## Spawnuje aure skilla w world_pos. `kind`: &"ring" (pierscien rosnacy — Wir Ostrzy),
## &"slam" (uderzenie w ziemie — iskra-burst + puls + pierscien — Roztrzaskanie), &"cast" (puls u stop).
## Reuse istniejacych puli (spark/light) tam, gdzie to mozliwe; pierscien to pooled MeshInstance3D.
func spawn_ability_aura(kind: StringName, col: Color, radius: float, world_pos: Vector3, forward: Vector3 = Vector3.ZERO) -> void:
	if kind == &"" or _auras.is_empty():
		return
	# SLAM: mocny impakt w ziemie — duza iskra + puls swiatla + pierscien fali uderzeniowej.
	# UWAGA (review #minor): spawn_hit_vfx(big=true) JUZ odpala spawn_light_pulse wewnetrznie (1 puls).
	# NIE dokladamy drugiego jawnego pulsu — slam = DOKLADNIE 1 slot puli swiatla (LIGHT_POOL=4), inaczej
	# jeden cast zjadalby 2 sloty i przeswietlal scene/wyczerpywal pule dla rownoczesnych trafien.
	if kind == &"slam":
		spawn_hit_vfx(world_pos + Vector3(0.0, 0.2, 0.0), col, true)
	elif kind == &"cast":
		spawn_light_pulse(world_pos + Vector3(0.0, 0.6, 0.0), col, false)
	# Wspolny element wszystkich aur: rosnacy pierscien na ziemi (czytelny obszar dzialania skilla).
	var au := _auras[_aura_next]
	var idx := _aura_next
	_aura_next = (_aura_next + 1) % _auras.size()
	au.global_position = world_pos + Vector3(0.0, 0.06, 0.0)
	var mat := au.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(col.r, col.g, col.b, 0.8)
		mat.emission = Color(col.r, col.g, col.b)
		mat.emission_energy_multiplier = 2.5
	_aura_max_scale[idx] = maxf(0.2, radius)
	au.scale = Vector3.ONE * 0.2          # start maly -> rosnie do radius w _process
	au.visible = true
	_aura_t[idx] = AURA_LIFE


# ============================================================================
#  FAZA 4 (5) CRIT BURST — wyrazny "POW": wiekszy iskra-burst + mocniejszy zloty puls swiatla
# ============================================================================
## Krytyk: mocniejszy burst niz zwykle big-trafienie. Wiecej czastek (26 vs 18), kolor podbity ku
## zlotu, puls swiatla 7.0 (vs 5.5 dla zwyklego big). Reuse puli spark+light — zero nowych nodow.
func spawn_crit_burst(pos: Vector3, col: Color) -> void:
	# Kolor iskry podbity ku zlotu krytyka (czytelna roznica od zwyklego ciosu).
	var gold := col.lerp(COL_CRIT_NUM, 0.5)
	# Big iskra (jak spawn_hit_vfx big=true), ale z wieksza liczba czastek i jasniejsza emisja.
	var s := _sparks[_spark_next]
	_spark_next = (_spark_next + 1) % _sparks.size()
	s.global_position = pos
	var mat := s.draw_pass_1.surface_get_material(0) if s.draw_pass_1 != null else null
	if mat == null:
		mat = (s.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	if mat is StandardMaterial3D:
		(mat as StandardMaterial3D).albedo_color = gold
		(mat as StandardMaterial3D).emission = gold
		(mat as StandardMaterial3D).emission_energy_multiplier = 6.0
	s.amount = 26
	s.restart()
	s.emitting = true
	# Mocniejszy zloty puls swiatla (energia 7.0 vs 5.5 big) — wiekszy "rozblysk" krytyka.
	var l := _lights[_light_next]
	var lidx := _light_next
	_light_next = (_light_next + 1) % _lights.size()
	l.global_position = pos
	l.light_color = gold
	l.light_energy = 7.0
	l.omni_range = 4.2
	l.visible = true
	_light_t[lidx] = LIGHT_PULSE_TIME


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

	# FAZA 4 (1): smugi broni gasna liniowo (alpha + emisja), lekko sie "rozmywaja" (scale-up), znikaja.
	for i in _trails.size():
		if _trail_t[i] > 0.0:
			_trail_t[i] = maxf(0.0, _trail_t[i] - delta)
			var k := _trail_t[i] / TRAIL_LIFE
			var tr := _trails[i]
			var mat := tr.material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color.a = clampf(k, 0.0, 1.0)
				mat.emission_energy_multiplier = 3.0 * k
			# Lekkie rozmycie ku koncowi zamachu (1.0->1.15 wzgledem startowej skali).
			tr.scale = tr.scale * (1.0 + delta * 0.9)
			if _trail_t[i] == 0.0:
				tr.visible = false

	# FAZA 4 (3): aury — pierscien rosnie od malego do max_scale + alpha gasnie; znika przy 0 (brak wycieku).
	for i in _auras.size():
		if _aura_t[i] > 0.0:
			_aura_t[i] = maxf(0.0, _aura_t[i] - delta)
			var k := _aura_t[i] / AURA_LIFE          # 1 -> 0
			var grow := 1.0 - k                       # 0 -> 1 (postep ekspansji)
			var au := _auras[i]
			var s := lerpf(0.2, _aura_max_scale[i], clampf(grow, 0.0, 1.0))
			au.scale = Vector3(s, 1.0, s)             # plaski pierscien na ziemi (Y staly)
			var mat := au.material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color.a = clampf(k * 0.8, 0.0, 0.8)
			if _aura_t[i] == 0.0:
				au.visible = false


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
	pm.color_ramp = _spark_color_ramp()      # ART OVERHAUL: flash-to-fade (pełna jasność -> zanik alfy)
	pm.scale_curve = _spark_scale_curve()     # ART OVERHAUL: POP (szybkie nabrzmienie) -> kurczenie
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


# ART OVERHAUL — tekstury iskry (cache, budowane raz): gradient flash-to-fade + krzywa pop-then-shrink.
# Hue-neutralny ramp (biel->biel->przezroczysty) zachowuje per-cios kolor materiału, dokłada PŁYNNY zanik
# alfy (dawniej iskry znikały skokowo na końcu życia). scale_curve daje „pop" (nabrzmienie) i kurczenie.
var _spark_ramp_tex: GradientTexture1D = null
var _spark_scale_tex: CurveTexture = null

func _spark_color_ramp() -> GradientTexture1D:
	if _spark_ramp_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var t := GradientTexture1D.new()
		t.gradient = g
		_spark_ramp_tex = t
	return _spark_ramp_tex

func _spark_scale_curve() -> CurveTexture:
	if _spark_scale_tex == null:
		var c := Curve.new()
		c.add_point(Vector2(0.0, 0.55))
		c.add_point(Vector2(0.16, 1.30))
		c.add_point(Vector2(1.0, 0.08))
		var t := CurveTexture.new()
		t.curve = c
		_spark_scale_tex = t
	return _spark_scale_tex


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


# FAZA 4 (1): smuga broni — luk-wachlarz zbudowany RAZ (ImmediateMesh) jako quad-strip wzdluz krzywej,
# szerokosc zwezajaca sie ku koncowi ostrza. Lokalna orientacja: -Z = przod ciosu (look_at), luk w XZ.
# Unlit/additive/alpha, billboard OFF (smuga ma orientacje swiata). Zero rebuildu per-cios.
func _make_trail() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(TRAIL_COL_DEFAULT.r, TRAIL_COL_DEFAULT.g, TRAIL_COL_DEFAULT.b, 0.0)
	mat.emission_enabled = true
	mat.emission = TRAIL_COL_DEFAULT
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED       # luk widoczny z obu stron
	# Budujemy luk RAZ: ~8 segmentow po krzywej (od ~+50° do ~-50° wokol osi Y), promien ~1.6 m,
	# szerokosc (wysokosc paska w Y) zwezajaca sie ku koncowi zamachu. Quad-strip jako trojkaty.
	const SEG: int = 8
	const ARC_RADIUS: float = 1.6
	const ARC_FROM: float = deg_to_rad(55.0)
	const ARC_TO: float = deg_to_rad(-55.0)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for s in SEG:
		var t0 := float(s) / float(SEG)
		var t1 := float(s + 1) / float(SEG)
		var a0 := lerpf(ARC_FROM, ARC_TO, t0)
		var a1 := lerpf(ARC_FROM, ARC_TO, t1)
		var w0 := lerpf(0.20, 0.03, t0)       # szerokosc (polowa wysokosci paska) maleje ku koncowi
		var w1 := lerpf(0.20, 0.03, t1)
		# Punkty na luku w plaszczyznie XZ (przod = -Z). Pasek rozciagniety w Y (gora/dol).
		var p0 := Vector3(sin(a0) * ARC_RADIUS, 0.0, -cos(a0) * ARC_RADIUS)
		var p1 := Vector3(sin(a1) * ARC_RADIUS, 0.0, -cos(a1) * ARC_RADIUS)
		var up0 := Vector3(0.0, w0, 0.0)
		var up1 := Vector3(0.0, w1, 0.0)
		# Quad (p0-up0, p0+up0, p1+up1, p1-up1) -> 2 trojkaty.
		im.surface_add_vertex(p0 - up0)
		im.surface_add_vertex(p0 + up0)
		im.surface_add_vertex(p1 + up1)
		im.surface_add_vertex(p0 - up0)
		im.surface_add_vertex(p1 + up1)
		im.surface_add_vertex(p1 - up1)
	im.surface_end()
	mi.mesh = im
	mi.material_override = mat
	mi.visible = false
	return mi


# FAZA 4 (3): aura skilla — plaski pierscien na ziemi (TorusMesh cienki). Unlit/additive, skalowany
# w XZ od malego do aura_radius (Y staly). Zbudowany RAZ; spawn ustawia kolor/alfe/skale.
func _make_aura() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86          # cienki pierscien (kontur), skalowany globalnie do radius
	torus.outer_radius = 1.0
	torus.rings = 24
	mi.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.visible = false
	return mi


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
