## 7. System sterowania postacią (TPP) — najwyższy priorytet

Ten rozdział definiuje rdzeń odczuwalnej jakości gry. Sterowanie musi być natychmiast responsywne, płynne i czytelne — na poziomie najlepszych action-MMO/action-RPG (GW2, BDO, ESO, FFXIV, New World). Wszystkie decyzje projektowe podporządkowane są trzem priorytetom: intuicyjność, płynność, responsywność. Model docelowy to **face-movement + combat-aim**: poza walką postać biegnie twarzą w kierunku ruchu, w walce orientuje się płynnie w stronę celownika (crosshair).

Definicje skrótów używanych w całym rozdziale:
- `cam_basis` — baza orientacji kamery (yaw) zrzutowana na płaszczyznę poziomą.
- `wish_dir` — znormalizowany wektor zamierzonego kierunku ruchu w przestrzeni świata.
- `aim_point` — punkt w świecie wyznaczony raycastem z kamery przez środek ekranu.
- `facing` — bieżący kąt yaw modelu postaci (obrót wokół osi Y).
- `dt` — `delta` z `_physics_process`.

---

### 7.1. Założenia ogólne i stany sterowania

System pracuje w jednym z dwóch trybów facingu, niezależnie od logiki ruchu (ruch zawsze jest względem kamery):

| Tryb | Warunek wejścia | Źródło docelowego facingu | Charakter ruchu |
|---|---|---|---|
| **Eksploracja** (`MODE_EXPLORE`) | Brak aktywnej akcji bojowej i poza `combat_lock_timer` | `wish_dir` (kierunek ruchu) | Postać biegnie zawsze przodem; „S" = obrót i bieg przodem w nowym kierunku |
| **Walka** (`MODE_COMBAT`) | Aktywny atak/skill **lub** wciśnięty modyfikator celowania (PPM) **lub** `combat_lock_timer > 0` | `aim_yaw` (kierunek do `aim_point`) | Możliwy strafe; postać zorientowana na cel, ruch boczny/cofanie zachowuje orientację na crosshair |

`combat_lock_timer` (domyślnie **1.5 s**) utrzymuje tryb walki przez krótki czas po ostatniej akcji bojowej, aby uniknąć ciągłego „przeskakiwania" między trybami podczas serii ataków. Każdy atak/skill/trafienie odświeża timer.

Kluczowa zasada: **ruch (velocity) i facing (rotacja) są rozdzielone.** Ruch zawsze liczony z `wish_dir` w bazie kamery. Tylko facing zmienia źródło docelowego kąta zależnie od trybu.

---

### 7.2. A) Ruch względem kamery 360°

Wejście z klawiszy mapujemy na dwuosiowy wektor wejścia `input_2d` (Vector2), a następnie rzutujemy go na bazę kamery zrzutowaną na płaszczyznę poziomą.

**Krok 1 — odczyt osi wejścia.** Korzystamy z `Input.get_vector` z deadzone, co od razu daje znormalizowany (z zachowaniem analogowej magnitudy gamepada) wektor i poprawnie obsługuje kombinacje:

```gdscript
# x: prawo(+)/lewo(-), y: tył(+)/przód(-) w konwencji ekranu
var input_2d: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
```

Kombinacje klawiszy są obsłużone automatycznie: W+D daje `(0.707, -0.707)`, S+A daje `(-0.707, 0.707)` itd. — pełne 360°. Dla klawiatury magnituda jest zawsze 0 lub 1 po normalizacji; dla gamepada zachowujemy analogowy zakres (chód/bieg progresywny).

**Krok 2 — baza kamery na płaszczyźnie.** Bierzemy wektory forward/right kamery i zerujemy ich składową Y, po czym normalizujemy. Dzięki temu pochylenie kamery (pitch) nie wpływa na kierunek ruchu po ziemi:

```gdscript
var cam_basis: Basis = camera.global_transform.basis
var cam_forward: Vector3 = -cam_basis.z   # Godot: -Z to "przód"
var cam_right: Vector3 = cam_basis.x
cam_forward.y = 0.0
cam_right.y = 0.0
cam_forward = cam_forward.normalized()
cam_right = cam_right.normalized()
```

