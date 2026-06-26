# Voxel RPG (nazwa robocza)

Oryginalna, voxelowa gra action-RPG **inspirowana** Cube World — pisana od zera,
z własnym kodem i własnymi assetami, tak aby **Oskar Olejnik był w 100% jej autorem
i właścicielem praw autorskich**.

> **To NIE jest Cube World ani jego modyfikacja.** Nie zawiera żadnego kodu,
> grafiki, dźwięku ani marki Cube World / Picroma. Cube World jest jedynie
> **inspiracją gatunkową** — a gatunek i mechaniki nie podlegają prawu autorskiemu.
> Szczegóły: [`docs/LEGAL.md`](docs/LEGAL.md).

## Status

🟢 **W aktywnym rozwoju — grywalny szkielet action-RPG.** Silnik: **Godot 4.7 / GDScript**.
Architektura **single-player-first** z trybem **co-op do 4 graczy** (listen-server).
Projekt urósł daleko poza prototyp „Hello 3D": działa świat z biomami i podziemnymi
jaskiniami, progresja postaci, walka ze status-effectami, proceduralne lochy z bossami
oraz trwały zapis gry.

## ✨ Co już działa

- **Tożsamość wizualna „Storybook Voxel"** — spójny, stylizowany look (malarska bryła bez tekstur, tożsamość przez sylwetkę + kolor + blask): 11 klas z odrębną paletą + naramiennikami wg pancerza + nakryciem głowy (hełm/kaptur/kapelusz maga) + świecącym akcentem; atmosferyczne światło (księżycowa noc, złota godzina z god-rays, paleta per biom); szum nieba z chmurami/gwiazdami/księżycem; mikro-voxelowe pnie; juice walki (iskry flash-to-fade, efektowne zgony). Pełny kierunek w [`docs/ART-DIRECTION-BIBLE.md`](docs/ART-DIRECTION-BIBLE.md).
- **Świat i biomy** — voxelowy świat z 7 biomami i progresją trudności opartą o dystans od startu.
- **Jaskinie i rudy** — proceduralnie drążone, połączone tunele i komory pod powierzchnią (deterministyczny szum 3D, w pełni chodliwe z kolizją) oraz żyły rud — miedź, żelazo, złoto — w pasmach głębokości o rosnącej rzadkości.
- **Klasy i rozwój** — 11 klas postaci, każda z własnym drzewkiem umiejętności, plus kreator postaci.
- **Walka** — system status-effectów (podpalenie, trucizna, krwawienie, spowolnienie, ogłuszenie, osłabienie) oraz „game feel" (hitstop, przerwanie postawy / poise-break, strafe).
- **Lochy** — proceduralnie generowane lochy z mechanikami bossów (enrage / miniboss) i lootem z pomieszczeń.
- **Co-op** — hostowanie i dołączanie przez RPC, do 4 graczy na listen-serverze.
- **Zapis gry** — trwały system zapisu (`SaveManager`) z pokryciem testowym.
- **AI** — system nastawienia stworzeń (wrogie / neutralne / pasywne).
- **Pipeline treści** — dane gry (rasy, klasy, pochodzenie) jako zasoby `.tres`, łatwe do rozszerzania.
- **Jakość** — własny audyt 11 podsystemów napędzający backlog (`docs/`).

## Struktura repo

| Ścieżka | Zawartość |
|---|---|
| `docs/RESEARCH-DOSSIER.md` | Pełny research: prawo, historia, mechaniki, stack, marka |
| `docs/GDD.md` | Game Design Document — projekt gry (nasz, oryginalny) |
| `docs/ROADMAP.md` | Plan etapów (od prototypu do grywalnego slice'a) |
| `docs/LEGAL.md` | Zasady: co wolno, czego nie wolno (łańcuch praw) |
| `docs/NAMING.md` | Kandydaci na nazwę + checklista clearance |
| `CREDITS.md` | Rejestr pochodzenia każdego assetu (dowód autorstwa) |
| `LICENSE` | Prawa zastrzeżone © Oskar Olejnik |
| `assets/` | Własne assety (modele .vox, tekstury, audio) |
| `src/` | Kod gry (świat, walka, klasy, lochy, sieć, zapis) |

## Zasada nr 1

Wszystko w tej grze musi być **stworzone od zera albo legalnie licencjonowane**
(CC0 / CC-BY z atrybucją). Żaden plik z folderu „Cube World Alpha" nie trafia tutaj —
nawet jako placeholder. Każdy asset zapisujemy w `CREDITS.md`.

— © 2026 Oskar Olejnik
