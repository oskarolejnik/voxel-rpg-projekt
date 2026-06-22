# Game Design Document — Voxel RPG (nazwa robocza)

> Dokument projektowy v2. Oryginalna voxelowa gra action-RPG (power-fantasy hack'n'slash),
> co-op do 4 graczy we wspolnym swiecie ze znajomymi. Cube World byl inspiracja gatunkowa —
> tu zapisujemy WLASNE decyzje. Stack: Godot 4.7 + GDScript. Single-player-first, ale
> architektura network-aware od poczatku.
>
> Powiazane: `TDD.md` (architektura/dane/netcode), `ROADMAP.md` (etapy + plan kodu).
> Stan kodu (zweryfikowany): chunkowy swiat voxelowy (watkowy streaming + LOD + mgla,
> deterministyczna generacja z `feature_hash` + `FastNoiseLite`), cykl dnia/nocy, szkielet
> walki (`src/Player.gd`), wrog + AI (`src/Enemy.gd`), HUD (`src/HUD.gd`), parametryczna
> postac voxelowa z animacja proceduralna.

---

## 1. Wizja i pitch

Voxelowy action-RPG, w ktorym **kosisz hordy wrogow z poczuciem rosnacej mocy**, zbierasz
gleboki loot i schodzisz w proceduralne dungeony. Grasz solo lub we **wspolnym swiecie z
maks. 3 znajomymi** (listen-server). Glowne zrodlo mocy to **loot** (styl Minecraft Dungeons,
ale z wieksza glebia build-craftingu); drzewko umiejetnosci jest skromne i sluzy wyborom, nie
grindowi.

**Jedno zdanie:** *Biegasz po szesciennym swiecie, kosisz hordy w dynamicznej walce
power-fantasy, polujesz na loot z afiksami/setami/socketami i schodzisz w instancjonowane
dungeony — sam albo z paczka do 4 graczy.*

## 2. Filary projektowe (czego bronimy przed scope creep)

1. **Power-fantasy, nie souls-like.** Gracz ma czuc sie potezny: kosi trash jednym ciosem,
   walczy z elitami, czyta grozbe hordy i ja rozbija. Wyzwanie z liczby wrogow i pozycjonowania,
   nie z punitywnego timingu.
2. **Loot to glowna progresja.** Moc rosnie glownie ze sprzetu (tiery, sety, enchanty, sockety,
   losowane afiksy). „Zeby bylo co robic” — umiarkowana glebia, czytelne pule.
3. **Trwaly wzrost.** Gracz NIGDY nie traci zdobytej mocy (lekcja z Cube World 1.0). Poziomy do
   99 sa stale; respec drzewka jest mozliwy za walute, ale to przebudowa, nie utrata.
4. **Network-aware od dnia 1.** Kazda decyzja systemowa dziala w SP i skaluje sie do co-opu 4
   bez przepisywania (autorytet hosta, predykcja klienta, swiat generowany lokalnie z seeda).
5. **Czytelnosc voxelowa.** Spojny, czysty styl blokow — produkowalny solo, czytelny w chaosie hordy.

## 3. Petla rozgrywki (core loop)

```
Eksploruj biom  ->  Kos hordy / walcz z elitami  ->  Loot + XP + waluta
        ^                          |                        |
        |                          v                        v
        |              Wejdz w dungeon (instancja)   Ulepsz: ekwipunek,
        |                          |                  klejnoty, enchanty,
        +---- glebszy biom/tier <--+-- boss -> top loot   drzewko, pet <-+
```

Petla krotka (jedna walka -> drop -> wpiecie statu) i petla dluga (biom/dungeon-tier -> set/legenda
-> nowy build). Dungeony to pierwsza powtarzalna farma; bossowie biomow to drugi filar farmy.

---

## 4. Klasy, sciezki, zasoby

Jedna postac main (decyzja: jeden bohater, nie roster). Klasa wybierana w kreatorze, do max
lvl 99. Trzy klasy, kazda z 3 sciezkami (podklasami). **Zasoby klas sa asymetryczne** — inny
„rytm” zarzadzania moca:

