# Roadmapa v2 — Voxel RPG (nazwa robocza)

> Zasada nadrzedna: **kazdy etap konczy sie czyms uruchamialnym**, a decyzje projektowe sa
> „baked-in” od poczatku (network-aware, host-authoritative, loot-jako-progresja). Powiazane:
> `GDD.md` (mechaniki), `TDD.md` (architektura/dane/netcode).
>
> **Stan obecny (zweryfikowany w kodzie):** chunkowy swiat voxelowy (watkowy streaming + LOD +
> mgla, deterministyczna generacja `feature_hash` + `FastNoiseLite`), cykl dnia/nocy
> (`src/DayNight.gd`), szkielet walki (`src/Player.gd`: HP/stamina, atak LMB promien+luk, unik
> z i-frames, combo->przebicie pancerza, knockback, hitstop, `take_damage`/smierc/respawn, sygnaly
> do HUD), wrog + AI (`src/Enemy.gd`: idle/patrol/chase/attack/leash, `armor 0..1`), HUD
> (`src/HUD.gd`), parametryczna postac voxelowa z animacja proceduralna (`src/world/VoxelModel.gd`).
> Warstwy kolizji: teren=1, gracz=2, wrog=3.

---

## 1. Decyzje zablokowane (baked-in we wszystkich etapach)

- **Multiplayer:** co-op do 4, wspolny swiat ze znajomymi (NIE MMO). Architektura network-aware
  od dnia 1, implementacja SP-first.
- **Stack:** Godot 4.7 + GDScript. High-level multiplayer (MultiplayerAPI/Spawner/Synchronizer/
  RPC), listen-server. GDExtension/C# tylko na udowodnione waskie gardla.
- **Swiat:** deterministyczny z seeda; klienci generuja lokalnie (oszczednosc pasma), siec
  synchronizuje encje/stan/loot.
- **Zapis:** hybryda — trwaly otwarty swiat (host) + instancjonowane runy dungeonow.
- **Progresja:** loot to glowne zrodlo mocy (MC-Dungeons-light + glebia), drzewko skromne; lvl
  max 99; respec za walute; jedna postac main.
- **Walka:** power-fantasy (kosisz hordy), NIE souls-like.
- **Zakres prototypu (vertical slice):** pare itemow/klase, pare typow mobow, 3 biomy (Verdant
  Hollow / Emberwaste / Frosthelm Peaks).

## 2. Mapa etapow

| Etap | Zawartosc | Baked-in |
|---|---|---|
| **0. Kregoslup** | StatBlock + pipeline, wszystkie Resource'y, DB-autoloady, SaveManager, NetManager (stub SP), NetIdentity | abstrakcja autorytetu od dnia 1 |
| **1. Mieso walki** | DamageService + HitData, Hit/Hurtbox, AbilityComponent, BuffComponent, refaktor Player/Enemy na komponenty | walka host-authoritative w SP |
| **2. Loot + itemy** | LootService, ItemInstance, afiksy/sety/sockety/enchanty, Inventory UI | RNG deterministyczny, host-only |
| **3. Progresja** | drzewko (skromne), level/xp, zasoby klas (Mana/Furia/Combo+Focus), respec | loot glowny, drzewko = wybory |
| **4. Biomy + wrogowie** | 3 biomy (BiomeResource), spawn tables, Brute/Slinger + warianty, telegrafy | spawn deterministyczny z seeda |
| **5. Dungeony** | wejscia w swiecie -> instancja proceduralna (graf+BSP+stitching), loot do postaci | instancje efemeryczne |
| **6. Pet/towarzysz** | oswajanie (od lvl 5), allegiance ALLY, stan FOLLOW | reuse Enemy.gd |
| **7. CO-OP** | NetManager live: Spawner/Synchronizer/RPC, predykcja+rekonsyliacja, host save | retrofit, nie przepisanie |
| **8. Vertical slice polish** | balans, VFX/SFX, UI, pare itemow/klasa, pare mobow, 3 biomy grywalne | zakres prototypu |

> Kolejnosc 0->1 jest twarda (dane przed logika). 2–6 maja pewna swobode, ale loot (2) przed
> progresja (3), biomy (4) przed dungeonami (5). Co-op (7) celowo PO ustabilizowaniu logiki —
> bo cala logika juz jest host-authoritative, wiec to dolozenie transportu, nie refaktor.

---

## 3. ETAP 0 — Kregoslup (szczegolowy plan plikow)

