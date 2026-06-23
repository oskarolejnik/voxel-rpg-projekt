extends Node
## ContentDB.gd (autoload) — rejestr treści DATA-DRIVEN (GDD sek.8). Seeduje KANON z kodu (6 ras,
## 11 klas, pochodzenia wg GDD), a następnie SKANUJE res://data/content/{races,classes,origins}/*.tres,
## by DODAĆ/NADPISAĆ treść plikami danych (rozszerzalność bez zmian w kodzie — wystarczy wrzucić .tres).
## Bezpieczny gdy katalogów brak (zostaje sam seed). Udostępnia listy + lookup do kreatora postaci.

const DIR_RACES := "res://data/content/races"
const DIR_CLASSES := "res://data/content/classes"
const DIR_ORIGINS := "res://data/content/origins"

var _races: Dictionary = {}     # StringName id -> RaceResource
var _classes: Dictionary = {}   # StringName id -> ClassResource
var _origins: Dictionary = {}   # StringName id -> OriginResource


func _ready() -> void:
	reload()


func reload() -> void:
	_races.clear(); _classes.clear(); _origins.clear()
	_seed()
	_scan(DIR_RACES, _races)
	_scan(DIR_CLASSES, _classes)
	_scan(DIR_ORIGINS, _origins)


# ============================================================================
#  API (woła kreator postaci)
# ============================================================================
func races() -> Array: return _races.values()
func classes() -> Array: return _classes.values()
func origins() -> Array: return _origins.values()
func race_ids() -> Array: return _races.keys()
func class_ids() -> Array: return _classes.keys()
func origin_ids() -> Array: return _origins.keys()
func get_race(id: StringName) -> RaceResource: return _races.get(id, null)
func class_by_id(id: StringName) -> ClassResource: return _classes.get(id, null)   # nazwa != Object.get_class()
func get_origin(id: StringName) -> OriginResource: return _origins.get(id, null)
func has_race(id: StringName) -> bool: return _races.has(id)
func has_class(id: StringName) -> bool: return _classes.has(id)


# ============================================================================
#  SKAN .tres (dodaje/nadpisuje seed) — punkt rozszerzalności data-driven
# ============================================================================
func _scan(dir_path: String, into: Dictionary) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return   # katalog nie istnieje -> zostaje sam seed (bezpieczne)
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and (f.ends_with(".tres") or f.ends_with(".res")):
			var res = load(dir_path.path_join(f))
			if res != null and res.get("id") != null and StringName(res.get("id")) != &"":
				into[StringName(res.get("id"))] = res
		f = d.get_next()
	d.list_dir_end()


# ============================================================================
#  SEED KANONU (GDD sek.3/4/1)
# ============================================================================
func _mk_race(id: StringName, nm: String, lore: String, biome: StringName, bonus: Dictionary,
		passive: String, roles: Array, pre: Array, suf: Array) -> void:
	var r := RaceResource.new()
	r.id = id; r.display_name = nm; r.lore = lore; r.biome = biome
	r.stat_bonus = bonus; r.passive = passive
	r.preferred_roles = PackedStringArray(roles)
	r.name_prefix = PackedStringArray(pre); r.name_suffix = PackedStringArray(suf)
	_races[id] = r

func _mk_class(id: StringName, nm: String, role: StringName, res_kind: StringName, primary: StringName,
		armor: StringName, weapons: Array, base: Dictionary, hints: Array) -> void:
	var c := ClassResource.new()
	c.id = id; c.display_name = nm; c.role = role; c.resource_kind = res_kind
	c.primary_stat = primary; c.armor_weight = armor
	c.weapons = PackedStringArray(weapons); c.base_stats = base
	c.skill_hints = PackedStringArray(hints)
	_classes[id] = c

func _mk_origin(id: StringName, nm: String, lore: String, bonus: Dictionary, biome: StringName, items: Array) -> void:
	var o := OriginResource.new()
	o.id = id; o.display_name = nm; o.lore = lore; o.stat_bonus = bonus
	o.start_biome = biome; o.start_items = PackedStringArray(items)
	_origins[id] = o