| Klasa | Zasob | Regula zasobu |
|---|---|---|
| **Mag** | **Mana** | pula bazowa ~100, regen ~5/s (skaluje z lootem). Skille kosztuja mane. |
| **Wojownik** | **Furia (0–100)** | +6 za trafienie wrecz, +4 za otrzymany cios, zanik 5/s po 3 s bez walki. Finishery konsumuja Furie. |
| **Ranger** | **Combo (0–5) + Focus** | buildery daja +1 Combo (max 5); finishery wydaja Combo. Focus = wolniej regenerujacy zasob na uniki/mobilnosc. |

### 4.1 Mag (Mana)

- **Piromanta** — `Ogien`/`AoE`/`Strefa`. Pocisk Zaru (builder, DoT), Eksplozja Plomieni
  (+50% vs podpalonych), Morze Ognia (strefa DoT). Pasywy: Katalizator (DoT tyka +25% szybciej),
  Wewnetrzny Zar (+20% increased `Ogien`, przy >50% many +10% more).
  **Keystone (lvl 25): Spalanie** — DoT `Ogien` moga krytowac, ale -15% bazowej many.
  **Capstone (lvl 60): Nova Supernowej** — Eksplozja Plomieni dodaje tag `Strefa` i wybucha 2x.
- **Kriomanta** — `Mroz`/`Kontrola`/`Pocisk`. Lodowa Wlocznia (przebija, slow), Nova Mrozu
  (root AoE), Zbroja Lodu (bariera + slow atakujacych). Pasywy: Krucha Skora (+15% dmg na
  spowolnionych), Zimna Krew (+25% increased `Mroz`, krytyk na zamrozonych +50% mnoznik).
  **Keystone: Zero Absolutne** — zamrozenie blokuje regen wroga; -20% szybkosci rzucania.
  **Capstone: Wieczna Zima** — Nova Mrozu zostawia strefe mrozu na 4 s.
- **Burzomistrz** — `Blyskawica`/`Kanal`/`Krytyk`. Luk Burzy (kanal, lancuch 3 cele), Grom
  (+100% kryt vs samotny cel), Naladowanie (+30% szybkosci rzucania, +1 cel lancucha). Pasywy:
  Przewodnik (`Blyskawica` ignoruje 20% odpornosci), Statyka (+5% kryt; kryt = +1 cel lancucha).
  **Keystone: Niestabilnosc** — +50% kryt, ale krytyk w zwarciu rani Cie o 5% HP.
  **Capstone: Gniew Niebios** — co 4. krytyk wywoluje darmowy Grom.

### 4.2 Wojownik (Furia) — klasa STARTOWA vertical slice

- **Berserker** — `Fizyczne`/`Wrecz`/`Obrazenia`. **Domyslna sciezka prototypu** (rozpis nizej).
  Wir Ostrzy (AoE 360°), Szal Krwi (+40% predkosci ataku, lifesteal), Roztrzaskanie (stun +
  armor pierce). Pasywy: Furia Bitwy (+25% generacji Furii), Krwiozerczosc (<50% HP +20%
  increased `Fizyczne`).
  **Keystone: Bez Opamietania** — +25% more `Fizyczne`, -15% obrony.
  **Capstone: Niepowstrzymany** — Wir Ostrzy podczas Szalu Krwi nie kosztuje Furii.
- **Straznik** — `Obrona`/`Kontrola`/`Aura`. Tarcza Wyzwania (taunt + bariera), Mur (-40%
  obrazen, brak knockback), Uderzenie Tarcza (knockback + stun). Pasywy: Twarda Skora (+15%
  bazowej obrony), Aura Opoki (sojusznicy -10% obrazen — co-op).
  **Keystone: Niezlomny** — nie mozesz dostac krytyka, ale -10% zadawanych obrazen.
  **Capstone: Ostatni Bastion** — przy 0 HP raz/60 s: bariera + taunt zamiast smierci.
- **Pogromca** — `Fizyczne`/`Krytyk`/`Ruch` (bron 2H). Skok Burzacy (gap-closer + stun),
  Egzekucja (+200% vs <25% HP), Tornado Ciec. Pasywy: Impet (po `Ruch` +20% dmg), Lowca Slabych
  (+15% kryt vs <50% HP).
  **Keystone: Krew za Krew** — +30% kryt, ale +10% otrzymywanych obrazen.
  **Capstone: Zniwiarz** — zabojstwo Egzekucja resetuje jej CD i daje +50 Furii.