**Cel / Definition of Done:** gra startuje w SP; postac ma staty z `StatBlock`; dolozenie
testowego itemu z `StatModifier` zmienia `get_stat()` wg wzoru base->flat->inc->more; save/load
postaci (JSON) dziala; `NetManager.has_authority()` zwraca `true`. Zero kodu sieciowego „na
twardo” w logice.

**Struktura katalogow (NOWE):** `res://data/resources/`, `res://autoload/`, `res://components/`,
`res://data/db/` (instancje .tres).

**Resource'y — `res://data/resources/`:**
- `StatModifier.gd`, `StatBlock.gd`, `HitData.gd`
- `SkillResource.gd`, `PassiveNodeResource.gd`, `SkillTreeResource.gd`, `AugmentResource.gd`
- `ItemResource.gd`, `ItemInstance.gd`, `AffixResource.gd`, `SetResource.gd`, `GemResource.gd`,
  `EnchantResource.gd`, `LootTableResource.gd`
- `EnemyResource.gd`, `BiomeResource.gd`, `CharacterAppearance.gd`, `SaveData.gd`

**Autoloady — `res://autoload/`** (rejestracja w `project.godot`):
- `GameState.gd` — tryb SP/host/client, ref do lokalnego gracza, biezacy run.
- `NetManager.gd` — STUB: `has_authority(_n)->true`, `is_host()->true`, `local_peer_id()->1`;
  API gotowe pod Etap 7.
- `SaveManager.gd` — `save_character()`, `load_character()`, `save_world()`, `load_world()`
  (JSON + `version`).
- `ItemDB.gd`, `SkillDB.gd`, `EnemyDB.gd` — skan folderow `res://data/db/...` -> slowniki po `id`.
- `RNGService.gd` — seed -> strumienie `world` / `loot` / `combat`; `world` dostarcza seed do
  `VoxelWorld` (jedno zrodlo, NIE duplikat generacji terenu).

**Komponenty (szkielet) — `res://components/`:**
- `NetIdentity.gd` — `net_id`, `owner_peer`, helpery autorytetu przez `NetManager`.
- `StatsComponent.gd` — pelny pipeline `get_stat` + `rebuild_modifiers` + cache + `stats_changed`.
- `HealthComponent.gd` — `current_hp` z `StatsComponent.max_hp`, `apply_damage`, `heal`, sygnaly
  `damaged`/`died`.

