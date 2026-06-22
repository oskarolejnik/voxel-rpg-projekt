class_name SaveData
extends Resource
## SaveData.gd — root zapisu (TDD 2.5 / 8). Hybryda: POSTAC (przenosna) + SWIAT (tylko host).
## Mechanika zapisu: JSON z polem `version` (migracje) zamiast surowego ResourceSaver
## (czytelnosc/wersjonowanie) — patrz SaveManager. (de)serializacja tutaj jest ZRODLEM PRAWDY
## ksztaltu JSON-a; SaveManager tylko czyta/pisze plik i pilnuje wersji.

const SAVE_VERSION: int = 1

@export var version: int = SAVE_VERSION

# --- POSTAC (przenosna miedzy swiatami) ---
@export var char_name: String = ""
@export var class_id: StringName = &""
@export var level: int = 1
@export var xp: int = 0
@export var gold: int = 0
@export var dust: int = 0                             # Pyl Enchantowania
@export var essence: int = 0                          # Esencja Ulepszen
@export var orbs: int = 0                             # Orby Przemiany (respec)
@export var appearance: CharacterAppearance
@export var allocated_passives: Array[StringName] = []
@export var equipped_skills: Array[StringName] = []
@export var skill_augments: Dictionary = {}          # skill_id -> Array[augment_id]
@export var inventory: Array = []                     # Array[ItemInstance zserializowane]
@export var equipment: Dictionary = {}               # Slot -> ItemInstance
@export var pet_id: StringName = &""
@export var pet_stable: Array[StringName] = []        # oswojone "w stajni"

# --- SWIAT (TYLKO host) ---
@export var world_seed: int = 0
@export var world_changes: Dictionary = {}           # chunk_key -> {voxel_edits} (delty od generacji)
@export var discovered_chunks: Array = []
@export var world_entities: Array = []                # trwale encje (NIE dungeonowe)
@export var play_time: float = 0.0


# ============================================================================
#  Serializacja CALEGO save'a do slownika gotowego pod JSON.stringify.
#  Tylko typy JSON-safe (String/float/int/bool/Array/Dictionary). StringName -> String,
#  ItemInstance/CharacterAppearance -> ich to_dict(). To gwarantuje czysty round-trip.
# ============================================================================
func to_dict() -> Dictionary:
	return {
		"version": version,
		# --- postac ---
		"char_name": char_name,
		"class_id": String(class_id),
		"level": level,
		"xp": xp,
		"gold": gold,
		"dust": dust,
		"essence": essence,
		"orbs": orbs,
		"appearance": appearance.to_dict() if appearance != null else null,
		"allocated_passives": allocated_passives.map(func(s: StringName) -> String: return String(s)),
		"equipped_skills": equipped_skills.map(func(s: StringName) -> String: return String(s)),
		"skill_augments": _augments_to_dict(),
		"inventory": inventory.map(func(it) -> Dictionary:
			return (it as ItemInstance).to_dict() if (it is ItemInstance) else it),
		"equipment": _equipment_to_dict(),
		"pet_id": String(pet_id),
		"pet_stable": pet_stable.map(func(s: StringName) -> String: return String(s)),
		# --- swiat ---
		"world_seed": world_seed,
		"world_changes": world_changes,
		"discovered_chunks": discovered_chunks,
		"world_entities": world_entities,
		"play_time": play_time,
	}


static func from_dict(d: Dictionary) -> SaveData:
	var s := SaveData.new()
	s.version = int(d.get("version", SAVE_VERSION))
	# --- postac ---
	s.char_name = String(d.get("char_name", ""))
	s.class_id = StringName(d.get("class_id", ""))
	s.level = int(d.get("level", 1))
	s.xp = int(d.get("xp", 0))
	s.gold = int(d.get("gold", 0))
	s.dust = int(d.get("dust", 0))
	s.essence = int(d.get("essence", 0))
	s.orbs = int(d.get("orbs", 0))
	var ap = d.get("appearance", null)
	if ap is Dictionary:
		s.appearance = CharacterAppearance.from_dict(ap)
	s.allocated_passives = _to_sn_array(d.get("allocated_passives", []))
	s.equipped_skills = _to_sn_array(d.get("equipped_skills", []))
	s.skill_augments = d.get("skill_augments", {})
	var inv: Array = []
	for it in d.get("inventory", []):
		if it is Dictionary:
			inv.append(ItemInstance.from_dict(it))
		else:
			inv.append(it)
	s.inventory = inv
	var eq: Dictionary = {}
	for k in d.get("equipment", {}):
		var v = d["equipment"][k]
		eq[int(k)] = ItemInstance.from_dict(v) if (v is Dictionary) else v
	s.equipment = eq
	s.pet_id = StringName(d.get("pet_id", ""))
	s.pet_stable = _to_sn_array(d.get("pet_stable", []))
	# --- swiat ---
	s.world_seed = int(d.get("world_seed", 0))
	s.world_changes = d.get("world_changes", {})
	s.discovered_chunks = d.get("discovered_chunks", [])
	s.world_entities = d.get("world_entities", [])
	s.play_time = float(d.get("play_time", 0.0))
	return s


func _augments_to_dict() -> Dictionary:
	var out: Dictionary = {}
	for k in skill_augments:
		out[String(k)] = skill_augments[k]
	return out


func _equipment_to_dict() -> Dictionary:
	var out: Dictionary = {}
	for slot in equipment:
		var v = equipment[slot]
		# Klucz slotu jako STRING (JSON nie ma kluczy int); from_dict odtwarza int().
		out[str(int(slot))] = (v as ItemInstance).to_dict() if (v is ItemInstance) else v
	return out


static func _to_sn_array(src) -> Array[StringName]:
	var out: Array[StringName] = []
	for x in src:
		out.append(StringName(x))
	return out
