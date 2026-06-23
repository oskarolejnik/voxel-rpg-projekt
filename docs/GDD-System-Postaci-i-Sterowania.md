# Game Design Document — System Tworzenia Postaci i Sterowania (TPP/MMORPG)

Wersja 1.0 · Silnik: Godot 4.7 (GDScript)

---

## Streszczenie wykonawcze

Niniejszy dokument definiuje kompletny, gotowy do implementacji system tworzenia postaci oraz model sterowania dla voxelowego action-RPG osadzonego w świecie Duralanii. Gra jest grą TPP (widok zza pleców) ze stałym celownikiem na środku ekranu, ruchem względem kamery, kooperacją do 4 graczy i progresją opartą głównie na loocie (level cap 99). Świat dzieli się na trzy biomy referencyjne: Verdant Hollow (las), Emberwaste (pustynia/ogień) i Frosthelm Peaks (śnieg/góry). System opiera się na sześciu kanonicznych rasach (Duryjczycy, Sylvani, Karłowie z Grimholdu, Embrani, Orguni, Feruni) i jedenastu klasach (Wojownik, Paladyn, Berserker, Łucznik, Łotrzyk, Zabójca, Mag, Nekromanta, Kapłan, Druid, Mnich).

Architektura jest w pełni data-driven: rasy, klasy, pochodzenia, presety wyglądu, reguły nazw oraz profile sterowania żyją jako zasoby `.tres` (Resource), a nie jako kod. Dodanie nowej rasy, klasy czy pochodzenia sprowadza się do utworzenia pliku `.tres` i umieszczenia go w odpowiednim katalogu, bez zmian w GDScript. Postać gracza to scena złożona z komponentów (kompozycja zamiast dziedziczenia), do których fabryka wstrzykuje dane wybrane w kreatorze. Statystyki przechodzą jednolity pipeline `base → flat → increased% → more`, a walka jest host-authoritative (autorytet po stronie hosta/serwera).

