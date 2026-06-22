# Technical Design Document — Voxel RPG (nazwa robocza)

> Implementowalny blueprint v2 dla Godot 4.7 + GDScript. Single-player-first, NETWORK-AWARE od
> dnia 1 (co-op do 4, listen-server). Spojny z `GDD.md` (mechaniki) i `ROADMAP.md` (etapy).
>
> **Stan realnego kodu (zweryfikowany w `C:\Users\oskar\Downloads\voxel-rpg`):** istnieja
> `src/Player.gd`, `src/Enemy.gd`, `src/HUD.gd`, `src/Main.gd`, `src/DayNight.gd` oraz
> `src/world/{VoxelWorld,Chunk,Blocks,VoxelModel}.gd`. Warstwy kolizji: teren=bit0 (warstwa 1),
> gracz=bit1 (warstwa 2), wrog=bit2 (warstwa 3); ciala koliduja TYLKO z terenem. Kontrakt walki:
> `take_damage(amount, from)` u gracza i wroga; wrog ma `armor: float (0..1)`; combo->przebicie
> pancerza liczone w `Player._deal_damage_to()`. Swiat: `VoxelWorld.feature_hash(wx, wz, salt)
> -> float` (deterministyczny mix int), `biome_factor(world_x, world_z) -> float`, streaming
> przez `WorkerThreadPool`, `Chunk.build_data()`, `VoxelModel.build_mesh(def, voxel_size, offset)`.
> Wszystkie hooki ponizej wskazuja TE pliki/funkcje (a nie hipotetyczne nazwy).

---

## 1. Architektura: kompozycja komponentow + dane w Resource + autoloady

### 1.1 Dlaczego NIE pelny ECS

1. **Silnik jest scene-tree-owy.** Godot daje cykl zycia wezlow, sygnaly i high-level
   multiplayer (`MultiplayerSpawner`/`MultiplayerSynchronizer`/RPC) dzialajace NA wezlach. Czysty
   ECS wymagalby obejscia tego i recznej replikacji — tracimy darmowy netcode.
2. **GDScript nie da cache-locality.** Glowna zaleta ECS (ciasne tablice struktur) jest nieosiagalna
   w dynamicznie typowanym GDScript — dostajemy zlozonosc bez wydajnosci.
3. **Skala jest mala.** Co-op 4 + kilkadziesiat mobow w runie != 50 000 encji. Kompozycja
   wezlow-komponentow wystarcza.

**Wybor:** Encja = root (`CharacterBody3D`) + dzieci-komponenty. Komponenty gadaja sygnalami,
referencje do braci cache'uja raz w `_ready()`. Dane statyczne (definicje) w `Resource`. Stan
dynamiczny w komponentach. Logika globalna w autoloadach.

### 1.2 Drzewo komponentow (gracz / wrog / pet)

```
Entity (CharacterBody3D)            # warstwa wg roli: gracz=2, wrog=3, pet=2 (sojusznik)
+-- NetIdentity (Node)              # net_id, owner_peer, helpery autorytetu (przez NetManager)
+-- StatsComponent (Node)          # StatBlock + pipeline modyfikatorow — JEDYNE zrodlo staty
+-- HealthComponent (Node)         # current_hp z StatsComponent.max_hp; sygnaly damaged/died
+-- HitboxComponent (Area3D)        # zadaje dmg (melee/AoE/pocisk) -> DamageService
+-- HurtboxComponent (Area3D)       # przyjmuje dmg -> HealthComponent
+-- AbilityComponent (Node)         # wykonuje SkillResource: koszt zasobu, CD, cast, spawn sceny
+-- BuffComponent (Node)            # czasowe StatModifiery (po source_id) -> StatsComponent
+-- AIComponent (Node)              # wrogowie/pet: maszyna stanow (HOST-ONLY)
+-- InputComponent (Node)           # gracz: input -> intencje (gotowe pod predykcje)
+-- InventoryComponent (Node)       # gracz: 7 slotow + plecak + sety
+-- LootComponent (Node)            # wrogowie: LootTableResource -> drop on death (HOST-ONLY)
+-- AppearanceComponent (Node3D)    # istniejacy model voxelowy + animacje proceduralne
```

Migracja jest stopniowa: obecne `Player.gd`/`Enemy.gd` to monolity — Etap 1 rozbija je na powyzsze
komponenty (patrz `ROADMAP.md`), zachowujac kontrakt `take_damage(amount, from)` jako fasade.

### 1.3 Autoloady (singletony — rejestry i uslugi bezstanowe)

