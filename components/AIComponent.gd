class_name AIComponent
extends Node
## AIComponent.gd (komponent) — maszyna stanow wroga/peta (idle/patrol/chase/attack/leash),
## HOST-ONLY (TDD 1.2 / 6.2: AI liczone tylko na hoscie; klient widzi wynik przez sync).
## Refaktor istniejacej logiki z Enemy.gd na komponent: ta sama histereza, leash, entry-delay,
## ale decyzje ataku ida przez AbilityComponent (TDD 1.2), a wartosci czyta z eksportow encji.
##
## KONTRAKT z encja (Enemy/pet) — komponent jest "mozgiem", encja "cialem":
##   host.ai_get_position() -> Vector3
##   host.ai_get_target() -> Node3D (lub null)
##   host.ai_move_towards(point: Vector3, speed: float)   # ustawia velocity.xz
##   host.ai_stop()                                        # velocity.xz = 0
##   host.ai_face(dir: Vector3)                            # kierunek modelu
##   host.ai_attack(target: Node3D)                        # 1 cios (przez AbilityComponent/hitbox)
##   host.ai_can_attack() -> bool                          # CD ataku zszedl
## Komponent zwraca w tick() wybrany stan (do animacji/diagnostyki). Brak autorytetu -> NO-OP.

## ETAP 6: dodany stan FOLLOW (pet idzie za graczem). Mapowanie enum 1:1 z Enemy.State (IDLE..FOLLOW).
enum State { IDLE, PATROL, CHASE, ATTACK, FOLLOW }

## Parametry zachowania — domyslne = obecny Goblin z Enemy.gd; encja moze nadpisac przez configure().
var move_speed: float = 3.5
var attack_range: float = 2.0
var aggro_radius: float = 12.0
var leash_radius: float = 18.0
var patrol_radius: float = 6.0
var attack_entry_delay: float = 0.35

var allegiance_hostile: bool = true        # pet (ALLY) celuje w HOSTILE; HOSTILE celuje w gracza

# ============================================================================
#  EKOSYSTEM (GDD Świat §4) — DISPOSITION dzikiego stworzenia: hostile / neutral / passive.
# ============================================================================
# Steruje TYLKO dzikim stworzeniem (allegiance_hostile=true, NIE pet). Default HOSTILE => pełna
# wsteczna zgodność: istniejący Goblin/Brute/Slinger bez zmiany zachowania, pet/ALLY nietknięty.
#   HOSTILE — agresywny na widok (CHASE w aggro_radius) ORAZ kontratak po trafieniu (jak dotąd).
#   NEUTRAL — NIE atakuje na widok; kontratakuje DOPIERO po sprowokowaniu (trafienie -> CHASE).
#   PASSIVE — nigdy nie atakuje; po sprowokowaniu LUB gdy gracz blisko -> UCIEKA (flee) od zagrożenia.
# Wartość jest danymi (configure() czyta "disposition" z EnemyResource); enum trzymamy jako int,
# by uniknąć ścisłej konwersji int->enum przy odczycie z Dictionary.
enum Disposition { HOSTILE, NEUTRAL, PASSIVE }
var disposition: int = Disposition.HOSTILE
const FLEE_TIME: float = 4.0             # s ucieczki po sprowokowaniu (PASSIVE)
const FLEE_SPEED_MULT: float = 1.35      # passive ucieka szybciej niż patroluje
const PASSIVE_SCARE_RADIUS: float = 6.0  # gracz bliżej niż to => passive ucieka „na widok"
var _flee_timer: float = 0.0             # >0 = passive w trakcie ucieczki (po prowokacji)

# ETAP 6 — parametry peta (ALLY). Anchor leasha = gracz (zamiast _home). Pet skanuje wrogow z grupy
# "enemies" w PET_AGGRO_RADIUS od SIEBIE; gdy za daleko od gracza (PET_LEASH_RADIUS) porzuca cel i
# wraca do FOLLOW. Histereza FOLLOW (stop/resume), by nie deptal graczowi po petach.
#
# NIEZMIENNIK (review): PET_AGGRO_RADIUS + FOLLOW_RESUME_DIST <= PET_LEASH_RADIUS. Dzieki temu cel
# namierzony z najdalszej granicy aggro (gdy pet jest w FOLLOW_RESUME ~5 m od gracza) NIE jest od
# razu za leashem -> brak oscylacji CHASE<->FOLLOW (pet plynnie dogania zamiast "drgac"). 10+5=15<=16.
const PET_AGGRO_RADIUS: float = 10.0
const PET_LEASH_RADIUS: float = 16.0
const FOLLOW_STOP_DIST: float = 3.0
const FOLLOW_RESUME_DIST: float = 5.0
var _leash_anchor: Node3D = null           # null => wrog (leash do _home); ustawiony => pet (leash do gracza)

