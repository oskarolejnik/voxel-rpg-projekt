## 4. Mob ecosystem (hostile/neutral/passive + logika)

Rozdział definiuje żywy ekosystem mobów dla świata voxelowego RPG: pełną taksonomię (Hostile / Neutral / Passive), algorytmy zachowań (predator/prey, herd, flee, nest, den, terytorializm), dystrybucję per biom oraz konkretne rozszerzenia istniejących systemów (`EnemyResource`, `WorldSpawner`, `AIComponent`). Wszystkie nazwy biomów i statusów są spójne z resztą GDD (Forest / Plains / Swamp / Mountains / Desert / Snow / Volcanic; statusy: bleed / poison / freeze / burn / stun / weaken).

Cel projektowy: świat ma SPRAWIAĆ WRAŻENIE ZAMIESZKANEGO. Gracz na łące widzi pasące się jelenie, które uciekają gdy podejdzie wilk; w jaskini natyka się na legowisko z młodymi; uderza zająca i ten ucieka, ale uderza dzika i ten kontratakuje. To różni nasz świat od „areny z agresywnymi spawnami".

---

### 4.1. Taksonomia mobów — 3 kategorie

Wprowadzamy pole `category` w `EnemyResource` (enum `MobCategory`). Kategoria steruje domyślnym `aggro_mode`, doborem stanów `AIComponent` oraz logiką spawnu.

```gdscript
enum MobCategory { HOSTILE, NEUTRAL, PASSIVE }
enum AggroMode {
    INSTANT,        # atakuje natychmiast po wykryciu gracza (LOS + range)
    PATROL_INSTANT, # patroluje trasę, atakuje po wykryciu
    TERRITORIAL,    # atakuje tylko po wejściu w promień terytorium / legowiska
    RETALIATE,      # atakuje dopiero gdy dostanie obrażenia (lub atak na stado/młode)
    NEVER           # nigdy nie atakuje, tylko ucieka (passive)
}
```

#### A) HOSTILE — wrogowie aktywni

Spawnowani przez `WorldSpawner` z `BiomeResource.enemy_spawn_table`. Zawsze wrodzy (`allegiance = ENEMY`). Dzielą się na 5 pod-typów wg pola `hostile_tier`:

| Pod-typ | `aggro_mode` | Mnożnik HP | Mnożnik dmg | Aura/skala | Limit aktywnych |
|---|---|---|---|---|---|
| Aggressive | INSTANT | 1.0× | 1.0× | brak | część MAX_ACTIVE |
| Patrolling | PATROL_INSTANT | 1.1× | 1.0× | brak | część MAX_ACTIVE |
| Territorial | TERRITORIAL | 1.2× | 1.1× | subtelny pył pod nogami | część MAX_ACTIVE |
| Elite | INSTANT | 3.5× | 1.8× | aura kolor biomu + skala 1.4× | osobny limit ELITE=2 |
| Boss | INSTANT (faza) | 12× | 2.5× | aura + skala 2.2× + pasek HP | unikalny, spawn skryptowy |

Progi bazowe HP/dmg liczone z poziomu (ilvl z audytu: `ilvl = dtier*2 + (loot_tier-1)*2`). Baza dla zwykłego mobka lvl 1: `HP = 30`, `dmg = 5`. Skalowanie liniowe: `HP = 30 + level*12`, `dmg = 5 + level*1.6`. Mnożniki z tabeli nakładane na ten wynik.

#### B) NEUTRAL wildlife — dzika zwierzyna

`allegiance = ALLY` traktowane jako frakcja `WILDLIFE` (neutralna). `aggro_mode = RETALIATE` lub `TERRITORIAL`. Atakują WYŁĄCZNIE po jednym z triggerów:

1. Gracz zadał im obrażenia (`HurtboxComponent` → sygnał `damaged_by(attacker)`).
2. Gracz wszedł w promień terytorium/legowiska (`TERRITORIAL`, dla niedźwiedzi/dzików w pobliżu dena).
3. Gracz zaatakował członka stada lub młode (propagacja aggro przez `HerdComponent`).