**Krok 3 — wektor życzenia (wish_dir).** Łączymy osie. Uwaga na znak osi Z: w konwencji `Input.get_vector` `move_forward` zmniejsza `y`, więc `input_2d.y` ujemne = przód:

```gdscript
var wish_dir: Vector3 = (cam_right * input_2d.x) + (cam_forward * -input_2d.y)
if wish_dir.length() > 1.0:
    wish_dir = wish_dir.normalized()
var wish_strength: float = wish_dir.length()  # 0..1 dla blendu animacji
```

`wish_dir` jest teraz pełnym 360° kierunkiem w świecie, niezależnym od orientacji postaci. To on napędza zarówno prędkość (zawsze), jak i — w trybie eksploracji — docelowy facing.

---

### 7.3. B) Płynny obrót postaci

Postać nigdy nie „przeskakuje" na docelowy kąt — interpolujemy `facing` do `target_yaw` z wygładzaniem niezależnym od framerate'u.

**Metoda 1 — wykładnicze wygładzanie (zalecane, framerate-independent):**

```gdscript
var t: float = 1.0 - exp(-turn_sharpness * dt)   # turn_sharpness ~ 12.0..18.0
facing = lerp_angle(facing, target_yaw, t)
```

`lerp_angle` automatycznie wybiera krótszą drogę po okręgu (obsługa zawijania ±π), co eliminuje problem „dalekiej drogi" przy przejściu przez ±180°. Współczynnik `1 - exp(-k*dt)` gwarantuje identyczne odczucie przy 60 i 144 FPS.

**Metoda 2 — obrót ze stałą prędkością kątową z ograniczeniem (do turn-in-place i ostrych zwrotów):**

```gdscript
var diff: float = wrapf(target_yaw - facing, -PI, PI)
var max_step: float = deg_to_rad(turn_speed_deg) * dt   # turn_speed_deg ~ 540..720 °/s
facing += clampf(diff, -max_step, max_step)
```

W praktyce łączymy oba: wygładzanie wykładnicze dla „czucia", z twardym limitem prędkości kątowej, by uniknąć teleportacji przy ekstremalnych skokach inputu.

**Parametry (wartości startowe do tuningu):**

| Parametr | Wartość | Opis |
|---|---|---|
| `turn_sharpness` | 14.0 | Współczynnik k w `1-exp(-k*dt)`; wyżej = ostrzej |
| `turn_speed_deg` | 600 °/s | Twardy limit prędkości kątowej (bieg) |
| `turn_speed_combat_deg` | 900 °/s | Szybszy obrót na cel w walce |
| `turn_in_place_threshold` | 100° | Powyżej tej różnicy w bezruchu odpalamy Turn In Place |
| `align_move_threshold` | 45° | Powyżej tej różnicy postać zwalnia ruch, dopóki się nie „dopasuje" |

**Reakcja na input jest natychmiastowa:** `target_yaw` jest przeliczany w tym samym klatce, w której zmienia się input; jedynie wizualny obrót modelu jest wygładzany. Nigdy nie opóźniamy momentu, w którym `wish_dir` zaczyna napędzać prędkość.

---

### 7.4. C) Ruch do tyłu — bez backpedal

W trybie eksploracji nie ma cofania tyłem. Wciśnięcie **S** daje `wish_dir` skierowany „do gracza/za kamerę", a `target_yaw` ustawiamy na yaw tego wektora — postać płynnie obraca się ~180° i biegnie **przodem** w nowym kierunku.

```gdscript
if wish_strength > 0.01:
    target_yaw = atan2(wish_dir.x, wish_dir.z)   # yaw w stronę ruchu
```

**Unikanie „wirowania" (spinning) przy szybkich zmianach:**

Problem pojawia się, gdy gracz szybko stuka przeciwnymi kierunkami (np. naprzemiennie W i S) albo gdy `wish_dir` przeskakuje o niemal 180° — postać mogłaby zacząć kręcić się w kółko. Rozwiązania, stosowane łącznie:

1. **Próg dopasowania ruchu (`align_move_threshold`).** Gdy różnica między `facing` a `target_yaw` przekracza 45°, mnożymy prędkość przez współczynnik `align_factor` (np. 0.3–0.6), aż postać „dogoni" kierunek. Daje to naturalny łuk skrętu zamiast ślizgu bokiem:

```gdscript
var angle_err: float = absf(wrapf(target_yaw - facing, -PI, PI))
var align_factor: float = clampf(1.0 - (angle_err - deg_to_rad(align_move_threshold)) / PI, 0.3, 1.0)
velocity_planar *= align_factor
```

2. **Histereza / minimalny czas trzymania kierunku.** `target_yaw` aktualizujemy tylko gdy `wish_strength` przekracza próg; przy chwilowym puszczeniu klawiszy (przejście W→S) zachowujemy ostatni `target_yaw`, dopóki nowy input nie ustabilizuje się przez ~0.05 s (mały input buffer kierunku).

3. **Twardy limit prędkości kątowej** (`turn_speed_deg`) zapobiega obrotowi szybszemu niż naturalny — nawet przy natychmiastowym skoku inputu obrót trwa ~0.3 s dla 180°.

4. **Turn-in-place przy bezruchu** (patrz 7.5): jeśli gracz stoi i tylko zmienia kierunek patrzenia ruchem postaci, nie ślizga się, lecz odgrywa animację obrotu w miejscu.

---

### 7.5. Turn In Place (obrót w miejscu)

Gdy `wish_strength == 0` (postać stoi) a `target_yaw` różni się od `facing` o więcej niż `turn_in_place_threshold` (np. po wyjściu z walki, gdy facing był na cel, a teraz gracz chce ruszyć w bok), odpalamy stan `TurnInPlace`:

- Postać pozostaje w miejscu (brak velocity planarnego).
- Odgrywana jest animacja Turn-In-Place (lewo/prawo wg znaku różnicy), zsynchronizowana z obrotem `facing` limitowanym prędkością kątową.
- Po dopasowaniu kąta (`|diff| < 5°`) wraca do `Idle` lub przechodzi w `Start`/`Run`, jeśli pojawił się input ruchu.

W praktyce w trybie eksploracji turn-in-place rzadko jest potrzebny (gracz po prostu rusza i postać skręca w łuku), ale jest kluczowy dla czytelności przy wyjściu z walki i przy starcie z postojem.

---

### 7.6. D) Obrót w walce — orientacja na celownik

W `MODE_COMBAT` źródłem `target_yaw` nie jest kierunek ruchu, lecz kierunek do `aim_point`. Postać może swobodnie strafe'ować (ruch względem kamery działa identycznie), ale tułów/model są zorientowane na cel — to umożliwia atakowanie w jedną stronę przy ruchu w inną.

**Wyznaczenie aim_point (raycast z kamery przez środek ekranu):**

```gdscript
func get_aim_point() -> Vector3:
    var vp_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
    var ray_origin: Vector3 = camera.project_ray_origin(vp_center)
    var ray_dir: Vector3 = camera.project_ray_normal(vp_center)
    var ray_end: Vector3 = ray_origin + ray_dir * AIM_RAY_LENGTH   # 1000.0
    var space := get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
    query.collision_mask = AIM_MASK            # wrogowie + teren, bez własnego ciała
    query.exclude = [self.get_rid()]
    var hit := space.intersect_ray(query)
    if hit:
        return hit.position
    return ray_end                              # brak trafienia -> punkt w nieskończoności na promieniu
```

**Facing na cel (yaw, ignorujemy wysokość):**

```gdscript
var to_aim: Vector3 = aim_point - global_position
to_aim.y = 0.0
if to_aim.length() > 0.01:
    target_yaw = atan2(to_aim.x, to_aim.z)
```

**Kierunek obrażeń/pocisków = aim_point.** Pociski i hitscany lecą do `aim_point` (z punktu wylotu broni, nie ze środka postaci), więc trafienie jest dokładnie tam, gdzie crosshair. Dla pocisków kierunek liczymy `(aim_point - muzzle_pos).normalized()`. Dla ataków stożkowych/melee używamy `target_yaw` jako osi stożka. Combat jest host-authoritative: klient wysyła `aim_point` (lub kierunek) w momencie odpalenia, host waliduje i rozstrzyga trafienia.

Pionowe celowanie (góra/dół) załatwia pitch broni/animacji warstwą upper-body (addytywnie), bez wpływu na yaw lokomocji.

