# Czcionki UI (drop-in)

Motyw menu (`res://data/ui/wood_gold_theme.tres`, generowany przez `tools/build_ui_theme.gd`)
automatycznie użyje **pixel-czcionki**, jeśli wrzucisz tu plik:

```
assets/fonts/pixel.ttf
```

Bez tego pliku menu mają poprawny styl ramek/kolorów drewno-złoto, ale tekst rysuje się domyślną
(gładką) czcionką Godota. Po wrzuceniu `pixel.ttf` przebuduj motyw:

```
godot --headless --path . res://tools/build_ui_theme.tscn
```

## Polecane darmowe pixel-czcionki (licencje wolne — sprawdź przed użyciem)
- **monogram** (CC0) — czytelna, mała, klasyczny pixel.
- **Pixel Operator** (CC0/SIL) — wariant zwykły i bold, duży zestaw znaków (polskie ogonki!).
- **m5x7 / m6x11** (autor: Daniel Linssen, darmowe) — bardzo „retro".

WAŻNE: wybierz czcionkę z **polskimi znakami** (ą/ć/ę/ł/ń/ó/ś/ź/ż), inaczej menu pokażą krzaki.
Plik musi być Twój lub na licencji pozwalającej na użycie w grze (CC0/SIL/OFL) — spójnie z polityką
projektu (zero cudzych assetów bez licencji).
