# Audio — manifest assetów (ETAP 8)

Ten folder trzyma pliki dźwiękowe gry. **Pliki NIE są dołączone do repo** — wrzucasz je sam
(własne lub CC0 / CC-BY z atrybucją w `CREDITS.md`). System audio (`autoload/AudioManager.gd`)
działa OD RAZU bez plików: gdy pliku brak, `play_sfx`/`play_music` to **no-op** (cisza, zero
crashy). Po wrzuceniu pliku o właściwej nazwie i **restarcie gry** dźwięk gra **bez zmiany kodu**.

## Jak to działa (kontrakt "wrzuć plik → działa")

- Nazwa pliku = logiczne `id` z manifestu poniżej (np. `attack` → `sfx/attack.ogg`).
- Obsługiwane rozszerzenia (brane pierwsze istniejące): **`.ogg`**, `.wav`, `.mp3`. Zalecane `.ogg`
  (mały rozmiar, dobry do muzyki i SFX).
- Muzyka jest automatycznie zapętlana w kodzie (nie musisz ustawiać loop w imporcie).
- Głośność: szyny **Master / SFX / Music** (suwaki w Ustawieniach) — nie trzeba nic konfigurować.

## SFX (folder `sfx/`)

| Plik (id)            | Kiedy gra                                  | Hook w kodzie |
|----------------------|--------------------------------------------|---------------|
| `sfx/attack.ogg`     | zamach gracza (LMB)                         | Player → AbilityComponent (opcjonalny) |
| `sfx/hit.ogg`        | trafienie celu (zadane obrażenia)          | `DamageService.hit_resolved` |
| `sfx/crit.ogg`       | trafienie krytyczne (fallback: `hit`)      | `DamageService.hit_resolved` |
| `sfx/player_hurt.ogg`| gracz oberwał                              | Player.take_damage (opcjonalny) |
| `sfx/death.ogg`      | śmierć wroga                               | `Main._on_enemy_died` |
| `sfx/player_death.ogg`| śmierć gracza                             | `Main._on_player_died` |
| `sfx/loot.ogg`       | podniesienie itemu                          | `Main._on_loot_picked_up` |
| `sfx/gold.ogg`       | podniesienie złota (fallback: `loot`)      | `Main._on_loot_picked_up` |
| `sfx/levelup.ogg`    | awans poziomu                              | `Main` (leveled_up) |
| `sfx/ability.ogg`    | finisher / skill zasobu klasy (R)          | (opcjonalny) |
| `sfx/dodge.ogg`      | unik / dash                                | (opcjonalny) |
| `sfx/perfect_dodge.ogg`| udany perfect-dodge (fallback: `dodge`)  | (opcjonalny) |
| `sfx/ui_click.ogg`   | kliknięcie w menu                          | MainMenu / PauseMenu / SettingsMenu |

## Muzyka (folder `music/`)

| Plik (id)            | Kiedy gra                                  |
|----------------------|--------------------------------------------|
| `music/menu.ogg`     | menu główne                                |
| `music/explore.ogg`  | eksploracja (brak wrogów w pobliżu)        |
| `music/combat.ogg`   | walka (żywy wróg < 22 m od gracza)         |
| `music/night.ogg`    | noc/ambient (rezerwa; fallback: `explore`) |

## Źródła CC0 (sugestie — zweryfikuj licencję przy pobraniu)

- **freesound.org** (filtr licencji CC0) — SFX (ciosy, kroki, UI, śmierć).
- **opengameart.org** (filtr CC0) — pętle muzyczne i SFX.
- **kenney.nl** — paczki SFX/UI na licencji CC0.
- Własne nagrania / generatory (sfxr, ChipTone) — w pełni Twoje prawa.

Każdy wrzucony asset zewnętrzny → wpis w `CREDITS.md` (tytuł, autor, licencja, URL).