Dokument celuje w jakość odczuwalną na poziomie najlepszych przedstawicieli gatunku (World of Warcraft, Guild Wars 2, Final Fantasy XIV, Black Desert Online, New World, The Elder Scrolls Online). Najwyższym priorytetem jest sterowanie: docelowy model to **face-movement + combat-aim** — poza walką postać biegnie zawsze twarzą w kierunku ruchu (płynny obrót, w tym obrót ~180° przy „S" i bieg przodem), a w walce orientuje się płynnie w stronę celownika (raycast z kamery przez środek ekranu), z którego startują pociski i ataki kierunkowe. Pozostałe priorytety to intuicyjność, płynność, responsywność, łatwa rozbudowa (data-driven) oraz nowoczesny design.

---

## Filary projektowe

- **Intuicyjność.** Kreator prowadzi gracza liniowo przez czytelne etapy z domyślnymi wartościami pozwalającymi na „szybki start". Sterowanie jest natychmiast zrozumiałe: ruch względem kamery, stały celownik, brak ukrytych trybów.
- **Płynność.** Obrót postaci, kamera i przejścia animacji wykorzystują wygładzanie niezależne od framerate'u (exp smoothing / `lerp_angle`), blend trees i akcelerację, eliminując „skoki", ślizg i sztywność ruchu.
- **Responsywność.** Wejście gracza reaguje w tej samej klatce, w której się pojawia; wygładzany jest wyłącznie efekt wizualny. Mechanizmy input buffer, coyote time i jump buffer gwarantują, że żadna intencja nie ginie.
- **Skalowalność / data-driven.** Cała treść (rasy, klasy, pochodzenia, wygląd, nazwy, sterowanie, zapisy) to zasoby `.tres` i lekkie referencje po ID. Rozszerzanie gry nie wymaga modyfikacji kodu — wystarczy dodać dane.
- **Nowoczesny design.** Voxelowy styl wizualny łączymy z filmowym oświetleniem podglądu, dostępnością (WCAG AA, pełny remap, redukcja efektów) oraz parzystością wejścia mysz+klawiatura / gamepad.

---

## Spis treści

1. **Kreator postaci** — wieloetapowy przepływ tworzenia postaci (draft jako Resource, walidacja, zapis postępu, diagram stanów).
2. **Personalizacja wyglądu** — edytor wyglądu (blendshapes, decale, attach pointy), rasozależność, presety, import/export, wydajność.
3. **System ras** — sześć kanonicznych ras, lore, wygląd, zbalansowane premie rasowe, powiązanie z biomami.
4. **System klas MMORPG** — jedenaście klas, role, zasoby klasowe, staty bazowe, przykładowe skille i integracja z celowaniem.
5. **System nadawania nazw** — generator nazw per rasa, walidacja, filtr wulgaryzmów, unikalność, tytuły i przydomki.
6. **Interfejs użytkownika kreatora** — układ ekranów, scena podglądu 3D, sterowanie kamerą, animacje, audio, dostępność, węzły Godot.
7. **System sterowania postacią (TPP)** — model face-movement + combat-aim, ruch względem kamery, obrót, celownik, kamera, animacje, migracja kodu.
8. **Architektura systemu (Data-Driven)** — zasoby jako dane, kompozycja komponentów, rejestr `ContentDB`, fabryka postaci, walidacja.
9. **Persistencja danych** — zapis lokalny (JSON, atomowy zapis, backupy) i serwerowy (PostgreSQL), serializacja, wersjonowanie i migracje.

---

## Słowniczek pojęć

| Pojęcie | Znaczenie |
|---|---|
| **TPP** (Third-Person Perspective) | Widok z trzeciej osoby, kamera zza pleców postaci (zza prawego barku), ze stałym celownikiem na środku ekranu. |
| **Crosshair / celownik** | Stały element UI na środku ekranu; przez jego punkt prowadzony jest raycast z kamery wyznaczający `aim_point` (cel ataków i orientacji postaci w walce). |
| **Ruch względem kamery** | Wektor wejścia (WSAD/gałka) rzutowany na bazę kamery (yaw) na płaszczyznę poziomą — kierunek ruchu zależy od orientacji kamery, nie postaci. |
| **face-movement + combat-aim** | Docelowy model facingu: poza walką postać zwraca się w kierunku ruchu, w walce — w stronę celownika. |
| **face-movement** | Tryb eksploracji: postać biegnie zawsze przodem w stronę kierunku ruchu (także „S" = obrót i bieg przodem). |
| **combat-aim** | Tryb walki: postać orientuje się na `aim_point`, dopuszczalny strafe, pociski lecą w punkt celownika. |
| **always-face-camera (strafe)** | Stary model (obecny `Player.gd`): postać stale zwrócona zgodnie z kamerą. Sekcja 7 opisuje migrację do modelu docelowego. |
| **blend tree / blend space** | Drzewo mieszania animacji w `AnimationTree`; BlendSpace1D (prędkość) dla eksploracji, BlendSpace2D (8 kierunków) dla strafe w walce. |
| **state machine** | Maszyna stanów (ruchu/walki/animacji): jawne stany (Idle, Run, TurnInPlace, Jump…) i przejścia między nimi. |
| **root motion** | Animacja napędzająca przemieszczenie postaci (uniki, lunge ataku); przeciwieństwo „in-place", gdzie ruch liczy kod. |
| **turn-in-place** | Obrót w miejscu (bez ruchu) przy dużej różnicy kąta, z dedykowaną animacją zsynchronizowaną z obrotem. |
| **data-driven** | Treść gry zdefiniowana jako dane (zasoby), nie kod — pozwala rozbudowywać grę bez programowania. |
| **`.tres`** | Tekstowy format zasobu Godota (Resource); wersjonowalny w Git, edytowalny w inspektorze, ładowalny w runtime. |
| **autoload (singleton)** | Globalny węzeł-serwis Godota dostępny zewsząd (np. `ContentDB`, `Events`, `SaveService`, `NameService`). |
| **kompozycja komponentów** | Budowa postaci z wymiennych komponentów (`StatsComponent`, `MovementComponent`…) zamiast dziedziczenia klas. |
| **pipeline statów** | Kolejność liczenia statystyk: `base → flat → increased% → more` (najpierw baza, potem dodatki płaskie, procenty addytywne, na końcu mnożniki). |
| **zasób klasowy** | Pula mocy klasy: Furia, Mana lub Focus (oraz warianty: Energia+Combo, Esencja Nieumarłych, Wiara, Chi, Esencja Natury, Święta Moc). |
| **host-authoritative** | Model sieci, w którym host/serwer jest źródłem prawdy: klient wysyła intencje (np. `aim_point`), host waliduje i rozstrzyga wynik. |
| **`schema_version`** | Numer wersji schematu zapisu w każdym pliku/rekordzie; umożliwia deterministyczne migracje v(N) → v(N+1). |
| **migracja** | Czysta, idempotentna funkcja podnosząca stary zapis do bieżącego `schema_version` (z domyślnymi wartościami nowych pól). |
| **ID-reference** | Zapis odwołujący się do definicji przez stabilne `id` (np. `race_id`), zamiast kopiować jej wartości — odporny na rebalans. |
| **`aim_point`** | Punkt w świecie wyznaczony raycastem z kamery przez crosshair; cel pocisków i źródło `target_yaw` w walce. |
| **`wish_dir`** | Znormalizowany wektor zamierzonego kierunku ruchu w przestrzeni świata (w bazie kamery). |
| **`combat_lock_timer`** | Krótki timer (domyślnie 1.5 s) utrzymujący tryb walki po ostatniej akcji bojowej, by uniknąć migotania trybów. |
| **biom** | Region świata o spójnym klimacie: Verdant Hollow (las), Emberwaste (pustynia/ogień), Frosthelm Peaks (śnieg/góry). |


---

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


---

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


---

## 3. System ras

### 3.0. Założenia projektowe systemu ras

System ras w grze opiera się na sześciu kanonicznych ludach świata Duralanii. Każda rasa jest **rdzeniem tożsamości postaci**, ale w żadnym wypadku nie determinuje wyboru klasy — wszystkie 11 klas (Wojownik, Paladyn, Berserker, Łucznik, Łotrzyk, Zabójca, Mag, Nekromanta, Kapłan, Druid, Mnich) jest dostępnych dla każdej rasy. Rasa wpływa wyłącznie na:

1. **Wygląd bazowy** (sylwetka, proporcje, paleta, opcje kreatora).
2. **Premie rasowe** — niewielki, zbalansowany pakiet: jeden zestaw modyfikatorów statystyk + jedna pasywka utility/aktywna.
3. **Lore i przynależność biomową** (powiązanie z lokacjami startowymi i hubami).

#### Zasady balansu (anty „must-pick")

- **Budżet bonusów** — każda rasa otrzymuje dokładnie ten sam budżet punktowy premii (referencyjnie **+12 „punktów rasowych"**, gdzie 1 pkt ≈ +1% statystyki wtórnej lub jego ekwiwalent). Rozkład różni się profilem, nie sumą.
- **Modyfikatory wchodzą w warstwę `increased%`** pipeline'u statów (base → flat → increased% → more), więc skalują się addytywnie z innymi „increased" i NIE psują późnej gry (brak warstwy `more` na rasach).
- **Brak twardych bramek** — żaden bonus rasowy nie jest warunkiem działania buildu; różnice mieszczą się w paśmie ±2–4% efektywności w docelowej roli. To kwestia smaku i fantazji, nie optymalizacji.
- **Pasywki to QoL/utility lub mikro-combat**, nie liniowy DPS — np. odporności żywiołowe, redukcja kar terenowych, bonusy do zbieractwa/tropienia, krótkie cooldownowe efekty obronne.
- **Odporności żywiołowe** zsumują się z odpornościami ze sprzętu; cap odporności = **75%** (warstwa kapowania niezależna od rasy).

#### Powiązanie ras z biomami

| Rasa | Biom-ojczyzna | Hub startowy (lore) | Klimat wizualny |
|---|---|---|---|
| Duryjczycy | regiony centralne (między biomami) | Stołeczne Królestwa Duralanii | uniwersalny, „domyślny" |
| Sylvani | Verdant Hollow (las) | Gaje Świetliste | zieleń, organika, światłocień |
| Karłowie z Grimholdu | Frosthelm Peaks (śnieg/góry) | Twierdza Grimhold | kamień, stal, mróz |
| Embrani | Emberwaste (pustynia/ogień) | Spiekota / Popielne Sadyby | ogień, obsydian, żar |
| Orguni | stepy i pogranicza (mobilne klany) | Obozowiska Klanowe | skóra, kość, surowość |
| Feruni | obrzeża Verdant Hollow / dzicz | Kniejne Stanowiska | futro, pióra, naturalia |

---

### 3.1. Duryjczycy

**Typ fantasy:** realistyczny (klasyczni „ludzie").

#### Lore i historia
Duryjczycy to ludzie z centralnych królestw **Duralanii** — krainy leżącej w sercu kontynentu, na styku lasu, gór i pustkowi. Z braku skrajnego środowiska wykształcili **wszechstronność jako cnotę**: nie najsilniejsi, nie najszybsi, nie najodporniejsi, lecz zdolni do wszystkiego. Ich historia to historia dyplomacji, szlaków handlowych i armii złożonych z najemników wszystkich pozostałych ludów. To Duryjczycy spisali wspólny kalendarz, znormalizowali języki kupieckie i zbudowali większość kamiennych traktów łączących biomy. W rozgrywce pełnią rolę **rasy domyślnej / referencyjnej** — punkt odniesienia balansu.

#### Wygląd
- **Sylwetka:** przeciętna, proporcje 1:1 względem szablonu humanoida (wzrost odniesienia 1.80 m).
- **Cechy charakterystyczne:** największa różnorodność karnacji, fryzur i zarostu w kreatorze; brak cech nieludzkich.
- **Paleta:** stonowane błękity, szarości stali, ciepłe brązy heraldyki królewskiej; akcenty złota i czerwieni.

#### Cechy unikalne
- Najszerszy zestaw opcji kreatora postaci (twarze, blizny, tatuaże).
- „Neutralny" rdzeń animacji — referencja dla retargetingu pozostałych ras.

#### Premie rasowe
- **Modyfikatory statystyk (increased%):** **+4% do całego doświadczenia (XP gain)**, **+3% szybkości przywracania zasobu klasowego** (Furia/Mana/Focus), **+5% do reputacji u frakcji**.
- **Pasywka — „Adaptacja":** raz na 90 s gracz może **przełączyć aktywną premię pomocniczą** między dwoma trybami: *Wytrwałość* (+8% increased Armor na 12 s) albo *Spryt* (+8% increased ruchu poza walką na 12 s). Utility, nie liniowy DPS.

#### Przykładowe imiona
Aldric Verleyn, Mira Doryn, Castan Velith, Edda Marowin, Roald Brentar, Selka Andrune.

---

### 3.2. Sylvani

**Typ fantasy:** stylizowany (lud leśny, elf-podobni).

#### Lore i historia
Sylvani to długowieczny **leśny lud** z **Verdant Hollow** — pradawnej puszczy o świetlistych baldachimach. Mierzą czas pokoleniami drzew, nie ludzkimi latami; pamięć zbiorowa Sylvani sięga epok, w których pozostałe ludy dopiero powstawały. Wierzą w **więź z żywą siecią lasu** (korzenie, grzybnie, ścieżki zwierząt) i traktują wycinkę jak okaleczenie własnego ciała. Z Duryjczykami łączą ich ostrożne sojusze handlowe (zioła, łuki, jedwab pajęczy), z Karłami spór o kopalnie podgórskie.

#### Wygląd
- **Sylwetka:** smukła, wysoka (wzrost odniesienia 1.90 m), długie kończyny, lekki chód.
- **Cechy charakterystyczne:** spiczaste uszy, duże oczy o nienaturalnych tęczówkach (bursztyn, mech, fiolet), delikatne wzory na skórze przypominające słoje/liście (bioluminescencja w cieniu).
- **Paleta:** zielenie mchu, brązy kory, akcenty świetlistego turkusu i bieli kwiatów.

#### Cechy unikalne
- Cichszy chód (mniejszy promień „alertu" przeciwników w trawie/lesie).
- Lepsza widoczność nocą w biomie leśnym.

#### Premie rasowe
- **Modyfikatory statystyk (increased%):** **+5% increased Movement Speed**, **+4% increased Critical Chance**, **+15% odporności na efekty spowolnienia/uwięzi (CC: root/slow)**.
- **Pasywka — „Krok Boru":** w Verdant Hollow i każdym biomie leśnym koszt zasobu klasowego umiejętności ruchu/uniku **−10%**; dodatkowo bierna regeneracja HP **+2%/s** gdy postać stoi nieruchomo w trawie/krzewach (utility eksploracyjne).

#### Przykładowe imiona
Faelar Thissewyn, Lirael Mossvane, Aerith Sylwen, Naeris Dawnroot, Thalael Brightleaf, Ysolde Fernmere.

---

### 3.3. Karłowie z Grimholdu

**Typ fantasy:** realistyczno-stylizowany (krasnoludy).

#### Lore i historia
Karłowie z **Grimholdu** to lud kowali i górników z **Frosthelm Peaks** — śnieżnego, granitowego pasma na północy. Ich twierdza Grimhold to miasto wykute w żywej skale, ogrzewane podziemnymi piecami. Karłowie cenią **rzemiosło, ród i przysięgę** ponad wszystko; rejestr kowalski rodu jest dla nich ważniejszy niż akt urodzenia. Słyną z najlepszych pancerzy i broni w Duralanii — to ich runiczna stal trzyma w ryzach żar Embrani i magię Sylvani. Z Orgunami łączy ich szorstki szacunek wojowników; z Embrani — rywalizacja o złoża obsydianu.

#### Wygląd
- **Sylwetka:** niska, krępa, masywna (wzrost odniesienia 1.40 m, szeroka klatka i bary), niski środek ciężkości.
- **Cechy charakterystyczne:** bujne brody i zaploty (z koralikami/okuciami), grube dłonie, wydatne brwi; częste blizny od ognia kuźni.
- **Paleta:** szarości kamienia, rdzawe brązy żelaza, mosiądz i miedź, akcenty błękitnego mrozu i runicznego światła.

#### Cechy unikalne
- Odporność na poślizg i kary terenowe na lodzie/śniegu (brak modyfikatora trakcji w Frosthelm Peaks).
- Premia do jakości łupu rzemieślniczego (rudy, sztaby).

#### Premie rasowe
- **Modyfikatory statystyk (increased%):** **+6% increased maksymalne HP**, **+10% odporności na Mróz (Frost)**, **+8% odporności na efekty przewrócenia/odrzutu (knockback/knockdown)**.
- **Pasywka — „Stopa Górska":** **−15% kary do ruchu od podłoża** (lód, błoto, sypki piach) we wszystkich biomach; w Frosthelm Peaks dodatkowo **+10% increased Armor**. Stabilność i przetrwanie, nie DPS.

#### Przykładowe imiona
Brokk Steinarn, Dwalia Grimbrand, Thrain Holl-forge, Vrenna Kolderhelm, Bardin Ashanvil, Hilde Stoneveld.

---

### 3.4. Embrani

**Typ fantasy:** stylizowany (lud naznaczony ogniem, ember-touched).

#### Lore i historia
Embrani to lud **naznaczony ogniem** z **Emberwaste** — rozległego pustkowia popiołu, obsydianowych iglic i wiecznie tlących się rozpadlin. Legenda głosi, że ich przodkowie zawarli pakt z **żywym płomieniem ziemi** i odtąd ich krew jest gorąca dosłownie — żar płynie w ich żyłach. Embrani są **gwałtowni, dumni i bezpośredni**; honor mierzą żarem, z jakim broni się swoich. Ich osady (Popielne Sadyby) lgną do termalnych szczelin. Z Karłami spierają się o obsydian, z Duryjczykami handlują szkłem wulkanicznym i przyprawami pustyni.

#### Wygląd
- **Sylwetka:** smukło-atletyczna (wzrost odniesienia 1.85 m), wyprostowana, „rozgrzana".
- **Cechy charakterystyczne:** skóra w odcieniach rozżarzonego węgla z **świecącymi żyłami lawy** (jaśnieją w walce), oczy jak żar, włosy przypominające dym/iskry; popękana, „obsydianowa" tekstura na barkach.
- **Paleta:** czerń obsydianu, czerwień i pomarańcz żaru, popielata szarość, akcenty złotej iskry.

#### Cechy unikalne
- Wizualny feedback bojowy: żyły jaśnieją wraz z wysokością zasobu klasowego.
- Naturalna komfortowa egzystencja w upale (brak kar od gorąca w Emberwaste).

#### Premie rasowe
- **Modyfikatory statystyk (increased%):** **+10% odporności na Ogień (Fire)**, **+4% increased Critical Damage**, **−20% czasu trwania efektów Podpalenia (Burn) nałożonych na gracza**.
- **Pasywka — „Żar Krwi" (aktywna, CD 60 s):** uwolnienie żaru — nakłada na siebie buff na 8 s: **+6% increased Attack/Cast Speed** oraz aura zadająca niewielkie obrażenia od ognia stykającym się wrogom (DoT kontaktowy). Krótka, cooldownowa, nie sumuje się liniowo z DPS-em buildu.

#### Przykładowe imiona
Pyrrhus Cindrael, Ashara Vol'kemn, Ignar Dunmothe, Ember Tash'virae, Solkan Reythe, Cyra Emberlyn.

---

### 3.5. Orguni

**Typ fantasy:** stylizowany (orkowie koczowniczych klanów).

#### Lore i historia
Orguni to **orkowie** z koczowniczych klanów przemierzających stepy i pogranicza Duralanii. Nie posiadają jednej stolicy — ich domem jest **ruchomy obóz i więź klanowa**. Wbrew uprzedzeniom innych ludów, Orguni kierują się surowym **kodeksem honoru**: słowo dane przy ognisku jest wiążące jak runiczna przysięga Karłów. Ceni się siłę, ale jeszcze bardziej **wierność i odwagę w obronie słabszych z klanu**. Ich wojownicy bywają najemnikami u Duryjczyków; z Ferunami dzielą szacunek dla dzikiej natury i sztuki tropienia.

#### Wygląd
- **Sylwetka:** potężna, wysoka i barczysta (wzrost odniesienia 2.05 m), wyraźna masa mięśniowa, lekko pochylona postawa bojowa.
- **Cechy charakterystyczne:** zielonkawa/szarozielona lub piaskowa skóra, wydatne kły dolne, mocna szczęka, blizny i barwy klanowe; często rytualne tatuaże i kościane ozdoby.
- **Paleta:** zielenie i ochry skóry, brązy skóry/futra, kość, akcenty czerwieni barw wojennych.

#### Cechy unikalne
- Onieśmielająca obecność: krótszy czas „aggro pull" na siebie (utility tank/front).
- Premia do udźwigu (większy limit ekwipunku ciężkiego).

#### Premie rasowe
- **Modyfikatory statystyk (increased%):** **+5% increased Melee/Physical Damage**, **+4% increased maksymalne HP**, **+10% odporności na efekty Oszołomienia (Stun)**.
- **Pasywka — „Niezłomność" (próg HP, CD 90 s):** gdy HP spadnie pierwszy raz poniżej 30%, postać natychmiast otrzymuje **tarczę pochłaniającą obrażenia (≈ 8% max HP) na 5 s** i **+10% increased ruchu** na 3 s (okno na repozycję). Survival/clutch, nie zwiększa DPS.

#### Przykładowe imiona
Grommash Karn, Urzha Bloodmane, Kael'gor Tthrok, Mazha Skarn, Drogath Ironhowl, Nakra Stormtusk.

---

### 3.6. Feruni

**Typ fantasy:** mocno stylizowany (lud-zwierzę, beastkin — w duchu Cube World).

#### Lore i historia
Feruni to **lud-zwierzę** (beastkin) z dzikich obrzeży **Verdant Hollow** i nieoswojonych ostępów. Każdy Feruni nosi cechy zwierzęcego pratotemu (kocie, wilcze, ptasie, lisie) — to nie kostium, lecz natura. Kierują ich **instynkt, węch i pamięć łowiecka**. Nie budują wielkich miast; żyją w stanowiskach łowieckich i wędrownych watahach. Są **najlepszymi tropicielami i zwiadowcami** Duralanii — to Feruni odnajdują zaginione szlaki i czytają ślady tam, gdzie inni widzą tylko mech. Z Sylvani łączy ich miłość do lasu (choć Feruni są bardziej drapieżni); z Orgunami — kultura watahy i łowów.

#### Wygląd
- **Sylwetka:** zwinna, lekko cofnięta cyfrygrada postawa (palcochodność), ogon (balans + animacja emocji) (wzrost odniesienia 1.75 m).
- **Cechy charakterystyczne:** futro/sierść lub pióra, zwierzęce uszy i pysk, pionowe źrenice, pazury; warianty totemu (felid/lupin/avian/vulpin) dobierane w kreatorze.
- **Paleta:** naturalia — rude, kremowe, grafitowe, pręgowane wzory; akcenty turkusu/zieleni oczu.

#### Cechy unikalne
- **Tropienie:** widzi ślady i pobliskie zasoby/wrogów na minimapie (utility eksploracyjne — kluczowe dla łupu jako progresji).
- Lepsza percepcja w nocy i w gęstym terenie.

#### Premie rasowe
- **Modyfikatory statystyk (increased%):** **+5% increased Movement Speed**, **+4% increased Critical Chance**, **+8% increased szybkości skoku/dasha (rozpęd uniku)**.
- **Pasywka — „Węch Łowcy":** stały **ujawniacz tropów** (zasoby, łup rzadki i elitarni wrogowie w promieniu pokazywani na minimapie); pierwszy atak z ukrycia/po unikach zadaje **+10% increased Damage** (jednorazowo, reset po 6 s poza walką). Eksploracja + mikro-burst otwarcia, nie ciągły DPS.

#### Przykładowe imiona
Rhel Swiftpaw, Nayra Duskfur, Korrin Greymane, Sisha Emberwhisk, Talon Brindlewing, Vesh Nightprowl.

---

### 3.7. Zbiorcza tabela premii rasowych

| Rasa | Bonus statystyczny (increased% / odporności) | Pasywka aktywna / utility | Preferowane role |
|---|---|---|---|
| **Duryjczycy** | +4% XP gain, +3% regen zasobu klasowego, +5% reputacji | „Adaptacja" — przełącznik buffa (Armor / Move Speed), CD 90 s | dowolna (rasa referencyjna, jednakowo dobra wszędzie) |
| **Sylvani** | +5% Move Speed, +4% Crit Chance, +15% odpor. root/slow | „Krok Boru" — −10% kosztu ruchu w lasie, regen HP w trawie | DPS dystansowy (Łucznik, Mag), mobilny Łotrzyk, Druid |
| **Karłowie z Grimholdu** | +6% max HP, +10% odpor. Mróz, +8% odpor. knockback/down | „Stopa Górska" — −15% kar terenowych, +10% Armor w górach | Tank/front (Wojownik, Paladyn), Berserker, Mnich |
| **Embrani** | +10% odpor. Ogień, +4% Crit Damage, −20% Burn na sobie | „Żar Krwi" — buff Atk/Cast Speed + aura ognia, CD 60 s | Caster DPS (Mag, Nekromanta), Berserker, Zabójca |
| **Orguni** | +5% Melee/Phys Dmg, +4% max HP, +10% odpor. Stun | „Niezłomność" — tarcza + speed przy <30% HP, CD 90 s | Tank/melee DPS (Wojownik, Berserker, Paladyn, Mnich) |
| **Feruni** | +5% Move Speed, +4% Crit Chance, +8% szybkości dasha | „Węch Łowcy" — tropy na minimapie + +10% dmg z otwarcia | Skirmisher (Łotrzyk, Zabójca, Łucznik), eksploracja/loot |

> **Uwaga balansowa dla implementacji:** sumaryczny „budżet" wszystkich ras jest równy (≈ +12 pkt rasowych). Profile różnią się rozkładem (przetrwanie vs. mobilność vs. żywioł vs. burst-otwarcie), nie mocą. Żaden bonus nie jest warunkiem buildu — różnice mieszczą się w paśmie ±2–4% efektywności w docelowej roli. Wszystkie modyfikatory wpisują się w warstwę `increased%` pipeline'u statów; odporności żywiołowe kapowane są wspólnym capem 75% niezależnie od rasy.

#### Wskazówki data-driven (zgodne z architekturą .tres)
- Każda rasa = jeden zasób `RaceData.tres` z polami: `id`, `nazwa`, `biom_ojczyzna`, `wzrost_odniesienia`, `mod_increased: Dictionary` (stat → %), `odpornosci: Dictionary` (żywioł → %), `pasywka_id` (ref do `RacePassive.tres`), `kreator_opcje`.
- Pasywki aktywne (Embrani „Żar Krwi", Orguni „Niezłomność", Duryjczycy „Adaptacja") implementować jako komponenty `AbilityComponent` z cooldownem — spójnie z host-authoritative combat.
- Bonusy `increased%` wstrzykiwać do `StatComponent` na etapie agregacji warstwy `increased`, PRZED warstwą `more`.


---

## 4. System klas MMORPG

### 4.0. Założenia projektowe

System klas opiera się na klasycznym trójkącie ról MMO (Tank / Healer / DPS) rozszerzonym o role
hybrydowe (Support, Bruiser). Wszystkie klasy są **data-driven** — każda klasa to zasób
`ClassData.tres` (Resource) wskazujący na `ResourcePoolData.tres` (mechanika zasobu), listę
`SkillData.tres`, dozwolone typy broni i pancerza oraz krzywą bazowych statów. Skille są komponentami
(`AbilityComponent`) operującymi na `StatsComponent` z pipeline `base -> flat -> increased% -> more`.

**Integracja z modelem sterowania (sekcja 7) — obowiązuje WSZYSTKIE klasy:**
- Skille kierunkowe (pociski, dashe, stożki, wiązki) celują w **punkt celownika** = raycast z kamery
  przez środek ekranu (crosshair) na geometrię/płaszczyznę świata. To `aim_point`.
- W momencie aktywacji skilla postać **płynnie orientuje się** w stronę `aim_point` (wejście w stan
  walki), a pocisk/hitbox startuje z `muzzle`/`hand_socket` skierowany na `aim_point`.
- Skille AoE typu "ground target" (np. meteor, totem, kałuża) lądują domyślnie w `aim_point`; przy
  trybie szybkim (quick-cast) bez decala — natychmiast pod celownikiem.
- Stożki/uderzenia melee używają `aim_point` tylko do wyznaczenia yaw uderzenia; sam hitbox jest
  względem postaci. Brak twardego lock-on (zgodnie z action-combat), opcjonalny "soft target" do UI.

**Atrybuty główne (skalujące):**
- **SIŁA (STR)** — obrażenia broni ciężkiej (miecze, topory, młoty), część HP i pancerza fizycznego.
- **ZRĘCZNOŚĆ (DEX)** — obrażenia broni lekkiej/dystansowej, szansa kryt., prędkość ataku.
- **INTELEKT (INT)** — obrażenia magiczne, max zasób many/esencji, efektywność leczenia magicznego.
- **DUCH/WIARA (SPI)** — moc leczenia, regeneracja zasobu, opór magiczny.
- **WYTRZYMAŁOŚĆ (VIT)** — max HP, opory, redukcja obrażeń (kluczowa dla tanków).

**Pancerze:** Lekki (mobilność, +DEX/INT, najmniejsza redukcja), Średni (balans), Ciężki (max redukcja,
+STR/VIT, ograniczenia mobilności). Dopasowanie pancerza do klasy wpływa na bonusy biome'owe i
afiksy lootu (sekcja progresji/loot).

**Zasoby (mechaniki klasowe) — kanon:**
- **Furia** (Rage) — buduje się w walce, decay poza walką. (zgodnie z istniejącym kodem)
- **Mana** — pula regenerująca się pasywnie. (zgodnie z istniejącym kodem)
- **Focus** (Skupienie) — regeneruje pasywnie, wydatkowany na precyzyjne strzały. (zgodnie z kodem)
- **Energia/Combo** — Energia regeneruje szybko; Punkty Combo (0–5) budowane uderzeniami, wydawane na
  finishery.
- **Esencja Nieumarłych** — generowana zabójstwami/przywołaniami, zasila pety i nekromancję.
- **Wiara** (Faith/Devotion) — ładowana atakami/modlitwą, wydawana na leczenie i wyroki.
- **Chi** — energia wewnętrzna mnicha, generowana ciosami, wydawana na techniki.
- **Mana + Energia Natury (Esencja Natury)** — Druid: dwuzasobowy (forma humanoidalna = Mana,
  formy zwierzęce = Esencja Natury).
- **Mana Świętej Mocy** — Paladyn: Mana + drugorzędne ładunki "Świętej Mocy" (0–3) na wyroki.

---

### 4.1. Wojownik (Tank / Bruiser)

**Rola:** Główny Tank (główny), opcjonalnie Melee Bruiser przy buildzie dwuręcznym.
**Fabuła:** Trzon każdej armii Duralanii. Najczęściej **Duryjczycy** i **Orguni** — żołnierze ceniący
dyscyplinę, mur tarcz i kontrolę pola bitwy. Sztuka przetrwania w pierwszej linii.

**Zasób:** Furia (0–100). Generacja: zadawanie/otrzymywanie obrażeń (+5–15 za hit). Decay 5/s poza walką.

| Statystyka bazowa (lvl 1) | Wartość |
|---|---|
| HP | 220 |
| Pancerz fizyczny | 40 |
| Główny atrybut | **SIŁA** (tank: + VIT) |
| Prędkość ruchu | 5.5 m/s |

**Broń:** miecz+tarcza, topór+tarcza, broń dwuręczna (miecz/topór/młot dwuręczny).
**Pancerz:** **Ciężki** (preferowany), Średni dozwolony.

**Skille (przykłady):**

| Skill | Efekt | Koszt / generacja | CD |
|---|---|---|---|
| Natarcie (Charge) | Dash do `aim_point` (do 12 m), stun 1.0 s na końcu, +20 Furii | gen +20 Furia | 12 s |
| Uderzenie Tarczą | Stożek 3 m pod celownikiem, dmg + osłabienie obrony wroga 15% / 6 s | 25 Furia | 6 s |
| Prowokacja (Taunt) | AoE 8 m wokół, wymusza aggro 4 s, +30% generacji aggro 6 s | 20 Furia | 14 s |
| Mur Obronny | +40% redukcji obrażeń, niewrażliwość na knockback 6 s | 40 Furia | 30 s |
| Wir Ostrzy (2H) | AoE 360° wokół, dmg w 4 m, leczy 2% HP za trafionego wroga | 35 Furia | 10 s |

**Styl walki:** Stabilny front-liner. Buduje Furię obroną, konwertuje ją na kontrolę (CC), aggro i
przetrwanie. Kierunkowe gap-closery (Natarcie) celują w celownik — gracz "wskazuje" cel ataku.

---

### 4.2. Paladyn (Tank / Healer hybryda)

**Rola:** Tank-Support lub Off-Healer. Najbardziej "drużynowa" klasa obronna.
**Fabuła:** Święci wojownicy światła. Głównie **Duryjczycy** i **Karłowie z Grimholdu**, łączący wiarę
z kowalską wytrzymałością. Chronią słabszych, karzą splugawionych.

**Zasób:** Mana + **Święta Moc** (0–3 ładunki). Ładunki generowane atakami w zwarciu (1 co 2 trafienia),
wydawane na potężne wyroki/leczenie grupowe.

| Statystyka bazowa (lvl 1) | Wartość |
|---|---|
| HP | 200 |
| Mana | 120 |
| Główny atrybut | **SIŁA** (off-heal: + DUCH) |
| Pancerz fizyczny | 38 |

**Broń:** młot jednoręczny+tarcza, miecz+tarcza, młot dwuręczny (build retri).
**Pancerz:** **Ciężki**.

**Skille (przykłady):**

| Skill | Efekt | Koszt | CD |
|---|---|---|---|
| Święty Młot | Rzut młotem w `aim_point`, dmg święte + leczy najbliższego sojusznika za 50% dmg | 30 Mana | 5 s |
| Tarcza Światła | Bariera na cel pod celownikiem (sojusznik), absorpcja 25% max HP / 8 s | 1 Święta Moc | 12 s |
| Aura Ochrony | AoE 10 m wokół, -15% obrażeń dla drużyny 8 s | 40 Mana | 20 s |
| Wyrok (Judgement) | Linia do celownika, dmg + leczenie grupy za część dmg | 3 Święta Moc | 18 s |
| Ręka Wybawienia | Natychmiast leczy sojusznika pod celownikiem za 18% max HP, usuwa 1 debuff | 50 Mana | 15 s |

**Styl walki:** Trwały front-liner z leczeniem reaktywnym. Może solo-tankować lub wspierać główny heal.
Skille leczące celują na sojusznika pod celownikiem (UI podświetla soft-target).

---

### 4.3. Berserker (Melee DPS / Bruiser)

**Rola:** Melee DPS o najwyższym burst, kosztem przeżywalności.
**Fabuła:** **Orguni** i **Embrani** w transie bojowym. Im bliżej śmierci, tym groźniejsi. Gardzą
tarczami — atak to obrona.

**Zasób:** Furia (0–100). Generacja agresywna (+10–20 za hit). Powyżej 50 Furii: +obrażenia; tryb
"Krwawego Szału" konsumuje Furię szybko.

| Statystyka bazowa (lvl 1) | Wartość |
|---|---|
| HP | 180 |
| Główny atrybut | **SIŁA** |
| Pancerz | 22 |
| Prędkość ataku | wysoka |

**Broń:** dwa topory jednoręczne (dual-wield), topór/miecz dwuręczny.
**Pancerz:** **Średni** (preferowany), Lekki dozwolony.

**Skille (przykłady):**

| Skill | Efekt | Koszt / gen | CD |
|---|---|---|---|
| Skok Krwi | Skok do `aim_point`, AoE uderzenie w lądowaniu (4 m), +25 Furia | gen +25 | 8 s |
| Furia Ostrzy | Seria 5 ciosów w kierunku celownika, każdy +dmg za % brakującego HP | 30 Furia | 6 s |
| Krwawy Szał | +30% dmg, +20% lifesteal, -15% redukcji obrażeń, 8 s | 50 Furia | 25 s |
| Bezgłowy Atak | Dash przez wrogów (linia do celownika), dmg + krwawienie 4 s | 25 Furia | 10 s |
| Ostatni Oddech | Przy HP <30%: natychm. leczy 20% i +50% dmg 5 s | 70 Furia | 60 s |

**Styl walki:** "Glass cannon" w zwarciu. Wysoki risk/reward, lifesteal zamiast pancerza. Wszystkie
gap-closery i serie celują w celownik dla precyzyjnego nurkowania na cele tylnej linii.

---

### 4.4. Łucznik (Ranged DPS)

**Rola:** Fizyczny Ranged DPS, sustained + burst na dystans.
**Fabuła:** Mistrzowie łuku. Głównie **Sylvani** i **Feruni** — leśni strzelcy o nadludzkiej precyzji
i instynkcie tropienia.

**Zasób:** Focus (0–100, regeneracja 8/s pasywnie). Precyzyjne strzały kosztują Focus; szybkie strzały
go budują.

| Statystyka bazowa (lvl 1) | Wartość |
|---|---|
| HP | 150 |
| Główny atrybut | **ZRĘCZNOŚĆ** |
| Szansa kryt. | bazowo 8% |
| Zasięg | 35 m |

**Broń:** łuk długi, łuk krótki (szybszy, bliżej), kusza (wolniejsza, mocniejsza).
**Pancerz:** **Lekki** (preferowany), Średni dozwolony.

**Skille (przykłady):**

| Skill | Efekt | Koszt | CD |
|---|---|---|---|
| Celny Strzał | Pojedynczy pocisk w `aim_point`, +50% kryt jeśli cel >20 m | 25 Focus | 4 s |
| Deszcz Strzał | Ground-target AoE w `aim_point` (5 m), dmg/s przez 4 s | 40 Focus | 14 s |
| Strzał Przebijający | Pocisk po linii do celownika, przebija wszystkich wrogów | 30 Focus | 8 s |
| Salto w Tył | Dash 6 m od celu (od kierunku celownika), +30% prędkości ataku 4 s | 15 Focus | 10 s |
| Sokole Oko | +25% kryt i +zasięg, strzały nie tracą dmg z dystansem 8 s | 50 Focus | 30 s |

**Styl walki:** Kiting i pozycjonowanie. Każdy strzał to fizyczny pocisk podążający do `aim_point` —
gracz prowadzi cele ręcznie (action-aim). Salto utrzymuje dystans.

---

### 4.5. Łotrzyk (Melee DPS / Support)

**Rola:** Melee DPS z elementami Supportu (CC, sustained DPS combo).
**Fabuła:** Złodzieje, najemnicy, awanturnicy. Głównie **Duryjczycy** i **Feruni** — szybcy, sprytni,
walczący brudno. Specjaliści od zatruć i mobilności.

**Zasób:** Energia (0–100, regen szybki 15/s) + **Punkty Combo** (0–5). Buildery wydają Energię i dają
Combo; finishery konsumują Combo.

| Statystyka bazowa (lvl 1) | Wartość |
|---|---|
| HP | 155 |
| Główny atrybut | **ZRĘCZNOŚĆ** |
| Prędkość ataku | bardzo wysoka |
| Pancerz | 18 |

**Broń:** dwa sztylety (dual-wield), miecz jednoręczny + sztylet.
**Pancerz:** **Lekki**.

**Skille (przykłady):**

| Skill | Efekt | Koszt | CD |
|---|---|---|---|
| Pchnięcie (builder) | Cios w kierunku celownika, +1 Combo | 30 Energia | — |
| Rozpłatanie (finisher) | Konsumuje Combo: dmg skaluje z liczbą punktów | 35 Energia | — |
| Cios w Plecy | Dash za cel pod celownikiem, +100% dmg jeśli z tyłu, +2 Combo | 40 Energia | 12 s |
| Zatrute Ostrza | Następne ataki nakładają stos trucizny (dmg/s) 10 s | 0 (toggle) | 18 s |
| Bomba Dymna | AoE pod celownikiem, oślepienie wrogów 3 s + niewidzialność 2 s | 50 Energia | 25 s |

**Styl walki:** Combo-driven, pozycjonowanie za plecami celu. Mobilny, oparty na rotacji
builder/finisher. CC (bomba, oślepienie) daje wartość supportową dla drużyny.

---

### 4.6. Zabójca (Melee DPS, burst)

**Rola:** Melee Burst DPS — najwyższy single-target burst, niska przeżywalność.
**Fabuła:** Cienie i skrytobójcy. Głównie **Feruni** i **Sylvani** — łowcy uderzający z ukrycia,
jeden cel, jedno trafienie.

**Zasób:** Energia (0–100) + **Punkty Combo** (0–5), wariant agresywny (mniej Energii, mocniejsze
finishery). Pierwszy atak z niewidzialności = gwarantowany kryt.

| Statystyka bazowa (lvl 1) | Wartość |
|---|---|
| HP | 145 |
| Główny atrybut | **ZRĘCZNOŚĆ** |
| Szansa kryt. | bazowo 12% |
| Pancerz | 16 |

**Broń:** sztylet + sztylet, miecz jednoręczny (build "shadow blade").
**Pancerz:** **Lekki**.

**Skille (przykłady):**

| Skill | Efekt | Koszt | CD |
|---|---|---|---|
| Mroczne Skradanie | Niewidzialność 6 s, +50% prędkości; przerywana atakiem | 0 | 20 s |
| Cios Egzekucji | Dmg + 200% jeśli cel <25% HP (cel pod celownikiem), +3 Combo | 35 Energia | 8 s |
| Mroczny Skok | Teleport do `aim_point` (do 15 m), następny atak gwarant. kryt | 30 Energia | 14 s |
| Sztych w Cień (finisher) | Konsumuje Combo: ogromny single-target burst | 40 Energia | — |
| Znak Śmierci | Naznacza cel pod celownikiem: +20% dmg na nim dla całej drużyny 12 s | 25 Energia | 30 s |

**Styl walki:** Otwarcie z niewidzialności, burst-rotacja, reset i wyjście. Teleport celuje w celownik
— precyzyjny "pick" na priorytetowy cel. Support poprzez Znak Śmierci.

---

### 4.7. Mag (Ranged DPS, AoE/Burst)

**Rola:** Magiczny Ranged DPS — wysoki AoE i burst żywiołów.
**Fabuła:** Uczeni żywiołów. Głównie **Duryjczycy** (akademie Duralanii) i **Embrani** (wrodzona magia
ognia). Władają ogniem, mrozem i błyskawicą — spójnie z biomami (Ember/Frost/Verdant).

**Zasób:** Mana (0–200, regen 6/s). Najwyższa pula many w grze; zarządzanie zasobem = rdzeń rozgrywki.

| Statystyka bazowa (lvl 1) | Wartość |
|---|---|
| HP | 135 |
| Mana | 200 |
| Główny atrybut | **INTELEKT** |
| Zasięg | 35 m |

**Broń:** kostur (staff), różdżka + tom/orb (focus).
**Pancerz:** **Lekki**.

**Skille (przykłady):**

| Skill | Efekt | Koszt | CD |
|---|---|---|---|
| Pocisk Ognia | Pocisk do `aim_point`, dmg ogień + podpalenie 3 s | 20 Mana | — |
| Meteor | Ground-target w `aim_point` (6 m), duży AoE dmg po 1.2 s opóźnienia | 60 Mana | 12 s |
| Nova Mrozu | AoE 8 m wokół maga, dmg + spowolnienie 50% / 4 s | 45 Mana | 14 s |
| Łańcuch Błyskawic | Linia do celownika, odbija się do 4 wrogów (−20% dmg/skok) | 40 Mana | 8 s |
| Bariera Arkany | Absorpcja 30% max HP, 6 s; blink 8 m w kierunku celownika | 50 Mana | 20 s |

**Styl walki:** Burst i kontrola tłumu na dystans. Ground-targety lądują w celowniku; pociski podążają
do `aim_point`. Wymaga pozycjonowania (krucha, ale potężna).

---

### 4.8. Nekromanta (Ranged DPS / Support, pet-master)

**Rola:** Magiczny Ranged DPS z petami i debuffami (Support przez osłabienia i sustained dmg).
**Fabuła:** Władcy śmierci. Głównie **Embrani** odszczepieńcy i **Duryjczycy** wyklęci z akademii.
Czerpią moc z nieumarłych i zarazy.

**Zasób:** **Esencja Nieumarłych** (0–100). Generowana zabójstwami i trafieniami zarazą; zasila
przywołania i potężne nekro-zaklęcia. Pasywnie regeneruje się wolno (3/s).

| Statystyka bazowa (lvl 1) | Wartość |
|---|---|
| HP | 140 |
| Główny atrybut | **INTELEKT** |
| Max pety | 3 (skalowane buildem) |
| Zasięg | 30 m |

**Broń:** kostur, kosa (scythe — melee/magiczna hybryda), tom + różdżka.
**Pancerz:** **Lekki**, Średni dozwolony (build "Death Knight" melee).

**Skille (przykłady):**

| Skill | Efekt | Koszt | CD |
|---|---|---|---|
| Pocisk Zarazy | Pocisk do `aim_point`, dmg + stos zarazy (dmg/s) | 0 (gen Esencji) | — |
| Wskrzeszenie | Przywołuje szkieleta-wojownika; atakuje cel pod celownikiem | 30 Esencji | 6 s |
| Eksplozja Truchła | Detonuje pet/zwłoki pod celownikiem, AoE 5 m dmg | 20 Esencji | 8 s |
| Klątwa Słabości | Cel pod celownikiem: +25% otrzymywanych obrażeń 10 s | 25 Esencji | 18 s |
| Żniwa Dusz | AoE 10 m wokół, dmg + leczenie nekromanty za 30% dmg, +Esencja | 50 Esencji | 22 s |

**Styl walki:** Zarządzanie petami + DoT (damage over time) + debuffy. Pety kierowane na cel pod
celownikiem. Rola supportowa: Klątwa Słabości to drużynowy debuff dmg.

---

### 4.9. Kapłan (Healer, główny)

**Rola:** Główny Healer (dedykowany). Filar przetrwania drużyny.
**Fabuła:** Słudzy bóstw światła i życia. Głównie **Duryjczycy** i **Sylvani**. Kanalizują wiarę w
leczenie i święte wyroki.

**Zasób:** **Wiara** (0–100) + Mana (0–150). Mana zasila leczenie; Wiara (generowana leczeniem/atakiem)
zasila potężne leczenie grupowe i wskrzeszenie.

| Statystyka bazowa (lvl 1) | Wartość |
|---|---|
| HP | 140 |
| Mana | 150 |
| Główny atrybut | **DUCH** (moc leczenia) |
| Regen Many | 7/s |

**Broń:** kostur, buława + tom/symbol święty (focus).
**Pancerz:** **Lekki**, Średni dozwolony.

**Skille (przykłady):**

| Skill | Efekt | Koszt | CD |
|---|---|---|---|
| Modlitwa Leczenia | Leczy sojusznika pod celownikiem 25% max HP, +5 Wiary | 30 Mana | — |
| Krąg Życia | Ground-target AoE w `aim_point` (6 m), leczenie/s 6 s | 50 Mana | 12 s |
| Tarcza Wiary | Bariera na sojuszniku pod celownikiem, 20% max HP / 8 s | 20 Wiary | 8 s |
| Święty Płomień | Pocisk dmg do `aim_point`; trafienie generuje +10 Wiary | 25 Mana | 5 s |
| Boska Interwencja | Leczenie grupowe AoE 15 m: 30% max HP + usuwa debuffy | 100 Wiary | 45 s |

**Styl walki:** Reaktywne i prewencyjne leczenie. Single-target leczy cel pod celownikiem (soft-target
UI); AoE lecznicze to ground-targety w celowniku. Atakami buduje Wiarę na "cooldownach" leczenia.

---

### 4.10. Druid (Healer / Support / hybryda)

**Rola:** Hybrydowy Healer/Support (HoT, formy zwierzęce dające melee DPS lub tankowanie sytuacyjne).
**Fabuła:** Strażnicy natury z **Verdant Hollow**. Głównie **Sylvani** i **Feruni**. Zmiennokształtni,
łączą leczenie z dziką mocą biomu.

**Zasób (dwuzasobowy):** **Mana** (forma humanoidalna — leczenie/zaklęcia) + **Esencja Natury**
(formy zwierzęce — melee/tank). Przełączanie formy zmienia aktywny zasób i pasek skilli.

| Statystyka bazowa (lvl 1) | Wartość |
|---|---|
| HP | 160 |
| Mana | 140 |
| Główny atrybut | **DUCH** (heal) / **ZRĘCZNOŚĆ** (formy) |
| Regen Many | 6/s |

**Broń:** kostur, sztylet + idol (focus natury).
**Pancerz:** **Średni** (preferowany — balans formy zwierzęcej i casterskiej).

**Skille (przykłady):**

| Skill | Efekt | Koszt | CD |
|---|---|---|---|
| Odnowa (HoT) | Leczenie/s na sojuszniku pod celownikiem 8 s | 25 Mana | — |
| Dzikie Korzenie | Ground-target w `aim_point`: unieruchamia wrogów 2 s + dmg | 35 Mana | 14 s |
| Forma Niedźwiedzia | Przełącz formę: +max HP, +pancerz, melee combat (Esencja Natury) | 0 | 1.5 s |
| Forma Pantery | Przełącz formę: +prędkość, melee DPS, dashe do celownika | 0 | 1.5 s |
| Rozkwit (Bloom) | AoE 8 m w `aim_point`: leczenie burst + usuwa 1 debuff | 60 Mana | 20 s |

**Styl walki:** Elastyczny — HoT-heal w formie humanoidalnej, awaryjne tankowanie (Niedźwiedź) lub melee
DPS (Pantera). Formy zwierzęce używają celownika do dashy i ataków melee jak inne klasy melee.

---

### 4.11. Mnich (Support / Melee DPS / Off-Tank)

**Rola:** Support melee z elementami Off-Heal i Off-Tank — utrzymuje drużynę przez bufy i sustain.
**Fabuła:** Wojownicy ducha i ciała. Głównie **Orguni** (klasztory bojowe) i **Karłowie z Grimholdu**.
Walczą wręcz, czerpiąc moc z wewnętrznej energii Chi.

**Zasób:** **Chi** (0–6 punktów). Generowane ciosami wręcz (1 Chi co ~2 trafienia), wydawane na techniki
lecznicze, bufy i finishery. Pasywnie nie regeneruje (tylko walką).

| Statystyka bazowa (lvl 1) | Wartość |
|---|---|
| HP | 175 |
| Główny atrybut | **ZRĘCZNOŚĆ** (+ DUCH dla off-heal) |
| Prędkość ataku | wysoka |
| Pancerz | 26 |

**Broń:** pięści/rękawice bojowe (fist weapons), bo (kij bojowy), nunczako.
**Pancerz:** **Średni**.

**Skille (przykłady):**

| Skill | Efekt | Koszt / gen | CD |
|---|---|---|---|
| Seria Pięści | Szybkie ciosy w kierunku celownika, gen +1 Chi co 2 trafienia | gen Chi | — |
| Dłoń Uzdrowienia | Leczy sojusznika pod celownikiem 15% max HP | 2 Chi | — |
| Wir Kopnięć | AoE 4 m wokół + odepchnięcie wrogów; mobilny | 1 Chi | 8 s |
| Aura Spokoju | Drużyna 10 m: +10% leczenia otrzymywanego i regen Chi 8 s | 3 Chi | 20 s |
| Kaskada Żywiołów | Linia do celownika: dmg + leczy najsłabszego sojusznika za część dmg | 4 Chi | 14 s |

**Styl walki:** Melee w ciągłym ruchu — bufuje i leczy drużynę nie wychodząc z walki. Off-tank przez
mobilność i sustain. Wszystkie techniki kierunkowe celują w celownik.

---

### 4.12. Zbiorcza tabela klas

| Klasa | Rola | Zasób | Broń | Pancerz | Główny atrybut |
|---|---|---|---|---|---|
| Wojownik | Tank / Bruiser | Furia | broń 1H+tarcza, 2H | Ciężki | SIŁA (+VIT) |
| Paladyn | Tank / Healer (hyb.) | Mana + Święta Moc | buława/miecz+tarcza, 2H | Ciężki | SIŁA (+DUCH) |
| Berserker | Melee DPS / Bruiser | Furia | dual topory, 2H | Średni | SIŁA |
| Łucznik | Ranged DPS | Focus | łuk długi/krótki, kusza | Lekki | ZRĘCZNOŚĆ |
| Łotrzyk | Melee DPS / Support | Energia + Combo | dual sztylety, miecz+sztylet | Lekki | ZRĘCZNOŚĆ |
| Zabójca | Melee DPS (burst) | Energia + Combo | dual sztylety, miecz 1H | Lekki | ZRĘCZNOŚĆ |
| Mag | Ranged DPS (AoE/burst) | Mana | kostur, różdżka+orb | Lekki | INTELEKT |
| Nekromanta | Ranged DPS / Support | Esencja Nieumarłych | kostur, kosa, tom | Lekki (Śr.) | INTELEKT |
| Kapłan | Healer (główny) | Wiara + Mana | kostur, buława+symbol | Lekki (Śr.) | DUCH |
| Druid | Healer / Support (hyb.) | Mana + Esencja Natury | kostur, sztylet+idol | Średni | DUCH/ZRĘCZNOŚĆ |
| Mnich | Support / Melee DPS / Off-Tank | Chi | pięści, bo, nunczako | Średni | ZRĘCZNOŚĆ (+DUCH) |

### 4.13. Balans ról (podsumowanie)

- **Tanki:** Wojownik (główny), Paladyn (tank-heal), + sytuacyjnie Druid (Niedźwiedź), Mnich (off-tank).
- **Healerzy:** Kapłan (główny), Druid (HoT/hybryda), Paladyn (off-heal), Mnich (off-heal).
- **Melee DPS:** Berserker, Łotrzyk, Zabójca, + Druid (Pantera), Mnich.
- **Ranged DPS:** Łucznik (fizyczny), Mag (magiczny AoE/burst), Nekromanta (magiczny/pety).
- **Support:** Łotrzyk (CC), Zabójca (Znak Śmierci), Nekromanta (debuffy), Mnich (bufy/aury), Paladyn (aury).

Każda kompozycja 4-osobowa do co-op może spełnić "świętą trójcę" (1 tank + 1 heal + 2 DPS) lub iść w
warianty bruiser/support — system jest elastyczny dzięki klasom hybrydowym (Paladyn, Druid, Mnich).

### 4.14. Uwagi implementacyjne (data-driven + celownik)

- Każdy `SkillData.tres` ma pole `aim_mode`: `PROJECTILE_TO_AIM`, `GROUND_AT_AIM`, `LINE_TO_AIM`,
  `CONE_AT_FACING`, `AROUND_SELF`, `ALLY_AT_AIM`, `SELF`. Determinuje użycie `aim_point` z sekcji 7.
- `ALLY_AT_AIM` korzysta z raycastu celownika z filtrem warstwy "sojusznik"; przy braku trafienia bierze
  soft-target z UI lub samego rzucającego (fallback).
- Aktywacja skilla kierunkowego ustawia flagę walki -> facing płynnie orientuje postać na `aim_point`
  (sekcja 7), pocisk/hitbox startuje z `muzzle` w stronę `aim_point`.
- Zasoby = osobne `ResourcePoolData.tres` z parametrami: `max`, `regen_per_sec`, `decay_per_sec`,
  `gen_on_hit`, `gen_on_kill`, `secondary_charges` (dla Święta Moc / Combo / Chi). Host-authoritative:
  generacja i wydatek liczone na hoście, klient predykcyjnie wyświetla.


---

## 5. System nadawania nazw

System nazw obejmuje pełen cykl życia nazwy postaci: od ręcznego wpisania lub wygenerowania, przez walidację (długość, znaki, wulgaryzmy), po rezerwację i potwierdzenie unikalności na serwerze. Jest w pełni data-driven — wszystkie zestawy sylab, prefiksów, sufiksów i wzorce fonetyczne żyją w zasobach `.tres`/JSON, ładowanych przez autoload `NameService`. Dzięki temu dodanie nowej rasy lub korekta klimatu nazw nie wymaga zmian w kodzie.

### 5.1. Cele i zasady projektowe

- **Spójność z lore.** Nazwy generowane dla każdej z 6 ras (Duryjczycy, Sylvani, Karłowie z Grimholdu, Embrani, Orguni, Feruni) muszą fonetycznie pasować do opisu rasy z sekcji 3.
- **Data-driven.** Generator nie zawiera żadnych nazw na sztywno — czyta `NameData` (Resource) per rasa.
- **Bezpieczeństwo i kultura.** Filtrowanie wulgaryzmów odporne na leetspeak, diakrytyki i podstawienia.
- **Jednoznaczność.** Każda nazwa konta-postaci unikalna globalnie (case-insensitive, po normalizacji), z mechanizmem rezerwacji i polityką kolizji.
- **Niska bariera wejścia.** Przycisk „Losuj” daje natychmiast poprawną, klimatyczną nazwę; nazwisko i przydomek są opcjonalne.

### 5.2. Struktura nazwy postaci

Pełna prezentowana nazwa składa się z maksymalnie czterech segmentów:

```
[Tytuł]  Imię  [Nazwisko]  [«Przydomek»]
```

| Segment | Wymagane | Źródło | Przykład |
|---|---|---|---|
| Tytuł (prefiks) | nie | zdobywany w grze, wybierany ze zdobytych | „Pogromca Smoków” |
| Imię | TAK | wpis ręczny lub generator | „Theron” |
| Nazwisko | nie (zależne od rasy) | wpis ręczny lub generator | „Valdoryn” |
| Przydomek (suffiks) | nie | zdobywany, wybierany | „«Niezłomny»” |

Tylko **Imię** jest obowiązkowe i podlega kontroli unikalności. Nazwisko jest opcjonalne i nie musi być unikalne. Tytuły i przydomki są kosmetyczne, przypisane do konta postaci, nie wpływają na unikalność.

#### Reguły długości i znaków (Imię)

| Reguła | Wartość |
|---|---|
| Min. długość | 2 znaki |
| Maks. długość | 16 znaków |
| Dozwolone znaki | litery Unicode (kategoria L), w tym polskie i typowe diakrytyki fantasy (à, ö, é, ’) |
| Apostrof / myślnik | dozwolone wewnątrz (np. „Kel’Thar”, „Ar-Vael”), maks. 1, nie na początku/końcu, nie podwójnie |
| Cyfry, spacje, symbole | zabronione |
| Wielkość liter | pierwsza litera wielka wymuszana; reszta wg wpisu (dla „Kel’Thar”) |
| Powtórzenia | maks. 3 te same znaki z rzędu (blokuje „Aaaaaa”) |

Nazwisko: te same reguły, długość 2–20, opcjonalne. Suma „Imię + spacja + Nazwisko” nie przekracza 32 znaków wyświetlanych.

### 5.3. Algorytm generatora nazw (per rasa)

Generator buduje imię z **wzorca fonetycznego** (pattern), wypełnianego elementami z puli danej rasy.

#### Elementy budulcowe

- **prefix** — początkowy człon (otwiera słowo, często z dużej litery).
- **mid** — środkowe sylaby (rdzeń, łączone 0–N razy).
- **suffix** — końcowy człon (zamyka słowo, niesie klimat rasy).
- **vowel / consonant** — pojedyncze fonemy do wzorców sylabicznych.
- **connector** — opcjonalny łącznik (’, -) dla ras, które tego używają (Sylvani, Orguni).

#### Symbole wzorca (pattern grammar)

| Symbol | Znaczenie |
|---|---|
| `P` | losowy prefix |
| `M` | losowy mid (środek) |
| `S` | losowy suffix |
| `C` | pojedyncza spółgłoska |
| `V` | pojedyncza samogłoska |
| `-` / `'` | dosłowny connector (tylko jeśli rasa go ma) |
| `[X]` | element opcjonalny (50% szansy, konfigurowalne) |
| `M{1,2}` | powtórzenie elementu 1–2 razy |

Przykładowe wzorce: `P + M{0,1} + S` (typowe), `CV + CV + S` (sylabiczne), `P + ' + S` (z connectorem dla Sylvani).

#### Procedura generowania (pseudokod)

```
func generate_name(race_id, gender) -> String:
    data = NameData[race_id]
    pattern = weighted_pick(data.patterns[gender])      # wzorzec wg wagi
    parts = []
    for token in tokenize(pattern):
        match token:
            "P": parts.append(pick(data.prefix[gender]))
            "M": parts.append(pick(data.mid))
            "S": parts.append(pick(data.suffix[gender]))
            "V": parts.append(pick(data.vowels))
            "C": parts.append(pick(data.consonants))
            connector: parts.append(token)              # ' lub -
    name = join(parts)
    name = apply_phonotactics(name, data.rules)         # patrz niżej
    name = capitalize_first(name)
    if not passes_length(name) or not passes_filter(name):
        return generate_name(race_id, gender)           # retry, limit 8 prób
    return name
```

#### Reguły fonotaktyczne (`apply_phonotactics`)

Wygładzają mechaniczne łączenia, by wynik brzmiał naturalnie dla rasy:

1. **Kolizja samogłosek** — przy „aa/ee/ii” na styku członów (np. „Thera” + „athon”) usuń jedną samogłoskę lub wstaw spółgłoskę łączącą z `data.glide` (np. „th”, „v”).
2. **Kolizja spółgłosek** — przy ≥3 spółgłoskach z rzędu wstaw `data.epenthesis` samogłoskę (np. „Grmd” → „Gromad”).
3. **Limit długości** — jeśli > maks., utnij środkowe `M` i regeneruj suffix.
4. **Connector** — Sylvani/Orguni mogą wstawić `'`/`-` tylko między `P` a `S`, nigdy podwójnie.
5. **Płeć** — `prefix`/`suffix` mają pulę per płeć; pula `neutral` używana, gdy gracz wybierze opcję neutralną.

#### Płeć (gender)

Trzy wartości: `male`, `female`, `neutral`. Generator dobiera odpowiednią pulę prefix/suffix i odpowiedni zestaw wzorców. Pula `neutral` zawiera człony brzmiące androginicznie; jeśli rasa ma głównie końcówki nacechowane płcią, `neutral` losuje z unii męskich i żeńskich z usunięciem skrajnie nacechowanych końcówek (flaga `gendered: true`).

### 5.4. Klimat fonetyczny per rasa

| Rasa | Charakter brzmienia | Typowe fonemy / końcówki | Connector | Nazwiska |
|---|---|---|---|---|
| Duryjczycy | klasyczny, uniwersalny, „ludzki” fantasy | -on, -an, -ric, -wyn; r, l, th | brak | rodowe, na -ford/-wick/-mont |
| Sylvani | miękki, płynny, leśny, długie samogłoski | -iel, -wen, -ara, -lael; l, n, ae, ’ | apostrof | przydomki natury (Liściocień) |
| Karłowie z Grimholdu | twardy, gardłowy, kuty | -grim, -dur, -bryn, -gar; k, g, r, dr, br | brak | rodowe runiczne, na -stein/-forge |
| Embrani | ostry, ognisty, syczący | -ash, -vyr, -zar, -ka; sz, z, k, x | brak | epitet ognia (Płomienny) |
| Orguni | mocny, dudniący, klanowy | -gor, -ук, -mash, -rok; gr, gh, ’ | apostrof/myślnik | klanowe (z Klanu …) |
| Feruni | szybki, urywany, zwierzęcy | -faa, -ix, -arr, -shi; sh, f, podwojone „rr” | brak | totemiczne (Cichołapy) |

### 5.5. Struktura danych generatora (JSON / Resource)

Każda rasa to jeden zasób `NameData` zapisany jako `.tres`, z lustrzanym formatem JSON dla edycji zewnętrznej. Schemat:

```json
{
  "race_id": "sylvani",
  "display_name": "Sylvani",
  "has_surname": true,
  "connector": "'",
  "glide": ["l", "n", "th"],
  "epenthesis": ["a", "e", "i"],
  "vowels": ["a", "e", "i", "ae", "ia"],
  "consonants": ["l", "n", "r", "th", "v", "s"],
  "patterns": {
    "male":    [{"p": "P + M[0,1] + S", "w": 5}, {"p": "P + ' + S", "w": 2}, {"p": "CV + CV + S", "w": 1}],
    "female":  [{"p": "P + M[0,1] + S", "w": 5}, {"p": "P + ' + S", "w": 2}],
    "neutral": [{"p": "P + S", "w": 4}, {"p": "CV + CV + S", "w": 1}]
  },
  "prefix": {
    "male":    ["Aer", "Thal", "Cael", "Fael", "Ela"],
    "female":  ["Lae", "Syl", "Mira", "Aria", "Nim"],
    "neutral": ["Vael", "Liri", "Aen"]
  },
  "mid": ["lan", "dor", "with", "ria", "los"],
  "suffix": {
    "male":    ["dir", "ion", "thas", "riel", "los"],
    "female":  ["wen", "iel", "ara", "ana", "lael"],
    "neutral": ["ael", "ir", "en"]
  },
  "surname": {
    "prefix": ["Liścio", "Sreb", "Świtu", "Cicho"],
    "suffix": ["cień", "rolist", "blask", "drzew"],
    "patterns": [{"p": "P + S", "w": 1}]
  }
}
```

Walidacja schematu przy starcie (`NameService._validate_data`): każda pula niepusta, sumy wag > 0, `connector` ∈ {„”, „'”, „-”}, znaki w pulach przechodzą blocklist (żeby dane bazowe nie generowały wulgaryzmów).

### 5.6. Generator nazwisk

Nazwiska są opcjonalne i sterowane flagą `has_surname` per rasa:

- **Duryjczycy, Karłowie, Sylvani** — `has_surname: true`, nazwiska rodowe.
- **Orguni** — zamiast nazwiska przynależność klanowa: „z Klanu <X>” (osobna pula `clan`).
- **Embrani, Feruni** — `has_surname: false`; ich „nazwisko” to przydomek/epitet (sekcja 5.9), nie rodowe.

Generator nazwiska używa osobnego bloku `surname` (prefix + suffix lub złożenie tematyczne). Nazwiska NIE podlegają kontroli unikalności (wiele postaci może dzielić ród).

### 5.7. Filtrowanie wulgaryzmów

Wielowarstwowy filtr uruchamiany przy walidacji każdej nazwy (ręcznej i wygenerowanej):

#### Warstwy

1. **Normalizacja wejścia** (przed porównaniem):
   - lower-case (Unicode case-fold);
   - usunięcie diakrytyków (NFKD + strip combining marks): „ą”→„a”, „ö”→„o”, „ł”→„l”;
   - de-leet: `0→o, 1→i/l, 3→e, 4→a, 5→s, 7→t, 8→b, @→a, $→s, !→i, ()→o`;
   - usunięcie powtórzeń ≥3 („fuuuck” → „fuck”) i znaków łączących/spacji wewnętrznych.
2. **Blocklist** — lista wulgaryzmów PL + EN + warianty (zewnętrzny plik `blocklist.txt`, ładowany do `HashSet`), porównanie po normalizacji:
   - **exact** — cała nazwa równa wpisowi z listy → blok;
   - **substring** — wpis z listy zawarty w nazwie → blok (z whitelistą wyjątków, np. „assassin” zawiera „ass” → dozwolone przez allowlist).
3. **Reguły wzorcowe (regex)** — np. blok ciągów wyłącznie ze znaków specjalnych, prób imitacji nazw systemowych („admin”, „gm”, „moderator”, „[GM]”).
4. **Allowlist** — fonetycznie niewinne kolizje (np. „Shitake”, „Cumberland”) zwolnione, by ograniczyć false-positives.

#### Konfiguracja

```json
{ "severity": "block",            // block | flag-for-review
  "match_modes": ["exact", "substring"],
  "leet_map": { "0":"o", "1":"i", "3":"e", "4":"a", "5":"s", "7":"t", "@":"a", "$":"s" },
  "allowlist": ["assassin", "shitake", "scunthorpe"] }
```

Wynik filtra: `OK` / `BLOCKED(reason)`. Dla nazw generowanych — przy `BLOCKED` automatyczny retry. Dla nazw ręcznych — komunikat „Ta nazwa jest niedozwolona”, bez ujawniania, które słowo trafiło (by nie pomagać w omijaniu).

### 5.8. Sprawdzanie unikalności (lokalnie + serwer)

#### Klucz unikalności

Unikalność liczona od **klucza znormalizowanego** `unique_key = casefold(strip_diacritics(remove_connectors(name)))`. Dzięki temu „Théron”, „Theron”, „Th’eron” kolidują. Wyświetlana jest oryginalna pisownia, kolizje liczone po kluczu.

#### Przepływ

1. **Walidacja lokalna (klient).** Długość, znaki, filtr wulgaryzmów — natychmiastowy feedback bez round-tripu do serwera.
2. **Zapytanie dostępności.** Klient wysyła `check_name(unique_key)`; serwer odpowiada `available | taken | reserved`. Debounce 400 ms przy wpisywaniu.
3. **Rezerwacja.** Przy kliknięciu „Utwórz postać” serwer wykonuje atomowe `INSERT ... ON CONFLICT` na unikalnym indeksie `unique_key`:
   - sukces → nazwa zarezerwowana na **15 minut** (rekord `reservation` z TTL), powiązana z sesją gracza;
   - konflikt → odpowiedź `taken`, klient pokazuje błąd i sugestie alternatyw.
4. **Potwierdzenie.** Finalizacja tworzenia postaci zamienia rezerwację na trwały rekord. Wygaśnięcie TTL bez finalizacji zwalnia klucz.

#### Polityka kolizji

| Sytuacja | Zachowanie |
|---|---|
| Nazwa zajęta | Blok + 5 sugestii (warianty z generatora na bazie tego rdzenia) |
| Race condition (dwóch graczy naraz) | Wygrywa atomowy `INSERT`; przegrany dostaje `taken` i sugestie |
| Konto usunięte | Klucz wraca do puli po **30 dniach** karencji |
| Rezerwacja wygasła | Klucz natychmiast dostępny |
| Multi-shard / multi-region | Globalny indeks unikalności (jedna autorytatywna tablica nazw) |

Sugestie alternatyw: do bazowego rdzenia generator dokłada suffix tej samej rasy lub liczbę-słowną nie psując klimatu (np. „Theron” zajęte → „Theronil”, „Therondir”, „Therwyn”). Nie dopisujemy surowych cyfr.

### 5.9. Przydomki i tytuły

- **Tytuł (prefiks):** wyświetlany przed imieniem, zdobywany za osiągnięcia (np. ubicie bossa, ukończenie rajdu, level cap 99). Gracz wybiera jeden aktywny ze zdobytych w panelu postaci.
- **Przydomek (suffiks):** wyświetlany po imieniu w „«…»”, zdobywany za czyny w świecie (PvP, eksploracja, profesje).
- **Zasoby:** każdy tytuł/przydomek to Resource `TitleData { id, display_text, source, race_locked?, gender_variants? }`. Przypisane do konta postaci w `unlocked_titles: Array[StringName]`, aktywny w `active_title` / `active_epithet`.
- **Wyświetlanie:** nad głową (nameplate) — `Tytuł Imię «Przydomek»`; w UI listy — pełna forma; w czacie — tylko Imię (+ przydomek opcjonalnie). Lokalne ustawienie pozwala ukryć tytuły innych graczy dla czytelności.

### 5.10. Przykładowe wygenerowane nazwy

Oznaczenia: **M** męskie, **K** żeńskie, **N** neutralne.

#### Duryjczycy (ludzie, klasyczny fantasy)
| Imię | Płeć | Imię | Płeć |
|---|---|---|---|
| Theron | M | Eldric | M |
| Garrwon | M | Aldwyn | M |
| Cedran | M | Mirelda | K |
| Elenwyn | K | Brisanne | K |
| Rowena | K | Adela | K |
| Avenor | N | Maren | N |

Nazwiska: Valdoryn, Ashford, Brightmont, Halewick, Caldren.
Tytuły/przydomki: „Strażnik Duralanii”, „«Sprawiedliwy»”, „Pogromca Smoków”.

#### Sylvani (leśni, miękkie brzmienie)
| Imię | Płeć | Imię | Płeć |
|---|---|---|---|
| Aerendir | M | Thalion | M |
| Caelthas | M | Faelros | M |
| Laewen | K | Sylmara | K |
| Mirael | K | Arianael | K |
| Nimiel | K | Elaria | K |
| Vael’ir | N | Liriaen | N |

Nazwiska: Liściocień, Srebrolist, Świtublask, Cichodrzew.
Tytuły/przydomki: „Strażnik Verdant Hollow”, „«Cichostopy»”, „Pieśniarz Drzew”.

#### Karłowie z Grimholdu (twarde, kute brzmienie)
| Imię | Płeć | Imię | Płeć |
|---|---|---|---|
| Thordur | M | Brangrim | M |
| Durgar | M | Korbryn | M |
| Grimbal | M | Hildra | K |
| Brunhild | K | Dagna | K |
| Thyra | K | Greta | K |
| Borin | N | Runa | N |

Nazwiska: Kamieństein, Żelazokuź (Ironforge), Głębrun, Młotobrew.
Tytuły/przydomki: „Mistrz Kuźni”, „«Niezłomny»”, „Górnik Frosthelm”.

#### Embrani (ognisty, ostry, syczący)
| Imię | Płeć | Imię | Płeć |
|---|---|---|---|
| Azkar | M | Pyrvash | M |
| Vyrran | M | Szandor | M |
| Emberka | K | Zaryka | K |
| Ashira | K | Velsza | K |
| Kasza | K | Ignara | K |
| Vex | N | Zarei | N |

„Nazwiska”/epitety: Płomiennorodni, Z Popielnej Krwi, Żarogrzywi.
Tytuły/przydomki: „Naznaczony Ogniem”, „«Płomienny»”, „Syn Emberwaste”.

#### Orguni (mocne, klanowe, dudniące)
| Imię | Płeć | Imię | Płeć |
|---|---|---|---|
| Grommash | M | Throk | M |
| Gar’ruk | M | Maugor | M |
| Drakgor | M | Urzma | K |
| Sharga | K | Gretka | K |
| Mokira | K | Gharda | K |
| Zug | N | Rok’na | N |

Klany (zamiast nazwiska): z Klanu Krwawego Kła, z Klanu Roztrzaskanej Pięści, z Klanu Burzogóry.
Tytuły/przydomki: „Wódz Klanu”, „«Honorowy»”, „Łamacz Tarcz”.

#### Feruni (zwierzęcy, szybkie, urywane)
| Imię | Płeć | Imię | Płeć |
|---|---|---|---|
| Rharr | M | Faolan | M |
| Kishi | M | Verix | M |
| Shaela | K | Nyssa | K |
| Faela | K | Tarii | K |
| Mirra | K | Senna | K |
| Vix | N | Asho | N |

Nazwiska/totemy: Cichołapy, Bystroślad, Nocnogrzywy, Wiatrobiegacze.
Tytuły/przydomki: „Tropiciel Stada”, „«Bystry»”, „Cień Boru”.

### 5.11. Integracja techniczna (Godot 4.7)

- **Autoload `NameService`** — ładuje wszystkie `NameData` (`res://data/names/*.tres`), `blocklist.txt`, `FilterConfig`. API: `generate_name(race_id, gender)`, `generate_surname(race_id, gender)`, `validate(name) -> Result`, `check_availability(unique_key)` (async, signal `availability_checked`), `reserve(unique_key)`.
- **Dane w Resource** — `NameData`, `FilterConfig`, `TitleData` jako klasy `Resource` z `@export`, zgodnie z architekturą data-driven; edytowalne w inspektorze i z JSON.
- **UI tworzenia postaci** — pole tekstowe (walidacja live + debounce), przycisk „Losuj” (per rasa/płeć aktualnego wyboru), wskaźnik dostępności (zielony/czerwony/„sprawdzam…”), lista sugestii.
- **Sieć (host-authoritative).** Walidacja długości/znaków/filtra po stronie klienta dla UX, ale autorytet ma serwer: ponowna walidacja + atomowa rezerwacja na serwerze, bez zaufania do klienta.
- **Lokalizacja.** Komunikaty filtra i UI przez `tr()`; blocklist rozszerzalny per region.


---

## 6. Interfejs użytkownika kreatora

Rozdział definiuje kompletny, gotowy do implementacji projekt UI kreatora postaci: układ ekranów per etap, scenę prezentacyjną podglądu 3D, sterowanie kamerą modelu (mysz + gamepad), animacje przejść, warstwę audio i efektów wizualnych, podświetlenia, responsywność, dostępność oraz mapowanie całości na węzły i zasoby Godot 4.7. Powiązanie z sekcją 1 (8 etapów) jest jawne — każdy etap ma osobny opis ekranu.

### 6.1. Założenia i filozofia UI

Cel: kreator ma być tak intuicyjny i płynny jak ekrany tworzenia postaci w BDO/ESO/FFXIV, ale w stylu voxelowym i czytelnej palecie zgodnej z `ART-DIRECTION-AAA.md`. Zasady:

- **Stała rama, zmienna treść** — pasek etapów, podgląd 3D i przyciski nawigacji są nieruchome przez cały proces; zmienia się wyłącznie panel opcji w kolumnie po prawej. Daje to poczucie ciągłości i obniża obciążenie poznawcze.
- **Podgląd zawsze widoczny** — model 3D jest renderowany na żywo w `SubViewport` i reaguje natychmiast na każdą zmianę. Brak ekranów „ładowania” między etapami.
- **Jeden spójny język wejścia** — każda akcja jest osiągalna myszą+klawiaturą ORAZ gamepadem; fokus jest zawsze widoczny (obrys), nigdy nie „znika”.
- **Data-driven** — opcje w panelach generowane są z zasobów `.tres` (rasy, klasy, kolory, fryzury), więc dodanie nowej opcji = dodanie zasobu, bez zmian w kodzie UI.

### 6.2. Mapa 8 etapów (powiązanie z sekcją 1)

Kreator prowadzi przez 8 etapów. Kolejność i zakres są kanoniczne dla całego GDD postaci.

| # | Etap | Zakres edycji | Fokus kamery |
|---|------|---------------|--------------|
| 1 | **Rasa** | wybór 1 z 6 ras (Duryjczycy, Sylvani, Karłowie z Grimholdu, Embrani, Orguni, Feruni) | cała sylwetka (full body) |
| 2 | **Klasa** | wybór 1 z 11 klas (Wojownik, Paladyn, Berserker, Łucznik, Łotrzyk, Zabójca, Mag, Nekromanta, Kapłan, Druid, Mnich) | sylwetka + poza klasowa |
| 3 | **Płeć i budowa** | płeć/wariant, skala wzrostu, proporcje kończyn, masa | full body |
| 4 | **Twarz** | kształt głowy, oczy, nos, usta, uszy, znamiona ras (np. ember-glow Embrani) | **zbliżenie na twarz** |
| 5 | **Włosy i zarost** | fryzura, broda/wąsy, długość, kolor włosów | popiersie (head + shoulders) |
| 6 | **Karnacja i barwy** | kolor skóry/futra (Feruni), kolory oczu, malatury/tatuaże, paleta klanowa | full body + szybki cut na twarz |
| 7 | **Zasoby i potwierdzenie statów** | przypisany zasób klasy (Furia/Mana/Focus), podgląd bazowych statów (base→flat→increased%→more), strój startowy | full body w pozie idle |
| 8 | **Imię i podsumowanie** | nazwa postaci, walidacja, ekran przeglądu wszystkich wyborów, „Utwórz” | obrót prezentacyjny 360° |

> Uwaga: etapy 1–2 (rasa/klasa) muszą używać DOKŁADNIE kanonicznych nazw z sekcji wstępnej. Lista opcji jest filtrowana per rasa tam, gdzie ma to sens (np. malatury klanowe Orgunów, znamiona ember Embrani).

### 6.3. Globalny układ ekranu (rama)

Ekran dzieli się na 4 strefy. Wymiary podane dla bazowej rozdzielczości projektowej **1920×1080** (skalowane proporcjonalnie — patrz 6.10).

```
┌──────────────────────────────────────────────────────────────────────────┐
│  [1] PASEK ETAPÓW  ●Rasa ─ ○Klasa ─ ○Budowa ─ ○Twarz ─ ○Włosy ─ ... (8)    │  h≈84 px
├───────────────────────────────────────────────┬──────────────────────────┤
│                                                │  [3] PANEL OPCJI         │
│                                                │  ┌─────────────────────┐ │
│              [2] PODGLĄD 3D                    │  │  Tytuł etapu        │ │
│           (SubViewport, scena prezent.)        │  │  ───────────────    │ │
│                                                │  │  ▣ opcja A  (aktywna)│ │
│              ◀ obrót / zoom ▶                  │  │  ▢ opcja B          │ │  szer.
│                                                │  │  ▢ opcja C          │ │  panelu
│                                                │  │  ...                │ │  ≈560 px
│                                                │  │  [slider proporcji] │ │
│                                                │  └─────────────────────┘ │
│   szer. ≈ 1360 px                              │  opis/tooltip wybranej   │
├───────────────────────────────────────────────┴──────────────────────────┤
│  [4] NAWIGACJA      [↺ Reset]      [< Wstecz]            [Dalej >]          │  h≈96 px
└──────────────────────────────────────────────────────────────────────────┘
```

- **[1] Pasek etapów (góra):** 8 węzłów-kropek połączonych linią, etap aktywny powiększony i podświetlony kolorem akcentu, etapy ukończone „wypełnione”, przyszłe wyszarzone. Klik/kliknięcie gamepadem na ukończony etap pozwala cofnąć się bezpośrednio. Pełni rolę paska postępu.
- **[2] Podgląd 3D (centrum-lewo):** największa strefa; renderuje żywy model na postumencie. Pod modelem mały hint sterowania kamerą (znika po 4 s lub po pierwszym obrocie).
- **[3] Panel opcji (prawo):** przewijalna lista opcji bieżącego etapu + kontrolki (suwaki, próbniki kolorów). Na dole panel opisu/tooltip wybranej opcji (krótki lore + bonus mechaniczny).
- **[4] Nawigacja (dół):** `Reset` (przywróć domyślne dla etapu), `Wstecz`, `Dalej`. Na etapie 8 `Dalej` zmienia się w `Utwórz postać` z wyróżnionym kolorem.

### 6.4. Scena prezentacyjna podglądu 3D

Renderowana do `SubViewport` (własny świat 3D, izolowany od głównej gry), wyświetlana przez `SubViewportContainer` / `TextureRect` w warstwie Control.

**Skład sceny `CreatorStage.tscn`:**

- **Postument (`Pedestal`)** — niski voxelowy dysk/kamienna płyta; obraca się o ~2°/s w bezruchu (idle „turntable”), aby model nie wyglądał statycznie. Materiał ciemny, matowy, by nie konkurował z postacią.
- **Tło (`Backdrop`)** — gradientowa kopuła/skybox w barwach neutralnych (ciemny granat → grafit), z subtelną mgłą atmosferyczną i delikatnym bloomem. Na etapie 1 tło może subtelnie sugerować biom wybranej rasy (las/pustynia/śnieg) — gradient i kolor mgły zmieniają się płynnie po wyborze rasy.
- **Oświetlenie 3-punktowe (filmowe):**

| Światło | Typ | Rola | Energia | Barwa | Kąt |
|---------|-----|------|---------|-------|-----|
| Key | `DirectionalLight3D` | główne, modeluje twarz | 1.6 | ciepła 5200 K | 35° z przodu-lewo, 40° nad |
| Fill | `DirectionalLight3D` | wypełnia cienie | 0.5 | chłodna 6500 K | z prawej, na wprost |
| Rim | `OmniLight3D`/`SpotLight3D` | obrys, oddziela od tła | 1.0 | akcent biomu | zza modelu, lekko z góry |

- **Kamera (`PreviewCamera3D`)** — orbituje wokół `CameraPivot` (gimbal yaw+pitch). FOV 35° (lekka teleobiektywowa kompresja, korzystna dla postaci). `WorldEnvironment` z SSAO (subtelne), bloom (próg wysoki), tonemapping ACES.
- **Cienie** — `DirectionalLight3D` rzuca miękki cień na postument (kontaktowy), wzmacnia osadzenie modelu.

**Renderowanie:** `SubViewport` w trybie `UPDATE_ALWAYS`, MSAA 4x, rozdzielczość = rozmiar kontenera × `render_scale` (1.0 desktop, możliwy 0.85 dla słabszego sprzętu). Model to ta sama postać parametryczna co w grze (`CharacterAppearance` Resource), więc podgląd jest 1:1 z efektem końcowym.

### 6.5. Sterowanie kamerą modelu (obrót / zoom / fokus)

Sterowanie działa tylko gdy kursor/fokus jest nad strefą podglądu **[2]** (myszą) lub gdy aktywny jest „tryb modelu” gamepadem (prawy stick zawsze steruje kamerą podglądu, bo lewy stick nie ma w kreatorze funkcji ruchu).

| Akcja | Mysz + klawiatura | Gamepad |
|-------|-------------------|---------|
| Obrót (yaw/pitch) | LPM + przeciągnięcie | Prawy analog |
| Zoom | Kółko myszy | LT/RT lub D-pad ↑/↓ |
| Reset kamery | Klawisz `F` lub przycisk ⟳ na HUD podglądu | Naciśnięcie prawego analoga (R3) |
| Fokus na twarz | Dwuklik na głowie / autom. na etapie 4 | autom. na etapie 4 + przycisk Y |
| Auto-obrót on/off | Spacja (toggle) | przycisk X |

**Parametry kamery:**

- Yaw: pełne 360°, bez ograniczeń. Pitch: ograniczony do **−25°…+30°** (by nie wejść „pod” lub „nad” model).
- Zoom: dystans pivota od **1.2 m** (zbliżenie twarzy) do **4.5 m** (cała sylwetka z postumentem), z wygładzeniem (lerp do celu, czas ~0.18 s).
- **Czułość** osobno dla myszy i gampada, regulowana w ustawieniach; martwa strefa analoga 0.15; krzywa odpowiedzi kwadratowa dla precyzji przy małych wychyleniach.
- Bezwładność/wygładzenie: obrót używa exponential smoothing (`current = lerp(current, target, 1 - exp(-k*dt))`, k≈12) — natychmiastowa reakcja, brak „gumy”, łagodne wyhamowanie.

**Fokus na twarz (etap 4):** przy wejściu w etap kamera płynnie (0.5 s, krzywa ease-in-out) przelatuje do presetu twarzy: pivot na wysokości głowy, dystans 1.2 m, lekko z góry (pitch +8°), pitch-lock zawężony do −10°…+18°. Przy wyjściu z etapu wraca do ostatniej swobodnej pozycji. Preset jako `Resource` `CameraFocus.tres` per etap (pivot offset, dystans, FOV, limity pitch) — data-driven.

### 6.6. Animacje przejść między etapami

Sterowane przez `AnimationPlayer` (UI) + `Tween` dla wartości dynamicznych. Czas bazowy przejścia: **0.28 s**.

- **Wymiana panelu opcji:** stary panel wyjeżdża w prawo + zanika (slide-out, alpha 1→0, x +40 px), nowy wjeżdża z prawej (slide-in, alpha 0→1, x −40 px → 0). Krzywa `ease-out cubic`. Lista opcji w nowym panelu pojawia się ze „staggerem” — każda pozycja z opóźnieniem 0.03 s (efekt kaskady).
- **Pasek etapów:** marker aktywnego etapu przesuwa się płynnie (Tween na pozycji) wzdłuż linii; kropka rośnie (scale 1.0→1.25) i pulsuje raz.
- **Kamera:** przejście do presetu fokusu danego etapu (patrz 6.5) jest częścią animacji etapu — synchronizowane z wymianą panelu.
- **Kierunek:** przy `Wstecz` animacje są lustrzane (panel z lewej). Sygnał `stage_changed(old, new, direction)` steruje wyborem klipu.
- **Brak blokady inputu** podczas przejścia poza ~0.1 s na początku (debounce), by uniknąć podwójnego kliknięcia „Dalej”.

### 6.7. Audio (klik / hover / zatwierdzenie)

Warstwa SFX przez dedykowaną szynę audio `UI` (osobny suwak głośności w ustawieniach). Autoload `UiAudio` z metodami `play(event)`.

| Zdarzenie | Dźwięk | Uwagi |
|-----------|--------|-------|
| Hover opcji/przycisku | krótki, miękki „tick” | losowa wariacja pitch ±3% (anti-fatigue) |
| Klik / wybór opcji | wyraźny „klik” | |
| Zmiana suwaka | subtelny „detent” co krok | throttling: max 1 dźwięk / 40 ms |
| Dalej | wznoszący akord | |
| Wstecz | opadający, cichszy ton | |
| Etap niedostępny / walidacja błędna | tępy „buzz” | np. puste imię na etapie 8 |
| **Utworzenie postaci** | fanfara + „whoosh” | zsynchronizowana z efektem wizualnym (6.8) |

Muzyka tła: spokojny, ambientowy motyw menu (pętla), przyciszany o −6 dB w trakcie fanfary finałowej.

### 6.8. Efekty wizualne

- **Podświetlenie aktywnej opcji:** kafel/wiersz wybranej opcji dostaje obrys w kolorze akcentu + delikatne tło-glow + ikonę „✓”. Hover: jaśniejsze tło + lekkie uniesienie (scale 1.02, cień). Fokus klawiatury/gamepada: dodatkowy wyraźny obrys (różny wizualnie od hovera, by były rozróżnialne).
- **Reakcja modelu na zmianę:** przy zmianie cechy (np. fryzury) krótki rozbłysk cząsteczek wokół edytowanego obszaru (głowa przy włosach, całe ciało przy karnacji) — `GPUParticles3D`, ~0.4 s, drobne iskry w kolorze akcentu. Sygnalizuje „co się zmieniło”.
- **Wybór rasy/klasy:** subtelny puls światła Rim w barwie biomu/klasy.
- **Finał (etap 8 → Utwórz):** sekwencja ~1.5 s:
  1. Postać wykonuje pozę bohaterską (klip z `AnimationPlayer` modelu).
  2. Rozbłysk światła (flash overlay alpha 0→0.7→0) + pierścień energii unoszący się z postumentu (`GPUParticles3D`, ring emitter).
  3. Wirujące cząsteczki w kolorze zasobu klasy (Furia=czerwień, Mana=błękit, Focus=zieleń/złoto).
  4. Krótkie vignette + bloom pulse, po czym fade-out do ekranu ładowania świata.
- Wszystkie efekty respektują ustawienie dostępności **„Ogranicz efekty/błyski”** (6.11) — wtedy flash i intensywne cząsteczki są wyłączone/stonowane.

### 6.9. Podświetlenia i stany kontrolek

Zdefiniowane jako stany w `Theme` (StyleBox per stan), spójne dla wszystkich Control:

| Stan | Wygląd |
|------|--------|
| Normalny | tło neutralne, brak obrysu |
| Hover | tło rozjaśnione +8%, miękki cień |
| Fokus (kbd/pad) | obrys 2 px kolor akcentu + delikatna poświata |
| Wybrany/aktywny | wypełnienie akcentem (przyciemnione), ikona ✓, tekst pogrubiony |
| Wyłączony | alpha 0.4, brak interakcji |

Fokus jest ZAWSZE jawnie rysowany (nigdy „niewidzialny”), co jest kluczowe dla nawigacji gamepadem i dostępności.

### 6.10. Responsywność i obsługa wejścia

**Skalowanie do rozdzielczości:**

- Tryb okna gry: `canvas_items` (lub `viewport`) z bazą **1920×1080**, `keep aspect`. UI skaluje się proporcjonalnie; przy aspektach innych niż 16:9 dochodzą marginesy „letterbox” w neutralnym kolorze.
- Layout oparty o kontenery (`HBoxContainer`/`VBoxContainer`/`MarginContainer`/`AspectRatioContainer`) + kotwice — bez sztywnych pozycji pikselowych.
- **Breakpointy:**
  - ≥1600 px szer. — układ pełny (podgląd + panel obok).
  - 1280–1599 px — panel opcji węższy (~480 px), fonty −1 stopień.
  - <1280 px / pionowy ekran — układ awaryjny: podgląd u góry (40% wysokości), panel opcji pod spodem (scroll), pasek etapów kompaktowy (tylko numery + tytuł aktywnego). Nawigacja przyklejona do dołu.

**Mysz + klawiatura:**

- Tab/Shift+Tab cykl po kontrolkach; strzałki nawigują w obrębie listy opcji; Enter = wybór; `Q`/`E` lub `,`/`.` = Wstecz/Dalej; Esc = wyjście/anuluj z potwierdzeniem.
- Strefa podglądu obsługuje mysz wg 6.5.

**Gamepad (pełna parzystość):**

- Lewy stick / D-pad: nawigacja po opcjach panelu.
- Prawy stick: zawsze kamera podglądu.
- A/✕: wybór; B/○: Wstecz; X: toggle auto-obrót; Y: fokus twarz/reset fokusu.
- LB/RB: skok między etapami (poprzedni/następny); LT/RT: zoom.
- Start: ekran ustawień; gamepadowy „cursor focus” widoczny zawsze (StyleBox fokusu).
- Dynamiczne podpowiedzi przycisków: ikony A/B/X/Y vs „Klik/Esc/Tab” przełączają się automatycznie zależnie od ostatniego użytego urządzenia (`Input.get_connected_joypads()` + ostatnie zdarzenie). Autoload `InputHints` zamienia ikony w UI w locie.

### 6.11. Dostępność

- **Rozmiar fontów:** skala UI **80%–150%** (krok 10%) niezależna od skali rozdzielczości; bazowy font tekstu 22 px @1080p, nagłówki 34 px, minimalny czytelny 16 px po skalowaniu.
- **Kontrast:** paleta UI spełnia WCAG AA (kontrast tekst/tło ≥ 4.5:1; elementy aktywne ≥ 3:1). Tryb wysokiego kontrastu (grubsze obrysy, mocniejsze tła paneli).
- **Daltonizm:** stany nie polegają wyłącznie na kolorze — zawsze towarzyszy ikona/obrys/kształt (np. ✓ przy wyborze, kropka wypełniona vs pusta na pasku etapów). Próbniki kolorów (karnacja/włosy) pokazują nazwę i wartość HEX obok próbki.
- **Remap sterowania:** pełny remap akcji `InputMap` dla klawiatury i gamepada, z zapisem do pliku ustawień; wykrywanie konfliktów; przycisk „Przywróć domyślne”.
- **Redukcja ruchu/efektów:** opcja wyłączająca auto-obrót postumentu, parallax, intensywne cząsteczki i flash finałowy (6.8); przejścia skracane do prostego fade.
- **Czytelność tooltipów:** opóźnienie hovera 0.4 s, tooltip z tłem o pełnym kontraście; wszystkie krytyczne info (bonusy ras/klas) także na stałe w panelu opisu, nie tylko w tooltipie.
- **Bez pułapek czasowych:** żadna decyzja kreatora nie ma limitu czasu.

### 6.12. Opis ekranu — każdy z 8 etapów

#### Etap 1 — Rasa
Panel opcji: siatka 6 kafli ras (ikona/portret + nazwa: Duryjczycy, Sylvani, Karłowie z Grimholdu, Embrani, Orguni, Feruni). Wybór natychmiast podmienia model (full body) i kolor tła/mgły na biom rasy. Pod siatką: opis lore + bonusy rasowe (krótkie wartości). Kamera: full body, dystans 4.0 m, auto-obrót on. „Wstecz” = wyjście do menu (z potwierdzeniem).

```
[Rasa]
┌──────┬──────┬──────┐
│Duryj.│Sylvan│Karłow│   ← kafel aktywny: obrys + ✓
├──────┼──────┼──────┤
│Embran│Orguni│Feruni│
└──────┴──────┴──────┘
Opis: <lore + bonusy>
```

#### Etap 2 — Klasa
Panel: lista/siatka 11 klas (Wojownik, Paladyn, Berserker, Łucznik, Łotrzyk, Zabójca, Mag, Nekromanta, Kapłan, Druid, Mnich), pogrupowana ikonami archetypu (melee/ranged/caster/support). Wybór podmienia startowy strój/broń na modelu i odtwarza krótką pozę klasową (np. mag — gest rzucania). Panel opisu: rola, zasób klasy (Furia/Mana/Focus), 1–2 zdania o stylu gry. Kamera: full body + lekkie zbliżenie na pozę.

#### Etap 3 — Płeć i budowa
Panel: przełącznik płci/wariantu (segmented control) + suwaki: Wzrost (skala), Masa/budowa, Proporcje kończyn (ramiona/nogi/tors). Model reaguje na żywo (parametryczna voxelowa sylwetka). Próbka „przed/po” przy suwakach. Kamera: full body, auto-obrót on.

#### Etap 4 — Twarz
Panel: zakładki cech — Kształt głowy, Oczy, Nos, Usta, Uszy, Znamiona (np. ember-glow Embrani, wzory Sylvani). Każda zakładka: galeria presetów + ewentualne mikro-suwaki. **Kamera automatycznie wykonuje fokus na twarz** (preset z 6.5), pitch-lock zawężony, auto-obrót off (by edycja była stabilna). Dwuklik/Y wraca do full body na podgląd ogólny.

```
[Twarz]  (kamera: zbliżenie na głowę)
Zakładki: Głowa | Oczy | Nos | Usta | Uszy | Znamiona
Galeria presetów ▣▢▢▢
[mikro-suwaki: rozstaw oczu, itp.]
```

#### Etap 5 — Włosy i zarost
Panel: galeria fryzur, osobno zarost (broda/wąsy) — dostępność zarostu zależna od płci/rasy (np. brak u części wariantów). Suwak długości tam, gdzie ma sens. Próbnik koloru włosów (paleta + HEX). Kamera: popiersie (head + shoulders), dystans ~2.0 m, auto-obrót on (wolniej), cząsteczki przy zmianie fryzury.

#### Etap 6 — Karnacja i barwy
Panel: próbniki — Kolor skóry/futra (Feruni — wzory futra), Kolor oczu, Malatury/tatuaże/paleta klanowa (Orguni), Akcenty. Próbki z nazwą + HEX (dostępność). Zmiana koloru ciała → krótki rozbłysk cząsteczek wzdłuż sylwetki + szybki cut kamery na twarz dla podglądu odcienia, potem powrót do full body.

#### Etap 7 — Zasoby i potwierdzenie statów
Panel (głównie informacyjny + drobne wybory): przypisany zasób klasy (Furia/Mana/Focus) z ikoną i opisem, tabela bazowych statów z rozpisanym pipeline'em base→flat→increased%→more, wybór wariantu stroju startowego (jeśli przewidziany). Kamera: full body w pozie idle. To „checkpoint” spójności — gracz widzi konsekwencje wyborów ras+klasa.

```
[Zasoby i staty]
Zasób klasy: ◇ Mana
Staty:  HP  base 100 → flat +20 → +15% → more ×1.0 = 138
        ...
Strój startowy: ▣ A  ▢ B
```

#### Etap 8 — Imię i podsumowanie
Panel: pole tekstowe imienia (walidacja: długość 2–20, dozwolone znaki, brak pustego — błąd = SFX buzz + komunikat), lista-przegląd wszystkich wyborów (Rasa, Klasa, Płeć/budowa, Twarz, Włosy, Barwy, Zasób) z możliwością kliknięcia → skok do danego etapu. Przycisk nawigacji zmienia się na **„Utwórz postać”** (wyróżniony). Kamera: prezentacyjny obrót 360°, auto-obrót on. Po zatwierdzeniu — sekwencja finałowa (6.8) i przejście do świata.

### 6.13. Realizacja w Godot 4.7 (architektura węzłów)

Drzewo sceny `CharacterCreator.tscn`:

```
CharacterCreator (Control, anchor full rect)
├─ UiAnimator (AnimationPlayer)            # przejścia paneli/paska
├─ Theme (zasób Theme przypięty do roota)  # StyleBox per stan, fonty
├─ Background (TextureRect/ColorRect)
├─ MainLayout (MarginContainer > VBoxContainer)
│  ├─ StageBar (HBoxContainer)             # 8× StageDot (Control)
│  ├─ Body (HBoxContainer)
│  │  ├─ PreviewArea (SubViewportContainer | AspectRatioContainer)
│  │  │  └─ SubViewport (UPDATE_ALWAYS, MSAA 4x)
│  │  │     └─ PreviewScene (instancja CreatorStage.tscn)
│  │  │        ├─ WorldEnvironment
│  │  │        ├─ CameraPivot > PreviewCamera3D
│  │  │        ├─ KeyLight / FillLight / RimLight
│  │  │        ├─ Pedestal (MeshInstance3D + idle turntable)
│  │  │        ├─ CharacterPreview (model param. + AnimationPlayer)
│  │  │        └─ FxParticles (GPUParticles3D)
│  │  └─ OptionsPanel (PanelContainer > VBox + ScrollContainer)
│  │     └─ StageOptions (instancja per etap, podmieniana)
│  └─ NavBar (HBoxContainer: Reset | Wstecz | Dalej/Utwórz)
└─ Overlays (CanvasLayer: flash, tooltipy, hinty przycisków)
```

**Wzorce i zasoby (data-driven, zgodnie z architekturą projektu):**

- **`CreatorStageData` (Resource, .tres) per etap** — pola: `id`, `title`, `option_source` (ścieżka do listy opcji .tres lub kolekcji ras/klas), `camera_focus` (`CameraFocus.tres`), `auto_rotate: bool`, `scene_variant` (full/face/bust). Sterownik kreatora iteruje po tablicy `stages: Array[CreatorStageData]`. Dodanie/zmiana etapu = edycja zasobów.
- **Opcje (rasy/klasy/fryzury/kolory)** jako kolekcje Resource — panel `StageOptions` generuje kafle/wiersze dynamicznie (`for opt in data.options`), więc UI nie zna konkretnych opcji.
- **`Theme`** trzyma StyleBoxy dla stanów (normal/hover/focus/pressed/disabled), czcionki i skalę; tryb wysokiego kontrastu i skala fontów to alternatywne zasoby Theme nakładane runtime.
- **`AnimationPlayer` (UiAnimator)** — klipy `stage_next`, `stage_prev`, `finalize`; wartości dynamiczne (pozycja markera, kamera) dopinane `Tween` w kodzie.
- **`SubViewport`** izoluje świat 3D podglądu; obraz wchodzi do warstwy Control przez `SubViewportContainer`. Wejście myszy nad podglądem przekazywane do kontrolera kamery (orbit/zoom).
- **Autoloady:** `UiAudio` (SFX), `InputHints` (ikony kbd/pad), `Settings` (skala UI, kontrast, czułość, remap), `CharacterDraft` (bieżący `CharacterAppearance` budowany przez etapy; na etapie 8 zapisywany do Resource gracza).
- **Stan kreatora** w lekkiej maszynie stanów (enum etapów + sygnały `stage_changed`, `option_selected`, `draft_updated`); model w `SubViewport` subskrybuje `draft_updated` i odświeża parametry oraz wyzwala FxParticles.
- **Sygnały** zamiast twardych referencji między panelem a podglądem — luźne sprzężenie, łatwa rozbudowa.

**Wydajność:** `SubViewport` w `UPDATE_ALWAYS` tylko w kreatorze; model voxelowy jest tani, więc 60+ FPS bez problemu. Opcjonalny `render_scale` 0.85 i wyłączenie SSAO na profilu „low”. Cząsteczki finałowe one-shot (po emisji zwalniane).


---

## 7. System sterowania postacią (TPP) — najwyższy priorytet

Ten rozdział definiuje rdzeń odczuwalnej jakości gry. Sterowanie musi być natychmiast responsywne, płynne i czytelne — na poziomie najlepszych action-MMO/action-RPG (GW2, BDO, ESO, FFXIV, New World). Wszystkie decyzje projektowe podporządkowane są trzem priorytetom: intuicyjność, płynność, responsywność. Model docelowy to **face-movement + combat-aim**: poza walką postać biegnie twarzą w kierunku ruchu, w walce orientuje się płynnie w stronę celownika (crosshair).

Definicje skrótów używanych w całym rozdziale:
- `cam_basis` — baza orientacji kamery (yaw) zrzutowana na płaszczyznę poziomą.
- `wish_dir` — znormalizowany wektor zamierzonego kierunku ruchu w przestrzeni świata.
- `aim_point` — punkt w świecie wyznaczony raycastem z kamery przez środek ekranu.
- `facing` — bieżący kąt yaw modelu postaci (obrót wokół osi Y).
- `dt` — `delta` z `_physics_process`.

---

### 7.1. Założenia ogólne i stany sterowania

System pracuje w jednym z dwóch trybów facingu, niezależnie od logiki ruchu (ruch zawsze jest względem kamery):

| Tryb | Warunek wejścia | Źródło docelowego facingu | Charakter ruchu |
|---|---|---|---|
| **Eksploracja** (`MODE_EXPLORE`) | Brak aktywnej akcji bojowej i poza `combat_lock_timer` | `wish_dir` (kierunek ruchu) | Postać biegnie zawsze przodem; „S" = obrót i bieg przodem w nowym kierunku |
| **Walka** (`MODE_COMBAT`) | Aktywny atak/skill **lub** wciśnięty modyfikator celowania (PPM) **lub** `combat_lock_timer > 0` | `aim_yaw` (kierunek do `aim_point`) | Możliwy strafe; postać zorientowana na cel, ruch boczny/cofanie zachowuje orientację na crosshair |

`combat_lock_timer` (domyślnie **1.5 s**) utrzymuje tryb walki przez krótki czas po ostatniej akcji bojowej, aby uniknąć ciągłego „przeskakiwania" między trybami podczas serii ataków. Każdy atak/skill/trafienie odświeża timer.

Kluczowa zasada: **ruch (velocity) i facing (rotacja) są rozdzielone.** Ruch zawsze liczony z `wish_dir` w bazie kamery. Tylko facing zmienia źródło docelowego kąta zależnie od trybu.

---

### 7.2. A) Ruch względem kamery 360°

Wejście z klawiszy mapujemy na dwuosiowy wektor wejścia `input_2d` (Vector2), a następnie rzutujemy go na bazę kamery zrzutowaną na płaszczyznę poziomą.

**Krok 1 — odczyt osi wejścia.** Korzystamy z `Input.get_vector` z deadzone, co od razu daje znormalizowany (z zachowaniem analogowej magnitudy gamepada) wektor i poprawnie obsługuje kombinacje:

```gdscript
# x: prawo(+)/lewo(-), y: tył(+)/przód(-) w konwencji ekranu
var input_2d: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
```

Kombinacje klawiszy są obsłużone automatycznie: W+D daje `(0.707, -0.707)`, S+A daje `(-0.707, 0.707)` itd. — pełne 360°. Dla klawiatury magnituda jest zawsze 0 lub 1 po normalizacji; dla gamepada zachowujemy analogowy zakres (chód/bieg progresywny).

**Krok 2 — baza kamery na płaszczyźnie.** Bierzemy wektory forward/right kamery i zerujemy ich składową Y, po czym normalizujemy. Dzięki temu pochylenie kamery (pitch) nie wpływa na kierunek ruchu po ziemi:

```gdscript
var cam_basis: Basis = camera.global_transform.basis
var cam_forward: Vector3 = -cam_basis.z   # Godot: -Z to "przód"
var cam_right: Vector3 = cam_basis.x
cam_forward.y = 0.0
cam_right.y = 0.0
cam_forward = cam_forward.normalized()
cam_right = cam_right.normalized()
```

**Krok 3 — wektor życzenia (wish_dir).** Łączymy osie. Uwaga na znak osi Z: w konwencji `Input.get_vector` `move_forward` zmniejsza `y`, więc `input_2d.y` ujemne = przód:

```gdscript
var wish_dir: Vector3 = (cam_right * input_2d.x) + (cam_forward * -input_2d.y)
if wish_dir.length() > 1.0:
    wish_dir = wish_dir.normalized()
var wish_strength: float = wish_dir.length()  # 0..1 dla blendu animacji
```

`wish_dir` jest teraz pełnym 360° kierunkiem w świecie, niezależnym od orientacji postaci. To on napędza zarówno prędkość (zawsze), jak i — w trybie eksploracji — docelowy facing.

---

### 7.3. B) Płynny obrót postaci

Postać nigdy nie „przeskakuje" na docelowy kąt — interpolujemy `facing` do `target_yaw` z wygładzaniem niezależnym od framerate'u.

**Metoda 1 — wykładnicze wygładzanie (zalecane, framerate-independent):**

```gdscript
var t: float = 1.0 - exp(-turn_sharpness * dt)   # turn_sharpness ~ 12.0..18.0
facing = lerp_angle(facing, target_yaw, t)
```

`lerp_angle` automatycznie wybiera krótszą drogę po okręgu (obsługa zawijania ±π), co eliminuje problem „dalekiej drogi" przy przejściu przez ±180°. Współczynnik `1 - exp(-k*dt)` gwarantuje identyczne odczucie przy 60 i 144 FPS.

**Metoda 2 — obrót ze stałą prędkością kątową z ograniczeniem (do turn-in-place i ostrych zwrotów):**

```gdscript
var diff: float = wrapf(target_yaw - facing, -PI, PI)
var max_step: float = deg_to_rad(turn_speed_deg) * dt   # turn_speed_deg ~ 540..720 °/s
facing += clampf(diff, -max_step, max_step)
```

W praktyce łączymy oba: wygładzanie wykładnicze dla „czucia", z twardym limitem prędkości kątowej, by uniknąć teleportacji przy ekstremalnych skokach inputu.

**Parametry (wartości startowe do tuningu):**

| Parametr | Wartość | Opis |
|---|---|---|
| `turn_sharpness` | 14.0 | Współczynnik k w `1-exp(-k*dt)`; wyżej = ostrzej |
| `turn_speed_deg` | 600 °/s | Twardy limit prędkości kątowej (bieg) |
| `turn_speed_combat_deg` | 900 °/s | Szybszy obrót na cel w walce |
| `turn_in_place_threshold` | 100° | Powyżej tej różnicy w bezruchu odpalamy Turn In Place |
| `align_move_threshold` | 45° | Powyżej tej różnicy postać zwalnia ruch, dopóki się nie „dopasuje" |

**Reakcja na input jest natychmiastowa:** `target_yaw` jest przeliczany w tym samym klatce, w której zmienia się input; jedynie wizualny obrót modelu jest wygładzany. Nigdy nie opóźniamy momentu, w którym `wish_dir` zaczyna napędzać prędkość.

---

### 7.4. C) Ruch do tyłu — bez backpedal

W trybie eksploracji nie ma cofania tyłem. Wciśnięcie **S** daje `wish_dir` skierowany „do gracza/za kamerę", a `target_yaw` ustawiamy na yaw tego wektora — postać płynnie obraca się ~180° i biegnie **przodem** w nowym kierunku.

```gdscript
if wish_strength > 0.01:
    target_yaw = atan2(wish_dir.x, wish_dir.z)   # yaw w stronę ruchu
```

**Unikanie „wirowania" (spinning) przy szybkich zmianach:**

Problem pojawia się, gdy gracz szybko stuka przeciwnymi kierunkami (np. naprzemiennie W i S) albo gdy `wish_dir` przeskakuje o niemal 180° — postać mogłaby zacząć kręcić się w kółko. Rozwiązania, stosowane łącznie:

1. **Próg dopasowania ruchu (`align_move_threshold`).** Gdy różnica między `facing` a `target_yaw` przekracza 45°, mnożymy prędkość przez współczynnik `align_factor` (np. 0.3–0.6), aż postać „dogoni" kierunek. Daje to naturalny łuk skrętu zamiast ślizgu bokiem:

```gdscript
var angle_err: float = absf(wrapf(target_yaw - facing, -PI, PI))
var align_factor: float = clampf(1.0 - (angle_err - deg_to_rad(align_move_threshold)) / PI, 0.3, 1.0)
velocity_planar *= align_factor
```

2. **Histereza / minimalny czas trzymania kierunku.** `target_yaw` aktualizujemy tylko gdy `wish_strength` przekracza próg; przy chwilowym puszczeniu klawiszy (przejście W→S) zachowujemy ostatni `target_yaw`, dopóki nowy input nie ustabilizuje się przez ~0.05 s (mały input buffer kierunku).

3. **Twardy limit prędkości kątowej** (`turn_speed_deg`) zapobiega obrotowi szybszemu niż naturalny — nawet przy natychmiastowym skoku inputu obrót trwa ~0.3 s dla 180°.

4. **Turn-in-place przy bezruchu** (patrz 7.5): jeśli gracz stoi i tylko zmienia kierunek patrzenia ruchem postaci, nie ślizga się, lecz odgrywa animację obrotu w miejscu.

---

### 7.5. Turn In Place (obrót w miejscu)

Gdy `wish_strength == 0` (postać stoi) a `target_yaw` różni się od `facing` o więcej niż `turn_in_place_threshold` (np. po wyjściu z walki, gdy facing był na cel, a teraz gracz chce ruszyć w bok), odpalamy stan `TurnInPlace`:

- Postać pozostaje w miejscu (brak velocity planarnego).
- Odgrywana jest animacja Turn-In-Place (lewo/prawo wg znaku różnicy), zsynchronizowana z obrotem `facing` limitowanym prędkością kątową.
- Po dopasowaniu kąta (`|diff| < 5°`) wraca do `Idle` lub przechodzi w `Start`/`Run`, jeśli pojawił się input ruchu.

W praktyce w trybie eksploracji turn-in-place rzadko jest potrzebny (gracz po prostu rusza i postać skręca w łuku), ale jest kluczowy dla czytelności przy wyjściu z walki i przy starcie z postojem.

---

### 7.6. D) Obrót w walce — orientacja na celownik

W `MODE_COMBAT` źródłem `target_yaw` nie jest kierunek ruchu, lecz kierunek do `aim_point`. Postać może swobodnie strafe'ować (ruch względem kamery działa identycznie), ale tułów/model są zorientowane na cel — to umożliwia atakowanie w jedną stronę przy ruchu w inną.

**Wyznaczenie aim_point (raycast z kamery przez środek ekranu):**

```gdscript
func get_aim_point() -> Vector3:
    var vp_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
    var ray_origin: Vector3 = camera.project_ray_origin(vp_center)
    var ray_dir: Vector3 = camera.project_ray_normal(vp_center)
    var ray_end: Vector3 = ray_origin + ray_dir * AIM_RAY_LENGTH   # 1000.0
    var space := get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
    query.collision_mask = AIM_MASK            # wrogowie + teren, bez własnego ciała
    query.exclude = [self.get_rid()]
    var hit := space.intersect_ray(query)
    if hit:
        return hit.position
    return ray_end                              # brak trafienia -> punkt w nieskończoności na promieniu
```

**Facing na cel (yaw, ignorujemy wysokość):**

```gdscript
var to_aim: Vector3 = aim_point - global_position
to_aim.y = 0.0
if to_aim.length() > 0.01:
    target_yaw = atan2(to_aim.x, to_aim.z)
```

**Kierunek obrażeń/pocisków = aim_point.** Pociski i hitscany lecą do `aim_point` (z punktu wylotu broni, nie ze środka postaci), więc trafienie jest dokładnie tam, gdzie crosshair. Dla pocisków kierunek liczymy `(aim_point - muzzle_pos).normalized()`. Dla ataków stożkowych/melee używamy `target_yaw` jako osi stożka. Combat jest host-authoritative: klient wysyła `aim_point` (lub kierunek) w momencie odpalenia, host waliduje i rozstrzyga trafienia.

Pionowe celowanie (góra/dół) załatwia pitch broni/animacji warstwą upper-body (addytywnie), bez wpływu na yaw lokomocji.

---

### 7.7. E) Kamera — free-look, stały crosshair

Kamera jest TPP, zza prawego barku, na sprężynie (`SpringArm3D`), ze stałym crosshair na środku ekranu.

**Hierarchia węzłów (zalecana):**

```
Player (CharacterBody3D)
└─ CameraPivot (Node3D)        # podąża za pozycją gracza (lerp pozycji), trzyma yaw+pitch kamery
   └─ SpringArm3D              # kolizyjne odsunięcie kamery (spring_length ~ 4.0)
      └─ Camera3D
```

- **Free-look:** mysz/prawa gałka sterują `CameraPivot.rotation.y` (yaw) i pitch (`SpringArm3D` lub osobny węzeł), z limitem pitch np. **−70°..+50°**. Poza walką kamera **nie wymusza** obrotu postaci — gracz może się rozglądać, a postać biegnie tam, dokąd wskazuje `wish_dir`.
- **Pozycja:** `CameraPivot.global_position` podąża za `player.global_position` z lekkim wygładzeniem (`lerp` pozycji, k ~ 20) i offsetem wysokości (cel ~ wysokość barków/głowy).
- **Stały crosshair:** statyczny element UI na środku; `aim_point` zawsze liczony przez ten punkt — niezależnie od trybu.

**Relacja kamera↔postać:**

| Aspekt | Eksploracja | Walka |
|---|---|---|
| Yaw kamery | Niezależny (free-look) | Niezależny (free-look) |
| Facing postaci | = kierunek ruchu (`wish_dir`) | = kierunek do `aim_point` (przez crosshair) |
| Wymuszanie obrotu postaci przez kamerę | Nie | Nie wprost — ale aim_point zależy od kamery, więc obracając kamerę zmieniasz cel |
| Czułość myszy | Standard | Można nieznacznie obniżyć przy precyzyjnym celowaniu (opcja) |

Opcjonalny **soft lock / lekki magnetyzm**: przy aktywnej walce można dodać drobną korektę aim do najbliższego wroga w stożku crosshaira (do rozważenia, domyślnie OFF — priorytet to czystość action-aim).

---

### 7.8. F) System animacji

Lokomocja i akcje bojowe rozdzielone na warstwy w `AnimationTree` (tryb AnimationNodeBlendTree z zagnieżdżonym StateMachine).

**Warstwy:**
1. **Base locomotion** — pełne ciało, sterowane prędkością i kierunkiem.
2. **Upper-body (addytywna)** — ataki, aim, kasty; nakładana addytywnie na lokomocję, by można było atakować w biegu/strafe. Maska kości od kręgosłupa w górę (spine→ręce→głowa).

**Base locomotion — blendspace:**
- W **eksploracji** postać zawsze biegnie przodem → wystarczy **BlendSpace1D** po `speed01` (0=Idle, 0.5=Walk, 1.0=Run/Sprint).
- W **walce** dochodzi strafe → **BlendSpace2D** (`move_forward`, `move_right` względem facingu postaci), dający 8-kierunkowy zestaw (Run F/B/L/R + diagonale) z poprawnym backpedal i strafe na cel.

Parametr kierunku do BlendSpace2D liczymy jako wektor ruchu w lokalnej przestrzeni postaci:

```gdscript
var local_move: Vector3 = global_transform.basis.inverse() * velocity_planar.normalized()
# local_move.z -> przód/tył, local_move.x -> bok; podajemy do BlendSpace2D
```

**State machine (lokomocja):**

```
Idle ──(input)──> Start ──> Run ──(speed up)──> Sprint
  ^                  │         │
  │                  v         v
  └──(no input)── Stop <──── (release)
Idle ──(|diff|>threshold & no input)──> TurnInPlace ──> Idle
(dowolny) ──(jump)──> Jump ──> Fall ──> Land ──> (Idle/Run)
```

| Stan | Wejście | Wyjście | Uwagi |
|---|---|---|---|
| Idle | `speed≈0` | input ruchu → Start | Może iść w TurnInPlace |
| Start | input z postoju | po ~0.15 s → Run | Krótka animacja ruszania (anti-pop) |
| Run | `speed01 > 0.5` | release → Stop; sprint → Sprint | BlendSpace prędkości |
| Sprint | `sprint` wciśnięty i ruch przód | release → Run | Większa prędkość, FOV +5° |
| Stop | release w biegu | → Idle | Krótkie wyhamowanie |
| TurnInPlace | bezruch + duża różnica yaw | po dopasowaniu → Idle | Sync z obrotem |
| Jump/Fall/Land | skok/spadanie | Land→Idle/Run | Coyote + jump buffer |

**Akcje (upper-body, OneShot/StateMachine addytywny):** Attack (combo 1/2/3), Skill_*, Dodge, Roll, Cast. Wyzwalane przez `OneShot` lub osobny mały StateMachine, nakładane na lokomocję. Dodge/Roll mogą tymczasowo przejąć root motion (patrz niżej).

**Root motion vs in-place:**

| Animacja | Tryb | Uzasadnienie |
|---|---|---|
| Walk/Run/Sprint | **In-place** | Prędkość steruje kod (responsywność, multiplayer, brak ślizgu kontrolowany przez dopasowanie animacji do velocity) |
| Idle/TurnInPlace | In-place (obrót kodem) | Pełna kontrola nad kątem |
| Dodge/Roll | **Root motion** | Dystans/krzywa unika muszą być spójne wizualnie; przewidywalny i deterministyczny dla hosta |
| Attack (melee z przemieszczeniem) | **Root motion** (opcjonalnie) | „Lunge" ataku — naturalne dosunięcie do celu |
| Jump/Land | In-place (fizyka kodem) | Łuk skoku liczony fizyką |

Przy root motion w multiplayer: host autorytatywnie odtwarza ruch z animacji i synchronizuje pozycję; klient predykuje.

---

### 7.9. G) Implementacja techniczna — odpowiedzi na 7 punktów

**1) Jak liczyć ruch względem kamery.** Patrz 7.2: `Input.get_vector` → `input_2d`; baza kamery z wyzerowanym Y → `cam_forward`/`cam_right`; `wish_dir = cam_right*x + cam_forward*(-y)`. Prędkość: `velocity_planar = wish_dir * current_speed`, gdzie `current_speed` rośnie/maleje z akceleracją (7.9.5). Ruch jest zawsze względem kamery, w obu trybach.

**2) Jak wyznaczać kierunek względem crosshaira (raycast).** Patrz 7.6: `project_ray_origin`/`project_ray_normal` ze środka viewportu → `PhysicsRayQueryParameters3D` z odpowiednią maską i `exclude=[self]` → `intersect_ray`. Wynik to `aim_point`; brak trafienia → punkt na końcu promienia. To jednocześnie `target_yaw` w walce i cel dla pocisków.

**3) Jak realizować płynny obrót.** Patrz 7.3: `lerp_angle(facing, target_yaw, 1-exp(-k*dt))` + twardy limit prędkości kątowej. `target_yaw` wybierany wg trybu. `facing` aplikowany do modelu (`mesh_root.rotation.y = facing`), nie do całego `CharacterBody3D` jeśli kolider ma być nieobracalny (kapsuła), albo do body jeśli kolider symetryczny.

**4) Jak połączyć sterowanie z animacjami.** Po obliczeniu velocity i facingu ustawiamy parametry `AnimationTree`:
```gdscript
anim_tree.set("parameters/locomotion/blend_position", speed01)            # 1D
# lub dla 2D w walce:
anim_tree.set("parameters/locomotion2d/blend_position", Vector2(local_move.x, -local_move.z))
anim_tree.set("parameters/conditions/moving", wish_strength > 0.01)
```
Stany (Start/Stop/Jump/Turn) sterowane warunkami i sygnałami; akcje przez `OneShot` (`anim_tree.set("parameters/attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)`).

**5) Jak uniknąć sztywnego/drewnianego sterowania.**
- **Akceleracja/decel:** `current_speed` interpolowana do docelowej (`accel ~ 25 m/s²`, `decel ~ 35 m/s²`), zamiast skoku 0→max.
- **Promień skrętu:** dopasowanie ruchu (`align_factor`, 7.4) tworzy łuk zamiast natychmiastowego strafe.
- **Blendy animacji:** Start/Stop, blendspace prędkości, addytywna warstwa upper-body — brak „pop" przy zmianach stanu.
- **Input buffer:** akcje (atak, skill, dodge, jump) buforowane ~0.15 s — naciśnięcie tuż przed końcem poprzedniej akcji odpala się natychmiast po jej zakończeniu.
- **Coyote time:** ~0.12 s po zejściu z krawędzi skok wciąż możliwy.
- **Jump buffer:** ~0.12 s przed lądowaniem — skok wykona się od razu po dotknięciu ziemi.

**6) Jak zaimplementować w Godot 4.**
- Węzeł gracza: `CharacterBody3D` z `CollisionShape3D` (kapsuła).
- Model: `Node3D mesh_root` (obracany `facing`) → `Skeleton3D` + `AnimationPlayer` + `AnimationTree`.
- Kamera: `CameraPivot (Node3D)` → `SpringArm3D` → `Camera3D` (poza hierarchią obrotu modelu, by free-look nie obracał postaci).
- Cała logika w `_physics_process(delta)`: odczyt inputu → `wish_dir` → tryb → `target_yaw` → obrót → prędkość → `move_and_slide()` → update `AnimationTree`.
- Free-look myszy w `_input` (akumulacja yaw/pitch pivotu).
- Autoload `InputModeManager` (opcjonalnie) do przełączania bindów MKB/gamepad i czułości.

**7) Pseudokod / przykładowy GDScript.**

