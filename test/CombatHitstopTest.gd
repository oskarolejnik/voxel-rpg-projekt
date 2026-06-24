extends Node
## CombatHitstopTest.gd — weryfikuje TIEROWANY hitstop (audyt rank #3).
## Uruchomienie: godot --headless res://test/CombatHitstopTest.tscn
##
## Zwykłe trafienia muszą używać LOKALNEGO freeze-frame (sterowanie/bufor responsywne — NIE globalny
## Engine.time_scale, który zamrażał też wejście gracza). Globalny bezczas zostaje TYLKO dla krytyka/
## ciężkiego ciosu w SP (emfaza). Co-op zawsze lokalnie (tu testujemy SP — has_network()==false).
##
##  (1) zwykłe trafienie (allow_global=false): _local_freeze_t > 0 ORAZ Engine.time_scale == 1.0.
##  (2) krytyk/ciężki (allow_global=true) w SP: Engine.time_scale < 1.0 (globalny bezczas).
##  (3) brak leaku: po wygaśnięciu hitstopów Engine.time_scale wraca do 1.0.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL.

const PlayerScript := preload("res://src/Player.gd")

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[HS] FAIL: %s" % msg)


func _ready() -> void:
	print("[HS] === Combat hitstop tiering test ===")
	Engine.time_scale = 1.0
	var p = PlayerScript.new()
	add_child(p)
	await get_tree().process_frame          # _ready: komponenty/model

	# (1) Zwykłe trafienie -> lokalny freeze, ZERO globalnego bezczasu (sterowanie responsywne).
	p._hitstop_active = false
	p._local_freeze_t = 0.0
	Engine.time_scale = 1.0
	p._hitstop(0.1, false)                  # start korutyny; część przed pierwszym await jest synchroniczna
	_check(p._local_freeze_t > 0.0, "zwykłe trafienie nie ustawiło lokalnego freeze (_local_freeze_t=%.3f)" % p._local_freeze_t)
	_check(absf(Engine.time_scale - 1.0) < 0.0001,
		"zwykłe trafienie ZAMRAŻA globalny czas (time_scale=%.3f) — sterowanie nieresponsywne" % Engine.time_scale)

	# (2) Krytyk/ciężki w SP -> globalny bezczas (emfaza dużego ciosu).
	p._hitstop_active = false
	Engine.time_scale = 1.0
	p._hitstop(0.1, true)
	_check(Engine.time_scale < 1.0, "krytyk/ciężki NIE używa globalnego bezczasu (time_scale=%.3f)" % Engine.time_scale)

	# (3) Po wygaśnięciu (timery ignore_time_scale -> realny czas) globalny czas wraca do 1.0.
	await get_tree().create_timer(0.3, true, false, true).timeout
	_check(absf(Engine.time_scale - 1.0) < 0.0001, "time_scale nie wrócił do 1.0 (leak: %.3f)" % Engine.time_scale)

	Engine.time_scale = 1.0                  # bezpieczeństwo dla pozostałych testów
	p.queue_free()
	if _failures == 0:
		print("[HS] ALL OK")
	else:
		printerr("[HS] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
