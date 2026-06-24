extends Node
## NewGameFlowTest.gd — weryfikuje naprawę "Nowa gra wrzuca do istniejącej gry".
## Uruchomienie: godot --headless res://test/NewGameFlowTest.tscn
##
## "Nowa gra" przeładowuje scenę i ustawia GameState.pending_new_game (autoload przeżywa reload).
## Po przeładowaniu Main._setup_menus ma AUTO-WEJŚĆ do świeżej gry (ukryć menu + odpauzować), zamiast
## zostawić gracza w menu nad starą sesją. Symulujemy stan PO reloadzie: flaga ustawiona + gra
## spauzowana (jak menu) + sesja sieciowa zrzucona, a następnie instancjonujemy Main.tscn.
##
## Sprawdza:
##  (1) auto-enter konsumuje flagę (pending_new_game == false po _ready),
##  (2) gra NIE jest spauzowana po auto-wejściu (menu zostało ukryte, sterowanie u gracza),
##  (3) NetManager jest w trybie SINGLE (nowa gra zrzuca ewentualną sesję co-op).
## Kod wyjścia: 0 = ALL OK, 1 = FAIL.

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[NG] FAIL: %s" % msg)


func _ready() -> void:
	print("[NG] === New game flow test ===")
	# Stan PO reloadzie wywołanym przez "Nowa gra".
	NetManager.leave()                          # nowa gra zrzuca sesję sieciową -> SINGLE
	GameState.pending_new_game = true
	GameState.set_paused(true)                  # menu zwykle pauzuje pod sobą; auto-enter ma to cofnąć

	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)                             # Main._ready -> _setup_menus -> flaga -> _enter_new_game
	await get_tree().process_frame
	await get_tree().process_frame

	_check(not GameState.pending_new_game, "pending_new_game nie skonsumowana (auto-enter nie zadziałał)")
	_check(not get_tree().paused, "gra nadal spauzowana po auto-wejściu (menu nie zostało ukryte)")
	_check(NetManager.mode == NetManager.Mode.SINGLE, "NetManager nie w trybie SINGLE po nowej grze")

	main.queue_free()
	await get_tree().process_frame
	if _failures == 0:
		print("[NG] ALL OK")
	else:
		printerr("[NG] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
