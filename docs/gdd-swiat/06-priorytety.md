## 6. Content priority list

Cel rozdziału: uszeregować prace z sekcji 2–5 (biomy, skille, moby/ekosystem, jaskinie) wg **stosunku wpływu na poczucie PRZYGODY/PROGRESJI/ODKRYWANIA do kosztu** (mały zespół, RTX 3050 4 GB). Każdy element dostaje priorytet (P0–P3), uzasadnienie i kotwicę implementacyjną. Spójność nazw zgodna z GDD: biomy `forest`/`plains`/`swamp`/`mountains`/`desert`/`snow`/`volcanic`; statusy `bleed`/`poison`/`freeze`/`burn`/`stun`/`weaken`.

Założenie nadrzędne: **BLOKER #1 z audytu (0 plików `.tres` → pusty świat)** unieważnia ocenę wszystkich „silnikowych" funkcji. Dopóki nie ma treści-danych, najlepszy kod combat/loot/spawn produkuje pustą mapę. Dlatego ranking zaczyna się od minimalnego zestawu danych, który **w ogóle ożywia istniejące systemy**, a dopiero potem rozbudowuje świat.

---

### 6.1 Kryteria oceny

Każdy element punktowany 1–5 w trzech osiach, koszt jako mnożnik odwrotny:

| Oś | Co mierzy |
|---|---|
| **ADV** (Adventure) | Czy buduje poczucie przygody/eksploracji „pójdź dalej, zobacz co tam jest". |
| **PROG** (Progression) | Czy daje wymierne power-spike'i, buildy, długoterminowy cel. |
| **DISC** (Discovery) | Czy nagradza ciekawość — sekrety, warianty, „nigdy nie wiesz co znajdziesz". |
| **KOSZT** | Roboczogodziny + ryzyko techniczne + budżet 4 GB (1=tani, 5=drogi/ryzykowny). |

`Wynik = (ADV + PROG + DISC) / KOSZT`. Wysoki wynik = szybka duża wygrana.

---

### 6.2 Ranking główny (P0 → P3)

| # | Pakiet pracy | Sekcja | ADV | PROG | DISC | KOSZT | Wynik | Prio |
|---|---|---|---|---|---|---|---|---|
| 1 | **Seed treści MVP** (.tres: ~12 wrogów, 7 BiomeResource, 1 pełne drzewo skilli) | 1/2/3/4 | 5 | 5 | 4 | 1 | **14.0** | **P0** |
| 2 | **Selektor RING + 3 istniejące biomy w pierścieniach** (przepisany `get_biome`/`surface_height`, blending) | 2 | 5 | 4 | 4 | 2 | **6.5** | **P0** |
| 3 | **Pełne drzewo skilli 1 klasy (Berserker) CORE+ADVANCED + 6 statusów** | 3 | 2 | 5 | 4 | 2 | **5.5** | **P0** |
| 4 | **Ekosystem: neutral/passive wildlife + FLEE + RETALIATE** (stany AI, EcoSensor lite) | 4 | 5 | 1 | 3 | 2 | **4.5** | **P1** |
| 5 | **Jaskinie typu small/deep (carving 3D)** jako pierwszy podziemny content | 5 | 5 | 2 | 5 | 3 | **4.0** | **P1** |
| 6 | **4 brakujące biomy** (swamp/mountains/desert/volcanic — flora/paleta/teren) | 2 | 5 | 3 | 4 | 3 | **4.0** | **P1** |
| 7 | **Hostile sub-typy: elite + boss** (mnożniki, aura, drop-sygnatura) | 4 | 4 | 4 | 4 | 3 | **4.0** | **P1** |
| 8 | **Drzewa skilli pozostałych 10 klas** | 3 | 1 | 5 | 3 | 5 | **1.8** | **P2** |
| 9 | **Jaskinie specjalne** (crystal/ice/lava/underground ruins/monster den) | 5 | 4 | 3 | 5 | 4 | **3.0** | **P2** |
| 10 | **Herd/Territory + predator/prey (pełny ekosystem)** | 4 | 4 | 1 | 3 | 4 | **2.0** | **P2** |
| 11 | **Link jaskinia→DungeonGen (Portal/Descent)** | 5 | 3 | 4 | 3 | 3 | **3.3** | **P2** |
| 12 | **Geografia kierunkowa (sektory zamiast czystych okręgów)** | 2 | 3 | 0 | 2 | 4 | **1.3** | **P3** |
| 13 | **WORLD_HEIGHT 96→128 (pionowe góry, wielopoziomowe jaskinie)** | 2/5 | 3 | 1 | 3 | 5 | **1.4** | **P3** |

