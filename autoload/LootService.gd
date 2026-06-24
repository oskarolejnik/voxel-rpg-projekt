extends Node
## LootService.gd (autoload) — generator dropow (TDD 1.3 / 2.4 / 6.2). HOST-ONLY, DETERMINISTYCZNY.
##
## DWA wejscia:
##   roll_item(seed, ilvl, biome, tier, slot) -> ItemInstance — deterministyczne losowanie
##       afiksow/socketow/enchantu/setu. TEN SAM seed -> TEN SAM item (DoD Etapu 2).
##   drop_for(enemy) -> Array[Dictionary] — czy/co dropi wrog (LootTableResource): itemy + zloto.
##
## DETERMINIZM (TDD 6.2): kazdy item ma WLASNY seed (rng.randi() ze strumienia RNGService.loot
## w momencie dropu). Z tego seeda budujemy LOKALNY RandomNumberGenerator i z niego losujemy
## WSZYSTKO dla tego itemu — wiec odtworzenie afiksow u klienta (sam seed + ilvl + rarity + slot +
## biome) daje identyczny wynik, niezaleznie od kolejnosci innych pobran. Globalny strumien
## RNGService.loot uzywamy WYLACZNIE do wyboru "co spadnie" (rarity/ile itemow/seed), po stronie
## autorytetu (NetManager.has_authority/is_host). Klient NIGDY nie woła roll na strumieniu — dostaje
## ItemInstance (seed+tier+ilvl) i odtwarza staty lokalnie przez to samo roll_item.
##
## Wartosc afiksu (GDD 6.4): value = lerp(min,max,roll) * TIER_MULT[tier] * ilvl_scale(ilvl),
## gdzie ilvl_scale = 1 + (ilvl-1)*0.04. Item nigdy nie dostaje dwoch afiksow tej samej `stat`.

## Mnoznik tieru (GDD 6.2). Indeksy = ItemResource.Rarity (COMMON..SET).
const TIER_MULT: Array[float] = [0.7, 0.85, 1.0, 1.15, 1.25, 1.0]

## Liczba afiksow per tier (GDD 6.2). SET ma 2 stale + losowane do tej liczby (tu traktujemy
## jako gorny limit losowanych poza fixed_modifiers).
const AFFIX_COUNT: Array[int] = [1, 2, 3, 4, 4, 3]

## Sockety per tier: Vector2i(min,max) (GDD 6.2). COMMON 0; UNCOMMON 0-1; RARE 1; EPIC 1-2;
## LEGENDARY 2; SET 1.
const SOCKETS_BY_TIER: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(1, 1),
]

## Enchant od RARE w gore (GDD 6.2): RARE/EPIC/LEGENDARY/SET maja slot enchantu.
const ENCHANT_FROM_RARITY: int = 2   # ItemResource.Rarity.RARE

## Domyslne wagi rarity, gdy LootTableResource ich nie poda (driver mocy = liczba afiksow).
## Indeksy = Rarity. Suma niewazna (normalizujemy). Trash czesty, legenda rzadka.
const DEFAULT_RARITY_WEIGHTS: Array[float] = [50.0, 30.0, 14.0, 5.0, 1.0, 0.0]

## Kolory rzadkosci (GDD 6.2) — wspoldzielone przez LootDrop (wizual) i UI/toast.
const RARITY_COLORS: Array[Color] = [
	Color(0.62, 0.62, 0.62),   # COMMON  — szary
	Color(0.36, 0.80, 0.36),   # UNCOMMON— zielony
	Color(0.30, 0.55, 0.95),   # RARE    — niebieski
	Color(0.66, 0.38, 0.92),   # EPIC    — fioletowy
	Color(0.96, 0.58, 0.16),   # LEGENDARY— pomaranczowy
	Color(0.20, 0.82, 0.78),   # SET     — turkus
]

const RARITY_NAMES: Array[String] = [
	"Pospolity", "Niezwykly", "Rzadki", "Epicki", "Legendarny", "Set",
]


# ============================================================================
#  PUBLICZNE API
# ============================================================================

