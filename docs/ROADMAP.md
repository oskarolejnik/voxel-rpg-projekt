# Roadmapa — etapy projektu

Zasada nadrzędna: **każdy etap kończy się czymś grywalnym/uruchamialnym.** Walczymy ze
scope creep — najpierw mała, skończona rzecz, potem kolejna warstwa.

---

## ETAP 0 — Fundamenty projektu ✅ (w trakcie)

- [x] Research (prawo, historia, mechaniki, stack, marka) → `RESEARCH-DOSSIER.md`
- [x] Struktura repo, README, LICENSE, .gitignore
- [x] GDD v0.1, zasady prawne (`LEGAL.md`), tracker assetów (`CREDITS.md`), lista nazw (`NAMING.md`)
- [x] **Decyzja: silnik** → **Godot 4** (wybór Oskara, 2026)
- [ ] Instalacja narzędzi (Godot 4 + później MagicaVoxel) — patrz `SETUP.md`
- [ ] Inicjalizacja Git (`git init`, pierwszy commit)

## ETAP 1 — Hello, 3D (2–4 tyg.)

- [x] Projekt Godota utworzony (`project.godot`, `Main.tscn`, `src/Main.gd`, `src/Player.gd`)
- [x] Scena 3D: podłoga, model-gracz (kapsuła), ruch WASD, kamera 3rd-person, skok, bieg — **kod gotowy**
- [ ] **Uruchomienie u Oskara** (zainstaluj Godota, ▶ Play) i potwierdzenie, że działa
- [ ] **Kamień milowy:** „chodząca kostka" — sterowalna postać na terenie ✅ po uruchomieniu

## ETAP 2 — Teren voxelowy ✅ (zweryfikowany)

Zaimplementowane przez zespół agentów (czysty GDScript, bez modułu godot_voxel):
- [x] Generacja chunku z szumu (FastNoiseLite, heightmapa) — `src/world/Chunk.gd`
- [x] Streaming chunków wokół gracza + kolejka budowy (anty-zacięcia) — `src/world/VoxelWorld.gd`
- [x] Kolizje (trimesh) i chodzenie po nierównym terenie
- [x] 5 typów terenu wg wysokości (piasek/trawa/ziemia/skała/śnieg) + woda w dolinach — `src/world/Blocks.gd`
- [x] Optymalizacje: face culling, twarde normalne, mikro-wariacja koloru, pseudo-AO
- [x] „Kill plane" — gdy gracz wypadnie pod świat, wraca na grunt
- [x] **Zweryfikowane przez Claude** (zrzut z gry + test ruchu 12 m). Naprawy: odwrócone nawijanie (CW), `vertex_color_is_srgb`, SDFGI off, auto-podskok, strojenie światła
- [ ] (Opcjonalnie, później) stawianie/usuwanie bloków
- [x] **Kamień milowy:** biegasz po nieskończonym, proceduralnym, voxelowym świecie ✅

### Strojenie wydajności (gdyby tnęło)
- `src/world/VoxelWorld.gd`: `render_distance` (domyślnie 6 → zmniejsz np. do 4) oraz
  `chunks_per_frame` (domyślnie 1 → zwiększ do 2–3, by szybciej doładowywać świat).

## ETAP 3 — Vertical slice action-RPG (2–4 mies.)

- [x] Własna postać voxel + animacja chodu (B1/B+) — zamiast modelu MagicaVoxel (B2 później)
- [x] **R1: Walka** (atak LMB, unik RMB/Q + i-frames + stamina, combo→przebicie pancerza) — zweryfikowane
- [x] **R1: Wróg + AI** (patrol→pościg→atak→leash), `src/Enemy.gd` — zweryfikowane
- [x] **R1: HP, obrażenia, śmierć/respawn** (gracz i wróg) + HUD (HP/stamina, licznik wrogów) — zweryfikowane
- [ ] **R2:** drop lootu, licznik/poziomy XP, save/load (pozycja + postęp)
- [ ] Dostrojenie balansu wrogów; (później) pathfinding (teraz mogą utknąć na stromym terenie)
- [ ] **Kamień milowy:** grywalny prototyp „czy to jest fun?" — rdzeń walki ✅, pełnia po R2