func _seed() -> void:
	# --- 6 RAS (GDD sek.3) ---
	_mk_race(&"duryjczycy", "Duryjczycy", "Ludzie z centralnych królestw Duralanii; wszechstronni.",
		&"", {"all": 1}, "Adaptacja: szybszy przyrost biegłości.", ["tank", "melee_dps", "support"],
		["Dur", "Ald", "Ren", "Mar", "Hel"], ["an", "ric", "win", "ek", "ia"])
	_mk_race(&"sylvani", "Sylvani", "Leśny lud z Verdant Hollow; zwinni, długowieczni, więź z naturą.",
		&"verdant", {"dex": 2, "int": 1}, "Lekkostopość: cisza ruchu, bonus do łuku/natury.",
		["ranged_dps", "healer"], ["Syl", "Ael", "Thi", "Lor", "Nae"], ["wen", "riel", "las", "thil", "a"])
	_mk_race(&"grimhold", "Karłowie z Grimholdu", "Krasnoludy z Frosthelm Peaks; wytrzymali kowale i górnicy.",
		&"frosthelm", {"str": 1, "vit": 2, "armor": 0.05}, "Twardziel: odporność, bonus do pancerza.",
		["tank", "melee_dps"], ["Bro", "Dur", "Thra", "Gri", "Kazd"], ["din", "grim", "bek", "nor", "il"])
	_mk_race(&"embrani", "Embrani", "Lud naznaczony ogniem z Emberwaste; ognista krew, temperament.",
		&"emberwaste", {"int": 2, "fire_res": 0.1}, "Żar w żyłach: odporność na ogień, bonus do magii.",
		["ranged_dps", "melee_dps"], ["Pyr", "Em", "Cin", "Ash", "Vael"], ["ros", "ka", "ith", "zar", "en"])
	_mk_race(&"orguni", "Orguni", "Orkowie z koczowniczych klanów; potężni, waleczni, honorowi.",
		&"", {"str": 2, "vit": 1}, "Krew wojownika: bonus do furii i siły uderzenia.",
		["melee_dps", "tank"], ["Gor", "Ruk", "Mok", "Tha", "Urz"], ["nak", "gash", "mok", "ul", "ra"])
	_mk_race(&"feruni", "Feruni", "Lud-zwierzę (beastkin); instynkt, szybkość, tropienie.",
		&"", {"dex": 2, "move": 0.05}, "Instynkt łowcy: szybkość ruchu, tropienie.",
		["ranged_dps", "melee_dps"], ["Fen", "Kar", "Luw", "Rha", "Mio"], ["fang", "paw", "ra", "wir", "ka"])

	# --- 11 KLAS (GDD sek.4) ---
	_mk_class(&"wojownik", "Wojownik", &"tank", &"rage", &"str", &"heavy",
		["miecz", "tarcza"], {"hp": 140, "dmg": 16, "armor": 0.25}, ["Tarcza", "Prowokacja", "Roztrzaskanie"])
	_mk_class(&"paladyn", "Paladyn", &"support", &"faith", &"str", &"heavy",
		["młot", "tarcza"], {"hp": 130, "dmg": 15, "armor": 0.22}, ["Święte światło", "Aura", "Pieczęć"])
	_mk_class(&"berserker", "Berserker", &"melee_dps", &"rage", &"str", &"medium",
		["topór dwuręczny"], {"hp": 120, "dmg": 20, "armor": 0.1}, ["Szał", "Wir Ostrzy", "Rozłup"])
	_mk_class(&"lucznik", "Łucznik", &"ranged_dps", &"focus", &"dex", &"light",
		["łuk"], {"hp": 95, "dmg": 18, "armor": 0.05}, ["Celny strzał", "Deszcz strzał", "Pułapka"])
	_mk_class(&"lotrzyk", "Łotrzyk", &"melee_dps", &"combo", &"dex", &"light",
		["sztylety"], {"hp": 90, "dmg": 17, "armor": 0.05}, ["Pchnięcie", "Cienie", "Trucizna"])
	_mk_class(&"zabojca", "Zabójca", &"melee_dps", &"combo", &"dex", &"light",
		["sztylet"], {"hp": 88, "dmg": 19, "armor": 0.05}, ["Skrytobójstwo", "Mgła", "Garota"])
	_mk_class(&"mag", "Mag", &"ranged_dps", &"mana", &"int", &"light",
		["różdżka"], {"hp": 80, "dmg": 22, "armor": 0.0}, ["Ognista kula", "Lodowy grot", "Mżenie"])
	_mk_class(&"nekromanta", "Nekromanta", &"ranged_dps", &"essence", &"int", &"light",
		["kostur"], {"hp": 85, "dmg": 18, "armor": 0.0}, ["Wskrzeszenie", "Klątwa", "Pocisk kości"])
	_mk_class(&"kaplan", "Kapłan", &"healer", &"faith", &"wis", &"light",
		["buława"], {"hp": 95, "dmg": 12, "armor": 0.05}, ["Leczenie", "Modlitwa", "Kara"])
	_mk_class(&"druid", "Druid", &"healer", &"nature", &"wis", &"medium",
		["kostur"], {"hp": 100, "dmg": 14, "armor": 0.1}, ["Odrost", "Cierniste pnącze", "Postać zwierzęca"])
	_mk_class(&"mnich", "Mnich", &"melee_dps", &"chi", &"dex", &"medium",
		["pięści"], {"hp": 105, "dmg": 16, "armor": 0.1}, ["Seria ciosów", "Fala chi", "Medytacja"])

	# --- POCHODZENIA (GDD sek.1) ---
	_mk_origin(&"wedrowiec", "Wędrowiec", "Wieczny podróżnik; zna szlaki.", {"move": 0.03}, &"", [])
	_mk_origin(&"zolnierz", "Żołnierz", "Wyszkolony w boju z regularnych szeregów.", {"vit": 1}, &"", ["healing_potion"])
	_mk_origin(&"uczony", "Uczony", "Adept ksiąg i run.", {"int": 1}, &"", [])
	_mk_origin(&"lowca", "Łowca", "Tropiciel z dzikich ostępów.", {"dex": 1}, &"verdant", [])
	_mk_origin(&"wygnaniec", "Wygnaniec", "Bez domu i pana; zahartowany.", {"vit": 1, "move": 0.02}, &"emberwaste", [])
	_mk_origin(&"rzemieslnik", "Rzemieślnik", "Mistrz kuźni i warsztatu.", {"str": 1}, &"frosthelm", [])