## Statyczny pomocnik: kolor wg rarity (bezpieczny dla zakresu). Uzywany przez LootDrop/UI/toast.
static func rarity_color(rarity: int) -> Color:
	if rarity >= 0 and rarity < RARITY_COLORS.size():
		return RARITY_COLORS[rarity]
	return Color.WHITE


static func rarity_name(rarity: int) -> String:
	if rarity >= 0 and rarity < RARITY_NAMES.size():
		return RARITY_NAMES[rarity]
	return "?"


## Skalowanie wartosci afiksu wg ilvl (GDD 6.4).
static func ilvl_scale(ilvl: int) -> float:
	return 1.0 + float(maxi(1, ilvl) - 1) * 0.04


## GLOWNE wejscie: deterministyczne wylosowanie itemu. Z `seed` budujemy LOKALNY RNG i z niego
## losujemy wszystko dla tej instancji (afiksy/sockety/enchant) — odtwarzalne u klienta z samego
## seeda. `biome` (StringName) filtruje afiksy tematyczne; `tier` = ItemResource.Rarity; `slot` =
## ItemResource.Slot. base_id moze zostac pusty (item proceduralny) lub byc dosypany z puli itemow.
func roll_item(item_seed: int, ilvl: int, biome: StringName, tier: int, slot: int,
		base_id: StringName = &"") -> ItemInstance:
	var rng := RandomNumberGenerator.new()
	# Mieszamy seed z kontekstem (slot/tier/ilvl), by ten sam seed na roznych slotach dal rozny item,
	# a JEDNOCZESNIE pelna determinacja: (seed,slot,tier,ilvl,biome) -> staly wynik.
	rng.seed = _mix_seed(item_seed, slot, tier, ilvl, biome)

	var it := ItemInstance.new()
	it.base_id = base_id
	it.rarity = tier
	it.ilvl = maxi(1, ilvl)
	it.seed = item_seed

	# --- Set (turkus): stale modyfikatory sztuki + przypisanie set_id ---
	# SET losuje set z puli ItemDB.sets (jesli sa). fixed_modifiers wchodza jako explicit (rozpoznawalnosc).
	var set_def: SetResource = null
	if tier == ItemResource.Rarity.SET:
		set_def = _pick_set(rng)
		if set_def != null:
			it.set_id = set_def.id          # NAPRAWA (audyt #2): zapamietaj set na instancji — inaczej bonus 2/4-cz. NIGDY nie liczy
			for fm in set_def.fixed_modifiers:
				if fm is StatModifier:
					var copy := _dup_mod(fm, &"set", set_def.id)
					it.explicit_modifiers.append(copy)

	# --- Afiksy losowane z pul AffixResource (filtr: slot + ilvl_min + biome), bez powtorzen stat ---
	var n_aff := _affix_count(tier)
	var rolled := _roll_affixes(rng, n_aff, ilvl, biome, slot, tier)
	for m in rolled:
		it.rolled_affixes.append(m)

	# --- Legendarny: efekt unikatowy jako MORE (game-changer, GDD 6.2) ---
	if tier == ItemResource.Rarity.LEGENDARY:
		var uniq := _roll_legendary_unique(rng, slot, ilvl)
		if uniq != null:
			it.rolled_affixes.append(uniq)

	# --- Sockety (puste; klejnoty wkladane pozniej w InventoryComponent.socket_gem) ---
	it.sockets = _roll_sockets(rng, tier)

	# --- Enchant (RARE+): {enchant_id, rank} — wybor 1 z puli; modyfikatory dolacza Inventory ---
	if tier >= ENCHANT_FROM_RARITY:
		it.enchant = _roll_enchant(rng, slot, tier)

	return it


