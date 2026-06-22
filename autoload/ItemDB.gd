extends Node
## ItemDB.gd (autoload) — rejestr definicji itemow i pokrewnych (TDD 1.3).
## Skanuje res://data/db/items (.tres) -> slowniki po `id`. Etap 0: folder moze byc pusty
## (brak .tres) — skan jest bezpieczny i daje puste rejestry. ItemInstance.base_id -> ItemDB.item(id).

const ITEMS_DIR: String = "res://data/db/items"
const AFFIXES_DIR: String = "res://data/db/affixes"
const SETS_DIR: String = "res://data/db/sets"
const GEMS_DIR: String = "res://data/db/gems"

var items: Dictionary = {}        # StringName -> ItemResource
var affixes: Dictionary = {}      # StringName -> AffixResource
var sets: Dictionary = {}         # StringName -> SetResource
var gems: Dictionary = {}         # StringName -> GemResource


func _ready() -> void:
	reload()


func reload() -> void:
	items = _scan(ITEMS_DIR)
	affixes = _scan(AFFIXES_DIR)
	sets = _scan(SETS_DIR)
	gems = _scan(GEMS_DIR)


func item(id: StringName) -> ItemResource:
	return items.get(id, null)

func affix(id: StringName) -> AffixResource:
	return affixes.get(id, null)

func set_def(id: StringName) -> SetResource:
	return sets.get(id, null)

func gem(id: StringName) -> GemResource:
	return gems.get(id, null)


## Rekurencyjny skan folderu .tres -> slownik po `id`. Bezpieczny dla nieistniejacego folderu.
## Wspoldzielony wzorzec dla wszystkich DB (kopiowany, bo autoloady sa niezalezne).
func _scan(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	_scan_into(dir_path, out)
	return out


func _scan_into(dir_path: String, out: Dictionary) -> void:
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
				_scan_into(dir_path.path_join(file_name), out)
		elif file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var res := load(dir_path.path_join(file_name))
			if res != null and "id" in res and res.id != &"":
				out[StringName(res.id)] = res
		file_name = dir.get_next()
	dir.list_dir_end()
