## 5. Cave generation design (proceduralne jaskinie)

Jaskinie to **pełnoprawny filar eksploracji** (nie dekoracja terenu) i kluczowy element pętli `explore -> fight -> loot -> upgrade -> find cave -> clear -> repeat`. Wpinają się w istniejący streaming chunków (`Chunk._generate_data`, off-thread jak obecnie), są deterministyczne (`feature_hash` na bazie `region_seed`/world seed), respektują budżet 4 GB (RTX 3050) i łączą się zarówno z `WorldSpawner`/`LootService`, jak i z instancjonowanymi dungeonami (`DungeonGen`, `DUNGEON_ORIGIN y=4000`).

Założenie progresji: jaskinie dziedziczą trudność/loot z `distance_tier()` (ring 80 m) miejsca wejścia oraz z biomu wejścia (`VoxelWorld.get_biome()`), dokładnie tak jak `WorldSpawner` skaluje `ilvl = dtier*2 + (biome.loot_tier-1)*2`. Im dalej od spawnu, tym głębsze i groźniejsze jaskinie + lepszy loot.

### 5.1 Filozofia i miejsce w pętli

- Jaskinia = **lokalny mikro-content**: 2–8 min eksploracji, samowystarczalny (wejście → korytarze → komora(y) → reward → wyjście), zawsze coś do zdobycia (ruda / ukryty loot / elite / mini-boss).
- Każdy biom ma 1–3 charakterystyczne typy jaskiń (patrz 5.7) — własna paleta bloków, oświetlenie, hazardy, moby i loot, by jaskinia czytała się jak „wnętrze tego biomu".
- Część jaskiń ma **ukryte wejście** (nagroda za eksplorację/percepcję), część widoczne z powierzchni (zachęta do zejścia). Najgłębsze jaskinie zawierają **portal do instancjonowanego dungeonu** (`DungeonGen`) — jaskinia jest „przedsionkiem", dungeon „finałem".

### 5.2 Taksonomia typów jaskiń

| Typ | Skala (komory / głębokość) | Profil generacji | Wejście | Rola w progresji |
|---|---|---|---|---|
| **Small cave** | 1–2 komory, do 8 m pod surface | krótki worm + 1 cellular blob | widoczne (otwór w zboczu) | tutorial eksploracji, dtier 0–1 |
| **Deep cave** | 3–6 komór, sieć tuneli, do ~30 m | 3D-noise sieć + worm-łączniki | widoczne lub półukryte | core loop, dtier 1–3 |
| **Crystal cave** | 2–4 duże komory | cellular (duże komory) + żyły kryształu | ukryte (za rudą/ścianą) | farm rzadkich materiałów, dtier 2–4 |
| **Ice cave** | 2–5 komór, lód + przepaście | 3D-noise + carve lodu, śliskie podłoże | widoczne w lodzie/jeziorze | hazard zimno, dtier 3–4 |
| **Lava cave** | 3–6 komór, jeziora lawy | 3D-noise + lava-fill poniżej `LAVA_LEVEL` | widoczne (łuna) | endgame, dtier 4–5 |
| **Underground ruins** | siatka pomieszczeń + tunele | hybryda: worm/cellular + prefab-stamp pokoi | ukryte (zawalone wejście) | lore + loot + portal do `DungeonGen` |
| **Monster den** | 1 duża komora + boczne nory | cellular blob + radialne nory (nest) | widoczne (ślady/kości) | nest/den ekosystemu, mini-boss, dtier 2–5 |

### 5.3 Techniki generacji w custom voxel engine

Generacja odbywa się jako **nowy, drugi przebieg** w `Chunk._generate_data`, PO zbudowaniu kolumn terenu (heightmapa do `surface_height`, woda do `SEA_LEVEL`), a PRZED placementem powierzchniowych feature'ów. Wszystko deterministyczne i off-thread (ten sam wątek streamingu co dziś).

Kolejność w `_generate_data`:
1. Kolumny terenu + woda (jak obecnie).
2. **`_carve_caves(chunk)`** — wycinanie pustek (3D noise + worms + cellular). Zapisuje voxele AIR poniżej powierzchni.
3. **`_fill_cave_fluids(chunk)`** — wlanie lawy/wody poniżej progów (`LAVA_LEVEL`, lokalny water table).
4. **`_decorate_caves(chunk)`** — rudy/kryształy/stalaktyty/propy w warstwie graniczącej z AIR.
5. Powierzchniowe feature'y (drzewa/krzaki/głazy) — z maską „nie stawiaj nad otworem jaskini".