## Czy/co dropi wrog. Zwraca Array[Dictionary]: kazdy wpis to
##   {kind: "item", instance: ItemInstance}  lub  {kind: "gold", amount: int}.
## HOST-ONLY: pobiera ze strumienia RNGService.loot tylko po stronie autorytetu. Brak loot_table
## -> sensowny domyslny drop (proceduralny item ze slotu losowego), by vertical slice mial co dropic.
func drop_for(enemy: Node) -> Array:
	var out: Array = []
	if not NetManager.has_state_authority(enemy):
		return out   # tylko HOST rozstrzyga drop (autorytet stanu — anti-desync lootu, TDD 6.2)

	var table: LootTableResource = null
	if enemy != null and "loot_table" in enemy and enemy.loot_table is LootTableResource:
		table = enemy.loot_table

	var ilvl := _enemy_ilvl(enemy)
	var biome := _enemy_biome(enemy)

	# --- Zloto ---
	var gmin := 0
	var gmax := 0
	if table != null:
		gmin = table.gold_min
		gmax = table.gold_max
	else:
		gmin = 3
		gmax = 12
	if gmax > 0:
		var gold := RNGService.loot.randi_range(gmin, maxi(gmin, gmax))
		if gold > 0:
			out.append({ "kind": "gold", "amount": gold })

	# --- Item(y) ---
	# Z tabeli: szansa per-wpis pominieta (vertical slice) — losujemy 1 item z rarity_weights.
	# Magic find (gracza) podbija rzadkosc — czytane z autorytetu, jesli dostepne. ETAP 4: do magic
	# find DODAJEMY premie z loot_tier biomu wroga (_enemy_loot_tier_bonus) — bogatszy biom (ember/
	# frost) realnie czesciej dropi wyzsza rzadkosc, nie tylko deklaratywnie (review #MAJOR).
	var rarity := _roll_rarity(table, _player_magic_find() + _enemy_loot_tier_bonus(enemy))
	if rarity >= 0:
		var slot := _roll_slot(table)
		var base_id := _roll_base_id(table, slot)
		var item_seed := RNGService.loot.randi()
		var inst := roll_item(item_seed, ilvl, biome, rarity, slot, base_id)
		out.append({ "kind": "item", "instance": inst })

	# --- Dropy CELOWANE z tabeli (item_drops): konkretny item z szansa, np. tame_charm dla bestii ---
	# Niezalezne od rarity (to konsumpcyjne/materialy — bierzemy je WPROST z ItemDB po item_id, bez
	# afiksow). Szansa per-wpis ze strumienia loot (HOST-ONLY — jestesmy juz za bramka autorytetu).
	if table != null:
		for entry in table.item_drops:
			if not (entry is Dictionary):
				continue
			var iid := StringName((entry as Dictionary).get("item_id", &""))
			if iid == &"":
				continue
			var chance := clampf(float((entry as Dictionary).get("chance", 1.0)), 0.0, 1.0)
			if RNGService.loot.randf() < chance:
				var targeted := _make_item_drop(iid, ilvl)
				if targeted != null:
					out.append({ "kind": "item", "instance": targeted })

	return out


# ============================================================================
#  WEWNETRZNE: losowanie skladnikow
# ============================================================================

## Buduje ItemInstance dla KONKRETNEGO itemu z ItemDB (base_id), BEZ losowania afiksow — uzywane przez
## dropy celowane (LootTableResource.item_drops, np. tame_charm). To itemy nieekwipowane (konsumpcyjne/
## materialy), wiec rarity nie ma znaczenia mechanicznie — ustawiamy COMMON dla spojnego wizualu dropu.
## ilvl niesiemy z kontekstu wroga (gdyby item kiedys skalowal sie poziomem). null gdy item nieznany.
func _make_item_drop(item_id: StringName, ilvl: int) -> ItemInstance:
	if ItemDB == null or ItemDB.item(item_id) == null:
		return null
	var inst := ItemInstance.new()
	inst.base_id = item_id
	inst.rarity = ItemResource.Rarity.COMMON
	inst.ilvl = maxi(1, ilvl)
	return inst


func _affix_count(tier: int) -> int:
	if tier >= 0 and tier < AFFIX_COUNT.size():
		return AFFIX_COUNT[tier]
	return 1


