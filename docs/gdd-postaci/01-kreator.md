## 1. Kreator postaci

Kreator postaci to wieloetapowy przepływ tworzenia nowej postaci gracza, uruchamiany przy starcie nowej gry lub z menu wyboru postaci. Składa się z 8 etapów, prowadzonych liniowo z możliwością swobodnego cofania. Kreator jest w pełni data-driven: rasy, klasy, pochodzenia i opcje wyglądu pochodzą z zasobów `.tres`, a stan budowanej postaci żyje w jednym obiekcie roboczym (draft), który jest zapisywany lokalnie po każdej zmianie etapu.

### 1.1. Założenia architektoniczne

- **Singleton kreatora** — autoload `CharacterCreator` (singleton) przechowuje aktualny `CharacterDraft`, indeks aktywnego etapu, historię etapów (do cofania) oraz referencje do katalogów zasobów (rasy/klasy/pochodzenia).
- **Draft jako Resource** — budowana postać to instancja `CharacterDraft` (`extends Resource`), serializowalna do `.tres`/`.res`. Każde pole etapu zapisuje się bezpośrednio w drafcie. Dzięki temu cofanie i wznawianie nie wymaga osobnej logiki — wystarczy odczyt pól.
- **Katalogi danych** — `RaceCatalog`, `ClassCatalog`, `OriginCatalog`, `AppearanceCatalog` to autoloady ładujące tablice `RaceData`/`ClassData`/`OriginData`/`AppearanceOptionData` z `res://data/...`. UI nigdy nie hardkoduje treści — czyta z katalogów.
- **Walidacja warstwowa** — każdy etap ma metodę `validate(draft) -> StageValidation` zwracającą `{ ok: bool, errors: Array[String] }`. Przycisk „Dalej” jest aktywny tylko gdy `ok == true`.
- **Stałe domyślne** — przy starcie draft jest wstępnie wypełniony domyślnymi wartościami (pierwsza rasa, płeć neutralna, pochodzenie pasujące do rasy, klasa „Wojownik”, neutralny preset wyglądu, puste imię), aby gracz w trybie „szybki start” mógł kliknąć „Dalej” przez większość etapów.

### 1.2. Model danych draftu

```gdscript
# res://data/character/character_draft.gd
class_name CharacterDraft
extends Resource

@export var race_id: StringName = &""          # Etap 1
@export var gender_id: StringName = &"neutral" # Etap 2 (m / f / neutral)
@export var origin_id: StringName = &""         # Etap 3
@export var class_id: StringName = &""          # Etap 4
@export var appearance: Dictionary = {}         # Etap 5: { skin, hair_style, hair_color, face, height, voxel_palette, accessory }
@export var character_name: String = ""        # Etap 6
@export var created_at_utc: int = 0             # Etap 8
@export var draft_version: int = 1              # migracje
@export var schema_uuid: String = ""            # unikalny id draftu
```

| Pole draftu | Ustawiane w etapie | Typ | Wymagane do utworzenia |
|---|---|---|---|
| `race_id` | 1 | StringName | Tak |
| `gender_id` | 2 | StringName | Nie (domyślnie `neutral`) |
| `origin_id` | 3 | StringName | Tak |
| `class_id` | 4 | StringName | Tak |
| `appearance` | 5 | Dictionary | Nie (domyślny preset) |
| `character_name` | 6 | String | Tak |

### 1.3. Etapy kreatora — wymagalność

| # | Etap | Wymagany? | Można pominąć? | Domyślna wartość |
|---|---|---|---|---|
| 1 | Wybór rasy | Tak | Nie | Duryjczycy |
| 2 | Wybór płci | Nie | Tak (→ neutralna) | Neutralna |
| 3 | Wybór pochodzenia | Tak | Nie | pierwsze pochodzenie zgodne z rasą |
| 4 | Wybór klasy | Tak | Nie | Wojownik |
| 5 | Personalizacja wyglądu | Nie | Tak (→ preset) | Preset „Domyślny” danej rasy/płci |
| 6 | Nadanie imienia | Tak | Nie | brak (puste — wymaga wpisania) |
| 7 | Podsumowanie | Tak (ekran) | Nie (tylko podgląd) | — |
| 8 | Utworzenie postaci | Tak (akcja) | Nie | — |

