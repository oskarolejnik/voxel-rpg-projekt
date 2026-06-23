## 2. Personalizacja wyglądu

System personalizacji wyglądu (Character Appearance Editor, dalej **CAE**) jest komponentem ekranu tworzenia postaci oraz dostępny ponownie u NPC "Mistrz Wyglądu" w hubach (barber/cosmetics). Architektura jest data-driven: każdy parametr to wpis w zasobie `AppearanceParam.tres`, a finalny wygląd postaci serializuje się do zasobu `CharacterAppearance.tres` (i równolegle do JSON na potrzeby import/export). Renderer wykorzystuje trzy mechanizmy modyfikacji modelu: **morph targety (blendshapes)**, **tekstury/decale** oraz **attach pointy (kości doczepowe)** dla ozdób.

### 2.1. Założenia techniczne

- **Bazowy mesh per rasa+płeć**: 6 ras × 2 płcie = 12 bazowych skinned-meshy (`res://characters/base/<rasa>_<plec>.glb`). Wszystkie współdzielą identyczny rig (humanoid skeleton, 1 spójny szkielet) — to warunek przenoszenia animacji i części ekwipunku.
- **Blendshapes**: do morfów sylwetki, twarzy i mięśni. Każdy bazowy mesh eksportuje znormalizowany zestaw shape keys (wartość 0.0–1.0, w Godot ustawiane przez `MeshInstance3D.set_blend_shape_value`).
- **Tekstury warstwowe**: skóra, włosy, oczy bazują na materiale PBR. Detale (blizny, tatuaże, piegi, makijaż, zarost teksturowy) realizowane jako **warstwy decali nakładane do atlasu** w czasie tworzenia (bake do jednej tekstury 2048², zob. 2.9 Wydajność), a nie jako osobne `Decal` node'y w runtime.
- **Attach pointy**: kolczyki, ozdoby, część biżuterii doczepiane jako `BoneAttachment3D` do nazwanych kości (`Head`, `Ear_L`, `Ear_R`, `Neck`, `Nose`).
- **Style wizualne**: dwa tryby palet — **Realistyczny** (naturalne zakresy) i **Stylizowany-Fantasy** (rozszerzone, fantazyjne kolory). Tryb to globalny toggle wpływający na to, które palety/zakresy są aktywne; nie blokuje zapisu — preset pamięta użyty tryb.

### 2.2. Sylwetka i budowa ciała

| Parametr | Kontrolka | Zakres / opcje | Mechanizm | Uwagi |
|---|---|---|---|---|
| Typ sylwetki | Lista (radio) | Smukła / Atletyczna / Masywna | Preset 3 blendshapów łącznie (`bs_slim`, `bs_athletic`, `bs_heavy`) jako punkty bazowe | Punkt startowy dla suwaków poniżej |
| Wzrost | Slider | 0.90–1.12 (mnożnik skali kości root, czyli ±~12%) | Skala szkieletu (uniform scale na `Skeleton3D` root z korektą stóp do podłoża) | Rasozależny zakres (patrz 2.8) |
| Budowa (waga/tusza) | Slider | 0.0–1.0 | Blendshape `bs_body_weight` | Wpływa na brzuch, uda, twarz |
| Szerokość barków | Slider | 0.0–1.0 | Blendshape `bs_shoulders` | |
| Rozmiar mięśni | Slider | 0.0–1.0 | Blendshape `bs_muscle` | Stylizowany pozwala >0.85 (przerysowane); Realistyczny soft-cap 0.85 |
| Obwód klatki/biust | Slider | 0.0–1.0 | Blendshape `bs_chest` | Zakres zależny od płci |
| Długość kończyn | Slider | -0.5–+0.5 | Blendshape `bs_limb_length` | Subtelne; Stylizowany szerszy |

Wszystkie blendshapy są addytywne i mieszane liniowo: finalny mesh = baza + Σ(waga_i × shape_i). Kolizja kapsuły gracza nie zmienia się z wyglądem (stała hitbox dla fair-play w co-op/PvE) — zmienia się tylko wizualny mesh.

### 2.3. Twarz

