# GDD — Świat i Progresja (voxel action-RPG)

Wersja 1.0 · Godot 4.7 · cel: Cube World + MMORPG, progression-heavy

> ⚠️ **SPROSTOWANIE AUDYTU (ważne).** Pierwotny audyt błędnie ogłosił „BLOKER #1: brak treści `.tres` → pusty świat / 0 wrogów". To NIEPRAWDA — `res://data/db/` zawiera **61 plików `.tres`** (8 wrogów, 3 biomy z tabelami spawnu, drzewko Wojownika + 8 pasywów, 21 afiksów, sety, gemy, itemy). **Gra spawnuje wrogów i działa.** Treść jest tylko **wąska** (3 biomy z docelowych 7, 8 typów wrogów, drzewka dla 1 z 11 klas) — to ROZSZERZANIE istniejącej treści, nie tworzenie od zera. Wszelkie „P0/F0: seed `.tres` MVP" w rozdz. 6-8 traktuj jako NIEAKTUALNE; realny pierwszy krok to model biomów wg dystansu (patrz niżej). Reszta projektu (biomy/skille/ekosystem/jaskinie) pozostaje w mocy.

---

## Streszczenie wykonawcze

Ten dokument projektuje warstwę **świata i progresji** autorskiego voxelowego action-RPG: 7 odseparowanych biomów ułożonych w pierścienie trudności wg dystansu od startu, żywy ekosystem mobów (hostile/neutral/passive), proceduralne jaskinie jako filar eksploracji oraz rozbudowane drzewka umiejętności (CORE + ADVANCED, statusy, synergie, real power spikes). Naczelny cel: poczucie **PRZYGODY, PROGRESJI i ODKRYWANIA** — gracz idzie dalej, świat robi się trudniejszy i ciekawszy, a każdy poziom daje odczuwalny skok mocy.

Punktem wyjścia jest audyt realnego kodu (rozdz. 1). Silniki są solidne — combat (`DamageService`/`Hitbox`/`Hurtbox`/`AbilityComponent`), loot (`LootService` z afiksami/setami/socketami), drzewko skilli (`SkillTreeComponent`/`SkillDB`), spawn (`WorldSpawner`, deterministyczny, `MAX_ACTIVE=14`), AI (`AIComponent`, 5 stanów), save/load (`SaveManager`) i progresja (`LevelComponent`, cap 99, respec). Problem nie leży w kodzie ANI w braku treści (ta istnieje — patrz sprostowanie wyżej), lecz w **zakresie i strukturze**: **(1)** biom liczony jest z czystego szumu klimatu, niezależnie od dystansu, więc las potrafi graniczyć ze śniegiem i nie ma kierunku ekspansji ani progresji „dalej = trudniej"; **(2)** świat jest wąski — 3 biomy z docelowych 7, 8 typów wrogów, brak ekosystemu (neutral/passive wildlife, herd/flee/terytoria), brak jaskiń eksploracyjnych, drzewka tylko dla 1 z 11 klas i bez warstw CORE/ADVANCED. To wyznacza kierunek: poszerzyć świat i pogłębić progresję na solidnym, działającym silniku.

Cały plan wdrożenia podporządkowano zasadzie **najpierw odblokuj świat, potem go pogłębiaj**. Reużywamy istniejące systemy zamiast pisać je od nowa: model RING wpinamy w `VoxelWorld.get_biome()`/`surface_height()`, ekosystem rozszerza `AIComponent`/`EnemyResource`/`WorldSpawner`, statusy wpinają się w gotowy hook `DamageService` (pkt 6), jaskinie to drugi przebieg w `Chunk._generate_data` (off-thread, deterministyczny przez `feature_hash`). Wszystko mieści się w budżecie RTX 3050 4 GB (preset LOW, pooling, twarde limity aktywnych encji). Spójność jest twardym kontraktem: nazwy 7 biomów (`forest`/`plains`/`swamp`/`mountains`/`desert`/`snow`/`volcanic`) i 6 statusów (`bleed`/`poison`/`freeze`/`burn`/`stun`/`weaken`) są identyczne we wszystkich rozdziałach.

## Filary projektowe

1. **PRZYGODA** — świat ma ciągnąć „pójdź dalej, zobacz co tam jest". Biomy w pierścieniach dystansu (`RING_WIDTH=320 m`) dają wyraźny kierunek ekspansji i rosnącą stawkę.
2. **PROGRESJA** — leveling = REAL POWER SPIKES, nie liniowy +1%. Drzewka CORE+ADVANCED, keystone na lvl 25, ultimate na lvl 60, synergie i combo statusów, meaningful builds + respec.
3. **ODKRYWANIE** — sekrety nagradzają ciekawość: ukryte wejścia do jaskiń, rzadkie rudy, elite/mini-bossy, warianty mobów, „nigdy nie wiesz co znajdziesz".
4. **ŻYWY ŚWIAT** — ekosystem predator/prey, herd, flee, terytoria i legowiska. Świat ma sprawiać wrażenie ZAMIESZKANEGO, nie być areną agresywnych spawnów.
5. **LOGIKA** — wszystko spójne i deterministyczne: biom = funkcja dystansu, spawn = f(biom, dtier), loot = `ilvl = dtier*2 + (loot_tier-1)*2 (+CAVE_BONUS)`. Host-authoritative, co-op-safe, ten sam seed → ten sam świat.

## Spis treści

1. **Audyt obecnego świata** — co realnie jest w kodzie, blokery, mapowanie 3→7 biomów (`01-audyt.md`).
2. **Redesign biome progression** — model RING-dystans, 7 biomów, blending, teren per biom (`02-biomy.md`).
3. **Redesign skill progression** — CORE/ADVANCED, statusy, combo, synergy, respec (`03-skille.md`).
4. **Mob ecosystem** — taksonomia hostile/neutral/passive, AI, dystrybucja per biom (`04-moby.md`).
5. **Cave generation design** — proceduralne jaskinie, carving, hazardy, link → dungeon (`05-jaskinie.md`).
6. **Content priority list** — ranking P0–P3 wg wpływu/kosztu (`06-priorytety.md`).
7. **Konkretne taski do implementacji** — 35 atomowych tasków z DoD/testami (`07-taski.md`).
8. **Kolejność wdrażania** — fazy z zależnościami i kontraktem testów (`08-kolejnosc.md`).

## Pętla docelowa

```
explore → fight → loot → upgrade → unlock skills → find cave →
clear dungeon → fight elite → craft → travel further → harder biome → repeat
```

Pętla materializuje się przyrostowo wraz z fazami wdrożenia: Faza 0 uruchamia `fight → loot`, Faza 1 dokłada `explore` i `travel further → harder biome`, Faza 2a `upgrade / unlock skills`, Faza 2b wzbogaca `fight` o ekosystem, Faza 3 `find cave`, Faza 4 domyka `clear dungeon → fight elite → craft`, Faza 5 szlifuje całość. Po domknięciu pętla jest regrywalna — kolejne biomy, klasy i jaskinie to skalowanie treści, nie nowych systemów.


