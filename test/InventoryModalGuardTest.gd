extends Node
## InventoryModalGuardTest.gd — weryfikuje guard: InventoryUI NIE otwiera sie nad innym modalem.
## Uruchomienie: godot --headless res://test/InventoryModalGuardTest.tscn
##
##  (1) gdy GameState.ui_capturing_input juz true (ustawione przez INNY panel) -> _set_open(true)
##      ODMAWIA otwarcia (lustro guardu z SkillTreeUI; bez tego dwa UI biłyby sie o kursor).
##  (2) gdy flaga wolna -> _set_open(true) otwiera i USTAWIA flage.
##  (3) zamkniecie -> _set_open(false) CZYSCI flage.
## Kod wyjscia: 0 = ALL OK, 1 = FAIL.

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[INVGUARD] FAIL: %s" % msg)


func _read_open(ui: InventoryUI) -> bool:
	return ui.get("_open")


func _ready() -> void:
	print("[INVGUARD] === Inventory modal guard test ===")
	if GameState == null:
		_check(false, "brak GameState")
		get_tree().quit(1)
		return

	# (1) Inny panel juz lapie input -> ekwipunek NIE moze sie otworzyc.
	GameState.ui_capturing_input = true
	var ui := InventoryUI.new()
	add_child(ui)   # _ready buduje panel + _set_open(false)
	ui._set_open(true)
	_check(not _read_open(ui), "ekwipunek otworzyl sie mimo zajetej flagi ui_capturing_input")
	_check(GameState.ui_capturing_input, "guard nie powinien czyscic cudzej flagi ui_capturing_input")

	# (2) Flaga wolna -> otwiera sie i ustawia flage.
	GameState.ui_capturing_input = false
	ui._set_open(true)
	_check(_read_open(ui), "ekwipunek nie otworzyl sie przy wolnej fladze")
	_check(GameState.ui_capturing_input, "otwarty ekwipunek nie ustawil ui_capturing_input")

	# (3) Zamkniecie czysci flage.
	ui._set_open(false)
	_check(not _read_open(ui), "ekwipunek nie zamknal sie")
	_check(not GameState.ui_capturing_input, "zamkniecie nie wyczyscilo ui_capturing_input")

	ui.queue_free()
	if _failures == 0:
		print("[INVGUARD] ALL OK")
	else:
		printerr("[INVGUARD] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
