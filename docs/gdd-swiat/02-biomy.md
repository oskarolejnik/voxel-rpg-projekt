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