### 4.3 Ranger (Combo + Focus)

- **Lucznik** — `Pocisk`/`Fizyczne`/`Krytyk`. Strzal Celny (builder, kryt = +1 Combo), Salwa
  (wachlarz 5 strzal), Strzal Przebijajacy (dmg skaluje z wydanym Combo). Pasywy: Oko Sokola
  (+10% kryt z `Pocisk`), Plynnosc (kryt zwraca 8 Focus).
  **Keystone: Snajper** — +40% dmg do celow >10 m, -20% do bliskich.
  **Capstone: Deszcz Strzal** — Salwa za 5 Combo wywoluje druga salwe.
- **Lowca Bestii** — `Pet`/`Trucizna`/`Pulapka`. Pchniecie Wlocznia (builder wrecz), Sidla
  (root 2 s), Rozkaz: Szarza (pet skacze, `Trucizna` DoT). Pasywy: Wiez (pet +30% HP/dmg),
  Toksyny (DoT `Trucizna` +25%, 2 stacki).
  **Keystone: Alfa** — drugi (mniejszy) pet, ale -20% dmg gracza.
  **Capstone: Pan Bestii** — Rozkaz: Szarza oswaja elite na 15 s (nie-bossa).
- **Cien** — `Mrok`/`Ruch`/`Krytyk`. Rzut Sztyletem (cichy builder), Mgla Cienia (blink +
  niewidzialnosc, nastepny atak +100% kryt dmg), Wachlarz Ostrzy. Pasywy: Zabojca (atak z
  niewidzialnosci = gwarantowany kryt), Zwinnosc (uniki bez kosztu Focus <3 Combo).
  **Keystone: Egzekutor Cienia** — +35% kryt mnoznik, ale -15% maks HP.
  **Capstone: Taniec Smierci** — zabojstwo skraca CD Mgly Cienia o 2 s i daje +1 Combo.

### 4.4 System TAGOW (rdzen synergii loot<->skill)

Kazdy skill ma zestaw **tagow**. Loot i pasywy modyfikuja skille przez **dopasowanie tagow**
(nie nazwy skilla), wiec afiks „+15% increased `Ogien`” wzmacnia KAZDY skill z tagiem `Ogien`,
niezaleznie od klasy. Tagi to jedyny slownik laczacy sekcje skilli, walki i itemizacji.

- **Typ obrazen:** `Fizyczne`, `Ogien`, `Mroz`, `Blyskawica`, `Trucizna`, `Mrok`
- **Dostarczanie:** `Pocisk`, `Wrecz`, `AoE`, `Strefa`, `Kanal`, `Aura`, `Totem/Pulapka`
- **Rola:** `Obrazenia`, `Leczenie`, `Buff`, `Debuff`, `Kontrola`, `Ruch`, `Obrona`
- **Skalowanie:** `Atak` (skaluje z bronia), `Czar` (skaluje z moca zaklec), `DoT`, `Krytyk`

> Tagi w GDScript to `StringName` (np. `&"fire"`, `&"melee"`, `&"aoe"`). Slownik PL<->kod i pelny
> pipeline modyfikatorow — patrz `TDD.md` paragraf „Stat / modifier pipeline”.

### 4.5 Augmenty skilli (sockety umiejetnosci)

Kazdy skill ma **0–3 gniazda na augmenty** (loot). Augment modyfikuje TEN skill (np. „Pocisk
rozszczepia +2”, „dodaje tag `Strefa`: zostawia kaluze”). Augmenty aplikuja sie PRZED
pipeline'em obrazen (moga dodac tag/efekt). To odrebny system od socketow na ekwipunku (paragraf 6.5).

---

## 5. Walka (feel)

Walka jest **power-fantasy**: szerokie ciecia, kosisz trash, czytasz telegrafy hordy i ja
rozbijasz. Bazuje na dzialajacym rdzeniu w `Player.gd` (atak LMB promien+luk, unik z i-frames,
combo->przebicie pancerza, knockback, hitstop) — projekt to rozszerza w przestrzen ciagla.

