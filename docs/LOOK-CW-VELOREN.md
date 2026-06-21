# Look Cube World / Veloren — wnioski wizualne (research)

Cel: trafić w „look CW", nie w „klocki jak Minecraft".

## Co definiuje ten look (esencja)
1. **Miękkie, powietrzne oświetlenie** — ambient góruje nad twardym kierunkowym; brak brudnych ostrych cieni; ciepłe słońce, chłodny cień.
2. **Atmosferyczna mgła dystansu** — kolor mgły = kolor nieba przy horyzoncie; dalekie wzgórza toną miękko. Podpis gatunku.
3. **Kontrast skali voxela** — gruby, czytelny teren (0,5 m) + DROBNIEJSZE, urocze postacie/propy (~0,15–0,2 m). To odróżnia od Minecrafta.
4. **Wysokie nasycenie + czysta paleta per-biom** — każdy biom jeden dominujący hue.
5. **Żywy świat** — gęste propy (trawa-sprites) + wiatr + reaktywne światła (glow).
6. **Woda jako bohater** (Veloren) — fresnel, przezroczystość, kolor wg głębi, foam, opcj. kaustyka.
7. **Cykl dnia/nocy** napędzający nastrój (ciepły dzień / nastrojowa noc, złota godzina).
8. **Sylwetka z charakterem** — chibi: duża głowa, wyraziste (emisyjne) oczy.

## TOP 8 zmian — status u nas
| # | Zmiana | Status |
|---|---|---|
| 1 | Mgła aerial (kolor nieba przy horyzoncie) | ✅ 0A (`fog_aerial_perspective`) |
| 2 | Hemisferyczny ambient, wysoki udział rozproszonego | ✅ 0B (shader terenu) |
| 3 | Nasycenie + paleta per-biom | ✅ saturacja (0A); 🔜 palety per-biom (2C) |
| 4 | Edge-AO w shaderze terenu | ✅ 0B |
| 5 | Kontrast skali voxela + chibi-oczy postaci | 🔜 (postać: emisyjne oczy/proporcje — 2D) |
| 6 | Woda fresnel + depth-color + foam | ◑ 1B (fresnel ✅; foam/depth-color 🔜) |
| 7 | Drobne propy z wiatrem (MultiMesh) | ✅ 1A (wiatr) ; gęstość/MultiMesh 🔜 |
| 8 | Cykl dnia/nocy + glow (point-glow) | ✅ dzień/noc + glow; point-glow ognisk 🔜 |

## Konkretne wartości z researchu (do użycia)
- Hemi ambient: niebo `#BFD6E6` (chłodne jasne) → ziemia `#6B5A42` (ciepła).
- Palety biomów: łąka `#6FB23C`, śnieg `#E8F0F5`, pustynia `#D9B26B`.
- Woda: brzeg `#5FC8C8` → głębia `#1A4E73`; foam na styku z lądem (depth diff); 2 ruchome normalmapy; opcj. kaustyka.
- Dzień/noc: dzień słońce `#FFF1D0`; złota godzina `#FF9E5E`; noc chłodny błękit `#2A3A6B`, niski ambient, księżyc jako delikatne kierunkowe.
- AGX + `adjustment_saturation` ~1.15. SSAO subtelnie. Glow threshold wysoki (świecą tylko światła/woda/oczy).
- Edge-AO siła max ~0,25–0,3 (delikatnie, nie brudzić).

Źródła: Wikipedia/Fandom Cube World; Kotaku; veloren.net devblogi 81 (światło/cienie) i 156 (woda/point-glow); wiki Veloren.