Zwierzęta neutralne: **wilki, niedźwiedzie, jelenie, dziki, lisy, bawoły, pająki, jaszczury, kozły**. Część z nich to drapieżniki (wilk, niedźwiedź, pająk, lis) — uczestniczą w pętli predator/prey wobec kategorii Passive.

#### C) PASSIVE — fauna tła

`allegiance = ALLY` (frakcja `WILDLIFE`), `aggro_mode = NEVER`. Nigdy nie atakują; jedyne stany bojowe to `FLEE`. Stanowią prey w ekosystemie i źródło materiałów (mięso, skóry, pióra).

Zwierzęta pasywne: **króliki, owce, kury, ryby, motyle, żaby**. Niskie HP (5–15), brak ataku, wysoki próg flee (uciekają na sam widok drapieżnika/gracza-agresora).

---

### 4.2. Rozszerzenie `EnemyResource`

Plik docelowy: `res://data/db/enemies/*.tres` (kanon `EnemyDB.ENEMIES_DIR` z audytu/sek. 7) + skrypt `EnemyResource.gd`. Dodajemy pola (bez łamania istniejącego `enemy_spawn_table` w `BiomeResource`):

```gdscript
class_name EnemyResource extends Resource

# --- istniejące (z audytu) ---
@export var id: StringName
@export var display_name: String
@export var scene: PackedScene
@export var base_loot_tier: int = 1

# --- TAKSONOMIA ---
@export var category: MobCategory = MobCategory.HOSTILE
@export var hostile_tier: int = 0          # 0=aggressive 1=patrol 2=territorial 3=elite 4=boss
@export var aggro_mode: AggroMode = AggroMode.INSTANT
@export var faction: StringName = &"ENEMY" # ENEMY / WILDLIFE

# --- STATY BAZOWE (skalowane poziomem w WorldSpawner) ---
@export var base_hp: float = 30.0
@export var base_dmg: float = 5.0
@export var move_speed: float = 3.0
@export var detect_range: float = 14.0     # promień wykrycia gracza (m)
@export var attack_range: float = 1.8

# --- TERYTORIUM / AGGRO ---
@export var territory_radius: float = 0.0  # >0 = territorial; promień obrony (m)
@export var leash_radius: float = 24.0     # max oddalenie od kotwicy spawnu

# --- HERD (stado) ---
@export var herd_min: int = 0              # 0 = solo; >0 = spawn w stadzie
@export var herd_max: int = 0
@export var herd_cohesion: float = 6.0     # max dystans od lidera zanim wraca (m)

# --- FLEE (ucieczka) ---
@export var flee_hp_pct: float = 0.0       # 0 = nie ucieka; np 0.25 = ucieka <25% HP
@export var flee_on_predator: bool = false # passive: ucieka na widok drapieżnika/gracza
@export var flee_speed_mult: float = 1.5

# --- EKOSYSTEM: predator/prey ---
@export var diet: Array[StringName] = []   # id ofiar które ten mob łowi (HUNT)
@export var is_prey_for: Array[StringName] = [] # informacyjne (kto na niego poluje)

# --- NEST / DEN ---
@export var spawn_structure: StringName = &"none" # none / nest / den
@export var young_id: StringName = &""     # id młodego do spawnu w nest/den
@export var young_count: int = 0

# --- DROP-SYGNATURA ---
@export var drop_signature: StringName = &"generic" # tag dla LootService
@export var guaranteed_drops: Array[StringName] = []
```

`LootService` czyta `drop_signature` + `base_loot_tier`, by dobrać pulę afiksów/materiałów. Drop-sygnatury są zharmonizowane per kategoria (np. każdy neutral wildlife dropi `hide`/`raw_meat`, passive dropi materiał lekki, hostile dropi sprzęt/waluty).

---

### 4.3. Rozszerzenie `AIComponent` — nowe stany