| Parametr | Kontrolka | Zakres / opcje | Mechanizm |
|---|---|---|---|
| Kształt twarzy (preset) | Lista | 6–10 presetów per rasa (owalna, kanciasta, okrągła...) | Zestaw blendshapów `bs_face_*` |
| Szerokość szczęki | Slider | 0.0–1.0 | `bs_jaw_width` |
| Wystawanie kości policzkowych | Slider | 0.0–1.0 | `bs_cheekbones` |
| Rozmiar/kształt nosa | 2× Slider | 0.0–1.0 (rozmiar, garb) | `bs_nose_size`, `bs_nose_bridge` |
| Rozmiar oczu | Slider | 0.0–1.0 | `bs_eye_size` |
| Rozstaw oczu | Slider | -0.5–+0.5 | `bs_eye_spacing` |
| Usta (pełność/szerokość) | 2× Slider | 0.0–1.0 | `bs_lips_full`, `bs_mouth_width` |
| Brwi (grubość/kąt) | 2× Slider | 0.0–1.0 | `bs_brow_thick`, `bs_brow_angle` |
| Uszy (rozmiar/szpic) | 2× Slider | 0.0–1.0 | `bs_ear_size`, `bs_ear_point` |

**Rasozależność twarzy**: Sylvani mają domyślnie podniesiony `bs_ear_point` (szpiczaste uszy, slider startuje ~0.7). Karłowie z Grimholdu mają szerszy zakres `bs_jaw_width` i `bs_cheekbones`. Orguni odblokowują kły (toggle `tusks`, blendshape `bs_tusks` 0–1). Feruni mają dodatkowe parametry pyska (zob. 2.8).

### 2.4. Fryzury i zarost

| Parametr | Kontrolka | Zakres / opcje | Mechanizm |
|---|---|---|---|
| Fryzura | Lista z miniaturami | 24–40 modeli (`hair_*.glb`) + "brak" | Wymienny mesh doczepiony do `BoneAttachment3D` (Head); osobny skinned submesh |
| Długość/objętość włosów | Slider (opcjonalny per fryzura) | 0.0–1.0 | Blendshape na meshu włosów (gdy fryzura wspiera) |
| Zarost (broda/wąsy) | Lista | 0–15 modeli + "brak" | Mesh doczepiony (Head) LUB decal teksturowy dla krótkiego zarostu |
| Gęstość zarostu | Slider | 0.0–1.0 | Alpha decala zarostu (gdy teksturowy) |
| Brwi (kolor osobno) | Toggle | wł/wył dziedziczenia koloru włosów | Override koloru |

Zarost dostępny zależnie od płci/rasy: Karłowie mają najbogatszy zestaw bród (15 modeli, w tym splecione z koralikami — koraliki jako attach pointy). Sylvani i Feruni mają ograniczony zarost. Embrani mogą mieć "tlące się" końcówki włosów (efekt emisyjny w trybie Stylizowanym).

### 2.5. Kolory (skóra, włosy, oczy)

| Parametr | Kontrolka | Realistyczny | Stylizowany-Fantasy | Mechanizm |
|---|---|---|---|---|
| Kolor skóry | Paleta (swatche) + koło HSV | 18 naturalnych odcieni (jasne→ciemne) | + niebieski/zielony/szary/czerwony (Embrani: rozżarzona) | `albedo_color` materiału skóry (tint na bazowej teksturze) |
| Kolor włosów | Koło kolorów HSV + swatche | naturalne: czerń, brąz, blond, rude, siwy | dowolny HSV + 2-tonowe gradienty | `albedo_color` + opcjonalny `secondary_tint` materiału włosów |
| Kolor oczu | Paleta + koło HSV | brąz, niebieski, zielony, szary, piwny | + świecące (emisja), heterochromia (L≠R) | `albedo_color` tęczówki + `emission` (fantasy) |
| Intensywność emisji oczu | Slider (tylko fantasy) | n/d | 0.0–3.0 | `emission_energy` |

Tryb Realistyczny **klampuje** wybór koła kolorów do dozwolonego podzbioru (np. włosy: nasycenie ≤ 0.4, jasność w naturalnym zakresie); Stylizowany zdejmuje klamp. Embrani w obu trybach mają minimalny "ember glow" skóry (subtelna emisja w szczelinach — implementowane przez maskę emisji w materiale).

### 2.6. Detale skóry: blizny, tatuaże, piegi, makijaż

Wszystkie realizowane jako **warstwy decali bakowane do atlasu** (zob. 2.9). Każda warstwa ma: ID wzoru, region (twarz/tułów/ramiona/nogi), kolor (tint), intensywność (alpha), pozycję UV i skalę.