---

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


---

## 2. Redesign biome progression (7 biomów, dystans)

Cel rozdziału: zastąpić obecny mozaikowy selektor `VoxelWorld.get_biome()` (czysty szum temperatura×wilgotność, biom niezależny od spawnu) modelem **DYSTANS-RING + lokalny wariant**, w którym odległość od punktu startu (0,0) wyznacza biom, a lokalny szum tylko delikatnie zaburza granice (anty-szew). Efekt docelowy (Cube World + MMORPG): 7 DUŻYCH, czytelnych, ODSEPAROWANYCH biomów ułożonych w pierścienie trudności — im dalej od spawnu, tym wyższy poziom wrogów, lepszy loot i ekstremalniejszy teren. Zachowujemy pełen determinizm (`feature_hash`, niemutowane szumy) i budżet RTX 3050 4 GB (`near_dist=3`/`far_dist=5`, `MAX_PROPS_PER_CHUNK=35`, `WorldSpawner.MAX_ACTIVE=14`).

Spójność nazewnictwa (obowiązuje we WSZYSTKICH rozdziałach GDD): `forest`, `plains`, `swamp`, `mountains`, `desert`, `snow`, `volcanic`. Statusy: `bleed`, `poison`, `freeze`, `burn`, `stun`, `weaken`.

---

### 2.1 Założenia projektowe progresji

1. **Biom = funkcja dystansu, nie szumu klimatu.** Główny selektor to pierścień `ring = floor(dist / RING_WIDTH)`. Klimatyczny szum (`_biome_noise`=temperatura, `_humid_noise`=wilgotność) degradujemy do roli **lokalnej wariacji granicy** (jitter ±~kilkanaście metrów) oraz wyboru wariantu w pierścieniach, które mieszczą dwa biomy.
2. **Biomy DUŻE i odseparowane.** Szerokość pierścienia liczona tak, by przejście przez jeden biom trwało minuty marszu, a nie sekundy. NIE las→śnieg→pustynia w 30 s.
3. **Trudność rośnie monotonicznie z dystansem.** Łączymy obecne `distance_tier()` (ring 80 m, cap 5) z nowym ringiem biomów — biom i tier idą w parze (wcześniej rozłączne, patrz audyt 1.1).
4. **Determinizm.** Selektor to czysta funkcja `(world_x, world_z)` + niemutowane szumy + stały `FEATURE_SEED`. Ten sam punkt zawsze daje ten sam biom (warunek SaveManager/co-op host-authoritative).
5. **Smooth blending na granicach.** Bez interpolacji height/koloru granice pierścieni dałyby ostry klif i szew kolorów. Wprowadzamy `_biome_weights()` (waga 2 sąsiednich biomów w pasie granicznym) używaną do mieszania heightu i palety.
6. **Geografia kierunkowa (opcja docelowa).** By gracz nie „obchodził" ringów w kółko widząc ten sam biom, w pierścieniach z 2 wariantami wybór steruje kąt (sektor) — daje wrażenie kontynentu, nie tarczy strzelniczej. Determinizm zachowany (kąt to czysta funkcja x,z).

---

### 2.2 Model RING — geometria pierścieni

Stałe do dodania w `VoxelWorld.gd` (sekcja parametrów biomów, obok `BIOME_*`):

```gdscript
const RING_WIDTH: float = 320.0        # szerokość JEDNEGO pierścienia biomu w metrach (~20 chunków)
const RING_BLEND_BAND: float = 48.0    # pas mieszania po obu stronach granicy (3 chunki)
const BIOME_RING_MAX: int = 6          # ring 0..6 -> 7 biomów (Forest..Volcanic)
const SPAWN_ORIGIN := Vector2(0.0, 0.0)  # środek progresji (punkt startu gracza)
```

Dlaczego `RING_WIDTH=320`: chunk = 16 m, `near_dist=3` → gracz widzi ~48 m detalu naraz. 320 m = 20 chunków = ~40 s marszu (bieg ~8 m/s), więc każdy biom jest realnie „rozległy" i czytelny. Granica jitterowana szumem (±~32 m), więc nie jest idealnym okręgiem.

Mapowanie ring → biom (monotoniczna progresja dystansem, zgodna z briefem 1→7):

| Ring | Promień (m) | Biom (`id`) | distance_tier (orient.) | Poziom wrogów |
|---|---|---|---|---|
| 0 | 0–320 | `forest` | 1 | 1–8 |
| 1 | 320–640 | `plains` | 1–2 | 8–16 |
| 2 | 640–960 | `swamp` | 2–3 | 16–24 |
| 3 | 960–1280 | `mountains` | 3–4 | 24–34 |
| 4 | 1280–1600 | `desert` | 4 | 34–44 |
| 5 | 1600–1920 | `snow` | 4–5 | 44–58 |
| 6 | 1920+ | `volcanic` | 5 | 58–80 |

`distance_tier()` (RING 80 m, cap 5) zostaje jako osobny modulator ilvl WEWNĄTRZ biomu — daje płynny wzrost mocy lootu też w obrębie jednego pierścienia (np. dalszy kraniec Forest jest minimalnie mocniejszy od spawnu). Poziomy wrogów to docelowy zakres `LevelComponent` per biom (cap 99 zostawia zapas na elity/bossy i endgame poza ringiem 6).

---

### 2.3 Nowy `get_biome()` — implementacja

Zastępujemy ciało `get_biome()` (linie ~267–274 w `VoxelWorld.gd`). Stare progi `BIOME_COLD_TEMP`/`BIOME_HOT_TEMP` przestają sterować biomem (szum klimatu schodzi do roli wariantu/jittera). `_biome_to_byte()`/`_biome_at()` w `Chunk.gd` rozszerzamy o nowe id (sekcja 2.6).

```gdscript
# Lista biomów wg ringu (indeks = ring). StringName spójne z BiomeResource.id i loot_biome wroga.
const RING_BIOMES: Array[StringName] = [
    &"forest", &"plains", &"swamp", &"mountains", &"desert", &"snow", &"volcanic"
]

## Surowy ring z dystansu od spawnu, z jitterem granicy ze szumu klimatu (anty-okrąg).
## Determinizm: czysta funkcja (x,z) + niemutowany _biome_noise.
func _raw_ring(world_x: float, world_z: float) -> float:
    var d := (Vector2(world_x, world_z) - SPAWN_ORIGIN).length()
    # Jitter granicy: ±~32 m wg temperatury (łamie idealny okrąg, ale deterministycznie).
    var jitter := _biome_noise.get_noise_2d(world_x, world_z) * 32.0
    return (d + jitter) / RING_WIDTH

func get_biome(world_x: int, world_z: int) -> StringName:
    var r := _raw_ring(float(world_x), float(world_z))
    var ring := clampi(int(floor(r)), 0, BIOME_RING_MAX)
    return RING_BIOMES[ring]
```