Obecny `AIComponent` ma 5 stanów: `IDLE / PATROL / CHASE / ATTACK / FOLLOW` i binarne `allegiance_hostile`. Rozszerzamy maszynę stanów o 5 nowych i wprowadzamy `faction` zamiast czystego boola.

```gdscript
enum State { IDLE, PATROL, CHASE, ATTACK, FOLLOW,    # istniejące
             TERRITORIAL, FLEE, HERD, HUNT, RETURN } # nowe
```

| Stan | Trigger wejścia | Logika | Wyjście |
|---|---|---|---|
| `TERRITORIAL` | gracz w `territory_radius`, mob `aggro_mode=TERRITORIAL` i jeszcze nie aggro | obraca się ku graczowi, ostrzegawcza animacja; jeśli gracz wejdzie głębiej (`<0.6×radius`) lub uderzy → przejście do `CHASE` | gracz wyszedł z promienia → `RETURN` |
| `FLEE` | `hp < flee_hp_pct` LUB (passive i wykryto predatora/agresora) | biegnie wektorem `(self.pos - threat.pos)` × `flee_speed_mult`; pathfinding od zagrożenia | dystans > `detect_range×1.5` przez 3 s → `IDLE` |
| `HERD` | mob ma `herd_min>0` i nie jest liderem | trzyma się w `herd_cohesion` od lidera; kopiuje `target` lidera (propagacja aggro) | lider martwy → wybór nowego lidera / `IDLE` |
| `HUNT` | drapieżnik (neutral) wykrył prey z `diet` w `detect_range` i brak aggro od gracza | ściga ofiarę zamiast gracza; po zabiciu „je" (cooldown 20 s, regen HP) | prey zabity/uciekł → `RETURN`; gracz zaatakował → `CHASE` |
| `RETURN` | oddalenie > `leash_radius` od kotwicy, lub utrata celu | wraca do `anchor_position`, leczy się do pełna podczas powrotu | dotarł do kotwicy → `IDLE`/`PATROL` |

**Priorytet stanów (od najwyższego):** `FLEE` > `CHASE/ATTACK` (gracz) > `HERD-aggro` > `HUNT` > `TERRITORIAL` > `RETURN` > `PATROL` > `IDLE`. Aggro na gracza zawsze nadpisuje HUNT (zwierzę porzuca polowanie, gdy gracz je atakuje).

**Propagacja aggro przez stado:** gdy członek stada wejdzie w `CHASE`, emituje sygnał `herd_alert(target)` do `HerdComponent`; pozostali członkowie w `herd_cohesion` przechodzą w `CHASE` z tym samym celem. To realizuje wymóg „atak na stado/młode → cały herd atakuje".

---

### 4.4. Nowe komponenty

#### `HerdComponent` (`res://scripts/ai/HerdComponent.gd`)
- Tworzony przy spawnie stada przez `WorldSpawner`. Trzyma `members: Array[AIComponent]`, `leader`, `center`.
- Każdy tick (0.5 s, zsynchronizowany z tickiem spawnera) liczy `center` jako średnią pozycji; lider wybiera kierunek wędrówki (random walk w obrębie regionu).
- Spójność: jeśli member `dist(member, center) > herd_cohesion` → member wymusza `HERD`/`RETURN` ku centrum.
- Obsługuje `herd_alert(target)` (predator/prey i obrona stada).

#### `TerritoryComponent` (lekki, opcjonalny — można scalić w `AIComponent`)
- Trzyma `anchor_position`, `territory_radius`. Co tick sprawdza dystans gracza; podaje `AIComponent` flagę `player_in_territory`.

#### `EcoSensor` (współdzielony, query co tick przez spawner, nie per-mob)
- Drapieżniki nie skanują samodzielnie świata (koszt). Zamiast tego `WorldSpawner` raz na tick buduje listę aktywnych prey per region i przekazuje drapieżnikom kandydatów z ich `diet`. To trzyma koszt predator/prey w ryzach budżetu 4 GB.

---

### 4.5. Ekosystem — algorytmy