| Autoload | Odpowiedzialnosc |
|---|---|
| `GameState` | tryb (SP/host/client), pauza, biezacy biom/run, ref do lokalnego gracza |
| `NetManager` | sesja, `SceneMultiplayer`, mapowanie peer_id<->encja, **abstrakcja autorytetu** |
| `SaveManager` | serializacja `SaveData` (JSON + `version`), hybryda swiat+postac |
| `ItemDB` | rejestr `ItemResource`/`AffixResource`/`SetResource`/`GemResource` |
| `SkillDB` | rejestr `SkillResource`/`PassiveNodeResource`/`SkillTreeResource` per klasa |
| `EnemyDB` | rejestr `EnemyResource` + `BiomeResource` |
| `LootService` | generowanie dropow z `LootTableResource` (rzadkosc/afiksy/sockety) — HOST-ONLY |
| `DamageService` | JEDNO miejsce liczenia obrazen (atakujacy StatBlock vs obronca) — HOST-ONLY |
| `RNGService` | deterministyczny RNG: strumienie `world` / `loot` / `combat` z seeda |

Regula: **autoloady nie trzymaja stanu encji** (to komponenty). Trzymaja rejestry danych i
bezstanowe uslugi albo globalny stan sesji.

> Uwaga integracyjna: swiat juz ma wlasny seed deterministyczny w `VoxelWorld` (`FEATURE_SEED`
> + `feature_hash`). `RNGService` NIE duplikuje generacji terenu — przejmuje TYLKO strumienie
> `loot`/`combat` i dostarcza `world`-seed do `VoxelWorld`/`DungeonGen` (jedno zrodlo seeda).

---

## 2. Schematy danych (Resource z polami)

Wszystko dziedziczy po `Resource` (`class_name`), serializowalne, edytowalne w inspektorze.

### 2.1 StatBlock + StatModifier (rdzen)

```gdscript
# StatModifier.gd
class_name StatModifier extends Resource
enum Op { FLAT, INCREASED, MORE }   # +N (added) | +N% sumowane | xN% multiplikatywne
@export var stat: StringName          # &"damage", &"max_hp", &"crit_chance", &"fire_damage"...
@export var op: Op = Op.FLAT
@export var value: float = 0.0
@export var tags: Array[StringName] = []   # &"fire"/&"melee"/&"set"/&"unique" — filtry/synergie
@export var source: StringName = &""        # &"gear"/&"gem"/&"enchant"/&"set"/&"tree"/&"buff"
@export var source_id: StringName = &""     # do usuwania (id buffa/itemu)

# StatBlock.gd — bazowe staty encji (definicja, nie stan)
class_name StatBlock extends Resource
@export var max_hp: float = 100.0
@export var hp_regen: float = 0.0
@export var max_stamina: float = 100.0
@export var stamina_regen: float = 22.0
@export var damage: float = 18.0            # == Player.attack_damage
@export var attack_speed: float = 2.2       # == 1/attack_cooldown
@export var crit_chance: float = 0.05
@export var crit_mult: float = 1.5
@export var armor: float = 0.0              # 0..1 (% redukcji, jak u Enemy)
@export var armor_pierce: float = 0.0
@export var move_speed: float = 6.0
@export var dodge_iframes: float = 0.30
@export var lifesteal: float = 0.0
@export var area_radius: float = 2.2        # == Player.attack_range
@export var cdr: float = 0.0
@export var magic_find: float = 0.0
@export var resistances: Dictionary = {}    # StringName(element) -> float(%)
@export var elemental: Dictionary = {}      # &"fire"/&"frost"/&"poison"/&"lightning"/&"dark" -> float
@export var pet_damage: float = 0.0
@export var pet_hp: float = 0.0
@export var primary: Dictionary = {}        # &"str"/&"dex"/&"int" -> int (skalowanie klas)
```

> **KANON op:** `FLAT` / `INCREASED` / `MORE`. (Sekcja itemizacji uzywala aliasow
> `PCT_ADD`/`PCT_MULT` — to dokladnie `INCREASED`/`MORE`; w kodzie obowiazuje nazewnictwo z `Op`.)

### 2.2 HitData (kontener trafienia walki)

```gdscript
# HitData.gd
class_name HitData extends RefCounted        # lekki, tworzony per cios (nie zapisywany)
var source: Node                              # kto bije (gracz/wrog/pet)
var base_damage: float = 0.0
var tags: Array[StringName] = []              # typ+dostarczanie+skalowanie (np. [&"fire",&"aoe",&"spell"])
var crit_chance: float = 0.05
var crit_mult: float = 1.5
var armor_pierce: float = 0.0                 # combo gracza wlicza tu (0..1)
var lifesteal: float = 0.0
var knockback: float = 6.0                    # sila (zastepuje hardkod 6.0 w take_damage)
var on_hit_effects: Array = []                # statusy z afiksow/setow (ignite/chill/poison...)
var hit_position: Vector3 = Vector3.ZERO
func to_dict() -> Dictionary: ...             # do RPC (klient->host)
static func from_dict(d: Dictionary) -> HitData: ...
```

### 2.3 Skille i drzewko

