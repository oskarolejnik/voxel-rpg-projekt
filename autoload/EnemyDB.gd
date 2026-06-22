extends Node
## EnemyDB.gd (autoload) — rejestr wrogow i biomow (TDD 1.3).
## Skanuje res://data/db/enemies i res://data/db/biomes (.tres) -> slowniki po `id`.
## Etap 0: foldery moga byc puste — skan bezpieczny. biome(id) zwraca BiomeResource
## (uzywane np. przez DungeonEntrance.entrance_chance w Etapie 5).

const ENEMIES_DIR: String = "res://data/db/enemies"
const BIOMES_DIR: String = "res://data/db/biomes"

var enemies: Dictionary = {}      # StringName -> EnemyResource
var biomes: Dictionary = {}       # StringName -> BiomeResource


func _ready() -> void:
	reload()


func reload() -> void:
	enemies = _scan(ENEMIES_DIR)
	biomes = _scan(BIOMES_DIR)


func enemy(id: StringName) -> EnemyResource:
	return enemies.get(id, null)


func biome(id: StringName) -> BiomeResource:
	return biomes.get(id, null)


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
