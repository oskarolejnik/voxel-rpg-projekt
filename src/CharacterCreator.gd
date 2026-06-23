class_name CharacterCreator
extends RefCounted
## CharacterCreator.gd — KONTROLER kreatora postaci (GDD sek.1, logika bez UI; UI sek.6 osobno).
## Prowadzi przez etapy rasa→płeć→pochodzenie→klasa→imię→podsumowanie→utworzenie, waliduje przejścia
## i buduje CharacterDefinition z opcji ContentDB. Generator imion korzysta z sylab rasy (GDD sek.5).
## Czysta logika (RefCounted) — łatwa do testów i do podpięcia pod dowolny UI.

enum Step { RACE, GENDER, ORIGIN, CLASS, NAME, SUMMARY, DONE }

var step: Step = Step.RACE
var def: CharacterDefinition = CharacterDefinition.new()

# --- Opcje (z ContentDB) — do listowania w UI ---
func options_races() -> Array: return ContentDB.races()
func options_classes() -> Array: return ContentDB.classes()
func options_origins() -> Array: return ContentDB.origins()

# --- Settery wyborów (walidują względem ContentDB; nieznane id = ignorowane) ---
func set_race(id: StringName) -> bool:
	if ContentDB.has_race(id):
		def.race_id = id
		return true
	return false

func set_gender(g: StringName) -> void:
	def.gender = g   # opcjonalne; dozwolone &"male"/&"female"/&"neutral"

func set_origin(id: StringName) -> bool:
	if ContentDB.get_origin(id) != null:
		def.origin_id = id
		return true
	return false

func set_class(id: StringName) -> bool:
	if ContentDB.has_class(id):
		def.class_id = id
		return true
	return false

func set_name(nm: String, surname: String = "") -> void:
	def.char_name = nm
	def.surname = surname

# --- Generator imienia zależny od rasy (GDD sek.5): prefiks+sufiks z sylab rasy. Deterministyczny dla seed. ---
func random_name(race_id: StringName, seed_val: int = 0) -> String:
	var r := ContentDB.get_race(race_id)
	if r == null or r.name_prefix.is_empty() or r.name_suffix.is_empty():
		return "Bezimienny"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var p: String = r.name_prefix[rng.randi() % r.name_prefix.size()]
	var s: String = r.name_suffix[rng.randi() % r.name_suffix.size()]
	return p + s

# --- Nawigacja etapów ---
## Czy spełnione warunki, by przejść z bieżącego etapu dalej (GDD sek.1: rasa/klasa/imię wymagane).
func can_advance() -> bool:
	match step:
		Step.RACE: return def.race_id != &""
		Step.GENDER: return true            # płeć opcjonalna (można pominąć)
		Step.ORIGIN: return true            # pochodzenie opcjonalne
		Step.CLASS: return def.class_id != &""
		Step.NAME: return def.char_name.strip_edges() != ""
		Step.SUMMARY: return def.is_valid()
		_: return false

func advance() -> bool:
	if not can_advance():
		return false
	if step < Step.DONE:
		step = (step + 1) as Step
	return true

func back() -> void:
	if step > Step.RACE:
		step = (step - 1) as Step

## Zwraca gotową definicję postaci (jeśli kompletna) lub null. Po tym kroku gra tworzy postać z danych.
func finalize() -> CharacterDefinition:
	if def.is_valid():
		step = Step.DONE
		return def
	return null