---

### 7.7. E) Kamera — free-look, stały crosshair

Kamera jest TPP, zza prawego barku, na sprężynie (`SpringArm3D`), ze stałym crosshair na środku ekranu.

**Hierarchia węzłów (zalecana):**

```
Player (CharacterBody3D)
└─ CameraPivot (Node3D)        # podąża za pozycją gracza (lerp pozycji), trzyma yaw+pitch kamery
   └─ SpringArm3D              # kolizyjne odsunięcie kamery (spring_length ~ 4.0)
      └─ Camera3D
```

- **Free-look:** mysz/prawa gałka sterują `CameraPivot.rotation.y` (yaw) i pitch (`SpringArm3D` lub osobny węzeł), z limitem pitch np. **−70°..+50°**. Poza walką kamera **nie wymusza** obrotu postaci — gracz może się rozglądać, a postać biegnie tam, dokąd wskazuje `wish_dir`.
- **Pozycja:** `CameraPivot.global_position` podąża za `player.global_position` z lekkim wygładzeniem (`lerp` pozycji, k ~ 20) i offsetem wysokości (cel ~ wysokość barków/głowy).
- **Stały crosshair:** statyczny element UI na środku; `aim_point` zawsze liczony przez ten punkt — niezależnie od trybu.

**Relacja kamera↔postać:**

| Aspekt | Eksploracja | Walka |
|---|---|---|
| Yaw kamery | Niezależny (free-look) | Niezależny (free-look) |
| Facing postaci | = kierunek ruchu (`wish_dir`) | = kierunek do `aim_point` (przez crosshair) |
| Wymuszanie obrotu postaci przez kamerę | Nie | Nie wprost — ale aim_point zależy od kamery, więc obracając kamerę zmieniasz cel |
| Czułość myszy | Standard | Można nieznacznie obniżyć przy precyzyjnym celowaniu (opcja) |

Opcjonalny **soft lock / lekki magnetyzm**: przy aktywnej walce można dodać drobną korektę aim do najbliższego wroga w stożku crosshaira (do rozważenia, domyślnie OFF — priorytet to czystość action-aim).

---

### 7.8. F) System animacji

Lokomocja i akcje bojowe rozdzielone na warstwy w `AnimationTree` (tryb AnimationNodeBlendTree z zagnieżdżonym StateMachine).

**Warstwy:**
1. **Base locomotion** — pełne ciało, sterowane prędkością i kierunkiem.
2. **Upper-body (addytywna)** — ataki, aim, kasty; nakładana addytywnie na lokomocję, by można było atakować w biegu/strafe. Maska kości od kręgosłupa w górę (spine→ręce→głowa).

**Base locomotion — blendspace:**
- W **eksploracji** postać zawsze biegnie przodem → wystarczy **BlendSpace1D** po `speed01` (0=Idle, 0.5=Walk, 1.0=Run/Sprint).
- W **walce** dochodzi strafe → **BlendSpace2D** (`move_forward`, `move_right` względem facingu postaci), dający 8-kierunkowy zestaw (Run F/B/L/R + diagonale) z poprawnym backpedal i strafe na cel.

Parametr kierunku do BlendSpace2D liczymy jako wektor ruchu w lokalnej przestrzeni postaci:

```gdscript
var local_move: Vector3 = global_transform.basis.inverse() * velocity_planar.normalized()
# local_move.z -> przód/tył, local_move.x -> bok; podajemy do BlendSpace2D
```

**State machine (lokomocja):**

```
Idle ──(input)──> Start ──> Run ──(speed up)──> Sprint
  ^                  │         │
  │                  v         v
  └──(no input)── Stop <──── (release)
Idle ──(|diff|>threshold & no input)──> TurnInPlace ──> Idle
(dowolny) ──(jump)──> Jump ──> Fall ──> Land ──> (Idle/Run)
```

