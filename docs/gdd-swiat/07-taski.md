## 7. Konkretne taski do implementacji

Rozdział przekłada projekt świata (rozdz. 02 biomy, 03 skille, 04 moby, 05 jaskinie) na **atomowe taski gotowe 1:1 do TaskCreate**. Każdy task ma: **Cel**, **Pliki/klasy**, **DoD / test headless**, **Ryzyko**. Taski są pogrupowane po systemie i uporządkowane wg zależności (góra → dół). Konwencje:

- **Test headless** = uruchamialny bez GUI: `godot --headless --script res://tests/<plik>.gd` (wzorzec istniejących testów stref/spawnu z audytu) ALBO scena testowa kończąca się `quit(0/1)`. Każdy test asercjami zwraca kod wyjścia.
- Spójność nazw (obowiązuje wszędzie): biomy `forest/plains/swamp/mountains/desert/snow/volcanic`, statusy `bleed/poison/freeze/burn/stun/weaken`, warstwy skilli `core/advanced`, gałęzie `offense/defense/utility/mobility/spec_a/spec_b`.
- Priorytet P0 = odblokowuje pusty świat (BLOKER #1 z audytu); P1 = rdzeń pętli; P2 = głębia/polish.
- Stałe referencyjne (zweryfikowane w kodzie): `WorldSpawner.MAX_ACTIVE=14`, `MAX_ACTIVE_ELITES=2`, `ELITE_REGION_CHANCE=0.14`, `REGION_SIZE=48`, `TICK_INTERVAL=0.5`, `EnemyDB.ENEMIES_DIR=res://data/db/enemies`, `BIOMES_DIR=res://data/db/biomes`, `SkillDB` skanuje `res://data/db/{skills,trees,passives,augments}`, `AIComponent.State{IDLE,PATROL,CHASE,ATTACK,FOLLOW}` + `allegiance_hostile:bool`, Godot 4.7.

Łącznie: **7 (biomy) + 9 (skille) + 8 (moby) + 7 (jaskinie) + 4 (loop) = 35 tasków**.

---

### 7.1 BIOMY (rozdz. 02 — model RING-dystans)

| # | Task | Cel | Pliki / klasy | DoD / test headless | Ryzyko |
|---|---|---|---|---|---|
| B1 | Stałe RING + `RING_BIOMES` + `BIOME_TERRAIN` | Wprowadzić parametry pierścieni i profile terenu per biom (2.2/2.5) | `VoxelWorld.gd` (sekcja parametrów biomów) | `RING_WIDTH=320`, `RING_BLEND_BAND=48`, `BIOME_RING_MAX=6`, `RING_BIOMES` ma 7 wpisów w kolejności forest→volcanic; `BIOME_TERRAIN` ma 7 kluczy z `base/amp/contrast`. Test: skrypt asertuje `RING_BIOMES.size()==7` i obecność wszystkich 7 kluczy w `BIOME_TERRAIN`. | Niskie (czyste dane) |
| B2 | Przepisać `get_biome()` na model dystansu | Biom = `floor(dist/RING_WIDTH)` z jitterem szumu (2.3) zamiast progów temp/hum | `VoxelWorld.gd::get_biome`, nowe `_raw_ring()` | Test: dla 7 promieni środkowych (160, 480, 800, 1120, 1440, 1760, 2200 m wzdłuż +X) `get_biome` zwraca kolejno forest…volcanic; ten sam punkt daje zawsze ten sam wynik (2× wywołanie == identyczne). | Średnie: zmiana stałych przemapowuje świat → migracja seeda (2.8 pkt 3); nie zmieniać po release |
| B3 | `biome_blend()` + blending wysokości | Gładkie granice (brak klifu/szwu) — wagi sąsiada w pasie 48 m (2.4/2.5) | `VoxelWorld.gd::biome_blend`, `surface_height`, `_height_for_profile` | Test: na granicy ring0/ring1 (x≈320±40) `surface_height` zmienia się monotonicznie bez skoku > 4 voxeli między sąsiednimi kolumnami; `biome_blend.t∈[0,0.5]`. | Średnie: koszt 2. profilu w pasie — pomijalny off-thread (2.8 pkt 4) |
| B4 | Rozszerzyć `Chunk` o 7 biomów i bloki | Mapowanie biom→bajt i blok powierzchni per biom (2.6/2.7) | `Chunk.gd::_biome_to_byte/_biome_at/_block_for`, `Blocks.Type` (+MUD, SANDSTONE, ICE, OBSIDIAN, BASALT, LAVA), `_solid_color` | Test: dla kolumny w swamp `_block_for` zwraca MUD na powierzchni, desert→SAND, volcanic→BASALT; `_biome_to_byte` mapuje 7 id na bajty 1..7. | Średnie: nowe bloki wymagają palety/emisji (B5); `_biomemap` zostaje 1 bajt/kolumna |
| B5 | Paleta + flora per biom | Kolory bloków z blendem + warianty propów (kaktus/martwe drzewo/grzyb) (2.7) | `Chunk.gd::_solid_color`, `_place_features/_place_tree/_place_bush/_place_rock`, `Blocks.biome_modulate` | Test: render headless 7 chunków (po 1 z centrum każdego ringu) → liczba propów ≤ `MAX_PROPS_PER_CHUNK(35)`; flora desert zawiera kaktus, snow martwe drzewo (sprawdzić licznik typów). | Średnie: budżet propów 35/chunk i 4 GB |
| B6 | 7× `BiomeResource.tres` (rozwiązuje BLOKER #1 — warstwa biomów) | Utworzyć dane biomów z polami spawn/loot/jaskinie | `res://data/db/biomes/{forest,plains,swamp,mountains,desert,snow,volcanic}.tres`, `BiomeResource.gd` (+`level_min/max`, `cave_types[]`, `dungeon_pool[]`, `weather`, `nest_chance`, `den_chance`) | Test: `EnemyDB.reload()` → `EnemyDB.biome(&"forest")` ≠ null dla wszystkich 7; każdy ma niepustą `enemy_spawn_table`, `loot_tier≥1`, `level_min<level_max` zgodne z tabelą 2.6. | **Wysokie**: bez tego spawner robi early-return = pusty świat |
| B7 | Spójność spawn vs render | `WorldSpawner._region_biome()` musi zwracać ten sam biom co `get_biome` (znika rozjazd audyt 1.1) | `WorldSpawner.gd::_region_biome`, `VoxelWorld.gd::distance_tier` (bez zmian) | Test: dla 200 losowych punktów `_region_biome(region_center) == get_biome(region_center)`; `distance_tier` rośnie monotonicznie z dystansem. | Niskie (oba czytają z RING) |

**Ryzyko przekrojowe biomów:** `WORLD_HEIGHT=96` za płytkie na mountains (base 30 + amp 64 ≈ 94) i wielopoziomowe jaskinie → osobny task **B-OPT** (podnieść do 128 z LOD-em) traktowany jako migracja wersji świata, NIE blokuje MVP.

---

### 7.2 SKILLE (rozdz. 03 — Core/Advanced + statusy + synergy)

| # | Task | Cel | Pliki / klasy | DoD / test headless | Ryzyko |
|---|---|---|---|---|---|
| S1 | Rozszerzyć `PassiveNodeResource` | Pola warstw/gałęzi/ranków (3.1) | `PassiveNodeResource.gd` (+`layer`, `branch`, `rank_max`, `grants_status_apply[]`, `spec_lock`) | Test: load istniejącego węzła `.tres` (jeśli jest) lub nowego — defaulty `layer=&"core"`, `rank_max=1` nie psują starych zasobów (backward-compat). | Niskie (nowe @export z defaultem) |
| S2 | `_allocated` bool→int (ranki) | Wielokrotna alokacja `rank_max>1`, `collect_modifiers` mnoży `value*rank` (3.1) | `SkillTreeComponent.gd::_allocated`, `allocate`, `collect_modifiers` | Test: alokuj węzeł `rank_max=3` trzykrotnie → `collect_modifiers` zwraca modyfikator ×3; 4. alokacja odrzucona. | Średnie: zmiana typu — sprawdzić serializację w `SaveData` |
| S3 | Metadane warstw w `SkillTreeResource` | `core_branches/advanced_branches/advanced_unlock_level/spec_choice_exclusive/resource_kind` (3.2) | `SkillTreeResource.gd` | Test: nowy tree `.tres` ma `advanced_unlock_level=25`, 4 core + 2 advanced gałęzie. | Niskie |
| S4 | Rozszerzyć `SkillResource` | `category/status_on_hit/combo_consumes/combo_bonus_mult/iframe_window` (3.3) | `SkillResource.gd` | Test: skill z `category=&"ultimate"` i `status_on_hit=[burn]` ładuje się; defaulty nie psują istniejących skilli. | Niskie |
| S5 | Walidacja warstw/spec w komponencie | `advanced` wymaga lvl≥25; hard-spec blokuje drugą gałąź; `grants_skill`/`grants_status_apply` przy alokacji (3.4) | `SkillTreeComponent.gd::cannot_allocate_reason`, `allocate` | Test: alokacja węzła `layer=&"advanced"` przy lvl 24 → reason ≠ ""; przy lvl 25 → OK; przy `spec_choice_exclusive` i wziętym spec_a blokada spec_b. | Średnie: interakcja z respec |
| S6 | Milestone-granty w `LevelComponent` | Bramki progowe lvl {1,5,10,15,20,25,60} emitują `milestone_reached` (3.5), krzywa XP/cap99 bez zmian | `LevelComponent.gd::_grant_points_for_level`, sygnał `milestone_reached(lvl,kind)` | Test: symuluj level-up 1→60, zlicz emisje `milestone_reached` na progach = 7; cap pozostaje 99, suma punktów zgodna z tabelą 3.5. | Średnie: encja musi obsłużyć sygnał (grant_skill/UI) |
| S7 | Nowy `StatusComponent` + `StatusApplyResource` | Warstwa 6 statusów: DoT tick 0.5 s, hard-CC flagi, weaken jako provider StatModifier (5.1–5.3) | nowe `components/StatusComponent.gd`, `data/resources/StatusApplyResource.gd`; hook w `DamageService.gd` (pkt 6 `on_hit_effects`) | Test headless: nałóż bleed (mag 0.04, 6 s) na atrapę z HP=100 → po 6 s zadane ≈ 12×(snapshot×0.04); freeze ustawia flagę blokady akcji; weaken dodaje StatModifier `damage -20%`/`taken +15%` i zdejmuje po wygaśnięciu. | **Wysokie**: nowy per-tick — trzymać 0.5 s tick + pooling (budżet 4 GB); snapshot dmg by uniknąć desyncu host-authoritative |
| S8 | Combo / synergy w skillach | `combo_consumes`/`combo_bonus_mult` + `has_status/consume_status` (rozdz. 6) | `SkillResource.gd`, `StatusComponent.gd::has_status/consume_status`, `AbilityComponent.gd` | Test: cel z freeze + cios z `combo_consumes=&"freeze"` → shatter dmg = 15% max_hp i status zdjęty; burn+oil → tick ×2. | Średnie: kolejność rozliczenia w `DamageService` |
| S9 | Dane skilli P0: Berserker + Mag (rozwiązuje BLOKER #1 — warstwa skilli) | Wyprodukować pełne drzewa wzorcowe (rozdz. 7: CORE+ADVANCED+ulti) | `res://data/db/trees/{berserker,mag}.tres`, `res://data/db/passives/...`, `res://data/db/skills/...` (rozlup, szarza, krwawa_laznia, tornado_stali, ...) | Test: `SkillDB` ładuje 2 drzewa; każde ma 4 core + 2 advanced gałęzie, ≥1 movement/defensive/utility w CORE, 2 ultimate (`tags=[&"ultimate"]`, `min_level=60`), keystone spec na lvl 25. Symulacja buildu „Krwawy Młyn" osiąga keystone Pakt Krwi (x1.25 MORE). | **Wysokie**: bez węzłów drzewo puste; reszta 9 klas wg wzorca po slice |

---

### 7.3 MOBY (rozdz. 04 — ekosystem hostile/neutral/passive)

| # | Task | Cel | Pliki / klasy | DoD / test headless | Ryzyko |
|---|---|---|---|---|---|
| M1 | Rozszerzyć `EnemyResource` | Taksonomia + staty + herd/flee/diet/nest/den/drop (4.2) | `EnemyResource.gd` (enum `MobCategory`,`AggroMode` + pola z 4.2) | Test: load `.tres` z `category=NEUTRAL`,`aggro_mode=RETALIATE`,`diet=[&"rabbit"]` → pola czytane; stare pola (`id/scene/base_loot_tier`) zachowane. | Niskie (addytywne) |
| M2 | `AIComponent`: `faction` zamiast boola | `faction:StringName` (ENEMY/WILDLIFE), kompat: ENEMY==hostile (4.3/4.10) | `AIComponent.gd::allegiance_hostile→faction`, `_resolve_target`, `set_allegiance_ally` | Test: encja `faction=&"ENEMY"` celuje w gracza; `&"WILDLIFE"` nie celuje dopóki brak triggera; istniejący pet-path (ALLY/FOLLOW) działa. | **Wysokie**: dotyka rdzenia AI i petów — utrzymać 1:1 mapowanie z `Enemy.State` |
| M3 | Nowe stany AI | `TERRITORIAL/FLEE/HERD/HUNT/RETURN` z priorytetami (4.3) | `AIComponent.gd::State` (rozszerzyć enum), `tick`, nowe `_territorial/_flee/_herd/_hunt/_return` | Test: mob `flee_hp_pct=0.25` przy HP 20% wchodzi w FLEE (oddala się od gracza); territorial po wejściu gracza w `territory_radius` ostrzega, po uderzeniu → CHASE; priorytet FLEE > CHASE > HUNT. | **Wysokie**: maszyna stanów — ryzyko zakleszczeń; testować przejścia |
| M4 | `HerdComponent` | Stado: leader/center/cohesion + `herd_alert` propagacja aggro (4.4/4.5) | nowe `components/HerdComponent.gd`, hook w `WorldSpawner` | Test: spawn stada 5 membrów; uderzenie 1 membera → `herd_alert` → wszyscy w `herd_cohesion` w CHASE (deer uciekają, boar kontratakują). | Średnie: tick 0.5 s zsynch ze spawnerem; budżet |
| M5 | `EcoSensor` (predator/prey w spawnerze) | Drapieżniki nie skanują same — spawner podaje listę prey per region (4.4/4.5) | `WorldSpawner.gd` (sekcja EcoSensor), `AIComponent.gd::HUNT` | Test: w regionie z wolf(diet=rabbit)+rabbit → wolf wchodzi w HUNT na rabbit; po „zjedzeniu" regen HP + `hunt_cooldown=20 s`; atak gracza nadpisuje HUNT→CHASE. | Średnie: koszt query — trzymać per-region nie per-mob |
| M6 | Budżety kategorii + spawn stad/struktur w `WorldSpawner` | Pod-pule hostile~8/neutral~4/passive~2 z MAX_ACTIVE=14; nest/den z seeda (4.6) | `WorldSpawner.gd` (filtr kategorii, `_spawn_herd`, struktury nest/den), `BiomeResource.nest_chance/den_chance` | Test: aktywacja regionu forest → liczba aktywnych ≤14, rozkład kategorii ~60/30/10; den deterministyczny z seeda (2× aktywacja == ten sam wynik). | **Wysokie**: nie przekroczyć MAX_ACTIVE; pooling stad jako N jednostek dzielących 1 HerdComponent |
| M7 | Elite/Boss — wizual + mechanika | Skala/aura/HP-bar + mnożniki HP×3.5/×12, dmg×1.8/×2.5, fazy bossa (4.9) | `WorldSpawner.gd::_elite_pick` (istnieje), `Enemy.gd`, `AbilityComponent.gd`, `LootService.roll_boss` | Test: elite ma skalę 1.4 i HP ≈ baza×3.5; boss `hostile_tier=4` ma pasek HP i zmianę mechanik na progach 66/33%; respektowany `MAX_ACTIVE_ELITES=2`. | Średnie: limit elite + `ELITE_REGION_CHANCE=0.14` |
| M8 | Dane mobów (rozwiązuje BLOKER #1 — warstwa mobów) | ~40 `EnemyResource.tres` wg tabeli 4.8, wpięte w `enemy_spawn_table` 7 biomów | `res://data/db/enemies/*.tres`, aktualizacja `BiomeResource.enemy_spawn_table` (B6) | Test: `EnemyDB.reload()` → wszystkie id z tabeli 4.8 ładowalne; każdy biom ma niepustą pulę hostile, dystrybucja zgodna z 4.7 (volcanic bez wildlife, forest pełny ekosystem). | **Wysokie**: ilość treści; priorytet Forest/Plains do slice |

---

### 7.4 JASKINIE (rozdz. 05 — proceduralne, eksploracyjne)

| # | Task | Cel | Pliki / klasy | DoD / test headless | Ryzyko |
|---|---|---|---|---|---|
| C1 | Szumy jaskiń + maska głębokości | `_cave_noise`/`_worm_dir_noise`, carve tylko `BEDROCK+2 < y < surface-CAVE_MIN_DEPTH(3)` (5.3.1/5.10) | `VoxelWorld.gd`/`Chunk.gd` (nowe `FastNoiseLite` seed `world_seed^0xCAVE`, freq≈0.045) | Test: szum 3D deterministyczny (ten sam seed/pozycja == identyczna gęstość); maska nie carve'uje powierzchni (y≥surface-3 zawsze solid). | Średnie |
| C2 | `_carve_caves` (3D noise + ridged) | Drugi przebieg w `_generate_data` PO terenie, PRZED feature'ami (5.3) | `Chunk.gd::_generate_data`, nowe `_carve_caves` | Test: chunk w mountains (CAVE_THRESHOLD wyższy) ma >X voxeli AIR poniżej surface; chunk forest mniej; powierzchnia nienaruszona. | **Wysokie**: narzut 15–30% czasu generacji — off-thread, bez nowych alokacji |
| C3 | Worm carving + cross-chunk + flood-fill | Tunele/wejścia random-walk, łączenie komór, gwarancja przejścia (5.3.2/5.3.4) | `Chunk.gd::_carve_worm/_carve_sphere`, mechanizm „pending edits" cross-chunk, `feature_hash` | Test: worm startujący w chunku N zapisuje AIR w N+1 (cross-chunk); flood-fill z wejścia osiąga wszystkie komory (brak izolowanych pustek). | **Wysokie**: spójność granic chunków, determinizm |
| C4 | `_fill_cave_fluids` + `_decorate_caves` | Lawa/woda poniżej progów + rudy/kryształy w warstwie granicznej AIR (5.3/5.5.1) | `Chunk.gd::_fill_cave_fluids/_decorate_caves`, `Blocks.Type` (LAVA z B4) | Test: lava cave w volcanic ma LAVA poniżej `LAVA_LEVEL`; rudy spawnują wg tabeli 5.5.1 (crystal cave: Crystal Shard ~60%); propy ≤ `MAX_PROPS_PER_CHUNK`. | Średnie: budżet propów współdzielony |
| C5 | Wejścia widoczne/ukryte + biom→typ | Otwór zboczowy/sinkhole/za-rudą/sekretna-ściana/podwodne; mapa biom→typ jaskini (5.4/5.7) | `Chunk.gd` (placement wejść, maska propów wokół otworu), `VoxelWorld.get_biome` (mapa 5.7) | Test: forest→{small,deep,monster_den}, snow→ice cave, volcanic→lava cave; udział ukrytych wejść rośnie z `distance_tier`. | Średnie |
| C6 | Hazardy jaskiniowe (status przez strefy) | Lawa/gaz/zimno/zawalenia/przepaście/kolce → statusy z combat (5.5.5) | nowe strefy `Area3D`/voxel-tag, `DamageService` (tick), `HazardZone.gd` (istnieje) | Test: wejście w strefę lawy → burn (6 dmg/s ×3 s) + 18 dmg/0.5 s kontakt; zimno +1 stack/2 s, stun przy 5 stackach; host-authoritative tick. | Średnie: reużycie StatusComponent (S7) |
| C7 | Spawn w jaskini + link do `DungeonGen` | Lokalny elite +1 pod ziemią, mini-boss w komorze końcowej, portal-prop → instancja (5.5.3/5.6) | `WorldSpawner.gd` (flaga „region ma jaskinię", `_elite_pick`), `DungeonGen.gd` (portal przekazuje `biome_id/dtier/loot_tier/seed`) | Test: region z jaskinią → efektywny `MAX_ACTIVE_ELITES` 2→3 tylko pod ziemią; interakcja z portalem teleportuje do instancji `y=4000` z poprawnym ilvl (`dtier*2+(loot_tier-1)*2+CAVE_BONUS`). | Średnie: pooling elite; spójność ilvl z LootService |

---

### 7.5 LOOP / INTEGRACJA (spięcie pętli explore→fight→loot→upgrade→repeat)

| # | Task | Cel | Pliki / klasy | DoD / test headless | Ryzyko |
|---|---|---|---|---|---|
| L1 | `LootService`: drop_signature + CAVE_BONUS + roll_boss | Drop sterowany sygnaturą moba i bonusem jaskini; pula bossa (4.2/4.9/5.5.2) | `LootService.gd` (`drop_signature`, `guaranteed_drops`, `roll_boss`, `CAVE_BONUS`) | Test: mob `drop_signature=&"pelt_meat"` dropi hide+raw_meat; skrzynia jaskiniowa ma ilvl+CAVE_BONUS(+1/+2); `roll_boss(&"boss_volcanic", ilvl)` zwraca ≥1 item ≥Rare. | Średnie: spójność ilvl między systemami |
| L2 | Spójność ilvl world↔cave↔dungeon | Jeden wzór `ilvl=dtier*2+(loot_tier-1)*2(+CAVE_BONUS)` we wszystkich źródłach (02/04/05) | `WorldSpawner.gd`, `LootService.gd`, `DungeonGen.gd` | Test: dla tego samego punktu wejścia ilvl powierzchni < ilvl jaskini < ilvl dungeonu (monotonicznie); ten sam seed == ten sam loot. | Niskie (jeden wzór) |
| L3 | Determinizm + save/load całości | RING biomy + jaskinie + spawn + drzewa skilli przeżywają save/load (host-authoritative) | `SaveManager.gd`, `SaveData.gd` (ranki S2), `VoxelWorld`, `WorldSpawner` | Test: zapis → reload → ten sam biom/jaskinia/spawn w 50 punktach; alokowane ranki skilli i wybrana spec zachowane. | **Wysokie**: zmiana `_allocated` typu (S2) + nowe pola muszą serializować |
| L4 | Smoke test pętli (vertical slice) | E2E: start w forest → walka → loot → level→węzeł → wejście do jaskini → elite → portal | scena `tests/loop_smoke.gd` spinająca wszystkie autoloady | Test headless: spawn gracza w (0,0), 60 s symulacji — asercje: ≥1 mob zabity, ≥1 item w inventory, ≥1 level-up, jaskinia osiągalna ≤300 m, brak błędów w logu (`push_error` count==0). | **Wysokie**: integracja wszystkich systemów; uruchamiać po każdym P0 |

---

### 7.6 Kolejność wdrożenia (krytyczna ścieżka pod vertical slice)

1. **P0 — odblokowanie świata:** B1→B2→B6 (biomy danymi), M1→M8 (Forest/Plains mob data), S1→S4→S9 (Berserker+Mag drzewa). Po tym świat przestaje być pusty (BLOKER #1 zamknięty).
2. **P1 — rdzeń pętli:** B3→B4→B7, M2→M3→M6, S5→S6→S7, C1→C2→C3, L1→L2.
3. **P2 — głębia/polish:** B5, M4→M5→M7, S8, C4→C7, L3, B-OPT (WORLD_HEIGHT 128).
4. **Bramka jakości:** L4 (smoke test) uruchamiany po każdym ukończonym P0/P1 — zielony = slice grywalny.

Każdy task jest atomowy i ma jednoznaczne DoD — gotowy do skopiowania do TaskCreate jako osobny ticket.
