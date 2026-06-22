extends SceneTree
## SeedData.gd — JEDNORAZOWY generator danych seed Etapu 2 (.tres) do res://data/db/.
## Uruchomienie: godot --headless --script res://test/SeedData.gd
##
## Tworzy pule do losowania lootu (LootService) + przyklady itemow/setow/klejnotow wg GDD 6:
##   data/db/affixes/*.tres  — prefiksy/sufiksy (Ostry/Plomienny/.../Witalny/...Zolwia/...)
##   data/db/gems/*.tres     — Rubin/Szafir/Szmaragd/Topaz/Diament/Ametyst/Onyks (klejnoty)
##   data/db/sets/*.tres     — Mur Obroncy / Plomien Pustyni / Lowca Cieni (bonusy 2/4-cz.)
##   data/db/items/*.tres    — kilka itemow startowych (mesh/nazwa/slot/base_modifiers/set_id)
##   data/db/enemies/goblin_loot.tres — LootTableResource przykladowa (zloto + rarity_weights)
##
## ZRODLO PRAWDY danych jest TUTAJ — uruchom ponownie, by przebudowac. ResourceSaver gwarantuje
## poprawny format .tres (zamiast recznego klepania ext_resource/sub_resource).

const AFFIX_DIR := "res://data/db/affixes"
const GEM_DIR := "res://data/db/gems"
const SET_DIR := "res://data/db/sets"
const ITEM_DIR := "res://data/db/items"
const ENEMY_DIR := "res://data/db/enemies"

const S := ItemResource.Slot
const OP := StatModifier.Op


func _init() -> void:
	print("[SEED] === generacja danych Etapu 2 ===")
	_ensure_dirs()
	_make_affixes()
	_make_gems()
	_make_sets()
	_make_items()
	_make_loot_table()
	print("[SEED] DONE")
	quit(0)


func _ensure_dirs() -> void:
	for d in [AFFIX_DIR, GEM_DIR, SET_DIR, ITEM_DIR, ENEMY_DIR]:
		if not DirAccess.dir_exists_absolute(d):
			DirAccess.make_dir_recursive_absolute(d)


func _save(res: Resource, dir: String, fname: String) -> void:
	var path := dir.path_join(fname + ".tres")
	var err := ResourceSaver.save(res, path)
	if err != OK:
		printerr("[SEED] blad zapisu %s: %d" % [path, err])
	else:
		print("[SEED] + %s" % path)


# ---------------------------------------------------------------------------
#  AFIKSY (prefiks=ofensywa, sufiks=utility/defensywa) — GDD 6.4
# ---------------------------------------------------------------------------
func _affix(id: StringName, kind: int, stat: StringName, op: int, vmin: float, vmax: float,
		tags: Array, slots: Array, ilvl_min: int = 1, biomes: Array = [], weight: float = 1.0) -> void:
	var a := AffixResource.new()
	a.id = id
	a.kind = kind
	a.stat = stat
	a.op = op
	a.value_min = vmin
	a.value_max = vmax
	var tg: Array[StringName] = []
	for t in tags: tg.append(StringName(t))
	a.tags = tg
	var sl: Array[int] = []
	for s in slots: sl.append(int(s))
	a.allowed_slots = sl
	a.ilvl_min = ilvl_min
	var bm: Array[StringName] = []
	for b in biomes: bm.append(StringName(b))
	a.biomes = bm
	a.weight = weight
	_save(a, AFFIX_DIR, String(id))