| Stan | Wejście | Wyjście | Uwagi |
|---|---|---|---|
| Idle | `speed≈0` | input ruchu → Start | Może iść w TurnInPlace |
| Start | input z postoju | po ~0.15 s → Run | Krótka animacja ruszania (anti-pop) |
| Run | `speed01 > 0.5` | release → Stop; sprint → Sprint | BlendSpace prędkości |
| Sprint | `sprint` wciśnięty i ruch przód | release → Run | Większa prędkość, FOV +5° |
| Stop | release w biegu | → Idle | Krótkie wyhamowanie |
| TurnInPlace | bezruch + duża różnica yaw | po dopasowaniu → Idle | Sync z obrotem |
| Jump/Fall/Land | skok/spadanie | Land→Idle/Run | Coyote + jump buffer |

**Akcje (upper-body, OneShot/StateMachine addytywny):** Attack (combo 1/2/3), Skill_*, Dodge, Roll, Cast. Wyzwalane przez `OneShot` lub osobny mały StateMachine, nakładane na lokomocję. Dodge/Roll mogą tymczasowo przejąć root motion (patrz niżej).

**Root motion vs in-place:**

| Animacja | Tryb | Uzasadnienie |
|---|---|---|
| Walk/Run/Sprint | **In-place** | Prędkość steruje kod (responsywność, multiplayer, brak ślizgu kontrolowany przez dopasowanie animacji do velocity) |
| Idle/TurnInPlace | In-place (obrót kodem) | Pełna kontrola nad kątem |
| Dodge/Roll | **Root motion** | Dystans/krzywa unika muszą być spójne wizualnie; przewidywalny i deterministyczny dla hosta |
| Attack (melee z przemieszczeniem) | **Root motion** (opcjonalnie) | „Lunge" ataku — naturalne dosunięcie do celu |
| Jump/Land | In-place (fizyka kodem) | Łuk skoku liczony fizyką |

Przy root motion w multiplayer: host autorytatywnie odtwarza ruch z animacji i synchronizuje pozycję; klient predykuje.

---

### 7.9. G) Implementacja techniczna — odpowiedzi na 7 punktów

**1) Jak liczyć ruch względem kamery.** Patrz 7.2: `Input.get_vector` → `input_2d`; baza kamery z wyzerowanym Y → `cam_forward`/`cam_right`; `wish_dir = cam_right*x + cam_forward*(-y)`. Prędkość: `velocity_planar = wish_dir * current_speed`, gdzie `current_speed` rośnie/maleje z akceleracją (7.9.5). Ruch jest zawsze względem kamery, w obu trybach.

**2) Jak wyznaczać kierunek względem crosshaira (raycast).** Patrz 7.6: `project_ray_origin`/`project_ray_normal` ze środka viewportu → `PhysicsRayQueryParameters3D` z odpowiednią maską i `exclude=[self]` → `intersect_ray`. Wynik to `aim_point`; brak trafienia → punkt na końcu promienia. To jednocześnie `target_yaw` w walce i cel dla pocisków.

**3) Jak realizować płynny obrót.** Patrz 7.3: `lerp_angle(facing, target_yaw, 1-exp(-k*dt))` + twardy limit prędkości kątowej. `target_yaw` wybierany wg trybu. `facing` aplikowany do modelu (`mesh_root.rotation.y = facing`), nie do całego `CharacterBody3D` jeśli kolider ma być nieobracalny (kapsuła), albo do body jeśli kolider symetryczny.

**4) Jak połączyć sterowanie z animacjami.** Po obliczeniu velocity i facingu ustawiamy parametry `AnimationTree`:
```gdscript
anim_tree.set("parameters/locomotion/blend_position", speed01)            # 1D
# lub dla 2D w walce:
anim_tree.set("parameters/locomotion2d/blend_position", Vector2(local_move.x, -local_move.z))
anim_tree.set("parameters/conditions/moving", wish_strength > 0.01)
```
Stany (Start/Stop/Jump/Turn) sterowane warunkami i sygnałami; akcje przez `OneShot` (`anim_tree.set("parameters/attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)`).

