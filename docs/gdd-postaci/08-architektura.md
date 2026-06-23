## 8. Architektura systemu (Data-Driven)

Niniejszy rozdział opisuje docelową architekturę systemu postaci (rasy, klasy, pochodzenie, wygląd, imiona, sterowanie) oraz zasady, według których cała treść gry jest definiowana jako **dane (.tres)**, a nie jako kod. Celem nadrzędnym jest: dodanie nowej rasy, klasy czy pochodzenia ma sprowadzać się do **utworzenia pliku `.tres` i wrzucenia go do odpowiedniego katalogu** — **bez żadnej zmiany w GDScript**. Architektura jest spójna z technologią projektu: Godot 4.7 + GDScript, `Resource` (.tres), autoloady (singletony-serwisy/rejestry), kompozycja komponentów oraz host-authoritative combat.

### 8.1 Filary architektoniczne

1. **Dane jako zasoby (Data-as-Resources).** Każdy byt konfiguracyjny (rasa, klasa, pochodzenie, preset wyglądu, zestaw reguł imion, profil sterowania) to `Resource` zapisany jako `.tres`. Zasoby są wersjonowalne w Git, edytowalne w inspektorze Godota i ładowalne w runtime.
2. **Kompozycja zamiast dziedziczenia.** `Player` to scena złożona z komponentów (`StatsComponent`, `MovementComponent`, `CombatComponent`, `AnimationComponent`, `ResourceComponent` itd.). Różnice między postaciami wynikają z **danych wstrzykniętych do komponentów**, nie z hierarchii klas GDScript.
3. **Singletony-serwisy / rejestry (autoloady).** Centralny `ContentDB` skanuje `res://` i udostępnia katalogi zasobów. Inne serwisy: `Events` (globalna magistrala sygnałów), `SaveService`, `RNG`.
4. **State machine** dla sterowania i animacji (stany ruchu/walki, blendy).
5. **Observer / sygnały** do luźnego sprzęgania systemów (zdrowie -> UI, śmierć -> loot itd.).
6. **Factory** budujące gotową instancję postaci z `CharacterDefinition` (agregatu danych) -> konfiguracja komponentów.
7. **Walidacja przy starcie.** Rejestry walidują zasoby (unikalność `id`, poprawność referencji, zakresy wartości) i raportują błędy zanim gracz wejdzie do gry.

### 8.2 Architektura klas (przegląd)

| Klasa (class_name) | Bazuje na | Rola | Przechowywana jako |
|---|---|---|---|
| `RaceResource` | `Resource` | Definicja rasy (modyfikatory statów, dozwolone klasy, opcje wyglądu, reguły imion) | `.tres` |
| `GenderOption` | `Resource` | Opcja płci/wariantu sylwetki (wpływa na siatkę i zestaw presetów) | `.tres` |
| `OriginResource` | `Resource` | Pochodzenie (bonusy startowe, ekwipunek, tło fabularne) | `.tres` |
| `ClassResource` | `Resource` | Definicja klasy (zasób klasowy, staty bazowe, drzewo umiejętności, broń) | `.tres` |
| `AppearancePreset` | `Resource` | Pojedynczy preset wyglądu (kolory, indeksy siatek, dodatki) | `.tres` |
| `AppearanceResource` | `Resource` | Katalog dostępnych opcji wyglądu dla rasy/płci (listy presetów i zakresów) | `.tres` |
| `NameRuleSet` | `Resource` | Reguły/generator imion danej rasy (sylaby, prefiksy, długości) | `.tres` |
| `ControlConfig` | `Resource` | Profil sterowania i tuning ruchu/kamery/celowania | `.tres` |
| `CharacterDefinition` | `Resource` | **Agregat**: wybory gracza (rasa+płeć+pochodzenie+klasa+wygląd+imię) | `.tres` (zapis postaci) |
| `ContentDB` | `Node` (autoload) | Rejestr: skanuje `res://`, indeksuje zasoby po `id`, waliduje, udostępnia listy | autoload |
| `CharacterFactory` | `RefCounted` | Buduje gotową instancję `Player` z `CharacterDefinition` | kod |