| Parametr | Kontrolka | Zakres / opcje | Mechanizm |
|---|---|---|---|
| Blizny | Lista warstw (toggle + wybór wzoru) | 0–20 wzorów; do **4 warstw** jednocześnie | Decal normal+albedo, region wybierany |
| Tatuaże | Lista warstw + paleta koloru | 0–40 wzorów; do **6 warstw** | Decal albedo z tintem; pozycja/skala edytowalna |
| Piegi | Toggle + slider gęstości | wł/wył, 0.0–1.0 | Decal albedo (maska) na twarzy/ramionach |
| Makijaż — oczy | Lista + paleta | 0–10 wzorów (cienie, kreska) | Decal albedo na twarzy |
| Makijaż — usta | Paleta + slider | kolor + intensywność | Tint regionu ust |
| Malowidła wojenne (fantasy/Orguni/Feruni) | Lista + paleta | 0–15 wzorów | Decal albedo, jaskrawe kolory |

Realistyczny vs Stylizowany: w trybie Realistycznym tatuaże/malowidła mają stonowane palety i brak emisji; w Stylizowanym dozwolone neonowe kolory i opcja **emisji wzoru** (świecące tatuaże — np. runiczne dla Magów/Nekromantów tematycznie). Embrani mogą mieć tatuaże "z żaru" (animowana emisja w shaderze).

### 2.7. Ozdoby (kolczyki, biżuteria)

Realizowane jako **attach pointy** (`BoneAttachment3D`) — modele 3D doczepiane do nazwanych kości. Nie wpływają na blendshapes ani tekstury.

| Parametr | Kontrolka | Opcje | Punkt doczepienia |
|---|---|---|---|
| Kolczyki — uszy | Lista (L/R osobno lub para) | 0–12 modeli + "brak" | `Ear_L`, `Ear_R` |
| Kolczyk — nos | Lista | 0–6 modeli | `Nose` |
| Naszyjnik kosmetyczny | Lista | 0–8 modeli | `Neck` |
| Korale we włosach/brodzie | Lista | 0–6 zestawów | child fryzury/brody |
| Rogi/ozdoby głowy (fantasy) | Lista | 0–10 (rasozależne) | `Head` |

Uwaga na konflikt z ekwipunkiem: hełm z ekwipunku może **ukrywać** włosy/ozdoby głowy (flaga `hides_hair`, `hides_head_attachments` na itemie). Ozdoby kosmetyczne mają niższy priorytet niż gear w gnieździe głowy.

### 2.8. Rasozależność — podsumowanie różnic

- **Duryjczycy**: pełny, neutralny zakres wszystkich suwaków (referencyjny). Wzrost 0.92–1.10.
- **Sylvani**: smuklejsza domyślna sylwetka, szpiczaste uszy (start), szerszy zakres `bs_eye_size`, naturalne włosy + (fantasy) odcienie srebra/zieleni. Wzrost 0.95–1.12.
- **Karłowie z Grimholdu**: niższy wzrost (0.85–0.98), szerszy `bs_shoulders`/`bs_muscle`, bogate brody, szeroki `bs_jaw`. Skala root korygowana, by proporcje były krępe (osobny mnożnik szerokości).
- **Embrani**: ember-touched — slider "żaru skóry" (emisja w szczelinach 0.0–1.0), włosy z żarzącymi się końcówkami (fantasy), kolory skóry rozszerzone o rozżarzone odcienie. Wzrost 0.92–1.10.
- **Orguni**: masywna domyślna sylwetka, toggle kłów (`bs_tusks`), wyższy soft-cap mięśni (1.0 nawet w Realistycznym), malowidła wojenne. Wzrost 1.00–1.12.
- **Feruni**: beastkin — dodatkowe parametry: typ pyska (lista, `bs_muzzle_*`), uszy zwierzęce (lista modeli zamiast `bs_ear_point`), ogon (lista modeli + attach `Tail`), wzór futra (decal tilingowy zamiast gładkiej skóry), pazury. Wzrost 0.90–1.10.

Mechanizm rasozależności: każdy `AppearanceParam.tres` ma słownik `race_overrides` z polami `min`, `max`, `default`, `hidden`, `locked_options`. CAE buduje UI z parametrów aktywnych dla wybranej rasy+płci.