### 5.1 Hitboxy w przestrzeni ciaglej

Obecna petla `dot()` po grupie `enemies` zostaje zastapiona **Area3D + okno czasowe + lista
trafionych** (anti-multihit). Cztery typy ataku:

- **Melee swept** — Area3D (dysk/box) aktywny tylko w „active frames” ataku; szeroki zbior
  kandydatow docinany filtrem `dot()` (zachowujemy `attack_arc_dot`). Sub-stepping tylko dla
  waskich „pchniec”.
- **AoE puls** — Area3D wlaczony na 1 klatke (nova maga, wir 2H), `get_overlapping_bodies()`.
- **Pocisk balistyczny** — wlasny ruch + ciagly raycast (CCD anti-tunnel); `gravity_scale`
  steruje opadaniem (strzala Rangera, belt ognia maga).
- **Strefa (HazardZone)** — trwaly Area3D tykajacy co interwal (kaluza ognia, lod, totem,
  telegraf wroga). Strefy gracza domyslnie NIE rania graczy w co-opie (friendly-fire off).

Warstwy walki rozszerzaja istniejace bity (teren=1, gracz=2, wrog=3) o osobne warstwy hitboxow
(player_hitbox, enemy_hitbox, enemy_hurtbox, projectile, interactable) — szczegoly w `TDD.md`.

### 5.2 Unik, i-frames, juice

- Dash z i-frames (istnieje): koszt 25 staminy, dash 16 m/s 0,22 s, i-frames 0,30 s, CD 0,55 s.
- **Perfect-dodge** (okno ~0,12 s na poczatku uniku): krotki lokalny bullet-time + premia
  (np. +50% dmg na 2 s lub zwrot czesci staminy).
- **Buforowanie inputu** ataku/uniku (~0,15 s) — plynne combo (jak istniejacy bufor skoku).
- **Cancel ataku w unik** dozwolony tylko w fazie recovery (po active frames) — i-frames nie
  „za darmo”.
- **Hitstop, shake, flash, knockback, damage numbers** — istnieja/rozszerzane; w co-opie
  hitstop jest LOKALNY (nigdy globalny `Engine.time_scale` — patrz `TDD.md` paragraf netcode).

### 5.3 Pipeline trafienia (on-hit)

Cala logika trafienia idzie przez `DamageService` (jedno miejsce, host-authoritative). Kontener
`HitData` niesie: zrodlo, base_damage, typ obrazen (tag), crit_chance/crit_mult, armor_pierce,
lifesteal, knockback, on_hit_effects (statusy z afiksow/setow), pozycje trafienia. Kolejnosc:
roll krytyka -> pancerz po przebiciu -> odpornosci typu -> `take_damage` -> lifesteal/statusy/proki
-> FX zwrotne. Krytyki, lifesteal i on-hit sa glownymi nosnikami „rosnacej mocy” z lootu.

### 5.4 Telegrafy wrogow (czytelnosc hordy)

Trzy poziomy wg grozonosci: **Trash** (poza windupu + blysk broni — tanie, bo 20 na ekranie),
**Elite** (+ naziemny decal ksztaltu hitboxa przez HazardZone w trybie „preview”), **Boss**
(+ dzwiek + dluzszy windup + faza wymuszajaca unik/repozycje). Regula: kolor telegrafu jednolity
(narastajaca czerwien), windup >= czas reakcji (>=0,4 s dla groznych); duzy dmg nigdy „instant”.

### 5.5 Archetypy broni (liczby bazowe, vertical slice)

Typ broni nadpisuje 4 istniejace eksporty (`attack_damage`/`attack_cooldown`/`attack_range`/
`attack_arc_dot`); afiksy je modyfikuja. Obecny uniwersalny default (dmg 18 / CD 0,45 / range
2,2 / dot 0,3) rozklada sie na archetypy:

| Bron | dmg | cooldown | range | dot (luk) |
|---|---|---|---|---|
| 1H + tarcza | 14 | 0.38 | 1.9 | 0.55 |
| 2H (topor/kostur) | 30 | 0.70 | 2.6 | 0.0 (180°) |
| Dual / sztylety (per cios) | 11 | 0.26 | 2.0 | 0.40 |
| Luk | 22 | 0.55 | CCD/pocisk | — |
| Rozdzka (belt) | 18 | 0.50 | pocisk | — |

