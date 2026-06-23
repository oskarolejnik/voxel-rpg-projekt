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