Wszystkie zasoby konfiguracyjne implementują wspólny kontrakt (przez konwencję): pole `id: StringName` (unikalne, stabilne — używane w zapisach), `display_name: String` (lokalizowalne) oraz `icon: Texture2D`.

### 8.3 Diagram zależności (tekstowy)

```
                         +------------------------+
                         |   ContentDB (autoload) |   skanuje res://content/**
                         |  rejestry po id:        |
                         |   races/ classes/ ...   |
                         +-----------+------------+
                                     | udostępnia listy / lookup(id)
            +------------------------+-----------------------------+
            |                        |                             |
       Kreator Postaci         CharacterFactory                 SaveService
       (UI, czyta listy)       (buduje Player)                  (zapis/odczyt
            |                        |                            CharacterDefinition.tres)
            | produkuje              | czyta agregat
            v                        v
     +---------------+        +--------------------------------------------+
     | Character     |------->|                Player (scena)              |
     | Definition    | wstrz. |  kompozycja komponentów:                   |
     | (agregat)     |        |  StatsComponent  <- RaceResource/ClassRes. |
     +---------------+        |  ResourceComponent (Furia/Mana/Focus)      |
        ^   ^   ^   ^         |  MovementComponent <- ControlConfig        |
        |   |   |   |         |  CombatComponent (host-authoritative)      |
   Race Class Origin          |  AnimationComponent (State Machine)        |
   Appearance/Name            |  AppearanceComponent <- AppearancePreset   |
   (referencje po id)         +---------------------+----------------------+
                                                    | emituje sygnały
                                                    v
                                          +----------------------+
                                          |  Events (autoload)   |  observer/sygnały
                                          |  health_changed,     |  -> UI, audio, loot
                                          |  resource_changed,   |
                                          |  entity_died, ...    |
                                          +----------------------+
```

Kierunek zależności jest jednostronny: **dane (.tres) nie znają kodu komponentów**; to komponenty czytają dane. Kreator i Factory zależą od `ContentDB`, a nie od konkretnych plików. UI zależy od sygnałów (`Events`), nie od logiki bojowej.

### 8.4 Wzorce projektowe (zastosowanie)

| Wzorzec | Gdzie | Po co |
|---|---|---|
| Data-as-Resources | wszystkie `*Resource` | treść edytowalna bez kompilacji, wersjonowalna |
| Kompozycja | `Player` + komponenty | różnice danymi, nie klasami; łatwa rozbudowa |
| Singleton-serwis / Rejestr | `ContentDB`, `Events`, `SaveService`, `RNG` | jeden punkt dostępu, brak twardych referencji |
| Factory | `CharacterFactory` | jedno miejsce budowy postaci z agregatu |
| State machine | `MovementComponent`, `AnimationComponent` | jasne stany ruch/walka, blendy |
| Observer / sygnały | `Events` + sygnały komponentów | luźne sprzęganie, UI reaguje na zdarzenia |
| Strategy (przez dane) | `NameRuleSet`, `ControlConfig` | wymienne algorytmy/tuning bez warunków w kodzie |

**Kompozycja zamiast dziedziczenia (przykład):** nie istnieje `class Mag extends Player`. Istnieje jeden `Player` z `StatsComponent`, do którego `CharacterFactory` wstrzykuje `ClassResource` o `id = &"mag"`. Zmiana balansu maga = edycja `mag.tres`, nie kodu.

### 8.5 Przykładowe struktury danych (GDScript)

#### 8.5.1 `RaceResource`

