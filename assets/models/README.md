# Modele 3D (drop-in z Blendera) — kontrakt

Wrzucaj tu modele wyeksportowane z Blendera. Format **glTF 2.0 binary (`.glb`)** —
Godot 4.7 importuje go natywnie, jeden plik niesie mesh + materiały + (opcjonalnie)
szkielet + animacje. Po wrzuceniu daj znać CO to jest (postać? prop? broń?) i czy
jest zriggowane — wtedy wpinam do gry.

## Struktura katalogów
```
assets/models/
  characters/   # gracz, NPC, pet/towarzysz
  enemies/      # goblin, brute, slinger, bossy
  weapons/      # miecze, łuki, tarcze, hełmy (attach do dłoni/głowy)
  props/        # dekoracje, runo, skały, skrzynie — statyczne
```

## Eksport z Blendera (File ▸ Export ▸ glTF 2.0)
- **Format:** glTF Binary (`.glb`)
- **+Y Up:** ZAZNACZONE (Blender jest Z-up, Godot Y-up — eksporter konwertuje osie)
- **Apply Modifiers:** ZAZNACZONE
- **Postać/stwór animowany:** zaznacz *Include ▸ Armature* + *Animation* (wszystkie akcje/NLA)
- **Materiały:** Export Materials = Export

## Konwencje silnika (żeby pasowało bez poprawek)
- **Skala:** postać ≈ **2 m** wysokości (kapsuła kolizji ma height 2.0, stopy na y=0).
  Prop/broń w skali realnej względem tego.
- **Orientacja:** przód postaci patrzy w **-Z** (Godot forward). Twarz/oczy do -Z.
- **Origin:** dla postaci/propów origin u STÓP (y=0), nie w środku bryły.
- **Materiały — pod RTX 3050 4 GB:** najlepiej 1 materiał na model, vertex colors albo
  mała tekstura palety (≤512²). Voxel = low-poly, więc to zwykle naturalne.
- **Poly/tekstury:** trzymaj nisko; bez 4K tekstur i milionów tri (budżet 4 GB VRAM).

## Dwie ścieżki dla POSTACI (wybór zależy od tego jak zrobiłeś model)
1. **Zriggowane w Blenderze** (szkielet + animacje) — importuję Skeleton3D +
   AnimationPlayer/AnimationTree i zastępuję proceduralne `_animate()` Twoimi klipami.
   Najczystsze, najlepszy efekt; wymaga że model MA kości i animacje.
2. **Statyczna bryła** (jeden mesh, bez kości) — albo (a) zostaje statyczna (tylko obrót
   + bob), albo (b) PODZIEL w Blenderze na części pasujące do riga gry
   (tułów, głowa, ramię górne+dolne, noga górna+dolna ×2) i każdą doczepiam do istniejących
   pivotów — wtedy DZIAŁA cała animacja chodu/biegu/ataku którą już mamy.

## Co dostarczyć przy wrzucaniu
- Pliki `.glb` w odpowiednim podkatalogu.
- Lista: który plik = co (np. `player.glb` = gracz, `goblin.glb` = wróg).
- Czy postać jest zriggowana i jakie ma animacje (idle/walk/run/attack...).