## Losuje `count` afiksow z pul ItemDB.affixes, filtrowanych slotem + ilvl_min + biomem, bez
## powtorzen `stat`. Wartosc = lerp(min,max,roll) * TIER_MULT[tier] * ilvl_scale(ilvl) (GDD 6.4).
## Wybor wazony `weight` afiksu. Zwraca Array[StatModifier] otagowane source=&"gear".
func _roll_affixes(rng: RandomNumberGenerator, count: int, ilvl: int, biome: StringName,
		slot: int, tier: int) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	var pool := _affix_pool(ilvl, biome, slot)
	if pool.is_empty():
		return out
	var mult := _tier_mult(tier)
	var scale := ilvl_scale(ilvl)
	var used_stats: Dictionary = {}      # `stat` -> true (item nigdy nie ma dwoch afiksow tej samej stat)
	var picked := 0
	var guard := 0
	while picked < count and guard < count * 12 and pool.size() > used_stats.size():
		guard += 1
		var a: AffixResource = _weighted_affix(rng, pool, used_stats)
		if a == null:
			break
		used_stats[a.stat] = true
		var roll := rng.randf()
		var raw := lerpf(a.value_min, a.value_max, roll) * mult * scale
		out.append(StatModifier.make(a.stat, a.op, raw, a.tags.duplicate(), &"gear", a.id))
		picked += 1
	return out


## Wazony wybor afiksu z puli, pomijajac juz uzyte `stat`. null gdy brak kandydatow.
func _weighted_affix(rng: RandomNumberGenerator, pool: Array, used: Dictionary) -> AffixResource:
	var total := 0.0
	for a in pool:
		if used.has((a as AffixResource).stat):
			continue
		total += maxf(0.0, (a as AffixResource).weight)
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	var acc := 0.0
	for a in pool:
		var aff := a as AffixResource
		if used.has(aff.stat):
			continue
		acc += maxf(0.0, aff.weight)
		if r < acc:
			return aff
	return null


## Pula afiksow (Array[AffixResource]) pasujacych do slotu/ilvl/biomu. Biom: afiks z pustym
## `biomes` pasuje wszedzie; z niepustym tylko gdy zawiera `biome`.
func _affix_pool(ilvl: int, biome: StringName, slot: int) -> Array:
	var pool: Array = []
	for id in ItemDB.affixes:
		var a: AffixResource = ItemDB.affixes[id]
		if a == null:
			continue
		if a.ilvl_min > ilvl:
			continue
		if not a.allowed_slots.is_empty() and not a.allowed_slots.has(slot):
			continue
		if not a.biomes.is_empty() and not a.biomes.has(biome):
			continue
		pool.append(a)
	return pool