---

### Etap 1 — Wybór rasy

**Cel.** Wybór jednej z 6 ras kanonicznych. Rasa determinuje dostępne pochodzenia (filtr w etapie 3), bazową paletę wokseli i sylwetki w etapie 5 oraz drobne modyfikatory startowe.

**Co gracz widzi i robi.** Siatka/karuzela 6 kart ras z miniaturą modelu 3D (podgląd na żywo, obracalny), nazwą i 2–3 zdaniami lore. Po prawej panel szczegółów: opis rasy, biom pochodzenia, drobne cechy (patrz tabela). Kliknięcie karty zaznacza rasę i aktualizuje podgląd 3D.

**Dane wejściowe → wyjściowe.** Wejście: `RaceCatalog.get_all()`. Wyjście: `draft.race_id`.

**Walidacja i przejście.** `race_id != &""` oraz istnieje w katalogu. Zawsze spełnione (domyślnie Duryjczycy). „Dalej” zawsze aktywne.

**Wstecz.** Brak (to pierwszy etap) — zamiast tego przycisk „Anuluj” (przerwanie, patrz 1.4). Stan rasy zachowany w drafcie.

**UX / podpowiedzi.** Tooltip na cechach rasowych; podświetlenie biomu na mini-mapie świata; podgląd 3D obraca się automatycznie + ręcznie myszą.

**Domyślnie.** Duryjczycy (uniwersalni — najbezpieczniejszy wybór dla nowych graczy).

| Rasa | Biom domyślny | Drobne cechy startowe (kosmetyczne/miękkie, bez psucia balansu) |
|---|---|---|
| Duryjczycy | Verdant Hollow (obrzeża) | Brak skrajności — neutralny start, +1 slot szybkiego dostępu na samouczku |
| Sylvani | Verdant Hollow | Cichszy chód (kosmetyka stealth), bonus do tropienia zielarstwa |
| Karłowie z Grimholdu | Frosthelm Peaks | Odporność na poślizg na lodzie, bonus do wykrywania żył rudy |
| Embrani | Emberwaste | Brak obrażeń od łagodnego gorąca terenu, ciepłe światło emisyjne |
| Orguni | Emberwaste / step | Większy domyślny przeskok ciężaru ekwipunku (kosmetyka udźwigu) |
| Feruni | Verdant Hollow | Lepsze widzenie nocne, szybsze wykrywanie tropów zwierzyny |

> Uwaga balansowa: cechy rasowe są celowo „miękkie” (eksploracja, czytelność, komfort), bez wpływu na DPS/EHP. Twardy balans pochodzi z klasy i lootu.

---

### Etap 2 — Wybór płci (opcjonalny)

**Cel.** Ustawienie prezentacji modelu i animacji bazowych. Płeć jest czysto kosmetyczna — nie wpływa na staty.

**Co gracz widzi i robi.** Trzy opcje: Męska, Żeńska, Neutralna (androgeniczna sylwetka). Przycisk „Pomiń” ustawia Neutralną i przechodzi dalej. Podgląd 3D natychmiast zmienia sylwetkę.

**Dane wejściowe → wyjściowe.** Wejście: warianty sylwetki z `RaceData.body_variants`. Wyjście: `draft.gender_id` (`m` / `f` / `neutral`).

**Walidacja i przejście.** Zawsze ważne (domyślnie `neutral`). „Dalej” aktywne zawsze; „Pomiń” dostępne.

**Wstecz.** Powrót do etapu 1; wybór płci zachowany.

**UX / podpowiedzi.** Etykieta: „Płeć jest wyłącznie kosmetyczna i nie wpływa na statystyki ani rozgrywkę.” Zmiana płci może zresetować część presetów wyglądu zależnych od sylwetki (etap 5) — wyświetl tooltip, jeśli gracz wraca i zmienia płeć po personalizacji.

**Domyślnie.** Neutralna.

---

### Etap 3 — Wybór pochodzenia (Origin / Background)

**Cel.** Nadanie postaci tła fabularnego z drobnymi bonusami startowymi (ekwipunek, punkt startu w świecie, jeden „miękki” modyfikator). Pochodzenia są filtrowane wg rasy (rekomendowane), ale gracz może wybrać dowolne odblokowane.

