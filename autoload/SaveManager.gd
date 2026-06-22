extends Node
## SaveManager.gd (autoload) — zapis HYBRYDOWY (TDD 8). JSON z polem `version` (migracje)
## zamiast surowego ResourceSaver (czytelnosc/wersjonowanie).
##
## - Postac: przenosna miedzy swiatami (wyglad, klasa, lvl/xp, waluty, drzewko, ekwipunek, pet).
## - Swiat: TYLKO host (world_seed, world_changes, discovered_chunks, world_entities, play_time).
##
## Etap 0: pelny round-trip POSTACI (save -> load -> identyczne) + analogiczny zapis SWIATA.
## SaveData.to_dict()/from_dict() jest zrodlem prawdy ksztaltu; tu obslugujemy plik + wersje.
##
## UWAGA (latentne, Etap 2/7): JSON.parse_string przepuszcza inty przez double — seedy > 2^53
## (ItemInstance.seed, world_seed) zaokraglilyby sie. Etap 0 jest bezpieczny (seedy <= 32-bit).

const SAVE_DIR: String = "user://saves"
const CHAR_PATH: String = "user://saves/character.json"
const WORLD_PATH: String = "user://saves/world.json"

signal save_completed(path: String)
signal load_completed(path: String)


func _ready() -> void:
	_ensure_dir()


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


# ============================================================================
#  POSTAC
# ============================================================================

## Zapisuje POSTAC z SaveData do JSON. Zwraca true przy sukcesie.
func save_character(data: SaveData, path: String = CHAR_PATH) -> bool:
	return _write_json(path, _character_dict(data))


## Wczytuje POSTAC. Zwraca SaveData albo null gdy brak/blad pliku.
func load_character(path: String = CHAR_PATH) -> SaveData:
	var d := _read_json(path)
	if d.is_empty():
		return null
	d = _migrate(d)
	return SaveData.from_dict(d)


# ============================================================================
#  SWIAT (tylko host)
# ============================================================================

func save_world(data: SaveData, path: String = WORLD_PATH) -> bool:
	if not NetManager.is_host():
		push_warning("SaveManager.save_world: tylko host zapisuje swiat — pomijam.")
		return false
	return _write_json(path, _world_dict(data))


func load_world(path: String = WORLD_PATH) -> SaveData:
	var d := _read_json(path)
	if d.is_empty():
		return null
	d = _migrate(d)
	return SaveData.from_dict(d)


# ============================================================================
#  Wewnetrzne: wybor pol postac/swiat, IO, migracje
# ============================================================================

## Pelny dict z SaveData, ale TYLKO pola postaci (+ version). Swiat pomijamy (przenosnosc postaci).
func _character_dict(data: SaveData) -> Dictionary:
	var full := data.to_dict()
	for world_key in ["world_seed", "world_changes", "discovered_chunks", "world_entities", "play_time"]:
		full.erase(world_key)
	return full


## Pelny dict z SaveData (postac + swiat) — host trzyma komplet.
func _world_dict(data: SaveData) -> Dictionary:
	return data.to_dict()


func _write_json(path: String, dict: Dictionary) -> bool:
	_ensure_dir()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: nie moge otworzyc do zapisu: %s (err %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(dict, "\t"))
	f.close()
	save_completed.emit(path)
	return true


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SaveManager: nie moge otworzyc do odczytu: %s" % path)
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		push_error("SaveManager: niepoprawny JSON w %s" % path)
		return {}
	load_completed.emit(path)
	return parsed


## Migracje wg pola `version`. Etap 0: jedna wersja, wiec no-op (miejsce na kroki w przyszlosci).
## Straznik gornej granicy: save z wyzsza wersja niz obslugiwana (np. po downgrade gry) moze
## miec pola, ktorych from_dict nie zna -> ostrzegamy, by cicha utrata byla widoczna.
func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	if v > SaveData.SAVE_VERSION:
		push_warning("SaveManager: save nowszy (v%d) niz obslugiwany (v%d) — moga zniknac nieznane pola." % [v, SaveData.SAVE_VERSION])
	# while v < SaveData.SAVE_VERSION: ... (kroki migracji) ; v += 1
	d["version"] = max(v, 1)
	return d