Krytyk bazowy gracza: 5% szans, x1,5 mnoznik. Combo: zachowane `armor_pierce_per_combo=0.15`
(max 0,8), `combo_window=1.2`; dodatkowo +5% dmg/stopien (max +25%) — odczuwalne narastanie.

---

## 6. Itemizacja (loot)

Loot to glowna progresja. Styl MC-Dungeons-light + wieksza glebia: **tiery rzadkosci + losowane
afiksy + sety + enchanty + sockety**. Cala moc itemu wplywa na postac przez `StatModifier`-y
zbierane w jednym miejscu (patrz `TDD.md`); item to czyste dane (seed + tier + ilvl), wiec w
co-opie host wysyla tylko rolle, a klient odtwarza staty deterministycznie.

### 6.1 Statystyki rdzeniowe (slownik `stat`)

Bazowe eksporty z kodu staja sie statami bazowymi; afiksy/drzewko je modyfikuja. Kanon nazw
(`StringName`) i mapowanie na kod:

| `stat` | Mapuje na | Baza |
|---|---|---|
| `damage` | `attack_damage` | 18 |
| `attack_speed` | 1/`attack_cooldown` | ~2.2 |
| `crit_chance` / `crit_damage` | nowe (HitData) | 5% / +50% |
| `max_hp` / `hp_regen` | `max_hp` / nowe | 100 / 0 |
| `armor` | nowe u gracza (% redukcji, jak u wroga) | 0% |
| `move_speed` | `speed` | 6 |
| `dodge_iframes` | `dodge_iframes` | 0.30 |
| `stamina_max` / `stamina_regen` | `max_stamina` / `stamina_regen` | 100 / 22 |
| `lifesteal` | nowe (% obrazen->HP) | 0% |
| `area_radius` | `attack_range` | 2.2 |
| `<element>_damage` | fire/frost/poison/lightning/dark | 0 |
| `<element>_resist` | nowe | 0 |
| `cdr` | redukcja cooldownow | 0% |
| `pet_damage` / `pet_hp` | bonusy peta (od lvl 5) | 0 |
| `magic_find` | szansa na lepszy loot | 0% |

### 6.2 Tiery rzadkosci

Glowny driver mocy = **liczba afiksow** (wartosci skaluja sie osobno z `ilvl`).

| Tier | Kolor | Afiksy | Mnoznik | Sockety | Enchant | Uwaga |
|---|---|---|---|---|---|---|
| Pospolity | szary | 1 | x0.7 | 0 | nie | paliwo do recyklingu |
| Niezwykly | zielony | 2 | x0.85 | 0–1 | nie | pierwszy build |
| Rzadki | niebieski | 3 | x1.0 | 1 | tak (1) | trzon mid-game |
| Epicki | fioletowy | 4 | x1.15 | 1–2 | tak (1) | end-game roll |
| Legendarny | pomarancz | 4 + **efekt unikatowy (MORE)** | x1.25 | 2 | tak (mocniejsza pula) | nazwany, zmienia gre |
| Set | turkus | 2–3 stale + **bonusy 2/4-cz.** | x1.0 | 1 | tak | afiksy czesciowo FIXED |

Czestotliwosci dropu rosna z tierem dungeona/biomu (tabele w `TDD.md` / per-mob). Magic Find
podbija rzadkosc.

### 6.3 Sloty ekwipunku (7)

Bron, Glowa, Tulow, Nogi, Buty, Trinket 1, Trinket 2. Dwa trinkety = wolne sloty na
build-craft (nie daja armoru, daja synergie). Typy broni per klasa: Wojownik (miecz+tarcza /
topor 2H / wlocznia), Mag (rozdzka / kostur / orb), Ranger (luk / kusza / sztylety).

### 6.4 Afiksy (prefiksy/sufiksy) i biomy