```gdscript
class_name RaceResource
extends Resource

## Unikalny, stabilny identyfikator (np. &"sylvani"). Używany w zapisach i referencjach.
@export var id: StringName
@export var display_name: String = ""            # np. "Sylvani"
@export_multiline var description: String = ""
@export var icon: Texture2D

# --- Modyfikatory statów wg pipeline base -> flat -> increased% -> more ---
@export_group("Modyfikatory statów (flat)")
@export var flat_strength: int = 0
@export var flat_agility: int = 0
@export var flat_intellect: int = 0
@export var flat_vitality: int = 0

@export_group("Modyfikatory statów (increased %)")
@export var increased_move_speed_pct: float = 0.0   # np. 5.0 = +5%
@export var increased_health_pct: float = 0.0
@export var increased_xp_gain_pct: float = 0.0

# --- Powiązania z resztą systemu (po id, nie po referencji ścieżkowej) ---
@export_group("Powiązania")
@export var allowed_class_ids: Array[StringName] = []   # puste = wszystkie 11 klas
@export var gender_option_ids: Array[StringName] = []
@export var appearance_id: StringName                   # -> AppearanceResource
@export var name_rule_set_id: StringName                # -> NameRuleSet
@export var home_biome: StringName                      # &"verdant_hollow" / &"emberwaste" / &"frosthelm_peaks"

# --- Pasywy rasowe (po id z rejestru pasywów) ---
@export var racial_passive_ids: Array[StringName] = []
```

Kanoniczne pliki: `duryjczycy.tres`, `sylvani.tres`, `karlowie_grimhold.tres`, `embrani.tres`, `orguni.tres`, `feruni.tres`.

#### 8.5.2 `ClassResource`

```gdscript
class_name ClassResource
extends Resource

@export var id: StringName                       # np. &"berserker"
@export var display_name: String = ""            # "Berserker"
@export_multiline var description: String = ""
@export var icon: Texture2D

# Zasób klasowy (Furia / Mana / Focus) — sterowany danymi, nie enumem w kodzie
@export_group("Zasób klasowy")
@export var resource_type: StringName = &"mana"  # &"fury" / &"mana" / &"focus"
@export var resource_max_base: float = 100.0
@export var resource_regen_per_sec: float = 5.0
@export var resource_color: Color = Color(0.2, 0.4, 1.0)

@export_group("Staty bazowe klasy")
@export var base_strength: int = 10
@export var base_agility: int = 10
@export var base_intellect: int = 10
@export var base_vitality: int = 10
@export var base_health: float = 100.0

@export_group("Walka / progresja")
@export var allowed_weapon_ids: Array[StringName] = []
@export var skill_tree_id: StringName                  # -> drzewo umiejętności
@export var starting_skill_ids: Array[StringName] = []
@export var level_cap: int = 99
@export var primary_attribute: StringName = &"strength" # główny stat skalujący

@export_group("Animacje / archetyp")
@export var animation_set_id: StringName               # zestaw blendów dla AnimationComponent
@export var combat_archetype: StringName = &"melee"    # &"melee" / &"ranged" / &"caster"
```

Kanoniczne pliki (11): `wojownik.tres`, `paladyn.tres`, `berserker.tres`, `lucznik.tres`, `lotrzyk.tres`, `zabojca.tres`, `mag.tres`, `nekromanta.tres`, `kaplan.tres`, `druid.tres`, `mnich.tres`.

#### 8.5.3 `AppearancePreset`

```gdscript
class_name AppearancePreset
extends Resource

@export var id: StringName
@export var display_name: String = ""

@export_group("Siatki (indeksy do AppearanceResource)")
@export var body_mesh_index: int = 0
@export var head_mesh_index: int = 0
@export var hair_mesh_index: int = 0
@export var beard_mesh_index: int = -1     # -1 = brak

@export_group("Kolory")
@export var skin_color: Color = Color.WHITE
@export var hair_color: Color = Color.BLACK
@export var eye_color: Color = Color(0.3, 0.5, 0.7)

@export_group("Proporcje (voxel)")
@export_range(0.85, 1.20, 0.01) var height_scale: float = 1.0
@export_range(0.85, 1.20, 0.01) var build_scale: float = 1.0

@export_group("Dodatki")
@export var decal_ids: Array[StringName] = []   # blizny, tatuaże, znamiona (np. ember-glow dla Embrani)
```

