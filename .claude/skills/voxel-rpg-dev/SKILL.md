---
name: voxel-rpg-dev
description: Playbook projektu "Voxel RPG" — oryginalna gra voxel action-RPG w Godot 4 inspirowana Cube World. Użyj, gdy pracujesz nad kodem, designem, grafiką lub assetami tej gry, aby trzymać się ustaleń (silnik, model progresji) i ZASAD PRAWNYCH (pełna własność, zero materiałów z Cube World).
---

# Voxel RPG — playbook deweloperski

Gra Oskara Olejnika: **oryginalny voxelowy action-RPG inspirowany Cube World**, do którego
Oskar ma mieć **pełne prawa autorskie**. To NIE jest kopia/rebranding Cube World.

## Niezmienne ustalenia

- **Silnik:** Godot 4 (GDScript). Licencja MIT, zero tantiem, pełna własność. (Unreal/Bevy odrzucone.)
- **Model progresji:** „alfa" — trwałe poziomy + drzewko umiejętności; gracz NIGDY nie traci mocy.
  Świeżość regionów przez skalowanie wrogów + klucze traversalu (NIE region-locking z CW 1.0).
- **Lokalizacja:** `C:\Users\oskar\Downloads\voxel-rpg\`. Materiał CW jest osobno i służy TYLKO jako referencja mechanik.
- **Język komentarzy w kodzie:** polski (Oskar się uczy).

## ŻELAZNE zasady prawne (patrz docs/LEGAL.md)

- ✅ Wolno kopiować MECHANIKI, gatunek, systemy, „feel" (idea/expression — pomysły nie są chronione).
- ❌ NIGDY nie używaj kodu/assetów/nazwy/logo/dźwięków z Cube World (`Cube.exe`, `data*.db`, `*.plx`, `logo.bmp`).
- ❌ NIE odtwarzaj assetów 1:1 ze screenshotów CW. ❌ NIE kopiuj kodu z projektów GPL (np. Veloren) — można się uczyć, nie kopiować.
- ✅ Assety tylko własne (MagicaVoxel/Blender) lub CC0/CC-BY (z atrybucją). Każdy asset → wpis w `CREDITS.md`.

## Konwencje techniczne

- Świat budujemy w KODZIE (skrypty), aby projekt działał bez ręcznej pracy w edytorze i był czytelny.
- Pliki kodu w `src/`. Statyczne typowanie GDScript gdzie sensownie. Bez nieużytych zmiennych (prefiks `_`).
- Sterowanie gracza: na razie `Input.is_physical_key_pressed` (docelowo Input Map / akcje).
- Wydajność: voxele chunkowane, mały render_distance, kolejka budowy chunków (anty-zacięcia).
- Nie mamy Godota w środowisku asystenta → kod musi być poprawny "od pierwszego strzału";
  po implementacji ZAWSZE przepuszczaj kod przez adwersaryjny code-review (sprawdzanie realnych API Godota 4.x).

## Mapa etapów (docs/ROADMAP.md)

1. ✅ Etap 1 — Hello 3D (postać + kamera 3rd-person).
2. ▶ Etap 2 — proceduralny teren voxelowy (czysty GDScript; godot_voxel później).
3. Etap 3 — vertical slice action-RPG (walka, wróg z AI, HP, loot, XP, save).
4. Etap 4 — warstwa RPG (ekwipunek, poziomy/drzewko, biomy, questy, audio, UI).
5. Etap 5 — multiplayer co-op (opcjonalnie).

## Jak pracować nad tym projektem (dla asystenta / zespołu agentów)

- Czytaj `docs/RESEARCH-DOSSIER.md` (pełen kontekst), `docs/GDD.md` (design), `docs/ROADMAP.md` (kolejność).
- Duże etapy realizuj „zespołem": projekt (równolegle) → implementacja → adwersaryjny review → synteza.
- Po każdym etapie: zaktualizuj ROADMAP, CREDITS i poproś Oskara o uruchomienie (F5) + raport.
- Trzymaj scope w ryzach (wróg nr 1 = scope creep): najpierw mała grywalna rzecz, potem warstwa.

## Weryfikacja zmian SAMODZIELNIE (bez czekania na użytkownika)

Asystent MOŻE uruchamiać Godota przez Bash i sam sprawdzać efekt:
- **Godot exe:** `C:\Users\oskar\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe`
- **Błędy skryptów/runtime:** `"<godot>" --headless --path "C:\Users\oskar\Downloads\voxel-rpg" --quit-after 120` i grep po `error|parse|invalid`.
- **Zrzut z gry (rendering):** tymczasowo dodać do `Main._ready()` funkcję, która `await get_tree().create_timer(2.0).timeout`, potem `await RenderingServer.frame_post_draw`, `get_viewport().get_texture().get_image().save_png("C:/.../_probe_shot.png")`, `get_tree().quit()`. Uruchomić z OKNEM: `"<godot>" --path "<proj>" --quit-after 600`. Odczytać PNG (Read). **PO WERYFIKACJI USUNĄĆ SONDĘ** (inaczej gra zamyka się sama).
- **Test ruchu/wejścia:** w sondzie `Input.parse_input_event(InputEventKey z physical_keycode=KEY_W, pressed=true)`, odczekać, porównać `_player_ref.global_position`.
- Computer-use (sterowanie pulpitem) NIE działa na Godota — przenośny exe nie jest rozpoznawany przez `request_access`. Używać metody przez Bash powyżej.

## Częste pułapki Godota (już napotkane — sprawdzaj najpierw je)

- **Nawijanie:** Godot rysuje jako PRZEDNIE ściany nawinięte CW od zewnątrz. Zła kolejność = niewidoczny mesh (culling). 
- **Vertex colors:** ustaw `material.vertex_color_is_srgb = true`, inaczej kolory wychodzą blade/wyprane.
- **SDFGI:** ładne, ale zalewa scenę światłem i obciąża słabsze GPU — ostrożnie/wyłączać przy problemach z wyglądem lub FPS.
- **CharacterBody3D nie wchodzi sam na stopnie** — na blokowym terenie potrzebny auto-podskok lub logika step-up.
- **Nowy `class_name` pisany spoza edytora** — globalny cache klas Godota jest nieświeży → „Could not find type X". Najpierw `--headless --path <proj> --import`, dopiero potem `--quit-after`.
- **Nietypowane `const`-tablice** — indeksowanie zwraca `Variant`, więc `var x := tablica[i]` daje „Cannot infer the type". Typuj tablice: `const A: Array[float] = [...]` / `Array[Color]`.
- **Wydajność voxeli 0,5 m** — wąskim gardłem jest KOSZT BUDOWY chunku (CPU meshing single-thread), nie renderowanie. Per-wierzchołkowe AO jest najdroższe → wyłącz, polegaj na SSAO. Steady-state FPS mierz z `VSYNC_DISABLED` (inaczej cap 60 maskuje problem) — niski FPS tuż po starcie to zwykle trwająca budowa chunków, nie render. Skalowanie zasięgu (render_distance) ograniczone czasem ładowania; docelowo WorkerThreadPool lub moduł godot_voxel.
