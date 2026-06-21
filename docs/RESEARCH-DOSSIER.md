# Cube World Alpha → Twoja własna gra: dossier decyzyjne

*Informacja ogólna, nie porada prawna. Przed komercyjną premierą skonsultuj się z polskim prawnikiem od własności intelektualnej (radca prawny / adwokat, specjalizacja: prawo własności intelektualnej).*

---

## 1. Najważniejsze: rzeczywistość prawna

Zacznę od twardej prawdy, bo to ona wyznacza cały plan.

**To, czego NIE możesz zrobić (i co trzeba wykreślić z planu):**

- **Nie możesz wziąć skompilowanego Cube World, zmienić mu nazwy i ogłosić, że to twoja gra z „pełnymi prawami autorskimi".** To podręcznikowe naruszenie praw autorskich. Kopiujesz cudze chronione dzieło, a na dodatek kłamiesz o autorstwie — co dokłada problem naruszenia **autorskich praw osobistych** (w Polsce są **wieczyste i niezbywalne** — nie da się ich „przeczekać" ani odkupić).
- **„Abandonware" to NIE jest status prawny.** To potoczne, nieformalne słowo. Prawo autorskie nie zna takiego pojęcia. Mylone bywa ze znakiem towarowym (ten faktycznie można stracić przez nieużywanie) — ale prawo autorskie **nie wygasa dlatego, że gra przestała być sprzedawana, łatana czy wspierana**.
- **Prawa do Cube World żyją i mają właściciela.** Należą do **Picroma e.K. / dr. Wolframa von Funcka** (Saarlouis, Niemcy — aktywny, zarejestrowany podmiot). Co więcej: gra **jest nadal sprzedawana na Steam** (App ID 1128000), a Wollay w maju 2023 ogłosił remake **„Cube World Omega" w Unreal Engine 5** — czyli właściciel czynnie utrzymuje i eksploatuje prawa. Ochrona to **życie autora + 70 lat** (prawo polskie/UE i USA) — czyli realnie do lat **2070+**, niezależnie od tego, jak „martwa" gra wygląda.
- **Dekompilacja w UE też tu nie pomoże.** Dyrektywa 2009/24 pozwala dekompilować tylko w wąskich celach: **interoperacyjność** własnego, niezależnie stworzonego programu oraz (wyrok TSUE z 6 X 2021) **naprawa błędów** w legalnie posiadanym oprogramowaniu. Dekompilacja, by skopiować/zrebrandować grę, **nie mieści się w żadnym z nich**.

**Wniosek:** plan „przemianuję i ogłoszę, że to moje" jest jedyną jednoznacznie nielegalną opcją na stole. Trzeba go porzucić.

**A teraz dobra wiadomość — i to naprawdę dobra:**

Prawo autorskie chroni **sposób wyrażenia** pomysłu, **nigdy sam pomysł**. To tzw. dychotomia idea/wyrażenie, wpisana wprost w **art. 1(2) dyrektywy o programach komputerowych**. TSUE potwierdził konsekwencje w sprawie **SAS Institute v. World Programming (C-406/10)**: **funkcjonalność, języki programowania i formaty plików NIE są chronione**. Wolno legalnie badać, obserwować i testować program, by zbudować **inny** program o **tej samej funkcjonalności** — pod warunkiem, że nie kopiujesz kodu ani assetów.

Dla gry znaczy to, że **wolno Ci za darmo użyć**:
- **gatunku** (voxelowy action-RPG z eksploracją),
- **mechanik, reguł i systemów** (crafting, klasy, loot, traversal, cykl dnia/nocy — sam *pomysł* funkcji),
- ogólnego **„feelu"** na poziomie abstrakcyjnym,
- elementów *scènes à faire* (standardowych, nieuniknionych dla gatunku — np. pasek HP).

**Dlatego ORYGINALNA gra zainspirowana Cube World jest w 100% Twoja i w pełni legalna.** Tak właśnie powstają „duchowi następcy": *Stardew Valley* ↔ *Harvest Moon*, *Hades* ↔ roguelike'i, setki gier typu Tetris. To jedyna ścieżka, która pozwala Ci uczciwie posiadać to, co tworzysz. Tę wybieramy.