#### 8.5.4 `ControlConfig`

```gdscript
class_name ControlConfig
extends Resource

@export var id: StringName = &"default"
@export var display_name: String = "Domyślny"

@export_group("Ruch (względem kamery)")
@export var move_speed: float = 6.0
@export var acceleration: float = 40.0
@export var deceleration: float = 50.0
@export var sprint_multiplier: float = 1.5

@export_group("Obrót postaci")
@export_range(4.0, 30.0, 0.5) var turn_smoothing: float = 12.0   # lerp_angle/exp smoothing
@export var turn_in_place_threshold_deg: float = 100.0           # ostry zwrot -> turn-in-place
@export var face_movement_out_of_combat: bool = true             # poza walką: twarzą w kierunek ruchu
@export var face_aim_in_combat: bool = true                      # w walce: twarzą do celownika

@export_group("Kamera (free-look, TPP)")
@export var camera_distance: float = 4.5
@export var camera_height: float = 1.7
@export_range(0.1, 1.0, 0.01) var mouse_sensitivity: float = 0.35
@export var camera_pitch_min_deg: float = -40.0
@export var camera_pitch_max_deg: float = 70.0
@export var invert_y: bool = false

@export_group("Responsywność")
@export var input_buffer_ms: int = 150          # bufor wejścia akcji
@export var aim_raycast_length: float = 200.0   # raycast z kamery przez crosshair
```

#### 8.5.5 `CharacterDefinition` (agregat)

```gdscript
class_name CharacterDefinition
extends Resource

## Pełna definicja konkretnej postaci gracza — zapisywana jako .tres w slocie zapisu.
## Trzyma WYŁĄCZNIE referencje po id + dane wyboru, nie logikę.
@export var character_name: String = ""
@export var race_id: StringName
@export var gender_id: StringName
@export var origin_id: StringName
@export var class_id: StringName

@export_group("Wygląd (rozwiązany wybór gracza)")
@export var appearance_preset_id: StringName     # bazowy preset
@export var skin_color: Color = Color.WHITE      # nadpisania suwakami w kreatorze
@export var hair_color: Color = Color.BLACK
@export var eye_color: Color = Color(0.3, 0.5, 0.7)
@export var height_scale: float = 1.0
@export var build_scale: float = 1.0

@export_group("Postęp")
@export var level: int = 1
@export var experience: int = 0

@export_group("Sterowanie")
@export var control_config_id: StringName = &"default"

## Walidacja przed użyciem (wywoływana przez Factory/SaveService).
func is_valid() -> bool:
    return race_id != StringName() and class_id != StringName() and origin_id != StringName()
```

### 8.6 Rejestr `ContentDB` — skanowanie `res://` i udostępnianie list

`ContentDB` to autoload, który przy starcie skanuje predefiniowane katalogi, ładuje wszystkie `.tres`, indeksuje je po polu `id` i waliduje. Kreator postaci oraz `CharacterFactory` pytają wyłącznie `ContentDB` — nigdy nie ładują plików po ścieżce.

**Struktura katalogów (konwencja):**

```
res://content/
  races/        *.tres  (RaceResource)
  classes/      *.tres  (ClassResource)
  origins/      *.tres  (OriginResource)
  genders/      *.tres  (GenderOption)
  appearances/  *.tres  (AppearanceResource)
  name_rules/   *.tres  (NameRuleSet)
  controls/     *.tres  (ControlConfig)
```