---

### 6.3 P0 — fundament (bez tego gra jest pusta lub bez celu)

**1. Seed treści MVP — NAJWIĘKSZA WYGRANA.** Rozwiązuje BLOKER #1: `EnemyDB`/`BiomeResource`/`SkillTree` skanują puste foldery → `WorldSpawner._activate_region` robi early-return → 0 wrogów. To czysta produkcja danych (zero nowego kodu): ~12 `EnemyResource` (warianty Goblin/Brute/Slinger już istnieją + 9 nowych), 7 `BiomeResource` z `enemy_spawn_table`, 1 `SkillTreeResource`. Koszt minimalny, efekt: martwy silnik staje się grywalną pętlą explore→fight→loot. **Bez tego żaden inny priorytet nie jest testowalny.** Hook: foldery skanowane przez `EnemyDB`/`SkillDB`, format zgodny z `EnemyResource`/`BiomeResource`/`SkillTreeResource`.

**2. Selektor RING.** Najważniejszy pojedynczy gameplay-fix dla „przygody". Obecnie biom = szum, więc las graniczy ze śniegiem i nie ma kierunku ekspansji — gracz nie czuje, że „idzie dalej w trudniejsze rejony". Przepisanie `get_biome()` na model dystans-ring (sekcja 2.3) + blending granic montuje progresję na osi promienia. Reużywa 3 istniejące biomy (verdant→forest/plains, frosthelm→snow, emberwaste→desert), więc dowozi efekt natychmiast bez nowych assetów. Hook: `VoxelWorld.get_biome`/`surface_height`/`_biome_weights`, `distance_tier()` jako modulator ilvl wewnątrz pierścienia.

