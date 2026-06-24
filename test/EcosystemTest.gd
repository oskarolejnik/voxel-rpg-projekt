extends Node
## EcosystemTest.gd — headless test EKOSYSTEMU (GDD Świat §4): AIComponent.disposition
## hostile / neutral / passive. Uruchomienie: godot --headless res://test/EcosystemTest.tscn
##
## Sprawdza:
##  (1) HOSTILE (default) — agresuje „na widok" (IDLE -> CHASE gdy gracz w aggro). Wstecznie zgodne.
##  (2) NEUTRAL — NIE agresuje na widok; CHASE DOPIERO po prowokacji (wake_to_chase).
##  (3) PASSIVE — nigdy nie CHASE/ATTACK; gracz w zasiegu spłoszenia -> ucieka OD gracza.
##  (4) PASSIVE — prowokacja (wake_to_chase) ustawia flee i ucieka nawet gdy gracz daleko.
##  (5) configure() czyta "disposition" z danych (enum oraz surowy int).
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[ECO] ...".

var _failures := 0


## Atrapa „ciała" wroga: implementuje kontrakt ai_* z AIComponent i rejestruje wywołania.
class DummyHost extends Node3D:
	var target: Node3D = null
	var last_move := Vector3.INF
	var move_calls := 0
	var attack_calls := 0
	var stopped := false
	func ai_get_position() -> Vector3: return global_position
	func ai_get_target() -> Node3D: return target
	func ai_move_towards(point: Vector3, _speed: float) -> void:
		last_move = point
		move_calls += 1
	func ai_stop() -> void: stopped = true
	func ai_face(_dir: Vector3) -> void: pass
	func ai_attack(_t: Node3D) -> void: attack_calls += 1
	func ai_can_attack() -> bool: return true


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[ECO] FAIL: %s" % msg)


## Buduje [host, ai] z danym disposition (allegiance_hostile=true = dzikie stworzenie).
func _make(disp: int) -> Array:
	var host := DummyHost.new()
	add_child(host)
	var ai := AIComponent.new()
	ai.disposition = disp
	ai.allegiance_hostile = true
	host.add_child(ai)        # ai._ready -> _host = host
	ai.set_home(Vector3.ZERO)
	return [host, ai]


func _spawn_player(at: Vector3) -> Node3D:
	var p := Node3D.new()
	add_child(p)
	p.global_position = at
	return p