var _state: State = State.IDLE
var _home: Vector3 = Vector3.ZERO
var _patrol_target: Vector3 = Vector3.ZERO
var _idle_timer: float = 0.0
var _patrol_timer: float = 0.0
var _entry_delay_left: float = 0.0

var _host: Node = null


func _ready() -> void:
	_host = get_parent()
	_idle_timer = randf_range(1.5, 3.5)


## Wstrzykuje parametry z eksportow encji (zeby tuning zostal w Enemy.gd/EnemyResource).
func configure(p: Dictionary) -> void:
	move_speed = float(p.get("move_speed", move_speed))
	attack_range = float(p.get("attack_range", attack_range))
	aggro_radius = float(p.get("aggro_radius", aggro_radius))
	leash_radius = float(p.get("leash_radius", leash_radius))
	patrol_radius = float(p.get("patrol_radius", patrol_radius))
	attack_entry_delay = float(p.get("attack_entry_delay", attack_entry_delay))
	allegiance_hostile = bool(p.get("allegiance_hostile", allegiance_hostile))
	disposition = int(p.get("disposition", disposition))   # ekosystem: 0=hostile/1=neutral/2=passive


func set_home(h: Vector3) -> void:
	_home = h
	_patrol_target = h


## ETAP 6 — przelacza komponent w tryb PETA (ALLY). Cel = najblizszy WROG (nie gracz), leash do
## gracza (anchor), start w FOLLOW. Reuse calej maszyny (CHASE/ATTACK/leash) — zmienia sie tylko
## KOGO uznajemy za cel i DOKAD wracamy. WOLANE z Enemy.convert_to_pet().
func set_allegiance_ally(owner_node: Node3D) -> void:
	allegiance_hostile = false
	_leash_anchor = owner_node
	aggro_radius = PET_AGGRO_RADIUS
	_state = State.FOLLOW


func get_state() -> State:
	return _state


## ETAP 6 — PUBLICZNY dostep do AI-rozwiazanego celu (liczony na biezaco z pozycji hosta). Uzywa go
## ranged pet przy spawnie pocisku: MUSI celowac we WROGA wskazanego przez maszyne, a nie w
## niejednoznaczne Enemy._target (fallback _physics_process potrafi przestawic _target na GRACZA,
## a take_damage na atakujacego wroga). Wrog: gracz (ai_get_target). Pet (ALLY): najblizszy zywy wrog.
func current_target() -> Node3D:
	if _host == null or not is_instance_valid(_host):
		return null
	return _resolve_target(_host.ai_get_position())


## Wybudzenie przez trafienie (z Enemy.take_damage): wymusza pogon.
## ETAP 6 (review): FOLLOW tez wybudza sie do CHASE — pet trafiony spoza aggro (np. ranged wrog)
## natychmiast kontratakuje, zamiast czekac az _follow() sam zobaczy wroga. Bezpieczne: CHASE bez
## celu spadnie z powrotem do FOLLOW przez _lose_target() (pet) / PATROL (wrog).
func wake_to_chase() -> void:
	# EKOSYSTEM: PASSIVE sprowokowane UCIEKA (nie walczy) — ustawiamy timer flee, _passive_tick zajmie się ruchem.
	if disposition == Disposition.PASSIVE:
		_flee_timer = FLEE_TIME
		return
	# HOSTILE i NEUTRAL: trafione -> kontratak (CHASE). To realizuje „neutral: attack only if provoked".
	if _state == State.IDLE or _state == State.PATROL or _state == State.FOLLOW:
		_state = State.CHASE


## Glowny krok AI (wolany z _physics_process encji). HOST-ONLY. Zwraca biezacy stan.
func tick(delta: float) -> int:
	# HOST-ONLY (TDD 6.2). W SP has_authority == true -> dziala lokalnie; klient -> NO-OP (sync).
	if NetManager != null and not NetManager.has_authority(_host):
		return _state
	if _host == null or not is_instance_valid(_host):
		return _state

	var pos: Vector3 = _host.ai_get_position()
	# ETAP 6: cel zalezy od allegiance. Wrog -> gracz (ai_get_target). Pet -> najblizszy ZYWY wrog.
	var target: Node3D = _resolve_target(pos)
	var has_target := target != null and is_instance_valid(target)
	var dist := INF
	if has_target:
		var d: Vector3 = target.global_position - pos
		dist = Vector2(d.x, d.z).length()

	# EKOSYSTEM: PASSIVE nigdy nie CHASE/ATTACK — osobna ścieżka ucieczki/wander (zostaje w IDLE/PATROL).
	if disposition == Disposition.PASSIVE and allegiance_hostile:
		_passive_tick(delta, pos, target)
		return _state

	match _state:
		State.IDLE:    _idle(delta, has_target, dist)
		State.PATROL:  _patrol(delta, has_target, dist, pos)
		State.CHASE:   _chase(has_target, dist, target, pos)
		State.ATTACK:  _attack(delta, has_target, dist, target, pos)
		State.FOLLOW:  _follow(has_target, dist, pos)
	return _state