`WorldSpawner._region_biome()` (biom środka regionu) i `Chunk._biomemap` dostają biom z tej samej funkcji — zero rozjazdu spawn vs render. `distance_tier()` zostaje bez zmian (osobny modulator mocy).

---

### 2.4 Smooth blending — wagi granicy

Aby uniknąć klifu wysokości i szwu palety na granicy ringów, dodajemy funkcję wag (główny + sąsiad w pasie `RING_BLEND_BAND`). Używa jej `surface_height()` (mieszanie amplitud terenu) i `Chunk._solid_color`/`Blocks.biome_modulate` (mieszanie palety).

```gdscript
## Zwraca {primary, secondary, t} gdzie t∈[0,1] to udział 'secondary'.
## Poza pasem granicznym t=0 (czysty biom). Determinizm: czysta funkcja (x,z).
func biome_blend(world_x: float, world_z: float) -> Dictionary:
    var r := _raw_ring(world_x, world_z)
    var ring := clampi(int(floor(r)), 0, BIOME_RING_MAX)
    var frac := r - floor(r)                  # pozycja w pierścieniu [0,1)
    var band := RING_BLEND_BAND / RING_WIDTH  # szerokość pasa w jednostkach ringu
    var out := { "primary": RING_BIOMES[ring], "secondary": RING_BIOMES[ring], "t": 0.0 }
    if frac > 1.0 - band and ring < BIOME_RING_MAX:
        # blisko ZEWNĘTRZNEJ granicy -> mieszaj z następnym (trudniejszym) biomem
        out.secondary = RING_BIOMES[ring + 1]
        out.t = smoothstep(0.0, 1.0, (frac - (1.0 - band)) / band) * 0.5
    elif frac < band and ring > 0:
        # blisko WEWNĘTRZNEJ granicy -> mieszaj z poprzednim biomem
        out.secondary = RING_BIOMES[ring - 1]
        out.t = smoothstep(0.0, 1.0, (band - frac) / band) * 0.5
    return out
```

`surface_height()` korzysta z wag, by interpolować amplitudę terenu między biomami (płaski Forest → wzgórzowy Plains → pionowe Mountains bez ściany na szwie) — patrz 2.5. Mnożnik `*0.5` ogranicza maksymalny udział sąsiada do 50% (granica zostaje czytelna, ale gładka).

---

### 2.5 Teren per biom — modulacja `surface_height()`

Obecny `surface_height()` (linie 210–217) jest płaski w sensie biomowym: `round(BASE_HEIGHT(14) + clamp(raw*1.6+0.5)*HEIGHT_AMPLITUDE(64))`. Wprowadzamy **profil terenu per biom** (baza + amplituda + wykładnik kontrastu), mieszany wg `biome_blend`.

| Biom | Baza (voxele) | Amplituda | Profil terenu | Uwaga |
|---|---|---|---|---|
| `forest` | 18 | 18 | płaski, łagodne pagórki | start bezpieczny, brak klifów |
| `plains` | 20 | 28 | rolling hills | szerokie wzgórza |
| `swamp` | 14 | 10 | niski, podmokły (dużo poniżej `SEA_LEVEL`) | rozlewiska, wyspy błota |
| `mountains` | 30 | 64 (×kontrast 2.2) | pionowy, granie, klify | wymaga podniesienia `WORLD_HEIGHT` (2.8) |
| `desert` | 22 | 30 | wydmy + płaskowyże, ruiny | mesy/płaskie urwiska |
| `snow` | 26 | 50 | wysokie ośnieżone, zamarznięte jeziora | lód na poziomie morza |
| `volcanic` | 28 | 56 | poszarpany, kanały lawy | obsydianowe iglice |

Implementacja (szkic — `surface_height()` dostaje pomocniczy profil per biom i miesza):

```gdscript
const BIOME_TERRAIN := {
    &"forest":    {"base": 18.0, "amp": 18.0, "contrast": 1.2},
    &"plains":    {"base": 20.0, "amp": 28.0, "contrast": 1.4},
    &"swamp":     {"base": 14.0, "amp": 10.0, "contrast": 1.0},
    &"mountains": {"base": 30.0, "amp": 64.0, "contrast": 2.2},
    &"desert":    {"base": 22.0, "amp": 30.0, "contrast": 1.5},
    &"snow":      {"base": 26.0, "amp": 50.0, "contrast": 1.8},
    &"volcanic":  {"base": 28.0, "amp": 56.0, "contrast": 2.0},
}

func _height_for_profile(raw: float, prof: Dictionary) -> float:
    var n := clampf(raw * float(prof.contrast) + 0.5, 0.0, 1.0)
    return float(prof.base) + n * float(prof.amp)

func surface_height(world_x: int, world_z: int) -> int:
    var raw := _noise.get_noise_2d(float(world_x), float(world_z))
    var bw := biome_blend(float(world_x), float(world_z))
    var hp := _height_for_profile(raw, BIOME_TERRAIN[bw.primary])
    if bw.t > 0.0:
        var hs := _height_for_profile(raw, BIOME_TERRAIN[bw.secondary])
        hp = lerpf(hp, hs, float(bw.t))
    return clampi(int(round(hp)), 1, WORLD_HEIGHT - 1)
```

Mieszanie `biome_blend` gwarantuje, że na styku Forest|Plains czy Mountains|Desert teren przechodzi płynnie (brak pionowego szwu między chunkami dwóch biomów). Determinizm zachowany — `raw` i `bw` to czyste funkcje pozycji.

---

### 2.6 Tabela master — 7 biomów