func _ready() -> void:
	print("[ECO] === Ecosystem (disposition) test start ===")
	_test_hostile_aggro_on_sight()
	_test_neutral_no_aggro_until_provoked()
	_test_passive_flees_from_player()
	_test_passive_provoked_flees()
	_test_configure_reads_disposition()
	_test_resource_wires_disposition()
	if _failures == 0:
		print("[ECO] ALL OK")
	else:
		printerr("[ECO] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


# ---------------------------------------------------------------------------
#  (1) HOSTILE (default) — agresuje na widok (wstecznie zgodne z dawnym zachowaniem)
# ---------------------------------------------------------------------------
func _test_hostile_aggro_on_sight() -> void:
	var pair := _make(AIComponent.Disposition.HOSTILE)
	var host := pair[0] as DummyHost
	var ai := pair[1] as AIComponent
	host.global_position = Vector3.ZERO
	host.target = _spawn_player(Vector3(3.0, 0.0, 0.0))   # w aggro_radius (12)
	ai._state = AIComponent.State.IDLE
	ai.tick(0.1)
	_check(ai.get_state() == AIComponent.State.CHASE,
		"HOSTILE nie wszedl w CHASE na widok gracza (stan %d)" % ai.get_state())
	host.target.queue_free()
	host.queue_free()
	print("[ECO] (1) HOSTILE agresuje na widok OK")


# ---------------------------------------------------------------------------
#  (2) NEUTRAL — brak agresji na widok; CHASE dopiero po prowokacji
# ---------------------------------------------------------------------------
func _test_neutral_no_aggro_until_provoked() -> void:
	var pair := _make(AIComponent.Disposition.NEUTRAL)
	var host := pair[0] as DummyHost
	var ai := pair[1] as AIComponent
	host.global_position = Vector3.ZERO
	host.target = _spawn_player(Vector3(3.0, 0.0, 0.0))   # w aggro_radius, ale NEUTRAL ma czekac
	ai._state = AIComponent.State.IDLE
	for i in 5:
		ai.tick(0.1)
		_check(ai.get_state() != AIComponent.State.CHASE and ai.get_state() != AIComponent.State.ATTACK,
			"NEUTRAL zaatakowal na widok (stan %d, tick %d)" % [ai.get_state(), i])
	ai.wake_to_chase()   # prowokacja (trafienie)
	_check(ai.get_state() == AIComponent.State.CHASE,
		"NEUTRAL po prowokacji nie wszedl w CHASE (stan %d)" % ai.get_state())
	host.target.queue_free()
	host.queue_free()
	print("[ECO] (2) NEUTRAL: brak agresji na widok, CHASE po prowokacji OK")


# ---------------------------------------------------------------------------
#  (3) PASSIVE — nigdy nie atakuje; gracz blisko => ucieka OD gracza
# ---------------------------------------------------------------------------
func _test_passive_flees_from_player() -> void:
	var pair := _make(AIComponent.Disposition.PASSIVE)
	var host := pair[0] as DummyHost
	var ai := pair[1] as AIComponent
	host.global_position = Vector3.ZERO
	host.target = _spawn_player(Vector3(3.0, 0.0, 0.0))   # w PASSIVE_SCARE_RADIUS (6) — splosza sie
	ai._state = AIComponent.State.IDLE
	host.move_calls = 0
	ai.tick(0.1)
	_check(ai.get_state() != AIComponent.State.CHASE and ai.get_state() != AIComponent.State.ATTACK,
		"PASSIVE wszedl w agresje (stan %d)" % ai.get_state())
	_check(host.move_calls > 0, "PASSIVE nie ruszyl mimo gracza w zasiegu (brak ai_move_towards)")
	_check(host.last_move.x < 0.0,
		"PASSIVE nie ucieka OD gracza (cel ruchu x=%.2f, oczekiwane <0 bo gracz na +x)" % host.last_move.x)
	_check(host.attack_calls == 0, "PASSIVE zaatakowal (attack_calls=%d)" % host.attack_calls)
	host.target.queue_free()
	host.queue_free()
	print("[ECO] (3) PASSIVE ucieka od gracza OK")


# ---------------------------------------------------------------------------
#  (4) PASSIVE — prowokacja ustawia flee i ucieka nawet gdy gracz daleko
# ---------------------------------------------------------------------------
func _test_passive_provoked_flees() -> void:
	var pair := _make(AIComponent.Disposition.PASSIVE)
	var host := pair[0] as DummyHost
	var ai := pair[1] as AIComponent
	host.global_position = Vector3.ZERO
	host.target = _spawn_player(Vector3(50.0, 0.0, 0.0))   # DALEKO (poza scare), ale prowokacja
	ai._state = AIComponent.State.IDLE
	ai.wake_to_chase()   # PASSIVE -> flee timer (nie CHASE)
	_check(ai.get_state() != AIComponent.State.CHASE,
		"PASSIVE po prowokacji wszedl w CHASE (powinien uciekac)")
	host.move_calls = 0
	ai.tick(0.1)
	_check(host.move_calls > 0, "PASSIVE sprowokowany nie ucieka (brak ruchu)")
	_check(host.last_move.x < 0.0, "PASSIVE sprowokowany nie ucieka OD gracza (x=%.2f)" % host.last_move.x)
	_check(host.attack_calls == 0, "PASSIVE sprowokowany zaatakowal (attack_calls=%d)" % host.attack_calls)
	host.target.queue_free()
	host.queue_free()
	print("[ECO] (4) PASSIVE sprowokowany ucieka OK")


# ---------------------------------------------------------------------------
#  (5) configure() czyta "disposition" z danych (enum i surowy int)
# ---------------------------------------------------------------------------
func _test_configure_reads_disposition() -> void:
	var pair := _make(AIComponent.Disposition.HOSTILE)
	var host := pair[0] as DummyHost
	var ai := pair[1] as AIComponent
	ai.configure({"disposition": AIComponent.Disposition.PASSIVE})
	_check(ai.disposition == AIComponent.Disposition.PASSIVE,
		"configure nie ustawil disposition=PASSIVE (jest %d)" % ai.disposition)
	ai.configure({"disposition": 1})
	_check(ai.disposition == AIComponent.Disposition.NEUTRAL,
		"configure nie ustawil disposition=NEUTRAL z int 1 (jest %d)" % ai.disposition)
	# Brak klucza => zostaje bez zmian (wsteczna zgodnosc: dane bez "disposition" => hostile).
	ai.disposition = AIComponent.Disposition.HOSTILE
	ai.configure({})
	_check(ai.disposition == AIComponent.Disposition.HOSTILE,
		"configure bez klucza zmienil disposition (jest %d, oczekiwane HOSTILE)" % ai.disposition)
	host.queue_free()
	print("[ECO] (5) configure czyta disposition (enum/int/brak) OK")


# ---------------------------------------------------------------------------
#  (6) INTEGRACJA — EnemyResource.disposition (.tres) -> Enemy -> AIComponent.
#      Weryfikuje, że dzika zwierzyna (deer=passive, boar=neutral) jest wczytana i zwiazana z AI.
# ---------------------------------------------------------------------------
func _test_resource_wires_disposition() -> void:
	if EnemyDB == null:
		_check(false, "brak EnemyDB do testu integracyjnego (6)")
		return
	EnemyDB.reload()
	var deer_res: EnemyResource = EnemyDB.enemy(&"deer")
	var boar_res: EnemyResource = EnemyDB.enemy(&"boar")
	_check(deer_res != null, "EnemyDB nie zna 'deer' (deer.tres nie wczytany)")
	_check(boar_res != null, "EnemyDB nie zna 'boar' (boar.tres nie wczytany)")
	if deer_res == null or boar_res == null:
		return
	_check(deer_res.disposition == AIComponent.Disposition.PASSIVE,
		"deer.tres disposition != PASSIVE (jest %d)" % deer_res.disposition)
	_check(boar_res.disposition == AIComponent.Disposition.NEUTRAL,
		"boar.tres disposition != NEUTRAL (jest %d)" % boar_res.disposition)
	# Integracja: Enemy z deer.tres po _ready ma AIComponent.disposition == PASSIVE (configure_from_resource
	# -> Enemy.disposition -> _build_components -> _ai.configure). configure WOLANE przed add_child.
	var e := Enemy.new()
	e.configure_from_resource(deer_res)
	add_child(e)
	_check(e._ai != null, "Enemy nie zbudowal AIComponent po _ready")
	if e._ai != null:
		_check(e._ai.disposition == AIComponent.Disposition.PASSIVE,
			"AIComponent po wiringu z deer.tres != PASSIVE (jest %d)" % e._ai.disposition)
	e.queue_free()
	print("[ECO] (6) wiring EnemyResource.disposition -> Enemy -> AIComponent OK")