```gdscript
extends Node
## Autoload: ContentDB. Rejestr wszystkich zasobów treści, indeksowany po id.

# Mapa kategoria -> { id: StringName -> Resource }
var _registry: Dictionary = {}

const CATEGORIES := {
    "races":       "res://content/races/",
    "classes":     "res://content/classes/",
    "origins":     "res://content/origins/",
    "genders":     "res://content/genders/",
    "appearances": "res://content/appearances/",
    "name_rules":  "res://content/name_rules/",
    "controls":    "res://content/controls/",
}

func _ready() -> void:
    for category in CATEGORIES:
        _registry[category] = {}
        _scan_dir(category, CATEGORIES[category])
    _validate()

func _scan_dir(category: String, path: String) -> void:
    var dir := DirAccess.open(path)
    if dir == null:
        push_error("ContentDB: brak katalogu %s" % path)
        return
    for file in dir.get_files():
        # W eksporcie .tres mogą mieć sufiks .remap
        if not (file.ends_with(".tres") or file.ends_with(".tres.remap")):
            continue
        var clean := file.trim_suffix(".remap")
        var res: Resource = load(path + clean)
        if res == null or not ("id" in res) or res.id == StringName():
            push_error("ContentDB: zasób bez poprawnego id: %s" % (path + clean))
            continue
        if _registry[category].has(res.id):
            push_error("ContentDB: duplikat id '%s' w kategorii %s" % [res.id, category])
            continue
        _registry[category][res.id] = res

# --- API dla kreatora i Factory ---
func get_all(category: String) -> Array:
    return _registry.get(category, {}).values()

func get_by_id(category: String, id: StringName) -> Resource:
    return _registry.get(category, {}).get(id, null)

func get_classes_for_race(race_id: StringName) -> Array[ClassResource]:
    var race: RaceResource = get_by_id("races", race_id)
    var out: Array[ClassResource] = []
    if race == null:
        return out
    for c in get_all("classes"):
        if race.allowed_class_ids.is_empty() or race.allowed_class_ids.has(c.id):
            out.append(c)
    return out

# --- Walidacja referencji krzyżowych przy starcie ---
func _validate() -> void:
    for race in get_all("races"):
        if get_by_id("appearances", race.appearance_id) == null:
            push_error("Rasa '%s' wskazuje na nieistniejący appearance_id '%s'" % [race.id, race.appearance_id])
        if get_by_id("name_rules", race.name_rule_set_id) == null:
            push_error("Rasa '%s' wskazuje na nieistniejący name_rule_set_id '%s'" % [race.id, race.name_rule_set_id])
        for cid in race.allowed_class_ids:
            if get_by_id("classes", cid) == null:
                push_error("Rasa '%s' dopuszcza nieistniejącą klasę '%s'" % [race.id, cid])
```

Kreator postaci buduje listy bezpośrednio z API:

```gdscript
# Wypełnienie panelu wyboru rasy
for race: RaceResource in ContentDB.get_all("races"):
    _add_race_button(race.id, race.display_name, race.icon)

# Po wyborze rasy — przefiltrowane klasy
for cls: ClassResource in ContentDB.get_classes_for_race(selected_race_id):
    _add_class_button(cls.id, cls.display_name, cls.icon)
```

### 8.7 `CharacterFactory` — budowa postaci z definicji

Factory tłumaczy agregat `CharacterDefinition` na skonfigurowaną instancję sceny `Player`, wstrzykując dane do komponentów. To jedyne miejsce, które „składa" postać.

```gdscript
class_name CharacterFactory
extends RefCounted

const PLAYER_SCENE := preload("res://entities/player/Player.tscn")

static func build(def: CharacterDefinition) -> Node3D:
    assert(def.is_valid(), "CharacterDefinition niekompletne")

    var race: RaceResource     = ContentDB.get_by_id("races", def.race_id)
    var cls: ClassResource     = ContentDB.get_by_id("classes", def.class_id)
    var origin: OriginResource = ContentDB.get_by_id("origins", def.origin_id)
    var control: ControlConfig = ContentDB.get_by_id("controls", def.control_config_id)

    var player := PLAYER_SCENE.instantiate()

    # Kompozycja: wstrzyknięcie danych do komponentów
    player.get_node("StatsComponent").configure(race, cls, origin, def.level)
    player.get_node("ResourceComponent").configure(cls.resource_type, cls.resource_max_base, cls.resource_regen_per_sec)
    player.get_node("MovementComponent").configure(control)
    player.get_node("CombatComponent").configure(cls, control)         # host-authoritative
    player.get_node("AnimationComponent").configure(cls.animation_set_id)
    player.get_node("AppearanceComponent").apply(def, race)

    player.display_name = def.character_name
    return player
```