func _roll_sockets(rng: RandomNumberGenerator, tier: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var rng_n := Vector2i(0, 0)
	if tier >= 0 and tier < SOCKETS_BY_TIER.size():
		rng_n = SOCKETS_BY_TIER[tier]
	var n := rng.randi_range(rng_n.x, rng_n.y)
	for _i in n:
		out.append(&"")   # pusty socket (klejnot wkladany pozniej)
	return out


## Wybor 1 enchantu z puli ItemDB (jesli sa enchanty zdefiniowane jako resource w sets/gems? nie).
## Etap 2: enchanty nie maja wlasnego DB-folderu, wiec losujemy z prostej puli wbudowanej (MCD).
## Zwraca {enchant_id, rank}. Modyfikatory enchantu dolacza InventoryComponent z ItemDB/wbudowanej mapy.
func _roll_enchant(rng: RandomNumberGenerator, _slot: int, tier: int) -> Dictionary:
	var ids := ENCHANT_POOL.keys()
	if ids.is_empty():
		return {}
	var pick := String(ids[rng.randi_range(0, ids.size() - 1)])
	# Wyzszy tier -> szansa na wyzsza range startowa (MCD: 1..3).
	var rank := 1
	if tier >= ItemResource.Rarity.EPIC:
		rank = rng.randi_range(1, 2)
	return { "enchant_id": pick, "rank": rank }


## Legendarny efekt unikatowy jako MORE na losowy "core" stat (game-changer). Tag &"unique".
func _roll_legendary_unique(rng: RandomNumberGenerator, slot: int, ilvl: int) -> StatModifier:
	var stat: StringName = &"damage" if slot == ItemResource.Slot.WEAPON else &"max_hp"
	var base := 0.15 + rng.randf() * 0.15        # +15..30% MORE
	var val := base + float(ilvl - 1) * 0.005     # lekko skaluje z ilvl
	return StatModifier.make(stat, StatModifier.Op.MORE, val,
		[&"unique"] as Array[StringName], &"unique", &"legendary")


func _pick_set(rng: RandomNumberGenerator) -> SetResource:
	var ids := ItemDB.sets.keys()
	if ids.is_empty():
		return null
	return ItemDB.sets[ids[rng.randi_range(0, ids.size() - 1)]]


# ============================================================================
#  WEWNETRZNE: wybor "co spadnie"
# ============================================================================

func _roll_rarity(table: LootTableResource, magic_find: float) -> int:
	var weights := DEFAULT_RARITY_WEIGHTS.duplicate()
	if table != null and not table.rarity_weights.is_empty():
		# rarity_weights: Rarity(int|String) -> waga. Nadpisujemy domyslne.
		weights = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		for k in table.rarity_weights:
			var idx := int(k)
			if idx >= 0 and idx < weights.size():
				weights[idx] = float(table.rarity_weights[k])
	# Magic find: przesuwa wage ku wyzszym tierom (proporcjonalnie do indeksu).
	if magic_find > 0.0:
		for i in range(1, weights.size()):
			weights[i] *= (1.0 + magic_find * float(i) * 0.5)
	return _weighted_pick(weights)


func _roll_slot(table: LootTableResource) -> int:
	# Tabela moze wymusic slot przez entries; vertical slice: losowy slot z noszonych (WEAPON..TRINKET).
	if table != null and not table.entries.is_empty():
		var e: Dictionary = table.entries[RNGService.loot.randi_range(0, table.entries.size() - 1)]
		var bid := StringName(e.get("item_id", ""))
		var ir := ItemDB.item(bid)
		if ir != null:
			return ir.slot
	return RNGService.loot.randi_range(ItemResource.Slot.WEAPON, ItemResource.Slot.TRINKET)


func _roll_base_id(table: LootTableResource, slot: int) -> StringName:
	# Jesli ItemDB ma itemy dla tego slotu, wybierz jeden (mesh/nazwa); inaczej pusty (proceduralny).
	var candidates: Array = []
	for id in ItemDB.items:
		var ir: ItemResource = ItemDB.items[id]
		if ir != null and ir.slot == slot:
			candidates.append(ir.id)
	if candidates.is_empty():
		return &""
	return candidates[RNGService.loot.randi_range(0, candidates.size() - 1)]


# ============================================================================
#  WEWNETRZNE: kontekst wroga (ilvl/biome/magic find)
# ============================================================================

func _enemy_ilvl(enemy: Node) -> int:
	if enemy != null and "loot_ilvl" in enemy:
		return maxi(1, int(enemy.loot_ilvl))
	return 1


func _enemy_biome(enemy: Node) -> StringName:
	if enemy != null and "loot_biome" in enemy and StringName(enemy.loot_biome) != &"":
		return StringName(enemy.loot_biome)
	return &"verdant"


## ETAP 4: premia rzadkosci z loot_tier biomu wroga jako wspolczynnik typu "magic find".
## enemy.loot_tier_bonus to (BiomeResource.loot_tier - 1): 0 verdant / 1 ember / 2 frost. Mnoznik
## BIOME_TIER_MF na stopien przeklada to na to samo przesuniecie wag co magic_find w _roll_rarity,
## wiec frost (bonus 2) realnie czesciej dropi wyzsza rzadkosc niz verdant (bonus 0). Bezpieczne 0.0.
const BIOME_TIER_MF: float = 0.5

func _enemy_loot_tier_bonus(enemy: Node) -> float:
	if enemy != null and "loot_tier_bonus" in enemy:
		return maxf(0.0, float(enemy.loot_tier_bonus)) * BIOME_TIER_MF
	return 0.0


## Magic find lokalnego gracza (jesli osiagalny przez GameState). Bezpieczne 0.0 gdy brak.
func _player_magic_find() -> float:
	var p = null
	if GameState != null and "local_player" in GameState:
		p = GameState.local_player
	if p == null:
		return 0.0
	for c in p.get_children():
		if c is StatsComponent:
			return (c as StatsComponent).get_stat(&"magic_find")
	return 0.0


# ============================================================================
#  POMOCNIKI
# ============================================================================

func _tier_mult(tier: int) -> float:
	if tier >= 0 and tier < TIER_MULT.size():
		return TIER_MULT[tier]
	return 1.0


## Deterministyczne mieszanie seeda z kontekstem (slot/tier/ilvl/biome) — staly wynik per kontekst.
func _mix_seed(s: int, slot: int, tier: int, ilvl: int, biome: StringName) -> int:
	var h := s
	h = (h * 73856093) ^ (slot * 19349663)
	h = (h * 83492791) ^ (tier * 50331653)
	h = (h * 2654435761) ^ (ilvl * 40503)
	h ^= int(hash(biome))
	# Maska na zakres dodatni zamiast absi() — usuwa rog INT64_MIN (absi(INT64_MIN) jest ujemny).
	# Determinizm bez zmian: to ten sam bijektywny zbior wartosci, tylko zawsze nieujemny.
	return h & 0x7FFFFFFFFFFFFFFF


func _dup_mod(m: StatModifier, source: StringName, source_id: StringName) -> StatModifier:
	return StatModifier.make(m.stat, m.op, m.value, m.tags.duplicate(), source, source_id)


func _weighted_pick(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return -1
	var r := RNGService.loot.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += maxf(0.0, float(weights[i]))
		if r < acc:
			return i
	return weights.size() - 1


# ============================================================================
#  WBUDOWANA PULA ENCHANTOW (MCD-light). enchant_id -> {ranks: [modyfikatory per ranga]}.
#  Modyfikatory zwraca enchant_modifiers() — InventoryComponent dolacza je do puli StatsComponent.
# ============================================================================
## Klucze jako String (nie StringName) — w slowniku-stalej GDScript traktuje String i StringName
## jako ROZNE klucze, a enchant_id z save/RPC bywa Stringiem. Lookup robimy przez String(eid).
## cdr/crit_chance to staty-frakcje o bazie 0 -> uzywamy FLAT (INCREASED na bazie 0 dawalby 0).
## damage/max_hp maja baze > 0 -> INCREASED dziala naturalnie (skaluje baze).
const ENCHANT_POOL: Dictionary = {
	"cool_down": { "stat": &"cdr", "op": StatModifier.Op.FLAT, "per_rank": 0.05 },
	"smiting":   { "stat": &"damage", "op": StatModifier.Op.INCREASED, "per_rank": 0.08 },
	"thorns":    { "stat": &"armor", "op": StatModifier.Op.FLAT, "per_rank": 0.05 },
	"vitality":  { "stat": &"max_hp", "op": StatModifier.Op.INCREASED, "per_rank": 0.06 },
	"swirling":  { "stat": &"crit_chance", "op": StatModifier.Op.FLAT, "per_rank": 0.03 },
}


## Modyfikatory enchantu wg {enchant_id, rank} -> Array[StatModifier]. Uzywane przez Inventory.
func enchant_modifiers(enchant: Dictionary) -> Array:
	var out: Array = []
	if enchant.is_empty():
		return out
	var eid := String(enchant.get("enchant_id", ""))
	var rank := int(enchant.get("rank", 1))
	if not ENCHANT_POOL.has(eid):
		return out
	var def: Dictionary = ENCHANT_POOL[eid]
	var val := float(def["per_rank"]) * float(maxi(1, rank))
	out.append(StatModifier.make(def["stat"], def["op"], val,
		[] as Array[StringName], &"enchant", StringName(eid)))
	return out