Prefiks = ofensywa („co robi item”), sufiks = utility/defensywa. Item nigdy nie dostaje dwoch
afiksow tej samej `stat`. Wartosc = `lerp(min,max) x TIER_MULT x ilvl_scale(ilvl)` gdzie
`ilvl_scale = 1 + (ilvl-1)*0.04` — ten sam afiks z glebszego biomu jest po prostu mocniejszy.

Przyklady prefiksow: Ostry (`damage` increased), Plomienny (`fire_damage` flat), Lodowaty
(`frost_damage` + slow), Jadowity (`poison_damage` DoT), Burzowy (`lightning_damage`),
Precyzyjny (`crit_chance`), Bezlitosny (`crit_damage`), Wampiryczny (`lifesteal`), Masywny
(`area_radius`), Zwinny (`attack_speed`), Pancerny (`armor`), Witalny (`max_hp`).

Przyklady sufiksow: ...Niedzwiedzia (`max_hp` %), ...Zolwia (`armor` %), ...Geparda (`move_speed`),
...Cienia (`dodge_iframes`), ...Wytrwalosci (`stamina_regen`), ...Maga (`cdr`), ...Regeneracji
(`hp_regen`), ...Chciwosci (`magic_find`), ...Opornosci (`<elem>_resist`), ...Bestiarza (`pet_damage`).

**Biomy dosypuja tematyczne afiksy** (spojnie z paragrafem 7): Verdant -> Jadowity/Witalny/...Geparda;
Emberwaste -> Plomienny/...Wytrwalosci/...Opornosci Ognia; Frosthelm -> Lodowaty/Burzowy/...Cienia/...Maga.

### 6.5 Sety, enchanty, sockety

- **Sety:** 2 czesci = liczbowy buff (INCREASED), 4 czesci = power-spike (MORE + efekt
  zmieniajacy gre). Przyklady (po jednym/klasa): **Plomien Pustyni** (Mag: +15% `fire_damage`
  -> x25% `fire_damage` + AoE podpalenie), **Lowca Cieni** (Ranger: +8% `crit_chance` -> +100%
  `crit_damage` + co 3. strzal ignoruje armor), **Mur Obroncy** (Wojownik: +20% `armor` ->
  x20% `max_hp` + unik daje 1,5 s tarczy).
- **Enchanty (model MCD):** item Rzadki+ ma 1 slot; przy dropie wybor 1 z 3, ulepszany do rangi
  3 za **Pyl Enchantowania**, rerollowalny. Przyklady: Radiance (fala leczenia — co-op), Chains
  (CC AoE), Smiting (+dmg vs nieumarlych), Thorns (odbicie), Swirling (unik = wybuch zywiolu),
  Cool Down (`cdr`), Death Barter (przezyj z 1 HP).
- **Sockety + klejnoty:** item ma 0–2 sockety (wg tieru); klejnot = wymienny bundle
  `StatModifier`. 5 jakosci (Skaza->Doskonaly), stackowanie 10->1. Klejnoty: Rubin (`fire`/dmg),
  Szafir (`cdr`/`max_hp`), Szmaragd (`crit_chance`), Topaz (`lightning`), Diament (`armor`),
  Ametyst (`lifesteal`), Onyks (`magic_find`). Wyjmowalne za Zloto (nie tracisz klejnotu).

### 6.6 Itemy startowe (po pare na klase, vertical slice)

- **Wojownik:** Hartowany Topor (2H, Niezwykly: Ostry +12% `damage`, ...Niedzwiedzia +6% `max_hp`),
  Napiersnik Straznika (Rzadki: Pancerny +16 `armor`, ...Zolwia +10% `armor`, Witalny +40 `max_hp`),
  Buty Wytrwalosci (Niezwykly, 1 pusty socket).
- **Mag:** Rozdzka Iskry (Niezwykly: Plomienny +8 `fire_damage`, Zwinny +8% `attack_speed`),
  Kaptur Adepta (Rzadki: ...Maga +6% `cdr`, Witalny +25 `max_hp`, Szafir w sockecie), Amulet Zaru
  (Niezwykly: Bezlitosny +18% `crit_damage`).
