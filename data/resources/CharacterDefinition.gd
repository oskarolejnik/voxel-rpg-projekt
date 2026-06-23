class_name CharacterDefinition
extends Resource
## CharacterDefinition.gd — AGREGAT wyborów z kreatora (GDD sek.8). Spina rasę/płeć/pochodzenie/klasę/
## imię/wygląd przez ID (lekkie referencje, odporne na rebalans). Serializowalny (zapis postaci, sek.9).

@export var char_name: String = ""
@export var surname: String = ""
@export var title: String = ""
@export var race_id: StringName = &""
@export var gender: StringName = &"neutral"         # &"male"/&"female"/&"neutral"
@export var origin_id: StringName = &""
@export var class_id: StringName = &""
@export var appearance: CharacterAppearance = null  # wygląd (istniejący CharacterAppearance)
@export var schema_version: int = 1

## Minimalna walidacja przed utworzeniem postaci (GDD sek.1 etap 8): imię + rasa + klasa wymagane.
func is_valid() -> bool:
	return char_name.strip_edges() != "" and race_id != &"" and class_id != &""

func full_name() -> String:
	var n := char_name.strip_edges()
	if surname.strip_edges() != "":
		n += " " + surname.strip_edges()
	return n

func to_dict() -> Dictionary:
	return {
		"char_name": char_name, "surname": surname, "title": title,
		"race_id": String(race_id), "gender": String(gender),
		"origin_id": String(origin_id), "class_id": String(class_id),
		"appearance": appearance.to_dict() if appearance != null else {},
		"schema_version": schema_version,
	}

static func from_dict(d: Dictionary) -> CharacterDefinition:
	var c := CharacterDefinition.new()
	c.char_name = String(d.get("char_name", ""))
	c.surname = String(d.get("surname", ""))
	c.title = String(d.get("title", ""))
	c.race_id = StringName(d.get("race_id", ""))
	c.gender = StringName(d.get("gender", "neutral"))
	c.origin_id = StringName(d.get("origin_id", ""))
	c.class_id = StringName(d.get("class_id", ""))
	c.schema_version = int(d.get("schema_version", 1))
	return c