```gdscript
extends CharacterBody3D

@export var camera_pivot: Node3D
@export var camera: Camera3D
@export var mesh_root: Node3D

# --- parametry ---
const WALK_SPEED := 3.0
const RUN_SPEED := 6.0
const SPRINT_SPEED := 9.0
const ACCEL := 25.0
const DECEL := 35.0
const GRAVITY := 22.0
const JUMP_VELOCITY := 8.0

const TURN_SHARPNESS := 14.0
const TURN_SPEED := deg_to_rad(600.0)
const TURN_SPEED_COMBAT := deg_to_rad(900.0)
const TURN_IN_PLACE_THRESHOLD := deg_to_rad(100.0)
const ALIGN_THRESHOLD := deg_to_rad(45.0)

const AIM_RAY_LENGTH := 1000.0
const AIM_MASK := 0b110   # warstwy: teren + wrogowie
const COMBAT_LOCK := 1.5
const ACTION_BUFFER := 0.15
const COYOTE := 0.12

var facing := 0.0
var current_speed := 0.0
var combat_lock_timer := 0.0
var action_buffer_timer := 0.0
var coyote_timer := 0.0
var aim_point := Vector3.ZERO

func _physics_process(dt: float) -> void:
    _update_timers(dt)

    # --- 1) wish_dir względem kamery ---
    var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var cb := camera.global_transform.basis
    var fwd := Vector3(-cb.z.x, 0, -cb.z.z).normalized()
    var rgt := Vector3(cb.x.x, 0, cb.x.z).normalized()
    var wish_dir := (rgt * input_2d.x) + (fwd * -input_2d.y)
    var wish_strength := clampf(wish_dir.length(), 0.0, 1.0)
    if wish_strength > 0.001:
        wish_dir = wish_dir.normalized()

    # --- 2) aim point z crosshaira ---
    aim_point = _get_aim_point()

    # --- tryb ---
    var in_combat := combat_lock_timer > 0.0 or Input.is_action_pressed("aim")

    # --- 3) wyznacz target_yaw wg trybu ---
    var has_move := wish_strength > 0.01
    var target_yaw := facing
    var do_turn_in_place := false

    if in_combat:
        var to_aim := aim_point - global_position
        to_aim.y = 0.0
        if to_aim.length() > 0.01:
            target_yaw = atan2(to_aim.x, to_aim.z)
    else:
        if has_move:
            target_yaw = atan2(wish_dir.x, wish_dir.z)   # bieg przodem (także "S")
        else:
            # bezruch: ewentualny turn-in-place jeśli duża różnica
            var diff_idle := absf(wrapf(target_yaw - facing, -PI, PI))
            if diff_idle > TURN_IN_PLACE_THRESHOLD:
                do_turn_in_place = true

    # --- 4) płynny facing z limitem prędkości kątowej ---
    var max_step := (TURN_SPEED_COMBAT if in_combat else TURN_SPEED) * dt
    var smoothed := lerp_angle(facing, target_yaw, 1.0 - exp(-TURN_SHARPNESS * dt))
    var step := wrapf(smoothed - facing, -PI, PI)
    facing += clampf(step, -max_step, max_step)
    mesh_root.rotation.y = facing

    # --- 5) prędkość (akceleracja) + dopasowanie kierunku (anti-spin) ---
    var target_speed := 0.0
    if has_move:
        target_speed = SPRINT_SPEED if Input.is_action_pressed("sprint") and not in_combat else RUN_SPEED
    var rate := ACCEL if target_speed > current_speed else DECEL
    current_speed = move_toward(current_speed, target_speed, rate * dt)

    var planar := wish_dir * current_speed
    if not in_combat and has_move:
        var ang_err := absf(wrapf(target_yaw - facing, -PI, PI))
        if ang_err > ALIGN_THRESHOLD:
            planar *= clampf(1.0 - (ang_err - ALIGN_THRESHOLD) / PI, 0.35, 1.0)

    velocity.x = planar.x
    velocity.z = planar.z

    # --- grawitacja / skok z coyote + buffer ---
    if is_on_floor():
        coyote_timer = COYOTE
        if _consume_jump_buffer():
            velocity.y = JUMP_VELOCITY
    else:
        velocity.y -= GRAVITY * dt

    move_and_slide()

    # --- 6) update AnimationTree ---
    _update_anim(wish_strength, in_combat, do_turn_in_place)

func _get_aim_point() -> Vector3:
    var center := get_viewport().get_visible_rect().size * 0.5
    var origin := camera.project_ray_origin(center)
    var dir := camera.project_ray_normal(center)
    var space := get_world_3d().direct_space_state
    var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * AIM_RAY_LENGTH)
    q.collision_mask = AIM_MASK
    q.exclude = [get_rid()]
    var hit := space.intersect_ray(q)
    return hit.position if hit else origin + dir * AIM_RAY_LENGTH

func notify_combat_action() -> void:   # wołane przy ataku/skillu/trafieniu
    combat_lock_timer = COMBAT_LOCK
```