```gdscript
# SkillResource.gd
class_name SkillResource extends Resource
@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export var class_path: StringName            # do ktorej sciezki (podklasy) nalezy
@export var cost_resource: StringName = &""    # &"mana"/&"rage"/&"combo"/&"focus"/&"stamina"
@export var cost_amount: float = 0.0
@export var cooldown: float = 0.0
@export var cast_time: float = 0.0
@export var damage_mult: float = 1.0
@export var tags: Array[StringName] = []       # tagi skilla (synergia z lootem)
@export var max_augments: int = 3              # gniazda augmentow (0..3)
@export var scene: PackedScene                 # pocisk/AoE/strefa do zespawnowania
@export var passive_modifiers: Array[StatModifier] = []  # gdy skill wpiety

# PassiveNodeResource.gd
class_name PassiveNodeResource extends Resource
@export var id: StringName
@export var display_name: String
@export var modifiers: Array[StatModifier] = []
@export var cost_points: int = 1
@export var requires: Array[StringName] = []   # prerekwizyty (id innych wezlow)
@export var min_level: int = 1                  # keystone=25, capstone=60
@export var is_keystone: bool = false
@export var grants_skill: StringName = &""

# SkillTreeResource.gd
class_name SkillTreeResource extends Resource
@export var class_id: StringName
@export var nodes: Array[PassiveNodeResource] = []
@export var layout: Dictionary = {}            # id -> Vector2 (pozycja w UI)

# AugmentResource.gd — wstawka modyfikujaca KONKRETNY skill (loot)
class_name AugmentResource extends Resource
@export var id: StringName
@export var display_name: String
@export var modifiers: Array[StatModifier] = []   # modyfikatory tego skilla
@export var added_tags: Array[StringName] = []     # moze dodac tag (np. &"zone")
@export var effect_id: StringName = &""             # specjalny efekt (rozszczepienie, kaluza...)
```

### 2.4 Itemy, afiksy, sety, klejnoty, loot

```gdscript
# ItemResource.gd — DEFINICJA (read-only z ItemDB)
class_name ItemResource extends Resource
enum Slot { WEAPON, HELM, CHEST, LEGS, BOOTS, TRINKET, CONSUMABLE, MATERIAL }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, SET }   # KANON tierow (= GDD 6.2)
@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export var mesh: PackedScene                   # voxelowy model broni/itemu
@export var slot: Slot
@export var weapon_class: StringName = &""       # &"axe2h"/&"wand"/&"bow"... -> nadpisuje bron
@export var base_modifiers: Array[StatModifier] = []   # implicit
@export var max_sockets: int = 0
@export var set_id: StringName = &""
@export var req_level: int = 1
@export var stack_size: int = 1

# AffixResource.gd
class_name AffixResource extends Resource
enum Kind { PREFIX, SUFFIX }
@export var id: StringName
@export var kind: Kind
@export var stat: StringName
@export var op: StatModifier.Op = StatModifier.Op.FLAT
@export var value_min: float
@export var value_max: float
@export var tags: Array[StringName] = []        # &"fire"/&"defense"/&"crit"...
@export var ilvl_min: int = 1
@export var allowed_slots: Array[int] = []        # ItemResource.Slot
@export var biomes: Array[StringName] = []        # biom dosypujacy ten afiks (pusty = wszedzie)
@export var weight: float = 1.0

# SetResource.gd
class_name SetResource extends Resource
@export var id: StringName
@export var display_name: String
@export var fixed_modifiers: Array[StatModifier] = []   # stale afiksy sztuk (rozpoznawalnosc)
@export var bonuses: Dictionary = {}   # int(liczba_czesci) -> Array[StatModifier]

# GemResource.gd
class_name GemResource extends Resource
@export var id: StringName
@export var display_name: String
@export var quality: int = 1            # 1..5 (Skaza..Doskonaly)
@export var modifiers: Array[StatModifier] = []

# EnchantResource.gd
class_name EnchantResource extends Resource
@export var id: StringName
@export var display_name: String
@export var allowed_slots: Array[int] = []
@export var ranks: Array[Dictionary] = []   # [{rank, effect_id, magnitude, modifiers}]

# LootTableResource.gd
class_name LootTableResource extends Resource
@export var entries: Array[Dictionary] = []      # {item_id, weight, min_qty, max_qty}
@export var rarity_weights: Dictionary = {}      # Rarity -> waga (per biom/dungeon-tier)
@export var affix_count_by_rarity: Dictionary = {}  # Rarity -> Vector2i(min_pre+suf)
@export var gold_min: int = 0
@export var gold_max: int = 0

# ItemInstance.gd — INSTANCJA (w plecaku/save/sync) vs definicja
class_name ItemInstance extends Resource
@export var base_id: StringName            # -> ItemResource w ItemDB
@export var rarity: int                    # ItemResource.Rarity
@export var ilvl: int = 1
@export var seed: int = 0                   # deterministyczne odtworzenie afiksow u klienta
@export var rolled_affixes: Array = []      # [{affix_id, value}] (lub odtwarzane z seed)
@export var sockets: Array[StringName] = [] # gem_id lub &"" (pusty)
@export var enchant: Dictionary = {}        # {enchant_id, rank}
```