### 2.9. Wydajność (limity warstw decali, słaby GPU)

- **Bake do atlasu**: wszystkie warstwy decali (blizny, tatuaże, piegi, makijaż, malowidła) są jednorazowo renderowane do **jednej tekstury skóry 2048×2048** (na słabym GPU fallback 1024²) podczas akceptacji wyglądu, a nie nakładane jako node'y `Decal` w czasie gry. Dzięki temu w świecie postać ma stały koszt: 1 materiał skóry, 1 materiał włosów, 1 materiał oczu.
- **Twardy limit warstw**: blizny ≤ 4, tatuaże ≤ 6, makijaż ≤ 3, piegi 1, malowidła ≤ 3. Łącznie ≤ 17 operacji bake — mieści się w jednym przebiegu compose.
- **Budżet blendshapów**: ≤ 24 aktywne shape keys na mesh ciała (wpływ na pamięć i koszt skinningu); twarz osobno ≤ 16.
- **LOD ozdób**: attach pointy z modelami biżuterii znikają na LOD2+ (dystans) — kolczyki/korale nie renderują się z daleka.
- **Co-op**: u zdalnych graczy detale decali bakują się przy wejściu w zasięg; do tego czasu skóra bazowa bez detali (progresywne ładowanie).

### 2.10. Losowanie wyglądu (determinizm i seed)

Przycisk **"Losuj"** generuje kompletny wygląd deterministycznie z 64-bitowego **seeda**. Ten sam seed + ta sama rasa + płeć + tryb (Real/Fantasy) = zawsze identyczny wynik (ważne dla powtarzalności i debugowania).

- Implementacja: `var rng := RandomNumberGenerator.new(); rng.seed = appearance_seed`.
- Kolejność losowania jest stała (sylwetka → twarz → fryzura/zarost → kolory → detale → ozdoby), dzięki czemu wynik jest deterministyczny niezależnie od platformy.
- Każdy parametr losuje w obrębie swojego rasozależnego `min`–`max`; opcje listowe przez `rng.randi() % count`.
- Liczba warstw detali losowana w granicach limitów z 2.9.
- Wyświetlany seed (hex) można skopiować i wkleić, by odtworzyć dokładnie ten sam wygląd. Pole "Seed" w UI jest edytowalne.
- Suwak **"Siła losowania"** (0.0–1.0) zawęża losowanie wokół wartości domyślnych rasy (0.0 = tylko domyślne, 1.0 = pełny zakres) — bez łamania determinizmu (mnożnik aplikowany deterministycznie).

### 2.11. Presety — reguły per rasa/płeć

- Preset zapisuje **pełny stan** `CharacterAppearance` + metadane (rasa, płeć, tryb, wersja schematu).
- Slotów lokalnych: 20 na konto + nielimitowane przez import/export plików.
- **Walidacja przy wczytaniu**: preset jest "kompatybilny" tylko jeśli `race` i `sex` zgadzają się z aktualnie tworzoną postacią. Wczytanie presetu innej rasy → opcja "Konwertuj" (mapuje wspólne parametry, parametry niedostępne dla docelowej rasy są pomijane, brakujące przyjmują default; konwersja oznaczana flagą `converted: true`).
- Parametry zablokowane/ukryte dla danej rasy są przy zapisie pomijane, a przy wczytaniu uzupełniane z defaults rasy.
- Wbudowane presety startowe: 3–5 per rasa+płeć (kuratorowane "twarze przewodnie"), oznaczone `builtin: true`, tylko-do-odczytu (można je wczytać i zapisać jako nowy slot).
- Niezgodność `schema_version` → migracja: brakujące pola dostają defaults, usunięte pola są ignorowane; przy większej różnicy wersji ostrzeżenie w UI.

### 2.12. Import / Export presetów

- **Export**: serializacja stanu do pliku `.vrpgapp` (JSON UTF-8) zapisywanego w `user://appearance_presets/`. Opcjonalnie eksport jako tekst Base64 do schowka ("Udostępnij kod") — krótki ciąg do wklejenia znajomemu.
- **Import**: z pliku `.vrpgapp` lub z wklejonego kodu Base64. Walidacja: poprawność JSON, obecność wymaganych pól, zgodność/konwersja rasy (2.11), sanity-check zakresów (klamp wartości spoza min–max), odrzucenie ID wzorów/modeli nieistniejących w bieżącej wersji gry (zastąpienie defaultem + ostrzeżenie).
- Bezpieczeństwo: importer **nie wykonuje kodu**, czyta wyłącznie znane pola (whitelist kluczy); nieznane klucze ignorowane.
- Integralność: opcjonalne pole `checksum` (CRC32 ciała JSON) — przy niezgodności ostrzeżenie, ale import dozwolony.