#### Predator / prey (kto na kogo poluje)

| Drapieżnik | Dieta (`diet`) | Biom |
|---|---|---|
| Wolf / Ice Wolf | rabbit, deer, sheep | Forest, Snow |
| Bear / Polar Bear | rabbit, deer, fish, boar | Forest, Snow |
| Fox | rabbit, frog, chicken | Forest, Plains |
| Spider / Frost Spider | rabbit, frog, butterfly | Swamp, Snow |
| Eagle (Mountains) | rabbit, goat (młode) | Mountains |
| Scorpion / Sand Worm | desert critters | Desert |

Algorytm (w `HUNT`): drapieżnik z listy `EcoSensor` wybiera najbliższego prey w `detect_range`, jeśli sam nie jest aggro na gracza i nie ma głodu cooldown. Po „zjedzeniu" ofiary: regen HP do 100%, `hunt_cooldown = 20 s`. Prey wykrywający drapieżnika w `detect_range` (i mający `flee_on_predator`) wchodzi w `FLEE`. To tworzy widoczne sceny pościgów na łące/w lesie.

#### Herd behavior (stado)
- Aktywne dla: deer, sheep, boar, goat, buffalo (`herd_min/max` 3–7).
- Lider = pierwszy spawnowany member z najwyższym HP. Wędruje random-walkiem; reszta utrzymuje formację w `herd_cohesion`.
- Atak na dowolnego membera → `herd_alert`: jelenie/owce uciekają stadem (`FLEE`), dziki/bawoły kontratakują stadem (`CHASE`).

#### Flee behavior (ucieczka)
- Passive: `flee_on_predator=true`, `flee_hp_pct=1.0` (uciekają zawsze gdy zagrożone — gracz-agresor lub drapieżnik w `detect_range`).
- Neutral nie-bojowe (jeleń, kozioł, lis): `flee_hp_pct ≈ 0.0` ale `flee_on_predator=true` wobec drapieżników; wobec gracza dopiero po jego ataku → wtedy też `FLEE` (a nie kontratak), bo to zwierzyna płochliwa.
- Neutral bojowe (niedźwiedź, dzik, bawół, pająk): `flee_hp_pct ≈ 0.15–0.25` (uciekają dopiero ranne), inaczej kontratakują.
- Wektor ucieczki: od zagrożenia, z preferencją terenu schodzącego/gęstego; jeśli zablokowany (ściana/woda) — bieg wzdłuż przeszkody (slide).

#### Nest areas (gniazda)
- Struktura terenowa generowana przez `WorldSpawner` (deterministycznie, seed regionu) dla mobów z `spawn_structure=nest`.
- Spawnuje cyklicznie młode (`young_id`, `young_count`), do limitu lokalnego. Atak na młode → `herd_alert` na dorosłych w pobliżu (obrona gniazda — `CHASE`).
- Przykłady: gniazda pająków (Swamp/Snow), gniazda orłów na półkach skalnych (Mountains), mrowiska/kopce skorpionów (Desert).

#### Den areas (legowiska drapieżników)
- `spawn_structure=den` — legowisko (wnęka/jama, idealnie wpięte w przyszłe jaskinie z rozdz. o jaskiniach).
- Wokół dena drapieżniki mają `aggro_mode=TERRITORIAL` (`territory_radius` 8–12 m): bronią legowiska. W środku den może trzymać młode + gwarantowany lepszy loot (`guaranteed_drops`).
- Przykłady: wilcze legowisko (Forest), jaskinia niedźwiedzia (Forest/Snow), nora sand worma (Desert), legowisko magma beasta (Volcanic).

---

### 4.6. Rozszerzenie `WorldSpawner` — spawn per biom + ring

Bazuje na istniejącym: regiony 48 m, siatka 3×3, tick 0.5 s, `MAX_ACTIVE=14`, `ELITE=2`, ważony pick z `BiomeResource.enemy_spawn_table`. Dodajemy:

1. **Filtr kategorii w tabeli spawnu.** `enemy_spawn_table` rozbita na 3 pod-pule z osobnymi wagami/budżetami:
   - `hostile_budget` (≈ 60% MAX_ACTIVE = ~8),
   - `neutral_budget` (≈ 30% = ~4, w tym stada),
   - `passive_budget` (≈ 10% = ~2 + ambient bez kosztu AI pełnego).
2. **Spawn stad.** Gdy wybrany mob ma `herd_min>0`, spawner tworzy `HerdComponent` i N=`randi_range(herd_min,herd_max)` członków w jednej kępie, licząc się ze wspólnym budżetem.
3. **Struktury (nest/den).** Per region, deterministycznie z seeda: szansa `nest_chance`/`den_chance` z `BiomeResource`. Struktura rejestruje kotwicę i własny mini-limit aktywnych (np. den = 1 dorosły + 2 młode).
4. **Skalowanie ring (dystans).** Bez zmian w `distance_tier()` (ring 80 m, cap 5). `ilvl = dtier*2 + (loot_tier-1)*2`. Hostile tier (elite/boss) i siła wildlife zależą od dtier — im dalej od spawnu, tym groźniejsze warianty (np. Wolf → Dire Wolf przy wyższym dtier).
5. **Budżet 4 GB.** Pooling wszystkich scen mobów; passive korzystają z „lite AI" (tylko `IDLE` + `FLEE`, bez nawigacji ścieżkowej — prosty steer). Stada liczą się jako N jednostek do `MAX_ACTIVE`, ale dzielą jeden `HerdComponent`. Deaktywacja regionu zwalnia całe stado/strukturę do puli.

---

### 4.7. Mob distribution per biom

Spawn logiczny: każdy biom ma własny mix Hostile/Neutral/Passive zgodny z kanonem. Tabela `BiomeResource.enemy_spawn_table` per biom dobiera id z poniższej listy.

| Biom | Hostile | Neutral wildlife | Passive |
|---|---|---|---|
| **Forest** (start, dtier 0–1) | Goblin, Slime, Goblin Brute (elite) | Wolf, Bear, Deer, Boar, Fox | Rabbit, Butterfly, Frog |
| **Plains** (dtier 1–2) | Goblin Slinger, Bandit Scout | Wolf, Boar, Buffalo (herd) | Sheep, Chicken, Rabbit, Butterfly |
| **Swamp** (dtier 2–3) | Swamp Beast, Poison Frog (hostile), Snake | Spider, Lizard, Boar | Frog, Fish, Butterfly |
| **Mountains** (dtier 3–4) | Stone Golem (elite), Wyvern (elite/boss) | Eagle, Goat | Rabbit, (mountain birds) |
| **Desert** (dtier 3–4) | Bandit, Scorpion, Sand Worm (boss) | Lizard, Vulture | (desert critters), Fish (oasis) |
| **Snow** (dtier 4–5) | Snowman, Frost Elemental (elite), Frost Giant (boss) | Ice Wolf (herd), Polar Bear, Frost Spider | Rabbit (arctic), Fish (under-ice) |
| **Volcanic** (dtier 5, endgame) | Fire Spirit, Magma Slime, Lava Beast (elite), Demon (boss) | — (jałowy: brak fauny neutralnej) | — (brak passive; biom śmierci) |

Uwaga spójnościowa: Volcanic celowo bez wildlife — wzmacnia narrację „martwego, wrogiego" endgame’u; cała pula = Hostile. Desert ma fauny mało (skrajne środowisko). Forest/Plains najbogatsze ekosystemowo (strefa nauki mechanik predator/prey).

---

### 4.8. Tabela mobów (pełna): nazwa | kategoria | biom | poziom | zachowanie | drop-sygnatura