Algorytm `roll_item(rng, ilvl, biome, tier, slot) -> ItemInstance` (w `LootService`):
zapisz `seed = rng.randi()`; pula prefiksow/sufiksow filtrowana slotem + `ilvl_min <= ilvl` +
biomem; losuj bez powtorzen `stat`; `value = lerp(min,max,roll) x TIER_MULT[tier] x
ilvl_scale(ilvl)` (`ilvl_scale = 1 + (ilvl-1)*0.04`); dla LEGENDARY dorzuc efekt unikatowy (MORE);
`sockets = roll_sockets(rng, tier)`.

### 2.5 Wrogowie, biomy, wyglad, save

```gdscript
# EnemyResource.gd
class_name EnemyResource extends Resource
@export var id: StringName
@export var display_name: String
@export var scene: PackedScene
@export var stats: StatBlock
@export var loot_table: LootTableResource
@export var xp_reward: int = 10
@export var ai_profile: StringName = &"melee"   # &"melee"/&"ranged"/&"caster"
@export var threat_tier: StringName = &"trash"   # &"trash"/&"elite"/&"boss" (telegraf — GDD 5.4)
@export var tameable: bool = false               # pet od lvl 5
@export var tame_difficulty_mult: float = 1.0
@export var biomes: Array[StringName] = []

# BiomeResource.gd
class_name BiomeResource extends Resource
@export var id: StringName                       # &"verdant"/&"emberwaste"/&"frosthelm"
@export var display_name: String
@export var loot_tier: int = 1
@export var noise_params: Dictionary = {}        # FastNoiseLite config (nadpisanie VoxelWorld)
@export var enemy_spawn_table: Array[Dictionary] = []  # {enemy_id, weight, max_alive}
@export var affix_themes: Array[StringName] = [] # tagi afiksow dosypywanych (GDD 6.4)
@export var entrance_chance: float = 0.01        # szansa wejscia dungeonu na chunk
@export var fog_color: Color
@export var ambient_light: Color

# CharacterAppearance.gd — kreator postaci (parametry istniejacej postaci voxelowej)
class_name CharacterAppearance extends Resource
@export var class_id: StringName
@export var body_color: Color
@export var height_scale: float = 1.0
@export var limb_proportions: Dictionary = {}    # P_* z Player.gd (np. P_SHOULDER_W...)

# SaveData.gd — root zapisu
class_name SaveData extends Resource
@export var version: int = 1
# --- POSTAC (przenosna miedzy swiatami) ---
@export var char_name: String
@export var class_id: StringName
@export var level: int = 1
@export var xp: int = 0
@export var gold: int = 0
@export var dust: int = 0                 # Pyl Enchantowania
@export var essence: int = 0              # Esencja Ulepszen
@export var orbs: int = 0                 # Orby Przemiany (respec)
@export var appearance: CharacterAppearance
@export var allocated_passives: Array[StringName] = []
@export var equipped_skills: Array[StringName] = []
@export var skill_augments: Dictionary = {}     # skill_id -> Array[augment_id]
@export var inventory: Array = []                # Array[ItemInstance zserializowane]
@export var equipment: Dictionary = {}           # Slot -> ItemInstance
@export var pet_id: StringName = &""
@export var pet_stable: Array[StringName] = []   # oswojone "w stajni"
# --- SWIAT (TYLKO host) ---
@export var world_seed: int = 0
@export var world_changes: Dictionary = {}       # chunk_key -> {voxel_edits} (delty od generacji)
@export var discovered_chunks: Array = []
@export var world_entities: Array = []            # trwale encje (NIE dungeonowe)
@export var play_time: float = 0.0
```

> **Instancja vs definicja:** `ItemResource` jest stala (z `ItemDB`). To, co w plecaku, to
> `ItemInstance` (lekka, z `seed`). W co-opie/save synchronizujemy `ItemInstance`; afiksy klient
> odtwarza deterministycznie z `seed + ilvl + rarity`.

---

## 3. Stat / modifier pipeline (jedno zrodlo prawdy)

`StatsComponent` jest JEDYNYM miejscem, gdzie powstaje finalna wartosc statu. Nikt nie czyta
afiksu z itemu wprost — wszyscy pytaja `StatsComponent.get_stat(&"armor")`.

### 3.1 Kolejnosc liczenia (standard ARPG)

```
final = (base + sum FLAT) x (1 + sum INCREASED) x prod (1 + MORE)   -> konwersje -> krytyk (w DamageService)
```

