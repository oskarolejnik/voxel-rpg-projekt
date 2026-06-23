class_name AmbientLife
extends Node3D
## AmbientLife.gd — FAZA 5 (WORLD ALIVENESS). Tanie, NIE-BOJOWE stworzenia ozywiajace swiat +
## rzadkie, odlegle "wydarzenia" budujace skale. Czysto WIZUALNE: zero wplywu na walke/HP/kolizje
## (wszystkie nody na warstwach 0, bez Area3D/fizyki). Spina sie pod Main (setup(world, player)) i
## tyka z _process Maina (push przez update()).
##
## ZASADA 4GB (nie psuc 2A/2B + FastFixes + Faza1-4): WSZYSTKO POOLOWANE (re-use, zero alokacji w
## hot-path po _ready), TWARDE LIMITY (CREATURE_POOL/EVENT_POOL), DESPAWN poza zasiegiem (recykling
## slotu, nie free), throttling (update co UPDATE_INTERVAL, nie co klatke). Stworzenia to proste
## meshe (QuadMesh billboard / maly Box) + tani lot/uciekanie; brak AI, brak pathfindingu.
##
## ROZMIESZCZENIE: LOSOWE (RNG, _rng.randomize() w _ready) — czysto WIZUALNE, NIEdeterministyczne.
## Stworzenia/eventy NIE wplywaja na gameplay ani co-op (brak Area3D/HP/kolizji/replikacji, klient-side
## kosmetyka => brak desyncu), wiec powtarzalnosc per-miejsce nie daje wartosci i jej nie wymuszamy
## (oszczednosc na celu LOW 4GB). Biom STERUJE TYLKO TYPEM stworzenia (_pick_kind wg get_biome), nie
## jego dokladnym polozeniem.
##
## TYPY STWORZEN wg biomu:
##   verdant    -> ptaki krazace po niebie (KIND_BIRD) + male krytery w trawie (KIND_CRITTER)
##   emberwaste -> ptaki (sepy) wysoko (KIND_BIRD), rzadziej krytery (sucho)
##   frosthelm  -> ptaki (KIND_BIRD), brak kryterow (mroz); ryby tylko nad woda (KIND_FISH)
## RYBY (KIND_FISH) pojawiaja sie nad tafla wody (height_at <= poziom wody) niezaleznie od biomu.
##
## DISTANT EVENTS (rzadkie, wizualne): sylwetka latajacego stwora na horyzoncie, slup dymu,
## spadajaca gwiazda/meteor, odlegly blysk. Wyzwalane LOSOWO-rzadko (RNG, EVENT_CHANCE na probe).

enum Kind { BIRD, CRITTER, FISH }

# --- LIMITY / ZASIEG (4GB-friendly) ---
const CREATURE_POOL: int = 14          # twardy limit jednoczesnych stworzen (pooled)
const EVENT_POOL: int = 3              # twardy limit jednoczesnych distant-events
const ACTIVE_RADIUS: float = 46.0      # promien (m) utrzymania stworzen wokol gracza; dalej despawn
const SPAWN_RADIUS: float = 38.0       # promien (m) w ktorym losujemy nowe stworzenia
const DESPAWN_RADIUS: float = 56.0     # poza tym recyklujemy slot (histereza vs SPAWN_RADIUS)
const UPDATE_INTERVAL: float = 0.5     # s miedzy przeliczeniem populacji (throttling, jak spawner)

# --- DISTANT EVENTS — dystans/rzadkosc ---
const EVENT_DIST_MIN: float = 70.0     # jak daleko (m) od gracza pojawia sie wydarzenie
const EVENT_DIST_MAX: float = 130.0
const EVENT_CHECK_INTERVAL: float = 6.0    # s miedzy probami wyzwolenia (rzadkie)
const EVENT_CHANCE: float = 0.22       # P(wyzwolenia) na probe (=> srednio co ~27 s jedno)

# --- Stan stworzenia (rownolegle tablice = pooled, brak per-creature obiektu) ---
var _cr_nodes: Array[Node3D] = []
var _cr_kind: Array[int] = []
var _cr_active: Array[bool] = []
var _cr_vel: Array[Vector3] = []           # predkosc lotu/biegu (swiat)
var _cr_phase: Array[float] = []           # faza machania skrzydel / kicania
var _cr_home: Array[Vector3] = []          # punkt zaczepienia (srodek krazenia / spawn)
var _cr_speed: Array[float] = []
var _cr_mat: Array[StandardMaterial3D] = []