| Nazwa | Kategoria | Biom | Poziom (dtier→lvl) | Zachowanie | Drop-sygnatura |
|---|---|---|---|---|---|
| Goblin | Hostile/aggressive | Forest | 1–6 | INSTANT chase | `goblin_common` (waluta, drobny sprzęt) |
| Slime | Hostile/aggressive | Forest | 1–5 | INSTANT, dzieli się przy śmierci | `slime_gel` (mat. alch., poison reagent) |
| Goblin Brute | Hostile/elite | Forest | 4–8 | INSTANT, aura, slam (stun) | `elite_forest` (gw. drop + afiks) |
| Wolf | Neutral/predator | Forest/Plains | 2–8 | HERD + HUNT(rabbit,deer), RETALIATE | `pelt_meat` (hide, raw_meat) |
| Dire Wolf (wariant dtier↑) | Neutral/predator | Forest/Snow | 6–14 | jw., bleed on bite | `pelt_meat_rare` |
| Bear | Neutral/territorial | Forest/Snow | 4–12 | TERRITORIAL(den), RETALIATE, flee<20% | `hide_heavy_meat` |
| Deer | Neutral/skittish | Forest/Plains | 1–6 | HERD, FLEE (zawsze ucieka) | `venison_hide` |
| Boar | Neutral/aggressive-prey | Forest/Plains/Swamp | 2–7 | HERD, RETALIATE+charge (knockback) | `boar_hide_meat` |
| Fox | Neutral/predator | Forest/Plains | 1–5 | HUNT(rabbit,frog), FLEE od gracza | `fox_pelt` |
| Buffalo | Neutral/territorial | Plains | 4–9 | HERD, RETALIATE stadem, charge | `buffalo_hide_horn` |
| Rabbit | Passive | Forest/Plains/Snow | 1–3 | NEVER, FLEE (lite AI) | `small_meat_fur` |
| Sheep | Passive | Plains | 1–3 | NEVER, HERD-flock, FLEE | `wool_mutton` |
| Chicken | Passive | Plains | 1 | NEVER, FLEE | `feather_egg` |
| Butterfly | Passive | Forest/Plains/Swamp | 1 | NEVER, ambient wander | `none` (ambient) |
| Frog | Passive | Forest/Swamp | 1–2 | NEVER, FLEE | `frog_reagent` |
| Fish | Passive | (woda) | 1–3 | NEVER, swim/flee | `raw_fish` |
| Spider | Neutral/territorial | Swamp/Snow | 3–10 | TERRITORIAL(nest), HUNT, poison bite | `spider_silk_venom` |
| Frost Spider | Neutral/territorial | Snow | 6–12 | jw., freeze on bite | `silk_frost` |
| Snake | Hostile/aggressive | Swamp | 3–8 | INSTANT, poison | `snake_venom_skin` |
| Poison Frog | Hostile/aggressive | Swamp | 3–7 | INSTANT, poison cloud | `toxic_gland` |
| Swamp Beast | Hostile/elite | Swamp | 6–11 | INSTANT, aura, weaken | `elite_swamp` |
| Lizard | Neutral/skittish | Swamp/Desert | 2–8 | FLEE od gracza, RETALIATE | `scale_meat` |
| Eagle | Neutral/predator | Mountains | 5–11 | HUNT(rabbit, goat-młode), nest, dive | `feather_talon` |
| Goat | Neutral/skittish | Mountains | 3–8 | HERD, climb, FLEE | `goat_hide_horn` |
| Stone Golem | Hostile/elite | Mountains | 8–14 | INSTANT slow, aura, AoE slam (stun) | `elite_mountain` (rzadka ruda) |
| Wyvern | Hostile/elite→boss | Mountains | 10–16 | INSTANT, fly, burn breath | `wyvern_scale` / boss `boss_mountain` |
| Bandit | Hostile/patrol | Desert | 5–11 | PATROL_INSTANT, grupa | `bandit_loot` (waluta, sprzęt) |
| Scorpion | Hostile/territorial | Desert | 4–10 | TERRITORIAL(nest), poison sting | `chitin_venom` |
| Vulture | Neutral/predator | Desert | 4–9 | HUNT(carrion/critters), FLEE | `feather_dark` |
| Sand Worm | Hostile/boss | Desert | 12–18 | burrow, ambush, AoE, boss aura/HP bar | `boss_desert` |
| Snowman | Hostile/aggressive | Snow | 6–12 | INSTANT, freeze touch | `frost_core` |
| Ice Wolf | Neutral/predator | Snow | 7–13 | HERD + HUNT, freeze bite | `pelt_frost_meat` |
| Polar Bear | Neutral/territorial | Snow | 8–14 | TERRITORIAL(den), RETALIATE | `hide_polar_heavy` |
| Frost Elemental | Hostile/elite | Snow | 9–15 | INSTANT, aura, freeze AoE | `elite_snow` |
| Frost Giant | Hostile/boss | Snow | 14–20 | slow, smash (stun), boss aura/HP bar | `boss_snow` |
| Fire Spirit | Hostile/aggressive | Volcanic | 14–20 | INSTANT float, burn | `ember_essence` |
| Magma Slime | Hostile/aggressive | Volcanic | 14–20 | INSTANT, dzieli się, burn pool | `magma_gel` |
| Lava Beast | Hostile/elite | Volcanic | 16–22 | INSTANT, aura, AoE burn | `elite_volcanic` |
| Demon | Hostile/boss | Volcanic | 20–26 | multi-faza, burn+weaken, boss aura/HP bar | `boss_volcanic` (legendary pool) |

