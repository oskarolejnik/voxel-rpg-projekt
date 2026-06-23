extends Node
## CreatorTest.gd — HEADLESS test kreatora postaci (Krok 3c): nawigacja etapów + walidacja + generator
## imion + finalizacja do CharacterDefinition. Uruchomienie: godot --headless res://test/CreatorTest.tscn
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[CREATOR] ..." + ALL OK + quit.

var _failures: int = 0


func _ready() -> void:
	print("[CREATOR] === test kreatora postaci start ===")
	_test_flow()
	_test_name_generator()
	if _failures == 0:
		print("[CREATOR] ALL OK")
	else:
		printerr("[CREATOR] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[CREATOR] FAIL: %s" % msg)


func _test_flow() -> void:
	var cc := CharacterCreator.new()
	_check(cc.options_races().size() == 6, "kreator nie widzi 6 ras z ContentDB")
	_check(cc.options_classes().size() == 11, "kreator nie widzi 11 klas z ContentDB")

	# Etap RACE: bez rasy NIE można dalej; nieznana rasa odrzucona.
	_check(cc.step == CharacterCreator.Step.RACE, "start nie na etapie RACE")
	_check(not cc.can_advance(), "RACE bez wyboru nie powinno pozwalać dalej")
	_check(not cc.set_race(&"nieistnieje"), "set_race(nieznana) powinno zwrócić false")
	_check(cc.set_race(&"sylvani"), "set_race(sylvani) powinno przejść")
	_check(cc.can_advance() and cc.advance(), "RACE->GENDER nie przeszło")

	# GENDER + ORIGIN opcjonalne (można przejść bez wyboru).
	_check(cc.step == CharacterCreator.Step.GENDER, "nie na GENDER")
	cc.set_gender(&"female")
	_check(cc.advance(), "GENDER->ORIGIN")
	_check(cc.advance(), "ORIGIN->CLASS (opcjonalne, bez wyboru)")

	# CLASS: wymagana.
	_check(cc.step == CharacterCreator.Step.CLASS, "nie na CLASS")
	_check(not cc.can_advance(), "CLASS bez wyboru nie powinno pozwalać dalej")
	_check(cc.set_class(&"lucznik"), "set_class(lucznik)")
	_check(cc.advance(), "CLASS->NAME")

	# NAME: wymagane niepuste.
	_check(not cc.can_advance(), "NAME puste nie powinno pozwalać dalej")
	cc.set_name("Aelwen", "Liściocień")
	_check(cc.advance(), "NAME->SUMMARY")

	# SUMMARY -> finalize: kompletna definicja.
	var d := cc.finalize()
	_check(d != null and d.is_valid(), "finalize() nie zwrócił poprawnej definicji")
	_check(d.race_id == &"sylvani" and d.class_id == &"lucznik" and d.full_name() == "Aelwen Liściocień", "finalize: złe dane")
	_check(cc.step == CharacterCreator.Step.DONE, "po finalize krok != DONE")
	print("[CREATOR] (1) przepływ: RACE->...->SUMMARY->finalize, walidacja etapów OK")


func _test_name_generator() -> void:
	var cc := CharacterCreator.new()
	var a := cc.random_name(&"sylvani", 1234)
	var b := cc.random_name(&"sylvani", 1234)
	_check(a == b, "generator imion NIE deterministyczny dla seed (%s != %s)" % [a, b])
	_check(a.length() >= 3, "wygenerowane imię za krótkie (%s)" % a)
	# Imię = prefiks+sufiks z danych rasy.
	var r := ContentDB.get_race(&"sylvani")
	var ok := false
	for p in r.name_prefix:
		if a.begins_with(String(p)):
			ok = true
			break
	_check(ok, "wygenerowane imię '%s' nie zaczyna się sylabą rasy" % a)
	_check(cc.random_name(&"nieistnieje", 0) == "Bezimienny", "brak rasy -> 'Bezimienny'")
	print("[CREATOR] (2) generator imion: deterministyczny, z sylab rasy (np. '%s') OK" % a)