# --- Stan distant-events ---
var _ev_nodes: Array[Node3D] = []
var _ev_active: Array[bool] = []
var _ev_t: Array[float] = []               # pozostaly czas zycia (s)
var _ev_life: Array[float] = []            # pelny czas zycia (do fade/lerp)
var _ev_kind: Array[int] = []
var _ev_vel: Array[Vector3] = []
var _ev_mat: Array[StandardMaterial3D] = []

enum Event { FLYER, SMOKE, METEOR, FLASH }

var _world = null                          # VoxelWorld (duck-typed: uzywamy TYLKO get_biome/height_at)
var _player: Node3D = null
var _accum: float = 0.0
var _event_accum: float = 0.0
var _rng := RandomNumberGenerator.new()
# Poziom wody w metrach (do detekcji ryb). VoxelWorld nie eksponuje go wprost — zachowawczo niski
# prog (ryby tylko w wyraznych zaglebieniach). Tani heurystyk, czysto wizualny.
var _water_level: float = 1.2


func setup(world, player: Node3D) -> void:
	_world = world
	_player = player


func _ready() -> void:
	_rng.randomize()
	# Pule stworzen + eventow tworzymy RAZ (zero alokacji w hot-path pozniej).
	for i in CREATURE_POOL:
		var n := _make_creature_node()
		add_child(n)
		_cr_nodes.append(n)
		_cr_kind.append(Kind.BIRD)
		_cr_active.append(false)
		_cr_vel.append(Vector3.ZERO)
		_cr_phase.append(0.0)
		_cr_home.append(Vector3.ZERO)
		_cr_speed.append(3.0)
		_cr_mat.append(n.get_meta("mat") as StandardMaterial3D)
	for i in EVENT_POOL:
		var e := _make_event_node()
		add_child(e)
		_ev_nodes.append(e)
		_ev_active.append(false)
		_ev_t.append(0.0)
		_ev_life.append(1.0)
		_ev_kind.append(Event.FLYER)
		_ev_vel.append(Vector3.ZERO)
		_ev_mat.append(e.get_meta("mat") as StandardMaterial3D)