Funkcje pomocnicze (`_update_timers`, `_consume_jump_buffer`, `_update_anim`) realizują logikę z punktów 7.8 i 7.9.5.

---

### 7.10. Tabela bindów

**Mysz + klawiatura:**

| Wejście | Akcja |
|---|---|
| W / S / A / D | Ruch przód / „tył" (obrót+bieg) / lewo / prawo (360° względem kamery) |
| Mysz (ruch) | Free-look kamery (yaw/pitch), pozycja crosshaira |
| Lewy przycisk myszy (LPM) | Atak podstawowy / combo (kierunek = crosshair) |
| Prawy przycisk myszy (PPM) | Celowanie / blok / atak alternatywny (modyfikator trybu walki) |
| Spacja | Skok (coyote + jump buffer) |
| Shift (lewy) | Sprint (tylko eksploracja, ruch do przodu) |
| Ctrl (lewy) / C | Unik (Dodge) / przewrót (Roll) |
| 1–6 | Umiejętności klasowe (skille) |
| Q / E | Skille pomocnicze / dodatkowe |
| R | Interakcja / przeładowanie zasobu klasy |
| Tab | Cel/lock najbliższego wroga (opcjonalny soft-lock) |
| F | Interakcja ze światem (loot, NPC) |
| Scroll myszy | Zoom kamery (dystans springa) |
| Esc | Menu |