## ETAP 4 — Warstwa RPG (3–6 mies.)

- [ ] Ekwipunek + przedmioty + statystyki
- [ ] **Poziomy + drzewko umiejętności (model alfy — moc trwała)**
- [ ] Kilka biomów, proste POI/questy
- [ ] Audio (własne/CC0), polish UI, menu, ustawienia
- [ ] **Kamień milowy:** mała, kompletna pętla rozgrywki

## ETAP 5 — Multiplayer (opcjonalnie, później)

- [ ] Co-op 2–4 graczy (high-level networking silnika)
- [ ] Synchronizacja świata/postaci

---

## Plan po Etapie 2 (ustalony z Oskarem: A → B → C)

**A) Żywy świat** 🌍 ✅ **ZROBIONE i zweryfikowane** (zrzuty dzień+noc z gry):
- [x] Drzewa (pień WOOD + korona LEAVES), krzaki, kamienie — proceduralnie, deterministycznie (`feature_hash`), wbudowane w voxele (kolizja+AO)
- [x] Cykl dnia i nocy — `src/DayNight.gd` (doba 240 s; słońce/niebo/ambient/mgła; noc ciemna, ale widoczna)
- [ ] (Później) więcej biomów, dopracowanie wody, stawianie/usuwanie bloków
- Drobny znany minus: auto-podskok potrafi „wspinać się" po pniu drzewa (do poprawy po stronie Playera w przyszłym etapie)

**Restyl wizualny → Cube World** 🧊 ✅ **ZROBIONE i zweryfikowane** (96 FPS, zrzut z gry):
- [x] Voxel terenu 1 m → 0,5 m (drobniejszy, mniej „Minecraft"); skala w metrach zachowana
- [x] Drobne propy (trawa/kwiaty/grzyby) ~0,25 m jako osobny mesh → „sześciany różnej wielkości"
- [x] Bogatsze kolory, gradient trawy, warianty (jesienne liście, mszyste głazy), śnieg na szczytach
- [x] Wydajność: AO per-wierzchołek off (zostaje SSAO), render_distance=4, chunks_per_frame=2 → ~96 FPS
- [ ] (Później) płynne ładowanie przez wątki (WorkerThreadPool) lub moduł godot_voxel — eliminacja chwilowego „doczytywania" na starcie

**B) Własna postać voxel** 🧍 — **B1 ✅ ZROBIONE i zweryfikowane** (zrzut z gry):
- [x] Kapsuła zastąpiona voxelowym „ludzikiem" z kostek w `src/Player.gd` (`_build_voxel_character`): głowa/włosy/oczy, tunika/pasek, ręce/dłonie, nogi/buty
- [x] **B+** obrót postaci w kierunku ruchu + animacja chodu (kołysanie kończyn na pivotach) — zweryfikowane
- [ ] (Później) B2 — model z MagicaVoxel, gdy zechcesz usiąść do edytora (mamy przewodnik)

**C) Etap 3 — rdzeń action-RPG** ⚔️ — walka (atak, unik z i-frames, stamina,
combo-jako-przebicie-pancerza), pierwszy wróg + AI (patrol→pościg→atak), HP, loot, XP, save.

→ Następnie Etap 4 (warstwa RPG: ekwipunek, poziomy/drzewko „model alfy", questy, audio, UI).

## Decyzje już podjęte

- **Silnik:** ✅ Godot 4 (MIT, pełna własność).
- **Model progresji:** ✅ „alfa" — trwałe poziomy/drzewko, moc nieutracalna.
- **Start:** ✅ single-player (multiplayer dopiero po potwierdzeniu, że gra jest fun).

## Otwarte decyzje (na później)

- **Rdzeń v1:** która pętla jest sercem MVP — walka+loot, walka+traversal, czy walka+crafting? (rozstrzygniemy przy Etapie 3 / C)
- **Nazwa:** wybór z `NAMING.md` + clearance (teraz używamy nazwy roboczej).
- **Komercja:** czy celujemy w wydanie/sprzedaż (wpływa na licencje i konsultację prawną)?