# ============================================================================
#  PETLA — wolana z Main._process (push delta). Throttling populacji + animacja co klatka.
# ============================================================================
func update(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# Animacja (lot/uciekanie/machanie) co KLATKA — tania (kilka operacji wektorowych per slot).
	_animate_creatures(delta)
	_animate_events(delta)

	# Populacja (despawn poza zasiegiem + dospawn) — throttling co UPDATE_INTERVAL.
	_accum += delta
	if _accum >= UPDATE_INTERVAL:
		_accum = 0.0
		_repopulate()

	# Distant events — rzadkie proby wyzwolenia.
	_event_accum += delta
	if _event_accum >= EVENT_CHECK_INTERVAL:
		_event_accum = 0.0
		_maybe_spawn_event()


# Despawn stworzen za DESPAWN_RADIUS (recykling slotu) + dospawn do limitu w SPAWN_RADIUS.
func _repopulate() -> void:
	var pp: Vector3 = _player.global_position
	var alive := 0
	for i in _cr_nodes.size():
		if not _cr_active[i]:
			continue
		var d := Vector2(_cr_nodes[i].global_position.x - pp.x, _cr_nodes[i].global_position.z - pp.z).length()
		if d > DESPAWN_RADIUS:
			_deactivate_creature(i)
		else:
			alive += 1
	# Dospawn: probujemy zapelnic wolne sloty (kilka na tick — rozlozenie kosztu).
	var to_spawn := mini(3, CREATURE_POOL - alive)
	for _k in to_spawn:
		var slot := _free_creature_slot()
		if slot < 0:
			break
		_spawn_creature(slot, pp)


func _free_creature_slot() -> int:
	for i in _cr_active.size():
		if not _cr_active[i]:
			return i
	return -1


func _deactivate_creature(i: int) -> void:
	_cr_active[i] = false
	_cr_nodes[i].visible = false


# Spawnuje stworzenie w LOSOWYM miejscu wokol gracza (RNG, nie feature_hash), dobierajac typ wg biomu
# pod tym miejscem. Ptaki wysoko (nad terenem), krytery przy ziemi, ryby nad woda. Czysto wizualne.
func _spawn_creature(slot: int, pp: Vector3) -> void:
	var ang := _rng.randf() * TAU
	var rad := _rng.randf_range(12.0, SPAWN_RADIUS)
	var wx := pp.x + cos(ang) * rad
	var wz := pp.z + sin(ang) * rad
	var ground := _ground_y(wx, wz)
	var biome := _biome_at(wx, wz)
	var kind := _pick_kind(biome, ground)
	if kind < 0:
		return
	var home: Vector3
	var spd: float
	match kind:
		Kind.BIRD:
			home = Vector3(wx, ground + _rng.randf_range(10.0, 18.0), wz)   # krazy wysoko
			spd = _rng.randf_range(4.0, 7.0)
		Kind.FISH:
			home = Vector3(wx, _water_level - 0.05, wz)                     # tuz pod tafla
			spd = _rng.randf_range(1.5, 3.0)
		_:
			home = Vector3(wx, ground + 0.18, wz)                          # krytery przy ziemi
			spd = _rng.randf_range(2.5, 4.5)
	_cr_kind[slot] = kind
	_cr_home[slot] = home
	_cr_speed[slot] = spd
	_cr_phase[slot] = _rng.randf() * TAU
	_cr_vel[slot] = Vector3(cos(ang + 1.57), 0.0, sin(ang + 1.57)) * spd
	var n := _cr_nodes[slot]
	n.global_position = home
	_style_creature(slot, kind, biome)
	n.visible = true
	_cr_active[slot] = true


# Typ stworzenia wg biomu + czy nad woda (ryby). Zwraca -1 gdy nic (np. krytery zbyt rzadkie).
func _pick_kind(biome: StringName, ground: float) -> int:
	# Ryby: gdy grunt ponizej poziomu wody (zaglebienie/zbiornik) — niezaleznie od biomu.
	if ground <= _water_level:
		return Kind.FISH if _rng.randf() < 0.7 else -1
	match biome:
		&"frosthelm":
			# Mroz: tylko ptaki (brak kryterow w trawie).
			return Kind.BIRD
		&"emberwaste":
			# Sucho: glownie ptaki (sepy), rzadko krytery.
			return Kind.BIRD if _rng.randf() < 0.7 else Kind.CRITTER
		_:
			# Verdant: rownowaga ptaki/krytery (najbardziej "zywy" biom).
			return Kind.BIRD if _rng.randf() < 0.5 else Kind.CRITTER


# ============================================================================
#  ANIMACJA STWORZEN — lot krazacy (ptaki), uciekanie od gracza (krytery), ryby (drobny dryf)
# ============================================================================
func _animate_creatures(delta: float) -> void:
	if _player == null:
		return
	var pp: Vector3 = _player.global_position
	for i in _cr_nodes.size():
		if not _cr_active[i]:
			continue
		var n := _cr_nodes[i]
		_cr_phase[i] += delta * (10.0 if _cr_kind[i] == Kind.BIRD else 14.0)
		match _cr_kind[i]:
			Kind.BIRD:
				# Krazenie wokol home (orbita) + lekkie falowanie wysokosci (machanie skrzydel = skala Y).
				var orbit := _cr_vel[i]
				# Sila dosrodkowa ku home (utrzymuje orbite).
				var to_home := _cr_home[i] - n.global_position
				to_home.y = 0.0
				orbit += to_home * 0.6 * delta
				orbit.y = 0.0
				if orbit.length() > 0.01:
					orbit = orbit.normalized() * _cr_speed[i]
				_cr_vel[i] = orbit
				n.global_position += orbit * delta
				n.global_position.y = _cr_home[i].y + sin(_cr_phase[i] * 0.3) * 1.2
				n.scale.y = 0.6 + absf(sin(_cr_phase[i])) * 0.6      # "machanie skrzydel"
				if orbit.length() > 0.01:
					n.rotation.y = atan2(orbit.x, orbit.z)
			Kind.CRITTER:
				# Krytery: spokojne dryfowanie; UCIEKAJA gdy gracz blisko (czytelne "ozywienie trawy").
				var flee := n.global_position - pp
				flee.y = 0.0
				var d := flee.length()
				if d < 7.0 and d > 0.01:
					_cr_vel[i] = flee.normalized() * _cr_speed[i] * 1.8   # sprint ucieczki
				else:
					# Powolne losowe dryfowanie (kicanie) wokol home.
					_cr_vel[i] = _cr_vel[i].lerp(Vector3.ZERO, delta * 1.2)
				n.global_position += _cr_vel[i] * delta
				n.global_position.y = _ground_y(n.global_position.x, n.global_position.z) + 0.18 \
					+ absf(sin(_cr_phase[i])) * 0.12                      # kicanie
				if _cr_vel[i].length() > 0.05:
					n.rotation.y = atan2(_cr_vel[i].x, _cr_vel[i].z)
			Kind.FISH:
				# Ryby: drobny dryf tuz pod tafla, lekkie wynurzenia (faza).
				n.global_position += _cr_vel[i] * delta
				n.global_position.y = _water_level - 0.05 + sin(_cr_phase[i] * 0.2) * 0.06
				# Odbicie od granicy promienia spawnu (zostaja w "stawie").
				var fd := Vector2(n.global_position.x - _cr_home[i].x, n.global_position.z - _cr_home[i].z)
				if fd.length() > 4.0:
					_cr_vel[i] = -_cr_vel[i]


# ============================================================================
#  DISTANT EVENTS — rzadkie, odlegle wizualia (skala swiata). LOSOWY (RNG) trigger, czysto wizualny.
# ============================================================================
func _maybe_spawn_event() -> void:
	if _rng.randf() > EVENT_CHANCE:
		return
	var slot := -1
	for i in _ev_active.size():
		if not _ev_active[i]:
			slot = i
			break
	if slot < 0:
		return
	var pp: Vector3 = _player.global_position
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(EVENT_DIST_MIN, EVENT_DIST_MAX)
	var bx := pp.x + cos(ang) * dist
	var bz := pp.z + sin(ang) * dist
	var ground := _ground_y(bx, bz)
	var kind := _rng.randi_range(0, 3)
	_trigger_event(slot, kind, Vector3(bx, ground, bz), pp)


func _trigger_event(slot: int, kind: int, base: Vector3, pp: Vector3) -> void:
	var n := _ev_nodes[slot]
	var mat := _ev_mat[slot]
	_ev_kind[slot] = kind
	_ev_active[slot] = true
	match kind:
		Event.FLYER:
			# Sylwetka latajacego stwora przelatujaca przez horyzont (wysoko, wolno).
			n.global_position = base + Vector3(0.0, 22.0, 0.0)
			_ev_vel[slot] = Vector3(cos(_rng.randf() * TAU), 0.0, sin(_rng.randf() * TAU)).normalized() * 6.0
			_ev_life[slot] = 9.0
			n.scale = Vector3(2.4, 1.0, 1.0)
			mat.albedo_color = Color(0.12, 0.12, 0.16, 0.9)   # ciemna sylwetka
			mat.emission_energy_multiplier = 0.0
		Event.SMOKE:
			# Slup dymu wznoszacy sie z odleglego punktu (stale, dlugie).
			n.global_position = base + Vector3(0.0, 6.0, 0.0)
			_ev_vel[slot] = Vector3(0.0, 1.2, 0.0)            # powolne wznoszenie (rozmywanie skala Y)
			_ev_life[slot] = 14.0
			n.scale = Vector3(2.0, 8.0, 2.0)
			mat.albedo_color = Color(0.3, 0.28, 0.26, 0.5)
			mat.emission_energy_multiplier = 0.0
		Event.METEOR:
			# Spadajaca gwiazda/meteor: smuga lecaca ukosem w dol (szybka, swiecaca).
			n.global_position = base + Vector3(0.0, 60.0, 0.0)
			var dir := (pp - n.global_position).normalized()
			_ev_vel[slot] = (dir + Vector3(0.0, -1.0, 0.0)).normalized() * 38.0
			_ev_life[slot] = 2.4
			n.scale = Vector3(0.5, 0.5, 3.0)
			mat.albedo_color = Color(1.0, 0.85, 0.5, 1.0)
			mat.emission = Color(1.0, 0.8, 0.4)
			mat.emission_energy_multiplier = 5.0
		Event.FLASH:
			# Odlegly blysk (burza/eksplozja na horyzoncie) — krotki, jasny rozblysk.
			n.global_position = base + Vector3(0.0, 10.0, 0.0)
			_ev_vel[slot] = Vector3.ZERO
			_ev_life[slot] = 0.6
			n.scale = Vector3(4.0, 4.0, 1.0)
			mat.albedo_color = Color(1.0, 0.95, 0.8, 1.0)
			mat.emission = Color(1.0, 0.95, 0.8)
			mat.emission_energy_multiplier = 8.0
	_ev_t[slot] = _ev_life[slot]
	n.visible = true


func _animate_events(delta: float) -> void:
	for i in _ev_nodes.size():
		if not _ev_active[i]:
			continue
		_ev_t[i] = maxf(0.0, _ev_t[i] - delta)
		var n := _ev_nodes[i]
		var k := _ev_t[i] / maxf(0.001, _ev_life[i])   # 1 -> 0
		n.global_position += _ev_vel[i] * delta
		var mat := _ev_mat[i]
		match _ev_kind[i]:
			Event.SMOKE:
				# Dym rozmywa sie ku gorze (rosnie + blednie u szczytu zycia).
				n.scale.y = 8.0 * (1.0 + (1.0 - k) * 0.6)
				if mat != null:
					mat.albedo_color.a = clampf(k * 0.5, 0.0, 0.5)
			Event.FLASH:
				if mat != null:
					mat.emission_energy_multiplier = 8.0 * k   # szybkie zgasniecie
					mat.albedo_color.a = clampf(k, 0.0, 1.0)
			Event.METEOR:
				if mat != null:
					mat.emission_energy_multiplier = 5.0 * clampf(k * 1.5, 0.0, 1.0)
			Event.FLYER:
				if mat != null:
					# Fade na koncu przelotu (znika za horyzontem).
					mat.albedo_color.a = clampf(k * 2.0, 0.0, 0.9)
		if _ev_t[i] <= 0.0:
			_ev_active[i] = false
			n.visible = false


# ============================================================================
#  POMOCNIKI — biom/grunt (duck-typed na VoxelWorld; bezpieczne gdy null = test/headless)
# ============================================================================
func _biome_at(wx: float, wz: float) -> StringName:
	if _world != null and _world.has_method("get_biome"):
		return _world.get_biome(int(floor(wx)), int(floor(wz)))
	return &"verdant"


func _ground_y(wx: float, wz: float) -> float:
	if _world != null and _world.has_method("height_at"):
		return _world.height_at(wx, wz)
	return 0.0


# ============================================================================
#  FABRYKI NODOW (pula) — tanie meshe, unshaded/billboard, BEZ kolizji/fizyki/Area3D
# ============================================================================
func _make_creature_node() -> Node3D:
	# Stworzenie = maly billboard quad (ptak/krytter/ryba). Tani, zawsze zwrocony do kamery.
	var mi := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.5, 0.32)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.1, 0.1, 0.12)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	mi.mesh = mesh
	mi.visible = false
	# Distance fade: dalekie stworzenia gasna (tanio na 4GB; nie rysujemy ich w mgle).
	mi.set_meta("mat", mat)
	return mi


