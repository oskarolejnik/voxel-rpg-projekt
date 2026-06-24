extends Node
## CreatorUITest.gd — HEADLESS smoke test ekranu kreatora (Krok 4): UI buduje się z ContentDB i
## "Stwórz" produkuje poprawną CharacterDefinition (sygnał character_created).
## Uruchomienie: godot --headless res://test/CreatorUITest.tscn. Print "[CREATORUI] ..." + ALL OK.

const UIScript := preload("res://src/CharacterCreatorUI.gd")

var _failures: int = 0
var _created = null


func _ready() -> void:
	print("[CREATORUI] === smoke test ekranu kreatora start ===")
	await _test()
	if _failures == 0:
		print("[CREATORUI] ALL OK")
	else:
		printerr("[CREATORUI] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[CREATORUI] FAIL: %s" % msg)


func _test() -> void:
	var ui = UIScript.new()
	add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(ui._name_edit != null, "UI nie zbudował pola imienia")
	_check(ui._race_btns.size() == 6, "UI: oczekiwano 6 przycisków ras (jest %d)" % ui._race_btns.size())
	_check(ui._class_btns.size() == 11, "UI: oczekiwano 11 przycisków klas (jest %d)" % ui._class_btns.size())

	ui.character_created.connect(func(d): _created = d)
	ui._on_pick_race(&"sylvani")
	ui._on_pick_class(&"lucznik")
	ui._name_edit.text = "Aelwen"
	ui._on_create()
	_check(_created != null and _created.is_valid(), "Stwórz NIE wyemitował poprawnej definicji")
	_check(_created != null and _created.race_id == &"sylvani" and _created.class_id == &"lucznik" \
		and _created.char_name == "Aelwen", "definicja z UI ma złe dane")
	print("[CREATORUI] (1) UI buduje listy (6 ras/11 klas) + Stwórz -> CharacterDefinition OK")

	# (2) PAYOFF namespace+flow: wybór klasy w kreatorze PROPAGUJE do GameState.class_id (świeży reload
	# zbuduje postać z tą klasą), a wybrana klasa od razu ma niepuste drzewko (SkillDB) — czyli „Nowa gra"
	# da realnie wybraną klasę, nie domyślnego wojownika.
	var gs := get_node_or_null("/root/GameState")
	_check(gs != null, "brak autoloadu GameState")
	if gs != null:
		_check(gs.class_id == &"lucznik", "GameState.class_id != lucznik po Stwórz (jest %s)" % str(gs.class_id))
	var sdb := get_node_or_null("/root/SkillDB")
	if sdb != null:
		var t = sdb.tree(&"lucznik")
		_check(t != null and t.nodes.size() > 0, "wybrana klasa lucznik nie ma niepustego drzewka")
	# (3) ścieżka anulowania kreatora istnieje (Main: powrót do menu bez tworzenia postaci).
	_check(ui.has_signal("cancelled"), "kreator nie ma sygnału cancelled (Wstecz)")
	print("[CREATORUI] (2) wybór klasy -> GameState.class_id + niepuste drzewko + sygnał Wstecz OK")
	ui.queue_free()
	await get_tree().process_frame
