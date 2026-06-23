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
