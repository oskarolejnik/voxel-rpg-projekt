# Instrukcja: instalacja Godota i uruchomienie prototypu

## 1. Pobierz Godota 4 (5 minut, bez instalatora)

1. Wejdź na **https://godotengine.org/download/windows/**
2. Pobierz **„Godot Engine" — wersję STANDARD** (NIE „.NET/C#" — my piszemy w GDScript).
   Wybierz **4.3 lub nowszą** (dowolna 4.x).
3. To jest ZIP z jednym plikiem `.exe` — rozpakuj go gdziekolwiek (np. `C:\Users\oskar\Godot\`).
   Godot nie wymaga instalacji — po prostu uruchamiasz ten `.exe`.

## 2. Otwórz projekt

1. Uruchom `Godot_v4.x...exe`.
2. W oknie projektów kliknij **„Import"** (Importuj).
3. Wskaż plik: `C:\Users\oskar\Downloads\voxel-rpg\project.godot`
4. Kliknij **„Import & Edit"**.
   - Przy pierwszym otwarciu Godot przez chwilę „importuje" projekt — to normalne.
   - Jeśli pojawi się informacja o innej wersji silnika — wybierz „Convert/OK"; projekt jest prosty i się otworzy.

## 3. Uruchom grę

- Naciśnij **F5** albo kliknij **▶ (Play)** w prawym górnym rogu.
- Scena główna jest już ustawiona (`Main.tscn`), więc gra od razu wystartuje.

## 4. Co powinieneś zobaczyć

- 🟩 Zielona, płaska ziemia i błękitne, proceduralne niebo.
- 🟧 24 kolorowe słupki rozrzucone wokół (punkty odniesienia).
- 🧍 Beżowa „kapsuła" — to Twoja postać (własny model voxel zrobimy w Etapie 3).
- Na górze ekranu podpowiedź ze sterowaniem.

**Sterowanie:**
| Klawisz | Akcja |
|---|---|
| `W A S D` | ruch (względem kamery) |
| mysz | obrót kamery |
| `spacja` | skok |
| `shift` | bieg |
| `ESC` | pokaż/ukryj kursor (żeby wyjść/kliknąć) |

## 5. Jeśli coś nie działa — jak mi zgłosić

Na dole edytora Godota są zakładki **„Output"** (Wyjście) i **„Debugger"**.
Jeśli zobaczysz **czerwone błędy** albo gra się nie uruchomi:

1. Skopiuj całą czerwoną treść z panelu **Output / Debugger**.
2. Wklej mi ją tutaj (możesz też zrobić zrzut ekranu).

Naprawię i podeślę poprawkę. Nie zniechęcaj się — przy pierwszym uruchomieniu drobne
poprawki to norma, zwłaszcza że piszę kod „na ślepo" (bez Godota w moim środowisku).

---

## Na później (Etap 2 — teren voxelowy)

Do nieskończonego, sześciennego terenu użyjemy modułu **`godot_voxel`** (Voxel Tools)
Zylanna. To rozszerzenie silnika — pobiera się gotowy build Godota z tym modułem
(https://github.com/Zylann/godot_voxel — sekcja Releases / dokumentacja).
Zajmiemy się tym, gdy Etap 1 będzie u Ciebie ładnie działał. Na Etap 1 wystarczy
zwykły Godot.
