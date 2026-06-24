extends Node
## SkillDB.gd (autoload) — rejestr skilli i drzewek per klasa (TDD 1.3).
## Skanuje res://data/db/skills i res://data/db/trees (.tres) -> slowniki po `id`/`class_id`.
## Etap 0: foldery moga byc puste — skan bezpieczny.

const SKILLS_DIR: String = "res://data/db/skills"
const TREES_DIR: String = "res://data/db/trees"
const PASSIVES_DIR: String = "res://data/db/passives"
const AUGMENTS_DIR: String = "res://data/db/augments"

var skills: Dictionary = {}       # StringName(id) -> SkillResource
var trees: Dictionary = {}        # StringName(class_id) -> SkillTreeResource
var passives: Dictionary = {}     # StringName(id) -> PassiveNodeResource
var augments: Dictionary = {}     # StringName(id) -> AugmentResource


func _ready() -> void:
	reload()


func reload() -> void:
	skills = _scan(SKILLS_DIR, "id")
	trees = _scan(TREES_DIR, "class_id")
	passives = _scan(PASSIVES_DIR, "id")
	augments = _scan(AUGMENTS_DIR, "id")


func skill(id: StringName) -> SkillResource:
	return skills.get(id, null)

func tree(class_id: StringName) -> SkillTreeResource:
	var t: SkillTreeResource = trees.get(class_id, null)
	if t == null:
		# Brak drzewka == punkty niewydawalne dla tej klasy. Nie ucisz tego po cichu — niech
		# brakujace dane ujawniaja sie w logu (10/11 klas wciaz bez .tres). UWAGA na rozjazd
		# przestrzeni id: SkillDB/trees kluczuja po ANGIELSKICH id (warrior), a ContentDB/kreator
		# po POLSKICH (wojownik) — pytanie o zla przestrzen tez wyladuje tutaj.
		push_warning("[SkillDB] brak drzewka umiejetnosci dla class_id=&\"%s\" (punkty niewydawalne; sprawdz res://data/db/trees i przestrzen id ang/pl)" % class_id)
	return t

func passive(id: StringName) -> PassiveNodeResource:
	return passives.get(id, null)

func augment(id: StringName) -> AugmentResource:
	return augments.get(id, null)


func _scan(dir_path: String, key_field: String) -> Dictionary:
	var out: Dictionary = {}
	_scan_into(dir_path, key_field, out)
	return out


func _scan_into(dir_path: String, key_field: String, out: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	# `file_name`, NIE `name` — uniknij przeslaniania Node.name (autoload extends Node).
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_scan_into(dir_path.path_join(file_name), key_field, out)
		elif file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var res := load(dir_path.path_join(file_name))
			if res != null and key_field in res and res.get(key_field) != &"":
				out[StringName(res.get(key_field))] = res
		file_name = dir.get_next()
	dir.list_dir_end()