Linia orzecznicza w jednym zdaniu (kazusy USA, ale UE rozumuje tak samo):
- **Wygrali klonujący** (skopiowali mechanikę, wyrażenie własne): *Atari v. Amusement World* (Asteroids), *Data East v. Epyx* (karate), *Capcom v. Data East* (Street Fighter II). Lekcja: **kopiowanie mechanik i koniecznych elementów gatunku jest legalne.**
- **Przegrali klonujący** (skopiowali wyrażenie): **Tetris v. Xio** — Xio skopiowało reguły (OK), ale też dokładną oprawę audiowizualną (plansza 20×10, „duch" klocka, podgląd następnego klocka) — naruszenie. **Spry Fox v. 6Waves** — nawet przy *innej grafice* przegrana, bo skopiowano specyficzną strukturę progresji + dochodziły złe fakty (podobna nazwa „town", dostęp pod NDA, intencja klonowania). Lekcja: **sama zmiana grafiki Cię nie ratuje, a udowodniona intencja kopiowania szkodzi.**

---

## 2. Co naprawdę jest w folderze

Zawartość `C:\Users\oskar\Downloads\Cube World Alpha\Cube World Alpha\` to **skompilowana gra i zamknięte, własnościowe assety — bez kodu źródłowego.**

- **Pliki wykonywalne (binarki):** `Cube.exe`, `CubeLauncher.exe`, `Server.exe` — skompilowane programy. To **chronione dzieło Picromy**; zero kodu źródłowego.
- **Kontenery assetów:** `data1.db`–`data4.db` (bazy **SQLite** typu klucz→blob; payloady binarne/skompresowane), `resource1.dat`, `resource2.dat`. To **własnościowe assety Picromy** (modele, tekstury, dźwięki).
- **Pliki graficzne `.plx` („PlasmaGraphics"):** `interface.plx`, `gui.plx`, `cursor.plx`, `help.plx`, `quest-tag.plx`, `start.plx` — własnościowy, kawałkowany format binarny.
- **Branding:** `logo.bmp` — chroniony **prawem autorskim i (potencjalnie) jako element marki**.
- **Konfiguracja:** `options.cfg`, `server.cfg`. **Biblioteki firm trzecich:** `FreeImage.dll`, `zlib1.dll`, `XAudio2_8.dll`, `msvcp110.dll`, `msvcr110.dll`, `vccorlib110.dll` (runtime Visual C++). **Deinstalator:** `unins000.exe`/`.dat`.

**Co to oznacza praktycznie:** masz produkt końcowy, a nie „przepis". Nie da się tego legalnie „otworzyć i przerobić na swoje". Te pliki służą Ci **wyłącznie jako materiał badawczy** — uruchamiasz grę, grasz, obserwujesz, jak działają mechaniki, i **odtwarzasz systemy od zera** we własnym kodzie i własnej grafice. **Żadnego pliku z tego folderu nie wolno użyć w Twojej grze** — ani modelu, ani dźwięku, ani logo, „nawet jako placeholder".

---

## 3. Czym jest Cube World

- **Gatunek:** voxelowy action-RPG nastawiony na eksplorację, w proceduralnie generowanym świecie z sześcianów.
- **Twórcy:** dr **Wolfram „Wollay" von Funck** (projekt/kod) i jego żona **Sarah „Pixxie" von Funck** (grafika). Start prac: **czerwiec 2011**.
- **Studio:** **Picroma e.K.**, Saarlouis, Niemcy.
- **Alfa 2013:** wydana **2 lipca 2013** jako płatna alfa, sprzedawana bezpośrednio. W dniu premiery serwery padły pod **atakiem DDoS**. Alfę **szybko wycofano** i nigdy oficjalnie nie udostępniono ponownie. Cisza **2013–2019**.
- **Premiera na Steam:** **30 września 2019**. Odbiór: rozczarowanie. Przeprojektowana progresja — **ekwipunek przypisany do regionu/biomu** resetujący moc po przekroczeniu granicy — zebrała ostrą krytykę.
- **Status (poł. 2026):** wciąż na Steam, oceny „Mostly Negative", niski online. **Prawa NIE są porzucone** — w maju 2023 ogłoszono remake **„Cube World Omega" w UE5**.

**Status własności IP:**
- **Prawa autorskie:** automatyczne, życie autora + 70 lat, należą do **Picroma / von Funck**.
- **Znak towarowy „Cube World":** Picroma nie ma widocznego zarejestrowanego znaku słownego w USA, ALE „Cube World" to też znana **linia zabawek Radica/Mattel** trzymająca znak w kategorii zabawek. Sam ciąg jest zajęty przez stronę trzecią. Każdą rejestrację weryfikuj w **USPTO TSDR / EUIPO / DPMA**.

---

## 4. Mechaniki do odtworzenia (legalnie)

Mapa systemów do **napisania od zera własnym kodem**. Mechaniki nie są chronione — kopiuj je, ale wyrażaj po swojemu.

**Esencja pętli:** eksploruj proceduralny świat → walcz w action-combat opartym na skillu → lootuj/craftuj lepszy sprzęt → pokonuj trudniejsze lochy/bossów → odblokowuj narzędzia traversalu otwierające nowy teren → powtórz w nowym regionie.

- **Styl art (voxel).** Wszystko z sześcianów; postacie/stwory **proceduralnie składane z części voxelowych** + palety. Zbuduj runtime'owy builder modeli z małej biblioteki części — to główny mnożnik produkcji.
- **Generowanie świata i biomy.** Nieskończony, seedowany świat; mapa świata jako hub. Regiony = instancja biomu z poziomem trudności (kolor). Biomy: łąki, las, śnieg, pustynia, sawanna, dżungla, bagna, grzyby, lawa, nieumarli, ocean. POI: wioski, świątynie-checkpointy, lochy, wieże, zamki, portale.
- **4 klasy × 2 specjalizacje:** Wojownik (Berserker/Guardian), Łowca (Sniper/Scout), Mag (Fire/Water), Łotr (Assassin/Ninja). Każda spec = (pasywna tożsamość) + (jedna unikalna aktywna). **Typ broni napędza moveset.**
- **Walka (action-combat).** Skill, ruch, reakcja. **Dodge roll** z i-frames (stamina). Smaczek: **licznik combo działa jak przebicie pancerza** — kolejne trafienia ignorują coraz więcej armoru (pudło resetuje). Nagradza agresję.
- **Traversal jako progresja (klucze metroidvania).** Wspinaczka, lotnia, pływanie/nurkowanie, żeglowanie, wierzchowce. Specjalne przedmioty odblokowujące + konsumpcje negujące lawę/lód/toksyny. **Każde nowe narzędzie otwiera mapę na nowo.**
- **Pety i oswajanie.** Karmienie ulubionym jedzeniem; role melee/ranged/heal/tank/mount; jeden aktywny; **skalują się od mocy gracza**.
- **Crafting.** Stacjowy, recepturowy (ognisko, kowadło, krosno, piec, alchemia). Smaczek: **jedzenie (siadasz, unieruchomienie) vs mikstura (pijesz w ruchu)**.
- **Loot i rzadkość.** 5 poziomów (Biały→Zielony→Niebieski→Fioletowy→Złoty), losowe afiksy. Łagodź „RNG power-swing" zawężeniem zakresu rzadkości w regionie.
- **Questy, lochy, bossowie.** Misje kolorowane wg trudności; różne czasowniki (nie tylko „zabij X"); dzienne resety; liniowe lochy z bossem.
- **Multiplayer / co-op** we wspólnym seedowanym świecie. Model: dedykowany serwer (alfa, sprzyja modom) vs lista znajomych z migracją hosta (1.0).

### KLUCZOWA decyzja: Alfa (2013) vs 1.0 (2019)

Społeczność **zdecydowanie woli alfę.**

- **Alfa — trwała progresja:** XP → poziomy → **punkty umiejętności** w drzewku; moc **trwała i przenośna** między regionami.
- **1.0 — sprzęt przypisany do regionu:** brak XP/poziomów; cała moc = ekwipunek przypisany do regionu (wyjdziesz — bezwartościowy). „Artefakty" dawały żałośnie małe bonusy.
- **Dlaczego 1.0 odrzucono:** brak trwałego wzrostu (ciągły restart mocy), brutalne RNG, utrata inwestycji w build.

**Najważniejszy wniosek dossier:** zrób **action-RPG z poziomym lootem, ALE z trwałym, pionowym kręgosłupem progresji** (poziomy/drzewko), którego gracz **nigdy nie traci**. Świeżość eksploracji osiągnij przez **skalowanie wrogów + bramki na kluczach traversalu**, a NIE przez kasowanie mocy na granicy. Samo Picroma to przyznało — Omega przywraca XP/poziomy/drzewka. Dodaj **tutorial** (jego brak był w 1.0 zarzutem nr 1).

---

## 5. Rekomendowany stack technologiczny

**Rekomendacja główna:** **Godot 4 + moduł `godot_voxel` (Voxel Tools) Zylanna + MagicaVoxel do assetów.**

- **Własność:** Godot na licencji **MIT** — darmowy, zero tantiem, brak progu przychodu, brak splash screena. Najczystsza historia „posiadam moją grę w całości".
- **Voxele:** `godot_voxel` (MIT) — teren blokowy i gładki, LOD, nieskończone stronicowanie chunków, kolizje.
- **Assety:** **MagicaVoxel** (darmowy, output w pełni Twój komercyjnie), eksport OBJ/PLY → Blender → Godot.
- **Proc-gen:** wbudowany **FastNoiseLite**. **Co-op:** wbudowany high-level multiplayer (ENet, RPC).
- **Dla solo-deva:** najwyższa produktywność; GDScript pythonowy, ogromny ekosystem tutoriali.

**Veloren — czytaj, nie kopiuj.** Najlepszy punkt odniesienia (multiplayer voxel RPG inspirowany CW, Rust, ECS). ALE **GPL-3.0**: dystrybucja dzieła pochodnego zmusza do otwarcia całości pod GPL. **Wolno uczyć się** z architektury i re-implementować pomysły własnym kodem; **nigdy nie kopiuj kodu ani nie forkuj**, jeśli chcesz pełnej własności. Książka: https://book.veloren.net/

**Alternatywy:**

| Silnik | Licencja / koszt | Werdykt |
|---|---|---|
| **Godot 4 + godot_voxel** | MIT, 0 tantiem | **Rekomendacja główna.** Pełna własność, gotowe voxele/LOD, przyjazny początkującemu. |
| **Bevy (Rust, ECS)** | MIT/Apache-2.0 | Alternatywa „purystyczna", najbliżej Veloren. Stromsza krzywa, narzędzia voxelowe składasz sam. |
| **Unity** | Darmowy <200k$/rok | Ryzyko zaufania/licencji (fiasko cennika 2023). |
| **Unreal 5** | 5% tantiem >1M$ | Zły wybór: ciężki, nie-natywnie voxelowy, wolna iteracja dla solo. |
| **Własny silnik** | Twój | Niezalecane teraz — 1–2 lata na silnik zamiast na grę. |

---

## 6. Marka i assety

**Nazwa / znak towarowy:** unikaj „Cube World" i bliskich wariantów. Test prawny to **prawdopodobieństwo wprowadzenia w błąd**. Wybierz silny, dystynktywny znak. Darmowy clearance: **EUIPO/TMview, USPTO TESS, Steam, itch/sklepy, Google/YouTube, domeny**. Zachowaj datowany zapis wyszukiwań.

**Checklista assetów:**
- Buduj wszystko od zera w **MagicaVoxel / Blender** (output w pełni Twój).
- **NIGDY nie wypakowuj/konwertuj** assetów CW (`data*.db`/`.plx`) ani nie odtwarzaj 1:1 ze screenshotów.
- **Muzyka/SFX:** oryginał lub otwarte licencje — **Kenney** (CC0), **OpenGameArt**, **Freesound** (sprawdzaj każdy plik). CC0 = bez kredytów; CC-BY = **musisz podać autora**; unikaj CC-BY-SA/GPL (copyleft) i CC-BY-NC (zakaz komercji) w płatnej grze.
- **Czysty łańcuch praw:** trzymaj pliki źródłowe (`.vox`/`.blend`/DAW), Git z datowanymi commitami, `CREDITS.md`, a przy współpracownikach — umowa o przeniesienie praw przed startem prac.

---

## 7. Realistyczna mapa drogowa

Wróg nr 1 to **scope creep**, nie brak talentu. Każdy etap = skończona, grywalna rzecz:

1. **Podstawy silnika (2–4 tyg.)** — język/edytor, demo-ruch 3D.
2. **Spike terenu voxelowego (3–6 tyg.)** — proceduralny świat, stawianie/usuwanie bloków.
3. **Vertical slice action-RPG (2–4 mies.)** — jedna postać, walka, 1–2 wrogów z AI, HP/dmg, loot, jeden biom. Single-player.
4. **Warstwa RPG (3–6 mies.)** — ekwipunek, staty, **poziomy/drzewko (model alfy!)**, kilka biomów, questy, save/load, audio, UI.
5. **Multiplayer (opcjonalnie, później)** — dopiero gdy single-player jest fun; co-op 2–4 graczy.

**Horyzont:** dopracowany single-player slice ~6–12 mies. po godzinach; mała gra do wydania 1,5–3 lata.

---

## 8. Decyzje do podjęcia

1. **Silnik** — Godot 4 (domyślnie) / Bevy / inne?
2. **Model progresji** — trwałe poziomy/drzewko (rekomendacja) ✓
3. **Zakres v1** — która pętla jest rdzeniem (walka+loot? +traversal? +crafting?)?
4. **Nazwa + clearance** — 3–5 kandydatów przez TMview/USPTO/Steam/domeny.
5. **Single-player czy od razu co-op** — rekomendacja: SP najpierw.
6. **Pipeline assetów** — MagicaVoxel (+Blender), `CREDITS.md` + Git od dnia 1.
7. **Komercja?** — jeśli tak: konsultacja z prawnikiem IP przed premierą; unikać copyleft.

*To informacja ogólna, nie porada prawna.*
