extends Node
## ContentDBTest.gd — HEADLESS test warstwy danych (Krok 3a): klasy Resource + rejestr ContentDB +
## CharacterDefinition. Uruchomienie: godot --headless res://test/ContentDBTest.tscn
##  (1) Klasy Resource instancjonują się i trzymają dane.
##  (2) ContentDB (autoload) seeduje kanon: 6 ras + 11 klas + >=4 pochodzenia; lookup po id działa.
##  (3) CharacterDefinition: walidacja (imię+rasa+klasa) + round-trip to_dict/from_dict.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[CONTENT] ..." + ALL OK + quit.

var _failures: int = 0


func _ready() -> void:
	print("[CONTENT] === test warstwy danych (ContentDB + Resource) start ===")
	_test_resource_classes()
	_test_contentdb()
	_test_character_def()
	if _failures == 0:
		print("[CONTENT] ALL OK")
	else:
		printerr("[CONTENT] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[CONTENT] FAIL: %s" % msg)


func _test_resource_classes() -> void:
	var r := RaceResource.new()
	r.id = &"x"; r.display_name = "X"; r.stat_bonus = {"dex": 2}
	_check(r.id == &"x" and int(r.stat_bonus.get("dex", 0)) == 2, "RaceResource nie trzyma danych")
	var c := ClassResource.new()
	c.id = &"y"; c.role = &"tank"; c.base_stats = {"hp": 100}
	_check(c.role == &"tank" and int(c.base_stats.get("hp", 0)) == 100, "ClassResource nie trzyma danych")
	var o := OriginResource.new()
	o.id = &"z"; o.start_biome = &"verdant"
	_check(o.start_biome == &"verdant", "OriginResource nie trzyma danych")
	print("[CONTENT] (1) klasy Resource: Race/Class/Origin trzymają dane OK")


func _test_contentdb() -> void:
	_check(ContentDB != null, "autoload ContentDB nieobecny")
	_check(ContentDB.races().size() == 6, "ContentDB: oczekiwano 6 ras (jest %d)" % ContentDB.races().size())
	_check(ContentDB.classes().size() == 11, "ContentDB: oczekiwano 11 klas (jest %d)" % ContentDB.classes().size())
	_check(ContentDB.origins().size() >= 4, "ContentDB: oczekiwano >=4 pochodzeń (jest %d)" % ContentDB.origins().size())

	var syl := ContentDB.get_race(&"sylvani")
	_check(syl != null and syl.display_name == "Sylvani", "lookup rasy sylvani błędny")
	var mag := ContentDB.class_by_id(&"mag")
	_check(mag != null and mag.role == &"ranged_dps" and mag.resource_kind == &"mana", "lookup klasy mag błędny")
	var wojo := ContentDB.class_by_id(&"wojownik")
	_check(wojo != null and wojo.role == &"tank" and int(wojo.base_stats.get("hp", 0)) > 0, "lookup klasy wojownik błędny")
	_check(ContentDB.has_class(&"berserker"), "has_class(berserker) == false")
	_check(ContentDB.class_by_id(&"nieistnieje") == null, "nieznana klasa powinna dać null")
	print("[CONTENT] (2) ContentDB: 6 ras + 11 klas + %d pochodzeń, lookup OK" % ContentDB.origins().size())


func _test_character_def() -> void:
	var c := CharacterDefinition.new()
	_check(not c.is_valid(), "pusta definicja NIE powinna być valid")
	c.char_name = "Thalion"; c.surname = "Liściocień"; c.race_id = &"sylvani"; c.class_id = &"lucznik"
	_check(c.is_valid(), "kompletna definicja POWINNA być valid")
	_check(c.full_name() == "Thalion Liściocień", "full_name błędne (%s)" % c.full_name())
	var d := c.to_dict()
	var c2 := CharacterDefinition.from_dict(d)
	_check(c2.char_name == "Thalion" and c2.race_id == &"sylvani" and c2.class_id == &"lucznik" \
		and c2.schema_version == 1, "round-trip to_dict/from_dict błędny")
	print("[CONTENT] (3) CharacterDefinition: walidacja + round-trip OK")