`StatsComponent.configure` realizuje pipeline `base -> flat -> increased% -> more`: bierze `base_*` z `ClassResource`, dodaje `flat_*` z `RaceResource`, a następnie mnożniki `increased_*_pct`.

### 8.8 Jak dodać nową treść (ZERO zmian w kodzie)

**Nowa rasa (np. siódma):**
1. Utwórz `res://content/races/nowa_rasa.tres` jako `RaceResource`, ustaw `id = &"nowa_rasa"`, `display_name`, ikonę, modyfikatory.
2. Wskaż istniejące lub nowe `appearance_id` i `name_rule_set_id`.
3. Uruchom grę — `ContentDB._ready()` automatycznie ją wykryje, zwaliduje i poda kreatorowi. Pojawia się w wyborze rasy bez dotykania GDScript.

**Nowa klasa:** utwórz `res://content/classes/nowa_klasa.tres`, ustaw `resource_type`, staty, `skill_tree_id`, `animation_set_id`. Gotowe — pojawi się w kreatorze (i przefiltruje się przez `allowed_class_ids` ras).

**Nowe pochodzenie:** utwórz `res://content/origins/nowe.tres`. Brak zmian w kodzie.

> Jedyne sytuacje wymagające kodu: wprowadzenie **całkowicie nowego TYPU danych** (nowy `class_name ... extends Resource`) lub **nowej kategorii** w `ContentDB.CATEGORIES`. Dodawanie kolejnych egzemplarzy istniejących typów jest czysto danymi.

### 8.9 System konfiguracji i walidacji (zasady)

| Reguła | Egzekwowana przez | Zachowanie przy naruszeniu |
|---|---|---|
| `id` niepuste i unikalne w kategorii | `ContentDB._scan_dir` | `push_error`, zasób pominięty |
| Referencje krzyżowe istnieją (appearance, name_rules, klasy) | `ContentDB._validate` | `push_error` przy starcie |
| Zakresy liczbowe (skale, kąty kamery) | `@export_range` w zasobie | ograniczone już w inspektorze |
| `CharacterDefinition` kompletne przed budową | `CharacterDefinition.is_valid()` + assert w Factory | przerwanie budowy |
| `resource_type` z dozwolonego zbioru (fury/mana/focus) | walidacja w `ResourceComponent.configure` | fallback + ostrzeżenie |

Walidacja działa **fail-fast w trybie deweloperskim** (błędy w konsoli przy starcie), co pozwala wychwycić literówki w `id` zanim trafią do gracza. W buildzie produkcyjnym brakujące/wadliwe zasoby są pomijane z logiem, a kreator pokazuje tylko poprawne pozycje.

### 8.10 Powiązanie ze sterowaniem (zapowiedź sekcji 7)

`ControlConfig` jest danymi wejściowymi dla `MovementComponent`, którego state machine realizuje docelowy model „face-movement + combat-aim": pola `face_movement_out_of_combat`, `face_aim_in_combat`, `turn_smoothing` i `turn_in_place_threshold_deg` parametryzują logikę facing opisaną w sekcji 7, bez zaszywania stałych w kodzie. Dzięki temu tuning responsywności i promienia skrętu jest edytowalny jako zasób, a profile sterowania (np. „klasyczny", „szybki") to po prostu kolejne pliki `.tres` w `res://content/controls/`.