# Styl stworzenia (kolor/rozmiar) wg typu+biomu. Wolane przy spawnie (re-use materialu slotu).
func _style_creature(slot: int, kind: int, biome: StringName) -> void:
	var mat := _cr_mat[slot]
	var mesh := (_cr_nodes[slot] as MeshInstance3D).mesh as QuadMesh
	if mat == null or mesh == null:
		return
	mat.emission_enabled = false
	match kind:
		Kind.BIRD:
			mesh.size = Vector2(0.7, 0.28)
			mat.albedo_color = Color(0.12, 0.12, 0.16, 0.95) if biome != &"emberwaste" \
				else Color(0.18, 0.12, 0.1, 0.95)   # sep w pustce
		Kind.FISH:
			mesh.size = Vector2(0.42, 0.18)
			mat.albedo_color = Color(0.6, 0.75, 0.85, 0.85)
			mat.emission_enabled = true
			mat.emission = Color(0.4, 0.6, 0.7)
			mat.emission_energy_multiplier = 0.6
		_:
			mesh.size = Vector2(0.34, 0.26)
			# Krytter: barwa biomu (brazowy verdant, rdzawy ember).
			mat.albedo_color = Color(0.45, 0.32, 0.2, 0.95) if biome != &"emberwaste" \
				else Color(0.5, 0.3, 0.18, 0.95)