func _make_affixes() -> void:
	var WEAPON := [S.WEAPON]
	var ARMOR := [S.HELM, S.CHEST, S.LEGS, S.BOOTS]
	var ANY := [S.WEAPON, S.HELM, S.CHEST, S.LEGS, S.BOOTS, S.TRINKET]
	var TRINK := [S.TRINKET]

	# --- PREFIKSY (ofensywa) ---
	_affix(&"sharp", AffixResource.Kind.PREFIX, &"damage", OP.INCREASED, 0.08, 0.20, ["phys"], WEAPON, 1, [], 1.4)
	_affix(&"flaming", AffixResource.Kind.PREFIX, &"fire_damage", OP.FLAT, 4.0, 12.0, ["fire"], WEAPON, 1, ["emberwaste"], 1.2)
	_affix(&"icy", AffixResource.Kind.PREFIX, &"frost_damage", OP.FLAT, 3.0, 10.0, ["frost"], WEAPON, 3, ["frosthelm"], 1.0)
	_affix(&"venomous", AffixResource.Kind.PREFIX, &"poison_damage", OP.FLAT, 2.0, 8.0, ["poison"], WEAPON, 1, ["verdant"], 1.0)
	_affix(&"stormy", AffixResource.Kind.PREFIX, &"lightning_damage", OP.FLAT, 3.0, 11.0, ["lightning"], WEAPON, 3, ["frosthelm"], 0.9)
	_affix(&"precise", AffixResource.Kind.PREFIX, &"crit_chance", OP.FLAT, 0.02, 0.06, ["crit"], ANY, 1, [], 1.0)
	_affix(&"merciless", AffixResource.Kind.PREFIX, &"crit_damage", OP.INCREASED, 0.10, 0.25, ["crit"], ANY, 3, [], 0.9)
	_affix(&"vampiric", AffixResource.Kind.PREFIX, &"lifesteal", OP.FLAT, 0.02, 0.06, ["leech"], WEAPON, 5, [], 0.7)
	_affix(&"massive", AffixResource.Kind.PREFIX, &"area_radius", OP.INCREASED, 0.05, 0.15, ["aoe"], WEAPON, 1, [], 0.9)
	_affix(&"swift", AffixResource.Kind.PREFIX, &"attack_speed", OP.INCREASED, 0.05, 0.12, ["speed"], WEAPON, 1, [], 1.1)
	_affix(&"armored", AffixResource.Kind.PREFIX, &"armor", OP.FLAT, 6.0, 18.0, ["defense"], ARMOR, 1, [], 1.3)
	_affix(&"vital", AffixResource.Kind.PREFIX, &"max_hp", OP.FLAT, 20.0, 60.0, ["defense"], ARMOR, 1, [], 1.3)

	# --- SUFIKSY (utility/defensywa) ---
	_affix(&"of_bear", AffixResource.Kind.SUFFIX, &"max_hp", OP.INCREASED, 0.04, 0.10, ["defense"], ARMOR, 1, [], 1.2)
	_affix(&"of_turtle", AffixResource.Kind.SUFFIX, &"armor", OP.INCREASED, 0.05, 0.12, ["defense"], ARMOR, 1, [], 1.1)
	_affix(&"of_cheetah", AffixResource.Kind.SUFFIX, &"move_speed", OP.INCREASED, 0.03, 0.08, ["speed"], [S.BOOTS, S.TRINKET], 1, ["verdant"], 1.0)
	_affix(&"of_shadow", AffixResource.Kind.SUFFIX, &"dodge_iframes", OP.FLAT, 0.02, 0.06, ["mobility"], [S.BOOTS, S.TRINKET], 3, ["frosthelm"], 0.8)
	_affix(&"of_endurance", AffixResource.Kind.SUFFIX, &"stamina_regen", OP.FLAT, 3.0, 9.0, ["utility"], ARMOR, 1, ["emberwaste"], 1.0)
	_affix(&"of_mage", AffixResource.Kind.SUFFIX, &"cdr", OP.INCREASED, 0.03, 0.08, ["utility"], [S.HELM, S.TRINKET], 3, ["frosthelm"], 0.9)
	_affix(&"of_regen", AffixResource.Kind.SUFFIX, &"hp_regen", OP.FLAT, 1.0, 4.0, ["heal"], ARMOR, 1, [], 1.0)
	_affix(&"of_greed", AffixResource.Kind.SUFFIX, &"magic_find", OP.FLAT, 0.03, 0.10, ["utility"], TRINK, 1, [], 0.7)
	_affix(&"of_beastmaster", AffixResource.Kind.SUFFIX, &"pet_damage", OP.INCREASED, 0.05, 0.15, ["pet"], TRINK, 5, [], 0.6)