**Gamepad (układ Xbox):**

| Wejście | Akcja |
|---|---|
| Lewa gałka | Ruch 360° względem kamery |
| Prawa gałka | Free-look kamery / pozycja crosshaira |
| A | Skok |
| Lewy spust LT | Celowanie / tryb walki (modyfikator) |
| Prawy spust RT | Atak podstawowy / combo |
| RB / LB | Skille (modyfikator + face buttons) |
| X / Y / B | Skille / interakcja / unik (konfigurowalne) |
| Naciśnięcie lewej gałki (L3) | Sprint |
| Naciśnięcie prawej gałki (R3) | Lock celu (soft-lock) |
| D-pad | Quickslot / przedmioty |
| Start | Menu |

Czułość, inwersja osi pitch i deadzone gałek konfigurowalne w ustawieniach. Mapy akcji zdefiniowane w Input Map projektu pod nazwami (`move_*`, `aim`, `attack`, `sprint`, `dodge`, `jump`, `skill_1..6`), co pozwala bindować MKB i gamepad do tych samych akcji.

---

### 7.11. Migracja z obecnego kodu (Player.gd)

Obecny `Player.gd` używa modelu **always-face-camera (strafe):** postać jest stale obracana tak, by patrzeć zgodnie z kamerą (yaw postaci = yaw kamery), a ruch jest względem kamery (to zostaje bez zmian). Docelowo wdrażamy **face-movement + combat-aim**.