**Co gracz widzi i robi.** Lista ~6 pochodzeń. Domyślnie posortowana: u góry pochodzenia „polecane” dla wybranej rasy (powiązanie biomowe), potem reszta. Każda pozycja: nazwa, lore (2–3 zdania), startowy ekwipunek, punkt startu, drobny bonus. Karta „polecane” oznaczona ikoną.

**Dane wejściowe → wyjściowe.** Wejście: `OriginCatalog.get_for_race(race_id)`. Wyjście: `draft.origin_id`.

**Walidacja i przejście.** `origin_id` istnieje w katalogu. Domyślnie ustawiane pierwsze polecane → „Dalej” aktywne od razu.

**Wstecz.** Powrót do etapu 2; wybór zachowany. Uwaga: jeśli gracz zmieni rasę w etapie 1, a obecne pochodzenie nie jest już polecane, wybór NIE jest kasowany (pozostaje ważny, traci tylko znacznik „polecane”) — chyba że pochodzenie było ekskluzywne dla starej rasy, wtedy reset do domyślnego + komunikat.

**UX / podpowiedzi.** Podgląd punktu startu na mini-mapie świata; jasna informacja, że bonusy są drobne i wyrównane między pochodzeniami.

**Domyślnie.** Pierwsze pochodzenie polecane dla rasy.

#### Tabela pochodzeń (~6)

| Pochodzenie | Polecane dla ras | Lore (skrót) | Punkt startu (biom) | Startowy ekwipunek | Drobny bonus (miękki) |
|---|---|---|---|---|---|
| **Dziecko Kniei** | Sylvani, Feruni | Wychowani w gęstwinie Verdant Hollow, znają każdy szept lasu. | Verdant Hollow — Polana Pierwszych Kroków | Prosty łuk treningowy, 5 strzał, skórzany kaftan, 3 zioła lecznicze | +5% szybkości zbierania ziół |
| **Czeladnik Kuźni** | Karłowie z Grimholdu, Duryjczycy | Terminowali w kuźniach Grimholdu pośród dymu i żaru. | Frosthelm Peaks — Brama Grimholdu | Młot roboczy, fartuch wzmacniany, kilof, 10 sztabek żelaza, 1 mikstura | +5% szybkości wydobycia rudy |
| **Najemnik Traktów** | Duryjczycy, Orguni | Pilnowali karawan na szlakach Duralanii za garść monet. | Verdant Hollow — Rozdroże Kupieckie | Krótki miecz, drewniana tarcza, podróżny płaszcz, 25 sztuk złota | +25 sztuk złota startowego |
| **Pielgrzym Popiołów** | Embrani, Orguni | Wędrowcy spalonych pustkowi, hartowani przez ogień i pragnienie. | Emberwaste — Oaza Spękanego Kamienia | Włócznia, bukłak (większy), tunika żaroodporna, 2 mikstury | Odporność na łagodne przegrzanie terenu |
| **Sierota Murów** | Wszystkie (uniwersalne) | Bezimienni z zaułków miast — przetrwanie nauczyło ich wszystkiego po trosze. | Verdant Hollow — Miasto Startowe (Duralis) | Sztylet, lekka kurtka, wytrych (x3), 10 sztuk złota | +1 dodatkowy slot torby na start |
| **Uczeń Wieży** | Duryjczycy, Sylvani, Embrani | Studiowali zasady mocy w akademiach Duralanii i strzeżonych wieżach. | Verdant Hollow — Akademia Liściastej Wieży | Różdżka treningowa, szata płócienna, księga zaklęć (pusta), 2 mikstury many | +5% regeneracji zasobu klasowego poza walką |

> Balans: każdy bonus to ~5% w domenie pomocniczej (eksploracja/ekonomia) LUB drobny komfort startowy (slot, złoto, odporność środowiskowa). Żadne pochodzenie nie daje przewagi bojowej; „Sierota Murów” jest celowo uniwersalna jako bezpieczny domyślny wybór dla każdej rasy.

---

### Etap 4 — Wybór klasy