| Biom | Ring / dystans | Poziom | Teren | Materiały (bloki) | Jaskinie | Dungeon | Sygnatura (ambient/pogoda/flora) |
|---|---|---|---|---|---|---|---|
| **Forest** | 0 / 0–320 m | 1–8 | płaski, łagodne pagórki | DIRT, GRASS, WOOD, LEAVES, kamień | `small` (płytkie, 1 poziom), rzadkie | „Goblin Warren" (lvl 3–6) | jasne dni, ptaki, lekki wiatr; dęby/sosny, krzaki jagód, grzyby |
| **Plains** | 1 / 320–640 m | 8–16 | rolling hills | GRASS, DIRT, kamień, siano | `small`/`deep` na zboczach | „Bandit Camp" (lvl 10–14) | wietrznie, trawa faluje; wysoka trawa, samotne drzewa, kwiaty |
| **Swamp** | 2 / 640–960 m | 16–24 | niski, podmokły | MUD (nowy), GRASS ciemna, WATER, korzenie | `deep` zalane, `monster_den` | „Sunken Crypt" (lvl 18–22) | mgła, rechot, gęsto; sitowie, zwisające pnącza, świecące grzyby, toksyczne sadzawki |
| **Mountains** | 3 / 960–1280 m | 24–34 | pionowy, klify, granie | ROCK, SNOW (szczyty), ruda żelaza/srebra | `crystal`, `deep`, wielopoziomowe | „Wyvern Roost" (lvl 28–32) | wiatr, echo, rzadkie powietrze; karłowate sosny, mchy, kryształy |
| **Desert** | 4 / 1280–1600 m | 34–44 | wydmy, płaskowyże, ruiny | SAND, SANDSTONE (nowy), ROCK, ruda złota | `underground_ruins`, `deep` | „Buried Temple" (lvl 38–42) | upał, burze piaskowe (pogoda), sępy; kaktusy, suche krzewy, oazy |
| **Snow** | 5 / 1600–1920 m | 44–58 | wysokie ośnieżone, lód | SNOW, ICE (nowy), ROCK, ruda mithrilu | `ice` (śliskie, hazard mróz), `crystal` | „Frozen Hold" (lvl 50–56) | śnieżyca (pogoda), zawodzenie wiatru; martwe drzewa, lodowe iglice, jagody mrozu |
| **Volcanic** | 6 / 1920+ m | 58–80 | poszarpany, kanały lawy | OBSIDIAN (nowy), BASALT, LAVA (nowy), ruda adamantu | `lava` (hazard burn), `monster_den` elite | „Demon Forge" (lvl 70–80, raid) | popiół opadający, łuna, drżenie ziemi; spalone pnie, kryształy ognia, gejzery |

Materiały oznaczone „(nowy)" wymagają dodania do `Blocks.Type` + `Blocks.biome_modulate`/palety w `Chunk._solid_color` (sekcja 2.7). Typy jaskiń (`small`/`deep`/`crystal`/`ice`/`lava`/`underground_ruins`/`monster_den`) i dungeony to hooki do rozdziałów „Jaskinie" i „Dungeony" — tu definiują, KTÓRE warianty spawnują się w danym pierścieniu (`BiomeResource.cave_types[]`, `BiomeResource.dungeon_pool[]`).

---

### 2.7 Hooki do istniejących klas

**`VoxelWorld.gd`**
- `get_biome()` — przepisany na model RING (2.3); usuwa zależność biomu od `temp/hum`.
- `surface_height()` — modulacja profilem terenu per biom + blend (2.5).
- Nowe: `_raw_ring()`, `biome_blend()`, stałe `RING_*`, `RING_BIOMES`, `BIOME_TERRAIN`.
- `distance_tier()` — bez zmian (osobny modulator ilvl wewnątrz biomu).
- `_biome_noise`/`_humid_noise` — zostają, ale schodzą do roli jittera granicy (`_raw_ring`) i ewentualnego wyboru wariantu w sektorach; NIE są już selektorem biomu.

**`Chunk.gd`**
- `_biome_to_byte()` / `_biome_at()` (linie ~389–408) — rozszerzyć mapowanie na 7 id (bajt 1..7). `_biomemap` to nadal `PackedByteArray` (1 bajt/kolumna, zero kosztu pamięci ponad obecny).
- `_block_for()` (linie ~412–428) — wybór bloku powierzchni musi zależeć od biomu kolumny (np. `swamp`→MUD zamiast GRASS, `desert`→SAND/SANDSTONE, `volcanic`→BASALT/OBSIDIAN), a nie tylko od wysokości. Czytać biom z `_biomemap`.
- `_place_features()` (linie ~432–491) — flora per biom: rozszerzyć `_place_tree/_place_bush/_place_rock` o warianty sterowane biomem (kaktus w desert, martwe drzewo w snow, świecący grzyb w swamp). Reużyć istniejące `SALT_*` + `feature_hash` (determinizm); trzymać się `MAX_PROPS_PER_CHUNK=35` (budżet 4 GB).
- `_solid_color()` (linia ~1272) / `Blocks.biome_modulate` — paleta per biom z mieszaniem wg `biome_blend` (anty-szew koloru na granicy).

**`WorldSpawner.gd`**
- `_region_biome()` — bez zmian w API, ale teraz zwraca biom z modelu RING (spawn idzie w parze z dystansem/trudnością; znika rozjazd z audytu 1.1).
- `enemy_spawn_table` zaczyna mieć sens „dalej = trudniej": tabele 7 biomów (`.tres`) wg dystrybucji mobów z briefu (Forest: boars/wolves/slimes/goblins/deer; Snow: ice wolves/frost spiders/polar bears/elementals; itd.). To treść do autorstwa (BLOKER #1 z audytu) — silnik gotowy.

**`BiomeResource` (.tres do utworzenia)** — pola wymagane przez spawner/loot, nowe pola pod ten rozdział:
- `id: StringName` (forest/plains/.../volcanic), `loot_tier: int`, `enemy_spawn_table: Array`.
- nowe: `level_min/level_max: int` (zakres z tabeli 2.6), `cave_types: Array[StringName]`, `dungeon_pool: Array[StringName]`, `weather: StringName`, `palette` (kolory bloków), `flora_table` (warianty propów + wagi).

---

### 2.8 Ryzyka i budżet

