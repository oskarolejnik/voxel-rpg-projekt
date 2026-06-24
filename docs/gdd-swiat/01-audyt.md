## 1. Audyt obecnego świata

Audyt realnego kodu (`src/world/`, `components/`, `data/resources/`, `autoload/EnemyDB.gd`) pod kątem celu docelowego: 7 biomów rozseparowanych dystansem + ekosystem + jaskinie + głębokie drzewka skilli. Wnioski oparte o nazwy funkcji/plików/liczby z kodu.

### 1.1 Skala i separacja biomów — `VoxelWorld.get_biome()`

Skala terenu (styl Cube World): `CHUNK_SIZE=32` voxeli × `VOXEL_SIZE=0.5` = **16 m/chunk**, `WORLD_HEIGHT=96` (48 m), `SEA_LEVEL=24` (12 m). Heightmapa `surface_height()`: `round(BASE_HEIGHT(14) + clampf(raw*1.6+0.5)*HEIGHT_AMPLITUDE(64))` → surface_y ∈ [24, 88] voxeli (12–44 m). `_noise.frequency=0.007`, FBM 4 oktawy.

Biom liczony z DWÓCH szumów niskiej częstotliwości (`_biome_noise`=temperatura seed 4242, `_humid_noise`=wilgotność seed 2024), **oba `frequency=0.0025`**. Model Whittaker-light, progi: `temp<=-0.15`→`frosthelm`, `temp>=0.12 && hum<0`→`emberwaste`, reszta→`verdant`.

**OCENA SKALI BIOMÓW:** `frequency=0.0025` Perlin → cecha szumu ~400 m, czyli strefy biomów rzędu **kilkuset metrów** — NIE poszatkowane, raczej duże plamy. ALE separacja jest **mozaikowa, nie progresją dystansem**: `get_biome` zależy WYŁĄCZNIE od (x,z) przez szum, nie od odległości od spawnu. Sąsiedztwo biomów jest losowe (las potrafi graniczyć ze śniegiem) — sprzeczne z celem „im dalej, tym trudniej, biomy w pierścieniach dystansu". Trudność/loot skaluje OSOBNY mechanizm `distance_tier()` (`DISTANCE_RING_METERS=80`, cap `DISTANCE_TIER_MAX=5`), niezależny od biomu. Czyli: temat (biom) = szum, moc (tier) = dystans — rozłączne.

### 1.2 Spawn wrogów — `WorldSpawner.gd`

Świat dzielony na regiony `REGION_SIZE=48 m`, aktywowane w siatce `REGION_RADIUS=1` (3×3) wokół gracza, tick co `TICK_INTERVAL=0.5 s`. Twarde limity: `MAX_ACTIVE=14`, `MAX_SPAWN_PER_TICK=6`, `MAX_ACTIVE_ELITES=2`. Region aktywuje się RAZ (`_activated`), deterministycznie z `region_seed(base_seed, region)`.

Dobór wroga: `_region_biome()` (biom środka regionu) → `EnemyDB.biome(id).enemy_spawn_table` (lista `{enemy_id, weight, max_alive}`) → `_weighted_pick()`. Liczba wrogów `max_in_region = min(3 + dtier, 6)`, `count = randi_range(0, max)`. ilvl lootu: `dtier*2 + (biome.loot_tier-1)*2`. Roaming elite: `ELITE_REGION_CHANCE=0.14`, `_elite_pick()` (heurystyka: rzadki + nazwa kończąca się na "brute"), spawn ≥18 m od gracza.

**SPROSTOWANE (audyt pierwotnie błędnie zgłosił pusty świat):** spawn jest w 100% sterowany DANYMI (`enemy_spawn_table` z `.tres`) — i te dane ISTNIEJĄ. `res://data/db/` zawiera **61 plików `.tres`**, w tym **8 wrogów** (`goblin/brute/slinger` + warianty `ember_*`/`frost_*` + `goblin_loot`), **3 biomy** (`verdant/emberwaste/frosthelm` z `enemy_spawn_table`), pełny loot (21 afiksów, sety, gemy, itemy). `EnemyDB._scan` ładuje je → tabele spawnu NIE są puste → **gra spawnuje wrogów** (3×3 regiony, MAX_ACTIVE=14). Uwaga: ContentDB (6 ras/11 klas) to ODRĘBNY, nowy system w `res://data/content/` (seed w kodzie, na potrzeby kreatora) — nie myleć z gameplayowym `res://data/db/`. REALNE ograniczenie to nie „brak treści", lecz **WĄSKI ZAKRES**: tylko 8 typów wrogów i 3 biomy (z docelowych 7).

### 1.3 Różnorodność mobów i ekosystem — `EnemyResource.gd` / `AIComponent.gd`

`EnemyResource` ma pola pod różnorodność: `ai_profile` (melee/ranged/caster), `threat_tier` (trash/elite/boss), `tameable`, `biomes[]`, `variant_meta` (windup/range/projectile/scale/element). To wystarcza na warianty Goblin/Brute/Slinger z briefu.

`AIComponent` to maszyna 5 stanów: `IDLE/PATROL/CHASE/ATTACK/FOLLOW`, host-authoritative, z aggro (`aggro_radius=12`), leash (`leash_radius=18`), entry-delay (0.35 s, okno na unik), histereza ataku ×1.3, tryb peta (ALLY → cel = najbliższy wróg z grupy "enemies", leash do gracza). 

