# Game Design Document — (nazwa robocza: Voxel RPG)

> Dokument żywy. To NASZ oryginalny projekt gry. Cube World był inspiracją gatunkową;
> tu zapisujemy własne decyzje projektowe. Wersja 0.1 — szkielet, rozwijany etapami.

## 1. Pitch (jednozdaniowy)

Voxelowy action-RPG o **eksploracji i skillu**: biegasz po proceduralnym, sześciennym
świecie, walczysz w dynamicznym systemie walki, zdobywasz loot i umiejętności, a nowe
narzędzia ruchu (wspinaczka, lotnia, łódź) **otwierają przed Tobą kolejne regiony świata**.

## 2. Filary projektowe (czego bronimy przed scope creep)

1. **Eksploracja jest nagrodą.** Świat ma być ciekawy do zwiedzania; ruch ma być przyjemny sam w sobie.
2. **Walka oparta na skillu, nie na liczbach.** Dobry gracz wygrywa z silniejszym wrogiem dzięki uniki/combo, nie tylko statystykom.
3. **Trwały wzrost postaci.** Gracz **nigdy nie traci** zdobytej mocy (lekcja z porażki Cube World 1.0). Poziomy i drzewko umiejętności są stałe.
4. **Czytelność voxelowa.** Prosty, czysty styl bloków — łatwy do produkcji solo, spójny wizualnie.

## 3. Pętla rozgrywki (core loop)

```
Eksploruj region  →  Walcz (skill)  →  Loot + XP  →  Ulepsz postać/sprzęt
        ↑                                                      │
        └──── Odblokuj narzędzie traversalu → nowy region ─────┘
```

## 4. Sterowanie i kamera

- Trzecioosobowa kamera (orbita za postacią), WASD + mysz, spacja skok, shift unik/sprint.
- Cel MVP: płynny ruch postaci po terenie voxelowym, kamera bez przenikania przez bloki.

## 5. Świat

- **Proceduralny, seedowany.** Teren z szumu (height + biom + jaskinie).
- **Biomy (docelowo):** łąki, las, śnieg, pustynia, dżungla, bagna, lawa. *MVP: 1 biom (łąki/las).*
- **Chunki:** świat dzielony na chunki ładowane wokół gracza (streaming).
- **POI (docelowo):** wioski (vendor, questy), świątynie-checkpointy, lochy. *MVP: brak — sam teren.*

## 6. Postać i progresja (MODEL ALFY — decyzja projektowa)

- **XP → poziomy → punkty umiejętności** wydawane w drzewku. Moc **trwała i przenośna**.
- Świeżość regionów = **skalowanie wrogów + bramki na kluczach traversalu**, NIE kasowanie mocy.
- **Klasy (docelowo):** Wojownik, Łowca, Mag, Łotr — każda z 2 specjalizacjami. *MVP: jedna klasa melee.*

## 7. Walka

- Action-combat: lekki/ciężki atak, **unik z i-frames** (stamina), blok.
- **Combo jako przebicie pancerza:** rosnący licznik trafień ignoruje coraz więcej armoru wroga; pudło/trafienie resetuje. (Sygnaturowa mechanika — nagradza agresję i skill.)
- **MVP:** gracz + 1–2 typy wrogów, HP/dmg, śmierć/respawn.

## 8. Ekwipunek, loot, crafting (po MVP)

- 5 poziomów rzadkości z losowymi afiksami; zawężony zakres rzadkości w obrębie regionu (anty-RNG-swing).
- Crafting stacjowy (recepturowy). Jedzenie (siadasz) vs mikstura (w ruchu).

## 9. Traversal (klucze do świata)

- Wspinaczka → lotnia → pływanie/nurkowanie → żeglowanie → wierzchowiec.
- Każde narzędzie **na nowo otwiera mapę** (pętla metroidvania).

## 10. Pety (później)

- Oswajanie karmieniem; role (dmg/heal/tank/mount); jeden aktywny; skalowanie od mocy gracza.

## 11. Multiplayer (opcjonalnie, po single-playerze)

- Co-op 2–4 graczy we wspólnym seedowanym świecie.

## 12. Styl audiowizualny

- Voxel, czyste palety, miękkie światło dnia/nocy. Assety **wyłącznie własne lub CC0/CC-BY** (patrz `../CREDITS.md`).

## 13. Zakres MVP (vertical slice — co MUSI być w pierwszym grywalnym buildzie)

> **DO POTWIERDZENIA z Oskarem** — patrz pytanie o „rdzeń v1" w ROADMAP.

Propozycja minimalna:
- [ ] Proceduralny voxelowy teren (1 biom), streaming chunków
- [ ] Sterowalna postać 3rd-person + kamera
- [ ] Podstawowa walka melee + 1 typ wroga z prostym AI
- [ ] HP, śmierć/respawn
- [ ] Prosty drop lootu (placeholder) + licznik XP
- [ ] Zapis/odczyt pozycji i postępu

Wszystko poza tą listą = **po MVP**.
