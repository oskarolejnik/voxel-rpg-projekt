# Zasady prawne projektu (łańcuch praw autorskich)

> Cel: gra, której Oskar Olejnik jest w 100% autorem i właścicielem.
> To wymaga DYSCYPLINY od pierwszego dnia. *Informacja ogólna, nie porada prawna.*

## Dlaczego nie „przerobimy Cube World"

- Cube World jest **chronione prawem autorskim** (Picroma / Wolfram von Funck), do ~2070+.
- „Porzucony / abandonware" **nie znaczy** „wolny od praw" — to nie jest status prawny.
- Folder „Cube World Alpha" zawiera **skompilowane binarki i zamknięte assety** — bez kodu źródłowego. Nie da się ich legalnie „otworzyć i zmienić na swoje".
- Dlatego budujemy **oryginalną grę inspirowaną gatunkowo**, nie kopię.

## ✅ WOLNO (nie podlega prawu autorskiemu)

- Używać **gatunku**: voxelowy action-RPG z eksploracją.
- Odtwarzać **mechaniki, reguły, systemy** (walka, loot, klasy, crafting, traversal, pety).
- Czerpać z **ogólnego „feelu"** na poziomie abstrakcyjnym.
- **Grać** w Cube World i **obserwować**, jak działają mechaniki, by je zaprojektować od nowa.
- Uczyć się z **architektury** projektów open-source (np. Veloren) i re-implementować pomysły **własnym kodem**.

## ❌ NIE WOLNO (naruszenie praw)

- Kopiować/dekompilować `Cube.exe`, `Server.exe` ani żadnej binarki.
- Wypakowywać/konwertować/używać assetów z `data*.db`, `*.plx`, `*.dat`, `logo.bmp`.
- Używać nazwy „Cube World", logo, czcionek, dźwięków, muzyki, modeli z gry — **nawet jako placeholder**.
- Odtwarzać assetów **1:1 ze screenshotów** (to też kopia pochodna).
- Kopiować kodu z projektów GPL (np. Veloren) ani ich forkować, jeśli chcemy pełnej własności (GPL = copyleft).
- Nazywać gry tak, by sugerować związek z Cube World / Picromą (ryzyko wprowadzenia w błąd).

## ✅ ROBIMY zamiast tego

- Wszystkie assety **od zera** (MagicaVoxel/Blender) lub z licencji **CC0 / CC-BY** (z atrybucją).
- Własna, **sprawdzona pod kątem clearance** nazwa i logo.
- **`CREDITS.md`** uzupełniany przy KAŻDYM dodanym asfecie (pochodzenie, autor, licencja, URL, data).
- **Git** z datowanymi commitami (dowód, kiedy i przez kogo coś powstało).
- Trzymanie **plików źródłowych** assetów (`.vox`, `.blend`, projekty audio) w repo.
- Przy współpracownikach: **umowa o przeniesienie praw / work-for-hire** PRZED rozpoczęciem prac.

## Przed komercyjną premierą

- Krótka, płatna **konsultacja z polskim prawnikiem IP**.
- Clearance nazwy w **EUIPO/TMview**, **USPTO** (jeśli rynek USA), Steam, domeny.
- Unikać licencji **copyleft** (GPL/AGPL/CC-BY-SA) w zamykanym produkcie.

## Test „go / no-go" w jednym zdaniu

> Jeśli plik/fragment **pochodzi z Cube World** albo **dałby się rozpoznać jako Cube World** — NIE.
> Jeśli to **Twój oryginał** lub **legalnie licencjonowany** materiał wyrażający wspólną mechanikę — TAK.