**Co zostaje (NIE ruszać):**
- Cała logika liczenia `wish_dir` względem kamery (sekcja 7.2) — ten fragment jest już poprawny.
- Liczenie `velocity` z `wish_dir` i `move_and_slide()`.
- Raycast z kamery przez środek ekranu do celowania (jeśli już istnieje) — używany do `aim_point`.

**Co zmienić — DOKŁADNIE gałąź facingu w `_process`/`_physics_process`.** Obecnie jest tam (lub odpowiednik):

```gdscript
# STARY KOD — always-face-camera (strafe):
var cam_yaw := camera_pivot.rotation.y
mesh_root.rotation.y = lerp_angle(mesh_root.rotation.y, cam_yaw, turn_speed * delta)
```

Zastąp to rozgałęzieniem na tryb (eksploracja vs walka), zachowując `wish_dir` i celowanie:

```gdscript
# NOWY KOD — face-movement + combat-aim:
var in_combat := combat_lock_timer > 0.0 or Input.is_action_pressed("aim")
var has_move := wish_strength > 0.01
var target_yaw := facing

if in_combat:
    # walka: orientacja na crosshair (aim_point liczony z istniejącego raycastu)
    var to_aim := aim_point - global_position
    to_aim.y = 0.0
    if to_aim.length() > 0.01:
        target_yaw = atan2(to_aim.x, to_aim.z)
elif has_move:
    # eksploracja w ruchu: twarz w kierunku ruchu (obejmuje "S" = obrót 180° i bieg przodem)
    target_yaw = atan2(wish_dir.x, wish_dir.z)
else:
    # bezruch: trzymaj ostatni facing; ewentualnie turn-in-place przy dużej różnicy
    target_yaw = facing

# płynny obrót (jak dotąd, ale do target_yaw zamiast cam_yaw):
facing = lerp_angle(facing, target_yaw, 1.0 - exp(-TURN_SHARPNESS * delta))
mesh_root.rotation.y = facing
```

**Kluczowe punkty migracji:**
1. Zmienna źródłowa obrotu zmienia się z `camera_pivot.rotation.y` na `target_yaw` wybierany warunkowo — to jedyna „rdzenna" zmiana.
2. Dodaj pole `combat_lock_timer` i wołaj `notify_combat_action()` w miejscach odpalania ataku/skilla/otrzymania trafienia, aby tryb walki utrzymywał się przez `COMBAT_LOCK` sekund.
3. Upewnij się, że obracasz **`mesh_root`**, a nie `camera_pivot` — kamera musi pozostać free-look i niezależna od facingu postaci.
4. Ruch (`velocity` z `wish_dir`) pozostaje nietknięty — dzięki temu strafe w walce działa od ręki (postać patrzy na cel, lecz porusza się względem kamery).
5. Dodaj dopasowanie kierunku (`align_factor`, 7.4) tylko w gałęzi eksploracji, aby uniknąć wirowania przy „S" i ostrych zwrotach.
6. Zamień ewentualny BlendSpace1D na BlendSpace2D w warstwie lokomocji dla trybu walki (strafe/backpedal), zostawiając 1D dla eksploracji — albo użyj jednego 2D z `local_move` (7.8).