# ---------------------------------------------------------------------------
#  KLEJNOTY — GDD 6.5
# ---------------------------------------------------------------------------
func _gem(id: StringName, name: String, quality: int, mods: Array) -> void:
	var g := GemResource.new()
	g.id = id
	g.display_name = name
	g.quality = quality
	var arr: Array[StatModifier] = []
	for m in mods: arr.append(m)
	g.modifiers = arr
	_save(g, GEM_DIR, String(id))


func _make_gems() -> void:
	# Jakosc 1 (Skaza) — startowe; staty skromne. Stackowanie 10->1 (GDD) poza zakresem Etapu 2.
	_gem(&"ruby_1", "Rubin (Skaza)", 1, [StatModifier.make(&"fire_damage", OP.FLAT, 4.0, [&"fire"], &"gem", &"ruby_1")])
	_gem(&"sapphire_1", "Szafir (Skaza)", 1, [StatModifier.make(&"cdr", OP.INCREASED, 0.04, [&"utility"], &"gem", &"sapphire_1")])
	_gem(&"emerald_1", "Szmaragd (Skaza)", 1, [StatModifier.make(&"crit_chance", OP.FLAT, 0.03, [&"crit"], &"gem", &"emerald_1")])
	_gem(&"topaz_1", "Topaz (Skaza)", 1, [StatModifier.make(&"lightning_damage", OP.FLAT, 5.0, [&"lightning"], &"gem", &"topaz_1")])
	_gem(&"diamond_1", "Diament (Skaza)", 1, [StatModifier.make(&"armor", OP.FLAT, 8.0, [&"defense"], &"gem", &"diamond_1")])
	_gem(&"amethyst_1", "Ametyst (Skaza)", 1, [StatModifier.make(&"lifesteal", OP.FLAT, 0.03, [&"leech"], &"gem", &"amethyst_1")])
	_gem(&"onyx_1", "Onyks (Skaza)", 1, [StatModifier.make(&"magic_find", OP.FLAT, 0.05, [&"utility"], &"gem", &"onyx_1")])


# ---------------------------------------------------------------------------
#  SETY — GDD 6.5 (bonusy 2/4-cz.)
# ---------------------------------------------------------------------------
func _make_set(id: StringName, name: String, fixed: Array, bonuses: Dictionary) -> void:
	var s := SetResource.new()
	s.id = id
	s.display_name = name
	var fx: Array[StatModifier] = []
	for m in fixed: fx.append(m)
	s.fixed_modifiers = fx
	s.bonuses = bonuses
	_save(s, SET_DIR, String(id))


func _make_sets() -> void:
	# Mur Obroncy (Wojownik): 2cz +20% armor (INCREASED) -> 4cz x20% max_hp (MORE).
	_make_set(&"wall_defender", "Mur Obroncy",
		[StatModifier.make(&"armor", OP.FLAT, 6.0, [&"set", &"defense"], &"set", &"wall_defender")],
		{
			2: [StatModifier.make(&"armor", OP.INCREASED, 0.20, [&"set"], &"set", &"wall_defender")],
			4: [StatModifier.make(&"max_hp", OP.MORE, 0.20, [&"set"], &"set", &"wall_defender")],
		})
	# Plomien Pustyni (Mag): 2cz +15% fire -> 4cz x25% fire (MORE).
	_make_set(&"desert_flame", "Plomien Pustyni",
		[StatModifier.make(&"fire_damage", OP.FLAT, 5.0, [&"set", &"fire"], &"set", &"desert_flame")],
		{
			2: [StatModifier.make(&"fire_damage", OP.INCREASED, 0.15, [&"set", &"fire"], &"set", &"desert_flame")],
			4: [StatModifier.make(&"fire_damage", OP.MORE, 0.25, [&"set", &"fire"], &"set", &"desert_flame")],
		})
	# Lowca Cieni (Ranger): 2cz +8% crit_chance -> 4cz +100% crit_damage (INCREASED, mocne).
	_make_set(&"shadow_hunter", "Lowca Cieni",
		[StatModifier.make(&"crit_chance", OP.FLAT, 0.03, [&"set", &"crit"], &"set", &"shadow_hunter")],
		{
			2: [StatModifier.make(&"crit_chance", OP.FLAT, 0.08, [&"set", &"crit"], &"set", &"shadow_hunter")],
			4: [StatModifier.make(&"crit_damage", OP.INCREASED, 1.00, [&"set", &"crit"], &"set", &"shadow_hunter")],
		})