## ETAP 6 — JEDNO miejsce wyboru celu (odwraca logike bez duplikowania maszyny).
## Wrog: cel = gracz (host.ai_get_target). Pet: cel = najblizszy ZYWY wrog z grupy "enemies".
func _resolve_target(pos: Vector3) -> Node3D:
	if allegiance_hostile:
		return _host.ai_get_target()
	return _nearest_enemy(pos)


## Pet: najblizszy zywy wrog (grupa "enemies") w PET_AGGRO_RADIUS od peta. Pomija martwych/niewaznych.
func _nearest_enemy(pos: Vector3) -> Node3D:
	if _host == null or not is_instance_valid(_host):
		return null
	var best: Node3D = null
	var best_d := aggro_radius * aggro_radius
	for e in _host.get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue
		var d: Vector3 = (e as Node3D).global_position - pos
		var dsq := d.x * d.x + d.z * d.z
		if dsq < best_d:
			best_d = dsq
			best = e as Node3D
	return best


func _idle(delta: float, has_target: bool, dist: float) -> void:
	_host.ai_stop()
	# EKOSYSTEM: tylko HOSTILE agresuje „na widok". NEUTRAL czeka na prowokację, PASSIVE nie trafia tu.
	if disposition == Disposition.HOSTILE and has_target and dist <= aggro_radius:
		_state = State.CHASE
		return
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_pick_patrol_target()
		_patrol_timer = 5.0
		_state = State.PATROL


func _patrol(delta: float, has_target: bool, dist: float, pos: Vector3) -> void:
	# EKOSYSTEM: tylko HOSTILE agresuje „na widok" w trakcie patrolu (patrz _idle).
	if disposition == Disposition.HOSTILE and has_target and dist <= aggro_radius:
		_state = State.CHASE
		return
	_host.ai_move_towards(_patrol_target, move_speed)
	_patrol_timer -= delta
	var to := _patrol_target - pos
	to.y = 0.0
	if to.length() < 0.8 or _patrol_timer <= 0.0:
		_idle_timer = randf_range(1.5, 3.5)
		_state = State.IDLE


func _chase(has_target: bool, dist: float, target: Node3D, pos: Vector3) -> void:
	if not has_target:
		_lose_target()
		return
	# ETAP 6: leash mierzony od ANCHORA (gracz dla peta, _home dla wroga). Pet za daleko od gracza
	# -> porzuca pogon i wraca do FOLLOW; wrog za daleko od domu -> PATROL (zachowanie 1:1 jak dotad).
	if _leash_broken(pos):
		_lose_target()
		return
	if dist <= attack_range:
		_host.ai_stop()
		_entry_delay_left = attack_entry_delay   # okno na unik przed pierwszym ciosem
		_state = State.ATTACK
		return
	_host.ai_move_towards(target.global_position, move_speed)


func _attack(delta: float, has_target: bool, dist: float, target: Node3D, pos: Vector3) -> void:
	_host.ai_stop()
	if not has_target:
		_lose_target()
		return
	if _leash_broken(pos):                         # leash ma priorytet nawet w ataku
		_lose_target()
		return

	# Patrz na cel.
	var to := target.global_position - pos
	to.y = 0.0
	if to.length() > 0.01:
		_host.ai_face(to.normalized())

	# Entry-delay (gracz ma okno na unik), potem cios gdy CD zszedl i cel w zasiegu (histereza 1.3).
	_entry_delay_left = maxf(0.0, _entry_delay_left - delta)
	if _entry_delay_left <= 0.0 and _host.ai_can_attack() and dist <= attack_range * 1.3:
		_host.ai_attack(target)

	# Wyjscie do CHASE z histereza, by stany nie migotaly na granicy.
	if dist > attack_range * 1.3:
		_state = State.CHASE


func _pick_patrol_target() -> void:
	var ang := randf() * TAU
	var r := randf() * patrol_radius
	_patrol_target = _home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)


