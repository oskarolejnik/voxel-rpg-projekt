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