**3. Pełne drzewo 1 klasy + statusy.** Progresja to rdzeń briefu („leveling = real power spikes"). Jedna klasa wzorcowa (Berserker, w pełni rozpisana w sekcji 3) z CORE (offense/defense/utility/mobility) + ADVANCED (spec A/B, ultimate) + 6 statusów (`bleed`/`poison`/`freeze`/`burn`/`stun`/`weaken` + `StatusComponent`/`StatusApplyResource` na hooku pkt 6 `DamageService`) dowodzi całego pipeline'u progresji i daje meaningful builds. Pozostałe klasy to potem powtarzalna produkcja danych wg tego wzorca. Hook: nowe `@export` w `PassiveNodeResource`/`SkillResource`, walidacja w `SkillTreeComponent`, milestone-granty w `LevelComponent`.

---

### 6.4 P1 — „najszybsze duże wygrane" po fundamencie

To warstwa, która zamienia poprawny szkielet w **żywy, ciekawy świat**. Kolejność wdrażania w obrębie P1: 4 → 6 → 5 → 7.

**4. Ekosystem lite (neutral/passive + FLEE/RETALIATE).** Najtańszy sposób, by świat przestał być strzelnicą. Dziś wszystko co spawnuje atakuje od razu (binarne `allegiance_hostile`). Dodanie kategorii `neutral`/`passive` + `aggro_mode` (RETALIATE/TERRITORIAL) + stanów `FLEE` w `AIComponent` daje uciekające króliki/jelenie i terytorialne dziki — natychmiastowy „Cube World vibe" przy małym koszcie (rozszerzenie istniejącego automatu stanów, bez nowych podsystemów ciężkich pamięciowo). Pełny ekosystem (herd/predator-prey, poz. 10) celowo odłożony do P2.

**6. 4 brakujące biomy.** Po działającym RING gracz po ~640 m wchodzi w „pustkę" (swamp/mountains/desert-tail/volcanic to dane do dorobienia). To największy zastrzyk DISCOVERY — nowe palety, flora, materiały, hazardy. Koszt to głównie produkcja assetów/danych, nie kod (selektor już je obsłuży). Hook: `BiomeResource` + `_biome_to_byte`/`_biome_at` w `Chunk.gd`.

**5. Jaskinie small/deep.** Pierwszy content podziemny — silny multiplikator DISCOVERY/ADVENTURE („co jest w tej dziurze?"). Świadomie tylko 2 najtańsze typy na start (carving 3D ridged/worm jako drugi przebieg w `Chunk._generate_data` off-thread, sekcja 5). Ryzyko: cap oświetlenia 3–4 `OmniLight3D` i budżet 4 GB — dlatego typy specjalne (crystal/ice/lava/ruins/den) idą do P2.

**7. Elite + boss.** Bez wyróżnionych wrogów progresja jest płaska. Elite/boss (mnożniki HP/dmg, aura, skala, drop-sygnatura — sekcja 4) tworzą cele eksploracji i pamiętne walki. Reużywa `EnemyResource` + limity `WorldSpawner` (elite=2). Tani, bo to dane + drobna logika aury.

---

### 6.5 P2 — pogłębienie (po grywalnej pętli end-to-end)

| Element | Dlaczego nie wcześniej |
|---|---|
| **8. Drzewa 10 klas** | Czysta produkcja wg wzorca z poz. 3; ogromny wolumen, ale powtarzalny i nie blokuje pętli. Robić przyrostowo (2–3 klasy/iterację). |
| **9. Jaskinie specjalne** | Wymagają nowych palet, hazardów (`zimno`/`lawa`/`gaz`) i logiki oświetlenia; wartość wysoka, ale koszt/ryzyko 4 GB realny. Dokładać biom po biomie po stabilizacji small/deep. |
| **10. Pełny ekosystem (herd/territory/predator-prey)** | `HerdComponent`/`TerritoryComponent`/`EcoSensor` + budżety kategorii pod `MAX_ACTIVE=14` — najcięższy CPU-owo podsystem. FLEE/RETALIATE z P1 dowozi 70% odczucia za 30% kosztu. |
| **11. Link jaskinia→Dungeon** | Domyka łuk eksploracji (przedsionek→instancja→boss), ale wymaga działających jaskiń (poz. 5) i treści dungeonu. Wysoka wartość PROG, więc górny P2. |

---

### 6.6 P3 — odłożyć (niski wpływ lub wysokie ryzyko/koszt)

| Element | Decyzja |
|---|---|
| **12. Geografia kierunkowa (sektory)** | „Nice to have" anty-monotonia. Czyste okręgi z jitterem (P0 poz. 2) wystarczą na długo. Odłożyć do polish-passu. |
| **13. WORLD_HEIGHT 96→128** | Najwyższe ryzyko: zwiększa pamięć/koszt chunków na 4 GB, dotyka rdzenia generacji i save'ów. Robić TYLKO gdy mountains/wielopoziomowe jaskinie udowodnią, że 48 m wysokości realnie ogranicza design. Do tego czasu projektować pionowość w istniejącym limicie. |

---

### 6.7 Najszybsze duże wygrane (TL;DR dla zespołu)

1. **Wyprodukuj `.tres` MVP (poz. 1)** — odblokowuje wszystko, niemal zero kodu, świat ożywa.
2. **Wdróż RING (poz. 2)** — jedna funkcja `get_biome` daje całe poczucie progresji dystansem.
3. **Dodaj FLEE/RETALIATE wildlife (poz. 4)** — tani „Cube World vibe", świat przestaje być strzelnicą.
4. **Włącz small/deep jaskinie (poz. 5)** — pierwszy prawdziwy hak DISCOVERY.

**Co świadomie odłożyć:** pełny ekosystem stadny, jaskinie specjalne, drzewa wszystkich klas, sektory kierunkowe i zmianę `WORLD_HEIGHT`. Wszystkie wymagają najpierw grywalnej, zamkniętej pętli explore→fight→loot→upgrade na minimalnym zestawie treści.

### 6.8 Definition of Done dla fazy P0

- W grze spawnują się wrogowie w ≥3 biomach ułożonych w pierścienie dystansem; ilvl rośnie z promieniem.
- 1 klasa ma w pełni grywalne drzewo CORE+ADVANCED z respec i ≥1 ultimate; statusy `bleed`/`poison`/`freeze`/`burn`/`stun`/`weaken` działają przez `DamageService`.
- Pętla explore→fight→loot→upgrade→unlock skill jest przechodzilna end-to-end na presecie LOW (RTX 3050 4 GB) bez przekroczenia budżetu pamięci.