**Cel.** Wybór jednej z 11 klas kanonicznych. Klasa determinuje zasób klasowy (Furia/Mana/Focus), bazowy zestaw umiejętności startowych i archetyp rozgrywki. To główna decyzja balansowa.

**Co gracz widzi i robi.** Siatka 11 kart klas pogrupowana wg roli (Walka wręcz / Dystans-skradanie / Magia). Karta: ikona, nazwa, zasób klasowy, krótki opis, 1–2 startowe umiejętności (z animowanym podglądem). Panel szczegółów pokazuje bazowy pipeline statów (base→flat→increased%→more) i broń startową.

**Dane wejściowe → wyjściowe.** Wejście: `ClassCatalog.get_all()`. Wyjście: `draft.class_id`.

**Walidacja i przejście.** `class_id` istnieje w katalogu. Domyślnie „Wojownik”. „Dalej” aktywne od razu.

**Wstecz.** Powrót do etapu 3; wybór zachowany.

**UX / podpowiedzi.** Filtr ról; tag „dla początkujących” na Wojowniku/Łuczniku/Kapłanie; podgląd zasobu klasowego (kolor paska zasobu). Brak twardych restrykcji rasa↔klasa (każda rasa może grać każdą klasą — czytelność i wolność wyboru), opcjonalnie znacznik „popularne dla tej rasy”.

**Domyślnie.** Wojownik.

| Grupa | Klasy | Zasób klasowy |
|---|---|---|
| Walka wręcz | Wojownik, Paladyn, Berserker, Mnich | Furia (Berserker, Wojownik) / Mana (Paladyn) / Focus (Mnich) |
| Dystans / skradanie | Łucznik, Łotrzyk, Zabójca | Focus |
| Magia | Mag, Nekromanta, Kapłan, Druid | Mana |

---

### Etap 5 — Personalizacja wyglądu (opcjonalny)

**Cel.** Dostosowanie wyglądu woksela: paleta skóry, fryzura/kolor, twarz (warianty), wzrost/sylwetka (w granicach rasy), paleta voxelowa, opcjonalne akcesorium. Czysto kosmetyczne.

**Co gracz widzi i robi.** Po lewej duży, obracalny podgląd 3D z oświetleniem; po prawej zakładki: Sylwetka, Skóra, Włosy, Twarz, Paleta, Akcesoria. Slidery i swatche kolorów. Przyciski „Losuj wygląd” i „Przywróć preset”. Każda zmiana natychmiast aktualizuje podgląd.

**Dane wejściowe → wyjściowe.** Wejście: `AppearanceCatalog.get_for(race_id, gender_id)`. Wyjście: `draft.appearance` (Dictionary, patrz 1.2).

**Walidacja i przejście.** Zawsze ważne — brak wymaganych pól (preset domyślny jest zawsze poprawny). „Dalej” i „Pomiń” aktywne.

**Wstecz.** Powrót do etapu 4; pełen stan wyglądu zachowany. Jeśli gracz wcześniej zmienił rasę/płeć, niezgodne opcje (np. fryzura nieistniejąca dla nowej sylwetki) są mapowane na najbliższy odpowiednik lub na preset; reszta zachowana.

**UX / podpowiedzi.** „Losuj” generuje spójną kombinację z palety rasy; preset „Domyślny” gwarantuje dobry wygląd jednym kliknięciem; podgląd na neutralnym i na świecie (tło biomu pochodzenia).

**Domyślnie.** Preset „Domyślny” dla pary `race_id` + `gender_id`.

---

### Etap 6 — Nadanie imienia

**Cel.** Nadanie unikalnej (w obrębie zapisu/serwera) nazwy postaci.

**Co gracz widzi i robi.** Pole tekstowe z licznikiem znaków, przycisk „Losuj imię” (generator wg rasy), podgląd imienia nad modelem 3D. Walidacja na żywo z komunikatami pod polem.

**Dane wejściowe → wyjściowe.** Wejście: tekst gracza. Wyjście: `draft.character_name`.

**Walidacja i przejście.** Reguły:
- długość 3–20 znaków,
- dozwolone: litery (w tym polskie znaki), pojedyncze spacje/myślniki/apostrofy wewnątrz, bez cyfr i symboli specjalnych,
- bez podwójnych spacji, bez spacji na początku/końcu,
- filtr wulgaryzmów (lista zakazana w `res://data/character/name_blocklist.tres`),
- w trybie co-op/online: sprawdzenie unikalności (jeśli zajęte → komunikat „Imię jest zajęte”).