func _make_event_node() -> Node3D:
	# Distant-event = billboard quad (sylwetka/dym/meteor/blysk). Skala/kolor ustawia _trigger_event.
	var mi := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.1, 0.1, 0.12, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	mi.mesh = mesh
	mi.visible = false
	mi.set_meta("mat", mat)
	return mi


# ============================================================================
#  DIAGNOSTYKA (test Feel5) — liczniki aktywnych stworzen/eventow
# ============================================================================
func active_creature_count() -> int:
	var n := 0
	for a in _cr_active:
		if a:
			n += 1
	return n


func active_event_count() -> int:
	var n := 0
	for a in _ev_active:
		if a:
			n += 1
	return n


## Test hook: wymusza wyzwolenie jednego distant-eventu danego rodzaju (rzadkosc obchodzimy w tescie).
func force_event(kind: int) -> bool:
	if _player == null:
		return false
	var slot := -1
	for i in _ev_active.size():
		if not _ev_active[i]:
			slot = i
			break
	if slot < 0:
		return false
	var pp: Vector3 = _player.global_position
	_trigger_event(slot, kind, pp + Vector3(100.0, 0.0, 0.0), pp)
	return true


## Test hook: wymusza pelne przeliczenie populacji (despawn/dospawn) bez czekania na throttling.
func force_repopulate() -> void:
	if _player != null and is_instance_valid(_player):
		_repopulate()