#### 5.3.1 3D noise carving (główna metoda — sieci i komory)

Bazowy filtr pustki: `FastNoiseLite` 3D (nowy `_cave_noise`, własny seed `world_seed ^ 0xCAVE`), Perlin/OpenSimplex2, `frequency≈0.045`, 2–3 oktawy. Voxel staje się AIR gdy:

```
density = _cave_noise.get_noise_3d(x, y*Y_SQUASH, z)   # Y_SQUASH≈0.65 → komory bardziej poziome
is_cave = abs(density) < CAVE_THRESHOLD                  # ridged: |noise|<próg = wąskie wstęgi pustki
```

- `CAVE_THRESHOLD` skaluje gęstość jaskiń: 0.06 (rzadkie) → 0.12 (gęsta sieć w Mountains).
- **Maska głębokości**: carve tylko dla `y < surface_height - CAVE_MIN_DEPTH(3 voxele)` i `y > BEDROCK+2`, żeby nie dziurawić powierzchni przypadkowo (otwory powierzchniowe robimy świadomie — 5.4).
- **Ridged noise** (`abs(noise)<próg`) daje naturalne, kręte wstęgi pustki; zwykły próg (`noise>próg`) daje obłe komory. Łączymy: warstwa wstęg (tunele) OR warstwa komór (blob).

#### 5.3.2 Worm / tunnel carving (łączniki i wejścia)

Dla czytelnych, „ręcznie wyglądających" tuneli i ramp wejściowych — algorytm 3D random-walk z kulistym pędzlem (jak Minecraft worm caves):