„Dalej” aktywne tylko gdy `validate() == ok`. To jedyne pole bez domyślnej wartości — wymaga wpisania lub wylosowania.

**Wstecz.** Powrót do etapu 5; wpisany tekst zachowany.

**UX / podpowiedzi.** Komunikaty błędów precyzyjne („Imię jest za krótkie — min. 3 znaki”). „Losuj imię” zawsze daje poprawne, unikalne (lokalnie) imię zgodne z rasą.

**Domyślnie.** Puste (brak).

---

### Etap 7 — Podsumowanie

**Cel.** Przegląd wszystkich wyborów przed zatwierdzeniem; ostatnia szansa na korektę.

**Co gracz widzi i robi.** Karta podsumowania: duży podgląd 3D postaci (z imieniem), tabela wyborów (rasa, płeć, pochodzenie, klasa), startowy ekwipunek i punkt startu, zastosowane bonusy pochodzenia, zasób klasowy. Przy każdym wierszu przycisk „Edytuj” skaczący bezpośrednio do odpowiedniego etapu (z zachowaniem draftu i powrotem na etap 7 po edycji — tzw. „edit-and-return”).

**Dane wejściowe → wyjściowe.** Wejście: cały `draft`. Wyjście: brak nowych pól (tylko podgląd). Uruchamia pełną walidację wszystkich etapów (`CharacterCreator.validate_all()`).

**Walidacja i przejście.** Wszystkie wymagane pola muszą być poprawne. Jeśli któreś nie jest (np. puste imię z powodu obejścia), pokaż błąd i zablokuj „Utwórz postać”, z linkiem do wadliwego etapu.

**Wstecz.** Powrót do etapu 6 (lub do dowolnego etapu przez „Edytuj”).

**UX / podpowiedzi.** Wyraźny, główny przycisk „Utwórz postać”; checklista zielonych „ptaszków” przy poprawnych sekcjach.

---

### Etap 8 — Utworzenie postaci

**Cel.** Finalizacja: konwersja draftu na trwały zapis postaci i wejście do gry (lub powrót do ekranu wyboru postaci).

**Co gracz widzi i robi.** Po kliknięciu „Utwórz postać”: animacja/przejście, krótki ekran ładowania. W tle:
1. ponowna `validate_all()` (zabezpieczenie),
2. zbudowanie obiektu `CharacterSave` z draftu (rasa, płeć, pochodzenie, klasa, wygląd, imię),
3. nadanie startowego ekwipunku i punktu startu z `OriginData`,
4. inicjalizacja statów przez pipeline base→flat→increased%→more z `RaceData` + `ClassData`,
5. ustawienie poziomu 1 (cap 99) i pustego ekwipunku poza startowym,
6. zapis `CharacterSave` do `user://characters/<schema_uuid>.tres`,
7. usunięcie pliku draftu (`user://drafts/active_draft.tres`),
8. emisja sygnału `character_created(character_id)`.

**Dane wejściowe → wyjściowe.** Wejście: `draft`. Wyjście: trwały `CharacterSave` + `created_at_utc` ustawione na czas zapisu.

**Walidacja i przejście.** Jeśli walidacja przejdzie → przejście do świata/wyboru postaci. Jeśli zapis się nie powiedzie (np. błąd I/O) → komunikat błędu, draft NIE jest kasowany, powrót do etapu 7.

**Wstecz.** Brak (po utworzeniu postaci kreator się kończy). Przed kliknięciem — „Wstecz” wraca do etapu 7.

**Domyślnie.** —

---

### 1.4. Diagram przepływu (state flow)