Po tej zmianie: poza walką postać biegnie zawsze przodem w kierunku ruchu (w tym płynny obrót przy „S"), w walce orientuje się na crosshair i może strafe'ować, a celowanie i ruch względem kamery pozostają nienaruszone.


---

## 8. Architektura systemu (Data-Driven)

Niniejszy rozdział opisuje docelową architekturę systemu postaci (rasy, klasy, pochodzenie, wygląd, imiona, sterowanie) oraz zasady, według których cała treść gry jest definiowana jako **dane (.tres)**, a nie jako kod. Celem nadrzędnym jest: dodanie nowej rasy, klasy czy pochodzenia ma sprowadzać się do **utworzenia pliku `.tres` i wrzucenia go do odpowiedniego katalogu** — **bez żadnej zmiany w GDScript**. Architektura jest spójna z technologią projektu: Godot 4.7 + GDScript, `Resource` (.tres), autoloady (singletony-serwisy/rejestry), kompozycja komponentów oraz host-authoritative combat.

### 8.1 Filary architektoniczne

1. **Dane jako zasoby (Data-as-Resources).** Każdy byt konfiguracyjny (rasa, klasa, pochodzenie, preset wyglądu, zestaw reguł imion, profil sterowania) to `Resource` zapisany jako `.tres`. Zasoby są wersjonowalne w Git, edytowalne w inspektorze Godota i ładowalne w runtime.
2. **Kompozycja zamiast dziedziczenia.** `Player` to scena złożona z komponentów (`StatsComponent`, `MovementComponent`, `CombatComponent`, `AnimationComponent`, `ResourceComponent` itd.). Różnice między postaciami wynikają z **danych wstrzykniętych do komponentów**, nie z hierarchii klas GDScript.
3. **Singletony-serwisy / rejestry (autoloady).** Centralny `ContentDB` skanuje `res://` i udostępnia katalogi zasobów. Inne serwisy: `Events` (globalna magistrala sygnałów), `SaveService`, `RNG`.
4. **State machine** dla sterowania i animacji (stany ruchu/walki, blendy).
5. **Observer / sygnały** do luźnego sprzęgania systemów (zdrowie -> UI, śmierć -> loot itd.).
6. **Factory** budujące gotową instancję postaci z `CharacterDefinition` (agregatu danych) -> konfiguracja komponentów.
7. **Walidacja przy starcie.** Rejestry walidują zasoby (unikalność `id`, poprawność referencji, zakresy wartości) i raportują błędy zanim gracz wejdzie do gry.

### 8.2 Architektura klas (przegląd)

| Klasa (class_name) | Bazuje na | Rola | Przechowywana jako |
|---|---|---|---|
| `RaceResource` | `Resource` | Definicja rasy (modyfikatory statów, dozwolone klasy, opcje wyglądu, reguły imion) | `.tres` |
| `GenderOption` | `Resource` | Opcja płci/wariantu sylwetki (wpływa na siatkę i zestaw presetów) | `.tres` |
| `OriginResource` | `Resource` | Pochodzenie (bonusy startowe, ekwipunek, tło fabularne) | `.tres` |
| `ClassResource` | `Resource` | Definicja klasy (zasób klasowy, staty bazowe, drzewo umiejętności, broń) | `.tres` |
| `AppearancePreset` | `Resource` | Pojedynczy preset wyglądu (kolory, indeksy siatek, dodatki) | `.tres` |
| `AppearanceResource` | `Resource` | Katalog dostępnych opcji wyglądu dla rasy/płci (listy presetów i zakresów) | `.tres` |
| `NameRuleSet` | `Resource` | Reguły/generator imion danej rasy (sylaby, prefiksy, długości) | `.tres` |
| `ControlConfig` | `Resource` | Profil sterowania i tuning ruchu/kamery/celowania | `.tres` |
| `CharacterDefinition` | `Resource` | **Agregat**: wybory gracza (rasa+płeć+pochodzenie+klasa+wygląd+imię) | `.tres` (zapis postaci) |
| `ContentDB` | `Node` (autoload) | Rejestr: skanuje `res://`, indeksuje zasoby po `id`, waliduje, udostępnia listy | autoload |
| `CharacterFactory` | `RefCounted` | Buduje gotową instancję `Player` z `CharacterDefinition` | kod |

Wszystkie zasoby konfiguracyjne implementują wspólny kontrakt (przez konwencję): pole `id: StringName` (unikalne, stabilne — używane w zapisach), `display_name: String` (lokalizowalne) oraz `icon: Texture2D`.

### 8.3 Diagram zależności (tekstowy)

```
                         +------------------------+
                         |   ContentDB (autoload) |   skanuje res://content/**
                         |  rejestry po id:        |
                         |   races/ classes/ ...   |
                         +-----------+------------+
                                     | udostępnia listy / lookup(id)
            +------------------------+-----------------------------+
            |                        |                             |
       Kreator Postaci         CharacterFactory                 SaveService
       (UI, czyta listy)       (buduje Player)                  (zapis/odczyt
            |                        |                            CharacterDefinition.tres)
            | produkuje              | czyta agregat
            v                        v
     +---------------+        +--------------------------------------------+
     | Character     |------->|                Player (scena)              |
     | Definition    | wstrz. |  kompozycja komponentów:                   |
     | (agregat)     |        |  StatsComponent  <- RaceResource/ClassRes. |
     +---------------+        |  ResourceComponent (Furia/Mana/Focus)      |
        ^   ^   ^   ^         |  MovementComponent <- ControlConfig        |
        |   |   |   |         |  CombatComponent (host-authoritative)      |
   Race Class Origin          |  AnimationComponent (State Machine)        |
   Appearance/Name            |  AppearanceComponent <- AppearancePreset   |
   (referencje po id)         +---------------------+----------------------+
                                                    | emituje sygnały
                                                    v
                                          +----------------------+
                                          |  Events (autoload)   |  observer/sygnały
                                          |  health_changed,     |  -> UI, audio, loot
                                          |  resource_changed,   |
                                          |  entity_died, ...    |
                                          +----------------------+
```

Kierunek zależności jest jednostronny: **dane (.tres) nie znają kodu komponentów**; to komponenty czytają dane. Kreator i Factory zależą od `ContentDB`, a nie od konkretnych plików. UI zależy od sygnałów (`Events`), nie od logiki bojowej.

### 8.4 Wzorce projektowe (zastosowanie)

| Wzorzec | Gdzie | Po co |
|---|---|---|
| Data-as-Resources | wszystkie `*Resource` | treść edytowalna bez kompilacji, wersjonowalna |
| Kompozycja | `Player` + komponenty | różnice danymi, nie klasami; łatwa rozbudowa |
| Singleton-serwis / Rejestr | `ContentDB`, `Events`, `SaveService`, `RNG` | jeden punkt dostępu, brak twardych referencji |
| Factory | `CharacterFactory` | jedno miejsce budowy postaci z agregatu |
| State machine | `MovementComponent`, `AnimationComponent` | jasne stany ruch/walka, blendy |
| Observer / sygnały | `Events` + sygnały komponentów | luźne sprzęganie, UI reaguje na zdarzenia |
| Strategy (przez dane) | `NameRuleSet`, `ControlConfig` | wymienne algorytmy/tuning bez warunków w kodzie |

**Kompozycja zamiast dziedziczenia (przykład):** nie istnieje `class Mag extends Player`. Istnieje jeden `Player` z `StatsComponent`, do którego `CharacterFactory` wstrzykuje `ClassResource` o `id = &"mag"`. Zmiana balansu maga = edycja `mag.tres`, nie kodu.

### 8.5 Przykładowe struktury danych (GDScript)

#### 8.5.1 `RaceResource`

```gdscript
class_name RaceResource
extends Resource

## Unikalny, stabilny identyfikator (np. &"sylvani"). Używany w zapisach i referencjach.
@export var id: StringName
@export var display_name: String = ""            # np. "Sylvani"
@export_multiline var description: String = ""
@export var icon: Texture2D

# --- Modyfikatory statów wg pipeline base -> flat -> increased% -> more ---
@export_group("Modyfikatory statów (flat)")
@export var flat_strength: int = 0
@export var flat_agility: int = 0
@export var flat_intellect: int = 0
@export var flat_vitality: int = 0

@export_group("Modyfikatory statów (increased %)")
@export var increased_move_speed_pct: float = 0.0   # np. 5.0 = +5%
@export var increased_health_pct: float = 0.0
@export var increased_xp_gain_pct: float = 0.0

# --- Powiązania z resztą systemu (po id, nie po referencji ścieżkowej) ---
@export_group("Powiązania")
@export var allowed_class_ids: Array[StringName] = []   # puste = wszystkie 11 klas
@export var gender_option_ids: Array[StringName] = []
@export var appearance_id: StringName                   # -> AppearanceResource
@export var name_rule_set_id: StringName                # -> NameRuleSet
@export var home_biome: StringName                      # &"verdant_hollow" / &"emberwaste" / &"frosthelm_peaks"

# --- Pasywy rasowe (po id z rejestru pasywów) ---
@export var racial_passive_ids: Array[StringName] = []
```

Kanoniczne pliki: `duryjczycy.tres`, `sylvani.tres`, `karlowie_grimhold.tres`, `embrani.tres`, `orguni.tres`, `feruni.tres`.

#### 8.5.2 `ClassResource`

```gdscript
class_name ClassResource
extends Resource

@export var id: StringName                       # np. &"berserker"
@export var display_name: String = ""            # "Berserker"
@export_multiline var description: String = ""
@export var icon: Texture2D

# Zasób klasowy (Furia / Mana / Focus) — sterowany danymi, nie enumem w kodzie
@export_group("Zasób klasowy")
@export var resource_type: StringName = &"mana"  # &"fury" / &"mana" / &"focus"
@export var resource_max_base: float = 100.0
@export var resource_regen_per_sec: float = 5.0
@export var resource_color: Color = Color(0.2, 0.4, 1.0)

@export_group("Staty bazowe klasy")
@export var base_strength: int = 10
@export var base_agility: int = 10
@export var base_intellect: int = 10
@export var base_vitality: int = 10
@export var base_health: float = 100.0

@export_group("Walka / progresja")
@export var allowed_weapon_ids: Array[StringName] = []
@export var skill_tree_id: StringName                  # -> drzewo umiejętności
@export var starting_skill_ids: Array[StringName] = []
@export var level_cap: int = 99
@export var primary_attribute: StringName = &"strength" # główny stat skalujący

@export_group("Animacje / archetyp")
@export var animation_set_id: StringName               # zestaw blendów dla AnimationComponent
@export var combat_archetype: StringName = &"melee"    # &"melee" / &"ranged" / &"caster"
```

Kanoniczne pliki (11): `wojownik.tres`, `paladyn.tres`, `berserker.tres`, `lucznik.tres`, `lotrzyk.tres`, `zabojca.tres`, `mag.tres`, `nekromanta.tres`, `kaplan.tres`, `druid.tres`, `mnich.tres`.

#### 8.5.3 `AppearancePreset`

```gdscript
class_name AppearancePreset
extends Resource

@export var id: StringName
@export var display_name: String = ""

@export_group("Siatki (indeksy do AppearanceResource)")
@export var body_mesh_index: int = 0
@export var head_mesh_index: int = 0
@export var hair_mesh_index: int = 0
@export var beard_mesh_index: int = -1     # -1 = brak

@export_group("Kolory")
@export var skin_color: Color = Color.WHITE
@export var hair_color: Color = Color.BLACK
@export var eye_color: Color = Color(0.3, 0.5, 0.7)

@export_group("Proporcje (voxel)")
@export_range(0.85, 1.20, 0.01) var height_scale: float = 1.0
@export_range(0.85, 1.20, 0.01) var build_scale: float = 1.0

@export_group("Dodatki")
@export var decal_ids: Array[StringName] = []   # blizny, tatuaże, znamiona (np. ember-glow dla Embrani)
```

#### 8.5.4 `ControlConfig`

```gdscript
class_name ControlConfig
extends Resource

@export var id: StringName = &"default"
@export var display_name: String = "Domyślny"

@export_group("Ruch (względem kamery)")
@export var move_speed: float = 6.0
@export var acceleration: float = 40.0
@export var deceleration: float = 50.0
@export var sprint_multiplier: float = 1.5

@export_group("Obrót postaci")
@export_range(4.0, 30.0, 0.5) var turn_smoothing: float = 12.0   # lerp_angle/exp smoothing
@export var turn_in_place_threshold_deg: float = 100.0           # ostry zwrot -> turn-in-place
@export var face_movement_out_of_combat: bool = true             # poza walką: twarzą w kierunek ruchu
@export var face_aim_in_combat: bool = true                      # w walce: twarzą do celownika

@export_group("Kamera (free-look, TPP)")
@export var camera_distance: float = 4.5
@export var camera_height: float = 1.7
@export_range(0.1, 1.0, 0.01) var mouse_sensitivity: float = 0.35
@export var camera_pitch_min_deg: float = -40.0
@export var camera_pitch_max_deg: float = 70.0
@export var invert_y: bool = false

@export_group("Responsywność")
@export var input_buffer_ms: int = 150          # bufor wejścia akcji
@export var aim_raycast_length: float = 200.0   # raycast z kamery przez crosshair
```

#### 8.5.5 `CharacterDefinition` (agregat)

```gdscript
class_name CharacterDefinition
extends Resource

## Pełna definicja konkretnej postaci gracza — zapisywana jako .tres w slocie zapisu.
## Trzyma WYŁĄCZNIE referencje po id + dane wyboru, nie logikę.
@export var character_name: String = ""
@export var race_id: StringName
@export var gender_id: StringName
@export var origin_id: StringName
@export var class_id: StringName

@export_group("Wygląd (rozwiązany wybór gracza)")
@export var appearance_preset_id: StringName     # bazowy preset
@export var skin_color: Color = Color.WHITE      # nadpisania suwakami w kreatorze
@export var hair_color: Color = Color.BLACK
@export var eye_color: Color = Color(0.3, 0.5, 0.7)
@export var height_scale: float = 1.0
@export var build_scale: float = 1.0

@export_group("Postęp")
@export var level: int = 1
@export var experience: int = 0

@export_group("Sterowanie")
@export var control_config_id: StringName = &"default"

## Walidacja przed użyciem (wywoływana przez Factory/SaveService).
func is_valid() -> bool:
    return race_id != StringName() and class_id != StringName() and origin_id != StringName()
```

### 8.6 Rejestr `ContentDB` — skanowanie `res://` i udostępnianie list

`ContentDB` to autoload, który przy starcie skanuje predefiniowane katalogi, ładuje wszystkie `.tres`, indeksuje je po polu `id` i waliduje. Kreator postaci oraz `CharacterFactory` pytają wyłącznie `ContentDB` — nigdy nie ładują plików po ścieżce.

**Struktura katalogów (konwencja):**

```
res://content/
  races/        *.tres  (RaceResource)
  classes/      *.tres  (ClassResource)
  origins/      *.tres  (OriginResource)
  genders/      *.tres  (GenderOption)
  appearances/  *.tres  (AppearanceResource)
  name_rules/   *.tres  (NameRuleSet)
  controls/     *.tres  (ControlConfig)
```

```gdscript
extends Node
## Autoload: ContentDB. Rejestr wszystkich zasobów treści, indeksowany po id.

# Mapa kategoria -> { id: StringName -> Resource }
var _registry: Dictionary = {}

const CATEGORIES := {
    "races":       "res://content/races/",
    "classes":     "res://content/classes/",
    "origins":     "res://content/origins/",
    "genders":     "res://content/genders/",
    "appearances": "res://content/appearances/",
    "name_rules":  "res://content/name_rules/",
    "controls":    "res://content/controls/",
}

func _ready() -> void:
    for category in CATEGORIES:
        _registry[category] = {}
        _scan_dir(category, CATEGORIES[category])
    _validate()

func _scan_dir(category: String, path: String) -> void:
    var dir := DirAccess.open(path)
    if dir == null:
        push_error("ContentDB: brak katalogu %s" % path)
        return
    for file in dir.get_files():
        # W eksporcie .tres mogą mieć sufiks .remap
        if not (file.ends_with(".tres") or file.ends_with(".tres.remap")):
            continue
        var clean := file.trim_suffix(".remap")
        var res: Resource = load(path + clean)
        if res == null or not ("id" in res) or res.id == StringName():
            push_error("ContentDB: zasób bez poprawnego id: %s" % (path + clean))
            continue
        if _registry[category].has(res.id):
            push_error("ContentDB: duplikat id '%s' w kategorii %s" % [res.id, category])
            continue
        _registry[category][res.id] = res

# --- API dla kreatora i Factory ---
func get_all(category: String) -> Array:
    return _registry.get(category, {}).values()

func get_by_id(category: String, id: StringName) -> Resource:
    return _registry.get(category, {}).get(id, null)

func get_classes_for_race(race_id: StringName) -> Array[ClassResource]:
    var race: RaceResource = get_by_id("races", race_id)
    var out: Array[ClassResource] = []
    if race == null:
        return out
    for c in get_all("classes"):
        if race.allowed_class_ids.is_empty() or race.allowed_class_ids.has(c.id):
            out.append(c)
    return out

# --- Walidacja referencji krzyżowych przy starcie ---
func _validate() -> void:
    for race in get_all("races"):
        if get_by_id("appearances", race.appearance_id) == null:
            push_error("Rasa '%s' wskazuje na nieistniejący appearance_id '%s'" % [race.id, race.appearance_id])
        if get_by_id("name_rules", race.name_rule_set_id) == null:
            push_error("Rasa '%s' wskazuje na nieistniejący name_rule_set_id '%s'" % [race.id, race.name_rule_set_id])
        for cid in race.allowed_class_ids:
            if get_by_id("classes", cid) == null:
                push_error("Rasa '%s' dopuszcza nieistniejącą klasę '%s'" % [race.id, cid])
```

Kreator postaci buduje listy bezpośrednio z API:

```gdscript
# Wypełnienie panelu wyboru rasy
for race: RaceResource in ContentDB.get_all("races"):
    _add_race_button(race.id, race.display_name, race.icon)

# Po wyborze rasy — przefiltrowane klasy
for cls: ClassResource in ContentDB.get_classes_for_race(selected_race_id):
    _add_class_button(cls.id, cls.display_name, cls.icon)
```

### 8.7 `CharacterFactory` — budowa postaci z definicji

Factory tłumaczy agregat `CharacterDefinition` na skonfigurowaną instancję sceny `Player`, wstrzykując dane do komponentów. To jedyne miejsce, które „składa" postać.

```gdscript
class_name CharacterFactory
extends RefCounted

const PLAYER_SCENE := preload("res://entities/player/Player.tscn")

static func build(def: CharacterDefinition) -> Node3D:
    assert(def.is_valid(), "CharacterDefinition niekompletne")

    var race: RaceResource     = ContentDB.get_by_id("races", def.race_id)
    var cls: ClassResource     = ContentDB.get_by_id("classes", def.class_id)
    var origin: OriginResource = ContentDB.get_by_id("origins", def.origin_id)
    var control: ControlConfig = ContentDB.get_by_id("controls", def.control_config_id)

    var player := PLAYER_SCENE.instantiate()

    # Kompozycja: wstrzyknięcie danych do komponentów
    player.get_node("StatsComponent").configure(race, cls, origin, def.level)
    player.get_node("ResourceComponent").configure(cls.resource_type, cls.resource_max_base, cls.resource_regen_per_sec)
    player.get_node("MovementComponent").configure(control)
    player.get_node("CombatComponent").configure(cls, control)         # host-authoritative
    player.get_node("AnimationComponent").configure(cls.animation_set_id)
    player.get_node("AppearanceComponent").apply(def, race)

    player.display_name = def.character_name
    return player
```

`StatsComponent.configure` realizuje pipeline `base -> flat -> increased% -> more`: bierze `base_*` z `ClassResource`, dodaje `flat_*` z `RaceResource`, a następnie mnożniki `increased_*_pct`.

### 8.8 Jak dodać nową treść (ZERO zmian w kodzie)

**Nowa rasa (np. siódma):**
1. Utwórz `res://content/races/nowa_rasa.tres` jako `RaceResource`, ustaw `id = &"nowa_rasa"`, `display_name`, ikonę, modyfikatory.
2. Wskaż istniejące lub nowe `appearance_id` i `name_rule_set_id`.
3. Uruchom grę — `ContentDB._ready()` automatycznie ją wykryje, zwaliduje i poda kreatorowi. Pojawia się w wyborze rasy bez dotykania GDScript.

**Nowa klasa:** utwórz `res://content/classes/nowa_klasa.tres`, ustaw `resource_type`, staty, `skill_tree_id`, `animation_set_id`. Gotowe — pojawi się w kreatorze (i przefiltruje się przez `allowed_class_ids` ras).

**Nowe pochodzenie:** utwórz `res://content/origins/nowe.tres`. Brak zmian w kodzie.

> Jedyne sytuacje wymagające kodu: wprowadzenie **całkowicie nowego TYPU danych** (nowy `class_name ... extends Resource`) lub **nowej kategorii** w `ContentDB.CATEGORIES`. Dodawanie kolejnych egzemplarzy istniejących typów jest czysto danymi.

### 8.9 System konfiguracji i walidacji (zasady)

| Reguła | Egzekwowana przez | Zachowanie przy naruszeniu |
|---|---|---|
| `id` niepuste i unikalne w kategorii | `ContentDB._scan_dir` | `push_error`, zasób pominięty |
| Referencje krzyżowe istnieją (appearance, name_rules, klasy) | `ContentDB._validate` | `push_error` przy starcie |
| Zakresy liczbowe (skale, kąty kamery) | `@export_range` w zasobie | ograniczone już w inspektorze |
| `CharacterDefinition` kompletne przed budową | `CharacterDefinition.is_valid()` + assert w Factory | przerwanie budowy |
| `resource_type` z dozwolonego zbioru (fury/mana/focus) | walidacja w `ResourceComponent.configure` | fallback + ostrzeżenie |

Walidacja działa **fail-fast w trybie deweloperskim** (błędy w konsoli przy starcie), co pozwala wychwycić literówki w `id` zanim trafią do gracza. W buildzie produkcyjnym brakujące/wadliwe zasoby są pomijane z logiem, a kreator pokazuje tylko poprawne pozycje.

### 8.10 Powiązanie ze sterowaniem (zapowiedź sekcji 7)

`ControlConfig` jest danymi wejściowymi dla `MovementComponent`, którego state machine realizuje docelowy model „face-movement + combat-aim": pola `face_movement_out_of_combat`, `face_aim_in_combat`, `turn_smoothing` i `turn_in_place_threshold_deg` parametryzują logikę facing opisaną w sekcji 7, bez zaszywania stałych w kodzie. Dzięki temu tuning responsywności i promienia skrętu jest edytowalny jako zasób, a profile sterowania (np. „klasyczny", „szybki") to po prostu kolejne pliki `.tres` w `res://content/controls/`.


---

## 9. Persistencja danych

Rozdział definiuje kompletny system zapisu i odczytu postaci dla obu trybów gry: **single-player / lokalny co-op** (źródłem prawdy jest plik na dysku gracza) oraz **MMO / autorytatywny serwer** (źródłem prawdy jest baza danych po stronie serwera). Projekt jest data-driven i spójny z architekturą z pozostałych rozdziałów: dane definicyjne (rasy, klasy, itemy, skille) żyją jako zasoby `.tres`, a stan postaci to lekkie referencje (ID) + wartości runtime serializowane do JSON.

Kanon (używany 1:1 w przykładach):
- **Rasy (6):** Duryjczycy, Sylvani, Karłowie z Grimholdu, Embrani, Orguni, Feruni.
- **Klasy (11):** Wojownik, Paladyn, Berserker, Łucznik, Łotrzyk, Zabójca, Mag, Nekromanta, Kapłan, Druid, Mnich.
- **Zasoby klas:** Furia, Mana, Focus (zależnie od klasy).

---

### 9.1. Zasady przewodnie

| # | Zasada | Konsekwencja implementacyjna |
|---|--------|------------------------------|
| 1 | **ID-references, nie wartości** dla wszystkiego, co ma definicję w `.tres` | Zapis jest mały, odporny na rebalans i pozwala podmienić balans bez migracji save'a |
| 2 | **Wartości tylko dla stanu runtime** (poziom, xp, pozycja, rolle losowanych statów) | To, czego nie da się odtworzyć z definicji, musi być zapisane wprost |
| 3 | **`schema_version` w każdym pliku/rekordzie** | Migracje deterministyczne v(N) -> v(N+1) |
| 4 | **Atomowy zapis** (temp + fsync + rename) | Brak uszkodzonych plików przy crashu/utracie zasilania |
| 5 | **Serwer = źródło prawdy w MMO** | Klient nigdy nie wysyła "mam 999 lvl"; wysyła intencje, serwer waliduje |
| 6 | **Rotacyjne backupy** | Każdy zapis tworzy kopię, trzymamy N ostatnich |
| 7 | **Idempotentny load** | Wczytanie tego samego pliku 2x daje identyczny stan |

---

### 9.2. Co zapisujemy jako ID-referencję, a co jako wartość

| Kategoria | Tryb zapisu | Uzasadnienie |
|-----------|-------------|--------------|
| Rasa (`race_id`), płeć, pochodzenie (`origin_id`) | ID / enum | Definicja w `RaceData.tres` |
| Klasa (`class_id`), specjalizacja | ID | Definicja w `ClassData.tres` |
| Tytuł (`title_id`) | ID | Lista tytułów w `TitleData.tres` |
| Imię, nazwisko | wartość (string) | Dane unikalne gracza |
| Wygląd (preset) | wartości liczbowe + ID części | Suwaki = wartości, fryzura/broda = ID assetu |
| Poziom, XP, punkty atrybutów/talentów | wartość | Stan progresji, nieodtwarzalny |
| Atrybuty bazowe alokowane | wartość | Decyzje gracza |
| Skille nauczone (`skill_id[]`), drzewko talentów | ID + ranga | Definicja skilla w `.tres`, ranga to wartość |
| Item w ekwipunku | `item_def_id` + `rolled_affixes` + `tier`/`ilvl` | Baza w `.tres`, losowe afiksy to wartości |
| Pozycja, biom, aktywne questy | wartość | Stan świata |
| Statystyki finalne (po pipeline base->flat->increased%->more) | **NIE zapisujemy** | Liczone przy ładowaniu z definicji + alokacji |

Zasada brzegowa: **wszystko, co potrafimy przeliczyć z definicji `.tres` + zapisanych wartości runtime, NIE trafia do save'a.** Statystyki finalne są zawsze rekonstruowane przez `StatPipeline` po wczytaniu.

---

### 9.3. Serializacja Resource <-> JSON

Stan postaci w pamięci to graf węzłów + komponentów (kompozycja), z danymi w zasobach `.tres`. Do persystencji NIE serializujemy całych zasobów `.tres` — serializujemy wyłącznie **stan zmienny** do JSON (czytelny, wersjonowalny, łatwy do migracji i eksportu).

Wzorzec: każdy komponent/agregat implementuje parę metod:

```gdscript
# Kontrakt serializacji — implementowany przez każdy serializowalny komponent.
class_name Serializable

# Zwraca słownik z prymitywami/ID (gotowy do JSON.stringify).
func to_dict() -> Dictionary:
    return {}

# Odtwarza stan ze słownika (po migracji do bieżącej schema_version).
func from_dict(data: Dictionary) -> void:
    pass
```

Reguły mapowania typów (Godot -> JSON):

| Typ Godot | Reprezentacja JSON | Uwaga |
|-----------|--------------------|-------|
| `int` / `float` / `bool` / `String` | natywnie | — |
| `Vector3` (pozycja) | `{"x":..,"y":..,"z":..}` lub `[x,y,z]` | Spójnie w całym projekcie — używamy obiektu |
| `Color` (wygląd) | `"#RRGGBBAA"` (hex) | Stabilne i czytelne |
| `Resource` (def itemu/klasy) | `String` ID | NIGDY nie zrzucamy ścieżki `res://` ani pól zasobu |
| `enum` (płeć, biom) | `int` lub stabilny `String`-klucz | Preferujemy string-klucz dla odporności na zmianę kolejności |
| tablica struktur | tablica obiektów | np. ekwipunek, afiksy |

Rozwiązywanie referencji przy ładowaniu odbywa się przez `DatabaseRegistry` (autoload): `DatabaseRegistry.get_item_def(item_def_id)` -> `ItemData`. Jeśli ID nie istnieje (np. usunięty content), stosujemy politykę fallbacku z sekcji 9.7.

---

### 9.4. Wersjonowanie i migracje

Każdy zapis ma `meta.schema_version: int`. Bieżąca wersja jest stałą w kodzie: `SaveSystem.CURRENT_SCHEMA_VERSION`. Przy ładowaniu, jeśli `file.schema_version < CURRENT`, uruchamiamy łańcuch migracji **deterministycznie, krok po kroku** (v1->v2->v3...), nigdy "na skróty".

Rejestr migracji to mapa `int -> Callable`, gdzie funkcja migruje słownik z wersji N do N+1:

```gdscript
# autoload: SaveMigrations.gd
class_name SaveMigrations

# Rejestr: klucz = wersja źródłowa, wartość = funkcja migrująca v(key) -> v(key+1).
static var REGISTRY: Dictionary = {
    1: _migrate_1_to_2,
    2: _migrate_2_to_3,
}

# Główny punkt wejścia: podnosi dowolny stary słownik do CURRENT_SCHEMA_VERSION.
static func migrate(data: Dictionary, current_version: int) -> Dictionary:
    var v: int = int(data.get("meta", {}).get("schema_version", 1))
    while v < current_version:
        assert(REGISTRY.has(v), "Brak migracji dla wersji %d" % v)
        data = REGISTRY[v].call(data)
        data["meta"]["schema_version"] = v + 1
        v += 1
    return data

# PRZYKŁAD: v1 -> v2 — dodanie nowego pola wyglądu "scar_style" z wartością domyślną.
static func _migrate_1_to_2(data: Dictionary) -> Dictionary:
    var app: Dictionary = data.get("appearance", {})
    if not app.has("scar_style"):
        app["scar_style"] = "none"     # domyślna wartość dla starych postaci
    data["appearance"] = app
    return data

# PRZYKŁAD: v2 -> v3 — rozbicie pola "name" na "first_name" + "last_name".
static func _migrate_2_to_3(data: Dictionary) -> Dictionary:
    var ident: Dictionary = data.get("identity", {})
    if ident.has("name") and not ident.has("first_name"):
        var parts: PackedStringArray = String(ident["name"]).split(" ", false, 1)
        ident["first_name"] = parts[0] if parts.size() > 0 else ""
        ident["last_name"] = parts[1] if parts.size() > 1 else ""
        ident.erase("name")
    data["identity"] = ident
    return data
```

Zasady migracji:
- Migracja jest **czysta** (bez efektów ubocznych poza zwróconym słownikiem) i **idempotentna** (sprawdza `has()` przed dopisaniem).
- Nowe pola **zawsze** mają wartość domyślną — żadna stara postać nie może po migracji wpaść w `null`.
- Po udanej migracji i przed nadpisaniem pliku tworzymy backup wersji sprzed migracji (`*.pre-v{N}.bak`).
- Migracje są pokryte testami jednostkowymi: dla każdej pary (vN -> vN+1) test bierze przykładowy fixture vN i asercją sprawdza pola vN+1.

---

### 9.5. Przykładowy plik JSON zapisanej postaci

Lokalizacja (lokalnie): `user://saves/{slot_id}/character.json`. Pełny przykład postaci (Embranka, Mag):

```json
{
  "meta": {
    "schema_version": 3,
    "save_id": "5b1c9e2a-7f4d-4a91-9c33-0a2e8d6f1b77",
    "game_build": "0.4.7",
    "created_at": "2026-06-21T10:14:02Z",
    "updated_at": "2026-06-21T11:58:40Z",
    "play_time_seconds": 51240,
    "checksum": "sha256:9f2b...e7"
  },
  "identity": {
    "race_id": "embrani",
    "gender": "female",
    "origin_id": "emberwaste_exile",
    "class_id": "mag",
    "first_name": "Ysera",
    "last_name": "Cynderfall",
    "title_id": "title_emberborn"
  },
  "appearance": {
    "preset_version": 2,
    "body_type": 1,
    "height_cm": 171,
    "skin_tone": "#C9743Aff",
    "face_id": "face_embrani_07",
    "hair_id": "hair_long_braided",
    "hair_color": "#1A0E0Eff",
    "beard_id": "none",
    "eye_color": "#FF7A1Eff",
    "ember_glow_intensity": 0.72,
    "tattoo_id": "tattoo_ember_runes_02",
    "tattoo_color": "#FFB347ff",
    "scar_style": "none",
    "voice_id": "voice_f_03"
  },
  "progression": {
    "level": 47,
    "xp_current": 184320,
    "xp_to_next": 251000,
    "unspent_attribute_points": 3,
    "unspent_talent_points": 1,
    "attributes": {
      "strength": 14,
      "dexterity": 22,
      "intellect": 88,
      "vitality": 40,
      "spirit": 55
    },
    "resource": {
      "type": "mana",
      "max": 1240,
      "current": 1240
    },
    "talents": [
      { "talent_id": "mag_pyromancy_t1_ember_bolt", "rank": 3 },
      { "talent_id": "mag_pyromancy_t2_combustion", "rank": 1 }
    ],
    "learned_skills": ["mag_fireball", "mag_blink", "mag_meteor", "mag_mana_shield"]
  },
  "equipment": {
    "main_hand": {
      "item_def_id": "staff_emberheart",
      "ilvl": 52,
      "rarity": "epic",
      "rolled_affixes": [
        { "affix_id": "increased_fire_damage_pct", "value": 34 },
        { "affix_id": "added_intellect", "value": 27 }
      ],
      "sockets": [{ "gem_def_id": "gem_ruby_t3" }, { "gem_def_id": null }]
    },
    "head": { "item_def_id": "hood_of_cinders", "ilvl": 49, "rarity": "rare", "rolled_affixes": [] },
    "chest": null,
    "off_hand": null
  },
  "inventory": {
    "gold": 18420,
    "slots": [
      { "slot": 0, "item_def_id": "potion_health_major", "stack": 12 },
      { "slot": 1, "item_def_id": "rune_of_focus", "stack": 3 }
    ]
  },
  "world_state": {
    "current_biome": "emberwaste",
    "position": { "x": 1284.5, "y": 62.0, "z": -903.2 },
    "facing_yaw": 1.92,
    "active_quests": ["q_emberwaste_main_03"],
    "completed_quests": ["q_intro_01", "q_verdant_01"],
    "bound_respawn": { "biome": "emberwaste", "anchor_id": "ashpoint_camp" }
  }
}
```

Uwagi do przykładu:
- `equipment.*.rolled_affixes` to **wartości** (losowane przy dropie), bo nie da się ich odtworzyć z definicji — `item_def_id` daje resztę (model, baza statów, ikonę).
- `progression.resource.type` = "mana" wynika z `class_id`=`mag`; trzymamy redundantnie dla szybkiego odczytu, ale prawda jest w definicji klasy.
- Statystyki finalne (DPS, finalny intellect po `more`-mnożnikach) **nie istnieją** w pliku — liczy je `StatPipeline` przy wczytaniu.

---

### 9.6. Schemat bazy danych (wariant serwerowy MMO)

Dla serwera autorytatywnego stan jest znormalizowany w relacyjnej DB (PostgreSQL). Definicje contentu (rasy, klasy, item defs) NIE są w tych tabelach — żyją w katalogu contentu serwera; tabele trzymają wyłącznie referencje (ID) + wartości runtime, dokładnie jak JSON.

```sql
-- ============ KONTO / SESJA ============
CREATE TABLE account (
    account_id      BIGSERIAL PRIMARY KEY,
    email           TEXT UNIQUE NOT NULL,
    password_hash   TEXT NOT NULL,         -- argon2id
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    banned          BOOLEAN NOT NULL DEFAULT false
);

-- ============ POSTAĆ (tożsamość + progresja) ============
CREATE TABLE character (
    character_id    BIGSERIAL PRIMARY KEY,
    account_id      BIGINT NOT NULL REFERENCES account(account_id),
    schema_version  INT NOT NULL DEFAULT 3,
    -- tożsamość (ID-referencje + wartości)
    race_id         TEXT NOT NULL,          -- 'embrani', 'sylvani', ...
    gender          TEXT NOT NULL,          -- 'female' | 'male' | 'neutral'
    origin_id       TEXT NOT NULL,
    class_id        TEXT NOT NULL,          -- 'mag', 'wojownik', ...
    first_name      TEXT NOT NULL,
    last_name       TEXT NOT NULL,
    title_id        TEXT,
    -- progresja
    level           INT  NOT NULL DEFAULT 1  CHECK (level BETWEEN 1 AND 99),
    xp_current      BIGINT NOT NULL DEFAULT 0,
    unspent_attr_points    INT NOT NULL DEFAULT 0,
    unspent_talent_points  INT NOT NULL DEFAULT 0,
    -- zasób klasowy (typ wynika z class_id, current przechowywany do respawnu)
    resource_type   TEXT NOT NULL,          -- 'furia' | 'mana' | 'focus'
    resource_current INT NOT NULL DEFAULT 0,
    -- stan świata
    current_biome   TEXT NOT NULL DEFAULT 'verdant_hollow',
    pos_x DOUBLE PRECISION NOT NULL DEFAULT 0,
    pos_y DOUBLE PRECISION NOT NULL DEFAULT 0,
    pos_z DOUBLE PRECISION NOT NULL DEFAULT 0,
    facing_yaw DOUBLE PRECISION NOT NULL DEFAULT 0,
    play_time_seconds BIGINT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ,            -- soft-delete
    UNIQUE (first_name, last_name)          -- unikalność nazwy postaci na shardzie
);
CREATE INDEX idx_character_account ON character(account_id) WHERE deleted_at IS NULL;

-- ============ WYGLĄD (1:1 z postacią) ============
CREATE TABLE character_appearance (
    character_id    BIGINT PRIMARY KEY REFERENCES character(character_id) ON DELETE CASCADE,
    preset_version  INT NOT NULL DEFAULT 2,
    body_type       SMALLINT NOT NULL,
    height_cm       SMALLINT NOT NULL,
    skin_tone       TEXT NOT NULL,          -- '#RRGGBBAA'
    face_id         TEXT NOT NULL,
    hair_id         TEXT NOT NULL,
    hair_color      TEXT NOT NULL,
    beard_id        TEXT NOT NULL DEFAULT 'none',
    eye_color       TEXT NOT NULL,
    tattoo_id       TEXT NOT NULL DEFAULT 'none',
    tattoo_color    TEXT,
    scar_style      TEXT NOT NULL DEFAULT 'none',   -- pole dodane w migracji v1->v2
    voice_id        TEXT NOT NULL,
    extra           JSONB NOT NULL DEFAULT '{}'     -- pola rasowo-specyficzne, np. ember_glow_intensity
);

-- ============ ATRYBUTY (alokacja gracza) ============
CREATE TABLE character_attribute (
    character_id  BIGINT NOT NULL REFERENCES character(character_id) ON DELETE CASCADE,
    attr_id       TEXT NOT NULL,            -- 'strength','dexterity','intellect','vitality','spirit'
    value         INT  NOT NULL DEFAULT 0,
    PRIMARY KEY (character_id, attr_id)
);

-- ============ TALENTY / SKILLE ============
CREATE TABLE character_talent (
    character_id  BIGINT NOT NULL REFERENCES character(character_id) ON DELETE CASCADE,
    talent_id     TEXT NOT NULL,
    rank          SMALLINT NOT NULL DEFAULT 1,
    PRIMARY KEY (character_id, talent_id)
);
CREATE TABLE character_skill (
    character_id  BIGINT NOT NULL REFERENCES character(character_id) ON DELETE CASCADE,
    skill_id      TEXT NOT NULL,
    learned_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (character_id, skill_id)
);

-- ============ ITEMY (instancje) ============
-- Każdy przedmiot to INSTANCJA: def_id (referencja) + wartości losowane.
CREATE TABLE item_instance (
    item_id       BIGSERIAL PRIMARY KEY,
    owner_char_id BIGINT REFERENCES character(character_id) ON DELETE CASCADE,
    item_def_id   TEXT NOT NULL,           -- referencja do contentu serwera
    ilvl          INT NOT NULL,
    rarity        TEXT NOT NULL,           -- 'common'..'legendary'
    rolled_affixes JSONB NOT NULL DEFAULT '[]', -- [{affix_id,value},...]
    sockets        JSONB NOT NULL DEFAULT '[]',
    stack          INT NOT NULL DEFAULT 1,
    bound          BOOLEAN NOT NULL DEFAULT false,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_item_owner ON item_instance(owner_char_id);

-- ============ EKWIPUNEK (założone sloty) ============
CREATE TABLE character_equipment (
    character_id  BIGINT NOT NULL REFERENCES character(character_id) ON DELETE CASCADE,
    slot          TEXT NOT NULL,           -- 'main_hand','off_hand','head','chest',...
    item_id       BIGINT REFERENCES item_instance(item_id) ON DELETE SET NULL,
    PRIMARY KEY (character_id, slot)
);

-- ============ EKWIPUNEK PLECAKA (referencje do instancji) ============
CREATE TABLE character_inventory (
    character_id  BIGINT NOT NULL REFERENCES character(character_id) ON DELETE CASCADE,
    slot_index    INT NOT NULL,
    item_id       BIGINT NOT NULL REFERENCES item_instance(item_id) ON DELETE CASCADE,
    PRIMARY KEY (character_id, slot_index)
);

-- ============ WALUTA ============
CREATE TABLE character_currency (
    character_id  BIGINT PRIMARY KEY REFERENCES character(character_id) ON DELETE CASCADE,
    gold          BIGINT NOT NULL DEFAULT 0 CHECK (gold >= 0)
);

-- ============ QUESTY ============
CREATE TABLE character_quest (
    character_id  BIGINT NOT NULL REFERENCES character(character_id) ON DELETE CASCADE,
    quest_id      TEXT NOT NULL,
    state         TEXT NOT NULL,           -- 'active' | 'completed'
    progress      JSONB NOT NULL DEFAULT '{}',
    PRIMARY KEY (character_id, quest_id)
);

-- ============ AUDYT / ANTY-CHEAT ============
CREATE TABLE character_audit (
    audit_id      BIGSERIAL PRIMARY KEY,
    character_id  BIGINT NOT NULL REFERENCES character(character_id),
    event_type    TEXT NOT NULL,           -- 'level_up','item_gain','gold_delta','login'
    payload       JSONB NOT NULL,
    server_ts     TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Mapowanie JSON <-> DB jest 1:1 na poziomie pojęć: sekcje JSON (`identity`, `appearance`, `progression`, `equipment`, `inventory`, `world_state`) odpowiadają tabelom; tablice (`learned_skills`, `talents`, `slots`) to tabele wiele-do-jednego. To pozwala dzielić tę samą warstwę serializacji między klientem (eksport JSON) a serwerem (zapis do DB).

---

### 9.7. Polityka fallbacku dla brakujących referencji

Gdy przy ładowaniu ID nie istnieje w `DatabaseRegistry` (usunięty/zmieniony content):

| Przypadek | Akcja |
|-----------|-------|
| `race_id` / `class_id` brak | BLOKADA ładowania, komunikat błędu (postać niegrywalna) — to twardy błąd contentu |
| `item_def_id` brak | Item przenoszony do "lost & found" (placeholder), log + ostrzeżenie; nie zawiesza save'a |
| `skill_id` / `talent_id` brak | Pomijany; punkty zwracane do puli `unspent_*` |
| `hair_id` / `tattoo_id` itp. brak | Fallback do wartości domyślnej presetu (np. `"none"`) |

---

### 9.8. Strategia zapisu: single-player vs serwer autorytatywny

#### 9.8.1. Lokalny (single-player / lokalny co-op host)

- **Źródło prawdy:** plik `user://saves/{slot}/character.json` na maszynie gracza.
- **Triggery zapisu:** autosave co 120 s, przy istotnych zdarzeniach (level-up, zmiana ekwipunku, ukończenie questa), przy wyjściu z gry, przy ręcznym zapisie.
- **Co-op lokalny:** host trzyma pliki wszystkich graczy w sesji; goście są symulowani na maszynie hosta (host-authoritative combat z rozdz. o sieci), więc ich postacie zapisuje host i synchronizuje eksport do plików gości po sesji.
- **Zaufanie:** w SP nie ma anty-cheatu — plik jest edytowalny przez gracza i to akceptujemy.

#### 9.8.2. Serwer autorytatywny (MMO)

- **Źródło prawdy:** baza danych serwera. Klient NIGDY nie przysyła stanu — przysyła **intencje** (ruszam się, używam skilla na punkt celownika, podnoszę loot). Serwer waliduje i to on decyduje o wyniku.
- **Anty-cheat (serwer = prawda):**
  - Walidacja każdej zmiany: przyrost XP/gold/itemów liczony i autoryzowany wyłącznie po stronie serwera; klient nie może "ogłosić" poziomu ani dropu.
  - Sanity-checki: prędkość ruchu, cooldowny, zasięg skilla (raycast celownika weryfikowany na serwerze), pojemność ekwipunku.
  - Tabela `character_audit` loguje wszystkie krytyczne delty (level_up, item_gain, gold_delta) do detekcji anomalii.
  - Itemy to **instancje z `item_id`** (nie kopiowalne stringi) — eliminuje duplikację itemów przez replay pakietów.
- **Persystencja:** stan w RAM serwera (hot), flush do DB co 60–120 s i przy ważnych zdarzeniach (handel, level-up, logout). Transakcje DB gwarantują spójność (np. handel = jedna transakcja przenosząca `owner_char_id`).
- **Logout/crash:** ostatni flush + dziennik zdarzeń (event sourcing krytycznych akcji) pozwala odtworzyć stan po awarii do ostatniej transakcji.

---

### 9.9. Atomowy zapis i kopie zapasowe (lokalnie)

Każdy zapis lokalny musi być atomowy, by crash w trakcie zapisu nie uszkodził save'a:

```gdscript
# SaveSystem.gd — atomowy zapis z rotacją backupów.
const CURRENT_SCHEMA_VERSION := 3
const MAX_BACKUPS := 5

func save_character(slot: String, data: Dictionary) -> Error:
    data["meta"]["schema_version"] = CURRENT_SCHEMA_VERSION
    data["meta"]["updated_at"] = Time.get_datetime_string_from_system(true)

    var dir := "user://saves/%s" % slot
    DirAccess.make_dir_recursive_absolute(dir)
    var final_path := "%s/character.json" % dir
    var tmp_path   := "%s/character.json.tmp" % dir

    # 1) Serializacja + suma kontrolna integralności.
    var json := JSON.stringify(data, "  ")
    data["meta"]["checksum"] = "sha256:" + _sha256(json)
    json = JSON.stringify(data, "  ")

    # 2) Zapis do pliku tymczasowego + flush na dysk.
    var f := FileAccess.open(tmp_path, FileAccess.WRITE)
    if f == null:
        return FileAccess.get_open_error()
    f.store_string(json)
    f.flush()                       # wymuszenie zrzutu bufora
    f.close()

    # 3) Rotacja backupu istniejącego pliku PRZED nadpisaniem.
    if FileAccess.file_exists(final_path):
        _rotate_backups(dir)        # character.json -> character.bak.1, .1 -> .2, ...

    # 4) Atomowy rename (zamiana tmp -> final).
    var err := DirAccess.rename_absolute(tmp_path, final_path)
    return err

func _rotate_backups(dir: String) -> void:
    var da := DirAccess.open(dir)
    for i in range(MAX_BACKUPS - 1, 0, -1):
        var src := "%s/character.bak.%d" % [dir, i]
        var dst := "%s/character.bak.%d" % [dir, i + 1]
        if da.file_exists(src):
            da.rename(src, dst)
    da.rename("character.json", "character.bak.1")
```

Reguły:
- **Nigdy** nie nadpisujemy pliku finalnego in-place; zawsze temp -> rename (rename jest atomowy na poziomie systemu plików).
- `flush()` przed rename — gwarancja, że dane są na dysku, nie tylko w buforze.
- Backup rotacyjny: trzymamy `MAX_BACKUPS` ostatnich (`character.bak.1` = najnowszy). Przy uszkodzeniu `character.json` (zła suma kontrolna) loader automatycznie próbuje `bak.1`, potem `bak.2`, ...
- `checksum` (SHA-256 treści) weryfikowany przy ładowaniu — wykrycie korupcji pliku.
- Po stronie serwera odpowiednikiem atomowości są **transakcje DB**; backupy to standardowy harmonogram dumpów PostgreSQL + WAL/PITR.

---

### 9.10. Pełna ścieżka ładowania (load pipeline)

1. Wczytaj surowy JSON (lub w razie złej sumy kontrolnej — kolejny backup).
2. Zweryfikuj `checksum`.
3. Odczytaj `meta.schema_version`; jeśli `< CURRENT` -> `SaveMigrations.migrate()` (z backupem pre-migracyjnym).
4. Rozwiąż referencje przez `DatabaseRegistry` (z polityką fallbacku 9.7).
5. Zbuduj graf postaci (komponenty `from_dict`).
6. Przelicz statystyki finalne przez `StatPipeline` (base->flat->increased%->more).
7. Postać gotowa; finalne staty nigdy nie pochodziły z pliku.

Ta sama warstwa `to_dict/from_dict` zasila trzy ścieżki: lokalny save JSON, eksport postaci (np. transfer/backup na chmurę gracza) oraz mapowanie do tabel DB na serwerze — jedno źródło prawdy serializacji, zero rozjazdu między trybami.


---