- Punkt startu deterministyczny z `feature_hash(region, "worm", i)`; długość `8–40 m`, promień `1.5–3.0 m` (malejący w „ogonie").
- Kierunek = wektor obracany szumem (`_worm_dir_noise`) — płynne zakręty, lekkie nurkowanie w dół (`pitch` bias −0.2, by tunel schodził pod ziemię).
- Każdy krok: `_carve_sphere(center, radius)` ustawia AIR. Worm łączy: (a) otwór wejściowy na zboczu z siecią 3D-noise, (b) komory między sobą (gwarantuje spójność — brak izolowanych pustek).
- **Gwarancja przejścia**: po carve robimy lekki flood-fill z punktu wejścia; komory nieosiągalne łączymy dodatkowym wormem (off-thread, tani — działamy na lokalnym buforze chunka + 1 chunk marginesu).

#### 5.3.3 Cellular automata (duże, organiczne komory)

Dla komór `crystal/den/ruins` — klasyczny CA na przekroju/objętości komory:

- Zasiej voxele `wall/air` losowo (`fill≈0.45`, seed z `feature_hash`).
- 4–5 iteracji reguły 4–5 (voxel→wall gdy ≥5 sąsiadów-wall, →air gdy ≤3) w obrębie bounding-boxa komory.
- Daje jamiste, naturalne komory z półkami i filarami. Stosowane lokalnie (komora ≤ 24³ voxeli), nie globalnie — tanio.

#### 5.3.4 Spójność między chunkami

- Carving liczony **na świecie (world-space x,y,z)**, nie chunk-lokalnie → wstęgi/komory przechodzą przez granice chunków bez szwów (3D noise jest ciągły).
- Wormy mogą startować w chunku N a kończyć w N+1 — `_carve_caves` zapisuje także do bufora sąsiadów przez istniejący mechanizm „pending edits" (jak obecne cross-chunk feature placement). Każdy chunk przy meshowaniu uwzględnia już zapisane edycje.
- Determinizm: wszystkie ziarna z `feature_hash(world_seed, region/chunk, salt)` — ten sam świat = te same jaskinie u hosta i klientów (host-authoritative, klient nie liczy własnych jaskiń — odbiera dane chunka jak dziś).

### 5.4 Wejścia: widoczne vs ukryte

| Tryb wejścia | Generacja | Sygnał dla gracza |
|---|---|---|
| **Widoczne (otwór zboczowy)** | worm wybija się do `surface_height` na stoku (slope > 0.5); placement drzew/głazów maskowany wokół otworu | ciemny otwór, czasem łuna (lava) / mróz (ice) / „cold breath" particles |
| **Widoczne (zapadlisko/sinkhole)** | pionowy worm przebija powierzchnię na płaskim terenie, krawędzie nieregularne | dziura w ziemi, opadająca rampa lub skok w dół |
| **Ukryte (za rudą)** | komora odcięta cienką ścianą (2–3 voxele) graniczącą z surowcem do wykopania | żyła rudy „wołająca" o kopanie; po przebiciu — komora |
| **Ukryte (sekretna ściana)** | fałszywa ściana z odmiennym tintem (`_tint_noise`), interakcja/uderzenie ją usuwa | subtelna różnica koloru/tekstury, dźwięk pustki |
| **Ukryte (podwodne)** | wejście pod `SEA_LEVEL` w jeziorze/rzece | trzeba zanurkować — ryzyko/nagroda |

Rozkład: dtier 0–1 → przewaga wejść widocznych (uczenie pętli). dtier 3+ → rośnie udział ukrytych (nagroda za eksplorację, crystal/ruins prawie zawsze ukryte).

### 5.5 Features: rudy, loot, moby, hazardy

#### 5.5.1 Rzadkie rudy i materiały (decorate pass)

Rudy spawnują w warstwie voxeli graniczącej z AIR jaskini (`_decorate_caves`), z szansą zależną od `distance_tier` i typu jaskini. Materiały wpięte do `LootService`/craftingu (te same id co loot powierzchniowy + jaskiniowe ekskluzywy):

| Materiał | Gdzie (typ/biom) | Bazowa szansa/komorę | Tier wymagany |
|---|---|---|---|
| Iron / Copper | wszędzie, small/deep | 35% | dtier 0+ |
| Silver | deep, dtier 1+ | 20% | dtier 1+ |
| Crystal Shard | **crystal cave** | 60% (żyły) | dtier 2+ |
| Frost Crystal | **ice cave** (Snow) | 45% | dtier 3+ |
| Obsidian / Sulfur | **lava cave** (Volcanic) | 40% | dtier 4+ |
| Ancient Fragment | **underground ruins** | 25% (+ chest) | dtier 2+ |
| Mythril (rare) | deep/crystal, dtier 4+ | 5% | dtier 4+ |

#### 5.5.2 Ukryty loot

- **Skrzynie** (prop pooled): 1 gwarantowana w komorze końcowej deep/crystal/ruins; ilvl = `dtier*2 + (biome.loot_tier-1)*2 + CAVE_BONUS(+1)` przez `LootService.roll()`.
- **Sekretne skarby**: za sekretną ścianą/pod wodą — wyższy `CAVE_BONUS(+2)`, większa szansa na afiks/set/socket (reużycie pełnego pipeline afiksów/setów/socketów/enchantów z LootService).
- **Stash mini-bossa**: drop mini-bossa (5.5.4) ma gwarantowany min. 1 item rzadkości ≥ Rare.

#### 5.5.3 Elite moby (in-cave)

- Jaskinie podnoszą limit elite lokalnie: dla aktywnego regionu z jaskinią `MAX_ACTIVE_ELITES` efektywnie +1 (z 2 → 3), tylko gdy gracz jest pod ziemią — pooling utrzymany.
- Elite dobierany z `EnemyDB.biome(id).enemy_spawn_table` filtrowany do `threat_tier == elite` (reużycie `_elite_pick()` z `WorldSpawner`), spawn w komorze środkowej, nie przy wejściu.
- ilvl elite: `+1` względem powierzchniowego tieru w tym regionie (jaskinia = trudniejsza).

#### 5.5.4 Mini-bossy

- Występują w komorze końcowej **deep/ruins/den** od dtier 2+, oraz gwarantowani w **monster den** (to ich „matecznik").
- To `EnemyResource` z `threat_tier == boss` ale skalą lokalną (HP/dmg poniżej dungeon-bossa). Realizowane przez istniejący `AIComponent` + `AbilityComponent` (telegraf przez `SkillResource.anticipation`), zamknięta arena = naturalne ściany komory.
- Drop: skrzynia + materiał ekskluzywny + szansa na recepturę/skill-unlock token (hook do `SkillTreeComponent.grants_skill`).

#### 5.5.5 Hazardy środowiskowe

Hazardy reużywają warstwę status effects z combat (`DamageService`): bleed/poison/freeze/burn/stun/weaken. Tick przez strefowy `Area3D`/voxel-tag, host-authoritative.

| Hazard | Typ jaskini | Efekt | Liczby |
|---|---|---|---|
| **Lawa** | lava cave, Volcanic | wejście = `burn`, kontakt = duży dmg | 18 dmg/0.5 s kontakt; burn 6 dmg/s ×3 s |
| **Trujący gaz** | swamp/den, deep | chmura → `poison`, redukcja widoczności | poison 4 dmg/s, stack do ×3; dim światła −40% |
| **Zimno** | ice cave, Snow | narastający `freeze`, slow → stun | +1 stack/2 s; stun przy 5 stacках; ognisko/źródło ciepła resetuje |
| **Zawalenia (cave-in)** | deep/ruins | spadające voxele po triggerze (płyta/waga) | 25 dmg + `stun 1 s`; deterministyczne miejsca |
| **Przepaście** | ice/deep | fall damage + soft-reset pozycji | dmg = (wysokość−safe) × k |
| **Kolce/pułapki** | underground ruins | `bleed` + dmg, telegraf wizualny | 12 dmg + bleed 3 dmg/s ×4 s |

Hazardy mają **kontrę przez build/loot** (np. odporność na ogień z setu, źródło ciepła vs zimno) — wpięcie w synergię skilli/lootu, zgodnie z celem „meaningful builds".

### 5.6 Połączenie jaskinia → dungeon (`DungeonGen`)

- Najgłębsze **underground ruins** i część **deep cave** zawierają w komorze końcowej **Portal/Descent** (prop interaktywny).
- Interakcja = teleport do instancjonowanego dungeonu generowanego przez istniejący `DungeonGen` (`DUNGEON_ORIGIN y=4000`), z parametrami przekazanymi z miejsca wejścia: `biome_id`, `distance_tier`, `loot_tier`, seed = `feature_hash(cave_id, "dungeon")`.
- Dzięki temu jaskinia (eksploracyjna, w terenie) i dungeon (instancjonowany, gridowy) tworzą jeden łuk: przedsionek-eksploracja → finał-instancja → boss → powrót portalem na powierzchnię w punkcie wejścia.
- Loot dungeonu skaluje tym samym `ilvl` co region wejścia + bonus dungeonu — spójne z `LootService`.

### 5.7 Mapowanie biom → typ jaskini

Reużycie `VoxelWorld.get_biome()` (docelowo 7 biomów) — typ jaskini wybierany z biomu wejścia + `distance_tier`.

| Biom | Główne typy jaskiń | Paleta / klimat | Charakterystyczny hazard | Sygnaturowy loot/mob |
|---|---|---|---|---|
| **Forest** | small, deep, monster den | wilgotna skała, mech, korzenie | zawalenia (lekkie) | Iron/Silver; den: wolves/spiders |
| **Plains** | small, deep | sucha skała, ziemia | przepaście | Iron/Copper; goblins |
| **Swamp** | deep, monster den | błoto, śluz, fosfor | **trujący gaz** | poison frogs/swamp beasts; Ancient Fragment |
| **Mountains** | deep (gęsta sieć), crystal | granit, żyły kryształu, pionowe szyby | przepaście, zawalenia | **Crystal Shard**; stone golems, wyverny (głęboko) |
| **Desert** | underground ruins, deep | piaskowiec, prefab-ruiny | kolce/pułapki, gaz | **Ancient Fragment**, sets; bandyci, sand worm (den) |
| **Snow** | **ice cave**, deep | lód, szron, zamarznięte jeziora | **zimno**, przepaście lodowe | **Frost Crystal**; ice wolves, frost spiders |
| **Volcanic** | **lava cave**, deep | bazalt, obsydian, jeziora lawy | **lawa**, burn ambient | **Obsidian/Sulfur**, Mythril; magma slimes, lava beasts, demony |

### 5.8 Oświetlenie i prezentacja

- Jaskinie są ciemne → czytelność przez **lokalne źródła**: emisyjne bloki (kryształy, lawa, grzyby fosforowe) + ograniczone światła dynamiczne.
- **Budżet świateł (4 GB / LOW)**: max **3–4** dynamiczne `OmniLight3D` aktywne naraz na gracza (pooling świateł — przypisywane do najbliższych źródeł, reszta emisyjna bez realnego światła). Tor pochodni/lampy gracza = 1 światło `follow`.
- Emisyjne voxele (crystal/lava/lava-cracks) — przez emission w materiale voxela (`_tint_noise` już istnieje jako hook na wariację koloru) — zero kosztu świateł dynamicznych.
- Particles ambient (kapanie, para lawy, mroźny oddech) — pooled, limit per typ, gęstość zależna od presetu.
- Mgła/zasięg widzenia w jaskini krótszy (camera fog) — sprzyja klimatowi i **wydajności** (mniej mesha widocznego).

### 5.9 Budżet wydajności (RTX 3050 4 GB)

- **Generacja**: carving to dodatkowy O(n) przebieg po voxelach chunka już budowanego — narzut ~15–30% czasu generacji chunka, akceptowalny off-thread (ten sam wątek streamingu, `near_dist=3/far_dist=5` bez zmian). Brak osobnych alokacji — piszemy do istniejącego bufora voxeli.
- **Pamięć**: jaskinie to AIR (usuwanie voxeli) — **nie zwiększają** liczby bloków; meshowanie wnętrz dokłada ściany komór, ale fog + krótszy zasięg w jaskini równoważy. Dekoracje (rudy/propy) liczone w istniejącym `MAX_PROPS_PER_CHUNK=35`.
- **Encje**: moby jaskiniowe dzielą pulę `WorldSpawner` (`MAX_ACTIVE=14`); pod ziemią faworyzujemy spawn w jaskini (mniej na powierzchni — bilans zerowy). Pooling elite jw. (lokalne +1).
- **Światła**: twardy cap 3–4 dynamiczne (5.8). Emisja zamiast świateł wszędzie gdzie się da.
- **Ryzyko `WORLD_HEIGHT=96` (48 m)**: dla wielopoziomowych jaskiń w Mountains/Volcanic zarezerwować pas `y ∈ [BEDROCK+2 .. surface−3]`; jeśli za płytko → rekomendacja podniesienia `WORLD_HEIGHT` (spójne z długiem #5 z audytu — pionowe góry).

### 5.10 Hooki implementacyjne (mapa do kodu)

| System | Plik/klasa | Co dodać |
|---|---|---|
| Generacja pustek | `src/world/Chunk.gd` → `_generate_data` | przebieg `_carve_caves` / `_fill_cave_fluids` / `_decorate_caves` po terenie, przed feature'ami |
| Szumy jaskiń | nowy `_cave_noise`, `_worm_dir_noise` w `VoxelWorld`/`Chunk` | `FastNoiseLite` seed `world_seed ^ 0xCAVE`, freq ≈0.045 |
| Determinizm | istniejący `feature_hash` / `region_seed` | ziarna worm/komora/loot/portal |
| Biom→typ | `VoxelWorld.get_biome()` | mapowanie z 5.7; typ jaskini = f(biom, `distance_tier`) |
| Spawn mobów | `WorldSpawner.gd` | flaga „region ma jaskinię" → lokalny elite +1, spawn w komorach; reużyć `_weighted_pick`/`_elite_pick` |
| Loot | `LootService` | `CAVE_BONUS` do ilvl; materiały jaskiniowe w tabelach |
| Hazardy/status | `DamageService` + strefy `Area3D` | burn/poison/freeze/stun/bleed jako tick stref hazardu |
| Dungeon link | `DungeonGen.gd` | portal-prop przekazuje `biome_id/dtier/loot_tier/seed`, generacja instancji `y=4000` |
| Oświetlenie | materiał voxela (emission) + pula `OmniLight3D` | emisyjne crystal/lava; cap 3–4 świateł, pooling |
| Encje w jaskini | `AIComponent` | matecznik (nest/den) = leash do komory; mini-boss przez `AbilityComponent`/`SkillResource` |