- **Ranger:** Luk Cisowy (Niezwykly: Precyzyjny +6% `crit_chance`, ...Cienia +0,05 s
  `dodge_iframes`), Kurtka Zwiadowcy (Rzadki: ...Niedzwiedzia +8% `max_hp`, ...Geparda +6%
  `move_speed`, Pancerny +10 `armor`), Pierscien Lowcy (Niezwykly: ...Bestiarza +10% `pet_damage`,
  ...Chciwosci +8% `magic_find`).
- **Wspolne:** 3x Klejnot Skazy (offense/defense/crit), ~200 Zlota, 5 Pylu Enchantowania.

---

## 7. Swiat i 3 biomy (vertical slice)

Swiat jest proceduralny, deterministyczny z seeda (`feature_hash` + `FastNoiseLite`). Biom
wyliczany lokalnie z niskoczestotliwosciowego szumu (rozszerzenie istniejacego `biome_factor`),
wiec host i klient dostaja identyczny podzial z samego seeda.

| Biom | Tier lootu | Klimat / teren | Wrogowie | Oswajalne (pet) |
|---|---|---|---|---|
| **Verdant Hollow** (start) | 1 | zielen, cieple swiatlo, strumienie, geste zagajniki, niskie wzgorza | Slime Lesny (hordy 4–6), Klusownik-Goblin (= istniejacy Goblin), Wilk Cienisty (nocny x2) | Wilk Cienisty, Slaby Slime (tank) |
| **Emberwaste** (mid) | 2 | spalona ziemia, ochra, kaniony, jeziora lawy (DoT przy kontakcie), wiecej wejsc do dungeonow | Skorpion Spaczony (combo, testuje unik), Zywiolak Zaru (ranged + AoE), Hiena (stado/flank) | Skorpion (DPS), Hiena (szybki) |
| **Frosthelm Peaks** (szczyt slice'a) | 3 | snieg, zamiecie (gesta mgla), strome granie, lodowe jaskinie, cienki lod | Yeti (tank, uczy combo->pierce), Wilk Lodowy Alfa (buff-lider stada), Wraith Mrozny (teleport, ranged slow) | Wilk Lodowy Alfa (buff-aura), Yeti mlody (tank top) |

Kazdy biom ma wlasna palete, mgle i tabele afiksow/klejnotow (paragraf 6.4). „Skalowanie po
dystansie od spawnu” (model Cube World): glebszy region = wyzszy `ilvl` lootu i poziom wrogow
wokol poziomu gracza.

## 8. Dungeony (instancjonowane)

Wejscia sa **deterministyczne z seeda chunka** (kazdy klient liczy je identycznie — nic nie leci
po sieci poza `seed + tier` przy wejsciu). Wejscie = voxelowy prefab w terenie (zawalona brama,
jaskinia, krag runiczny). Trigger Area3D -> fade + async build w watku (reuse istniejacej puli
`WorkerThreadPool`) -> wejscie do osobnej proceduralnej przestrzeni.

**Generacja:** graf pokoi (logika) + stitching prefabow voxelowych (geometria) + BSP do
rozmieszczenia w gridzie, wszystko z `entrance_seed`. Krytyczna sciezka:
`ENTRANCE -> COMBAT x k -> TREASURE -> COMBAT x m -> MINIBOSS -> BOSS` + 1–3 odnogi (SECRET/LOOT/LOCKED).
**Zamek-klucz:** drzwi do BOSS zablokowane; klucz zawsze lezy na sciezce osiagalnej PRZED
drzwiami (w MINIBOSS lub SECRET). Tier dungeona skaluje `ilvl`, rzadkosc i nagrode konczaca
(T1 gwarant Rzadki -> T3+ gwarant Epicki + znaczaca szansa Set/Legenda + Pyl). Dungeon to
instancja efemeryczna — loot/postep przechodzi do postaci, sama przestrzen znika.

## 9. Pety / towarzysz (od lvl 5)

Pet = wariant wroga z `allegiance = ALLY` (dzieli 90% kodu Enemy). **Oswajanie (model Cube
World):** oslab dzika bestie (<35% HP) i uzyj jedzenia/przedmiotu zdobytego w terenie; szansa
zalezy od `tame_power` jedzenia i typu bestii. Tylko 1 aktywny pet (reszta „w stajni”). Pet
skaluje sie z poziomem gracza; jego smierc = respawn po cooldownie (nie permanentny — power-fantasy).

## 10. Progresja (lvl 99, drzewko, respec)

- **Poziomy 1–99**, trwale i nieutracalne. 1 punkt umiejetnosci na poziom (2–99 -> 98 pkt). Co 5
  poziomow dodatkowy **punkt mocy** (tylko na keystone/notable).
- **Drzewko skromne** (glowna moc z lootu): notable co 20 pkt zainwestowanych w sciezke;
  keystone wymaga lvl 25, capstone lvl 60.
- **Respec:** pelny reset za walute **Orby Przemiany** (koszt schodkowy: 500 -> 1500 -> 4000 ->
  +4000, cap). Pojedynczy wezel = 1 Orb Drobny (tani, dropi z elit). Drzewko da sie przebudowac
  za Zloto (alternatywa tania, wg `koszt = lvl x 50`); zmiana buildu lootowego = wyjecie klejnotow
  (Zloto) + reroll enchantu (Pyl), bez niszczenia itemu.

### 10.1 Ekonomia (3 waluty + Orby)

| Waluta | Zrodlo | Wydatek |
|---|---|---|
| **Zloto** | moby, sprzedaz, dungeony | respec drzewka (tani), wyjmowanie klejnotow, reroll enchantu, vendor |
| **Pyl Enchantowania** | recykling Rzadki+, bossowie, dungeony T2+ | ulepszanie/reroll enchantow |
| **Esencja Ulepszen** | recykling + craft | **upgrade `ilvl`** ulubionego itemu do biezacego poziomu, reroll afiksu |
| **Orby Przemiany** | bossowie, elity (Orb Drobny) | pelny respec drzewka (schodkowo) / pojedynczy wezel |

Petle „co robic”: recykling (sink na nadmiar lootu), upgrade ilvl (anti-frustration — nie tracisz
dobrego itemu wchodzac w wyzszy biom), reroll afiksu (end-game).

## 11. UI / HUD + zasoby per klasa

HUD podpiety pod sygnaly (nie czyta pol bezposrednio): paski **HP** i **stamina** (istnieja),
**licznik wrogow**, ekran smierci (istnieja). Dochodzi:
- **Pasek zasobu klasy:** Mana (Mag) / Furia 0–100 (Wojownik) / Combo 0–5 + Focus (Ranger) —
  jeden widget, inny tryb wg klasy (wzorem istniejacego `stamina_changed`).
- **Combo licznik** (istnieje `combo_changed`) — „Combo xN”.
- **Pasek skilli** (4 aktywne + cooldowny), **damage numbers**, **toast lootu** (kolor wg tieru),
  **minimapa/kompas** wejsc do dungeonow.
- **Ekrany:** ekwipunek (7 slotow + plecak), drzewko, craft/enchant/socket, oswajanie peta.

## 12. Kreator postaci

Przy nowej grze: wybor **klasy** (Mag/Wojownik/Ranger) + **wyglad** (parametry postaci
voxelowej — kolor ciala, proporcje konczyn, skala wzrostu; postac jest juz parametryczna w kodzie).
Wyglad zapisywany w `CharacterAppearance` (Resource) i przenosny miedzy swiatami (postac nalezy do
gracza, swiat do hosta — patrz `TDD.md` paragraf zapis hybrydowy).

## 13. Multiplayer (co-op do 4)

Wspolny swiat ze znajomymi, **listen-server** (jeden gracz hostuje). NIE masowe MMO. Swiat
generowany lokalnie u kazdego z seeda (oszczednosc pasma); siec niesie tylko encje, ich stan,
loot i edycje swiata. Walka i loot host-authoritative, ruch wlasnej postaci predykowany u klienta.
SP to po prostu „sesja z jednym peerem, ktory jest hostem” — szczegoly w `TDD.md`.

## 14. Styl audiowizualny i prawo

Voxel, czyste palety, miekkie swiatlo dnia/nocy, mgla atmosferyczna per biom. Assety wylacznie
wlasne lub CC0/CC-BY (`CREDITS.md`, `LEGAL.md`). Pelna wlasnosc praw (Godot MIT). Nazwa robocza —
finalna po clearance (`NAMING.md`).