**Integracja (minimalna, dowod pipeline'u):**
- `project.godot` — rejestracja autoloadow (sekcja `[autoload]`; obecnie jej brak).
- `Player.gd` — HP/stamina czytane przez `StatsComponent`/`HealthComponent` zamiast hardkodu
  (tylko tyle, by udowodnic pipeline; pelny refaktor w Etapie 1). Zachowac sygnaly `hp_changed`/
  `stamina_changed` (HUD bez zmian).
- Mini-test: postac z `StatBlock` + testowy `ItemInstance` z `StatModifier(&"damage", INCREASED,
  0.2)` -> `get_stat(&"damage")` zwraca `18 x 1.2 = 21.6`.

**Pierwszy commit Etapu 0 (rekomendacja):** `StatModifier.gd` + `StatBlock.gd` +
`StatsComponent.gd` + `NetManager.gd` (stub) — minimalna petla danych do uruchomienia testu.

---

## 4. ETAP 1 — Mieso walki (szczegolowy plan plikow)

**Cel / Definition of Done:** gracz i wrog zbudowani z komponentow; atak gracza idzie sciezka
`AbilityComponent -> HitboxComponent -> DamageService -> HurtboxComponent -> HealthComponent`;
krytyk/pancerz/armor_pierce liczone w `DamageService` z `StatsComponent`; smierc wroga emituje
sygnal (hook pod loot); buff testowy zmienia staty przez pipeline; AI dziala jako host-only
komponent. Cala walka host-authoritative — w Etapie 7 dokladamy tylko transport.

**Autoload:**
- `DamageService.gd` — `request_hit(source, target, HitData)` -> `_resolve` (krytyk -> pancerz po
  przebiciu -> odpornosci -> `take_damage` -> lifesteal/statusy -> FX). Host-authoritative przez
  `NetManager.has_authority`. W SP rozstrzyga lokalnie.

**Komponenty — `res://components/`:**
- `HitboxComponent.gd` (Area3D) — okno czasowe (active frames) + lista trafionych
  (`PackedInt64Array`, czyszczona na starcie okna) + dociecie filtrem `dot()` (reuse
  `attack_arc_dot`); sub-stepping tylko dla waskich atakow. Zglasza do `DamageService` po stronie
  autorytetu.
- `HurtboxComponent.gd` (Area3D) — przyjmuje trafienie -> `HealthComponent.apply_damage`.
- `AbilityComponent.gd` — wykonuje `SkillResource`: koszt zasobu (Mana/Furia/Combo/Focus/stamina
  z `StatsComponent`), cooldown (`cdr`), cast_time, spawn `scene`, odpalenie Hitboxa; bufor/anulowanie.
- `BuffComponent.gd` — dodaj/usun czasowe `StatModifier` (po `source_id`), timery ->
  `StatsComponent.rebuild_modifiers()`.
- `AIComponent.gd` — refaktor istniejacej maszyny (idle/patrol/chase/attack/leash) na komponent;
  **host-only** (`if not NetManager.has_authority(self): return`). Uzywa `AbilityComponent`.
- `Projectile.gd` — wlasny ruch + CCD (raycast prev->new, mask `terrain|enemy_body`); pierce N
  (lista trafionych); impakt na terenie. Pod Slingera (ranged) i luk Rangera.
- `HazardZone.gd` (Area3D) — trwala strefa tykajaca (`duration`/`tick_interval`); tryb „preview”
  dla telegrafow elite/boss. Tyka (dmg) tylko na hoscie.

**Refaktor istniejacych plikow:**
- `Player.gd` -> root + `InputComponent` (input->intencje, gotowe pod predykcje) + `StatsComponent`
  + `HealthComponent` + `AbilityComponent` + `HurtboxComponent` + `HitboxComponent`. Atak LMB i
  unik RMB/Q jako `SkillResource` (atak podstawowy, dash). Combo->pierce jako flaga w `HitData`.
  **Lokalny hitstop** zdjac z globalnego `Engine.time_scale` na drodze co-opowej (ok. L1213).
- `Enemy.gd` -> root + `StatsComponent` (z `EnemyResource.stats`) + `HealthComponent` +
  `AIComponent` + `HurtboxComponent` + `HitboxComponent` + `LootComponent` (szkielet; pelny w
  Etapie 2). Brute/Slinger = warianty przez eksporty/Resource; Slinger spawnuje `Projectile`.
- `HUD.gd` — podpiecie pod `HealthComponent.damaged/died` i `StatsComponent.stats_changed` zamiast
  bezposredniego czytania pol; dodac widget zasobu klasy.

**Konkretna kolejnosc wdrozenia w Etapie 1 (najtaniej -> najwiecej wartosci):**
1. `DamageService` + `HitData` — owin istniejace `Player._deal_damage_to()` (ok. L1201): zamien
   inline na `DamageService.request_hit(self, enemy, _build_hit())`. W SP wola `_resolve` od razu ->
   zero zmian w grze, fundament sieci. (<- REKOMENDOWANY PIERWSZY KROK PO ETAPIE 0)
2. `MeleeHitbox`/`HitboxComponent` (Area3D + okno + lista trafionych) — zastap petle `dot()` w
   `_try_attack()` (ok. L1178).
3. Bufor inputu ataku/uniku + perfect-dodge + cancel tylko w recovery.
4. Lokalny hitstop (zdejmij globalny `time_scale` z drogi co-opowej).
5. `Projectile.gd` -> Slinger + luk Rangera; `HazardZone.gd` -> mag.
6. Telegrafy elite/boss (decal hitboxa przez „preview” HazardZone).
7. Krytyki/lifesteal/on-hit w `HitData` -> wpiecie afiksow lootu (zazebia sie z Etapem 2).

---

## 5. Skrot dalszych etapow (kamienie milowe)

- **Etap 2 — Loot+itemy:** `LootService` (rzadkosc -> slot -> `roll_item(seed, ilvl, biome, tier,
  slot)`), `ItemInstance` w plecaku/save, afiksy/sety/sockety/enchanty wpiete w `StatsComponent`
  przez `InventoryComponent`. UI ekwipunku + toast lootu. DoD: ubicie wroga dropi `ItemInstance`,
  zalozenie zmienia `get_stat()`, klejnot w sockecie dziala.
- **Etap 3 — Progresja:** drzewka per klasa (`SkillTreeResource`, skromne), alokacja pasywow,
  level/xp, zasoby klas (Mana/Furia/Combo+Focus) na pasku HUD, respec za Zloto/Orby. DoD: lvl up
  daje punkt, wezel zmienia staty, respec zwraca punkty za walute.
- **Etap 4 — Biomy+wrogowie:** `get_biome()` (rozszerzenie `biome_factor`), 3 `BiomeResource`,
  spawn tables, Brute/Slinger + warianty biomowe, telegrafy wg `threat_tier`. DoD: 3 biomy z
  wlasnym lootem/wrogami, deterministyczny spawn z seeda.
- **Etap 5 — Dungeony:** `DungeonEntrance.gd` + `DungeonGen.gd` (graf+BSP+stitching z
  `entrance_seed`, zamek-klucz), build w watku (reuse `WorkerThreadPool`/`Chunk`/`VoxelModel`).
  DoD: wejscie w swiecie -> instancja -> boss -> loot do postaci -> powrot.
- **Etap 6 — Pet:** `Allegiance.ALLY` + stan `FOLLOW` w `Enemy.gd`, `TameSystem` (lvl 5, cel <35%
  HP). DoD: oswojona bestia walczy u boku, skaluje sie z graczem.
- **Etap 7 — CO-OP:** `NetManager` live (Spawner/Synchronizer/RPC), predykcja+rekonsyliacja ruchu,
  walka/loot host-authoritative przez transport, host save. DoD: 2–4 graczy w jednym swiecie, brak
  desyncu HP/lootu, klient z wlasna postacia.
  - **Etap 7b (domkniecie — replikacja wspolnego swiata):** host-authoritative spawn/transform/HP
    wrogow, loot i pociskow replikowane host->klient przez RECZNY rejestr net_id + stabilny NodePath
    (`Enemy_<id>`/`Loot_<id>`) — patrz TDD 6.4b (wzorzec wybrany zamiast `MultiplayerSpawner`, by
    zachowac istniejacy kanal HP-sync po sciezce). Pickup lootu host-authoritative (klient ->
    `request_loot_pickup` -> host waliduje dystans/istnienie -> grant + despawn u wszystkich).
    Wrogowie u klienta to repliki (fizyka OFF, transform z `MultiplayerSynchronizer`). **DoD spelniony
    dla OTWARTEGO SWIATA ORAZ DUNGEONOW**: host przy wejsciu rozsyla `_rpc_load_dungeon(seed,tier,biome)`,
    klient buduje ten sam uklad lokalnie i dostaje repliki wrogow dungeonu pod `Main/DungeonRun`
    (path-match HP-sync). Pelna walidacja replikacji w zywej scenie wymaga RECZNEGO testu 2-graczy
    (residual_risks); headless pokrywa kontrakt + SP-bramki + transport ENet (Etap7bTest A/B/C).
- **Etap 8 — Polish:** balans (liczby z `GDD.md` 5/6), VFX/SFX (wlasne/CC0), UI/menu/ustawienia.
  DoD: grywalny vertical slice (pare itemow/klasa, pare mobow, 3 biomy).

## 6. Liczby balansu na pierwszy przebieg (vertical slice)

- **Gracz lvl 1:** HP 100, stamina 100 (regen 22/s, delay 0,6 s), krytyk 5% / x1,5; unik dash 16
  m/s 0,22 s, i-frames 0,30 s, CD 0,55 s, koszt 25; perfect-dodge okno 0,12 s.
- **Wojownik starter (Berserker):** atak LMB (0 Furii, +6/trafienie, CD 0,5 s), Wir Ostrzy (30
  Furii, CD 1 s, 0,8x dmg AoE r=2,5), Roztrzaskanie (35 Furii, CD 6 s, 1,8x + stun 1 s + 50%
  pierce), Szal Krwi (40 Furii, CD 12 s, +40% predkosci ataku + 15% lifesteal). Furia: +6/+4,
  zanik 5/s po 3 s, cap 100. Drzewko startowe 8 wezlow (Furia Bitwy -> +Obrazenia I/II, Twardziel,
  Wytrwalosc, Krwiozerczosc, Drugi Oddech, keystone Bez Opamietania lvl 25).
- **Wrogowie:** Goblin/trash (HP 30, dmg 8, speed 3,5, windup 0,35, armor 0 — = obecny `Enemy.gd`),
  Brute/elite (HP 120, dmg 18, speed 2,8, windup 0,55, armor 0,3), Slinger/ranged (HP 45, dmg 12
  pocisk, speed 3,0, windup 0,5, armor 0).
- **Cel odczuciowy:** gracz 2H ubija goblina 1 ciosem (30 >= 30 HP); Brute = 4 ciosy (mini-walka);
  horda 8–12 goblinow na arene. „Kosisz hordy, ale musisz sie ruszac”.