**5) Jak uniknąć sztywnego/drewnianego sterowania.**
- **Akceleracja/decel:** `current_speed` interpolowana do docelowej (`accel ~ 25 m/s²`, `decel ~ 35 m/s²`), zamiast skoku 0→max.
- **Promień skrętu:** dopasowanie ruchu (`align_factor`, 7.4) tworzy łuk zamiast natychmiastowego strafe.
- **Blendy animacji:** Start/Stop, blendspace prędkości, addytywna warstwa upper-body — brak „pop" przy zmianach stanu.
- **Input buffer:** akcje (atak, skill, dodge, jump) buforowane ~0.15 s — naciśnięcie tuż przed końcem poprzedniej akcji odpala się natychmiast po jej zakończeniu.
- **Coyote time:** ~0.12 s po zejściu z krawędzi skok wciąż możliwy.
- **Jump buffer:** ~0.12 s przed lądowaniem — skok wykona się od razu po dotknięciu ziemi.

**6) Jak zaimplementować w Godot 4.**
- Węzeł gracza: `CharacterBody3D` z `CollisionShape3D` (kapsuła).
- Model: `Node3D mesh_root` (obracany `facing`) → `Skeleton3D` + `AnimationPlayer` + `AnimationTree`.
- Kamera: `CameraPivot (Node3D)` → `SpringArm3D` → `Camera3D` (poza hierarchią obrotu modelu, by free-look nie obracał postaci).
- Cała logika w `_physics_process(delta)`: odczyt inputu → `wish_dir` → tryb → `target_yaw` → obrót → prędkość → `move_and_slide()` → update `AnimationTree`.
- Free-look myszy w `_input` (akumulacja yaw/pitch pivotu).
- Autoload `InputModeManager` (opcjonalnie) do przełączania bindów MKB/gamepad i czułości.

**7) Pseudokod / przykładowy GDScript.**

```gdscript
extends CharacterBody3D

@export var camera_pivot: Node3D
@export var camera: Camera3D
@export var mesh_root: Node3D

# --- parametry ---
const WALK_SPEED := 3.0
const RUN_SPEED := 6.0
const SPRINT_SPEED := 9.0
const ACCEL := 25.0
const DECEL := 35.0
const GRAVITY := 22.0
const JUMP_VELOCITY := 8.0

const TURN_SHARPNESS := 14.0
const TURN_SPEED := deg_to_rad(600.0)
const TURN_SPEED_COMBAT := deg_to_rad(900.0)
const TURN_IN_PLACE_THRESHOLD := deg_to_rad(100.0)
const ALIGN_THRESHOLD := deg_to_rad(45.0)

const AIM_RAY_LENGTH := 1000.0
const AIM_MASK := 0b110   # warstwy: teren + wrogowie
const COMBAT_LOCK := 1.5
const ACTION_BUFFER := 0.15
const COYOTE := 0.12

var facing := 0.0
var current_speed := 0.0
var combat_lock_timer := 0.0
var action_buffer_timer := 0.0
var coyote_timer := 0.0
var aim_point := Vector3.ZERO

func _physics_process(dt: float) -> void:
    _update_timers(dt)

    # --- 1) wish_dir względem kamery ---
    var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var cb := camera.global_transform.basis
    var fwd := Vector3(-cb.z.x, 0, -cb.z.z).normalized()
    var rgt := Vector3(cb.x.x, 0, cb.x.z).normalized()
    var wish_dir := (rgt * input_2d.x) + (fwd * -input_2d.y)
    var wish_strength := clampf(wish_dir.length(), 0.0, 1.0)
    if wish_strength > 0.001:
        wish_dir = wish_dir.normalized()

    # --- 2) aim point z crosshaira ---
    aim_point = _get_aim_point()

    # --- tryb ---
    var in_combat := combat_lock_timer > 0.0 or Input.is_action_pressed("aim")

    # --- 3) wyznacz target_yaw wg trybu ---
    var has_move := wish_strength > 0.01
    var target_yaw := facing
    var do_turn_in_place := false

    if in_combat:
        var to_aim := aim_point - global_position
        to_aim.y = 0.0
        if to_aim.length() > 0.01:
            target_yaw = atan2(to_aim.x, to_aim.z)
    else:
        if has_move:
            target_yaw = atan2(wish_dir.x, wish_dir.z)   # bieg przodem (także "S")
        else:
            # bezruch: ewentualny turn-in-place jeśli duża różnica
            var diff_idle := absf(wrapf(target_yaw - facing, -PI, PI))
            if diff_idle > TURN_IN_PLACE_THRESHOLD:
                do_turn_in_place = true

    # --- 4) płynny facing z limitem prędkości kątowej ---
    var max_step := (TURN_SPEED_COMBAT if in_combat else TURN_SPEED) * dt
    var smoothed := lerp_angle(facing, target_yaw, 1.0 - exp(-TURN_SHARPNESS * dt))
    var step := wrapf(smoothed - facing, -PI, PI)
    facing += clampf(step, -max_step, max_step)
    mesh_root.rotation.y = facing

    # --- 5) prędkość (akceleracja) + dopasowanie kierunku (anti-spin) ---
    var target_speed := 0.0
    if has_move:
        target_speed = SPRINT_SPEED if Input.is_action_pressed("sprint") and not in_combat else RUN_SPEED
    var rate := ACCEL if target_speed > current_speed else DECEL
    current_speed = move_toward(current_speed, target_speed, rate * dt)

    var planar := wish_dir * current_speed
    if not in_combat and has_move:
        var ang_err := absf(wrapf(target_yaw - facing, -PI, PI))
        if ang_err > ALIGN_THRESHOLD:
            planar *= clampf(1.0 - (ang_err - ALIGN_THRESHOLD) / PI, 0.35, 1.0)

    velocity.x = planar.x
    velocity.z = planar.z

    # --- grawitacja / skok z coyote + buffer ---
    if is_on_floor():
        coyote_timer = COYOTE
        if _consume_jump_buffer():
            velocity.y = JUMP_VELOCITY
    else:
        velocity.y -= GRAVITY * dt

    move_and_slide()

    # --- 6) update AnimationTree ---
    _update_anim(wish_strength, in_combat, do_turn_in_place)

func _get_aim_point() -> Vector3:
    var center := get_viewport().get_visible_rect().size * 0.5
    var origin := camera.project_ray_origin(center)
    var dir := camera.project_ray_normal(center)
    var space := get_world_3d().direct_space_state
    var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * AIM_RAY_LENGTH)
    q.collision_mask = AIM_MASK
    q.exclude = [get_rid()]
    var hit := space.intersect_ray(q)
    return hit.position if hit else origin + dir * AIM_RAY_LENGTH

func notify_combat_action() -> void:   # wołane przy ataku/skillu/trafieniu
    combat_lock_timer = COMBAT_LOCK
```