# ---------------------------------------------------------------------------
#  ITEMY startowe — GDD 6.6 (definicje; instancje losuje LootService)
# ---------------------------------------------------------------------------
func _item(id: StringName, name: String, slot: int, weapon_class: StringName, base_mods: Array,
		max_sockets: int = 0, set_id: StringName = &"", req_level: int = 1) -> void:
	var it := ItemResource.new()
	it.id = id
	it.display_name = name
	it.slot = slot
	it.weapon_class = weapon_class
	var bm: Array[StatModifier] = []
	for m in base_mods: bm.append(m)
	it.base_modifiers = bm
	it.max_sockets = max_sockets
	it.set_id = set_id
	it.req_level = req_level
	_save(it, ITEM_DIR, String(id))


func _make_items() -> void:
	# Wojownik
	_item(&"hardened_axe", "Hartowany Topor", S.WEAPON, &"axe2h",
		[StatModifier.make(&"damage", OP.FLAT, 30.0, [&"phys"], &"gear", &"hardened_axe")], 0)
	_item(&"guardian_chest", "Napiersnik Straznika", S.CHEST, &"",
		[StatModifier.make(&"armor", OP.FLAT, 16.0, [&"defense"], &"gear", &"guardian_chest")], 1, &"wall_defender")
	_item(&"endurance_boots", "Buty Wytrwalosci", S.BOOTS, &"",
		[StatModifier.make(&"stamina_regen", OP.FLAT, 4.0, [&"utility"], &"gear", &"endurance_boots")], 1)
	# Mag
	_item(&"spark_wand", "Rozdzka Iskry", S.WEAPON, &"wand",
		[StatModifier.make(&"fire_damage", OP.FLAT, 8.0, [&"fire"], &"gear", &"spark_wand")], 0, &"desert_flame")
	_item(&"adept_hood", "Kaptur Adepta", S.HELM, &"",
		[StatModifier.make(&"cdr", OP.INCREASED, 0.06, [&"utility"], &"gear", &"adept_hood")], 1)
	# Ranger
	_item(&"yew_bow", "Luk Cisowy", S.WEAPON, &"bow",
		[StatModifier.make(&"crit_chance", OP.FLAT, 0.06, [&"crit"], &"gear", &"yew_bow")], 0, &"shadow_hunter")
	_item(&"scout_jacket", "Kurtka Zwiadowcy", S.CHEST, &"",
		[StatModifier.make(&"max_hp", OP.INCREASED, 0.08, [&"defense"], &"gear", &"scout_jacket")], 1)
	_item(&"hunter_ring", "Pierscien Lowcy", S.TRINKET, &"",
		[StatModifier.make(&"magic_find", OP.FLAT, 0.08, [&"utility"], &"gear", &"hunter_ring")], 0)


# ---------------------------------------------------------------------------
#  TABLICA LOOTU przykladowa (goblin) — zloto + wagi rzadkosci
# ---------------------------------------------------------------------------
func _make_loot_table() -> void:
	var t := LootTableResource.new()
	t.gold_min = 3
	t.gold_max = 15
	# Rarity -> waga (Rarity int jako klucz). Goblin: glownie pospolite/niezwykle, rzadko wyzej.
	t.rarity_weights = {
		ItemResource.Rarity.COMMON: 55.0,
		ItemResource.Rarity.UNCOMMON: 30.0,
		ItemResource.Rarity.RARE: 12.0,
		ItemResource.Rarity.EPIC: 2.5,
		ItemResource.Rarity.LEGENDARY: 0.5,
	}
	# LootTableResource nie ma pola `id` -> ItemDB go nie zindeksuje (i dobrze: to nie item).
	# Trzymamy plik dla EnemyResource.loot_table (przypisanie w inspektorze/Etap 4).
	_save(t, ENEMY_DIR, "goblin_loot")