Poziom = orientacyjny zakres wg dtier biomu (Forest dtier 0–1 → lvl ~1–6; Volcanic dtier 5 → lvl ~14–26 z wariantami/elite). Konkretny lvl liczy `WorldSpawner` z `distance_tier()`.

---

### 4.9. Elite i Boss — wyróżnienie wizualne i mechaniczne

**Elite** (`hostile_tier=3`):
- Skala modelu ×1.4, emisyjna aura w kolorze biomu (Forest=zielona, Snow=cyjan, Desert=bursznowa, Volcanic=czerwona, Swamp=trująca zieleń, Mountains=szara/kamienna).
- HP ×3.5, dmg ×1.8, jedna mechanika specjalna (slam/aura/AoE status z listy bleed/poison/freeze/burn/stun/weaken).
- Osobny limit `ELITE=2` aktywnych na obszar. Gwarantowany lepszy drop (`elite_<biom>` → afiks/socket przez `LootService`).

**Boss** (`hostile_tier=4`):
- Unikalny, spawn skryptowy (np. w jaskini/dungeonie lub jako world-event przy wysokim dtier), nie z losowej puli.
- Skala ×2.2, aura + pasek HP w UI, HP ×12, dmg ×2.5, wielofazowa walka (zmiana mechanik przy progach 66%/33% HP).
- Drop z dedykowanej puli (`boss_<biom>`, szansa na legendary/set). Hook: `LootService.roll_boss(drop_signature, ilvl)`.

---

### 4.10. Hooki implementacyjne (skrót dla programisty)

- `EnemyResource.gd` — dodać pola z 4.2; istniejące `.tres` (gdy powstaną) wypełniać wg tabeli 4.8.
- `BiomeResource.gd` — `enemy_spawn_table` rozbić na pod-pule kategorii + dodać `nest_chance`, `den_chance`.
- `AIComponent.gd` — dodać stany z 4.3, zamienić `allegiance_hostile:bool` na `faction:StringName` (ENEMY/WILDLIFE) + zachować kompatybilność (ENEMY = hostile).
- `WorldSpawner.gd` — budżety kategorii, spawn stad (`HerdComponent`), struktury nest/den, `EcoSensor` per region.
- Nowe: `HerdComponent.gd`, opcjonalnie `TerritoryComponent.gd`, `EcoSensor` (w spawnerze).
- `LootService` — obsługa `drop_signature`, `guaranteed_drops`, `roll_boss`.
- Statusy bleed/poison/freeze/burn/stun/weaken — już w warstwie combat (`DamageService`); moby je tylko aplikują przez `AbilityComponent`/`Hitbox`.