# ============================================================================
#  EKOSYSTEM — PASSIVE: ucieczka od zagrożenia + spokojny wander (bez agresji)
# ============================================================================
## PASSIVE: nigdy nie atakuje. Ucieka OD gracza gdy sprowokowany (_flee_timer>0, ustawiany przez
## wake_to_chase po trafieniu) LUB gdy gracz w PASSIVE_SCARE_RADIUS („spłoszenie na widok"). W trakcie
## ucieczki biegnie w przeciwną stronę niż zagrożenie (PATROL = animacja biegu, FLEE_SPEED_MULT).
## Gdy spokojnie — łagodny wander wokół _home (reuse _idle/_patrol z has_target=false: zero agresji).
func _passive_tick(delta: float, pos: Vector3, threat: Node3D) -> void:
	_flee_timer = maxf(0.0, _flee_timer - delta)
	var scared := _flee_timer > 0.0
	var has_threat := threat != null and is_instance_valid(threat)
	if has_threat and not scared:
		var dt := threat.global_position - pos
		dt.y = 0.0
		if dt.length() <= PASSIVE_SCARE_RADIUS:
			scared = true
	if scared and has_threat:
		var away := pos - threat.global_position
		away.y = 0.0
		if away.length() < 0.01:
			away = Vector3(1.0, 0.0, 0.0)
		away = away.normalized()
		_host.ai_face(away)
		_host.ai_move_towards(pos + away * 4.0, move_speed * FLEE_SPEED_MULT)
		_state = State.PATROL
		return
	# Spokojnie — łagodny wander wokół domu, BEZ agresji (has_target=false; aggro i tak gated HOSTILE).
	match _state:
		State.IDLE:   _idle(delta, false, INF)
		State.PATROL: _patrol(delta, false, INF, pos)
		_:            _state = State.IDLE   # CHASE/ATTACK/FOLLOW nie dotyczą passive — wróć do IDLE


# ============================================================================
#  ETAP 6 — leash anchor (gracz dla peta, _home dla wroga) + stan FOLLOW
# ============================================================================

## Punkt powrotu/leasha: gracz (pet) albo _home (wrog).
func _leash_origin() -> Vector3:
	if _leash_anchor != null and is_instance_valid(_leash_anchor):
		return _leash_anchor.global_position
	return _home


## Promien leasha: pet trzyma sie blisko gracza (PET_LEASH_RADIUS), wrog jak dotad (leash_radius).
func _leash_radius_eff() -> float:
	return PET_LEASH_RADIUS if _leash_anchor != null else leash_radius


## Czy zerwano leash (pet: za daleko od gracza; wrog: cel za daleko od domu — UWAGA: dla wroga
## leash liczony jest po dystansie do CELU, jak dawniej, by nie zmienic zachowania Etapow 1-5).
func _leash_broken(pos: Vector3) -> bool:
	if _leash_anchor != null:
		var to := _leash_origin() - pos
		to.y = 0.0
		return to.length() > _leash_radius_eff()
	# Wrog: zachowanie 1:1 jak dotad — leash po dystansie XZ do gracza (ai_get_target).
	var t: Node3D = _host.ai_get_target()
	if t == null or not is_instance_valid(t):
		return false
	var dt: Vector3 = t.global_position - pos
	return Vector2(dt.x, dt.z).length() > leash_radius


## Utrata celu / zerwanie leasha: pet wraca do FOLLOW (do gracza), wrog do PATROL (do domu).
func _lose_target() -> void:
	if _leash_anchor != null:
		_state = State.FOLLOW
	else:
		_patrol_target = _home
		_state = State.PATROL


## ETAP 6 — FOLLOW: pet idzie za graczem (anchor). Wrog w PET_AGGRO_RADIUS -> CHASE (ta sama maszyna).
## Histereza ruchu (stop/resume), by pet nie deptal graczowi po piętach ani nie zostawal w tyle.
func _follow(has_target: bool, dist: float, pos: Vector3) -> void:
	if has_target and dist <= aggro_radius:        # wrog w zasiegu -> walcz
		_state = State.CHASE
		return
	if _leash_anchor == null or not is_instance_valid(_leash_anchor):
		_host.ai_stop()
		return
	var to := _leash_anchor.global_position - pos
	to.y = 0.0
	var ad := to.length()
	if ad > FOLLOW_RESUME_DIST:
		_host.ai_move_towards(_leash_anchor.global_position, move_speed * 1.15)  # dogania, nie zostaje w tyle
	elif ad < FOLLOW_STOP_DIST:
		_host.ai_stop()
		if to.length() > 0.01:
			_host.ai_face(to.normalized())
	else:
		_host.ai_move_towards(_leash_anchor.global_position, move_speed)
