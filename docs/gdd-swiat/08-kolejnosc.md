## 8. Kolejność wdrażania

Cel rozdziału: ułożyć systemy z sekcji 2–7 w **fazy (milestones) z jawnymi zależnościami**, tak by każda faza dowoziła grywalny przyrost wartości wzdłuż pętli docelowej (`explore → fight → loot → upgrade → unlock skills → find cave → clear dungeon → fight elite → craft → travel further → harder biome → repeat`), nie psując istniejącej gry (single-player **i** co-op host-authoritative) ani kontraktu testów. Zasada nadrzędna: **najpierw odblokować świat (rozwiązać BLOKER #1 — pusty świat), bo bez treści `.tres` wszystkie pozostałe systemy są martwym silnikiem** (audyt 1.4). Każda kolejna faza buduje na poprzedniej i pozostaje regrywalna po mergu.

Spójność nazewnictwa (jak w całym GDD): biomy `forest`, `plains`, `swamp`, `mountains`, `desert`, `snow`, `volcanic`; statusy `bleed`, `poison`, `freeze`, `burn`, `stun`, `weaken`.

---

### 8.1 Zasady prowadzenia prac (obowiązują w każdej fazie)

1. **Vertical slice nad horyzontalnym.** Każda faza kończy się stanem grywalnym end-to-end (uruchom grę → zobacz efekt), nie „połową systemu we wszystkich biomach".
2. **Determinizm to twardy kontrakt.** Każda zmiana generacji/spawnu MUSI być czystą funkcją `(world_x, world_z, FEATURE_SEED)` + `feature_hash`. Warunek SaveManager/co-op (host-authoritative): klient i host z tym samym seedem dają identyczny świat. Brak determinizmu = blok mergu.
3. **Co-op-safe by default.** Logika świata, AI, lootu, statusów rozstrzygana po stronie hosta; klient dostaje wynik. Każda nowa encja/komponent ma jawnie określone, kto jest autorytatywny.
4. **Feature flag + fallback.** Każdy duży podsystem za flagą (`Settings`/`debug`), domyślnie ON dopiero po DoD fazy. Stara ścieżka (3 biomy, brak jaskiń) działa do czasu zielonej fazy — pozwala mergować przyrostowo.
5. **Budżet 4 GB jako kryterium akceptacji, nie afterthought.** Każda faza ma limit aktywnych encji/węzłów i pooling; profilowanie na RTX 3050 (preset LOW) jest częścią DoD, nie osobnym taskiem na koniec.
6. **Kontrakt testów rośnie z fazą.** Każda faza dokłada testy determinizmu (ten sam seed → ten sam wynik) i smoke-test grywalności; CI nie może zejść poniżej zielonego.

---

### 8.2 Mapa zależności (co od czego)

| System (sekcja) | Zależy od (twardo) | Odblokowuje |
|---|---|---|
| Treść `.tres` enemy/biome/skill (BLOKER #1) | — (fundament) | spawn, biomy, skille — całą resztę |
| Biomy RING 7× (sek. 2) | `WORLD_HEIGHT 96→128`, treść biome `.tres` | dystrybucję mobów per biom, typy jaskiń |
| Skille CORE/ADVANCED + StatusComponent (sek. 3) | treść skill `.tres`, hook pkt6 `DamageService` | power spikes, combo, kontry hazardów jaskiń |
| Ekosystem mobów (sek. 4) | nowe stany `AIComponent`, biomy RING (dystrybucja) | predator/prey, herd, flee, neutral/passive |
| Jaskinie proceduralne (sek. 5) | biomy RING, carving w `Chunk._generate_data`, `WORLD_HEIGHT 128` | mob dens, loot CAVE_BONUS, link → dungeon |
| Dungeony jako finał jaskiń | jaskinie (Portal/Descent), `DungeonGen` (istnieje) | domknięcie pętli „clear dungeon → elite/boss" |

Ścieżka krytyczna: **`.tres` → biomy RING → (skille ∥ ekosystem) → jaskinie → dungeon-link**. Skille i ekosystem są równoległe po biomach (różne pliki, brak kolizji), więc dają się robić w dwóch nurtach.

---

### 8.3 Fazy wdrożenia

#### Faza 0 — Fundament treści (rozwiązanie BLOKERA #1)
- **Cel:** świat przestaje być pusty — pojawiają się wrogowie i działa istniejący silnik (combat/loot/skill) na realnych danych. Pętla `fight → loot` żyje na obecnych 3 biomach.
- **Zawartość:**
  - Wyprodukować minimalny komplet `.tres`: ≥1 `BiomeResource` z niepustą `enemy_spawn_table` na każdy istniejący biom (`verdant`/`emberwaste`/`frosthelm`), ≥6 `EnemyResource` (warianty Goblin/Brute/Slinger + 3 wildlife placeholdery), ≥1 `SkillTreeResource` z kilkoma `PassiveNodeResource` dla 1 klasy referencyjnej (Berserker z sek. 3).
  - Smoke-test ścieżki: `EnemyDB` skanuje niepuste foldery → `_activate_region` NIE robi early-return → wrogowie spawnują.
- **DoD:** uruchomienie gry → w promieniu spawnu spawnują wrogowie, da się ich zabić, leci loot, można wydać punkt skilla; SP i co-op identyczny świat dla tego samego seeda; smoke-test w CI zielony.
- **Ryzyka:** złe ścieżki/format `.tres` → ciche puste tabele (mitigacja: walidator ładowania logujący liczbę wczytanych zasobów); rozjazd seedów host/klient (mitigacja: test determinizmu spawnu).

#### Faza 1 — Świat RING (7 biomów wg dystansu)
- **Cel:** „explore" i „travel further → harder biome" — biom = funkcja dystansu, 7 dużych odseparowanych stref w pierścieniach trudności (sek. 2).
- **Zawartość:**
  - `WORLD_HEIGHT 96 → 128` (audyt 9: pod pionowe góry i wielopoziomowe jaskinie) — przeprofilować budżet pamięci na 4 GB PRZED resztą fazy.
  - Przepisać `VoxelWorld.get_biome()` na model RING (`RING_WIDTH`, `_biome_weights()`, blending granic) + profile `surface_height()` per biom; dodać brakujące biomy `swamp`/`mountains`/`volcanic` jako `.tres`.
  - Powiązać biom z `distance_tier()` (biom i tier idą w parze) — `WorldSpawner.ilvl` skaluje monotonicznie z dystansem.
- **DoD:** marsz od spawnu w linii prostej przecina biomy w kolejności Forest→…→Volcanic, granice gładkie (brak klifu/szwu kolorów), trudność i ilvl rosną z dystansem; determinizm utrzymany (test: ten sam seed → ta sama mapa biomów); brak regresu FPS na LOW.
- **Ryzyka:** szew/klif na granicach (mitigacja: `RING_BLEND_BAND`), 128 wys. przebija budżet (mitigacja: chunk pooling, `near/far` bez zmian), rozjazd ze starymi save'ami (mitigacja: bump wersji save + regen świata).

#### Faza 2a — Skille progression-heavy + statusy (nurt A)
- **Cel:** „unlock skills → upgrade" z REAL POWER SPIKES; statusy zasilają combat i przyszłe kontry hazardów.
- **Zawartość:**
  - Rozszerzyć `PassiveNodeResource`/`SkillTreeResource`/`SkillResource` (nowe `@export` z sek. 3), walidacja `layer`/`spec` w `SkillTreeComponent`, milestone-granty w `LevelComponent`.
  - Wyprodukować pełne drzewa CORE (offense/defense/utility/mobility) + ADVANCED (spec A/B unlock lvl 25, ultimate lvl 60) dla klas — start od Berserkera (wzorzec), potem reszta kanonu ContentDB.
  - `StatusComponent` + `StatusApplyResource` wpięte w hook pkt6 `DamageService`; 6 statusów + tabela combo (freeze→shatter, burn+oil, bleed+execute, poison+weaken, stun→burst).
- **DoD:** levelowanie daje odczuwalne skoki mocy; respec (węzeł/gałąź/pełny/zmiana spec) działa za walutę; statusy nakładają się i tickują po stronie hosta, combo wyzwala efekty; co-op: statusy/skille rozstrzygane przez hosta.
- **Ryzyka:** balans (mitigacja: liczby z sek. 3 jako baseline + tuning pass), desync statusów w co-op (mitigacja: host-authoritative tick + replikacja stanu, nie eventów).

#### Faza 2b — Ekosystem mobów (nurt B, równolegle do 2a)
- **Cel:** „fight" przestaje być jednorodne — Hostile/Neutral/Passive, predator/prey, herd, flee; logiczny spawn per biom.
- **Zawartość:**
  - Rozszerzyć `EnemyResource` (category/aggro_mode/faction/territory/herd/flee/diet/nest-den/drop_signature); dodać stany `AIComponent` (TERRITORIAL/FLEE/HERD/HUNT/RETURN) z tabelą triggerów/priorytetów.
  - Nowe komponenty `HerdComponent`/`TerritoryComponent`/`EcoSensor`; algorytmy predator/prey, herd, flee, nest/den.
  - Rozszerzyć `WorldSpawner` o budżety kategorii (~8 hostile / 4 neutral / 2 passive pod `MAX_ACTIVE=14`), spawn stad i struktur; pełna dystrybucja ~40 mobów per biom (sek. 4).
- **DoD:** w każdym biomie spawnują właściwe typy; passive uciekają, neutral retaliują/bronią terytorium, hostile agresywne; stada trzymają się razem; limity aktywnych encji nieprzekroczone; determinizm spawnu utrzymany.
- **Ryzyka:** koszt AI/sensorów na 4 GB (mitigacja: tick co 0.5 s, pooling, LOD zachowań przy odległości), zalanie ekranu encjami (mitigacja: twarde budżety kategorii).

#### Faza 3 — Jaskinie proceduralne (eksploracja w głąb)
- **Cel:** „find cave" — jaskinie jako część eksploracji (7 typów per biom), z rudami, ukrytym lootem, elite/mini-bossami i hazardami.
- **Zawartość:**
  - Drugi przebieg carvingu w `Chunk._generate_data` (3D ridged noise / worm-walk / cellular), off-thread, spójność cross-chunk i determinizm przez `feature_hash`.
  - Wejścia widoczne/ukryte; features: rudy (tabela szans/tier), loot przez `LootService` z `CAVE_BONUS`, hazardy (lawa/gaz/zimno/zawalenia/przepaście/pułapki) — kontrowane buildem/lootem z Fazy 2a.
  - Monster den/elite z `WorldSpawner` (reużycie ekosystemu z 2b); oświetlenie cap 3–4 `OmniLight3D` + emisja.
- **DoD:** w każdym biomie generują się jaskinie właściwego typu (sek. 5.7), wejścia odnajdywalne, hazardy działają i mają kontrę, loot/elite obecne; brak dziur w terenie cross-chunk; FPS na LOW utrzymany.
- **Ryzyka:** szwy/dziury między chunkami (mitigacja: determinizm + carving na bazie globalnych współrzędnych), koszt off-thread + światła na 4 GB (mitigacja: cap świateł, batch generacji).

#### Faza 4 — Domknięcie pętli (jaskinia → dungeon → elite/boss)
- **Cel:** zamknąć pełną pętlę docelową: „clear dungeon → fight elite → craft → travel further".
- **Zawartość:**
  - Portal/Descent w finałowych komorach (deep/underground ruins) → teleport do `DungeonGen` (`DUNGEON_ORIGIN y=4000`) z parametrami `biome_id`/`distance_tier`/`loot_tier`/seed = `feature_hash(cave_id,"dungeon")`.
  - Boss/elite w dungeonie, loot skalowany `ilvl` regionu wejścia + bonus dungeonu (spójnie z `LootService`); powrót portalem do punktu wejścia.
  - Spięcie z craftingiem/upgrade (jeśli w zakresie) — domknięcie „loot → upgrade → craft".
- **DoD:** gracz wchodzi z jaskini do instancji, czyści ją, ubija elite/bossa, dostaje skalowany loot, wraca na powierzchnię; pętla regrywalna i działa w co-op (instancja host-authoritative).
- **Ryzyka:** instancja vs świat persistence w co-op (mitigacja: host trzyma stan instancji), trudność bossa rozjechana z ilvl (mitigacja: skalowanie z `distance_tier`).

#### Faza 5 — Polish, balans, tuning skali
- **Cel:** dowieźć „poczucie PRZYGODY/PROGRESJI/ODKRYWANIA" jakościowo.
- **Zawartość:** tuning krzywych poziomów/lootu/spawnu, ambient/pogoda per biom, balans statusów i combo, audyt budżetu 4 GB end-to-end, rozszerzenie testów determinizmu na pełen łuk biom→jaskinia→dungeon.
- **DoD:** pełen przebieg Forest→Volcanic bez regresów wydajności/determinizmu; subiektywna ocena „flow progresji" pozytywna; CI zielony z rozszerzonym kontraktem testów.
- **Ryzyka:** scope creep (mitigacja: zamrożenie zakresu, balans iteracyjnie po danych z grania).

---

### 8.4 Tabela master faz

| Faza | Cel (pętla) | Kluczowa zawartość | Zależy od | DoD (skrót) | Główne ryzyko |
|---|---|---|---|---|---|
| **0** | fight → loot | komplet startowych `.tres` (BLOKER #1) | — | wrogowie spawnują, loot/skill działają | puste tabele / desync seed |
| **1** | explore, harder biome | RING 7 biomów, `WORLD_HEIGHT 128`, blending | F0 | marsz przecina 7 biomów, trudność rośnie | szew granic, budżet 128 |
| **2a** | unlock skills → upgrade | CORE/ADVANCED, `StatusComponent`, combo | F0 | power spikes, statusy/combo, respec | balans, desync statusów |
| **2b** | fight (ekosystem) | kategorie mobów, stany AI, dystrybucja | F0, F1 | hostile/neutral/passive, herd/flee | koszt AI 4 GB, zalanie encji |
| **3** | find cave | carving 3D, hazardy, rudy, loot CAVE_BONUS | F1, F2a, F2b | jaskinie per biom, hazardy z kontrą | szwy cross-chunk, koszt świateł |
| **4** | clear dungeon → elite | Portal/Descent → `DungeonGen`, boss, loot | F3 | pełna pętla regrywalna w co-op | persistence instancji, skalowanie bossa |
| **5** | repeat / przygoda | balans, ambient, audyt budżetu, testy | F0–F4 | przebieg Forest→Volcanic bez regresów | scope creep |

---

### 8.5 Powiązanie z pętlą docelową

Pętla `explore → fight → loot → upgrade → unlock skills → find cave → clear dungeon → fight elite → craft → travel further → harder biome → repeat` materializuje się przyrostowo: **F0** uruchamia `fight → loot`; **F1** dokłada `explore` i `travel further → harder biome`; **F2a** dokłada `upgrade / unlock skills` (power spikes, statusy); **F2b** wzbogaca `fight` o ekosystem; **F3** dokłada `find cave`; **F4** domyka `clear dungeon → fight elite → craft`; **F5** szlifuje całość w spójne „poczucie przygody". Po F4 pętla jest zamknięta i regrywalna — kolejne biomy/klasy/jaskinie to skalowanie treści, nie nowych systemów.