### 2.13. Format presetu (przykład JSON)

```json
{
  "schema_version": 3,
  "type": "vrpg_appearance_preset",
  "meta": {
    "name": "Embrańska Berserkerka",
    "author": "Oskar",
    "created_utc": "2026-06-21T10:30:00Z",
    "builtin": false,
    "converted": false,
    "checksum": "0x8FA31C2D"
  },
  "race": "Embrani",
  "sex": "female",
  "style_mode": "fantasy",
  "appearance_seed": "0x7F3A19C204DE8B11",
  "body": {
    "silhouette": "athletic",
    "height": 1.04,
    "weight": 0.35,
    "shoulders": 0.62,
    "muscle": 0.71,
    "chest": 0.55,
    "limb_length": 0.05
  },
  "face": {
    "preset": "face_emb_03",
    "jaw_width": 0.4,
    "cheekbones": 0.66,
    "nose_size": 0.45,
    "nose_bridge": 0.3,
    "eye_size": 0.58,
    "eye_spacing": -0.05,
    "lips_full": 0.6,
    "mouth_width": 0.5,
    "brow_thick": 0.4,
    "brow_angle": 0.55,
    "ear_size": 0.5,
    "ear_point": 0.0,
    "tusks": 0.0,
    "ember_skin_glow": 0.45
  },
  "hair": {
    "style": "hair_long_braided_07",
    "volume": 0.7,
    "beard": "none",
    "beard_density": 0.0,
    "brow_color_override": false
  },
  "colors": {
    "skin": { "h": 12, "s": 0.55, "v": 0.62, "tint": "#B5562F" },
    "hair_primary": "#C81E1E",
    "hair_secondary": "#FF7A18",
    "hair_two_tone": true,
    "eyes": "#FFB000",
    "eye_emission": 1.6,
    "heterochromia": false
  },
  "detail_layers": {
    "scars": [
      { "pattern": "scar_face_02", "region": "face", "uv": [0.31, 0.44], "scale": 0.8, "tint": "#7A4B3A", "alpha": 0.7 }
    ],
    "tattoos": [
      { "pattern": "tat_ember_runes_05", "region": "arm_r", "uv": [0.6, 0.3], "scale": 1.0, "tint": "#FF5A00", "alpha": 0.9, "emissive": true },
      { "pattern": "tat_tribal_11", "region": "torso", "uv": [0.5, 0.55], "scale": 1.2, "tint": "#FF5A00", "alpha": 0.85, "emissive": false }
    ],
    "freckles": { "enabled": false, "density": 0.0 },
    "makeup": {
      "eyes": { "pattern": "makeup_eye_03", "tint": "#1A0A0A", "alpha": 0.6 },
      "lips": { "tint": "#8E1B1B", "alpha": 0.5 }
    },
    "warpaint": [
      { "pattern": "warpaint_06", "region": "face", "uv": [0.5, 0.4], "scale": 1.0, "tint": "#FF3300", "alpha": 0.9 }
    ]
  },
  "ornaments": {
    "earring_l": "earring_hoop_03",
    "earring_r": "earring_hoop_03",
    "nose_ring": "none",
    "necklace": "necklace_ember_01",
    "hair_beads": "none",
    "head_piece": "horns_short_02"
  }
}
```

### 2.14. Przepływ akceptacji (od edytora do gry)

1. CAE buduje stan w pamięci (live preview na modelu w scenie kreatora).
2. Po "Akceptuj": warstwy decali bakowane do atlasu skóry (2.9), zapis `CharacterAppearance.tres` + JSON do `user://`.
3. W świecie gry postać ładuje base mesh + zbakowane tekstury + blendshapy + attach pointy (stały koszt renderu).
4. Wizyta u "Mistrza Wyglądu" wczytuje JSON z powrotem do CAE, umożliwiając pełną edycję (zachowanie spójne z importem presetu).
