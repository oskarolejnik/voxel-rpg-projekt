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