Funkcje pomocnicze (`_update_timers`, `_consume_jump_buffer`, `_update_anim`) realizują logikę z punktów 7.8 i 7.9.5.

---

### 7.10. Tabela bindów

**Mysz + klawiatura:**

| Wejście | Akcja |
|---|---|
| W / S / A / D | Ruch przód / „tył" (obrót+bieg) / lewo / prawo (360° względem kamery) |
| Mysz (ruch) | Free-look kamery (yaw/pitch), pozycja crosshaira |
| Lewy przycisk myszy (LPM) | Atak podstawowy / combo (kierunek = crosshair) |
| Prawy przycisk myszy (PPM) | Celowanie / blok / atak alternatywny (modyfikator trybu walki) |
| Spacja | Skok (coyote + jump buffer) |
| Shift (lewy) | Sprint (tylko eksploracja, ruch do przodu) |
| Ctrl (lewy) / C | Unik (Dodge) / przewrót (Roll) |
| 1–6 | Umiejętności klasowe (skille) |
| Q / E | Skille pomocnicze / dodatkowe |
| R | Interakcja / przeładowanie zasobu klasy |
| Tab | Cel/lock najbliższego wroga (opcjonalny soft-lock) |
| F | Interakcja ze światem (loot, NPC) |
| Scroll myszy | Zoom kamery (dystans springa) |
| Esc | Menu |

**Gamepad (układ Xbox):**

| Wejście | Akcja |
|---|---|
| Lewa gałka | Ruch 360° względem kamery |
| Prawa gałka | Free-look kamery / pozycja crosshaira |
| A | Skok |
| Lewy spust LT | Celowanie / tryb walki (modyfikator) |
| Prawy spust RT | Atak podstawowy / combo |
| RB / LB | Skille (modyfikator + face buttons) |
| X / Y / B | Skille / interakcja / unik (konfigurowalne) |
| Naciśnięcie lewej gałki (L3) | Sprint |
| Naciśnięcie prawej gałki (R3) | Lock celu (soft-lock) |
| D-pad | Quickslot / przedmioty |
| Start | Menu |