1. **`WORLD_HEIGHT=96` (48 m) za płytkie na Mountains/Volcanic** (audyt 1.7). Profil `mountains` (baza 30 + amp 64 = do 94 voxeli) prawie dotyka sufitu, a wielopoziomowe jaskinie (rozdział „Jaskinie") potrzebują pustki pod szczytem. Rekomendacja: podnieść `WORLD_HEIGHT` do 128 (64 m) globalnie. Koszt: +33% voxeli/chunk w pionie → mieści się w 4 GB tylko z LOD-em (FAR step=2 bez kolizji już działa) i przy zachowaniu `near_dist=3`. Alternatywa tańsza: kompresja pustki (`AIR` nad terenem nie zajmuje mesha) — pionowy zasięg rośnie bez liniowego kosztu, bo mesh liczy tylko ściany graniczne.
2. **Granice pierścieni „obchodzenie" w kółko.** Czysty ring daje tarczę strzelniczą. Mitygacja: jitter (2.3) + opcjonalny model sektorowy (2.1 pkt 6) — w pierścieniach z wariantem kąt wybiera podbiom. Do decyzji po prototypie; nie blokuje MVP.
3. **Szew determinizmu przy zmianie `RING_WIDTH`/`SPAWN_ORIGIN`.** Każda zmiana tych stałych przemapowuje cały świat → niespójność z istniejącymi save'ami (SaveManager). Traktować jak migrację seeda: zmieniać tylko przy bump wersji świata.
4. **Koszt `biome_blend` w `surface_height`.** Wołane raz/kolumnę w `_generate_data` (off-thread, jak obecnie). Dodatkowy koszt: 1× `_raw_ring` (1 próbka szumu + length) + ewentualny 2. profil w pasie granicznym. Pomijalne vs obecne 2× szum klimatu, które usuwamy z selektora.
5. **Budżet propów/spawnów bez zmian.** `MAX_PROPS_PER_CHUNK=35`, `MAX_ACTIVE=14`, `MAX_ACTIVE_ELITES=2`, pooling — flora i moby per biom muszą się w tych limitach zmieścić; tabele `.tres` dobierane pod te liczby.

---

### 2.9 Kolejność wdrożenia (DoD tego rozdziału)

1. Dodać stałe `RING_*`, `RING_BIOMES`, `BIOME_TERRAIN` + przepisać `get_biome()` i `surface_height()` w `VoxelWorld.gd`.
2. Dodać `_raw_ring()` i `biome_blend()`; podpiąć blend do heightu i palety.
3. Rozszerzyć `Chunk._biome_to_byte/_biome_at/_block_for` o 7 biomów + nowe bloki w `Blocks.Type`.
4. Utworzyć 7 plików `BiomeResource.tres` (rozwiązuje BLOKER #1 dla warstwy biomów) z `enemy_spawn_table`, `level_min/max`, `cave_types`, `dungeon_pool`, `weather`, `palette`, `flora_table`.
5. Test E (jak obecny test 3 stref): weryfikacja, że marsz od (0,0) na zewnątrz przechodzi przez 7 biomów w kolejności Forest→Volcanic, granice są gładkie (brak klifu/szwu), a `_region_biome` zgadza się z `get_biome` (spawn = render).


---

## Redesign skill progression (Core + Advanced, statusy, synergy)

> Rozdział GDD świata — warstwa progresji umiejętności. Reużywa istniejącego silnika:
> `SkillResource` / `SkillTreeResource` / `PassiveNodeResource` / `SkillTreeComponent` /
> `LevelComponent` / `AbilityComponent` / `StatsComponent` / `StatModifier` / `DamageService` /
> `SkillDB` / `ContentDB`. **Zero przepisywania rdzenia** — rozszerzamy o nowe pola danych i nowy
> komponent statusów. Wszystkie liczby gotowe do wpisania w `.tres`.

---

### 1. Cel i pętla mocy

Leveling ma dawać **odczuwalne skoki mocy** (real power spikes), a nie liniowy +1% co poziom.
Pętla: `kill -> XP -> level up -> punkt -> węzeł CORE -> nowy skill/spec -> nowy combo -> mocniejszy
build -> dalszy biom`. Spójność ze światem (rozdz. 02): biomy w pierścieniach dystansu dostarczają
przeciwników z konkretnymi typami obrażeń/odpornościami — buildy statusowe (freeze w Snow, burn w
Volcanic, poison w Swamp) mają tam mieć sens lub karę.

Każda z **11 klas** (kanon `ContentDB._seed`: wojownik, paladyn, berserker, lucznik, lotrzyk,
zabojca, mag, nekromanta, kaplan, druid, mnich) dostaje **jedną** `SkillTreeResource` o tej samej
strukturze szkieletowej:

- **CORE TREE** — 4 gałęzie: **Offense / Defense / Utility / Mobility**. Dostępne od lvl 1.
- **ADVANCED TREE** — 2 gałęzie specjalizacji: **Spec A / Spec B**. Odblokowywane od lvl 25
  (keystone wyboru spec), pełnia od lvl 60 (capstone/ultimate).

---

### 2. Taksonomia węzłów i skilli

Mapowanie na istniejące typy zasobów:

| Kategoria | Nośnik danych | Pole/typ | Uwagi |
|---|---|---|---|
| **Pasyw** | `PassiveNodeResource.modifiers` | `Array[StatModifier]` (FLAT/INCREASED/MORE) | wpina się przez provider `SkillTreeComponent.collect_modifiers()` |
| **Notable** | `PassiveNodeResource` + `is_keystone=false`, `min_level` próg | mocniejszy pasyw, 1 punkt | "węzeł smaku" gałęzi |
| **Keystone** | `PassiveNodeResource.is_keystone=true`, `min_level=25` | zmienia regułę gry, często trade-off | brama do Spec A/B |
| **Aktywny skill** | `PassiveNodeResource.grants_skill` -> `SkillResource` | węzeł nadaje skill na pasek | spawn/hitbox wg `SkillResource.scene` + timeline |
| **ULTIMATE** | `SkillResource` z `tags=[&"ultimate"]`, `min_level` capstone=60 | **1 per spec** (2 na klasę) | długi CD, duży `damage_mult`, własna aura |
| **Movement skill** | `SkillResource` z `tags=[&"movement"]` | dash/skok/teleport | cancel-into z `AbilityComponent.cancel()` |
| **Defensive skill** | `SkillResource` z `tags=[&"defensive"]` | block/bariera/unik-i-frame | i-frames z timeline `anticipation`/`active` |
| **Utility skill** | `SkillResource` z `tags=[&"utility"]` | pułapka/aura/totem/oil | często enabler combo |

**Każda klasa dostaje** (minimum): 1 movement, 1 defensive, 1 utility w CORE + 2 ultimate w ADVANCED
(po jednym na spec).

---

### 3. Rozszerzenia techniczne istniejących zasobów

Wszystko jako **nowe `@export` z bezpiecznym defaultem** (stare `.tres` działają bez zmian).

#### 3.1 `PassiveNodeResource.gd` (dodać pola)

```gdscript
@export var layer: StringName = &"core"        # &"core" | &"advanced"
@export var branch: StringName = &""           # &"offense"|&"defense"|&"utility"|&"mobility"|&"spec_a"|&"spec_b"
@export var rank_max: int = 1                   # ile razy można dobrać (skalowalne pasywy 1..N)
@export var grants_status_apply: Array[StatusApplyResource] = []  # węzeł nadaje on-hit status (sek.5)
@export var spec_lock: StringName = &""         # jeśli != "" -> wziąć tylko gdy aktywna ta spec (A/B)
```

`rank_max>1`: `SkillTreeComponent.allocate()` zezwala na wielokrotną alokację, `collect_modifiers()`
mnoży `value*rank`. Wymaga drobnej zmiany `_allocated: Dictionary` z `bool` na `int` (liczba ranków).

#### 3.2 `SkillTreeResource.gd` (dodać metadane warstw)

```gdscript
@export var core_branches: Array[StringName] = [&"offense", &"defense", &"utility", &"mobility"]
@export var advanced_branches: Array[StringName] = [&"spec_a", &"spec_b"]
@export var advanced_unlock_level: int = 25     # próg odblokowania ADVANCED
@export var spec_choice_exclusive: bool = false # true -> wybór A LUB B (hard spec); false -> oba dostępne wolniej
@export var resource_kind: StringName = &""     # &"rage"/&"mana"/&"combo"/&"focus"... (z ClassResource.resource_kind)
```

#### 3.3 `SkillResource.gd` (dodać)

```gdscript
@export var category: StringName = &"active"    # active|ultimate|movement|defensive|utility
@export var status_on_hit: Array[StatusApplyResource] = []  # statusy nakładane przy trafieniu
@export var combo_consumes: StringName = &""    # np. &"oil"/&"freeze" — zużywa status celu na bonus
@export var combo_bonus_mult: float = 1.0       # mnożnik dmg gdy combo_consumes spełnione
@export var iframe_window: float = 0.0          # s nietykalności w fazie active (defensive/dash)
```

#### 3.4 `SkillTreeComponent.gd` (rozszerzyć walidację)

- `cannot_allocate_reason()` dokłada: `layer==&"advanced"` wymaga `lvl >= tree.advanced_unlock_level`;
  jeśli `spec_choice_exclusive` i wzięto już węzeł z `spec_a`, blokuj `spec_b` (i odwrotnie) — chyba że
  pełny respec.
- `grants_skill` -> przy alokacji woła `entity.grant_skill(node.grants_skill)` (encja podpina na pasek;
  `AbilityComponent.try_use` reszta bez zmian).
- `grants_status_apply` -> rejestruje on-hit u `StatusComponent` (sek. 5) po `source_id=node.id`.

#### 3.5 `LevelComponent.gd` (power-spike granty)

Obecnie: +1 punkt/level, +1 power-point co 5 lvl. **Dokładamy bramki progowe** (bez zmiany krzywej XP):

| Próg | Co dostaje gracz |
|---|---|
| lvl 1 | 1. aktywny CORE skill (z `ClassResource.skill_hints[0]`), movement skill |
| lvl 5 | +1 power-point; odblokowanie **defensive skill** |
| lvl 10 | utility skill; pierwszy notable osiągalny |
| lvl 15 | drugi aktywny CORE; +1 power-point |
| lvl 20 | trzeci aktywny CORE (`skill_hints[2]`) |
| **lvl 25** | **WYBÓR SPECJALIZACJI** (keystone spec_a/spec_b) — duży skok |
| lvl 30/35/40 | notable w wybranej spec, +power-pointy co 5 |
| **lvl 60** | **ULTIMATE** danej spec (capstone) — drugi duży skok |
| lvl 75/90 | drugi keystone spec / cross-spec notable |
| lvl 99 | cap; pełna alokacja ~98 pkt + ~19 power-point |

Implementacja: `_grant_points_for_level(lvl)` emituje dodatkowy sygnał `milestone_reached(lvl, kind)`
przy lvl ∈ {1,5,10,15,20,25,60}, encja wtedy `grant_skill`/otwiera UI spec. Krzywa XP i cap 99
**bez zmian**.

---

### 4. Pipeline statów a skille (spójność z TDD 3.1)

Węzły piszą wyłącznie `StatModifier` w kanonie `FLAT / INCREASED / MORE`:

```
final = (base + Σ FLAT) * (1 + Σ INCREASED) * Π(1 + MORE)
```

Reguły projektowe (by uniknąć inflacji):
- **FLAT** — tylko wczesne CORE (np. `+8 damage`, `+40 max_hp`).
- **INCREASED %** — większość węzłów skalowalnych (`+12% increased fire_damage`), sumują się — tanie,
  liniowe, podstawa buildu.
- **MORE %** — rzadkie, **tylko keystone/ultimate/spec capstone** (`x1.30 more damage gdy cel pali`).
  Multiplikatywne = źródło prawdziwych power-spike’ów. Max 2-3 źródła MORE na build.

Tagi `StatModifier.tags` (np. `&"fire"`, `&"melee"`, `&"bleed"`, `&"crit"`) pozwalają węzłom celować
w konkretny typ — synergia z lootem (afiksy o tych samych tagach się sumują w INCREASED).

Zasoby klas (`ClassResource.resource_kind`): rage/faith/combo/focus/mana/essence/nature/chi —
węzły mogą modyfikować staty zasobu kluczami `&"<res>_max"`, `&"<res>_regen"`, `&"<res>_on_hit"`.

---

### 5. STATUS EFFECTS — nowy `StatusComponent` (komponent) + `StatusApplyResource` (dane)

`DamageService._resolve()` ma już hook **pkt 6** (`on_hit_effects` — obecnie no-op). Aktywujemy go:
po `hit_resolved` wołamy `StatusComponent.apply()` na celu. Status = data (`StatusApplyResource`) +
runtime stack na celu. Tick co 0.5 s w `_process` (zgodnie z budżetem RTX 3050 — pooling, brak
per-frame).

#### 5.1 Tabela statusów (mechanika liczbowo)

| Status | Typ | Czas | Tick | Obrażenia/efekt na tick | Stack | Max stack | Interakcje |
|---|---|---|---|---|---|---|---|
| **bleed** (krwawienie) | DoT fizyczny | 6 s | 0.5 s | 4% atk dmg / tick | dodaje czas + intensywność | 5 | nasila się przy ruchu celu (+50% tick gdy się porusza); `execute` poniżej 20% HP |
| **poison** (trucizna) | DoT chaos, ignoruje pancerz | 8 s | 0.5 s | 3% atk dmg / tick | osobne instancje (każda swój timer) | 8 | nie redukowany przez `armor`; synergia z `weaken` (x1.25 tick) |
| **burn** (ogień) | DoT ognisty | 4 s | 0.5 s | 5% atk dmg / tick | odświeża czas, intensywność max 3 | 3 | `+oil` -> x2 dmg i +czas; podpala olej/gaz w jaskini |
| **freeze** (zamrożenie) | hard CC | 2 s | — | brak ruchu i akcji | nie stackuje (odświeża) | 1 | po wyjściu **shatter**: dmg = 15% max_hp celu jeśli rozbity bronią; chill (slow 30%) jako stan przejściowy |
| **stun** (ogłuszenie) | hard CC | 1.2 s | — | brak akcji (może spaść) | DR: każdy kolejny stun w 6 s -50% czasu | 1 | przerywa cast wroga; immunity 4 s po pełnym stunie (anty-permastun) |
| **weaken** (osłabienie) | debuff | 5 s | — | cel zadaje -20% dmg, otrzymuje +15% dmg | odświeża, intensywność max 2 (-30%/+25%) | 2 | mnoży dmg wszystkich źródeł — enabler dla DoT i burst |

Liczby skalują się od `atk dmg` źródła w momencie nałożenia (snapshot), żeby DoT nie był zależny od
późniejszych buffów (determinizm host-authoritative, brak desyncu — zgodnie z DamageService).

#### 5.2 `StatusApplyResource.gd` (nowy zasób danych)

```gdscript
class_name StatusApplyResource
extends Resource
@export var status: StringName = &""        # &"bleed"|&"poison"|&"burn"|&"freeze"|&"stun"|&"weaken"
@export var chance: float = 1.0             # 0..1 szansa nałożenia
@export var duration: float = 6.0
@export var tick: float = 0.5
@export var magnitude: float = 0.04         # % atk dmg / tick LUB % efektu
@export var max_stacks: int = 1
@export var tags: Array[StringName] = []
```

#### 5.3 `StatusComponent.gd` (nowy komponent)

- `apply(src_dmg: float, def: StatusApplyResource)` — rzut na `chance`, dodaj/odśwież stack.
- `_process(delta)` — akumuluj do `tick`; per tick: DoT -> `DamageService.request_hit(src=null,
  self, HitData(base_damage=snapshot*magnitude, tags=[status]))` (centralne liczenie odporności).
- hard CC (`freeze`/`stun`) -> ustawia flagę w `AIComponent`/Player input (blokada akcji), emituje
  `status_changed` (HUD/FX).
- `has_status(s)`, `consume_status(s)` — używane przez combo (`SkillResource.combo_consumes`).
- Provider `StatsComponent`: `weaken` wpina `StatModifier` (`damage` INCREASED -20%, `taken` +15%)
  po `source=&"status"`, `source_id=&"weaken"` — auto-zdejmowane po wygaśnięciu (`remove_modifiers_by_source`).

---

### 6. COMBO / SYNERGY — konkretne przykłady

**Combo (status -> finisher), liczbowo:**

| Combo | Setup | Finisher | Efekt |
|---|---|---|---|
| **freeze -> shatter** | freeze celu (Lodowy grot/keystone) | dowolny cios bronią | `shatter`: +15% max_hp celu jako dmg, AoE 3 m do sąsiadów |
| **burn + oil** | utility `Olej` (status `oil`) na cel/teren | burn (Ognista kula) | burn tick **x2** i +2 s; podpala kałużę oleju (strefa 4 m) |
| **bleed + execute** | 3+ stacki bleed | skill z tagiem `&"execute"` poniżej 25% HP | natychmiastowa egzekucja (dmg = pozostałe HP), zwrot zasobu |
| **poison + weaken** | poison na cel | weaken | tick poison x1.25, ignoruje pancerz — anty-tank/anty-elite |
| **stun -> burst** | stun (Roztrzaskanie/Fala chi) | nuke w oknie stunu | crit guaranteed w pierwszych 0.4 s stunu |

**Synergia między węzłami (pasywy mnożą się przez tagi/MORE):**

- *"Każdy stack bleed na celu: +6% increased damage Twoich ataków przeciw niemu"* (notable Offense) +
  *"Bleed nakłada się o 1 stack więcej (max 6)"* (notable) -> skaluje DoT-build liniowo, a keystone
  *"Cele krwawiące: x1.25 more damage"* daje power-spike multiplikatywny.
- *"Freeze trwa +0.5 s"* + *"Shatter zadaje +50%"* + keystone *"Twoje obrażenia ognia ROZBIJAJĄ
  zamrożenie zamiast je zdejmować"* -> cross-element fire+ice burst.
- *"Weaken aplikuje się przy każdym ulti"* + *"Cele osłabione: x1.3 more crit damage"* -> burst-spec.

---

### 7. Wzorcowa pełna klasa: **Berserker** (`class_id = &"berserker"`, zasób `rage`)

Baza (z `ContentDB`): `hp 120, dmg 20, armor 0.1`, broń: topór dwuręczny, hinty: Szał / Wir Ostrzy /
Rozłup. Spec A = **Krwawy Szał** (bleed/lifesteal/sustained), Spec B = **Burza Ostrzy** (AoE/freeze-shatter/burst).

#### 7.1 CORE — Offense (`branch=&"offense"`, layer=&"core"`)

| id | display | min_lvl | rank_max | koszt | modifiers (op) | grants_skill / status |
|---|---|---|---|---|---|---|
| `brsk_off_1` | Ostrze Furii | 1 | 3 | 1 | `damage` INCREASED +10% (tag melee) | — |
| `brsk_off_2` | Głęboka Rana | 5 | 3 | 1 | `bleed_magnitude` INCREASED +15% | nadaje on-hit bleed 1 stack (`StatusApplyResource` chance 0.4) |
| `brsk_off_3` | Krwiożerczość (notable) | 10 | 1 | 1 | `crit_chance` FLAT +8% (tag bleed) | — |
| `brsk_off_4` | Topór Spustoszenia | 15 | 1 | 1 | — | grants_skill `&"rozlup"` (AoE cleave) |
| `brsk_off_5` | Furia Rośnie (notable) | 20 | 1 | 1 | `damage` INCREASED +6% per 25 rage (warunkowe) | — |

#### 7.2 CORE — Defense

| id | display | min_lvl | rank_max | koszt | modifiers |
|---|---|---|---|---|---|
| `brsk_def_1` | Twarda Skóra | 1 | 3 | 1 | `max_hp` FLAT +40 |
| `brsk_def_2` | Zacietość | 5 | 1 | 1 | grants_skill `&"krzyk_bojowy"` (defensive: -20% taken 4 s) |
| `brsk_def_3` | Drugi Oddech (notable) | 10 | 1 | 1 | `lifesteal` FLAT +5% (tag bleed) |
| `brsk_def_4` | Niezłomny (notable) | 20 | 1 | 1 | `max_hp` INCREASED +15% |

#### 7.3 CORE — Utility

| id | display | min_lvl | koszt | modifiers / grants |
|---|---|---|---|---|
| `brsk_uti_1` | Zew Krwi | 5 | 1 | `rage_on_hit` FLAT +4 |
| `brsk_uti_2` | Prowokacja | 10 | 1 | grants_skill `&"prowokacja"` (utility: taunt + weaken AoE) |
| `brsk_uti_3` | Niegasnąca Furia (notable) | 15 | 1 | `rage_decay` INCREASED -30% |

#### 7.4 CORE — Mobility

| id | display | min_lvl | koszt | grants / modifiers |
|---|---|---|---|---|
| `brsk_mob_1` | Szarża | 1 | 1 | grants_skill `&"szarza"` (movement: dash 6 m, `iframe_window 0.2`) |
| `brsk_mob_2` | Pęd Bitewny (notable) | 10 | 1 | `move_speed` INCREASED +12% po zabiciu (5 s) |
| `brsk_mob_3` | Szarża+ | 15 | 1 | `szarza` cooldown INCREASED -25%; szarża nakłada stun 0.6 s |

#### 7.5 ADVANCED — Spec A: Krwawy Szał (`branch=&"spec_a"`, advanced, unlock 25)

| id | display | min_lvl | is_keystone | koszt | efekt |
|---|---|---|---|---|---|
| `brsk_a_key` | **Pakt Krwi** (keystone) | 25 | true | 1 | Twoje ataki zawsze nakładają bleed; cele krwawiące: **x1.25 MORE damage**; tracisz 2% HP/s |
| `brsk_a_1` | Żniwo | 30 | false | 1 | `bleed` może mieć 6 stacków; każdy stack +4% lifesteal |
| `brsk_a_2` | Egzekucja (notable) | 40 | false | 1 | skill `rozlup` zyskuje tag `&"execute"` (combo bleed+execute <25% HP) |
| `brsk_a_ult` | **ULTIMATE: Krwawa Łaźnia** | 60 | true | 1 | grants_skill `&"krwawa_laznia"`: AoE, zużywa wszystkie stacki bleed wrogów w 6 m -> dmg = Σ pozostałego bleed x2, leczy 40% zadanego (CD 60 s, `tags=[&"ultimate"]`) |

#### 7.6 ADVANCED — Spec B: Burza Ostrzy (`branch=&"spec_b"`)

| id | display | min_lvl | is_keystone | koszt | efekt |
|---|---|---|---|---|---|
| `brsk_b_key` | **Wir Nieustający** (keystone) | 25 | true | 1 | grants_skill `&"wir_ostrzy"` (kanałowane AoE); podczas wiru: x1.2 MORE AoE dmg, brak regenu rage |
| `brsk_b_1` | Mroźne Ostrze | 30 | false | 1 | ataki AoE nakładają chill; krytyk na schłodzonym -> freeze 1.5 s |
| `brsk_b_2` | Roztrzaskanie (notable) | 40 | false | 1 | combo freeze->shatter +50% (synergia z Mroźnym Ostrzem) |
| `brsk_b_ult` | **ULTIMATE: Tornado Stali** | 60 | true | 1 | grants_skill `&"tornado_stali"`: wir 8 m, wciąga wrogów, shatteruje wszystkie zamrożone (CD 75 s, `tags=[&"ultimate"]`) |

#### 7.7 Powiązane `SkillResource` (timeline — wzorzec dla `rozlup`)

```
id=&"rozlup", category=&"active", cost_resource=&"rage", cost_amount=25, cooldown=4.0,
damage_mult=1.6, anticipation=0.25, active=0.15, recovery=0.35, cancel_window=0.2,
tags=[&"melee",&"aoe"], aura_kind=&"slam", status_on_hit=[StatusApply(bleed,0.5,...)]
```

---

### 8. Build diversity — przykładowe buildy (Berserker + Mag)

**Berserker / Build A — "Krwawy Młyn" (sustained DoT bruiser):**
CORE Offense pełne (Ostrze Furii ×3, Głęboka Rana ×3, Krwiożerczość) + Defense lifesteal (Drugi
Oddech) -> Spec A keystone **Pakt Krwi** + Żniwo + ULTIMATE Krwawa Łaźnia. Loot: afiksy `+bleed`,
`+lifesteal`. Power-spike: keystone (x1.25 MORE) na lvl 25, drugi na ulti lvl 60. Gra: utrzymuj
bleed, egzekucje, sustain HP z lifesteal — anty-elite, słaby przeciw rojom.

**Berserker / Build B — "Lodowa Burza" (AoE freeze-shatter):**
CORE Offense crit + Mobility (Szarcha+ stun) -> Spec B **Wir Nieustający** + Mroźne Ostrze +
Roztrzaskanie + ULTIMATE Tornado Stali. Loot: `+cold/ice`, `+crit`. Combo: chill -> krytyk freeze ->
ulti shatteruje całą grupę. Power-spike: AoE clear pod Snow/jaskinie z rojami. Słaby 1v1 vs
freeze-immune (Volcanic).

**Berserker / Build C — "Tank-Provokator" (co-op frontline):**
Defense pełne (Niezłomny, Twarda Skóra ×3) + Utility (Prowokacja+weaken) + Spec A do Pakt Krwi dla
sustainu, bez ulti-burst. Rola: trzyma aggro, weaken na bossie -> reszta party bije mocniej (synergia
party-wide). Power-spike: lvl 20 Niezłomny (+15% HP MORE-like) + weaken aura.

**Mag (`&"mag"`, zasób mana) / Build A — "Piromanta" (burn + oil):**
CORE Offense fire (INCREASED fire_damage) + Utility **Olej** -> Spec fire keystone *"burn x1.3
MORE"*. Combo burn+oil (x2 tick), podpala kałuże w jaskiniach. Loot: `+fire`, `+burn duration`.
Świetny w Volcanic-ready vs grupy, kara: cele fire-immune.

**Mag / Build B — "Kriomanta" (freeze control):**
CORE Lodowy grot + freeze-duration notable -> Spec ice keystone *"krytyk zawsze freeze"* + shatter.
Kontrola CC, burst z shatter (15% max_hp). Synergia party: zamraża dla meleé do shatteru. Słaby DPS
solo na bossach freeze-resistant -> wtedy respec.

---

### 9. RESPEC (rozbudowa istniejącego `SkillTreeComponent.respec`)

Silnik już ma: koszt schodkowy w **Orbach Przemiany** (`ORB_COST_STEPS = [500,1500,4000]`, dalej
+4000 cap) i tani respec za **Złoto** (`level*50`). Rozszerzenia projektowe:

| Tryb | Koszt | Zakres | Hook |
|---|---|---|---|
| **Pojedynczy węzeł** (Orb Drobny) | 1 Orb Drobny | cofnij 1 liść (jeśli nic od niego nie zależy) | `deallocate()` — już istnieje, strukturalnie darmowy + opłata waluty w warstwie wyżej |
| **Respec gałęzi** | `gold_cost_for(level)` ×0.5 | reset jednej gałęzi CORE | nowy wariant `respec_branch(branch)` filtrujący `_allocated` po `node.branch` |
| **Pełny respec** | `orb_cost_for(respec_index)` LUB `gold_cost_for(level)` | wszystko + zmiana spec A/B | istniejący `respec()` |
| **Zmiana specjalizacji** | pełny respec (zwalnia `spec_lock`) | przełączenie hard-spec A<->B | walidacja `spec_choice_exclusive` w `cannot_allocate_reason` |

`respec_done(refunded, cost)` / `respec_failed(reason)` — bez zmian; UI (`SkillTreeUI.gd`) pokazuje
podgląd przed potwierdzeniem. Pierwszy respec do lvl 20 darmowy (onboarding eksperymentowania).

---

### 10. Pliki danych do wyprodukowania (rozwiązuje BLOKER #1 — pusty świat)

`SkillDB` skanuje `res://data/db/{skills,trees,passives,augments}`. Potrzebne `.tres`:

- `data/db/trees/` — **11×** `SkillTreeResource` (1 per `class_id`), każde z `core_branches`/`advanced_branches`.
- `data/db/passives/` — **~22 węzły/klasa** (CORE ~16 + ADVANCED ~6) -> ~240 plików, lub jedno
  `SkillTreeResource.nodes` inline per klasa (preferowane: mniej plików, szybszy skan, budżet pamięci).
- `data/db/skills/` — `SkillResource` dla każdego `grants_skill` + 2 ultimate/klasa (~6-8/klasa).
- Nowe: `StatusApplyResource` (inline w skillach/węzłach), `StatusComponent.gd` dodać do prefabu encji
  jako sibling `StatsComponent` (auto-rejestruje provider, jak `SkillTreeComponent`).

Kolejność wdrożenia (pod vertical slice): Berserker + Mag pełne -> reszta klas wg wzorca z sek. 7.


---

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


---

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


---

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


---

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


---

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


---