- **base** — z `StatBlock` (klasa + poziom).
- **FLAT (added)** — plaskie dodatki (np. `+5–10 Ogien do Ataku`), sumuja sie.
- **INCREASED** — addytywne procenty w jednej puli (+20% +15% = +35%), mnoza baze.
- **MORE** — multiplikatywne, kazde osobno (rzadkie, mocne: keystone, set 4-cz., legendy).
- **Konwersje** (np. 30% Fizyczne -> Ogien) — miedzy INCREASED a MORE.
- **Krytyk** — szansa (cap) i mnoznik liczone na koncu, w `DamageService` (nie w StatsComponent).

### 3.2 Zbieranie modyfikatorow (4 zrodla, kazde otagowane `source`)

1. `InventoryComponent` — `base_modifiers` ekwipunku + `rolled_affixes` + gemy w socketach +
   bonusy setow (z liczby zalozonych czesci).
2. drzewko (z `SaveData.allocated_passives`) — modyfikatory wezlow.
3. `BuffComponent` — czasowe (z `source_id` do wygasniecia).
4. `AbilityComponent` — `passive_modifiers` wpietych skilli.

Augmenty skilli (2.3) dzialaja lokalnie na skill (przed pipeline'em obrazen), NIE wchodza do
globalnej puli StatsComponent.

### 3.3 Rdzen (memoizacja + invalidacja)

```gdscript
# StatsComponent.gd
class_name StatsComponent extends Node
@export var base: StatBlock
var _mods: Array[StatModifier] = []
var _cache: Dictionary = {}
var _dirty := true
signal stats_changed

func rebuild_modifiers() -> void:
    _mods.clear()
    _mods.append_array(_inventory.collect_modifiers())
    _mods.append_array(_tree.collect_modifiers())
    _mods.append_array(_buffs.collect_modifiers())
    _mods.append_array(_abilities.collect_modifiers())
    _dirty = true
    stats_changed.emit()

func get_stat(stat: StringName) -> float:
    if _dirty: _cache.clear(); _dirty = false
    if _cache.has(stat): return _cache[stat]
    var b := _base_value(stat)
    var flat := 0.0; var inc := 0.0; var more := 1.0
    for m in _mods:
        if m.stat != stat: continue
        match m.op:
            StatModifier.Op.FLAT:      flat += m.value
            StatModifier.Op.INCREASED: inc  += m.value
            StatModifier.Op.MORE:      more *= (1.0 + m.value)
    var fin := (b + flat) * (1.0 + inc) * more
    _cache[stat] = fin
    return fin
```

Zmiana ekwipunku/buffa/drzewka -> `rebuild_modifiers()` -> invalidacja cache -> `stats_changed` ->
HUD i `HealthComponent.max_hp` reaguja. Identyczne dane -> identyczny wynik na hoscie i kliencie
(determinizm = brak desyncu staty).

### 3.4 Most do istniejacego kodu (minimalna inwazyjnosc)

- `Player._deal_damage_to()` (ok. L1201) i `take_damage()` (ok. L1267) czytaja `stats.get_stat(...)`
  zamiast surowych `attack_damage`/`max_hp`. Wzor pancerza gracza = kopia z `Enemy.take_damage`
  (`effective_armor = armor * (1 - pierce)`).
- Combo->pierce z `Player` przechodzi do `HitData.armor_pierce` (zachowane `armor_pierce_per_combo`/
  `armor_pierce_max`/`combo_window`).
- `Enemy` czyta `stats` z `EnemyResource.stats` (warianty Brute/Slinger to skalowanie tych samych
  eksportow + dla Slingera spawn pocisku w `_state_attack`).

---

## 4. DamageService (centralny on-hit, host-authoritative)

```gdscript
# DamageService.gd (autoload) — JEDNO wejscie calej walki
func request_hit(source: Node, target: Node, hit: HitData) -> void:
    if NetManager.has_authority(target):     # host LUB single-player
        _resolve(source, target, hit)
    else:
        _predict_fx(source, target, hit)     # KLIENT: tylko FX (flash/hitstop/numbers)
        _submit.rpc_id(1, source.get_path(), target.get_path(), hit.to_dict())

func _resolve(source: Node, target: Node, hit: HitData) -> void:
    var dmg := hit.base_damage
    if RNGService.combat.randf() < hit.crit_chance: dmg *= hit.crit_mult
    var armor := 0.0
    if "armor" in target: armor = clampf(target.armor, 0.0, 1.0)   # kontrakt istnieje
    var eff := armor * (1.0 - hit.armor_pierce)
    dmg *= (1.0 - eff)
    # odpornosci typu (hit.tags przeciw target.resistances) ...
    target.take_damage(dmg, source)          # ISTNIEJACY kontrakt — bez zmian
    if hit.lifesteal > 0.0 and source.has_method("heal"):
        source.heal(dmg * hit.lifesteal)
    # on_hit_effects (statusy/proki), FX zwrotne (hitstop skalowany, shake, damage numbers)
```

Kolejnosc rozstrzygania (jedno miejsce -> latwy balans i replikacja): krytyk -> pancerz po
przebiciu -> odpornosci -> `take_damage` -> lifesteal/statusy/proki -> FX. W SP `has_authority()==true`
zawsze, wiec `request_hit` po prostu wola `_resolve` — zero zmian w odczuciu gry wzgledem dzisiejszego
inline'u w `Player._deal_damage_to()`.

---

## 5. Warstwy kolizji walki (rozszerzenie istniejacych bitow)

Trzymamy bity 0–2 (teren/gracz/wrog) bez zmian. Hitboxy Area3D sa na OSOBNYCH warstwach (tanie,
jednoznaczne query; ciala nadal nie wykrywaja sie nawzajem). To takze granica autorytetu sieci —
hitboxy autorytatywne zyja na hoscie.

| Bit | Warstwa | Co tam jest | Kto pyta (mask) |
|---|---|---|---|
| 0 | `terrain` | chunki voxela (CCD pociskow, LOS) | gracz, wrog, pocisk, raycast |
| 1 | `player_body` | CharacterBody gracza (+ pet jako sojusznik) | hitboxy wrogow |
| 2 | `enemy_body` | CharacterBody wrogow | hitboxy gracza, pociski gracza, pet |
| 3 | `player_hitbox` | Area3D atakow gracza/peta | mask `enemy_body` |
| 4 | `enemy_hurtbox` | precyzyjny hurtbox wroga (opcjonalnie) | hitbox gracza |
| 5 | `enemy_hitbox` | Area3D atakow/telegrafow wrogow | mask `player_body` |
| 6 | `projectile` | pociski (gracz i wrog) | informacyjnie / pet-AI |
| 7 | `interactable` | loot, wejscia dungeonow, oswajalne bestie | raycast interakcji |

Pet (`allegiance = ALLY`) ustawia `collision_layer = player_body`, wiec wrogowie celuja w niego
i gracza tak samo, a hitbox peta celuje w `enemy_body` (cala maszyna stanow z `Enemy.gd` reuzyta).

---

## 6. NETCODE co-op 4 (host-authoritative + predykcja)

### 6.1 Model

- **Listen-server:** jeden gracz hostuje (autorytet), do 3 klientow dolacza. Host gra normalnie.
- **`SceneMultiplayer`** + `MultiplayerSpawner` (spawn encji) + `MultiplayerSynchronizer`
  (transform/HP/state) + RPC (akcje).
- **Swiat z seeda lokalnie:** klient dostaje tylko `world_seed` + liste edycji swiata
  (`world_changes`) i generuje chunki SAM (`VoxelWorld` + `WorkerThreadPool`). Po sieci leci
  TYLKO: encje, ich stan, loot, edycje. Geometria voxela sie NIE wysyla.

### 6.2 Co sie synchronizuje, a co liczone lokalnie

| Element | Autorytet | Transport |
|---|---|---|
| Generacja terenu/chunkow | lokalnie u kazdego z seeda | NIC |
| Wejscia dungeonow | lokalnie z seeda chunka (`feature_hash`) | NIC |
| Geometria dungeonu | lokalnie z `entrance_seed` | `seed + tier` (kilka bajtow) |
| Edycje swiata (zniszczone voxele) | host | RPC + save (male delty) |
| Pozycja/rotacja encji | host | `MultiplayerSynchronizer` (interpolacja u klientow) |
| HP/staty encji | host | `MultiplayerSynchronizer` (klient tylko wyswietla) |
| Obrazenia (kto/ile) | **host** (`DamageService`) | RPC wynik |
| Drop lootu (afiksy/rzadkosc) | **host** (`LootService`) | RPC: `ItemInstance` (seed+tier+ilvl) |
| Input gracza | klient->host | RPC (intencje + tick) |
| Ruch wlasnej postaci | predykcja klienta + rekonsyliacja | — |
| AI wrogow/peta | **host-only** (`AIComponent`) | wynik przez sync |
| Animacje/VFX/SFX/hitstop | lokalnie (kosmetyka) | trigger przez sync/RPC |

### 6.3 Predykcja + rekonsyliacja (ruch wlasnej postaci)

1. Klient zbiera input, OD RAZU porusza swoja postacia i zapisuje `(input, tick, predicted_pos)`.
2. Klient wysyla input do hosta (RPC, ze stemplem ticka).
3. Host liczy ruch autorytatywnie i odsyla `(tick, authoritative_pos)` przez synchronizer.
4. Rozbieznosc > prog -> rekonsyliacja: ustaw pozycje autorytatywna i odtworz inputy z bufora od
   tego ticka (replay). Male roznice — wygladzanie.
5. Cudzy gracze i wrogowie u klienta — interpolacja miedzy stanami (bez predykcji ruchu).

### 6.4 Walka i FX po sieci

- Klient klika atak -> RPC `request_attack(target_or_dir, tick)` -> host waliduje (zasieg, CD,
  zasob, czy cel zyje, czy hitbox mogl siegnac — anti-cheat) -> `DamageService._resolve`.
- **Predykcja klienta = tylko FX, nigdy HP.** HP/smierc/loot zmienia wylacznie host. Jesli host
  odrzuci trafienie, klient po prostu nie dostaje update HP — FX byl kosmetyczny (brak „phantom kill”).
- **Hitstop/bullet-time MUSZA byc lokalne.** Obecny `Player._hitstop()` uzywa globalnego
  `Engine.time_scale = 0.05` (ok. L1213) — w co-opie zamrozilby wszystkich. Zamiana: lokalny
  „freeze frame” pozy atakujacego + shake (globalny `time_scale` dozwolony TYLKO gdy
  `not multiplayer.has_multiplayer_peer()`).
- **Pociski:** spawn przez `MultiplayerSpawner`; ruch i CCD liczy host, klienci interpoluja; klient
  strzelajacy moze pokazac „ghost” zastapiony replika. **Strefy/HazardZone:** tykaja (dmg) tylko na
  hoscie, wizual replikowany. Determinizm terenu (identyczna geometria u wszystkich) sprawia, ze CCD
  pocisku o teren daje ten sam wynik — kolizje z terenem mozna nawet predykowac bez desyncu.

### 6.5 Warstwa abstrakcji autorytetu (SP-first -> retrofit bez przepisywania)

Cala mutacja stanu (HP, loot, smierc, postep) przechodzi przez `DamageService`/`LootService`
bramkowane `NetManager.has_authority()`. W SP `NetManager` to stub zwracajacy `true` — logika
rozstrzyga lokalnie; w Etapie 7 ten sam kod dziala na HOSCIE, a klient wysyla intencje (RPC) i
odbiera stan (Synchronizer). Co-op to wiec DOLOZENIE transportu, NIE przepisanie logiki.

---

## 7. Skalowalna jakosc grafiki (presety Low / High)

Decyzja: zostajemy na Godot; troske o "sufit grafiki" rozwiazujemy SKALOWALNIE, nie zmiana silnika.
Look stylizowany (Cube World) zalezy od ART DIRECTION, nie od Nanite/Lumen — a Godot 4 Forward+ ma
caly potrzebny arsenal. Wystawiamy ustawienia w `GameSettings` (autoload) + menu opcji; preset to
zestaw wartosci property `Environment`/`VoxelWorld` (mamy je), NIE przebudowa.

**Preset LOW (cel: RTX 3050 4GB — obecny tuning):** volumetric fog OFF (atmosfere niesie depth fog),
SDFGI/SSR/DoF OFF; near_dist 3 / far_dist 5; MSAA 2x; cienie max 80 m; MAX_FINALIZE 1; MAX_PROPS 35.

**Preset HIGH (mocniejszy GPU, ten sam silnik):** volumetric fog ON (god-rays), SDFGI ON (real-time
GI) lub reflection probes, SSR (woda/metal), SSIL, DoF; near_dist 5-6 / far_dist 8-10; MSAA 4x;
gestsze propy/liscie; ostrzejsze i dluzsze cienie.

**Zasada:** gra CHODZI na Low (laptop), a na High wyglada oszalamiajaco — sufit wizualny NIE jest
zamkniety wyborem silnika. Dochodzi osobny pass art-direction (lepsze materialy, woda z odbiciami,
dopieszczone swiatlo), ktory podnosi BAZOWY look obu presetow.

```gdscript
# w DamageService / AbilityComponent / LootComponent / HealthComponent
func _change_state(target, fn: Callable) -> void:
    if NetManager.has_authority(target):     # host LUB single-player
        fn.call()                             # realna zmiana stanu
    else:
        NetManager.request.rpc_id(1, ...)     # klient prosi hosta
```

W **single-player** `NetManager.has_authority()` zwraca ZAWSZE `true` (brak sieci = jestes
autorytetem). Caly kod gry pisany jest jak host-authoritative od dnia 1; SP to „sesja z jednym
peerem-hostem”. Retrofit co-op (Etap 7) = wlaczenie transportu (Spawner/Synchronizer/RPC), NIE
przepisanie logiki. `NetIdentity` niesie `net_id` + `owner_peer`; w SP wszystko nalezy do peer 1.

---

## 7. Swiat, biomy i dungeony (integracja z realnym kodem)

### 7.1 Biom z seeda (rozszerzenie istniejacego `biome_factor`)

`VoxelWorld` ma juz `biome_factor(world_x, world_z) -> float` (jeden niskoczestotliwosciowy szum)
i `feature_hash(wx, wz, salt)`. Biom rdzeniowy (Verdant/Emberwaste/Frosthelm) wyliczamy z tego
SAMEGO mechanizmu, nie wprowadzajac osobnego stanu sieciowego:

```gdscript
# rozszerzenie VoxelWorld.gd — biom rdzeniowy (deterministyczny, network-safe)
enum Biome { VERDANT, EMBERWASTE, FROSTHELM }
func get_biome(chunk_x: int, chunk_z: int) -> int:
    var t := biome_factor(chunk_x * CHUNK_SIZE, chunk_z * CHUNK_SIZE)       # temperatura/region
    var h := feature_hash(chunk_x, chunk_z, SALT_HUMIDITY) * 2.0 - 1.0       # 2. wymiar z hasha
    if t < -0.15: return Biome.FROSTHELM
    if h > 0.20:  return Biome.VERDANT
    return Biome.EMBERWASTE
```

> Korekta wzgledem wczesniejszego szkicu: NIE tworzymy dwoch nowych obiektow `FastNoiseLite`
> (temp+humid) ani pola `world_seed` na boku — reuzywamy `biome_factor` + `feature_hash`
> (drugi wymiar przez `salt`), bo to jedno, juz deterministyczne zrodlo.

### 7.2 Wejscia dungeonow (deterministyczne z chunka)

```gdscript
# DungeonEntrance.gd
func chunk_has_entrance(cx: int, cz: int) -> bool:
    var roll := world.feature_hash(cx, cz, SALT_DUNGEON)        # [0,1)
    var biome := world.get_biome(cx, cz)
    return roll < EnemyDB.biome(biome).entrance_chance          # Verdant 1% / Ember 3% / Frost 5%
func entrance_seed(cx: int, cz: int) -> int:
    return int(world.feature_hash(cx, cz, SALT_DUNGEON_SEED) * 0x40000000)
```

Prefab wejscia wbudowany w chunk przy generacji (`Chunk.build_data()`); trigger = Area3D na
`interactable`. Wejscie -> fade + async build w watku (reuse `WorkerThreadPool` z `VoxelWorld`) ->
osobna proceduralna przestrzen. Co-op: host wola `enter_dungeon`, RPC `load_dungeon(seed, tier)`;
kazdy klient generuje lokalnie z seeda.

### 7.3 Generacja dungeonu (`DungeonGen.gd`, NOWY)

Graf pokoi (logika) + stitching prefabow voxelowych (geometria) + BSP (rozmieszczenie w gridzie),
wszystko z `entrance_seed` przez `RNGService`. Sciezka krytyczna `ENTRANCE -> COMBAT x k -> TREASURE
-> COMBAT x m -> MINIBOSS -> BOSS` + odnogi; zamek-klucz gwarantuje klucz PRZED drzwiami BOSS (w
MINIBOSS/SECRET). Mesh + kolizje budowane w watku tym samym builderem co chunki (`Chunk.build_data`
/ `VoxelModel.build_mesh`) — zero duplikacji meshingu. Skalowanie trudnosci/lootu wg dystansu od
origin (model Cube World): `loot_tier = region_tier + biome_bonus`, poziom wrogow wokol poziomu gracza.

### 7.4 Pety (reuse `Enemy.gd`)

```gdscript
# Enemy.gd — dodac:
enum Allegiance { HOSTILE, ALLY }
@export var allegiance := Allegiance.HOSTILE
func convert_to_pet(owner_node) -> void:
    allegiance = Allegiance.ALLY
    collision_layer = 1 << 1                     # warstwa gracza (sojusznik)
    _leash_anchor = owner_node                   # leash trzyma sie gracza, nie home
    _state = State.FOLLOW                         # nowy stan: PATROL z anchor=gracz
# target-selection filtruje allegiance == HOSTILE; reszta maszyny (chase/attack/leash) bez zmian
```

Oswajanie (`TameSystem`): wymaga lvl 5 + cel <35% HP; szansa z `tame_power` jedzenia x
`tame_difficulty_mult`. 1 aktywny pet, reszta `pet_stable`. W co-opie oswajanie = RPC do hosta.

---

## 8. Zapis hybrydowy

**Host posiada save swiata.** Klienci NIE zapisuja swiata; zabieraja tylko progres POSTACI
(synchronizowany i cache'owany jako ich `SaveData` postaci — przenosny miedzy swiatami).

- **Postac:** wyglad, klasa, poziom/xp, waluty (Zloto/Pyl/Esencja/Orby), `allocated_passives`,
  `equipped_skills`, `skill_augments`, `equipment` (Slot->`ItemInstance`) + `inventory`, `pet_id` +
  `pet_stable`.
- **Swiat (tylko host):** `world_seed`, `world_changes` (delty voxeli od generacji — tylko
  odstepstwa od seeda), `discovered_chunks`, `world_entities` (trwale encje otwartego swiata; NIE
  dungeonowe — instancje dungeonow sa efemeryczne, ich loot/postep wchodzi do postaci).
- **Mechanika:** JSON z polem `version` (migracje) zamiast surowego `ResourceSaver` (czytelnosc/
  wersjonowanie). Autosave na eventach (wyjscie z dungeonu, level up, wylogowanie) + interwalowo.
  Co-op: na evencie zapisu host zapisuje swiat + swoja postac, kazdy klient dostaje snapshot SWOJEJ
  postaci i trzyma u siebie.