**BRAK EKOSYSTEMU (vs cel):** model wrogości jest binarny — `allegiance_hostile` (wróg→gracz / pet→wróg). NIE ma kategorii Neutral/Passive wildlife, NIE ma reakcji „atakuj tylko gdy uderzony / wejście na terytorium / atak na młode". Brak: predator/prey, herd/flock, flee behavior, nest/den, terytorializm. Wszystko co spawnuje jest od razu agresywne (CHASE z IDLE/PATROL po wejściu w aggro). Zero passive/neutral wildlife.

### 1.4 Jaskinie — BRAK

Grep `cave|cavern|tunnel|carve|get_noise_3d` w `src/world/`: jedyne trafienie to `_tint_noise.get_noise_3d` (kolor bloku). `Chunk._generate_data` buduje WYŁĄCZNIE kolumny do `surface_height` + woda do `SEA_LEVEL` + powierzchniowe feature'y (`_place_tree/_place_bush/_place_rock`) i propy. **Zero pustek 3D, zero carvingu — jaskiń nie ma w ogóle.** `DungeonGen.gd` to osobny system (instancjonowane dungeony na siatce gridowej, `DUNGEON_ORIGIN y=4000`), NIE jaskinie eksploracyjne wplecione w teren.

### 1.5 Głębia drzewka skilli — `SkillTreeComponent` / zasoby

`SkillTreeResource` = `{class_id, nodes:Array[PassiveNodeResource], layout}`. `PassiveNodeResource` = `{id, modifiers, cost_points, requires[], min_level, is_keystone, grants_skill}`. `SkillResource` ma bogaty timeline ataku (anticipation/active/recovery/cancel_window, augmenty, aura). `SkillTreeComponent` obsługuje: alokację z walidacją (prereq `requires`, `min_level`, dostępne punkty), dealokację z kontrolą spójności grafu, respec za walutę (`ORB_COST_STEPS=[500,1500,4000]` schodkowo / `gold_cost_for=level*50`), provider modyfikatorów do StatsComponent.

**OCENA (sprostowana):** silnik drzewka jest solidny (pasywy + grants_skill + keystone + respec) i ma JUŻ treść dla klasy startowej: `data/db/trees/warrior.tres` + **8 pasywów** `data/db/passives/war_*` (damage_1/2, endurance, toughness, battle_fury, bloodthirst, reckless, second_wind). REALNE braki vs cel: (a) drzewka istnieją tylko dla **1 z 11 klas** (10 klas bez `.tres`); (b) brak rozdziału **CORE/ADVANCED**, spec branch A/B, ultimate/movement/defensive jako warstw drzewka; (c) status effects (bleed/poison/freeze/burn/stun/weaken) są w warstwie combat/DamageService, NIE jako nody. Czyli: silnik + 1 płytkie drzewko Wojownika → trzeba pogłębić strukturę i dopisać drzewka pozostałych klas (NIE budować od zera).

### 1.6 Mapowanie istniejących 3 biomów → docelowe 7

| Obecny (`get_biome`) | Tier | Docelowe biomy (z briefu) |
|---|---|---|
| `verdant` (Verdant Hollow) | 1 start | 1. Forest, 2. Plains (rozbić temp×hum) |
| — (brak) | — | 3. Swamp (nowy: hum bardzo wysoka, temp średnia) |
| — (brak) | — | 4. Mountains (sterować `surface_height`/biome noise — wysoki teren) |
| `emberwaste` (Emberwaste) | 2 mid | 5. Desert |
| — (brak) | — | 7. Volcanic (nowy: skrajne temp + dystans) |
| `frosthelm` (Frosthelm Peaks) | 3 szczyt | 6. Snow |

Docelowo: 3 → 7 biomów + ZMIANA modelu z czystego szumu temp×hum na **pierścienie dystansu** (`distance_tier` jako główny selektor biomu, szum tylko jako lokalna wariacja w obrębie pierścienia), by uzyskać progresję „dalej = trudniej + lepszy loot + ekstremalniejszy teren".

### 1.7 Ryzyka / długi techniczne
- ~~**BLOKER #1:** brak `.tres`~~ → **NIEPRAWDA (sprostowane).** `data/db/` ma 61 `.tres` (8 wrogów, 3 biomy, drzewko Wojownika + 8 pasywów, pełny loot). Gra spawnuje wrogów i działa. REALNY temat to **WĄSKI ZAKRES TREŚCI**: 3 biomy (cel 7), 8 typów wrogów, drzewka tylko dla 1/11 klas — to rozszerzanie istniejącej treści, nie tworzenie od zera.
- **BLOKER #1 (faktyczny):** biom ≠ dystans — `get_biome` losowy względem spawnu; cel „biomy w pierścieniach trudności" wymaga przepisania selektora biomu.
- Brak warstwy ekosystemu w `AIComponent` (binarne allegiance) — neutral/passive wildlife to nowy podsystem.
- Brak generacji 3D pustek → jaskinie wymagają nowego przebiegu w `Chunk._generate_data` (3D noise carve) + integracji ze spawnerem/lootem.
- `WORLD_HEIGHT=96` (48 m) jest płytkie na pionowe Mountains/jaskinie wielopoziomowe — może wymagać podniesienia.
- Budżet 4GB: `near_dist=3`/`far_dist=5`, `MAX_ACTIVE=14`, `MAX_PROPS_PER_CHUNK=35` — każdy nowy podsystem (wildlife, jaskinie) musi mieścić się w tych limitach (pooling).
