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
