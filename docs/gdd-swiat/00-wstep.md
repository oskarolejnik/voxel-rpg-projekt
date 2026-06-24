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