Czułość, inwersja osi pitch i deadzone gałek konfigurowalne w ustawieniach. Mapy akcji zdefiniowane w Input Map projektu pod nazwami (`move_*`, `aim`, `attack`, `sprint`, `dodge`, `jump`, `skill_1..6`), co pozwala bindować MKB i gamepad do tych samych akcji.

---

### 7.11. Migracja z obecnego kodu (Player.gd)

Obecny `Player.gd` używa modelu **always-face-camera (strafe):** postać jest stale obracana tak, by patrzeć zgodnie z kamerą (yaw postaci = yaw kamery), a ruch jest względem kamery (to zostaje bez zmian). Docelowo wdrażamy **face-movement + combat-aim**.

**Co zostaje (NIE ruszać):**
- Cała logika liczenia `wish_dir` względem kamery (sekcja 7.2) — ten fragment jest już poprawny.
- Liczenie `velocity` z `wish_dir` i `move_and_slide()`.
- Raycast z kamery przez środek ekranu do celowania (jeśli już istnieje) — używany do `aim_point`.

**Co zmienić — DOKŁADNIE gałąź facingu w `_process`/`_physics_process`.** Obecnie jest tam (lub odpowiednik):

```gdscript
# STARY KOD — always-face-camera (strafe):
var cam_yaw := camera_pivot.rotation.y
mesh_root.rotation.y = lerp_angle(mesh_root.rotation.y, cam_yaw, turn_speed * delta)
```

Zastąp to rozgałęzieniem na tryb (eksploracja vs walka), zachowując `wish_dir` i celowanie:

```gdscript
# NOWY KOD — face-movement + combat-aim:
var in_combat := combat_lock_timer > 0.0 or Input.is_action_pressed("aim")
var has_move := wish_strength > 0.01
var target_yaw := facing

if in_combat:
    # walka: orientacja na crosshair (aim_point liczony z istniejącego raycastu)
    var to_aim := aim_point - global_position
    to_aim.y = 0.0
    if to_aim.length() > 0.01:
        target_yaw = atan2(to_aim.x, to_aim.z)
elif has_move:
    # eksploracja w ruchu: twarz w kierunku ruchu (obejmuje "S" = obrót 180° i bieg przodem)
    target_yaw = atan2(wish_dir.x, wish_dir.z)
else:
    # bezruch: trzymaj ostatni facing; ewentualnie turn-in-place przy dużej różnicy
    target_yaw = facing

# płynny obrót (jak dotąd, ale do target_yaw zamiast cam_yaw):
facing = lerp_angle(facing, target_yaw, 1.0 - exp(-TURN_SHARPNESS * delta))
mesh_root.rotation.y = facing
```

**Kluczowe punkty migracji:**
1. Zmienna źródłowa obrotu zmienia się z `camera_pivot.rotation.y` na `target_yaw` wybierany warunkowo — to jedyna „rdzenna" zmiana.
2. Dodaj pole `combat_lock_timer` i wołaj `notify_combat_action()` w miejscach odpalania ataku/skilla/otrzymania trafienia, aby tryb walki utrzymywał się przez `COMBAT_LOCK` sekund.
3. Upewnij się, że obracasz **`mesh_root`**, a nie `camera_pivot` — kamera musi pozostać free-look i niezależna od facingu postaci.
4. Ruch (`velocity` z `wish_dir`) pozostaje nietknięty — dzięki temu strafe w walce działa od ręki (postać patrzy na cel, lecz porusza się względem kamery).
5. Dodaj dopasowanie kierunku (`align_factor`, 7.4) tylko w gałęzi eksploracji, aby uniknąć wirowania przy „S" i ostrych zwrotach.
6. Zamień ewentualny BlendSpace1D na BlendSpace2D w warstwie lokomocji dla trybu walki (strafe/backpedal), zostawiając 1D dla eksploracji — albo użyj jednego 2D z `local_move` (7.8).

Po tej zmianie: poza walką postać biegnie zawsze przodem w kierunku ruchu (w tym płynny obrót przy „S"), w walce orientuje się na crosshair i może strafe'ować, a celowanie i ruch względem kamery pozostają nienaruszone.