```
                                  [START: Nowa postać]
                                          |
                                          v
   +-----------------------------------------------------------------------+
   |                          KREATOR (draft aktywny)                       |
   |                                                                        |
   |  (1) Rasa ──Dalej──> (2) Płeć ──Dalej/Pomiń──> (3) Pochodzenie         |
   |    ^                    ^  (Pomiń => neutral)        |                  |
   |    |  <──Wstecz─────────+  <──Wstecz────────────────-+                  |
   |    |                                                  |                 |
   |    |                                          ──Dalej─v                 |
   |  Anuluj                              (4) Klasa ──Dalej──> (5) Wygląd    |
   |    |                                     ^                    |  ^      |
   |    |                          <──Wstecz──+   <──Wstecz────────+  |      |
   |    |                                                  Dalej/Pomiń|      |
   |    |                                                            v       |
   |    |                                 (6) Imię <──Wstecz── (7) Podsum.   |
   |    |                                   |   ──Dalej(walid. OK)──> ^      |
   |    |                                   | <──Wstecz───────────────+      |
   |    |                                   |                                |
   |    |                       [Edytuj X] z (7) skacze do etapu X,          |
   |    |                       po zapisie wraca do (7) (edit-and-return)    |
   |    |                                                                    |
   |    |                              (7) ──"Utwórz postać"(walid_all OK)── |
   +----|--------------------------------------------------------|----------+
        |                                                         v
        v                                                  (8) Utworzenie
   [PRZERWANIE]                                                   |
        |                                            sukces       |   błąd
        |                                          +──────────────+──────────+
        v                                          v                         v
   {Zapis draftu?}                          [Zapis CharacterSave]    [Błąd I/O ->
   - Tak  -> zapis user://drafts/...          + usunięcie draftu      komunikat,
            -> powrót do menu                  + sygnał created       draft zostaje,
   - Nie  -> porzuć draft -> menu                   |                  wróć do (7)]
   - Anuluj -> wróć do kreatora                     v
                                              [WEJŚCIE DO GRY /
                                               EKRAN WYBORU POSTACI]
```

### 1.5. Obsługa przerwania (Anuluj / Esc / wyjście)

W każdym etapie dostępny jest „Anuluj” (oraz klawisz `Esc`). Wywołuje dialog:

- **„Zapisz szkic i wyjdź”** — draft zapisany do `user://drafts/active_draft.tres`; przy następnym wejściu do kreatora gra wykrywa istniejący draft i proponuje „Wznów tworzenie postaci”.
- **„Odrzuć i wyjdź”** — draft usunięty, powrót do menu.
- **„Wróć do kreatora”** — zamknięcie dialogu, kontynuacja od bieżącego etapu.

Nagłe zamknięcie aplikacji jest bezpieczne, bo draft jest zapisywany inkrementalnie (patrz 1.6).

### 1.6. Zapis postępu (draft)

- **Kiedy zapis:** po każdym udanym przejściu „Dalej”/„Wstecz” oraz po każdej zmianie pola (debounce 500 ms dla pól tekstowych/sliderów). Plik: `user://drafts/active_draft.tres`.
- **Format:** serializacja `CharacterDraft` (Resource → `.tres`). Pole `draft_version` umożliwia migracje przy zmianie schematu.
- **Wznowienie:** przy wejściu do kreatora `CharacterCreator` sprawdza istnienie `active_draft.tres`. Jeśli istnieje → ekran „Wznów / Zacznij od nowa”. „Wznów” wczytuje draft i ustawia ostatni aktywny etap (zapisany w `CharacterCreator.last_stage_index`, również trzymany w pliku stanu kreatora `user://drafts/active_stage.cfg`).
- **Integralność:** zapis atomowy (zapis do pliku tymczasowego `.tmp` + rename), aby nie uszkodzić draftu przy awarii.
- **Po utworzeniu:** draft jest kasowany w etapie 8 dopiero po pomyślnym zapisaniu `CharacterSave`.

### 1.7. Stałe celownik / podgląd 3D w kreatorze (uwaga implementacyjna)

Podgląd postaci w kreatorze działa na osobnej scenie `CharacterPreviewViewport` (`SubViewport` + obrotowa kamera orbitalna). Nie korzysta z modelu sterowania rozgrywki (face-movement/combat-aim z sekcji 7) — jest to statyczny model z animacjami idle/emote i ręcznym obrotem myszą. Dzięki rozdzieleniu scen zmiany w drafcie (rasa, płeć, wygląd) odświeżają wyłącznie viewport podglądu, bez ingerencji w logikę gracza w świecie.
