extends CharacterBody3D
## Player.gd — sterowalna postać 3rd-person + kamera orbitalna + RDZEŃ WALKI (ETAP 3, R1).
##
## Sterowanie czytamy bezpośrednio z klawiszy (Input.is_physical_key_pressed),
## żeby prototyp działał bez konfigurowania mapy wejść w edytorze. Później
## przejdziemy na "Input Actions" (czytelniejsze i konfigurowalne przez gracza).
##
## ETAP 3 / RUNDA 1: dołożony rdzeń walki — atak (LMB), unik z i-frames (RMB / Q),
## HP + stamina, combo→przebicie pancerza, take_damage/śmierć/respawn, błysk i knockback,
## sygnały dla HUD. Wszystko współgra z istniejącymi pętlami:
##   _unhandled_input — mysz/kamera + ESC + KLIK LMB/RMB (walka),
##   _process         — WIZUALE: obrót modelu, chód, ANIMACJA ZAMACHU (flaga is_attacking),
##   _physics_process — fizyka: grawitacja, ruch, dash, LICZNIKI czasu walki, move_and_slide.

@export var speed: float = 6.0            # prędkość chodu (m/s)
@export var sprint_speed: float = 10.0    # prędkość biegu (shift)
@export var jump_velocity: float = 7.0    # siła skoku
@export var mouse_sensitivity: float = 0.0025
## ETAP 8: bazowa czulosc myszy (rad/px). mouse_sensitivity = MOUSE_SENS_BASE * mnoznik z GameSettings.
## Trzymamy baze osobno, by suwak ustawien mogl skalowac czulosc bez gubienia wartosci domyslnej.
const MOUSE_SENS_BASE: float = 0.0025

# ============================================================================
#  STATYSTYKI WALKI (ETAP 3) — eksporty do łatwego strojenia w inspektorze
# ============================================================================

# --- ZDROWIE ---
@export var max_hp: float = 100.0
var hp: float = 100.0                            # publiczne (HUD/wrogowie czytają)

# --- STAMINA ---
@export var max_stamina: float = 100.0
@export var stamina_regen: float = 22.0          # punkty/s, regeneracja
@export var stamina_regen_delay: float = 0.6     # s ciszy po wydatku, zanim rusza regen
@export var dodge_stamina_cost: float = 25.0
@export var sprint_stamina_cost: float = 12.0    # punkty/s podczas biegu
var stamina: float = 100.0                       # publiczne (HUD czyta)
var _stamina_idle: float = 0.0                   # licznik czasu od ostatniego wydatku

# --- ATAK ---
@export var attack_damage: float = 18.0
@export var attack_range: float = 2.2            # m, promień rażenia
@export var attack_arc_dot: float = 0.3          # próg dot() = łuk ~±72° (czyli ~145° z przodu)
@export var attack_cooldown: float = 0.45        # s między zamachami
@export var attack_anim_time: float = 0.28       # s trwania animacji zamachu
var _attack_cd: float = 0.0                      # ile zostało do następnego ciosu
var _attack_anim_t: float = 0.0                  # postęp animacji (>0 = trwa)
var is_attacking: bool = false                   # FLAGA: blokuje chód-anim na rękach

# ============================================================================
#  FAZA 1 (FEEL) — ATTACK TIMELINE (ANTICIPATION -> ACTIVE -> RECOVERY)
# ============================================================================
# Kazdy cios ma 3 fazy. Hitbox NIE otwiera sie w klatce 0 — dopiero po ANTICIPATION (wind-up):
#   ANTICIPATION (~0.06 s): hitbox ZAMKNIETY, model cofa/dipuje rece (czytelny zamach -> "impact"),
#   ACTIVE       (~0.10 s): hitbox OTWARTY (DamageService liczy trafienia),
#   RECOVERY     (~0.18 s): hitbox zamkniety, CANCELABLE — w unik ZAWSZE, w nastepny cios w oknie.
# Czasy biora sie z SkillResource (anticipation/active/recovery/cancel_window) z eksportowymi
# fallbackami ponizej. Timeline tyka w _physics_process (_tick_attack_timeline). To jedyne zrodlo
# otwarcia/zamkniecia okna ataku — _perform_skill TYLKO STARTUJE timeline (nie otwiera hitboxa wprost).
enum AtkPhase { NONE, ANTICIPATION, ACTIVE, RECOVERY }
@export var attack_anticipation: float = 0.06    # s wind-upu (hitbox zamkniety) — fallback gdy skill=0
@export var attack_active: float = 0.10          # s aktywnych klatek (hitbox otwarty) — fallback
@export var attack_recovery: float = 0.18        # s recovery (cancelable) — fallback
@export var attack_cancel_window: float = 0.12   # s w recovery na cancel-into-next (okno combo)
var _atk_phase: int = AtkPhase.NONE              # biezaca faza timeline'u ataku
var _atk_phase_t: float = 0.0                    # czas pozostaly w biezacej fazie (s)
var _atk_forward: Vector3 = Vector3.ZERO         # kierunek przodu ciosu (do otwarcia hitboxa w ACTIVE)
var _atk_anticipation: float = 0.06              # zapamietane czasy biezacego ciosu (z SkillResource)
var _atk_active: float = 0.10
var _atk_recovery: float = 0.18
var _atk_cancel_window: float = 0.12
var _atk_index: int = 0                          # ktory cios w lancuchu (1/2/3) — do juice 3. ciosu

# --- COMBO / PRZEBICIE PANCERZA (sygnatura systemu) ---
@export var combo_window: float = 1.2            # s na kontynuację combo po trafieniu
@export var armor_pierce_per_combo: float = 0.15
@export var armor_pierce_max: float = 0.8
# FAZA 1: lancuch 3-ciosowy. _chain_step 0->1->2->3 (3=finisher serii: mocniejszy hitstop/shake/
# knockback). Reset gdy okno cancel/combo wygasnie LUB po wykonaniu 3. ciosu. NIEZALEZNE od
# _combo_count (przebicie pancerza), ale 3. cios dorzuca premie. _chain_queued = cancel-into-next
# zakolejkowany w oknie recovery (input buffer + cancel window).
const ATTACK_CHAIN_MAX: int = 3
var _combo_count: int = 0
var _combo_timer: float = 0.0                    # odlicza okno combo; 0 = reset
var _chain_step: int = 0                         # 0=brak serii, 1..3 = ktory cios w lancuchu
var _chain_queued: bool = false                  # cancel-into-next zakolejkowany w recovery

# --- UNIK (dash) ---
@export var dodge_speed: float = 16.0            # m/s zrywu
@export var dodge_time: float = 0.22             # s trwania zrywu
@export var dodge_iframes: float = 0.30          # s nietykalności (lekko dłużej niż dash)
@export var dodge_cooldown: float = 0.55         # s między unikami
# FAZA 1: po zrywie krotkie RECOVERY (~0.12 s) — postac "laduje" z uniku. Cancelable ATAKIEM (agresja
# po uniku = nagroda), ale nie ruchem (lekkie wyhamowanie daje wage). i-frames/perfect-dodge bez zmian.
@export var dodge_recovery: float = 0.12         # s recovery po dashu (cancelable atakiem)
var _dodge_t: float = 0.0                        # >0 = trwa dash
var _dodge_recovery_t: float = 0.0               # >0 = trwa recovery po dashu (cancelable atakiem)
var _dodge_cd: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var is_dodging: bool = false

# --- I-FRAMES (nietykalność: unik + po respawnie) ---
var _iframes: float = 0.0                        # s pozostałej nietykalności

# --- RESPAWN ---
@export var respawn_iframes: float = 1.5
var respawn_point: Vector3 = Vector3.ZERO        # ustawiany w _ready() na pozycji startu (i przez Main)
var is_dead: bool = false

# --- KNOCKBACK (gasnący wektor doliczany do ruchu poziomego) ---
var _knockback: Vector3 = Vector3.ZERO

# --- BŁYSK TRAFIENIA (emisja na modelu) ---
var _flash_tween: Tween                          # trzymamy referencję, żeby ubić poprzedni błysk

# --- UNIK z klawiatury (debounce dla KEY_Q) ---
var _q_was_down: bool = false

# --- SYGNAŁY dla HUD i logiki śmierci (HUD podłącza się w Main) ---
signal hp_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal combo_changed(count: int)        # NOWY: HUD pokazuje "Combo xN" (osobna etykieta)
signal died()
signal respawned()

# Grawitacja brana z ustawień projektu (project.godot -> physics/3d/default_gravity).
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)

var _pivot: Node3D        # obrót poziomy kamery (yaw)
var _spring: SpringArm3D  # ramię kamery: pochylenie (pitch) + shapecast kolizji (TYLKO pomiar dystansu)
var _camera: Camera3D
# KAMERA: sami sterujemy długością ramienia (boom) zamiast skokowego auto-pozycjonowania SpringArm —
# eliminuje to dawne DRGANIA (SpringArm ustawiał camera.z, a bob/shake nadpisywał z=0 → bicie fizyka↔render)
# i daje łagodny zoom na zboczu (asymetryczne wygładzanie w _update_camera).
var _cam_dist: float = 5.6            # bieżąca (wygładzona) długość ramienia kamery
var _cam_off: Vector3 = Vector3.ZERO  # wygładzony offset x/y kamery (bob+shake); boom-Z liczony osobno

# Model i pivoty kończyn (zawiasy bark/biodro) — animacja chodu + obrót w kierunku ruchu.
# KOŃCZYNY 2-SEGMENTOWE: górny pivot (bark/biodro) trzyma dolny pivot (łokieć/kolano)
# zagnieżdżony, więc rotation.x dolnego zgina kończynę w stawie. Górny segment (ramię/udo)
# wisi pod górnym pivotem; dolny segment (przedramię+dłoń / łydka+but) pod dolnym pivotem.
var _model: Node3D            # cały model (obrót yaw w kierunku ruchu)
var _torso: Node3D            # tułów+głowa razem — dla body-bob / lean / twist
var _head: Node3D             # sama głowa — stabilizacja/oscylacja niezależna od tułowia
var _arm_l: Node3D            # pivot barku L
var _arm_r: Node3D            # pivot barku R
var _arm_l_lo: Node3D         # pivot łokcia L (dziecko _arm_l)
var _arm_r_lo: Node3D         # pivot łokcia R (dziecko _arm_r)
var _leg_l: Node3D            # pivot biodra L
var _leg_r: Node3D            # pivot biodra R
var _leg_l_lo: Node3D         # pivot kolana L (dziecko _leg_l)
var _leg_r_lo: Node3D         # pivot kolana R (dziecko _leg_r)
var _walk_phase: float = 0.0
# Stan animacji proceduralnej (frame-rate independent, wygładzane lerpami).
var _idle_phase: float = 0.0  # niezależny zegar dla oddychania/weight-shift w idle
var _anim_bob: float = 0.0    # bieżący pionowy bob tułowia (m), wygładzany
var _land_squash: float = 0.0 # 0..1 chwilowy „przysiad" przy lądowaniu, gaśnie
# FAZA 2 — warstwy ADDITIVE (czysto wizualne, frame-rate independent, nakladane PO bazie locomocji).
var _breath_phase: float = 0.0      # zegar oddechu (biegnie zawsze, jak _idle_phase)
var _stretch: float = 0.0           # squash/stretch pionowy: <0 zgniecenie, >0 rozciagniecie (wygladzany)
var _stretch_target: float = 0.0    # cel stretcha liczony per stan/faza
# secondary motion — spring 1-stopniowy (kat+predkosc) na akcencie, lag za bazowa rotacja rodzica
var _hair_ang: float = 0.0;  var _hair_vel: float = 0.0      # grzywka/wlosy (pitch, lokalny do _head)
var _wpn_ang: float = 0.0;   var _wpn_vel: float = 0.0       # bron/dlon (lag za _arm_r)
var _cape_ang: float = 0.0;  var _cape_vel: float = 0.0      # peleryna (pitch za tulowiem)
var _prev_torso_x: float = 0.0      # do liczenia predkosci katowej tulowia (driver springow)
var _prev_head_x: float = 0.0       # do liczenia predkosci katowej glowy (driver grzywki)
var _prev_arm_r_x: float = 0.0      # do liczenia predkosci ramienia (driver springu broni)
# FRAME-RATE INDEPENDENCE: nakladki rotacji additive (oddech/atak-twist/hit-react) sa NIE-KUMULACYJNE.
# Trzymamy nakladke z poprzedniej klatki, zdejmujemy ja PRZED smootherami bazowymi (_animate_torso/
# _animate_head czytaja wlasne rotation w lerp), liczymy swieza i nakladamy raz. Bez tego oscylujaca
# nakladka wsiakala w lerp bazy => amplituda rosla z FPS (sway/nod ~3x ciezsze @120fps niz @30fps).
var _add_torso: Vector3 = Vector3.ZERO   # nakladka additive na _torso.rotation (zdejmowana co klatke)
var _add_head: Vector3 = Vector3.ZERO    # nakladka additive na _head.rotation (zdejmowana co klatke)
# hit-react additive (gracz) — wzbogacenie o zachwianie tulowia/glowy ~0.12 s
var _hitreact_t: float = 0.0        # pozostaly czas (s)
var _hitreact_dir: Vector3 = Vector3.ZERO   # kierunek OD zrodla (XZ, swiatowy)
const HITREACT_TIME: float = 0.12
# death (poza przewrocenia)
var _death_t: float = 0.0           # postep pozy smierci (0->1 narasta)
var _dying: bool = false
# nowe wezly-segmenty dla secondary motion (pivoty doczepiane w _build_voxel_character)
var _hair: Node3D            # pivot grzywki (dziecko _head)
var _weapon: Node3D          # pivot broni/dloni (dziecko _arm_r_lo)
var _cape: Node3D            # pivot peleryny (dziecko _torso)
# Dodatkowy stan dla NATURALNEJ animacji (wygładzane „blend weights" 0..1 i fazy).
var _gait: float = 0.0        # 0=idle/stoi, 1=pełny chód — wygładzona „siła" lokomocji (anti-pop)
var _run_blend: float = 0.0   # 0=chód, 1=bieg — wygładzone przejście chód<->bieg (amplitudy/tempo)
var _air_blend: float = 0.0   # 0=na ziemi, 1=w powietrzu — wygładza wejście/wyjście z pozy lotu
# Wspólny próg prędkości wejścia w lokomocję (nogi) i startu narastania _gait — JEDNO źródło,
# by nogi i tułów/głowa zaczynały „chodzić" razem (bez rozjazdu progów).
const _LOCO_MIN_SPEED: float = 0.4
# ============================================================================
#  PARAMETRY PROPORCJI POSTACI (STROJENIE WIZUALNE — ZMIENIAJ TYLKO LICZBY)
# ============================================================================
# To JEDYNE miejsce, gdzie definiujemy budowę sylwetki. Cała geometria (_sculpt_*)
# i wszystkie pivoty wyliczają się z tych nazwanych eksportów — integrator może
# stroić proporcje zmieniając wartości BEZ przepisywania logiki budowy.
#
# Jednostka: VOXEL (całkowity, oś Y od stóp y=0). Skala metryczna VS jest WYLICZANA
# z P_HEIGHT_M / P_HEIGHT_VOX, więc model trzyma realny wzrost niezależnie od siatki.
# Kierunek wzroku: -Z (twarz z przodu). x = lewo(-)/prawo(+) widza.
#
# CEL: zgrabny bohater „pośredni" (między chibi a realizmem) — ~1,8 m, ~4,5 głowy
# wysokości, głowa UMIARKOWANA, smukły tułów, proporcjonalne kończyny.
@export_group("Proporcje postaci")
@export var P_HEIGHT_M: float = 1.80          # docelowy wzrost w metrach (świat 0,5 m/voxel)
@export var P_HEIGHT_VOX: int = 36            # pełna wysokość modelu w voxelach (czubek włosów)
                                              # NADPISYWANE w _compute_proportions realną sumą (auto=37);
                                              # 37 vox / ~8-voxelowa renderowana głowa ≈ 4,6 „głowy" — pośrednie

# --- GŁOWA (umiarkowana, NIE chibi) ---
# CEL pomiarowy (zweryfikowany sondą AABB): renderowana głowa (czaszka+włosy) ~= 0,21 wzrostu
# => ~4,8 „głowy"; czaszka WĘŻSZA od barków (head_w/shoulder_w ~0,64). Stąd niższa i smuklejsza
# czaszka + nieco szersze barki (P_SHOULDER_W=11), co dodatkowo wyszczupla głowę w sylwetce.
@export var P_HEAD_H: int = 7                 # wysokość czaszki+twarzy (voxele) — „1 głowa" = jednostka proporcji
@export var P_HEAD_W: int = 7                 # szerokość głowy (nieparzysta => symetria wokół x=0; < barków)
@export var P_HEAD_D: int = 6                 # głębokość głowy
@export var P_HAIR_TOP: int = 1               # ile voxeli czapy włosów STERCZY ponad czaszkę

# --- SZYJA ---
@export var P_NECK_H: int = 2                 # wysokość szyi (voxele) — łączy głowę z barkami
@export var P_NECK_W: int = 3                 # szerokość szyi (smukła)

# --- TUŁÓW (smukły, lekka klepsydra) ---
@export var P_TORSO_H: int = 11               # wysokość tułowia (pas -> nasada szyi)
@export var P_SHOULDER_W: int = 11            # szerokość barków (najszerszy punkt korpusu, nieparzysta)
                                              # head_w(7)/shoulder_w(11) ≈ 0,64 => smukła głowa, heroiczne barki
@export var P_WAIST_W: int = 7                # szerokość w pasie (< barków => talia)
@export var P_TORSO_D: int = 5                # głębokość tułowia (przód-tył)

# --- NOGI (2 segmenty: udo + łydka/but) ---
@export var P_THIGH_H: int = 8                # długość uda (biodro -> kolano)
@export var P_SHIN_H: int = 6                 # długość łydki (kolano -> kostka, nad butem)
@export var P_FOOT_H: int = 2                 # wysokość buta (kostka -> podeszwa y=0)
@export var P_LEG_W: int = 3                  # szerokość nogi (voxele)
@export var P_LEG_GAP: int = 1                # przerwa między nogami (od osi do wewn. krawędzi: P_LEG_GAP)
@export var P_FOOT_FWD: int = 2               # o ile but wystaje w przód (-Z, palce)

# --- RĘCE (2 segmenty: ramię + przedramię/dłoń) ---
# Dłuższe niż dawniej: na wiarygodnym bohaterze palce sięgają ~połowy uda (poniżej pasa),
# a nie kończą się na linii bioder. Dół dłoni ląduje ~vox 11-12 (między kolanem=8 a biodrem=16).
@export var P_UARM_H: int = 7                 # długość ramienia (bark -> łokieć)
@export var P_FARM_H: int = 8                 # długość przedramienia+dłoni (łokieć -> palce)
@export var P_ARM_W: int = 3                  # szerokość ręki (smuklejsza od nogi lub równa)
@export var P_ARM_GAP: int = 0               # odstęp ręki od boku tułowia (0 = tuż przy barku)

# --- GŁĘBOKOŚĆ KOŃCZYN (wspólna dla rąk i nóg) ---
@export var P_LIMB_D: int = 3                 # głębokość (oś Z) kończyn — lekko > szer. = owalny przekrój

# ----------------------------------------------------------------------------
#  WYLICZONE wysokości pivotów + skala (NIE strój ręcznie — liczone z parametrów).
#  Ustawiane w _compute_proportions() PRZED _build_voxel_character().
#  Konwencja Y (od stóp): 0 = podeszwa, _ANKLE_Y = kostka (wierzch buta),
#  _KNEE_Y = kolano, _HIP_Y = biodro/pas, _SHOULDER_Y = bark, _NECK_TOP = nasada głowy.
# ----------------------------------------------------------------------------
var VS: float = 0.05          # bok voxela postaci (m) — WYLICZANY: P_HEIGHT_M / P_HEIGHT_VOX
var _ANKLE_Y: int = 2         # = P_FOOT_H
var _KNEE_Y: int = 8          # = P_FOOT_H + P_SHIN_H
var _HIP_Y: int = 16          # = P_FOOT_H + P_SHIN_H + P_THIGH_H
var _SHOULDER_Y: int = 27     # = _HIP_Y + P_TORSO_H
var _ELBOW_Y: int = 21        # = _SHOULDER_Y - P_UARM_H
var _NECK_TOP: int = 29       # = _SHOULDER_Y + P_NECK_H (nasada głowy)
var _HEAD_TOP: int = 37       # = _NECK_TOP + P_HEAD_H (+ czapa włosów osobno)
# Wyliczone pozycje X zawiasów (środek nogi/ręki) — używane przy budowie i animacji.
var _LEG_X: int = 2           # |x| środka nogi = P_LEG_GAP + P_LEG_W/2
var _ARM_X: int = 5           # |x| środka ręki = P_SHOULDER_W/2 + P_ARM_GAP + P_ARM_W/2

# --- GAME FEEL (Faza 0C) ---
@export var ground_accel: float = 55.0     # przyspieszenie na ziemi (m/s^2) — szybki ROZPED ("szybki")
@export var air_accel: float = 14.0        # słabsza kontrola w powietrzu
# FAZA 1: MOVEMENT WEIGHT ("ciezki ale szybki"). Rozdzielamy rozped od wyhamowania i dodajemy
# turn_accel (kierunek ruchu DOCHODZI w ~0.08 s, nie natychmiast — ciezar zwrotu) + lean wizualny.
#  * ground_accel (55): mocny rozped — wystartowanie jest natychmiastowe i responsywne,
#  * ground_decel (28): SLABSZE wyhamowanie — lekki poslizg po puszczeniu klawisza (waga/momentum),
#  * turn_accel: jak szybko WEKTOR ruchu obraca sie ku nowemu kierunkowi (nizszy = ciezszy zwrot).
# NIE rusza auto-stepu/floor-snap/skoku/interpolacji kamery — tylko krzywa rozpedu/hamowania _move_vel.
@export var ground_decel: float = 28.0     # wyhamowanie na ziemi (m/s^2) — DLUZSZE niz rozped (poslizg)
@export var turn_accel: float = 18.0       # jak szybko wektor ruchu dochodzi do nowego kierunku (rad/s skala)
@export var lean_max: float = 0.16         # maks. pochyl tulowia od rozpedu/skretu (rad, wizual)
var _lean_vel: float = 0.0                 # wygladzony lean wzdluzny (przod/tyl) — wizual ciezaru
var _lean_turn: float = 0.0               # wygladzony lean boczny (na zewnatrz skretu) — wizual
var _prev_hvel: Vector3 = Vector3.ZERO     # poprzednia pozioma predkosc (do liczenia przyspieszenia/leanu)
@export var coyote_time: float = 0.12      # okno skoku tuż po zejściu z krawędzi
@export var jump_buffer_time: float = 0.12 # bufor wciśnięcia skoku przed lądowaniem
@export var fall_gravity_mult: float = 1.5 # mocniejsze opadanie (mniej „księżycowo")
# Auto-step: pokonuj TYLKO niskie progi (~1 voxel). Wyższe ściany/strome zbocza NIE są
# pokonywane (postać się zatrzyma) — koniec „wspinania się po terenie, gdzie nie powinna".
@export var step_height: float = 0.6       # maks. wysokość progu do automatycznego wejścia (m)
@export var cam_follow: float = 14.0       # szybkość podążania kamery (lag)
@export var trauma_decay: float = 1.6      # zanik wstrząsu kamery /s
@export var shake_pos: float = 0.18        # amplituda przesunięcia kamery
@export var shake_roll: float = 0.06       # amplituda przechyłu kamery (rad)
var _move_vel: Vector3 = Vector3.ZERO      # wygładzona prędkość pozioma (akceleracja)
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _space_was: bool = false
# FAZA 2 (squash anticipation skoku): krotkie okno przysiadu seedowane W MOMENCIE konsumpcji skoku
# (bufor skoku jest ustawiany i zerowany w tej samej klatce na ziemi, wiec nie da sie nim sterowac
# przysiadem). Tyka w dol w _anim_additive; gdy >0 WARSTWA 4 dodaje krotki przysiad przed wybiciem.
var _jump_antic_t: float = 0.0
var _trauma: float = 0.0
var _shake_time: float = 0.0
var _shake_noise: FastNoiseLite
var _was_on_floor: bool = true
var _hitstop_active: bool = false
var _local_freeze_t: float = 0.0                # co-op: lokalny freeze-frame pozy ataku (s, w _process)
# FEEL (2): TIEROWANY hitstop — wynik ostatniego NASZEGO ciosu (z DamageService.hit_resolved),
# czytany przez _on_hitbox_hit_landed, by dobrac dlugosc bezczasu. _is_heavy_attack ustawia finisher
# (AoE/ciezka bron) na czas okna — wtedy nawet bez krytyka bezczas jest dluzszy (waga ciosu).
var _last_hit_crit: bool = false
var _is_heavy_attack: bool = false

# --- ETAP 1: komponenty wpięte w realną encję (DoD: atak idzie ścieżką komponentów). ---
# Gdy z jakiegoś powodu nie powstaną, kod ma BEZPIECZNE fallbacki (eksporty + ręczna pętla), więc
# gra pozostaje grywalna. Ścieżka docelowa: AbilityComponent -> HitboxComponent -> DamageService ->
# HurtboxComponent(wroga) -> HealthComponent(wroga); a obrażenia gracza wchodzą jego HealthComponent.
var _stats: StatsComponent = null               # JEDYNE źródło staty (gdy wpięte)
var _health: HealthComponent = null             # JEDYNE źródło HP gracza (gdy wpięte); hp mirroruje
var _hurtbox: HurtboxComponent = null           # cel hitboxów wroga (Area3D, warstwa player_body)
var _hitbox: HitboxComponent = null             # okno ataku LMB (Area3D) zamiast ręcznej pętli dot()
var _ability: AbilityComponent = null           # wykonuje atak/dash jako SkillResource (bufor/cancel)
var _skill_attack: SkillResource = null         # podstawowy atak (LMB)
var _skill_dash: SkillResource = null           # unik (RMB/Q)
var _dead_emitted: bool = false                 # idempotencja śmierci (HealthComponent.died + fallback)

# --- ETAP 7: tożsamość sieciowa + predykcja/rekonsyliacja ruchu (TDD 6.3). W SP OBA są BEZCZYNNE:
# NetIdentity.owner_peer=1 (host), a PlayerNetSync.net_post_physics() robi natychmiastowy return gdy
# NetManager.has_network()==false. Dzięki temu SP biegnie sciezka lokalna jak dotad (zero zmian odczucia).
var _net_identity: NetIdentity = null            # owner_peer (kto steruje ta postacia)
var _net_sync: PlayerNetSync = null              # predykcja wlasnej / interpolacja cudzej postaci

# --- ETAP 3: progresja (poziomy/XP, drzewko, zasob klasy). Patrz LevelComponent/SkillTreeComponent/
# ClassResourceComponent. Gracz spina je w _build_progression() i wystawia jako publiczne API
# (grant_xp, allocate_node, respec_tree) + sygnaly do HUD. Fallbacki: brak komponentu = no-op.
var _level: LevelComponent = null               # poziomy/XP -> punkty umiejetnosci
var _tree: SkillTreeComponent = null            # alokacja pasywow (provider StatsComponentu)
var _class_res: ClassResourceComponent = null   # Mana/Furia/Combo+Focus (resource_pool/spend Ability)
var _tame: TameSystem = null                    # ETAP 6: oswajanie bestii -> pet (gate lvl 5, T)
var _skill_finisher: SkillResource = null       # finisher zasobu klasy (Wojownik: Wir Ostrzy, R)
signal level_changed(level: int, xp: int, xp_to_next: int)   # HUD: pasek/etykieta poziomu
signal leveled_up(new_level: int, points_gained: int)        # HUD/FX: awans
signal class_resource_changed(name: StringName, current: float, maximum: float)  # HUD: pasek zasobu
signal class_combo_changed(count: int, maximum: int)         # HUD: pipsy combo (Ranger)

# --- ETAP 1 / FAZA 1: bufor inputu ataku/uniku (ROADMAP 4 krok 3 + Lost Ark responsywnosc) ---
# Spojny bufor (~0.15 s) dla ATAKU i UNIKU: wcisniecie tuz przed koncem recovery/CD/dasha kolejkuje
# akcje. Zunifikowane z jump-buffer (0.12). Atak buforowany odpala sie, gdy okno ataku znow wolne
# (CD zszedl LUB recovery weszlo w cancel-window); unik buforowany odpala po CD/dashu. Patrz
# _tick_input_buffers w _physics_process.
@export var attack_buffer_time: float = 0.15    # s: klik LMB tuż przed końcem recovery/CD zostaje zapamiętany
@export var dodge_buffer_time: float = 0.15     # s: klik uniku w trakcie ataku/CD zostaje zapamiętany
var _attack_buffered: float = 0.0               # >0 = zakolejkowany atak
var _dodge_buffered: float = 0.0                # >0 = zakolejkowany unik

# --- ETAP 1: perfect-dodge (ROADMAP 6: okno 0.12s -> lokalny bullet-time + premia) ---
@export var perfect_dodge_window: float = 0.12  # s od startu uniku, w których trafienie = perfect
@export var perfect_dodge_slowmo: float = 0.35  # time_scale lokalnego bullet-time (SP)
@export var perfect_dodge_slowmo_time: float = 0.35  # s trwania bullet-time (realny czas)
@export var perfect_dodge_pierce_bonus: float = 0.5  # +50% przebicia na następny cios po perfect
var _dodge_active_t: float = 0.0                # ile czasu już trwa bieżący unik (do okna perfect)
var _perfect_bonus_next: bool = false           # następny cios dostaje premię za perfect-dodge
signal perfect_dodge()                          # HUD/FX: udany perfect-dodge

# ============================================================================
#  FAZA 1 (FEEL) — LOCK-ON + SOFT TARGET ASSIST (WoW/Lost Ark feel)
# ============================================================================
# Tab/MMB = lock najblizszego wroga (grupa "enemies"). Przy ataku melee: lekki AUTO-OBROT modelu
# ku celowi + "PULL" kierunku ciosu do celu w zasiegu (koniec machania w powietrze). Wskaznik locka
# (prosty pierscien-Sprite3D) wisi nad celem. Soft-target (bez locka): jesli wrog jest w stozku
# przodu i zasiegu, cios i tak lekko docelowuje (assist). NIC sieciowego — czysto lokalna pomoc celu.
@export var lockon_range: float = 16.0          # m maks. dystans namierzenia/utrzymania locka
@export var lockon_assist_angle: float = 0.5    # dot() progu soft-targetu bez locka (~±60° przod)
@export var melee_pull_range: float = 3.2       # m: w tym zasiegu cios "ciagnie" kierunek do celu
var _lock_target: Node3D = null                 # aktualnie zalockowany wrog (null = brak locka)
var _lock_indicator: Sprite3D = null            # prosty wskaznik nad celem (lazy-tworzony)
signal lockon_changed(target: Node)             # HUD/FX: zmiana celu locka (null = zdjety)

# --- FEEL (5): AFTERIMAGE uniku (duchy modelu) + interwal spawnu ---
const AFTERIMAGE_INTERVAL: float = 0.05         # s miedzy duchami (3 duchy w ~0.1 s zrywu)
const AFTERIMAGE_LIFE: float = 0.22             # s gasniecia ducha
var _afterimage_left: int = 0                   # ile duchow jeszcze spawnowac w tym dashu
var _afterimage_t: float = 0.0                  # licznik do nastepnego ducha

# --- JUICE RUCHU (FOV kick + walk-bob kamery + pył lądowania) ---
# FAZA 5 (TUNING KAMERY): bazowe FOV 75->78 — szerszy kadr pod world-aliveness (więcej świata/hordy
# w polu widzenia), nadal poniżej progu "rybie oko". Sprint-kick 9->10 (mocniejsze poczucie pędu).
@export var base_fov: float = 78.0          # bazowe FOV kamery
@export var sprint_fov_add: float = 10.0    # ile FOV dokładamy przy biegu
@export var fov_lerp: float = 8.0           # szybkość zmiany FOV
@export var cam_bob_amount: float = 0.035   # amplituda walk-bob kamery (m) — MAŁA, by nie mdliło
# KAMERA (boom): osobne tempa wygładzania długości ramienia. „Do środka" szybko (teren wchodzi w kadr —
# anty-clip), „na zewnątrz" wolno (po minięciu zbocza brak szarpniętego zoomu). Zob. _smooth_boom.
@export var boom_in_speed: float = 22.0     # tempo skracania ramienia gdy teren przysłania (szybko)
@export var boom_out_speed: float = 5.0     # tempo wysuwania ramienia gdy teren znika (łagodnie)
var _cam_bob_phase: float = 0.0             # faza walk-bob kamery (czas*tempo)
var _land_dust: GPUParticles3D              # one-shot pył przy lądowaniu (reuse wzorca z Main)
# FEEL 7: pyl spod stop podczas biegu (kadencja kroku) — re-use _land_dust co interwal.
const SPRINT_DUST_INTERVAL: float = 0.26    # s miedzy obloczkami przy biegu (tempo kroku)
var _sprint_dust_t: float = 0.0
# FAZA 4 (6): debounce pylu poslizgu przy ostrym zwrocie (min odstep, by nie spamowac).
const TURN_DUST_DEBOUNCE: float = 0.12
var _turn_dust_t: float = 0.0
var _prev_move_dir: Vector3 = Vector3.ZERO  # kierunek ruchu z poprzedniej klatki (do detekcji zwrotu)
# FAZA 4 (1): kolor smugi broni (slash-trail). Default bialo-stalowy; moze pochodzic z broni/elementu.
@export var _weapon_trail_color: Color = Color(0.85, 0.92, 1.0)
# FAZA 4: leniwie cache'owana referencja do FeelFX (Main dodaje go do drzewa). Brak -> ciche no-op.
var _feel_fx_ref: Node = null

func _ready() -> void:
	_compute_proportions()  # WYLICZ VS + wysokości pivotów z parametrów (PRZED budową modelu)
	_build_body()     # kształt kolizji + widoczny model (kapsuła)
	_build_camera()   # kamera 3rd-person z ramieniem

	# --- Inicjalizacja walki (ETAP 3) ---
	add_to_group("player")          # by wrogowie mogli nas znaleźć fallbackiem (get_first_node_in_group)
	# Warstwy kolizji: gracz na warstwie 2, ale zderza się WYŁĄCZNIE z terenem (warstwa 1).
	# Dzięki temu stado wrogów (warstwa 3) nie spycha gracza — AI i tak działa po dystansie XZ,
	# a chód/auto-podskok po terenie zostają nienaruszone.
	collision_layer = 1 << 1        # warstwa 2 (bit 1) = gracz
	collision_mask = 1              # maska = tylko teren (warstwa 1, bit 0)
	# Gładkie poruszanie po schodkach voxela (0,5 m): snap do podłoża przy SCHODZENIU (bez
	# odrywania się/odpalania lądowania co stopień). floor_max_angle 50° (wierzchy voxeli płaskie;
	# pionowe ściany to wciąż ściany). floor_constant_speed = stała prędkość na zboczach.
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	hp = max_hp
	stamina = max_stamina
	# Punkt odrodzenia = miejsce startu. Main ustawia position PRZED add_child, więc w _ready()
	# global_position jest już poprawne (na terenie z 2 m zapasu). Main może to też nadpisać.
	respawn_point = global_position
	_build_components()              # ETAP 1: Stats/Health/Hurtbox/Hitbox/Ability (droga komponentowa)
	# Emisja startowa w call_deferred — HUD podłącza sygnały dopiero po _ready() gracza.
	call_deferred("emit_signal", "hp_changed", hp, max_hp)
	call_deferred("emit_signal", "stamina_changed", stamina, max_stamina)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # chowamy i łapiemy kursor

	# ETAP 8: zastosuj zapisana czulosc myszy (GameSettings). Brak autoloadu (test) = zostaje baza.
	if GameState != null and typeof(GameState) == TYPE_OBJECT:
		var gs := get_node_or_null("/root/GameSettings")
		if gs != null and "mouse_sensitivity" in gs:
			set_mouse_sensitivity_mult(gs.mouse_sensitivity)

# FAZA 1: wskaznik locka wisi pod rootem sceny (nie pod graczem), wiec przy zwolnieniu gracza
# (smierc/despawn co-op) trzeba go ubic recznie — inaczej zostaje orphan nad pustym miejscem.
func _exit_tree() -> void:
	if _lock_indicator != null and is_instance_valid(_lock_indicator):
		_lock_indicator.queue_free()
	_lock_indicator = null

# ETAP 1: buduje stos komponentów gracza i wpina go w istniejące pola/sygnały. Po tym:
# HP żyje w HealthComponent (hp mirroruje), atak LMB idzie AbilityComponent -> HitboxComponent
# (Area3D) -> DamageService -> Hurtbox/HealthComponent wroga, a obrażenia gracza wchodzą jego
# HealthComponent. Gdyby coś nie powstało, fallbacki w _try_attack/take_damage trzymają grę.
func _build_components() -> void:
	# 1) StatsComponent z base StatBlock z eksportów gracza (jedno źródło staty; krytyk wg GDD 6).
	_stats = StatsComponent.new()
	var block := StatBlock.new()
	block.max_hp = max_hp
	block.max_stamina = max_stamina
	block.stamina_regen = stamina_regen
	block.damage = attack_damage
	block.attack_speed = 1.0 / maxf(0.01, attack_cooldown)
	block.crit_chance = 0.05                       # GDD/ROADMAP 6: gracz lvl 1 = 5% / x1.5
	block.crit_mult = 1.5
	block.move_speed = speed
	block.area_radius = attack_range
	block.dodge_iframes = dodge_iframes
	_stats.base = block
	add_child(_stats)

	# 2) HealthComponent — JEDYNE źródło HP gracza. Śmierć -> _die; HP -> mirror do pola hp + HUD.
	_health = HealthComponent.new()
	add_child(_health)
	_health.damage_gate = _damage_gate          # i-frames/perfect-dodge wetują cios (HP nietknięte)
	_health.died.connect(_on_health_died)
	_health.hp_changed.connect(_on_health_hp_changed)
	hp = _health.current_hp

	# 3) HurtboxComponent (Area3D) — cel hitboxów wroga (warstwa player_body). Kształt ~ kapsuła gracza.
	_hurtbox = HurtboxComponent.new()
	_hurtbox.setup_as_player()
	var hs := CollisionShape3D.new()
	var hcap := CapsuleShape3D.new()
	hcap.height = 1.6
	hcap.radius = 0.45
	hs.shape = hcap
	hs.position = Vector3(0.0, 0.9, 0.0)
	_hurtbox.add_child(hs)
	add_child(_hurtbox)

	# 4) HitboxComponent (Area3D) — okno ataku LMB. Łuk = attack_arc_dot (reuse). set_hit_builder
	#    wstrzykuje _build_hit (combo->przebicie/krytyk/lifesteal liczone ze STATSCOMPONENT gracza).
	#    Juice (combo/hitstop/trauma) odpalamy z sygnałów hit_landed/window_ended (nie z pętli).
	_hitbox = HitboxComponent.new()
	_hitbox.setup_as_player(attack_arc_dot)
	_hitbox.set_hit_builder(func(_t: Node) -> HitData: return _build_hit())
	var bs := CollisionShape3D.new()
	var bsph := SphereShape3D.new()
	bsph.radius = attack_range
	bs.shape = bsph
	_hitbox.add_child(bs)
	add_child(_hitbox)
	_hitbox.hit_landed.connect(_on_hitbox_hit_landed)
	_hitbox.window_ended.connect(_on_hitbox_window_ended)

	# FEEL (2): hitstop TIEROWANY. Krytyk/ciezkosc ostatniego NASZEGO ciosu czytamy z DamageService
	# (jedyne miejsce, ktore zna wynik krytyka). Zapamietujemy w _last_hit_crit, by _on_hitbox_hit_landed
	# dobralo dlugosc bezczasu (light/heavy/crit). To czysto LOKALNE odczucie — HP liczy host.
	if DamageService != null and not DamageService.hit_resolved.is_connected(_on_damage_resolved):
		DamageService.hit_resolved.connect(_on_damage_resolved)

	# 5) AbilityComponent — wykonuje atak/dash jako SkillResource (bufor + cancel w komponencie).
	#    LMB/dash przechodzą przez try_use() -> perform_skill (encja deleguje wykonanie). To literalna
	#    ścieżka DoD: AbilityComponent -> HitboxComponent (perform_skill atak otwiera okno hitboxa).
	_ability = AbilityComponent.new()
	add_child(_ability)
	_ability.resource_pool = func(name: StringName) -> float:
		if name == &"stamina":
			return stamina
		# ETAP 3: zasoby klasy (mana/rage/focus/combo) idą przez ClassResourceComponent.
		if _class_res != null:
			return _class_res.pool(name)
		return 0.0
	_ability.resource_spend = func(name: StringName, amount: float) -> void:
		if name == &"stamina":
			stamina = maxf(0.0, stamina - amount)
			_stamina_idle = 0.0
			stamina_changed.emit(stamina, max_stamina)
		elif _class_res != null:
			_class_res.spend(name, amount)   # ETAP 3: finisher Furii / kast many / wydanie Combo
	_ability.perform_skill = _perform_skill
	_skill_attack = SkillResource.new()
	_skill_attack.id = &"basic_attack"
	_skill_attack.cooldown = attack_cooldown
	# FAZA 1: timeline ataku (anticipation -> active -> recovery + okno cancel). Player czyta te
	# wartosci w _perform_skill i tyka maszyne faz w _tick_attack_timeline (hitbox NIE w klatce 0).
	_skill_attack.anticipation = attack_anticipation
	_skill_attack.active = attack_active
	_skill_attack.recovery = attack_recovery
	_skill_attack.cancel_window = attack_cancel_window
	_skill_dash = SkillResource.new()
	_skill_dash.id = &"dash"
	_skill_dash.cooldown = dodge_cooldown
	_skill_dash.cost_resource = &"stamina"
	_skill_dash.cost_amount = dodge_stamina_cost

	# ETAP 7 — tożsamość sieciowa + predykcja ruchu. NetIdentity domyślnie owner_peer=1 (host/SP).
	# W co-opie Main/warstwa spawnu ustawia owner_peer na peer-właściciela tej postaci (set_owner_peer).
	# PlayerNetSync jest bezczynny w SP (net_post_physics -> return gdy brak sieci), więc dodanie go
	# NIE zmienia single-playera. Tworzymy zawsze (tani Node), by co-op nie wymagał re-spawnu encji.
	_net_identity = NetIdentity.new()
	_net_identity.owner_peer = NetManager.HOST_PEER_ID if NetManager != null else 1
	add_child(_net_identity)
	_net_sync = PlayerNetSync.new()
	add_child(_net_sync)
	_net_sync.setup(self, _net_identity)

	# ETAP 3 — progresja (poziomy/XP + drzewko + zasob klasy). Po komponentach walki, by
	# StatsComponent juz istnial (drzewko rejestruje sie jako jego provider).
	_build_progression()

# ETAP 3: buduje stos progresji (LevelComponent + SkillTreeComponent + ClassResourceComponent)
# i wpina go w istniejace komponenty i sygnaly. Klasa z GameState.class_id, drzewko z SkillDB.
# Wstepny stan (poziom/XP/alokacja) z save'a wczytuje Main przez load_progression() — tu start lvl 1.
func _build_progression() -> void:
	var cls: StringName = &"warrior"
	if typeof(GameState) != TYPE_NIL and GameState != null:
		cls = GameState.class_id

	# 1) LevelComponent — XP -> punkty. Sygnaly do HUD (re-emit z encji, by HUD spinal sie z graczem).
	_level = LevelComponent.new()
	add_child(_level)
	_level.level_changed.connect(func(lv: int, x: int, nx: int) -> void: level_changed.emit(lv, x, nx))
	_level.leveled_up.connect(func(lv: int, pts: int) -> void: leveled_up.emit(lv, pts))

	# 2) SkillTreeComponent — provider StatsComponentu. Drzewko klasy z SkillDB (jesli zaladowane).
	_tree = SkillTreeComponent.new()
	add_child(_tree)
	var tree_res: SkillTreeResource = null
	if typeof(SkillDB) != TYPE_NIL and SkillDB != null and SkillDB.has_method("tree"):
		tree_res = SkillDB.tree(cls)
	_tree.setup(tree_res, _level)

	# 3) ClassResourceComponent — Mana/Furia/Combo+Focus. Re-emit do HUD.
	_class_res = ClassResourceComponent.new()
	add_child(_class_res)
	_class_res.build_for(cls)
	# Wepnij StatsComponent: zasob KLASY czyta z niego mnozniki/pule (rage_gen -> realna Furia za cios,
	# mana_max -> pula many) i subskrybuje stats_changed, wiec loot/pasywy zmieniajace te staty od razu
	# wplywaja na generacje i maksima (review Etap 3: rage_gen byl martwy, mana_max czytany raz).
	if _stats != null:
		_class_res.set_stats(_stats)
	_class_res.resource_changed.connect(func(n: StringName, c: float, m: float) -> void:
		class_resource_changed.emit(n, c, m))
	_class_res.combo_changed.connect(func(c: int, m: int) -> void: class_combo_changed.emit(c, m))

	# ETAP 6 — TameSystem (oswajanie -> pet). Gate lvl 5 + cel <35% HP + item-oswajacz; 1 aktywny pet
	# skalowany pet_damage/pet_hp gracza. Po LevelComponent/StatsComponent (czyta oba do gate'u/skalow.).
	_tame = TameSystem.new()
	add_child(_tame)
	_tame.setup(self, _level, _stats)
	# ETAP 6 (loot pipeline): item-oswajacz idzie przez REALNY ekwipunek. Wpinamy peek (czy gracz ma
	# tame_charm) i provider (zuzyj 1) jako Callable szukajace InventoryComponentu LENIWIE — Main tworzy
	# go jako dziecko gracza PO tym _ready, wiec lookup robimy DOPIERO przy oswajaniu (gdy juz istnieje),
	# a nie teraz. charm_count zostaje fallbackiem dla testow bez ekwipunku.
	# Locale Callable'i jako Node (duck-type), NIE InventoryComponent: na CZYSTYM checkoutcie
	# class_name InventoryComponent bywa jeszcze nierejestrowany w TYM samym przebiegu --import, co
	# kompiluje Player.gd (dwuprzebiegowa rejestracja Godota). Zalezno do nazwanej klasy w ciele tych
	# Callable'i potrafila wtedy transient'owo wywalic _find_inventory jako "not found". has_item/
	# consume_item sa kaczkowane, wiec Node wystarcza i znosi zaleznosc od rejestracji klasy (1-pass CI).
	_tame.charm_peek = func() -> bool:
		var inv: Node = _find_inventory()
		return inv != null and inv.has_item(TameSystem.TAME_CHARM_ITEM)
	_tame.charm_provider = func() -> bool:
		var inv: Node = _find_inventory()
		return inv != null and inv.consume_item(TameSystem.TAME_CHARM_ITEM)

	# 4) Finisher zasobu klasy (sink, by zasob mial sens w grze). Wojownik: Wir Ostrzy (30 Furii,
	#    CD 1 s, AoE wokol — ROADMAP 6). Koszt/CD pilnuje AbilityComponent (cost_resource=rage).
	if cls == &"warrior":
		_skill_finisher = SkillResource.new()
		_skill_finisher.id = &"whirlwind"
		_skill_finisher.cooldown = 1.0
		_skill_finisher.cost_resource = &"rage"
		_skill_finisher.cost_amount = 30.0
		_skill_finisher.damage_mult = 0.8
		var ftags: Array[StringName] = [&"phys", &"aoe", &"melee"]
		_skill_finisher.tags = ftags
		# FAZA 4 (3): Wir Ostrzy -> aura-pierscien (kolor stalowy, promien = zasieg AoE wokol gracza).
		_skill_finisher.aura_kind = &"ring"
		_skill_finisher.aura_color = Color(0.8, 0.9, 1.0)
		_skill_finisher.aura_radius = 2.6

# ============================================================================
#  ETAP 3 — PUBLICZNE API PROGRESJI (Main/HUD/UI drzewka/test wolaja to)
# ============================================================================

## ETAP 7 — ustawia peer-właściciela tej postaci (warstwa spawnu co-op). owner==local -> predykcja
## i czytanie klawiatury; inaczej host symuluje z RPC, a klient interpoluje. W SP nie wołane (owner=1).
## Ustawia też Godotowy multiplayer authority (gdy w drzewie), by has_authority() działało dwustronnie.
func set_owner_peer(peer_id: int) -> void:
	if _net_identity != null:
		_net_identity.owner_peer = peer_id
	if is_inside_tree() and NetManager != null and NetManager.has_network():
		# REKURENCYJNIE na cale poddrzewo (review #major): @rpc("authority") na PlayerNetSync musi
		# rozwiazywac autorytet wzgledem OWNER-PEERA tej postaci, a nie domyslnego 1. set_multiplayer_
		# authority na samym roocie NIE propaguje na dzieci — komponent PlayerNetSync ma wtedy zly
		# autorytet i _ack_position/_recv_snapshot ida z perspektywy zlego peera. true = rekurencyjnie.
		set_multiplayer_authority(peer_id, true)

## ETAP 7 — peer-właściciel tej postaci (1 = host/SP).
func owner_peer() -> int:
	return _net_identity.owner_peer if _net_identity != null else 1

## ETAP 7 — komponent predykcji/synchronizacji (Main/test). Null tylko zanim _ready zbuduje komponenty.
func net_sync() -> PlayerNetSync:
	return _net_sync

## XP za zabicie wroga (hook smierci wroga w Main). Deleguje do LevelComponent (lvl up -> punkt).
func grant_xp(amount: int) -> void:
	if _level != null:
		_level.grant_xp(amount)

func get_level() -> int:
	return _level.level if _level != null else 1

func get_xp() -> int:
	return _level.xp if _level != null else 0

func get_skill_points() -> int:
	return _level.available_points() if _level != null else 0

## Alokuje wezel drzewka (UI/test). Zwraca true przy sukcesie (walidacja w SkillTreeComponent).
func allocate_node(node_id: StringName) -> bool:
	return _tree.allocate(node_id) if _tree != null else false

func deallocate_node(node_id: StringName) -> bool:
	return _tree.deallocate(node_id) if _tree != null else false

## Pelny respec drzewka za walute (Orby — GDD 10.1). Zwraca liczbe zwroconych punktow.
## Koszt liczony schodkowo; waluta z GameState.orbs (pool/spend). respec_index — ile razy juz respec.
func respec_tree(respec_index: int = 0) -> int:
	if _tree == null:
		return 0
	var cost := SkillTreeComponent.orb_cost_for(respec_index)
	var pool := func() -> int: return GameState.orbs if GameState != null else 0
	var spend := func(amount: int) -> void:
		if GameState != null:
			GameState.spend_orbs(amount)
	return _tree.respec(cost, pool, spend)

## Komponenty progresji (dla Main/UI/HUD/test).
func level_component() -> LevelComponent:
	return _level
func skill_tree_component() -> SkillTreeComponent:
	return _tree
func class_resource_component() -> ClassResourceComponent:
	return _class_res
## ETAP 6 — TameSystem (oswajanie/pet). Main/test wola try_tame / load_pet_from_save przez to.
func tame_system() -> TameSystem:
	return _tame

## ETAP 6 — InventoryComponent gracza. Tworzy go Main jako dziecko gracza (po _ready), wiec szukamy
## LENIWIE wsrod dzieci. Uzywane przez charm_peek/charm_provider (item-oswajacz w plecaku). Null gdy
## ekwipunku jeszcze/wcale nie ma (np. headless bez Main) -> oswajanie spada na charm_count.
## Zwracamy Node (duck-type), NIE InventoryComponent: adnotacja zwrotu wymuszalaby rejestracje
## class_name InventoryComponent juz przy KOMPILACJI Player.gd, co na czystym checkoutcie potrafi
## byc jeszcze niedostepne w tym samym przebiegu --import (dwuprzebiegowa rejestracja klas Godota) ->
## transient parse error i "Failed to load Main.gd" na 1-pass CI. is InventoryComponent w ciele jest
## bezpieczne (sprawdzane w RUNTIME), a wolajacy uzywaja tylko kaczkowanych has_item/consume_item.
func _find_inventory() -> Node:
	for c in get_children():
		if c is InventoryComponent:
			return c
	return null

## Wczytanie stanu progresji z save (Main wola po spawnie). poziom/XP + alokacja drzewka.
func load_progression(p_level: int, p_xp: int, p_allocated: Array[StringName]) -> void:
	if _level != null:
		_level.load_from(p_level, p_xp)
	if _tree != null:
		_tree.setup(_tree.tree, _level, p_allocated)

## Zapisuje stan progresji gracza do SaveData (poziom/xp/alokacja). Waluty trzyma GameState ->
## zsynchronizuj je tu, by SaveData mial komplet (DoD: poziom/xp/punkty/waluta/alokacja w save).
func write_progression_to_save(sd: SaveData) -> void:
	if sd == null:
		return
	sd.class_id = GameState.class_id if GameState != null else &"warrior"
	sd.level = get_level()
	sd.xp = get_xp()
	if _tree != null:
		sd.allocated_passives = _tree.allocated_ids()
	if GameState != null:
		sd.gold = GameState.gold
		sd.orbs = GameState.orbs
	# ETAP 6 — pet (aktywny typ + stajnia) do save'a.
	if _tame != null:
		_tame.write_pet_to_save(sd)

## Wczytuje progresje z SaveData (odwrotnosc write). Waluty -> GameState.
func read_progression_from_save(sd: SaveData) -> void:
	if sd == null:
		return
	load_progression(sd.level, sd.xp, sd.allocated_passives)
	if GameState != null:
		GameState.gold = sd.gold
		GameState.orbs = sd.orbs
		GameState.gold_changed.emit(GameState.gold)
		GameState.orbs_changed.emit(GameState.orbs)
	# ETAP 6 — odtworz peta ze stanu save (typ -> ALLY przy graczu + stajnia).
	if _tame != null:
		_tame.load_pet_from_save(sd)

## ETAP 3 — TRWALY zapis progresji w trakcie gry (review: sciezka zapisu nie byla wolana w grze).
## Wola Main na zamknieciu okna, awansie i po zmianie alokacji/respec. Najpierw WCZYTUJE istniejacy
## zapis postaci (by NIE nadpisac wygladu/ekwipunku/skilli z innych etapow), nakłada na niego biezaca
## progresje (poziom/xp/alokacja/waluty) i zapisuje. Bezpieczne, gdy SaveManager niedostepny (no-op).
func save_progression() -> bool:
	if typeof(SaveManager) == TYPE_NIL or SaveManager == null:
		return false
	var sd: SaveData = SaveManager.load_character()
	if sd == null:
		sd = SaveData.new()       # swiezy zapis (np. pierwsza sesja bez character.json)
	write_progression_to_save(sd)
	return SaveManager.save_character(sd)

# ============================================================================
#  WYLICZENIE PROPORCJI: pivoty + skala VS z parametrów P_* (wołane w _ready
#  PRZED _build_body). To JEDYNE miejsce, gdzie liczby z panelu zamieniają się
#  na wysokości zawiasów i metryczny rozmiar voxela — sculpt-y i animacja czytają
#  TYLKO wyniki (_HIP_Y, _SHOULDER_Y, VS, ...), więc strojenie = zmiana liczb P_*.
# ============================================================================
func _compute_proportions() -> void:
	# --- PIONOWY STOS (od stóp y=0 w górę) ---
	_ANKLE_Y    = P_FOOT_H                                  # wierzch buta (kostka)
	_KNEE_Y     = _ANKLE_Y + P_SHIN_H                       # pivot kolana
	_HIP_Y      = _KNEE_Y + P_THIGH_H                       # pivot biodra/pasa
	_SHOULDER_Y = _HIP_Y + P_TORSO_H                        # pivot barku
	_ELBOW_Y    = _SHOULDER_Y - P_UARM_H                    # pivot łokcia (w połowie wysokości ramienia)
	_NECK_TOP   = _SHOULDER_Y + P_NECK_H                    # nasada głowy (wierzch szyi)
	_HEAD_TOP   = _NECK_TOP + P_HEAD_H                      # czubek czaszki (bez włosów)
	# --- POPRZECZNE pozycje zawiasów (środek nogi/ręki w X) ---
	_LEG_X = P_LEG_GAP + int(P_LEG_W / 2.0 + 0.5)          # noga tuż przy osi (wąski rozkrok, smukło)
	_ARM_X = int(P_SHOULDER_W / 2.0) + P_ARM_GAP + int(P_ARM_W / 2.0 + 0.5)  # ramię tuż przy barku
	# --- SKALA: VS dobrane tak, by PEŁNA wysokość (z czapą włosów) = P_HEIGHT_M ---
	# P_HEIGHT_VOX nadpisujemy realną sumą (czubek włosów), więc P_HEIGHT_VOX*VS == P_HEIGHT_M
	# DOKŁADNIE, niezależnie od tego, jak integrator zmieni pojedyncze segmenty.
	P_HEIGHT_VOX = _HEAD_TOP + P_HAIR_TOP
	VS = P_HEIGHT_M / float(maxi(1, P_HEIGHT_VOX))          # bok voxela postaci (m)

func _build_body() -> void:
	# Kolizja (kapsuła) — smuklejsza (smukły bohater), stoi „stopami" na y=0.
	# Wysokość kapsuły dopasowana do realnego wzrostu modelu (P_HEIGHT_M), więc czubek
	# głowy mieści się w kapsule (środek = połowa wzrostu, biegun = wzrost). Stopy na y=0
	# pozostają niezmienione: floor_snap, auto-step i kamera działają jak dotąd.
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	# height kapsuły = realny wzrost (bez czapy włosów, by nie zawadzała o niskie nawisy),
	# clamp na 2*radius (minimalna sensowna kapsuła). Środek = height/2 => stopy na y=0.
	var body_h := maxf(2.0 * capsule.radius + 0.01, P_HEIGHT_M)
	capsule.height = body_h
	shape.shape = capsule
	shape.position = Vector3(0.0, body_h * 0.5, 0.0)
	add_child(shape)

	# Widoczny model: voxelowa postać z małych kostek (styl Cube World).
	_build_voxel_character()

# ============================================================================
#  POSTAĆ Z MALUTKICH VOXELI — ZGRABNY BOHATER „POŚREDNI" (~1,8 m, ~4,5 głowy)
# ============================================================================
# Każda grupa ciała = jeden zbatchowany ArrayMesh z drobnych kostek (vertex color),
# z cullingiem wewnętrznych ścian (przez VoxelModel). Tułów+głowa na _torso/_head;
# ręce/nogi jako 2-segmentowe łańcuchy pivotów (bark->łokieć, biodro->kolano).
# Materiał: StandardMaterial3D z vertex_color_use_as_albedo, by _flash_hit() (rzut
# `as StandardMaterial3D`) działał dalej, a kolory były wbudowane w jeden materiał.
#
# PROPORCJE są PARAMETRYCZNE: cała geometria poniżej liczy zakresy voxeli z eksportów
# P_* (sekcja „Proporcje postaci"). Skala VS = P_HEIGHT_M / P_HEIGHT_VOX, więc model
# trzyma realny wzrost (~1,8 m) niezależnie od gęstości siatki. Stopy na y=0, twarz -Z.

# Buduje voxelową postać. Tułów+głowa na _torso/_head (anim bob/lean/twist + stabilizacja głowy);
# ręce i nogi jako 2-segmentowe łańcuchy pivotów (bark->łokieć, biodro->kolano).
func _build_voxel_character() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	var mat := _make_char_material()

	# --- TUŁÓW (węzeł animowany: bob/lean/twist) — pivot w pasie (y=_HIP_Y), by lean/twist
	#     obracał się od bioder, a głowa siedziała wyżej. Geometria tułowia bake'owana z
	#     offsetem -_HIP_Y, więc pas leży w (0,0,0) węzła _torso.
	_torso = _make_pivot(_model, Vector3(0.0, float(_HIP_Y) * VS, 0.0))
	var torso := VoxelModel.VoxelDef.new()
	_sculpt_torso(torso)
	_add_model_mesh(_torso, torso, mat, Vector3i(0, _HIP_Y, 0))

	# FAZA 2 (secondary motion): PELERYNA na osobnym pivocie u nasady barkow (kolysze sie za
	# tulowiem). Pivot u gory pleców (+Z), geometria peleryny bake'owana z offsetem tego pivota,
	# wiec fala zwisa W DOL od barkow. _sculpt_cape buduje TYLKO warstwe peleryny (wycieta z torsa).
	var cape_pivot_y := _SHOULDER_Y - 1            # nasada peleryny tuz pod barkiem
	var cape_pivot_z := P_TORSO_D / 2 + 1          # tyl korpusu (warstwa peleryny)
	_cape = _make_pivot(_torso, Vector3(0.0, float(cape_pivot_y - _HIP_Y) * VS, float(cape_pivot_z) * VS))
	var cape := VoxelModel.VoxelDef.new()
	_sculpt_cape(cape)
	_add_model_mesh(_cape, cape, mat, Vector3i(0, cape_pivot_y, cape_pivot_z))

	# --- GŁOWA (osobny węzeł na szczycie tułowia: stabilizacja/oscylacja) — pivot u nasady
	#     szyi (y=_SHOULDER_Y), dziecko _torso, więc dziedziczy bob/lean, a dokłada własny ruch.
	_head = _make_pivot(_torso, Vector3(0.0, float(_SHOULDER_Y - _HIP_Y) * VS, 0.0))
	var head := VoxelModel.VoxelDef.new()
	_sculpt_head(head)
	_add_model_mesh(_head, head, mat, Vector3i(0, _SHOULDER_Y, 0))
	# FEEL 3: EMISYJNY AKCENT OCZU — dwa malutkie świecące voxele na tęczówkach (osobne meshe, bo
	# głowa to jeden vertex-color mesh bez emisji per-voxel). Subtelny "żywy" błysk spojrzenia,
	# czytelny w cieniu/mgle, ale niski energetycznie (glow_hdr_threshold=1.0 nie zrobi z tego flara).
	_add_eye_glints(head)

	# FAZA 2 (secondary motion): GRZYWKA na osobnym pivocie u czoła (dziecko _head, dziedziczy ruch
	# glowy a dokłada wlasny lag). Pivot u gory czaszki z przodu; grzywka zwisa od niego (wycieta z glowy).
	var fringe_pivot_y := _HEAD_TOP - 2
	var fringe_pivot_z := -(P_HEAD_D / 2) - 1      # przed licem (warstwa grzywki)
	_hair = _make_pivot(_head, Vector3(0.0, float(fringe_pivot_y - _SHOULDER_Y) * VS, float(fringe_pivot_z) * VS))
	var fringe := VoxelModel.VoxelDef.new()
	_sculpt_fringe(fringe)
	_add_model_mesh(_hair, fringe, mat, Vector3i(0, fringe_pivot_y, fringe_pivot_z))

	# --- NOGI (2 segmenty): biodro (y=_HIP_Y) -> kolano (y=_KNEE_Y zagnieżdżony) ---
	# Zawias biodra w X = ±_LEG_X (wyliczone z P_LEG_*). Udo bake'owane pod biodrem
	# (offset -_HIP_Y, -_LEG_X). Łydka+but pod kolanem (offset -_KNEE_Y, -_LEG_X). Pivot
	# kolana jest dzieckiem biodra (ten sam X), na wysokości (_KNEE_Y-_HIP_Y)*VS poniżej.
	_leg_l = _make_pivot(_model, Vector3(float(-_LEG_X) * VS, float(_HIP_Y) * VS, 0.0))
	_leg_r = _make_pivot(_model, Vector3(float( _LEG_X) * VS, float(_HIP_Y) * VS, 0.0))
	_leg_l_lo = _make_pivot(_leg_l, Vector3(0.0, float(_KNEE_Y - _HIP_Y) * VS, 0.0))
	_leg_r_lo = _make_pivot(_leg_r, Vector3(0.0, float(_KNEE_Y - _HIP_Y) * VS, 0.0))
	var thigh_l := VoxelModel.VoxelDef.new(); _sculpt_thigh(thigh_l, -1)
	var thigh_r := VoxelModel.VoxelDef.new(); _sculpt_thigh(thigh_r, 1)
	var shin_l := VoxelModel.VoxelDef.new(); _sculpt_shin(shin_l, -1)
	var shin_r := VoxelModel.VoxelDef.new(); _sculpt_shin(shin_r, 1)
	# Pivot w X przesuwamy kompensacyjnie o ±_LEG_X (geometria liczona w globalnych X),
	# by zawias leżał DOKŁADNIE w osi nogi.
	_add_model_mesh(_leg_l, thigh_l, mat, Vector3i(-_LEG_X, _HIP_Y, 0))
	_add_model_mesh(_leg_r, thigh_r, mat, Vector3i( _LEG_X, _HIP_Y, 0))
	_add_model_mesh(_leg_l_lo, shin_l, mat, Vector3i(-_LEG_X, _KNEE_Y, 0))
	_add_model_mesh(_leg_r_lo, shin_r, mat, Vector3i( _LEG_X, _KNEE_Y, 0))

	# --- RĘCE (2 segmenty): bark (y=_SHOULDER_Y) -> łokieć (y=_ELBOW_Y zagnieżdżony) ---
	# Zawias barku w X = ±_ARM_X (za krawędzią barków, z P_SHOULDER_W/P_ARM_*).
	_arm_l = _make_pivot(_model, Vector3(float(-_ARM_X) * VS, float(_SHOULDER_Y) * VS, 0.0))
	_arm_r = _make_pivot(_model, Vector3(float( _ARM_X) * VS, float(_SHOULDER_Y) * VS, 0.0))
	_arm_l_lo = _make_pivot(_arm_l, Vector3(0.0, float(_ELBOW_Y - _SHOULDER_Y) * VS, 0.0))
	_arm_r_lo = _make_pivot(_arm_r, Vector3(0.0, float(_ELBOW_Y - _SHOULDER_Y) * VS, 0.0))
	var uarm_l := VoxelModel.VoxelDef.new(); _sculpt_upper_arm(uarm_l, -1)
	var uarm_r := VoxelModel.VoxelDef.new(); _sculpt_upper_arm(uarm_r, 1)
	var farm_l := VoxelModel.VoxelDef.new(); _sculpt_forearm(farm_l, -1)
	var farm_r := VoxelModel.VoxelDef.new(); _sculpt_forearm(farm_r, 1)
	_add_model_mesh(_arm_l, uarm_l, mat, Vector3i(-_ARM_X, _SHOULDER_Y, 0))
	_add_model_mesh(_arm_r, uarm_r, mat, Vector3i( _ARM_X, _SHOULDER_Y, 0))
	_add_model_mesh(_arm_l_lo, farm_l, mat, Vector3i(-_ARM_X, _ELBOW_Y, 0))
	_add_model_mesh(_arm_r_lo, farm_r, mat, Vector3i( _ARM_X, _ELBOW_Y, 0))

	# FAZA 2 (secondary motion): BROŃ/DŁOŃ na osobnym pivocie u nadgarstka prawej reki (dziecko
	# _arm_r_lo). Maly akcent (rekojesc/krotki implement) ktory KOLYSZE sie za zamachem ramienia
	# (lag springiem). Pivot na dnie segmentu przedramienia = nadgarstek; geometria zwisa w dol.
	var wrist_y := _ELBOW_Y - P_FARM_H + 2          # nadgarstek (nad dlonia)
	# PIVOT broni: local X = 0 (jak _hair/_cape). _arm_r_lo dziedziczy juz +_ARM_X*VS od _arm_r, wiec
	# pivot lezy DOKLADNIE w osi geometrii broni. (Wczesniej local X=_ARM_X*VS odsuwalo pivot ~5 voxeli
	# na zewnatrz, przez co spring WARSTWY 3 obracal bron po luku — "slizg" zamiast kolysania w miejscu.)
	# Bake offset Vector3i(_ARM_X, wrist_y, 0) nadal liczy geometrie w globalnym X, wiec mesh nie drgnie.
	_weapon = _make_pivot(_arm_r_lo, Vector3(0.0, float(wrist_y - _ELBOW_Y) * VS, 0.0))
	var wpn := VoxelModel.VoxelDef.new()
	_sculpt_weapon(wpn)
	_add_model_mesh(_weapon, wpn, mat, Vector3i(_ARM_X, wrist_y, 0))

# Bakuje JEDNĄ grupę voxeli do zbatchowanego ArrayMesh i wiesza pod 'parent'.
# pivot_vox = logiczny punkt obrotu (w voxelach); geometrię przesuwamy o -pivot*VS,
# żeby zawias leżał w (0,0,0) węzła (animacja rotation.x bez zmian).
func _add_model_mesh(parent: Node3D, def: VoxelModel.VoxelDef, mat: Material, pivot_vox: Vector3i) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelModel.build_mesh(def, VS, -Vector3(pivot_vox) * VS)
	# KAŻDY segment dostaje WŁASNĄ kopię materiału (duplicate) — zgodnie z kontraktem opisanym
	# przy _make_char_material(). _flash_hit() i tak iteruje per mesh (idempotentnie), ale własna
	# kopia umożliwia per-segment albedo/emisję (np. tint jednej kończyny) bez wpływu na resztę.
	mi.material_override = mat.duplicate()
	parent.add_child(mi)

# Materiał postaci: vertex-color jako albedo, matowy. To WZORZEC — _add_model_mesh() robi
# .duplicate() na każdy segment, więc KAŻDA grupa ma WŁASNĄ kopię materiału (per-mesh albedo/
# emisja możliwe niezależnie; _flash_hit() ustawia emisję per mesh).
func _make_char_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true   # spójnie z paletą sRGB (Blocks)
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat

# FEEL 3: dokłada dwa malutkie EMISYJNE voxele na tęczówkach gracza (dzieci _head). Głowa to jeden
# vertex-color mesh bez emisji per-voxel, więc świecący akcent oka dajemy osobnymi mini-meshami.
# Pozycje liczone IDENTYCZNIE jak w _sculpt_head (eye_y/ex/fz), przeliczone do lokalnych _head
# (pivot głowy = Vector3i(0,_SHOULDER_Y,0), geometria = (voxel-pivot)*VS). Tuż przed licem (-Z),
# by błysk nie z-fightował ze skórą. Energia niska — czytelny "żywy" wzrok, bez flara pod glow.
const _C_EYE_GLINT: Color = Color(0.55, 0.80, 1.00)   # chłodny błękit tęczówki (spójny z _C_IRIS)
func _add_eye_glints(_head_def: VoxelModel.VoxelDef) -> void:
	var hw := P_HEAD_W / 2
	var hd := P_HEAD_D / 2
	var eye_y := _NECK_TOP + (P_HEAD_H * 11) / 20
	var ex := maxi(1, hw - 1)
	var fz := -hd - 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _C_EYE_GLINT
	mat.emission_enabled = true
	mat.emission = _C_EYE_GLINT
	mat.emission_energy_multiplier = 1.8   # subtelny błysk spojrzenia (AGX/glow-safe)
	mat.roughness = 1.0
	for sx in [-ex, ex]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * (VS * 0.7)   # mniejszy niż voxel oka => błysk w środku tęczówki
		mi.mesh = bm
		mi.material_override = mat   # współdzielony (oba oczy identyczne; nie modyfikujemy per-mesh)
		# Lokalna pozycja względem _head: (voxel - pivot)*VS; pivot.y = _SHOULDER_Y. Lekko przed licem.
		mi.position = Vector3(
			float(sx) * VS,
			float(eye_y - _SHOULDER_Y) * VS,
			float(fz) * VS - VS * 0.4
		)
		_head.add_child(mi)

# Tworzy węzeł-zawias (pivot) kończyny w danym punkcie modelu.
func _make_pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p

# --- RZEŹBIENIE GRUP CIAŁA (siatka voxeli całkowitych, y=0 = poziom stóp) ---
# Konwencja: x = lewo(-)/prawo(+) WIDZA, y = w górę, z = przód(-)/tył(+). Front twarzy = -Z.

# Paleta postaci (sRGB; vertex_color_is_srgb=true w materiale).
const _C_SKIN    := Color(0.95, 0.78, 0.62)
const _C_SKIN_SH := Color(0.86, 0.68, 0.53)   # cień skóry (szyja/nos)
const _C_BLUSH   := Color(0.93, 0.62, 0.55)
const _C_HAIR    := Color(0.40, 0.24, 0.12)
const _C_HAIR_HI := Color(0.52, 0.33, 0.17)
const _C_EYE_W   := Color(0.97, 0.97, 0.98)
const _C_IRIS    := Color(0.20, 0.46, 0.72)
const _C_PUPIL   := Color(0.05, 0.05, 0.07)
const _C_MOUTH   := Color(0.62, 0.34, 0.34)
const _C_TUNIC   := Color(0.20, 0.52, 0.36)
const _C_TUNIC_SH := Color(0.15, 0.40, 0.28)
const _C_TRIM    := Color(0.86, 0.78, 0.42)   # złota lamówka/naramiennik
const _C_BELT    := Color(0.34, 0.22, 0.12)
const _C_BUCKLE  := Color(0.82, 0.72, 0.34)
const _C_PANTS   := Color(0.28, 0.32, 0.50)
const _C_PANTS_SH := Color(0.22, 0.25, 0.40)
const _C_BOOTS   := Color(0.26, 0.18, 0.12)
const _C_BOOTS_HI := Color(0.36, 0.26, 0.17)
const _C_SOLE    := Color(0.16, 0.12, 0.09)   # ciemna podeszwa (czytelny styk z ziemią)
const _C_CAPE    := Color(0.62, 0.20, 0.22)   # peleryna (akcent koloru z tyłu)
const _C_CAPE_SH := Color(0.48, 0.14, 0.16)
const _C_LEATHER := Color(0.45, 0.30, 0.18)   # rękawice/naramiennik skórzany
const _C_EAR     := _C_SKIN

# GŁOWA — UMIARKOWANA (NIE chibi): owalna czaszka + schludne włosy + uszy + CZYTELNA twarz.
# Cała geometria liczona z parametrów: czaszka zajmuje y[_NECK_TOP.._HEAD_TOP), szer. P_HEAD_W,
# głęb. P_HEAD_D. Twarz to „naklejka" na froncie (-Z). Oczy PROPORCJONALNE (małe), nie gigantyczne.
# NIE: wielka kula głowy, oczy na pół twarzy, sterczący ahoge — to dawało „pokraczny" chibi-look.
func _sculpt_head(d: VoxelModel.VoxelDef) -> void:
	var hw := P_HEAD_W / 2                       # półszerokość (np. 7/2=3 => x[-3..3])
	var hd := P_HEAD_D / 2                       # półgłębokość
	var y0 := _NECK_TOP                          # dół czaszki = wierzch szyi
	var y1 := _HEAD_TOP                          # czubek czaszki (bez włosów)
	var fz := -hd - 1                            # warstwa „naklejki" twarzy (1 przed licem)
	# CZASZKA (skóra) — owalna: pełny blok, potem ścięte 4 pionowe krawędzie i górne rogi.
	d.fill_box(Vector3i(-hw, y0, -hd), Vector3i(hw + 1, y1, hd + 1), _C_SKIN)
	# Ścięcie 4 pionowych krawędzi (mniej „pudełkowo") na całej wysokości oprócz środka.
	for ey in range(y0 + 1, y1 - 1):
		d.cells.erase(Vector3i(-hw,  ey, -hd)); d.cells.erase(Vector3i(hw,  ey, -hd))
		d.cells.erase(Vector3i(-hw,  ey,  hd)); d.cells.erase(Vector3i(hw,  ey,  hd))
	# Ścięcie górnych rogów (kopuła czaszki) i dolnych-przednich (lekki, zwężony podbródek).
	for cx in [-hw, hw]:
		for cz in [-hd, hd]:
			d.cells.erase(Vector3i(cx, y1 - 1, cz))
		d.cells.erase(Vector3i(cx, y0, -hd))     # zwężenie szczęki u dołu z przodu
	# SZYJA (ciemniejsza skóra) — smukła, łączy głowę z barkami. y[_SHOULDER_Y.._NECK_TOP).
	var nw := P_NECK_W / 2
	d.fill_box(Vector3i(-nw, _SHOULDER_Y, -nw), Vector3i(nw + 1, _NECK_TOP, nw + 1), _C_SKIN_SH)
	# USZY — wtopione w bok czaszki (x=±hw, NIE ±hw-1 ani ±hw+1), na wys. oczu. Świadomie NIE
	# wystają poza skroń: gdyby sterczały (±hw+1), poszerzałyby SYLWETKĘ głowy do szer. barków
	# (chibi „wielka głowa"); recesja trzyma head_w/shoulder_w ≈ 0,64 (cel 0,6-0,7). Lekki cień
	# (_C_SKIN_SH) na dolnym voxelu daje czytelny zarys małżowiny bez dokładania szerokości.
	var ear_y := y0 + (P_HEAD_H / 2) - 1
	d.set_voxel(Vector3i(-hw, ear_y, 1), _C_EAR);     d.set_voxel(Vector3i(-hw, ear_y + 1, 1), _C_SKIN_SH)
	d.set_voxel(Vector3i( hw, ear_y, 1), _C_EAR);     d.set_voxel(Vector3i( hw, ear_y + 1, 1), _C_SKIN_SH)
	# WŁOSY: schludna czapa (P_HAIR_TOP nad czaszką), boki/tył do połowy głowy, grzywka na czole.
	var hair_lo := y0 + (P_HEAD_H * 2) / 3       # włosy schodzą do ~2/3 wysokości głowy (czoło odsłonięte niżej)
	d.fill_box(Vector3i(-hw, y1 - 1, -hd), Vector3i(hw + 1, y1 + P_HAIR_TOP, hd + 1), _C_HAIR)  # czapa + naddatek
	d.fill_box(Vector3i(-hw, hair_lo, hd, ), Vector3i(hw + 1, y1, hd + 1), _C_HAIR)             # tył (+Z)
	d.fill_box(Vector3i(-hw, hair_lo, -hd), Vector3i(-hw + 1, y1, hd + 1), _C_HAIR)             # lewy bok
	d.fill_box(Vector3i( hw, hair_lo, -hd), Vector3i(hw + 1, y1, hd + 1), _C_HAIR)              # prawy bok
	# GRZYWKA (front -Z) wydzielona do osobnego pivota _hair (_sculpt_fringe) — secondary motion (lag).
	# Pasemka połysku na czapie (światło z góry-przodu) — bez sterczących kosmyków.
	for hx in range(-hw + 1, hw, 2):
		d.set_voxel(Vector3i(hx, y1 + P_HAIR_TOP - 1, -hd + 1), _C_HAIR_HI)
	# --- TWARZ (front -Z) — CZYTELNA i proporcjonalna. Linia oczu na ~55% wysokości głowy. ---
	# WSZYSTKO liczone z hw/P_HEAD_H, więc twarz skaluje się ze zmianą proporcji głowy
	# (przy head_w=7 => hw=3: oczy przy x=±2; przy zwężeniu head_w=5 => hw=2: oczy przy x=±1).
	var eye_y := y0 + (P_HEAD_H * 11) / 20       # ~0,55 wysokości głowy
	var ex := maxi(1, hw - 1)                    # |x| oka: tuż przy krawędzi, ale nie na samym brzegu
	# OCZY: małe (tęczówka 1 voxel + źrenica nad nią), rozstawione symetrycznie. NIE gigantyczne.
	d.set_voxel(Vector3i(-ex, eye_y, fz), _C_IRIS);  d.set_voxel(Vector3i(-ex, eye_y + 1, fz), _C_PUPIL)
	d.set_voxel(Vector3i( ex, eye_y, fz), _C_IRIS);  d.set_voxel(Vector3i( ex, eye_y + 1, fz), _C_PUPIL)
	# Białko jako wąski błysk w kąciku oka (od strony skroni) — ożywia spojrzenie bez „wielkich oczu".
	d.set_voxel(Vector3i(-ex - 1, eye_y, fz), _C_EYE_W) if ex + 1 <= hw else d.set_voxel(Vector3i(-ex, eye_y, fz), _C_IRIS)
	d.set_voxel(Vector3i( ex + 1, eye_y, fz), _C_EYE_W) if ex + 1 <= hw else d.set_voxel(Vector3i( ex, eye_y, fz), _C_IRIS)
	# BRWI: krótka kreska nad każdym okiem (lekko uniesiona = sympatyczny wyraz).
	d.set_voxel(Vector3i(-ex, eye_y + 2, fz), _C_HAIR)
	d.set_voxel(Vector3i( ex, eye_y + 2, fz), _C_HAIR)
	# NOS: krótki grzbiet (1 voxel) z cieniem na osi — głębia profilu bez „ryjka".
	d.set_voxel(Vector3i(0, eye_y - 1, fz), _C_SKIN_SH)
	# USTA: subtelny uśmiech (3 voxele) poniżej nosa.
	var mouth_y := eye_y - 2
	d.set_voxel(Vector3i(-1, mouth_y, fz), _C_MOUTH); d.set_voxel(Vector3i(0, mouth_y, fz), _C_MOUTH)
	d.set_voxel(Vector3i( 1, mouth_y, fz), _C_MOUTH)
	# Rumieńce (drobny akcent na policzkach, po bokach ust).
	d.set_voxel(Vector3i(-ex, mouth_y, fz), _C_BLUSH); d.set_voxel(Vector3i(ex, mouth_y, fz), _C_BLUSH)

# FAZA 2: GRZYWKA jako osobny segment (pivot _hair u czoła) — lag/spring za ruchem glowy.
# Geometria w GLOBALNYCH y; _build_voxel_character bake'uje z offsetem pivota (fringe_pivot_y, _z),
# wiec kosmyki zwisaja w dol od mocowania u gory czoła i moga sie kolysac.
func _sculpt_fringe(d: VoxelModel.VoxelDef) -> void:
	var hw := P_HEAD_W / 2
	var hd := P_HEAD_D / 2
	var y1 := _HEAD_TOP
	# Grzywka na czole (front -Z), kilka voxeli wysoko — zwisa od czubka czoła.
	d.fill_box(Vector3i(-hw, y1 - 2, -hd - 1), Vector3i(hw + 1, y1, -hd), _C_HAIR)
	for hx in range(-hw + 1, hw, 2):
		d.set_voxel(Vector3i(hx, y1 - 1, -hd - 1), _C_HAIR_HI)   # rozjaśnienie grzywki

# FAZA 2: BROŃ/DŁOŃ jako osobny akcent (pivot _weapon u nadgarstka prawej reki) — kolysze sie za
# zamachem. Maly „implement" (rekojesc + krotka glownia/kij) zwisajacy z dloni. Geometria w
# GLOBALNYCH x/y; bake'owana z offsetem pivota (wrist_y, _ARM_X), wiec zwisa w dol od nadgarstka.
func _sculpt_weapon(d: VoxelModel.VoxelDef) -> void:
	var cx := _ARM_X
	var wrist_y := _ELBOW_Y - P_FARM_H + 2
	var dz := P_LIMB_D / 2
	# Rekojesc (skora) tuz pod nadgarstkiem.
	d.set_voxel(Vector3i(cx, wrist_y - 1, -dz), _C_LEATHER)
	# Krotka glownia/akcent ku przodowi (-Z) — czytelny element, ktory „dociaga" po ramieniu.
	d.fill_box(Vector3i(cx, wrist_y - 1, -dz - 2), Vector3i(cx + 1, wrist_y, -dz), _C_TRIM)
	d.set_voxel(Vector3i(cx, wrist_y - 1, -dz - 3), _C_TRIM)

# TUŁÓW — SMUKŁY kaftan/tunika z lekką talią (klepsydra), pasek, naramienniki, peleryna.
# Geometria parametryczna: y[_HIP_Y.._SHOULDER_Y), barki szer. P_SHOULDER_W (góra), pas P_WAIST_W
# (dół), głęb. P_TORSO_D. NIE: beczkowaty/szeroki korpus — sylwetka ma być wysmuklona, „na nogach".
func _sculpt_torso(d: VoxelModel.VoxelDef) -> void:
	var y0 := _HIP_Y                             # pas (dół tułowia)
	var y1 := _SHOULDER_Y                        # bark (góra tułowia)
	var sw := P_SHOULDER_W / 2                   # półszerokość barków (x[-sw..sw])
	var ww := P_WAIST_W / 2                      # półszerokość pasa
	var dz := P_TORSO_D / 2                      # półgłębokość (z[-dz..dz])
	var mid := (y0 + y1) / 2                     # wysokość talii (najwęższy punkt)
	# Korpus warstwami: szerokość interpoluje od pasa (dół) przez talię (najwęziej) do barków (góra).
	for yy in range(y0, y1):
		var t: float = float(yy - mid) / float(maxi(1, y1 - mid))   # 0 w talii -> 1 na barkach
		var half: int = ww if yy <= mid else ww + int(round(float(sw - ww) * t))
		half = clampi(half, ww - 1, sw)         # delikatne wcięcie talii o 1 poniżej środka
		if yy < mid:
			half = ww - 1 if yy == mid - 1 else ww     # zaznaczona talia tuż nad paskiem
		d.fill_box(Vector3i(-half, yy, -dz), Vector3i(half + 1, yy + 1, dz + 1), _C_TUNIC)
		d.fill_box(Vector3i(-half, yy, dz), Vector3i(half + 1, yy + 1, dz + 1), _C_TUNIC_SH)  # cień pleców
	# Boki w cieniu (bryła nie jest płaska) — lewa/prawa kolumna.
	d.fill_box(Vector3i(-sw, mid, -dz), Vector3i(-sw + 1, y1, dz + 1), _C_TUNIC_SH)
	d.fill_box(Vector3i( sw, mid, -dz), Vector3i( sw + 1, y1, dz + 1), _C_TUNIC_SH)
	# Złota lamówka pod szyją (dekolt w V) + rząd guzików na froncie (warstwa z=-dz-1 „nakładka").
	d.fill_box(Vector3i(-2, y1 - 1, -dz - 1), Vector3i(3, y1, -dz), _C_TRIM)
	for gy in range(y0 + 2, y1 - 1, 2):
		d.set_voxel(Vector3i(0, gy, -dz - 1), _C_TRIM)            # guziki
	# Naramienniki (złota „lekka zbroja" na szczycie barków).
	d.fill_box(Vector3i(-sw, y1 - 1, -dz), Vector3i(-sw + 2, y1, dz + 1), _C_TRIM)
	d.fill_box(Vector3i( sw - 1, y1 - 1, -dz), Vector3i(sw + 1, y1, dz + 1), _C_TRIM)
	# PASEK (2 dolne rzędy) dookoła pasa + klamra na froncie.
	d.fill_box(Vector3i(-ww, y0, -dz - 1), Vector3i(ww + 1, y0 + 2, dz + 1), _C_BELT)
	d.set_voxel(Vector3i(0, y0, -dz - 1), _C_BUCKLE)
	d.set_voxel(Vector3i(0, y0 + 1, -dz - 1), _C_BUCKLE)
	# PELERYNA: wydzielona do osobnego pivota _cape (_sculpt_cape) — secondary motion (kolysze sie
	# za tulowiem). Zapinki peleryny na barkach (złoto) zostaja na tulowiu (nieruchomy punkt mocowania).
	d.set_voxel(Vector3i(-sw + 1, y1 - 1, dz + 1), _C_TRIM); d.set_voxel(Vector3i(sw - 1, y1 - 1, dz + 1), _C_TRIM)

# FAZA 2: PELERYNA jako osobny segment (pivot _cape u nasady barkow) — kolysze sie za tulowiem.
# Geometria liczona w GLOBALNYCH y/z (jak reszta sculptow); _build_voxel_character bake'uje ja z
# offsetem pivota (cape_pivot_y, cape_pivot_z), wiec fala zwisa W DOL od mocowania na barkach.
func _sculpt_cape(d: VoxelModel.VoxelDef) -> void:
	var y0 := _HIP_Y                             # dol peleryny (na wysokosci pasa)
	var y1 := _SHOULDER_Y                        # gora peleryny (barki)
	var sw := P_SHOULDER_W / 2
	var dz := P_TORSO_D / 2
	# Warstwa peleryny na plecach (+Z) od barkow w dol — akcent koloru i ruch sylwetki.
	d.fill_box(Vector3i(-sw + 1, y0, dz + 1), Vector3i(sw, y1, dz + 2), _C_CAPE)
	d.fill_box(Vector3i(-sw + 1, y0, dz + 1), Vector3i(-1, y1, dz + 2), _C_CAPE_SH)   # cień fałdy (lewa)
	d.fill_box(Vector3i(1, y0, dz + 1), Vector3i(sw, y1, dz + 2), _C_CAPE_SH)         # cień fałdy (prawa)

# UDO (górny segment nogi, w spodniach). side=-1(L)/+1(R). y[_KNEE_Y.._HIP_Y).
# Bryła CENTROWANA na zawiasie biodra (x=±_LEG_X), szer. P_LEG_W, głęb. P_LIMB_D -> owalny przekrój.
# NIE: zbyt grube udo (klocek) — noga ma być wyraźna, lecz smukła.
func _sculpt_thigh(d: VoxelModel.VoxelDef, side: int) -> void:
	var cx := side * _LEG_X                       # środek nogi w X (zawias biodra)
	var x0 := cx - P_LEG_W / 2                    # lewy brzeg bryły
	var x1 := x0 + P_LEG_W                        # prawy brzeg (wyłączny)
	var dz := P_LIMB_D / 2
	# Udo (spodnie): pełny przód, tył w cieniu.
	d.fill_box(Vector3i(x0, _KNEE_Y, -dz), Vector3i(x1, _HIP_Y, dz + 1), _C_PANTS)
	d.fill_box(Vector3i(x0, _KNEE_Y, dz), Vector3i(x1, _HIP_Y, dz + 1), _C_PANTS_SH)   # cień z tyłu
	# Boczna fałda/szew (akcent na zewnętrznej stronie uda).
	var outer := (x0 if side < 0 else x1 - 1)
	d.fill_box(Vector3i(outer, _KNEE_Y + 1, -dz), Vector3i(outer + 1, _HIP_Y - 1, dz), _C_PANTS_SH)

# ŁYDKA + BUT (dolny segment nogi). side=-1/+1. y[0.._KNEE_Y): but [0.._ANKLE_Y), łydka wyżej.
func _sculpt_shin(d: VoxelModel.VoxelDef, side: int) -> void:
	var cx := side * _LEG_X
	var x0 := cx - P_LEG_W / 2
	var x1 := x0 + P_LEG_W
	var dz := P_LIMB_D / 2
	var fwd := P_FOOT_FWD                         # o ile but wystaje w przód (-Z)
	# Łydka (spodnie): od kostki do kolana.
	d.fill_box(Vector3i(x0, _ANKLE_Y, -dz), Vector3i(x1, _KNEE_Y, dz + 1), _C_PANTS)
	d.fill_box(Vector3i(x0, _ANKLE_Y, dz), Vector3i(x1, _KNEE_Y, dz + 1), _C_PANTS_SH)   # cień z tyłu
	# BUT: y[1.._ANKLE_Y+1), dłuższy w przód (czubek/palce na -Z). Cholewka (góra) rozjaśniona.
	d.fill_box(Vector3i(x0, 1, -dz - fwd), Vector3i(x1, _ANKLE_Y + 1, dz + 1), _C_BOOTS)
	d.fill_box(Vector3i(x0, _ANKLE_Y, -dz, ), Vector3i(x1, _ANKLE_Y + 1, dz + 1), _C_BOOTS_HI)  # rant cholewki
	d.fill_box(Vector3i(x0, 1, -dz - fwd), Vector3i(x1, 2, -dz), _C_BOOTS_HI)             # czubek (palce)
	# PODESZWA (y0) — ciemna, czytelny styk z gruntem (foot-plant feel). Sięga pod czubek.
	d.fill_box(Vector3i(x0, 0, -dz - fwd), Vector3i(x1, 1, dz + 1), _C_SOLE)

# RAMIĘ górne (rękaw kaftana + naramiennik). side=-1/+1. y[_ELBOW_Y.._SHOULDER_Y).
# Bryła CENTROWANA na zawiasie barku (x=±_ARM_X), szer. P_ARM_W. NIE: za cienkie „patyki".
func _sculpt_upper_arm(d: VoxelModel.VoxelDef, side: int) -> void:
	var cx := side * _ARM_X
	var x0 := cx - P_ARM_W / 2
	var x1 := x0 + P_ARM_W
	var dz := P_LIMB_D / 2
	# Rękaw kaftana (od barku do łokcia).
	d.fill_box(Vector3i(x0, _ELBOW_Y, -dz), Vector3i(x1, _SHOULDER_Y, dz + 1), _C_TUNIC)
	d.fill_box(Vector3i(x0, _ELBOW_Y, dz), Vector3i(x1, _SHOULDER_Y, dz + 1), _C_TUNIC_SH)  # cień rękawa
	d.fill_box(Vector3i(x0, _SHOULDER_Y - 1, -dz), Vector3i(x1, _SHOULDER_Y, dz + 1), _C_TRIM)  # naramiennik

# PRZEDRAMIĘ + DŁOŃ (dolny segment ręki). side=-1/+1. y[0(=łokieć-baza).._ELBOW_Y w skali pivota).
# UWAGA: bryła liczona w GLOBALNYCH y; segment wisi pod pivotem łokcia (_ELBOW_Y), więc dłoń
# spada poniżej. Karwasz (skóra/skórzany) + zarys dłoni z kciukiem od strony tułowia.
func _sculpt_forearm(d: VoxelModel.VoxelDef, side: int) -> void:
	var cx := side * _ARM_X
	var x0 := cx - P_ARM_W / 2
	var x1 := x0 + P_ARM_W
	var dz := P_LIMB_D / 2
	var hand_h := 2                               # wysokość dłoni (dolny fragment segmentu)
	var y_bot := _ELBOW_Y - P_FARM_H              # dolny koniec przedramienia+dłoni
	var y_wrist := y_bot + hand_h                 # nadgarstek (nad dłonią)
	# Przedramię w skórzanym karwaszu (od nadgarstka do łokcia).
	d.fill_box(Vector3i(x0, y_wrist, -dz), Vector3i(x1, _ELBOW_Y, dz + 1), _C_LEATHER)
	d.fill_box(Vector3i(x0, y_wrist, dz), Vector3i(x1, _ELBOW_Y, dz + 1), _C_TUNIC_SH)   # cień z tyłu
	# DŁOŃ (skóra) na dole segmentu.
	d.fill_box(Vector3i(x0, y_bot, -dz), Vector3i(x1, y_wrist, dz), _C_SKIN)
	# KCIUK (1 voxel po wewnętrznej stronie, ku tułowiu).
	var thumb_x := (x1 if side < 0 else x0 - 1)
	d.set_voxel(Vector3i(thumb_x, y_bot + 1, 0), _C_SKIN)
	# Cień kostek na grzbiecie dłoni (przód -Z).
	d.fill_box(Vector3i(x0, y_bot, -dz), Vector3i(x1, y_bot + 1, -dz + 1), _C_SKIN_SH)

func _build_camera() -> void:
	# Pivot: obraca się tylko w poziomie (yaw). NIE obracamy całej postaci,
	# żeby kamera i ruch się nie "biły".
	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	_pivot.position = Vector3(0.0, 1.6, 0.0)  # na wysokości "głowy"
	add_child(_pivot)

	# SpringArm: odsuwa kamerę do tyłu i automatycznie ją przysuwa,
	# gdy coś zasłoni (np. ściana), żeby nie patrzeć przez geometrię.
	# FAZA 5 (TUNING KAMERY pod world-aliveness/power-fantasy): odsunięta nieco dalej (5.0->5.6) —
	# więcej świata w kadrze (widać ambient creatures / roaming-elite / distant events i hordę 8-12
	# wrogów naraz), bez utraty czytelności postaci. Lekki DOMYŚLNY pitch w dół (model CW: patrzymy
	# na bohatera i teren wokół, nie w horyzont) — daje natychmiast bardziej "action-RPG" kadr.
	_spring = SpringArm3D.new()
	_spring.spring_length = 5.6
	_spring.rotation.x = deg_to_rad(-12.0)   # start lekko z góry; gracz i tak swobodnie reguluje myszą
	# Kolizja ramienia = shapecast KULĄ (gładszy na krawędziach voxeli niż raycast) + margines + jawna
	# maska = TYLKO teren (warstwa 1; gracz=2, wrogowie=3 nie wpychają kamery). SpringArm tylko MIERZY
	# dystans (get_hit_length); samo wygładzanie/pozycjonowanie robimy w _update_camera.
	var cam_probe := SphereShape3D.new()
	cam_probe.radius = 0.3
	_spring.shape = cam_probe
	_spring.margin = 0.3
	_spring.collision_mask = 1
	_pivot.add_child(_spring)
	_cam_dist = _spring.spring_length        # start na pełnej długości ramienia

	_camera = Camera3D.new()
	_camera.fov = base_fov           # bazowe FOV (sprint kick podbija je w _process)
	_spring.add_child(_camera)
	_camera.current = true

	# Pył lądowania (one-shot GPUParticles, wzorzec jak ambient w Main): tworzony raz, ponownie
	# „odpalany" przez restart() przy każdym lądowaniu. local_coords=false — pył zostaje w świecie.
	_land_dust = _make_land_dust()
	add_child(_land_dust)

	# Game feel (0C): kamera ODPIĘTA od gracza (top_level) — podąża z wygładzeniem w _process.
	_pivot.top_level = true
	_pivot.global_position = global_position + Vector3(0.0, 1.6, 0.0)
	# Interpolacja fizyki jest WŁ. globalnie, ale pivot pozycjonujemy ręcznie w _process
	# (już w tempie klatek) — wyłączamy go z interpolacji silnika, by nie był wygładzany
	# podwójnie (co dawałoby lag/smużenie kamery). Dzieci (spring/kamera) dziedziczą OFF.
	_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_shake_noise = FastNoiseLite.new()
	_shake_noise.seed = 7
	_shake_noise.frequency = 1.0

# Tworzy one-shot „obłoczek" pyłu pod stopami (wzorzec GPUParticles jak ambient w Main.gd).
# emitting=false na starcie; lądowanie woła restart()+emitting=true (one_shot sam wygasza).
func _make_land_dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 0.9       # cały burst naraz (puff), nie strużka
	p.local_coords = false      # pył zostaje w świecie, gdy postać biegnie dalej
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.gravity = Vector3(0.0, -1.2, 0.0)         # lekko opada
	pm.direction = Vector3(0.0, 0.3, 0.0)
	pm.spread = 75.0                              # rozłazi się na boki (płaski obłok)
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.4
	pm.damping_min = 2.0
	pm.damping_max = 4.0                          # szybko hamuje (puff, nie eksplozja)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.16, 0.16)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.74, 0.68, 0.56, 0.7)   # piaskowy kurz
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = mat
	p.draw_pass_1 = mesh
	return p

# Odpala obłoczek pyłu u stóp (siła ~ prędkość upadku). Wołane z _physics_process przy lądowaniu.
func _spawn_land_dust(strength: float) -> void:
	if _land_dust == null:
		return
	_land_dust.global_position = global_position    # u stóp (origin postaci = y=0)
	_land_dust.amount = int(clampf(10.0 + strength * 22.0, 10.0, 28.0))
	_land_dust.restart()
	_land_dust.emitting = true

# FEEL 7: lekki obloczek pylu spod stop przy biegu (re-use emitera _land_dust; mniej czastek niz
# ladowanie). Lekko za postacia (przeciwnie do ruchu), by "odbijal sie" od kroku.
func _spawn_sprint_dust() -> void:
	if _land_dust == null:
		return
	var back := Vector3(velocity.x, 0.0, velocity.z)
	if back.length() > 0.01:
		back = -back.normalized() * 0.3
	_land_dust.global_position = global_position + back
	_land_dust.amount = 6
	_land_dust.restart()
	_land_dust.emitting = true

# FAZA 4 (6): mocniejszy obloczek pylu PRZY OSTRYM ZWROCIE (poslizg). Wiecej czastek niz zwykly krok,
# pozycja po ZEWNETRZNEJ stronie zwrotu (przeciwnie do nowego kierunku — slad poslizgu). Reuse _land_dust.
func _spawn_turn_dust(new_dir: Vector3) -> void:
	if _land_dust == null:
		return
	var offset := -new_dir * 0.35       # po zewnetrznej stronie zwrotu (za nowym kierunkiem)
	_land_dust.global_position = global_position + offset
	_land_dust.amount = 10
	_land_dust.restart()
	_land_dust.emitting = true

func _unhandled_input(event: InputEvent) -> void:
	# Ruch myszy obraca kamerę (gdy kursor jest złapany).
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		_spring.rotate_x(-event.relative.y * mouse_sensitivity)
		# Ogranicz pochylenie, żeby nie "przekręcić" kamery.
		_spring.rotation.x = clampf(_spring.rotation.x, deg_to_rad(-70.0), deg_to_rad(30.0))

	# ESC: pokaż/ukryj kursor (przydatne, żeby wyjść z gry).
	# ETAP 8: jeśli w grze jest PauseMenu, ESC należy DO NIEGO (pauza), nie do toggle kursora —
	# inaczej jeden ESC zrobiłby PODWÓJNĄ akcję (kursor + pauza). PauseMenu konsumuje zdarzenie
	# w swoim _unhandled_input; gdyby dotarło tu mimo to, ten gate i tak nie odpala toggle myszy.
	if event.is_action_pressed("ui_cancel"):
		if not _pause_menu_present():
			_toggle_mouse()

	# --- WALKA: klik myszy (tylko gdy kursor złapany, by klik w odsłoniętym kursorze nie atakował) ---
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_attack()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_try_dodge()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_toggle_lock_on()      # FAZA 1: MMB = lock/unlock najblizszego wroga

	# FAZA 1: LOCK-ON (Tab). Toggle najblizszego wroga (grupa "enemies"); ponowny Tab przy aktywnym
	# locku zdejmuje go. Tylko nasz input (SP/klient-wlasciciel); brak wplywu na HP/siec.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventKey and event.pressed \
			and not event.echo and event.physical_keycode == KEY_TAB:
		_toggle_lock_on()

	# ETAP 3: R = finisher zasobu klasy (Wojownik: Wir Ostrzy, 30 Furii). AbilityComponent pilnuje
	# kosztu/CD; brak Furii -> try_use po prostu nie odpali (bufor wygasa). Nie psuje LMB/RMB.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventKey and event.pressed \
			and not event.echo and event.physical_keycode == KEY_R:
		_try_finisher()

	# ETAP 6: T = oswajanie najblizszej bestii (gate lvl 5 + cel <35% HP + item-oswajacz). TameSystem
	# pilnuje warunkow i 1-aktywnego-peta; brak warunkow -> tame_failed (no-op dla rozgrywki).
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventKey and event.pressed \
			and not event.echo and event.physical_keycode == KEY_T:
		if _tame != null:
			_tame.try_tame()

func _toggle_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## ETAP 8: ustawia czulosc myszy = baza * mnoznik (z GameSettings/SettingsMenu). Suwak ustawien
## woła to przez GameSettings.apply_mouse(). Mnoznik >0; zabezpieczamy przed 0/ujemnym (kamera by stanela).
func set_mouse_sensitivity_mult(mult: float) -> void:
	mouse_sensitivity = MOUSE_SENS_BASE * maxf(0.01, mult)

## ETAP 8: bezpieczne SFX przez AudioManager (autoload). No-op gdy brak autoloadu (test/headless) lub
## pliku audio (placeholder). Tylko lokalny gracz dudni dzwiekiem akcji — repliki/cudze postacie nie
## (inaczej w co-opie kazdy slyszalby N nakladajacych sie zamachow). _net_sync==null => SP (gra).
func _play_sfx(id: StringName, pitch: float = 1.0) -> void:
	if _net_sync != null and not _net_sync.should_read_local_input():
		return    # to nie NASZA postac (replika/symulacja cudza) — dzwiek akcji gra wlasciciel u siebie
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.play_sfx(id, pitch)

## ETAP 8: czy w drzewie istnieje PauseMenu (Main go dodaje). Jesli tak, ESC obsluguje pauza,
## a Player NIE przelacza kursora (uniknij podwojnej akcji). Brak (test/headless) = stary toggle dziala.
func _pause_menu_present() -> bool:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return false
	return tree.root.find_child("PauseMenu", true, false) != null

# Game feel (0C): kamera podąża z wygładzeniem/lagiem + trauma-shake + (JUICE) FOV kick i walk-bob.
func _update_camera(delta: float) -> void:
	if _pivot == null:
		return
	# Podążaj za INTERPOLOWANĄ pozycją gracza (gładką między krokami fizyki), nie za
	# surową global_position (skokową w tempie fizyki) — inaczej kamera „skacze".
	var target := get_global_transform_interpolated().origin + Vector3(0.0, 1.6, 0.0)
	_pivot.global_position = _pivot.global_position.lerp(target, 1.0 - exp(-cam_follow * delta))
	_trauma = maxf(0.0, _trauma - trauma_decay * delta)
	var s := _trauma * _trauma
	if _camera == null:
		return

	# JUICE: SPRINT FOV KICK — przy biegu FOV rośnie (poczucie pędu), wraca przy chodzie/staniu.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var is_sprint := hspeed > speed + 0.6 and is_on_floor()
	var fov_target := base_fov + (sprint_fov_add if is_sprint else 0.0)
	_camera.fov = lerpf(_camera.fov, fov_target, _sm(fov_lerp, delta))

	# JUICE: WALK-BOB kamery (MAŁY) — pionowe „tętno" kroku, tylko przy ruchu po ziemi.
	var bob_off := Vector3.ZERO
	if hspeed > 0.6 and is_on_floor():
		_cam_bob_phase += delta * hspeed * 1.9
		var amp := cam_bob_amount * clampf(hspeed / sprint_speed, 0.4, 1.0)
		bob_off.y = -absf(sin(_cam_bob_phase)) * amp       # opada na każdym kroku
		bob_off.x = sin(_cam_bob_phase) * amp * 0.4        # delikatne kołysanie boczne
	else:
		_cam_bob_phase = 0.0

	# BOOM (oś -Z): WŁASNE wygładzanie długości ramienia zamiast skokowego auto-pozycjonowania SpringArm.
	# get_hit_length() = dystans po kolizji (lub pełny w otwartym terenie). To naprawia DRGANIA: dawniej
	# SpringArm ustawiał camera.z, a poniższy kod nadpisywał całe _camera.position z z=0 → bicie fizyka↔render.
	_cam_dist = _smooth_boom(_spring.get_hit_length(), delta)

	# BOB + SHAKE jako offset X/Y (NIGDY nie dotyka boom-Z). z = -_cam_dist ustawiamy bezpośrednio.
	var off := bob_off
	if s > 0.0:
		# Wstrząs dominuje nad walk-bobem (lądowanie/trafienie) — krótkie, więc OK.
		_shake_time += delta
		var nx := _shake_noise.get_noise_2d(_shake_time * 50.0, 0.0)
		var ny := _shake_noise.get_noise_2d(0.0, _shake_time * 50.0)
		var nr := _shake_noise.get_noise_2d(_shake_time * 50.0, 99.0)
		off += Vector3(nx, ny, 0.0) * s * shake_pos
		_camera.rotation.z = nr * s * shake_roll
	else:
		_camera.rotation.z = lerpf(_camera.rotation.z, 0.0, _sm(12.0, delta))
	_cam_off = _cam_off.lerp(off, _sm(12.0, delta))             # wygładzony offset x/y (bob/shake)
	_camera.position = Vector3(_cam_off.x, _cam_off.y, -_cam_dist)

# Wygładzanie długości ramienia kamery: asymetria „do środka" (szybko, anty-clip) vs „na zewnątrz"
# (wolno, bez szarpniętego zoomu). hit_len = wynik shapecastu SpringArm. Mutuje i zwraca _cam_dist.
func _smooth_boom(hit_len: float, delta: float) -> float:
	var k_boom := boom_in_speed if hit_len < _cam_dist else boom_out_speed
	_cam_dist = lerpf(_cam_dist, hit_len, _sm(k_boom, delta))
	return _cam_dist

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

# ============================================================================
#  ANIMACJA PROCEDURALNA (Veloren-feel: ciężar, foot-plant, przeciwfaza, zgięcia)
# ============================================================================
# Cała animacja jest FRAME-RATE INDEPENDENT:
#  * ruch cykliczny = sin/cos(_walk_phase), gdzie _walk_phase += delta*tempo (czas, nie klatki),
#  * wygładzanie/dosztywnianie = lerp z czynnikiem 1-exp(-k*delta) (stała szybkość niezależna od FPS).
# Konwencja stawów. Segmenty WISZĄ poniżej swoich pivotów (y<0 względem zawiasu). Obrót wokół
# +X: z' = y*sinθ, więc dla y<0: θ>0 => z'<0 (segment do PRZODU, -Z), θ<0 => z'>0 (do TYŁU, +Z).
# Stąd kierunki naturalnych zgięć:
#   * udo/bark w PRZÓD  => rotation.x DODATNI (a w tył => ujemny),
#   * KOLANO (pięta ku górze, do TYŁU) => rotation.x UJEMNY na dolnym pivocie,
#   * ŁOKIEĆ (dłoń ku twarzy, do PRZODU) => rotation.x DODATNI na dolnym pivocie.
# (Zachowujemy fazowanie hip = -sin(phase), zgodne z oryginalnym, działającym chodem.)

# Wygładzanie wykładnicze (frame-rate independent): zwraca alpha do lerp(a,b,alpha).
func _sm(k: float, delta: float) -> float:
	return 1.0 - exp(-k * delta)

# Wizualne: wybór stanu animacji + tułów (bob/lean/twist) + stabilizacja głowy. Sterownik główny.
func _process(delta: float) -> void:
	_update_camera(delta)
	if _model == null:
		return

	# FEEL (5): spawn duchow afterimage w trakcie dasha (co AFTERIMAGE_INTERVAL, lacznie 3).
	if _afterimage_left > 0:
		_afterimage_t -= delta
		if _afterimage_t <= 0.0:
			_afterimage_t = AFTERIMAGE_INTERVAL
			_afterimage_left -= 1
			_spawn_afterimage()

	# --- Regeneracja staminy w czasie (po krótkiej ciszy od ostatniego wydatku), gdy gracz żyje ---
	if not is_dead:
		_stamina_idle += delta
		if _stamina_idle >= stamina_regen_delay and stamina < max_stamina:
			stamina = minf(max_stamina, stamina + stamina_regen * delta)
			stamina_changed.emit(stamina, max_stamina)

	# --- Pomiary stanu ---
	var hvel := Vector2(velocity.x, velocity.z)
	var hspeed := hvel.length()
	var on_floor := is_on_floor()
	var sprinting := hspeed > speed + 0.6        # próg „bieg" (powyżej zwykłej prędkości chodu)
	_idle_phase += delta                          # zegar idle (oddychanie) — biegnie zawsze
	# Gaśnięcie przysiadu lądowania (squash) — niezależne od FPS.
	_land_squash = maxf(0.0, _land_squash - delta * 4.0)

	# FAZA 1: utrzymanie locka (zdejmij martwy/daleki cel) + pozycja wskaznika nad celem.
	_update_lock_on(delta)

	# --- OBRÓT MODELU: w trakcie ataku ku celowi/kamerze; przy locku STRAFE (twarz do celu);
	#     inaczej w stronę ruchu. ---
	var locked := _lock_target != null and is_instance_valid(_lock_target)
	if is_attacking:
		# Cel obrotu: jesli lock -> ku celowi (cios trafia), inaczej yaw kamery (jak dotad).
		var atk_yaw := _pivot.rotation.y
		if locked:
			var tl: Vector3 = _lock_target.global_position - global_position
			tl.y = 0.0
			if tl.length() > 0.05:
				atk_yaw = atan2(-tl.x, -tl.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, atk_yaw, _sm(18.0, delta))
	elif locked:
		# STRAFE wzgledem locka: model patrzy NA CEL niezaleznie od kierunku ruchu (kroki w bok).
		var tl2: Vector3 = _lock_target.global_position - global_position
		tl2.y = 0.0
		if tl2.length() > 0.05:
			_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-tl2.x, -tl2.z), _sm(14.0, delta))
	elif hspeed > 0.5:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, _sm(12.0, delta))

	# FAZA 1: LEAN WIZUALNY proporcjonalny do PRZYSPIESZENIA poziomego (waga ruchu). Liczymy zmiane
	# predkosci miedzy klatkami i rzutujemy ja na os PRZOD/BOK MODELU: przyspieszanie -> tulow do
	# przodu, hamowanie -> do tylu, ostry skret -> przechyl na zewnatrz. Czysto wizualne (czytane w
	# _animate_torso), zero wplywu na fizyke/auto-step. dt>0 zabezpiecza przed dzieleniem przez 0.
	if delta > 0.0:
		var acc := (Vector3(velocity.x, 0.0, velocity.z) - _prev_hvel) / delta
		# Bazis modelu: -Z = przod modelu, +X = prawo modelu.
		var m_fwd := -_model.global_transform.basis.z; m_fwd.y = 0.0
		var m_right := _model.global_transform.basis.x; m_right.y = 0.0
		var lean_fwd_t := 0.0
		var lean_turn_t := 0.0
		if m_fwd.length() > 0.01:
			lean_fwd_t = clampf(m_fwd.normalized().dot(acc) / 60.0, -1.0, 1.0) * lean_max
		if m_right.length() > 0.01:
			lean_turn_t = clampf(m_right.normalized().dot(acc) / 60.0, -1.0, 1.0) * lean_max
		_lean_vel = lerpf(_lean_vel, lean_fwd_t, _sm(9.0, delta))
		_lean_turn = lerpf(_lean_turn, lean_turn_t, _sm(9.0, delta))
	_prev_hvel = Vector3(velocity.x, 0.0, velocity.z)

	# --- BLEND WEIGHTS (wygładzane, anti-pop): przejścia idle<->chód<->bieg<->lot bez „strzału" ---
	# Te trzy wagi są FAKTYCZNIE czytane przez _anim_locomotion/_animate_torso/_animate_head
	# (mnożą amplitudy / interpolują pary chód-bieg / cross-fade ziemia-powietrze):
	# _gait: 0 gdy stoi, 1 przy pełnej prędkości chodu — wygładza WEJŚCIE w cykl kroku, by nogi nie
	#        „skakały" z pozy idle do pełnego zamachu (mnoży swing/bend/lean/twist/roll/bob/łokcie).
	# _run_blend: 0=chód, 1=bieg — interpoluje WSZYSTKIE pary amplitud/tempo (koniec popu na progu biegu).
	# _air_blend: 0=ziemia, 1=powietrze — cross-fade rytmu kroku tułowia/głowy i skali leanu w locie.
	var gait_target := clampf((hspeed - _LOCO_MIN_SPEED) / maxf(0.1, speed - _LOCO_MIN_SPEED), 0.0, 1.0) if on_floor else 0.0
	var run_target := clampf((hspeed - speed) / maxf(0.5, sprint_speed - speed), 0.0, 1.0)
	_gait = lerpf(_gait, gait_target, _sm(8.0, delta))
	_run_blend = lerpf(_run_blend, run_target, _sm(6.0, delta))
	_air_blend = lerpf(_air_blend, 0.0 if on_floor else 1.0, _sm(10.0, delta))

	# --- WYBÓR STANU NÓG/RĄK ---
	# Priorytet: powietrze > chód/bieg > idle. Atak nadpisuje TYLKO ręce (nogi grają normalnie).
	# Cykl kroku liczymy na ziemi powyżej _LOCO_MIN_SPEED (ten sam próg co start narastania _gait),
	# a _gait skaluje amplitudę — start/stop ruchu jest płynny (nogi „rozkręcają się", nie skaczą).
	# Tułów/głowa NIE mają osobnego progu prędkości — mieszają się przez _gait/_air_blend, więc
	# nogi i tułów wchodzą w lokomocję RAZEM (koniec rozjazdu progów nogi vs tułów).
	if not on_floor:
		_anim_air(delta, hspeed)
	elif hspeed > _LOCO_MIN_SPEED:
		_anim_locomotion(delta, hspeed, sprinting)
	else:
		_anim_idle(delta)

	# Atak nadpisuje ramiona (po wyliczeniu lokomocji/idle dla nóg i tułowia).
	if is_attacking:
		_anim_attack_arms(delta)

	# --- TUŁÓW: pionowy bob + lean (do przodu wg prędkości) + twist (wg fazy kroku) ---
	_animate_torso(delta, hspeed, on_floor, sprinting)
	# --- GŁOWA: stabilizacja (kompensuje bob/lean tułowia) + subtelny oddech-nod ---
	_animate_head(delta, hspeed)

	# FAZA 2: warstwa ADDITIVE (breath/sway + secondary-motion + squash/stretch + atak-twist +
	# hit-react + death) NAKLADANA na baze — OSTATNI krok, wiec nie rusza przetestowanej logiki Fazy 1.
	_breath_phase += delta
	_anim_additive(delta)

# FAZA 2 — ADDITIVE: breath/sway, secondary motion (lag), squash/stretch, atak-twist, hit-react, death.
# Wszystko NAKLADANE (+=) na baze ustawiona przez locomotion/idle/air/torso/head. Czysto wizualne,
# frame-rate independent. Kapsula/kamera/HP nietkniete. Kazda warstwa niezaleznie wylaczalna.
func _anim_additive(delta: float) -> void:
	if _torso == null:
		return
	var dt := minf(delta, 0.05)            # clamp dt (stabilnosc springow przy spadku FPS)

	# === WARSTWA 7 (DEATH) — dominuje, gdy martwy: poza przewrocenia, pomijamy reszte ===
	if _dying:
		_death_t = minf(1.0, _death_t + delta * 2.2)              # ~0.45 s do pelnej pozy
		var e := _death_t * _death_t * (3.0 - 2.0 * _death_t)     # smoothstep
		_model.rotation.z = e * 1.45                              # upadek na bok (~83 stopni)
		_torso.rotation.x += e * 0.5                              # kuli sie
		_head.rotation.x += e * 0.4
		_arm_l.rotation.x += e * 0.3; _arm_r.rotation.x += e * 0.3   # rece bezwladnie
		_model.scale = Vector3(_model.scale.x, (1.0 + _stretch) * (1.0 - e * 0.2), _model.scale.z)
		return

	# === FRAME-RATE INDEPENDENCE: zdejmij nakladke z POPRZEDNIEJ klatki, zanim policzymy swieza. ===
	# _animate_torso/_animate_head robia lerpf(rotation, cel, _sm) czytajac WLASNE rotation — gdyby
	# nakladka additive zostala wbita w rotation, lerp by ja wsiakal i amplituda rosla z FPS. Dlatego
	# nakladka jest NIE-KUMULACYJNA: usuwamy ostatnia, akumulujemy nowa do _add_*, nakladamy raz na koncu.
	_torso.rotation -= _add_torso
	_head.rotation -= _add_head
	_add_torso = Vector3.ZERO
	_add_head = Vector3.ZERO

	# === WARSTWA 2 (ODDECH/SWAY) — nakladany na KAZDY stan; amplituda mocniejsza w spoczynku ===
	var breath := sin(_breath_phase * 1.6)                        # ~0.26 Hz, spokojny rytm
	var breath_amp := lerpf(1.0, 0.35, _gait)                    # w ruchu wyciszony (~35%)
	_torso.position.y += breath * 0.010 * breath_amp             # uniesienie klatki (wdech) — position.y
	#  ustawiana absolutnie przez _animate_torso, wiec NIE wymaga un-bake (nadpisywana co klatke).
	var inhale := maxf(0.0, breath) * 0.02 * breath_amp         # mikro-rozszerzenie klatki przy wdechu
	_torso.scale = Vector3(1.0 - inhale * 0.3, 1.0 + inhale, 1.0 + inhale * 0.6)
	var shift := sin(_breath_phase * 0.5) * 0.018 * lerpf(1.0, 0.2, _gait)   # idle weight-shift (roll)
	_add_torso.z += shift
	_add_head.x += breath * 0.012 * breath_amp                   # delikatny nod oddechu

	# === WARSTWA 5 (ATAK: twist korpusu spiety z faza) — additive do torso.rotation.y ===
	if _atk_phase == AtkPhase.ANTICIPATION:
		_add_torso.y += lerpf(0.0, 0.22, 1.0 - _atk_phase_t / maxf(0.01, _atk_anticipation))
	elif _atk_phase == AtkPhase.ACTIVE:
		_add_torso.y += lerpf(0.22, -0.18, 1.0 - _atk_phase_t / maxf(0.01, _atk_active))
	elif _atk_phase == AtkPhase.RECOVERY:
		_add_torso.y += lerpf(-0.18, 0.0, 1.0 - _atk_phase_t / maxf(0.01, _atk_recovery))

	# === WARSTWA 6 (HIT-REACT) — krotkie zachwianie tulowia+glowy od ciosu (gasnie ~0.12 s) ===
	if _hitreact_t > 0.0:
		_hitreact_t = maxf(0.0, _hitreact_t - delta)
		var f := _hitreact_t / HITREACT_TIME
		var amp := f * f                                          # ostre na starcie, miekko gasnie
		var local := _model.global_transform.basis.inverse() * _hitreact_dir   # kierunek w lokalu modelu
		_add_torso.x += local.z * 0.18 * amp                     # pochyl wzdluzny od/ku zrodlu
		_add_torso.z += -local.x * 0.14 * amp                    # przechyl boczny
		_add_head.x += local.z * 0.12 * amp                      # glowa szarpie mocniej
		_add_head.z += -local.x * 0.10 * amp

	# Naloz swieza nakladke RAZ (przed warstwa secondary-motion, by springi lagowaly za pelna,
	# WIDOCZNA poza tulowia/glowy — overlay wlacznie). Nakladka zostanie zdjeta na poczatku nastepnej
	# klatki, zanim _animate_torso/_animate_head policza baze, wiec nigdy nie kumuluje sie w lerp.
	_torso.rotation += _add_torso
	_head.rotation += _add_head

	# === WARSTWA 4 (SQUASH/STRETCH) — jeden skalar -> skala modelu z zachowaniem objetosci ===
	_stretch_target = 0.0
	_stretch_target += clampf(absf(velocity.y) / 14.0, 0.0, 1.0) * 0.12 * _air_blend   # lot: rozciagniecie
	_stretch_target -= _land_squash * 0.18                       # ladowanie: zgniecenie (wzmocniony _land_squash)
	if _jump_antic_t > 0.0:
		_jump_antic_t = maxf(0.0, _jump_antic_t - delta)
		_stretch_target -= 0.10                                  # anticipation skoku: przysiad (krotkie okno)
	if _atk_phase == AtkPhase.ANTICIPATION:
		_stretch_target -= 0.05 * (1.0 - _atk_phase_t / maxf(0.01, _atk_anticipation))
	elif _atk_phase == AtkPhase.ACTIVE:
		_stretch_target += 0.06                                  # atak: "pchniecie" sylwetki
	_stretch = lerpf(_stretch, _stretch_target, _sm(18.0, delta))
	var sy := 1.0 + _stretch
	var sxz := 1.0 / sqrt(maxf(0.2, sy))                         # zachowanie objetosci
	_model.scale = Vector3(sxz, sy, sxz)

	# === WARSTWA 3 (SECONDARY MOTION) — spring-lag akcentow za predkoscia katowa rodzicow ===
	# Pol-jawny Euler tlumionego springu: vel += (target - ang)*stiff*dt - vel*damp*dt. Clamp dt.
	# PELERYNA: driver = zmiana pitcha tulowia + skladowa biegu (powiew do tylu przy ruchu na ziemi).
	var torso_pitch_vel := (_torso.rotation.x - _prev_torso_x) / maxf(dt, 0.001)
	var cape_drive := -torso_pitch_vel * 0.06 - _gait * 0.25 * (1.0 - _air_blend)
	_cape_vel += (cape_drive - _cape_ang) * 90.0 * dt - _cape_vel * 14.0 * dt
	_cape_ang += _cape_vel * dt
	if _cape != null: _cape.rotation.x = clampf(_cape_ang, -0.6, 0.6)
	# GRZYWKA: driver = predkosc katowa glowy (bob/nod) -> wlosy podskakuja z lagiem.
	var head_vel := (_head.rotation.x - _prev_head_x) / maxf(dt, 0.001)
	_hair_vel += (-head_vel * 0.5 - _hair_ang) * 120.0 * dt - _hair_vel * 16.0 * dt
	_hair_ang += _hair_vel * dt
	if _hair != null: _hair.rotation.x = clampf(_hair_ang, -0.35, 0.35)
	# BRON/DLON: lag za zamachem ramienia (najsilniejszy w ataku — bron "dociaga" po reke).
	# Gain 0.035 (nie 0.12): zamach ACTIVE to ~35 rad/s, wiec target ~1.2 rad — clamp 0.5 nie saturuje
	# sie na cala faze (proporcjonalny lag widoczny zamiast "przypiecia do limitu"). Stan wewnetrzny
	# _wpn_ang TEZ clampowany po calkowaniu, by nie narastal ponad display i nie odplywal po zamachu.
	var arm_vel := (_arm_r.rotation.x - _prev_arm_r_x) / maxf(dt, 0.001)
	_wpn_vel += (-arm_vel * 0.035 - _wpn_ang) * 80.0 * dt - _wpn_vel * 12.0 * dt
	_wpn_ang = clampf(_wpn_ang + _wpn_vel * dt, -0.5, 0.5)
	if _weapon != null: _weapon.rotation.x = _wpn_ang
	# Zapamietaj bazy do liczenia predkosci katowej w nastepnej klatce.
	_prev_torso_x = _torso.rotation.x
	_prev_head_x = _head.rotation.x
	_prev_arm_r_x = _arm_r.rotation.x

# FAZA 2 — FOOT IK / FOOT PLANTING (2-kosciowe IK biodro->kolano->stopa, analityczne).
# W fazie PODPORU stopa jest NIERUCHOMA wzgledem ziemi (kompensuje ruch biodra do przodu = koniec
# slizgu); w fazie PRZENOSZENIA leci po luku z uniesieniem. Raycast w dol dobiera wysokosc gruntu
# (foot-plant na nierownym terenie). Rusza WYLACZNIE rotation.x pivotow wizualnych — kapsula i
# kamera nietkniete. Konwencja: udo do przodu = +rot.x (hip), kolano gnie do tylu = -rot.x (knee).
const _IK_K: float = 22.0   # smoothing nog (jak dotychczasowe _sm(22) na kolanach)

func _foot_ik_leg(hip: Node3D, knee: Node3D, phase_off: float,
		stride: float, lift: float, delta: float) -> void:
	var ph := _walk_phase + phase_off
	var swing_phase := sin(ph)
	var foot_z: float                          # +Z = tyl, -Z = przod (konwencja modelu)
	var foot_lift: float                        # uniesienie stopy nad podloge (m)
	if swing_phase > 0.0:
		# SWING: noga przenosi sie z tylu (+stride) do przodu (-stride) po luku; pieta sie podrywa.
		var u := (cos(ph) * -0.5 + 0.5)         # 0->1 gladko przez faze swingu
		foot_z = lerpf(stride, -stride, u)
		foot_lift = sin(u * PI) * lift           # luk uniesienia, 0 na koncach
	else:
		# STANCE (FOOT PLANT): stopa nieruchoma wzgledem ziemi. W ukladzie biodra (jadacego do
		# przodu) stopa zostaje w tyle => przesuwa sie LINIOWO -przod -> +tyl = kotwica. Zero uniesienia.
		var u2 := (cos(ph) * 0.5 + 0.5)          # 0 (touchdown) -> 1 (toe-off), liniowo w stance
		foot_z = lerpf(-stride, stride, u2)
		foot_lift = 0.0
	# RAYCAST w dol pod biodro dla realnej wysokosci gruntu (foot-plant na nierownym terenie).
	# Maska=1 (teren), exclude=[self]. Bezpieczne headless: brak swiata fizyki => brak hitu => 0.
	var ground_drop := 0.0
	var world := get_world_3d()
	if world != null and world.direct_space_state != null:
		var hip_world := hip.global_position
		var ro := hip_world + Vector3(0.0, 0.2, 0.0)
		var rq := PhysicsRayQueryParameters3D.create(ro, ro + Vector3(0.0, -(float(_HIP_Y) * VS + 0.6), 0.0), 1)
		rq.exclude = [self]
		var hit := world.direct_space_state.intersect_ray(rq)
		if hit:
			# WYZSZY grunt (hit.y > poziom stop = global_position.y) PODNOSI stope: +ground_drop ->
			# target.y mniej ujemny (stopa wyzej). Wczesniej odwrocony znak wpychal stope W WYZSZY teren
			# (schody/auto-step/zbocze). global_position to poziom stop (kapsula wycentrowana na body_h*0.5).
			ground_drop = clampf((hit.position.y - global_position.y), -0.25, 0.25)
	# Cel stopy w LOKALU biodra (X=0; Z=krok; Y w dol). UWAGA: cel NIE siega pelnej dlugosci nogi —
	# zostawiamy ~12% luzu (stand_drop), by przy kroku fore/aft noga miala zapas i kolano moglo sie
	# ugiac (nie ma przeprostu/clampu zasiegu). To naturalna, lekko ugieta postawa stojaca.
	var leg_len := float(_HIP_Y) * VS
	var stand_drop := leg_len * 0.94               # bazowa wysokosc bioder nad stopa (luz na zgiecie)
	var target_local := Vector3(0.0, -(stand_drop - foot_lift) + ground_drop, foot_z)
	# --- 2-BONE IK (prawo cosinusow) ---
	var L1 := float(_HIP_Y - _KNEE_Y) * VS       # udo (hip->knee)
	var L2 := float(_KNEE_Y) * VS                # lydka+but (knee->podeszwa)
	var d := clampf(target_local.length(), maxf(0.001, absf(L1 - L2) + 0.001), L1 + L2 - 0.001)
	# Kat w kolanie (prawo cosinusow), zamieniony na zgiecie -rot.x (clamp ujemny = anti-lamanie).
	var cos_knee := clampf((L1 * L1 + L2 * L2 - d * d) / (2.0 * L1 * L2), -1.0, 1.0)
	var knee_inner := acos(cos_knee)             # PI = proste, mniej = zgiete
	var knee_bend := -(PI - knee_inner)          # UJEMNY (gnie do tylu) — zgodne z konwencja
	# Kat biodra: kierunek do celu (plaszczyzna YZ; przod=-Z, dol=-Y) + korekta na trojkat IK.
	var aim := atan2(-target_local.z, -target_local.y)   # 0 = noga prosto w dol
	var cos_hip := clampf((L1 * L1 + d * d - L2 * L2) / (2.0 * L1 * d), -1.0, 1.0)
	var hip_corr := acos(cos_hip)
	var hip_ang := aim + hip_corr                # udo wychylone tak, by stopa trafila w cel
	hip.rotation.x = lerpf(hip.rotation.x, hip_ang, _sm(_IK_K, delta))
	knee.rotation.x = lerpf(knee.rotation.x, minf(knee_bend, -0.02), _sm(_IK_K, delta))

# --- CHÓD / BIEG -----------------------------------------------------------
# Naturalny, WAŻONY krok: biodra w przeciwfazie, ramiona w przeciwfazie do nóg, kolana
# zginają się TYLKO w fazie przenoszenia (foot-plant w podporze), łokcie „pompują" w rytm
# barku. Amplitudy narastają płynnie z prędkością. ANTY-„POŁAMANE": kolano gnie się WYŁĄCZNIE
# do tyłu (clamp na ujemne), nigdy nie odwraca stawu w drugą stronę.
#
# ANTY-POP (kluczowe): wszystkie amplitudy/tempo czytają WYGŁADZONE wagi z _process zamiast
# surowej prędkości i twardego boola „sprinting":
#   * _gait (0->1, idle->pełny chód) MNOŻY wszystkie amplitudy => nogi/ręce ROZKRĘCAJĄ się z idle,
#     a nie skaczą w pełny zamach (eliminuje „klik" kolana i przeskok zamachu na starcie ruchu),
#   * _run_blend (0->1, chód->bieg) INTERPOLUJE pary chód/bieg (swing/bend/tempo/łokcie) =>
#     na progu biegu (hspeed≈speed) nic nie przeskakuje skokowo — przejście jest ciągłe.
func _anim_locomotion(delta: float, _hspeed: float, _sprinting: bool) -> void:
	# Kadencja (tempo): interpolowana chód<->bieg wagą _run_blend (bez skoku na progu biegu).
	# Tempo skaluje z fazą kroku; przy starcie z idle _gait dławi prędkość rozwoju fazy, więc
	# faza nie „strzela" od zera (nogi wchodzą w cykl miękko).
	var cadence := lerpf(1.8, 2.05, _run_blend)
	_walk_phase += delta * sprint_speed * lerpf(0.55, 1.0, _gait) * cadence * (0.6 + 0.4 * _run_blend)
	# Amplitudy: para chód/bieg wybierana _run_blend, całość skalowana _gait (rozruch z idle).
	var swing := lerpf(0.62, 0.95, _run_blend) * _gait              # zamach uda/ramienia (rad)
	var ph := _walk_phase
	var s := sin(ph)

	# NOGI — FAZA 2: FOOT IK / FOOT PLANTING. Zamiast czystej sinusoidy hip/knee (slizg), 2-kosciowe
	# IK kotwiczy stope w fazie PODPORU (nieruchoma wzgledem ziemi), raycast dobiera wysokosc gruntu.
	# To RDZEN fixu sztywnosci (jedyna ingerencja w baze locomocji — uzasadniona). L=faza 0, R=faza PI.
	var stride := lerpf(0.14, 0.22, _run_blend) * _gait     # dlugosc kroku (m) skaluje z biegiem/rozruchem
	var lift := lerpf(0.06, 0.12, _run_blend) * _gait       # uniesienie stopy w swingu (m)
	_foot_ik_leg(_leg_l, _leg_l_lo, 0.0, stride, lift, delta)
	_foot_ik_leg(_leg_r, _leg_r_lo, PI, stride, lift, delta)

	# RĘCE — barki w PRZECIWFAZIE do nóg (ramię L z nogą R). Atak nadpisze je później, jeśli trwa.
	if not is_attacking:
		var arm_sw := swing * lerpf(0.7, 0.85, _run_blend)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x,  s * arm_sw, _sm(18.0, delta))
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -s * arm_sw, _sm(18.0, delta))
		# ŁOKCIE — lekkie zgięcie (rośnie z _gait) + „pompa", gdy WŁASNY bark napiera do przodu.
		# Bark L do przodu, gdy s>0 (_arm_l=+s); R, gdy s<0. Flex parujemy z dodatnim wkładem barku.
		var base_elbow := lerpf(0.18, lerpf(0.4, 0.55, _run_blend), _gait)
		var pump := lerpf(0.32, 0.5, _run_blend) * _gait
		var elbow_l := base_elbow + maxf(0.0,  s) * pump
		var elbow_r := base_elbow + maxf(0.0, -s) * pump
		_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, elbow_l, _sm(18.0, delta))
		_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, elbow_r, _sm(18.0, delta))

# --- IDLE: spokojny oddech + powolne przestępowanie (weight-shift) ----------
# Sylwetka STOI WYSOKO: kolana niemal proste (stały offset ~-0.02, dopasowany do startowej
# „podłogi" kolana w lokomocji, by przejście idle->chód nie klikało), bez stałego przysiadu.
# Tylko przejściowy weight-shift dokłada drobne ugięcie odciążonej nogi.
func _anim_idle(delta: float) -> void:
	_walk_phase = 0.0
	# Wolny oddech (klatka unosi się) + bardzo powolny weight-shift L/R — postać „żyje".
	var breath := sin(_idle_phase * 1.5) * 0.035       # oddech (rad) — subtelny
	var shift := sin(_idle_phase * 0.6)                # przenoszenie ciężaru (wolne)
	# Nogi prawie proste; noga „odciążona" minimalnie w przód — luźna, naturalna, WYPROSTOWANA postawa.
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x,  breath * 0.4 + maxf(0.0,  shift) * 0.025, _sm(5.0, delta))
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -breath * 0.4 + maxf(0.0, -shift) * 0.025, _sm(5.0, delta))
	# Stały offset kolana tylko -0.02 (prawie prosto) + drobne przejściowe ugięcie z weight-shiftu.
	_leg_l_lo.rotation.x = lerpf(_leg_l_lo.rotation.x, -maxf(0.0,  shift) * 0.08 - 0.02, _sm(5.0, delta))
	_leg_r_lo.rotation.x = lerpf(_leg_r_lo.rotation.x, -maxf(0.0, -shift) * 0.08 - 0.02, _sm(5.0, delta))
	# Ręce zwisają swobodnie z minimalnym kołysaniem oddechu + naturalnie lekko zgięte łokcie.
	if not is_attacking:
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x,  breath * 0.8, _sm(5.0, delta))
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -breath * 0.8, _sm(5.0, delta))
		_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, 0.16, _sm(5.0, delta))
		_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, 0.16, _sm(5.0, delta))

# --- SKOK / SPADANIE: pozy w powietrzu (NATURALNE, ważone fazą lotu) ---------
# WZBICIE: dynamiczny „tuck" (udo do przodu, pięta podkulona) najmocniejszy zaraz po odbiciu,
# rozluźniany ku APEKSOWI (apex = velocity.y≈0). SPADANIE: nogi „sięgają" w dół ku ziemi tym
# bardziej, im szybciej opadamy (gotowość do amortyzacji), kolana lekko ugięte. Konwencja stawów:
# udo do przodu = DODATNI hip, kolano (pięta do tyłu/góry) = UJEMNY, łokieć (zgięcie) = DODATNI.
# Wszystko wygładzane (_sm) — wejście/wyjście z lotu nie „strzela".
func _anim_air(delta: float, _hspeed: float) -> void:
	_walk_phase = 0.0
	var rising := velocity.y > 0.5
	if rising:
		# tuck 1 na odbiciu -> 0 przy apeksie (rozluźnienie nóg u szczytu skoku).
		var tuck := clampf(velocity.y / maxf(1.0, jump_velocity), 0.0, 1.0)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, lerpf(0.25, 0.65, tuck), _sm(12.0, delta))
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, lerpf(0.15, 0.40, tuck), _sm(12.0, delta))
		_leg_l_lo.rotation.x = lerpf(_leg_l_lo.rotation.x, lerpf(-0.45, -1.05, tuck), _sm(12.0, delta))
		_leg_r_lo.rotation.x = lerpf(_leg_r_lo.rotation.x, lerpf(-0.30, -0.65, tuck), _sm(12.0, delta))
		# Bramka po _attack_anim_t: is_attacking gaśnie klatkę później (unikamy twitcha ramion).
		if _attack_anim_t <= 0.0:
			# Ramiona lekko w górę-przód (zryw): bark DODATNI + zgięte łokcie (DODATNI).
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.5, _sm(10.0, delta))
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.5, _sm(10.0, delta))
			_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, 0.55, _sm(10.0, delta))
			_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, 0.55, _sm(10.0, delta))
	else:
		# SPADANIE: im szybciej w dół, tym bardziej nogi „sięgają" ku ziemi (reach), gotowe
		# amortyzować. reach 0 (apex) -> 1 (szybkie opadanie). Lekki rozkrok przód/tył + ugięte kolana.
		var reach := clampf(-velocity.y / 12.0, 0.0, 1.0)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, lerpf(-0.05, -0.20, reach), _sm(10.0, delta))
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, lerpf( 0.10,  0.28, reach), _sm(10.0, delta))
		_leg_l_lo.rotation.x = lerpf(_leg_l_lo.rotation.x, lerpf(-0.18, -0.40, reach), _sm(10.0, delta))
		_leg_r_lo.rotation.x = lerpf(_leg_r_lo.rotation.x, lerpf(-0.12, -0.26, reach), _sm(10.0, delta))
		if _attack_anim_t <= 0.0:
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.28, _sm(8.0, delta))
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.28, _sm(8.0, delta))
			_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, 0.42, _sm(8.0, delta))
			_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, 0.42, _sm(8.0, delta))

# --- ATAK: zamach prawą ręką (nadpisuje ramiona po lokomocji/idle) ----------
# FAZA 2: pelne pozy spiete z timeline Fazy 1 (ANTICIPATION/ACTIVE/RECOVERY) + ANTICIPATION/OVERSHOOT/
# FOLLOW-THROUGH (12 zasad anim):
#   ANTICIPATION: ramie COFA sie mocniej (wind-up, easeIn), lokiec mocno zgiety — "naladowanie",
#   ACTIVE: gwaltowny zamach z OVERSHOOT (konczyna PRZESKAKUJE cel i wraca), lokiec prostuje sie,
#   RECOVERY: FOLLOW-THROUGH — ramie OSIADA miekko z przeregulowania do neutralu (nie skokowo).
# Twist korpusu jest w _anim_additive (warstwa 5), by nie kolidowac z _animate_torso. Bron dociaga
# springiem (secondary motion) ~2 klatki po ramieniu = follow-through narzedzia. Brak timeline
# (finisher/fallback) -> stara parabola z _attack_anim_t (zachowanie sprzed Fazy 1).
func _anim_attack_arms(delta: float) -> void:
	if _atk_phase == AtkPhase.ANTICIPATION:
		var k := 1.0 - (_atk_phase_t / maxf(0.01, _atk_anticipation))   # 0->1 wind-up
		var ease := k * k                                              # przyspieszajacy wind-up (naladowanie)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, lerpf(0.0, 0.95, ease), _sm(28.0, delta))
		_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, lerpf(0.4, 1.25, ease), _sm(28.0, delta))
	elif _atk_phase == AtkPhase.ACTIVE:
		var k2 := 1.0 - (_atk_phase_t / maxf(0.01, _atk_active))        # 0->1
		# CIOS + OVERSHOOT: krzywa PRZESKAKUJE cel (-2.6) i osiada (-2.2).
		var swing := _overshoot(k2, -2.6, -2.2)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, swing, _sm(38.0, delta))
		_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, lerpf(0.5, 0.02, k2), _sm(38.0, delta))
	elif _atk_phase == AtkPhase.RECOVERY:
		var k3 := 1.0 - (_atk_phase_t / maxf(0.01, _atk_recovery))
		# FOLLOW-THROUGH: ramie osiada miekko z przeregulowania do neutralu.
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, lerpf(-1.0, -0.2, k3), _sm(14.0, delta))
		_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, lerpf(0.15, 0.45, k3), _sm(14.0, delta))
	else:
		# Brak timeline (finisher/fallback): stara parabola z _attack_anim_t (zachowanie sprzed Fazy 1).
		var t := 1.0 - (_attack_anim_t / attack_anim_time)   # 0..1 postęp animacji
		var swing2 := sin(t * PI)                            # 0->1->0 parabola
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -2.2 * swing2, _sm(28.0, delta))
		_arm_r_lo.rotation.x = lerpf(_arm_r_lo.rotation.x, 0.9 * (1.0 - swing2), _sm(28.0, delta))
	# Lewa ręka: kontra w tył dla balansu (lekkie zgięcie łokcia).
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.35, _sm(14.0, delta))
	_arm_l_lo.rotation.x = lerpf(_arm_l_lo.rotation.x, 0.4, _sm(14.0, delta))

# Krzywa OVERSHOOT: k 0..1. 0..0.6: szybki smoothstep do 'peak' (przeskok celu); 0.6..1: smoothstep
# z 'peak' do 'settle' (przeregulowanie = "miesistosc" ciosu). peak/settle docelowe katy (rad).
func _overshoot(k: float, peak: float, settle: float) -> float:
	if k < 0.6:
		var a := k / 0.6
		return lerpf(0.0, peak, a * a * (3.0 - 2.0 * a))
	var b := (k - 0.6) / 0.4
	return lerpf(peak, settle, b * b * (3.0 - 2.0 * b))

# --- TUŁÓW: body-bob (2× tempo kroku), lean wg prędkości, twist wg fazy ------
# ANTY-POP: amplitudy lean/twist/roll/bob czytają WYGŁADZONE wagi (_gait dławi rozruch z idle,
# _run_blend interpoluje pary chód/bieg), więc na progu biegu i na starcie ruchu nic nie strzela.
# _air_blend wycisza rytm kroku w locie i skaluje lean w powietrzu (bez twardego if on_floor).
func _animate_torso(delta: float, _hspeed: float, _on_floor: bool, _sprinting: bool) -> void:
	var ground := 1.0 - _air_blend                # 1 na ziemi, 0 w powietrzu (cross-fade)
	# 1) Pionowy bob: szczyt 2× na cykl kroku (ciało unosi się na każdym kroku). Amplituda przez wagi.
	var bob_amp := lerpf(0.045, 0.06, _run_blend) * _gait
	var target_bob := -absf(sin(_walk_phase)) * bob_amp * ground
	# Idle: minimalne unoszenie z oddechu (gdy lokomocja praktycznie wygaszona).
	target_bob += sin(_idle_phase * 1.6) * 0.012 * (1.0 - _gait) * ground
	# Lądowanie: przysiad (squash) zaniża tułów chwilowo.
	target_bob -= _land_squash * 0.10
	_anim_bob = lerpf(_anim_bob, target_bob, _sm(16.0, delta))
	_torso.position.y = float(_HIP_Y) * VS + _anim_bob

	# 2) Lean do przodu: chód<->bieg przez _run_blend, skala przez _gait. W powietrzu wytłumiony.
	var lean := lerpf(0.16, 0.28, _run_blend) * _gait
	lean *= lerpf(0.4, 1.0, ground)               # w locie ~0,4× (zamiast twardego if not on_floor)
	# 3) Twist (skręt barków wokół osi pionowej, przeciwnie do bioder) — naturalny rytm chodu.
	var twist := sin(_walk_phase) * lerpf(0.09, 0.14, _run_blend) * _gait * ground
	# 4) Boczny przechył (roll): w chodzie WAŻONY — ciało przenosi się nad nogę podporową
	#    (w fazie z bobem), w idle delikatny weight-shift.
	var roll := sin(_walk_phase) * lerpf(0.045, 0.07, _run_blend) * _gait * ground
	roll += sin(_idle_phase * 0.6) * 0.03 * (1.0 - _gait) * ground   # idle weight-shift
	# FAZA 1: dorzuc LEAN OD PRZYSPIESZENIA (waga ruchu) — wzdluzny do pitcha, boczny do rolla.
	# _lean_vel/_lean_turn policzone w _process (od realnego przyspieszenia, w bazie modelu).
	_torso.rotation.x = lerpf(_torso.rotation.x, lean + _lean_vel, _sm(10.0, delta))
	_torso.rotation.y = lerp_angle(_torso.rotation.y, twist, _sm(14.0, delta))
	_torso.rotation.z = lerpf(_torso.rotation.z, roll - _lean_turn, _sm(9.0, delta))

# --- GŁOWA: stabilizacja (kontra do leanu/twistu tułowia) + drobny nod ------
func _animate_head(delta: float, _hspeed: float) -> void:
	# Głowa częściowo KOMPENSUJE pochylenie tułowia (wzrok trzyma się horyzontu) —
	# to klasyczny „head stabilization": ujemny ułamek leanu/twistu tułowia.
	var counter_pitch := -_torso.rotation.x * 0.55
	var counter_twist := -_torso.rotation.y * 0.4
	# Nod kroku i oddech idle MIESZANE wagą _gait (bez twardego progu hspeed) — spójne z nogami/tułowiem.
	var ground := 1.0 - _air_blend
	counter_pitch += sin(_walk_phase * 2.0) * 0.02 * _gait * ground         # nod w rytm kroku
	counter_pitch += sin(_idle_phase * 1.6) * 0.025 * (1.0 - _gait) * ground # oddech w idle
	_head.rotation.x = lerpf(_head.rotation.x, counter_pitch, _sm(12.0, delta))
	_head.rotation.y = lerp_angle(_head.rotation.y, counter_twist, _sm(12.0, delta))

func _physics_process(delta: float) -> void:
	# ----------------------------------------------------------------------
	#  TIKI WALKI (odliczanie czasu) — na samym początku, przed grawitacją
	# ----------------------------------------------------------------------
	_attack_cd      = maxf(0.0, _attack_cd - delta)
	_dodge_cd       = maxf(0.0, _dodge_cd - delta)
	_iframes        = maxf(0.0, _iframes - delta)
	# ETAP 1 (krok 4): LOKALNY freeze-frame co-opu. Gdy aktywny (_local_freeze_t>0, ustawiany w
	# _hitstop/_on_perfect_dodge na drodze has_network()==true), ZAMRAŻAMY pozę zamachu: nie
	# dekrementujemy postępu animacji ataku (_attack_anim_t stoi), więc ramię zastyga na klatce
	# trafienia. Ruch poziomy gracza też wstrzymujemy niżej (velocity.x/z=0). W SP ta gałąź jest
	# nieaktywna (tam globalny Engine.time_scale daje bezczas — patrz _hitstop()).
	var _frozen := _local_freeze_t > 0.0
	if not _frozen:
		_attack_anim_t  = maxf(0.0, _attack_anim_t - delta)
		# FAZA 1: gdy timeline ataku NIEAKTYWNY, is_attacking gasnie wg _attack_anim_t (jak dotad).
		# Gdy timeline AKTYWNY, to ON trzyma is_attacking (gasnie w _end_attack_timeline).
		if _attack_anim_t <= 0.0 and _atk_phase == AtkPhase.NONE:
			is_attacking = false
	# FAZA 1: TIMELINE ataku (anticipation -> active -> recovery). Tyka po dekremencie anim, przed
	# grawitacja. Otwiera/zamyka okno hitboxa we wlasciwych fazach (NIE w klatce 0).
	_tick_attack_timeline(delta)
	if _combo_timer > 0.0:
		_combo_timer = maxf(0.0, _combo_timer - delta)
		if _combo_timer == 0.0:
			_combo_count = 0          # okno combo wygasło
			# FAZA 1: wygasle okno combo resetuje TEZ lancuch 3-ciosowy (gdy nie trwa timeline).
			if _atk_phase == AtkPhase.NONE:
				_chain_step = 0
			combo_changed.emit(_combo_count)   # HUD: schowaj "Combo xN"
	if _dodge_t > 0.0:
		_dodge_t = maxf(0.0, _dodge_t - delta)
		_dodge_active_t += delta          # ETAP 1: czas trwania uniku (do okna perfect-dodge)
		if _dodge_t == 0.0:
			is_dodging = false
			_dodge_recovery_t = dodge_recovery   # FAZA 1: wejdz w krotkie recovery (cancelable atakiem)
	# FAZA 1: recovery po dashu — cancelable atakiem (_try_attack zeruje je). Sam gasnie po czasie.
	if _dodge_recovery_t > 0.0:
		_dodge_recovery_t = maxf(0.0, _dodge_recovery_t - delta)
	# Obsługa KEY_Q jako alternatywy uniku (debounce) — tylko gdy kursor złapany.
	# ETAP 7 (review #minor): czytamy KEY_Q TYLKO gdy to NASZ input (SP lub klient-właściciel). Gdy HOST
	# symuluje CUDZĄ postać (should_read_local_input==false), klawiatura HOSTA nie może wywołać uniku
	# cudzej postaci — inaczej klient unika wg klawiszy hosta. W SP zawsze true (zero zmian odczucia).
	var read_local_input := _net_sync == null or _net_sync.should_read_local_input()
	var q_down := read_local_input and Input.is_physical_key_pressed(KEY_Q) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if q_down and not _q_was_down:
		_try_dodge()
	_q_was_down = q_down

	# ETAP 1: BUFOR inputu (ROADMAP 4 krok 3). Klik tuż przed końcem CD/ataku zostaje zapamiętany
	# i odpalany, gdy tylko okno się otworzy — koniec „połykania" inputu na styku akcji.
	if _local_freeze_t > 0.0:
		_local_freeze_t = maxf(0.0, _local_freeze_t - delta)
	if _dodge_buffered > 0.0:
		_dodge_buffered = maxf(0.0, _dodge_buffered - delta)
		if _dodge_buffered > 0.0 and _can_dodge():
			_dodge_buffered = 0.0
			_try_dodge()
	if _attack_buffered > 0.0:
		_attack_buffered = maxf(0.0, _attack_buffered - delta)
		# FAZA 1: buforowany atak odpala gdy okno wolne (CD) LUB gdy jestesmy w oknie cancel recovery
		# (cancel-into-next) — _try_attack sam wybierze sciezke (zwykly cios / kolejny krok lancucha).
		if _attack_buffered > 0.0 and (_can_attack() or _in_attack_cancel_window()):
			_attack_buffered = 0.0
			_try_attack()

	# 1) Grawitacja (mocniejsza przy opadaniu — mniej „księżycowy" skok)
	if not is_on_floor():
		var g := _gravity * (fall_gravity_mult if velocity.y < 0.0 else 1.0)
		velocity.y -= g * delta

	# Bramka UI (Etap 2 review #4): gdy modalne UI (ekwipunek) lapie input LUB gra jest spauzowana,
	# gracz NIE chodzi/skacze/sprintuje — inaczej klikajac itemy w ekwipunku odbiegasz od lootu/wrogow.
	var ui_locked := get_tree().paused or (GameState != null and GameState.ui_capturing_input)

	# ETAP 7: ŹRÓDŁO INPUTU. read_local==true w SP (has_network()==false) -> sciezka klawiatury jak
	# dotąd, IDENTYCZNIE. W co-opie HOST symulujący CUDZĄ postać czyta input przysłany RPC zamiast
	# klawiatury (autorytatywna symulacja); klient-właściciel i SP czytają klawiaturę (predykcja od ręki).
	var read_local := _net_sync == null or _net_sync.should_read_local_input()

	# 2) Skok z game feel (0C): coyote time + bufor wejścia + jump-cut.
	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote = maxf(0.0, _coyote - delta)
	var space_down := false
	if read_local:
		space_down = Input.is_physical_key_pressed(KEY_SPACE) and not is_dead and not ui_locked
	else:
		space_down = (_net_sync != null and _net_sync.remote_input_jump()) and not is_dead
	if space_down and not _space_was:
		_jump_buffer = jump_buffer_time
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if _jump_buffer > 0.0 and _coyote > 0.0:
		if is_on_floor():
			_jump_antic_t = 0.08          # przysiad anticipation tuz przed wybiciem (widoczny squash)
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
	# jump-cut: puszczenie spacji w fazie wznoszenia skraca skok (lepsza kontrola wysokości).
	if not space_down and velocity.y > 0.0:
		velocity.y = minf(velocity.y, jump_velocity * 0.35)
	_space_was = space_down

	# 3) Kierunek z klawiszy WASD (lokalny: x = bok, y = przód/tył). read_local policzone wyżej.
	var input_dir := Vector2.ZERO
	if read_local:
		if not is_dead and not ui_locked:
			if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1.0
			if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1.0
			if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1.0
			if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1.0
	else:
		# HOST nad cudzą postacią: kierunek z przysłanego inputu klienta (autorytatywna symulacja).
		if not is_dead:
			input_dir = _net_sync.remote_input_dir()
	input_dir = input_dir.normalized()

	# (Auto-step przeniesiony niżej — wymaga policzonego `direction`/`current_speed`, a do tego
	#  jest BRAMKOWANY test_move, żeby wchodzić tylko na niskie progi, nie na strome ściany.)

	# 4) Obróć kierunek o yaw kamery — "przód" zawsze tam, gdzie patrzysz.
	var yaw := _pivot.rotation.y
	var direction := Vector3(input_dir.x, 0.0, input_dir.y).rotated(Vector3.UP, yaw)

	# 5) Prędkość pozioma (bieg z shiftem; bramkowanie staminą) + knockback (gaśnie)
	var moving := input_dir != Vector2.ZERO
	# Bieg: lokalnie z SHIFT; host nad cudzą postacią z flagi inputu klienta. W SP = stara ścieżka.
	var sprint_held := Input.is_physical_key_pressed(KEY_SHIFT) if read_local else (_net_sync != null and _net_sync.remote_input_run())
	var can_sprint := sprint_held and stamina > 0.0 and not ui_locked
	var current_speed := sprint_speed if can_sprint else speed
	# FAZA 1: MOVEMENT WEIGHT ("ciezki ale szybki"). Rozdzielamy ROZPED (ground_accel) od WYHAMOWANIA
	# (ground_decel, slabsze -> poslizg) i dodajemy TURN_ACCEL (wektor ruchu obraca sie ku nowemu
	# kierunkowi stopniowo ~0.08 s, nie natychmiast — ciezar zwrotu). W powietrzu zostaje air_accel
	# (slabsza kontrola jak dotad). NIE rusza auto-stepu/floor-snap/skoku — tylko krzywa _move_vel.
	var target := Vector3(direction.x, 0.0, direction.z) * current_speed
	var cur := Vector3(_move_vel.x, 0.0, _move_vel.z)
	if not is_on_floor():
		# Powietrze: stara, prosta krzywa (slaba kontrola) — nie psujemy odczucia skoku/lotu.
		cur = cur.move_toward(target, air_accel * delta)
	elif not moving:
		# Brak inputu: WYHAMOWANIE z poslizgiem (ground_decel < ground_accel -> dluzszy wybieg).
		cur = cur.move_toward(Vector3.ZERO, ground_decel * delta)
	else:
		# Jest input: rozdziel skladowa WZDLUZ biezacego ruchu (rozped/hamowanie) od PROSTOPADLEJ
		# (zwrot kierunku, sterowany turn_accel — ciezar zmiany kierunku). To daje "szybki start,
		# ale ciezki zwrot": pelny gaz do przodu jest natychmiastowy, ostry skret kosztuje moment.
		var speed_now := cur.length()
		if speed_now < 0.01:
			cur = cur.move_toward(target, ground_accel * delta)   # rusza z miejsca: pelny rozped
		else:
			var fwd := cur / speed_now
			var along := fwd.dot(target)                          # rzut celu na biezacy kierunek (m/s)
			var target_perp := target - fwd * along               # skladowa celu PROSTOPADLA (zwrot)
			# Wzdluz: rozped gdy przyspieszamy (along >= biezaca predkosc), decel gdy zwalniamy/zawracamy.
			var along_rate := ground_accel if along >= speed_now else ground_decel
			var along_target := fwd * clampf(along, -current_speed, current_speed)
			cur = cur.move_toward(along_target, along_rate * delta)   # skladowa "wzdluz" (rozped/hamuj)
			cur += target_perp.limit_length(turn_accel * delta)      # skladowa "w bok" (zwrot z waga)
			cur = cur.limit_length(current_speed)                    # nigdy ponad docelowa predkosc
	# FAZA 1: DODGE RECOVERY — krotkie wyhamowanie po dashu (waga "ladowania" z uniku). Cancelable
	# atakiem (_dodge_recovery_t zerowane w _try_attack). Ruch tlumiony proporcjonalnie do reszty okna.
	if _dodge_recovery_t > 0.0 and _dodge_t <= 0.0 and is_on_floor():
		var damp := clampf(_dodge_recovery_t / maxf(0.01, dodge_recovery), 0.0, 1.0)
		cur *= (1.0 - 0.6 * damp)
	_move_vel.x = cur.x
	_move_vel.z = cur.z
	velocity.x = _move_vel.x + _knockback.x
	velocity.z = _move_vel.z + _knockback.z
	# ETAP 1 (krok 4): podczas LOKALNEGO freeze-frame (co-op) wstrzymujemy WŁASNĄ lokomocję, żeby
	# bezczas był odczuwalny u nas, nie zamrażając całego świata globalnym time_scale. Grawitacja i
	# knockback (niżej) działają dalej; dash (perfect-dodge) celowo dozwolony jako nagroda ruchowa.
	if _frozen and _dodge_t <= 0.0:
		_move_vel.x = 0.0
		_move_vel.z = 0.0
		velocity.x = _knockback.x
		velocity.z = _knockback.z

	# (AUTO-STEP wykonujemy PO move_and_slide — _try_step_up() algorytmem góra->przód->dół.
	#  Niezawodne wchodzenie na schodki voxela 0,5 m bez skakania, BEZ wspinania po ścianach.)

	# Sprint pobiera staminę tylko gdy faktycznie biegniemy i się ruszamy:
	if can_sprint and moving and stamina > 0.0:
		stamina = maxf(0.0, stamina - sprint_stamina_cost * delta)
		_stamina_idle = 0.0
		stamina_changed.emit(stamina, max_stamina)

	# 5b) UNIK (dash): nadpisuje poziomą prędkość zrywem (po zwykłej prędkości, przed move_and_slide).
	# Respektuje grawitację (nie zerujemy velocity.y) — można unikać w powietrzu, ale nie "latać".
	if _dodge_t > 0.0:
		velocity.x = _dodge_dir.x * dodge_speed
		velocity.z = _dodge_dir.z * dodge_speed
		_move_vel.x = velocity.x   # po dashu kontynuuj płynnie (bez „szarpnięcia")
		_move_vel.z = velocity.z

	# 5c) Knockback w pionie: jednorazowy impuls w górę przy trafieniu (dodawany do velocity.y).
	if _knockback.y > 0.0:
		velocity.y += _knockback.y
		_knockback.y = 0.0
	# Wygaszanie knockbacku w poziomie.
	_knockback.x = move_toward(_knockback.x, 0.0, 18.0 * delta)
	_knockback.z = move_toward(_knockback.z, 0.0, 18.0 * delta)

	# Gdy martwy — wygaszamy ruch poziomy (grawitacja zostaje, by nie wisiał w powietrzu).
	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)

	# ETAP 7: czy w ogóle SYMULUJEMY ruch (move_and_slide). True w SP i dla postaci, nad którą mamy
	# kontrolę (host: wszyscy; klient: tylko własna postać — predykcja). False TYLKO dla CUDZEJ postaci
	# u klienta — tam pozycję narzuca interpolacja w net_post_physics() (poniżej). W SP zawsze true.
	var simulate := _net_sync == null or _net_sync.should_simulate_movement()

	# 6) Wykonaj ruch z uwzględnieniem kolizji
	var pre_vy := velocity.y
	if simulate:
		move_and_slide()

		# 6a) AUTO-STEP po ruchu: jeśli zablokował nas NISKI próg (schodek voxela), wnieś postać
		# na niego płynnie (góra->przód->dół). Wysokie ściany/strome zbocza => brak (postać staje).
		if moving and is_on_floor() and not is_dead and _dodge_t <= 0.0:
			_try_step_up(direction, current_speed, delta)

		# Lądowanie (0C + JUICE / FEEL 7): trzask kamery + przysiad (squash) + pył, skalowane upadkiem.
		if is_on_floor() and not _was_on_floor and pre_vy < -3.0:
			var fall := -pre_vy
			# FEEL 7: mocniejszy trzask kamery przy lądowaniu (waga ruchu) — wyzszy sufit trauma.
			add_trauma(clampf(fall / 24.0, 0.05, 0.45))
			# Squash: glebszy przysiad ciala (anim _animate_torso zaniża tułów wg _land_squash).
			_land_squash = clampf(fall / 13.0, 0.2, 1.2)
			# FEEL 7: pyl juz przy lzejszym ladowaniu (prog 3.5 zamiast 5) + mocniejszy puff przy upadku.
			if fall > 3.5:
				_spawn_land_dust(clampf(fall / 14.0, 0.0, 1.2))
			_play_sfx(&"land")   # FEEL 7: SFX ladowania (no-op bez pliku)
		_was_on_floor = is_on_floor()

		# FEEL 7: SPRINT JUICE — przy biegu po ziemi pyl spod stop (kadencja kroku) + (FOV/bob juz sa).
		# Tani: re-use one-shot _land_dust co krok (przy fazie chodu mijajacej dolny punkt). Waga ruchu.
		if simulate and is_on_floor() and not is_dead and _dodge_t <= 0.0:
			var hvel := Vector3(velocity.x, 0.0, velocity.z)
			var hsp := hvel.length()
			if hsp > speed + 0.6:                  # tylko BIEG (nie zwykly chod)
				_sprint_dust_t -= delta
				if _sprint_dust_t <= 0.0:
					_sprint_dust_t = SPRINT_DUST_INTERVAL
					_spawn_sprint_dust()
				# FAZA 4 (6): PYL POSLIZGU przy OSTRYM ZWROCIE — gdy kierunek ruchu gwaltownie sie zmienil
				# (dot < 0.3 wzgledem poprzedniej klatki), buchnij mocniejszym obloczkiem (debounce).
				_turn_dust_t = maxf(0.0, _turn_dust_t - delta)
				var cur_dir := hvel / hsp
				if _prev_move_dir.length_squared() > 0.01 and _turn_dust_t <= 0.0:
					if cur_dir.dot(_prev_move_dir) < 0.3:
						_turn_dust_t = TURN_DUST_DEBOUNCE
						_spawn_turn_dust(cur_dir)
				_prev_move_dir = cur_dir
			else:
				_sprint_dust_t = 0.0
				_prev_move_dir = Vector3.ZERO

	# ETAP 7: PREDYKCJA/REKONSYLIACJA + INTERPOLACJA. No-op w SP (net_post_physics -> return gdy brak
	# sieci). Klient-właściciel: buforuje input + wysyła do hosta; host: rozsyła snapshoty; cudza postać
	# u klienta: ustawia pozycję z interpolacji snapshotów. Wołane PO ruchu (predykcja już się wydarzyła).
	# Wysylamy SUROWA intencje biegu `sprint_held` (review #minor), NIE `can_sprint` (juz zbramkowane
	# lokalna stamina) — host bramkuje bieg WLASNA kopia staminy na tej samej intencji => zgodna predykcja.
	if _net_sync != null:
		_net_sync.net_post_physics(delta, input_dir, sprint_held, space_down)

## Gładkie wchodzenie na NISKIE progi (schodki voxela ~0,5 m) bez skakania — algorytm
## góra->przód->dół. Jeśli w przód blokuje, a po podniesieniu o step_height przód jest WOLNY
## i pod spodem jest grunt, podnosimy postać na próg. Wyższa ściana/strome zbocze => nic
## (postać się zatrzymuje — koniec „wspinania się tam, gdzie nie powinna" i „ciągłego skakania").
func _try_step_up(dir: Vector3, spd: float, delta: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		return
	var horiz := flat.normalized() * maxf(spd * delta + 0.06, 0.12)   # jak daleko w przód testujemy
	# 1) Czy w przód na OBECNEJ wysokości coś blokuje? Jeśli nie — nie ma progu, koniec.
	if not test_move(global_transform, horiz):
		return
	# 2) Podniesiony o step_height: czy w przód WOLNO? Jeśli nie => ściana, NIE wchodzimy.
	var up_t := global_transform
	up_t.origin += Vector3.UP * step_height
	if test_move(up_t, horiz):
		return
	# 3) Z przodu-na-górze rzut w DÓŁ — znajdź wierzch progu (musi być grunt, nie przepaść).
	var fwd_t := up_t
	fwd_t.origin += horiz
	var down := KinematicCollision3D.new()
	if not test_move(fwd_t, Vector3.DOWN * (step_height + 0.05), down):
		return   # brak gruntu pod progiem => krawędź/dziura, nie wnosimy w powietrze
	var rise := step_height - down.get_travel().length()
	if rise > 0.02:
		global_position.y += rise          # wejdź na próg (move_and_slide w nast. klatce niesie w przód)
		if velocity.y < 0.0:
			velocity.y = 0.0               # nie „spadaj" w tej klatce po wejściu

# ============================================================================
#  WALKA — ATAK
# ============================================================================

# Czy można TERAZ zaatakować. FAZA 1: blokujemy w trakcie ANTICIPATION/ACTIVE (cios w toku) — nowy
# cios serii idzie WYLACZNIE przez cancel-into-next w RECOVERY (_try_attack obsluguje to osobno).
# Dozwolone z dodge-RECOVERY (cancel atakiem) i z attack-RECOVERY poza oknem cancel (CD juz zszedl).
func _can_attack() -> bool:
	if is_dead or is_dodging:
		return false
	if _atk_phase == AtkPhase.ANTICIPATION or _atk_phase == AtkPhase.ACTIVE:
		return false
	return _attack_cd <= 0.0

# Czy można TERAZ wykonać unik (CD, nie martwy, nie w uniku, jest stamina). FAZA 1: unik ANULUJE
# zarowno atak (kazda faza timeline) jak i wlasne recovery — ucieczka ma priorytet (cancel-into-dodge).
func _can_dodge() -> bool:
	return not is_dead and _dodge_cd <= 0.0 and not is_dodging and stamina >= dodge_stamina_cost

# ETAP 3: finisher zasobu klasy (Wojownik: Wir Ostrzy). AbilityComponent sprawdza koszt (Furia) i CD;
# gdy brak Furii -> nie odpali. perform_skill (_perform_skill) otwiera szerokie okno hitboxa (AoE).
func _try_finisher() -> void:
	if is_dead or _ability == null or _skill_finisher == null:
		return
	# ETAP 8: SFX skilla zasobu klasy (R). AbilityComponent i tak waliduje koszt/CD — dźwięk gramy
	# optymistycznie przy próbie (vertical slice; precyzyjne "tylko gdy odpalił" to przyszły hook).
	_play_sfx(&"ability")
	_ability.try_use(_skill_finisher)

func _try_attack() -> void:
	if is_dead:
		return
	# FAZA 1: CANCEL-INTO-NEXT. Jesli trwa RECOVERY i jestesmy w OKNIE CANCEL (wczesna czesc recovery) ->
	# NIE odpalaj nowego ciosu od razu, tylko ZAKOLEJKUJ kolejny krok lancucha (plynny combo flow).
	# Okno cancel = pierwsze `_atk_cancel_window` s recovery: elapsed = _atk_recovery - _atk_phase_t.
	if _in_attack_cancel_window():
		_chain_queued = true
		return
	if not _can_attack():
		# ETAP 1: nie teraz -> buforuj (odpali się, gdy CD zejdzie / unik / recovery się skończy).
		if not is_dodging:                 # w trakcie uniku nie kolejkujemy ataku (unik = ucieczka)
			_attack_buffered = attack_buffer_time
		return
	# FAZA 1: cancel-into-attack z dodge-recovery (agresja po uniku = nagroda).
	_dodge_recovery_t = 0.0
	_attack_cd = attack_cooldown
	_attack_anim_t = attack_anim_time   # start animacji zamachu
	is_attacking = true

	# FAZA 1: krok lancucha (1..3). Reset gdy poprzednie okno wygaslo (_chain_step==0).
	_chain_step = mini(_chain_step + 1, ATTACK_CHAIN_MAX)

	# ETAP 8: SFX zamachu (whoosh). Lekka wariacja pitchu z combo -> seria ciosow nie brzmi identycznie.
	# No-op bez AudioManager/pliku (placeholder). Trafienie/krytyk gra osobno (DamageService.hit_resolved).
	_play_sfx(&"attack", 1.0 + 0.04 * float(_combo_count))

	# WARIANT A (rekomendacja): pierwszy cios serii już z 15% przebicia.
	# Inkrement combo PRZED oknem trafień (pudło zresetuje go do 0 w _on_hitbox_window_ended).
	_combo_count += 1
	combo_changed.emit(_combo_count)      # HUD: pokaż "Combo xN" (reset przy pudle po oknie)

	# FAZA 1: SOFT TARGET ASSIST — przed ciosem lekki AUTO-OBROT modelu/yaw ku celowi (lock lub
	# soft-target w stozku przodu), by koniec "machania w powietrze". Aktualizuje yaw pivota? NIE —
	# kamera zostaje gracza; obracamy tylko model i kierunek FILTRA luku ataku.
	# Cios idzie TAM, GDZIE PATRZY KAMERA, chyba ze assist wskaze cel — wtedy lekko docelujemy.
	var fyaw := _pivot.rotation.y
	var forward := Vector3(-sin(fyaw), 0.0, -cos(fyaw)).normalized()
	var aim := _attack_aim_dir(forward)   # FAZA 1: forward z soft-targetem (pull do celu w zasiegu)
	_model.rotation.y = atan2(-aim.x, -aim.z)

	# ETAP 1 (DoD): atak idzie ścieżką AbilityComponent -> HitboxComponent -> DamageService ->
	# Hurtbox/HealthComponent wroga. _perform_skill() STARTUJE timeline; _tick_attack_timeline otwiera
	# hitbox w fazie ACTIVE z kierunkiem `aim`. Fallback (brak komponentów) = dawna ręczna pętla.
	_atk_forward = aim
	if _ability != null:
		_ability.try_use(_skill_attack)
	else:
		# Brak AbilityComponent: i tak prowadzimy timeline lokalnie (hitbox/sweep w ACTIVE).
		_begin_attack_timeline(_skill_attack)

# perform_skill z AbilityComponent: faktyczne wykonanie skilla deleguje encja (TDD 1.2).
# Atak -> STARTUJ TIMELINE (anticipation->active->recovery); dash -> uruchom zryw uniku.
# FAZA 1: atak NIE otwiera juz hitboxa w klatce 0 — _perform_skill tylko ROZPOCZYNA faze ANTICIPATION,
# a _tick_attack_timeline (w _physics_process) otwiera hitbox dopiero po wind-upie i zamyka po active.
func _perform_skill(skill: SkillResource, _target: Node) -> void:
	if skill == _skill_attack:
		_is_heavy_attack = false             # FEEL (2): zwykly cios = lekki tier hitstopu
		_begin_attack_timeline(_skill_attack)
	elif skill == _skill_dash:
		_begin_dash()
	elif skill == _skill_finisher:
		# ETAP 3: Wir Ostrzy — AoE 360°. Otwieramy okno hitboxa BEZ filtra łuku (dot=-1 -> wszystko
		# wokół) i z lekkim juicem. Damage idzie tą samą ścieżką DamageService (HitData z _build_hit).
		_is_heavy_attack = true              # FEEL (2): AoE/finisher = ciezki tier hitstopu
		_attack_anim_t = attack_anim_time
		is_attacking = true
		if _hitbox != null:
			var fyaw := _pivot.rotation.y
			var forward := Vector3(-sin(fyaw), 0.0, -cos(fyaw)).normalized()
			_atk_forward = forward          # FAZA 4: smuga/aura zorientowane wzdluz ciosu
			_hitbox.global_position = global_position + Vector3(0.0, 0.9, 0.0)
			_hitbox.open_window(0.14, forward)
		add_trauma(0.18)
		# FAZA 4 (1)+(3): Wir Ostrzy — szeroka smuga 360° (big) + aura-pierscien wg SkillResource.
		_spawn_slash_trail(true)
		_spawn_ability_aura(_skill_finisher)

# ============================================================================
#  FAZA 1 — ATTACK TIMELINE (ANTICIPATION -> ACTIVE -> RECOVERY) + COMBO CHAIN
# ============================================================================
# Rozpoczyna timeline ciosu od fazy ANTICIPATION (hitbox JESZCZE zamkniety). Wartosci faz biora sie
# ze SkillResource (z eksportowymi fallbackami). _tick_attack_timeline (w _physics_process) przejdzie
# ANTICIPATION -> ACTIVE (otwiera hitbox/sweep) -> RECOVERY (cancelable). Wolane z _perform_skill.
func _begin_attack_timeline(skill: SkillResource) -> void:
	_atk_anticipation = skill.anticipation if skill.anticipation > 0.0 else attack_anticipation
	_atk_active = skill.active if skill.active > 0.0 else attack_active
	_atk_recovery = skill.recovery if skill.recovery > 0.0 else attack_recovery
	_atk_cancel_window = skill.cancel_window if skill.cancel_window > 0.0 else attack_cancel_window
	_atk_index = _chain_step                       # ktory cios serii (1..3) — do juice 3. ciosu
	_atk_phase = AtkPhase.ANTICIPATION
	_atk_phase_t = _atk_anticipation
	is_attacking = true
	# Hitbox JESZCZE zamkniety w klatce 0 (klucz "impactu"). Otworzy go _enter_attack_active.

# Tyka maszyne faz ataku (wolane z _physics_process gdy _atk_phase != NONE). Frame-rate independent.
# ANTICIPATION: hitbox zamkniety, model dipuje rece (anim). Po jej zejsciu -> ACTIVE (otwarcie okna).
# ACTIVE: okno hitboxa otwarte (DamageService liczy). Po zejsciu -> RECOVERY (zamkniecie okna).
# RECOVERY: cancelable (unik zawsze, nastepny cios w cancel_window). Po zejsciu -> koniec/lancuch.
func _tick_attack_timeline(delta: float) -> void:
	if _atk_phase == AtkPhase.NONE:
		return
	# Podczas LOKALNEGO freeze-frame (co-op hitstop) zamrazamy timeline — poza zamachu zastyga.
	if _local_freeze_t > 0.0:
		return
	_atk_phase_t -= delta
	if _atk_phase_t > 0.0:
		return
	# Faza dobiegla konca -> przejscie do nastepnej (z przeniesieniem nadmiaru czasu, anti-drift).
	var overflow := -_atk_phase_t                    # ile czasu "przeszlo" ponad koniec fazy (>=0)
	match _atk_phase:
		AtkPhase.ANTICIPATION:
			_enter_attack_active()
			_atk_phase_t = maxf(0.0, _atk_phase_t - overflow)   # ACTIVE skrocone o nadmiar (anti-drift)
		AtkPhase.ACTIVE:
			_enter_attack_recovery()
			_atk_phase_t = maxf(0.0, _atk_phase_t - overflow)   # RECOVERY skrocone o nadmiar
		AtkPhase.RECOVERY:
			_end_attack_timeline()

# Wejscie w ACTIVE: OTWORZ okno hitboxa (lub sweep w fallbacku) w kierunku _atk_forward. To JEDYNE
# miejsce, gdzie hitbox sie otwiera — nigdy w klatce 0 (anticipation gwarantuje wind-up przed ciosem).
func _enter_attack_active() -> void:
	_atk_phase = AtkPhase.ACTIVE
	_atk_phase_t = _atk_active
	if _hitbox != null:
		_hitbox.global_position = global_position + Vector3(0.0, 0.9, 0.0)
		_hitbox.open_window(_atk_active, _atk_forward)   # hity przez DamageService
	else:
		_melee_sweep(_atk_forward)                       # fallback recznej petli
	# FAZA 4 (1): SLASH-TRAIL — smuga broni DOPIERO w ACTIVE (nie w ANTICIPATION). 3. cios serii =
	# szerszy luk (big). Spina sie z overshoot/follow-through z Fazy 2 (gasnie z koncem zamachu).
	_spawn_slash_trail(_is_chain_finisher())

func _enter_attack_recovery() -> void:
	_atk_phase = AtkPhase.RECOVERY
	_atk_phase_t = _atk_recovery
	# Zamkniecie okna na wszelki wypadek (hitbox sam zamyka po duration, ale gdy active skrocone).
	if _hitbox != null:
		_hitbox.close_window()

# Koniec recovery: jesli zakolejkowano cancel-into-next i jest jeszcze krok lancucha -> odpal kolejny
# cios PLYNNIE (combo flow). Inaczej zakoncz serie (reset lancucha) — albo zostaw okno na buforowany.
func _end_attack_timeline() -> void:
	_atk_phase = AtkPhase.NONE
	_atk_phase_t = 0.0
	if _chain_queued and _chain_step < ATTACK_CHAIN_MAX:
		_chain_queued = false
		_attack_cd = 0.0                  # cancel zwalnia CD dla nastepnego ciosu serii
		if _ability != null:
			_ability.reset_cooldown(_skill_attack.id)   # AbilityComponent: nie czekaj na pelny CD
		_try_attack()                     # nastepny krok lancucha (3. cios = mocniejszy juice)
		return
	# Brak kontynuacji: seria sie konczy. _chain_step wyzeruje sie z _combo_timer (okno combo) niżej,
	# albo natychmiast gdy doszlismy do 3. ciosu (lancuch zamkniety).
	_chain_queued = false
	if _chain_step >= ATTACK_CHAIN_MAX:
		_chain_step = 0                   # 3. cios zakonczyl lancuch -> nastepny LMB zaczyna od 1
	is_attacking = false

# FAZA 1: czy 3. (ostatni) cios lancucha — mocniejszy juice (wiekszy hitstop/shake/knockback).
func _is_chain_finisher() -> bool:
	return _atk_index >= ATTACK_CHAIN_MAX

# FAZA 1: czy jestesmy w OKNIE CANCEL (wczesna czesc RECOVERY) i jest jeszcze krok lancucha.
# Okno = pierwsze `_atk_cancel_window` s recovery (elapsed = _atk_recovery - _atk_phase_t).
func _in_attack_cancel_window() -> bool:
	if _atk_phase != AtkPhase.RECOVERY or _chain_step >= ATTACK_CHAIN_MAX:
		return false
	var elapsed := _atk_recovery - _atk_phase_t
	return elapsed <= _atk_cancel_window

# ============================================================================
#  FAZA 1 — LOCK-ON + SOFT TARGET ASSIST
# ============================================================================
# Toggle locka: brak locka -> namierz najblizszego wroga w zasiegu; jest lock -> zdejmij.
func _toggle_lock_on() -> void:
	if _lock_target != null and is_instance_valid(_lock_target):
		_set_lock_target(null)
	else:
		_set_lock_target(_nearest_enemy(lockon_range))

func _set_lock_target(t: Node3D) -> void:
	_lock_target = t
	lockon_changed.emit(t)
	if t == null and _lock_indicator != null:
		_lock_indicator.visible = false

# Najblizszy zywy wrog w promieniu (XZ) — grupa "enemies". Pomija martwych (is_dead). Null gdy brak.
func _nearest_enemy(max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist * max_dist
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue
		var to: Vector3 = (e as Node3D).global_position - global_position
		to.y = 0.0
		var d := to.length_squared()
		if d < best_d:
			best_d = d
			best = e as Node3D
	return best

# Kierunek ciosu z SOFT TARGET ASSIST. Zaczynamy od `forward` (yaw kamery). Jesli mamy lock w zasiegu
# LUB soft-target w stozku przodu — lekko "ciagniemy" kierunek do celu (pull), by cios nie szedl w
# powietrze. Pull tylko w zasiegu melee_pull_range (dalej: zwykly forward, gracz musi podejsc).
func _attack_aim_dir(forward: Vector3) -> Vector3:
	var tgt := _soft_target(forward)
	if tgt == null:
		return forward
	var to: Vector3 = tgt.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.05 or dist > melee_pull_range:
		return forward
	# Pull: interpoluj forward -> kierunek do celu. Lock = mocniejszy pull (0.85), soft = lekki (0.6).
	var pull := 0.85 if tgt == _lock_target else 0.6
	var to_n := to / dist
	var aim := forward.lerp(to_n, pull)
	if aim.length() < 0.001:
		return forward
	return aim.normalized()

# Cel softu: priorytet LOCK (jesli w zasiegu locka), inaczej najblizszy wrog w stozku przodu (assist).
func _soft_target(forward: Vector3) -> Node3D:
	if _lock_target != null and is_instance_valid(_lock_target):
		if (not _lock_target.has_method("is_dead")) or (not _lock_target.is_dead()):
			var to_lock: Vector3 = _lock_target.global_position - global_position
			to_lock.y = 0.0
			if to_lock.length() <= lockon_range:
				return _lock_target
	# Bez locka: najblizszy wrog w stozku przodu (dot >= lockon_assist_angle) i zasiegu melee_pull.
	var best: Node3D = null
	var best_d := melee_pull_range * melee_pull_range
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue
		var to: Vector3 = (e as Node3D).global_position - global_position
		to.y = 0.0
		var d := to.length_squared()
		if d < 0.0025 or d > best_d:
			continue
		if forward.dot(to.normalized()) < lockon_assist_angle:
			continue
		best_d = d
		best = e as Node3D
	return best

# Utrzymanie locka co klatke: zdejmij gdy cel zginal/zniknal/wyszedl z zasiegu; pozycjonuj wskaznik.
# Wolane z _process (wizual). Strafe wzgledem locka realizuje _process (obrot modelu ku celowi).
func _update_lock_on(_delta: float) -> void:
	if _lock_target != null:
		var drop := not is_instance_valid(_lock_target)
		if not drop and _lock_target.has_method("is_dead") and _lock_target.is_dead():
			drop = true
		if not drop:
			var to: Vector3 = _lock_target.global_position - global_position
			to.y = 0.0
			if to.length() > lockon_range * 1.15:    # histereza: nie migaj na granicy
				drop = true
		if drop:
			_set_lock_target(null)
	# Wskaznik nad celem (prosty pierscien/strzalka). Lazy-tworzony, re-uzywany.
	_update_lock_indicator()

func _update_lock_indicator() -> void:
	if _lock_target == null or not is_instance_valid(_lock_target):
		if _lock_indicator != null:
			_lock_indicator.visible = false
		return
	if _lock_indicator == null:
		_lock_indicator = _make_lock_indicator()
		var root := get_tree().root if get_tree() != null else null
		if root != null:
			root.add_child(_lock_indicator)
		else:
			add_child(_lock_indicator)
	_lock_indicator.visible = true
	_lock_indicator.global_position = _lock_target.global_position + Vector3(0.0, 2.0, 0.0)

# Prosty wskaznik locka: maly billboardowy znacznik (proceduralna tekstura — bez assetow z dysku).
func _make_lock_indicator() -> Sprite3D:
	var s := Sprite3D.new()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.pixel_size = 0.01
	s.modulate = Color(1.0, 0.85, 0.2)
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Romb-celownik (diament) — czytelny i tani (16x16 proceduralnie).
	for y in 16:
		for x in 16:
			if absi(x - 8) + absi(y - 8) == 6:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	s.texture = ImageTexture.create_from_image(img)
	s.visible = false
	return s

## FAZA 1 — PUBLICZNE API locka (HUD/test/Main). Zwraca aktualny cel locka (null = brak).
func lock_target() -> Node3D:
	return _lock_target if (_lock_target != null and is_instance_valid(_lock_target)) else null

# Hitbox trafił cel: juice (combo-okno + hitstop + trauma) raz na klatkę trafienia. HP już zadane
# przez DamageService z poziomu hitboxa — tu tylko odczucie walki.
func _on_hitbox_hit_landed(_target: Node) -> void:
	_combo_timer = combo_window
	# FAZA 1: 3. cios lancucha traktujemy jak "ciezki" do tieru hitstopu (mocniejszy bezczas/shake).
	var heavy := _is_heavy_attack or _is_chain_finisher()
	# FEEL (2): hitstop TIEROWANY — krytyk (0.14) > ciezki/3.cios/AoE (0.10) > zwykly (0.04). Mocniej na
	# TRAFIENIU, nigdy na zamachu. _last_hit_crit przychodzi z DamageService tuz przed tym callbackiem.
	if not _hitstop_active:
		_hitstop(FeelFX.hitstop_for(_last_hit_crit, heavy))
	# Trauma kamery proporcjonalna do wagi. FAZA 4 (5): KRYTYK = najmocniejszy wstrzas (0.26) — czesc
	# wyrazistego "POW" (obok screen-flasha/crit-burst); ciezki/3.cios = 0.20; zwykly = 0.12.
	add_trauma(0.26 if _last_hit_crit else (0.20 if heavy else 0.12))
	# ETAP 3: zadany cios wrecz buduje zasob klasy (Furia +6 / Combo +1 — GDD 4.2/4.3, ROADMAP 6).
	if _class_res != null:
		_class_res.on_hit_dealt(true)

# FEEL (2): zapamietuje wynik krytyka NASZEGO ostatniego ciosu (z centralnego DamageService).
# Filtrujemy po source==self — interesuje nas tylko cios zadany przez gracza (nie obrazenia wziete).
# Czysto lokalne: steruje tylko dlugoscia hitstopu/trauma, ZERO wplywu na HP (host-authoritative).
func _on_damage_resolved(source: Node, _target: Node, _final_damage: float, was_crit: bool) -> void:
	if source == self:
		_last_hit_crit = was_crit

# Okno hitboxa zamknięte: gdy 0 trafień -> pudło = reset combo (kasuje inkrement z _try_attack).
func _on_hitbox_window_ended(hit_count: int) -> void:
	if hit_count <= 0:
		_combo_count = 0
		_combo_timer = 0.0
		combo_changed.emit(_combo_count)

# Fallback ręcznej pętli (gdy komponenty nie powstały) — dawna logika _try_attack jako jedno źródło.
func _melee_sweep(forward: Vector3) -> void:
	var origin := global_position
	var hit_any := false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not (enemy is Node3D):
			continue
		var to_enemy: Vector3 = (enemy as Node3D).global_position - origin
		to_enemy.y = 0.0
		var dist := to_enemy.length()
		if dist > attack_range or dist < 0.05:
			continue
		if forward.dot(to_enemy / dist) < attack_arc_dot:
			continue
		_deal_damage_to(enemy)
		hit_any = true
	if hit_any:
		_combo_timer = combo_window
		# FEEL (2)+FAZA 1: tiered hitstop tez w fallbacku (krytyk z _last_hit_crit, 3.cios = ciezki).
		var heavy := _is_heavy_attack or _is_chain_finisher()
		_hitstop(FeelFX.hitstop_for(_last_hit_crit, heavy))
		add_trauma(0.26 if _last_hit_crit else (0.20 if heavy else 0.12))
	else:
		_combo_count = 0
		_combo_timer = 0.0
		combo_changed.emit(_combo_count)

# Zadaje obrażenia jednemu wrogowi — ETAP 1: przez DamageService (host-authoritative).
# Combo→przebicie i krytyk/lifesteal pakujemy w HitData; DamageService liczy pancerz po przebiciu,
# odporności i krytyk w JEDNYM miejscu (TDD 4). W SP NetManager.has_authority()==true -> rozstrzyga
# lokalnie, więc odczucie gry jest identyczne jak przy dawnym inline'ie.
func _deal_damage_to(enemy: Node) -> void:
	DamageService.request_hit(self, enemy, _build_hit())

# Buduje HitData bieżącego ciosu z combo→przebicia i (jeśli jest) StatsComponent gracza.
# combo_count jest już zinkrementowane (wariant A) — pierwszy cios = 15% przebicia.
func _build_hit() -> HitData:
	var hit := HitData.new()
	hit.source = self
	hit.base_damage = _stat(&"damage", attack_damage)
	var pierce := float(_combo_count) * armor_pierce_per_combo
	if _perfect_bonus_next:                            # premia za perfect-dodge: +przebicie na 1 cios
		pierce += perfect_dodge_pierce_bonus
		_perfect_bonus_next = false
	hit.armor_pierce = minf(armor_pierce_max, pierce)
	hit.crit_chance = _stat(&"crit_chance", 0.0)      # 0 gdy brak StatsComponent (zachowanie sprzed Etapu 1)
	hit.crit_mult = _stat(&"crit_mult", 1.5)
	hit.lifesteal = _stat(&"lifesteal", 0.0)
	# FAZA 1: 3. cios lancucha = mocniejszy KNOCKBACK (waga finishera serii). Inne ciosy = 6.0 jak dotad.
	hit.knockback = 11.0 if _is_chain_finisher() else 6.0
	# typed: HitData.tags to Array[StringName] (4.x strict — literal daje goly Array).
	var t: Array[StringName] = []
	t.append(&"melee")
	hit.tags = t
	return hit

# Odczyt staty przez StatsComponent (jeśli wpięty), inaczej fallback na eksport (Etap 0/1 most).
func _stat(key: StringName, fallback: float) -> float:
	if _stats != null:
		return _stats.get_stat(key)
	return fallback

# Hitstop (0C): krótki bezczas przy trafieniu — najsilniejszy „juice" walki.
# ETAP 1 (TDD 6.4): globalny Engine.time_scale ZAMRAŻA wszystkich w co-opie. Dlatego globalny
# bezczas dozwolony TYLKO w prawdziwym single-player (brak transportu sieciowego). W co-opie
# robimy „local freeze-frame" — krótkie zamrożenie własnej pozy ataku + trauma kamery (lokalne FX).
func _hitstop(dur: float) -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	if not NetManager.has_network():
		# SP: globalny time_scale wolno (nikogo nie zamrażamy poza sobą — jesteśmy sami).
		Engine.time_scale = 0.05
		await get_tree().create_timer(dur, true, false, true).timeout  # ignore_time_scale=true (realny czas)
		Engine.time_scale = 1.0
	else:
		# CO-OP: lokalny freeze-frame pozy ataku (nie ruszamy globalnego czasu).
		_local_freeze_t = dur
		await get_tree().create_timer(dur, true, false, true).timeout
	_hitstop_active = false

# ============================================================================
#  WALKA — UNIK (dash z i-frames)
# ============================================================================

func _try_dodge() -> void:
	if is_dead:
		return
	if not _can_dodge():
		# ETAP 1: nie teraz -> buforuj (np. wciśnięty w trakcie ataku, odpali po CD uniku).
		_dodge_buffered = dodge_buffer_time
		return
	# ETAP 1 (DoD): unik jako SkillResource przez AbilityComponent (koszt staminy + CD w komponencie).
	# perform_skill (_perform_skill) zdeleguje do _begin_dash(). Fallback (brak komponentu) = wprost.
	if _ability != null and _skill_dash != null:
		# Koszt/CD pilnuje AbilityComponent (cost_resource=stamina, cooldown=dodge_cooldown). Dodatkowo
		# trzymamy stary _dodge_cd zsynchronizowany, by _can_dodge() (input gate) działał spójnie.
		_dodge_cd = dodge_cooldown
		_ability.try_use(_skill_dash)
	else:
		stamina -= dodge_stamina_cost
		_stamina_idle = 0.0
		stamina_changed.emit(stamina, max_stamina)
		_dodge_cd = dodge_cooldown
		_begin_dash()

# Wykonanie zrywu uniku (ruch + i-frames + perfect-dodge + cancel ataku). Wołane przez
# AbilityComponent.perform_skill (droga komponentowa) lub bezpośrednio w fallbacku.
func _begin_dash() -> void:
	_dodge_t = dodge_time
	_dodge_active_t = 0.0           # ETAP 1: start okna perfect-dodge
	_iframes = maxf(_iframes, dodge_iframes)
	is_dodging = true
	_play_sfx(&"dodge")             # ETAP 8: SFX uniku (no-op bez pliku). perfect_dodge gra osobno (Main).
	# FEEL (5): POWER FANTASY uniku — 3 "duchy" modelu gasnace wzdluz toru dasha (afterimage).
	# Spawnujemy 3 klony pozy z lekkim opoznieniem przez _afterimage_left (zlapie ruch postaci).
	_afterimage_left = 3
	_afterimage_t = 0.0
	_spawn_afterimage()            # pierwszy duch natychmiast (start zrywu)
	# ETAP 1 / FAZA 1: CANCEL ataku w unik (kazda faza timeline) — priorytet ucieczki. Czysci tez
	# bufor ataku, lancuch combo i zamyka ewentualne otwarte okno hitboxa (cancel-into-dodge ZAWSZE).
	is_attacking = false
	_attack_anim_t = 0.0
	_attack_buffered = 0.0
	_dodge_recovery_t = 0.0        # nowy dash resetuje recovery poprzedniego
	if _atk_phase != AtkPhase.NONE:
		_atk_phase = AtkPhase.NONE
		_atk_phase_t = 0.0
		_chain_queued = false
		_chain_step = 0
		if _hitbox != null:
			_hitbox.close_window()
	if _ability != null:
		_ability.cancel()          # anuluj ewentualny zakolejkowany/trwający atak w AbilityComponent

	# Kierunek: WASD jeśli się ruszasz, inaczej forward modelu; fallback = forward kamery.
	var dir := _wish_direction()
	if dir.length() < 0.1:
		dir = -_model.global_transform.basis.z
		dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3(-sin(_pivot.rotation.y), 0.0, -cos(_pivot.rotation.y))
	_dodge_dir = dir.normalized()

# Zwraca świat-kierunek z WASD+yaw kamery (ta sama logika co w _physics_process).
# ETAP 7 (review #minor): gdy NIE czytamy lokalnego inputu (host symuluje cudzą postać), kierunek
# bierzemy z inputu KLIENTA (_net_sync.remote_input_dir), nie z klawiatury hosta — inaczej dash
# cudzej postaci szedłby wg klawiszy hosta. W SP/u klienta-właściciela: klawiatura jak dotąd.
func _wish_direction() -> Vector3:
	var input_dir := Vector2.ZERO
	if _net_sync != null and not _net_sync.should_read_local_input():
		input_dir = _net_sync.remote_input_dir()
	else:
		if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1.0
		if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1.0
	input_dir = input_dir.normalized()
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO
	var yaw := _pivot.rotation.y
	return Vector3(input_dir.x, 0.0, input_dir.y).rotated(Vector3.UP, yaw)

# ETAP 1: nagroda za perfect-dodge. Bullet-time GLOBALNY tylko w SP (TDD 6.4: w co-opie zamroziłby
# wszystkich — wtedy lokalny freeze-frame). Premia przebicia leci na następny cios (_build_hit).
func _on_perfect_dodge() -> void:
	_perfect_bonus_next = true
	add_trauma(0.18)
	perfect_dodge.emit()
	_play_sfx(&"perfect_dodge")          # FEEL (5): osobny dzwiek nagrody (no-op bez pliku; AudioManager ma fallback)
	# FEEL (5): ZWROT ZASOBU — perfect-dodge oddaje wydana stamine (nagroda za timing -> agresywna gra).
	if stamina < max_stamina:
		stamina = minf(max_stamina, stamina + dodge_stamina_cost)
		_stamina_idle = 0.0
		stamina_changed.emit(stamina, max_stamina)
	# FEEL (5): ROZBLYSK wokol gracza (puls swiatla przez FeelFX) — czytelna nagroda za perfect.
	_spawn_perfect_flash()
	if _hitstop_active:
		return
	_hitstop_active = true
	if not NetManager.has_network():
		Engine.time_scale = perfect_dodge_slowmo
		await get_tree().create_timer(perfect_dodge_slowmo_time, true, false, true).timeout
		Engine.time_scale = 1.0
	else:
		_local_freeze_t = perfect_dodge_slowmo_time
		await get_tree().create_timer(perfect_dodge_slowmo_time, true, false, true).timeout
	_hitstop_active = false

# FEEL (5): rozblysk perfect-dodge przez centralny FeelFX (puls swiatla + iskra wokol gracza).
# FeelFX jest w drzewie (Main go dodaje); brak (test/headless) -> ciche no-op (bez crasha).
func _spawn_perfect_flash() -> void:
	var fx := _find_feel_fx()
	if fx != null and fx.has_method("spawn_hit_vfx"):
		fx.spawn_hit_vfx(global_position + Vector3(0.0, 1.0, 0.0), Color(0.6, 0.85, 1.0), true)

# FAZA 4: leniwy lookup centralnego FeelFX w drzewie (Main go dodaje). Cache + walidacja instancji.
# Brak (headless/test bez Main) -> null => wszyscy wolajacy robia ciche no-op.
func _find_feel_fx() -> Node:
	if _feel_fx_ref != null and is_instance_valid(_feel_fx_ref):
		return _feel_fx_ref
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	_feel_fx_ref = tree.root.find_child("FeelFX", true, false)
	return _feel_fx_ref

# FAZA 4 (1): smuga broni w fazie ACTIVE ataku. Wolane z _enter_attack_active i finishera (NIGDY w
# ANTICIPATION). origin u barku (~0.9 m), kierunek = _atk_forward, kolor broni, big dla finishera.
func _spawn_slash_trail(big: bool) -> void:
	var fx := _find_feel_fx()
	if fx != null and fx.has_method("spawn_slash_trail"):
		var origin := global_position + Vector3(0.0, 0.9, 0.0)
		fx.spawn_slash_trail(origin, _atk_forward, _weapon_trail_color, big)

# FAZA 4 (3): aura skilla (wg SkillResource.aura_kind) w fazie ACTIVE. No-op gdy skill nie ma aury.
func _spawn_ability_aura(skill: SkillResource) -> void:
	if skill == null or skill.aura_kind == &"":
		return
	var fx := _find_feel_fx()
	if fx != null and fx.has_method("spawn_ability_aura"):
		fx.spawn_ability_aura(skill.aura_kind, skill.aura_color, skill.aura_radius,
			global_position, _atk_forward)

# FAZA 4 (6): per-biom kolor pylu spod stop. Main/World woła przy zmianie biomu (reuse palety biomu).
# Tani: jeden albedo_color set na materiale emitera (nie per-czastka).
func set_dust_tint(color: Color) -> void:
	if _land_dust == null:
		return
	var mesh := _land_dust.draw_pass_1 as QuadMesh
	if mesh != null and mesh.material is StandardMaterial3D:
		(mesh.material as StandardMaterial3D).albedo_color = color

# ============================================================================
#  HP, OBRAŻENIA, ŚMIERĆ, RESPAWN
# ============================================================================

# ETAP 1: BRAMKA obrażeń wpięta w HealthComponent.damage_gate. Zwraca true -> cios ZABLOKOWANY
# (HP nietknięte). Trzyma nietykalność gracza (i-frames / perfect-dodge) PRZED HealthComponent,
# który pozostaje jedynym źródłem HP. Perfect-dodge (cios w oknie 0.12 s aktywnego uniku) odpala
# nagrodę i też blokuje cios.
func _damage_gate(_amount: float, _from: Node) -> bool:
	if is_dead:
		return true
	if _iframes > 0.0:
		if is_dodging and _dodge_active_t <= perfect_dodge_window:
			_on_perfect_dodge()
		return true
	return false

# PUBLICZNA — wołana przez DamageService (FX-only: amount=0 + knockback) i jako fasada (amount>0).
# 'from' to węzeł źródła. Knockback>=0 nadpisuje hardkod 6.0 (siła per-cios z HitData).
# i-frames/perfect-dodge oraz odjęcie HP załatwia HealthComponent (przez damage_gate/apply_damage);
# tu robimy FX (błysk + odrzut) i — w fallbacku bez HealthComponent — klasyczne odjęcie HP.
func take_damage(amount: float, from: Node = null, knockback: float = -1.0) -> void:
	if is_dead:
		return
	# Gdy HP liczy HealthComponent: i-frames/perfect-dodge sprawdza damage_gate (wywołany z
	# apply_damage). Tu, dla FX (błysk/odrzut), respektujemy tę samą nietykalność.
	if _iframes > 0.0:
		if _health == null and is_dodging and _dodge_active_t <= perfect_dodge_window:
			_on_perfect_dodge()    # w trybie komponentowym perfect-dodge odpala damage_gate
		return

	_flash_hit()              # błysk koloru modelu (czerwień)
	# ETAP 3: otrzymany cios buduje Furie (+4 — GDD 4.2, ROADMAP 6). Tylko realne trafienie
	# (po przejsciu i-frames/perfect-dodge powyzej), niezaleznie od tego kto liczy HP.
	if _class_res != null:
		_class_res.on_hit_taken()

	# Knockback: odpychamy w bok OD źródła trafienia (poziomo) + lekko w górę. Siła z HitData lub 6.0.
	var src := global_position
	if from != null and from is Node3D:
		src = (from as Node3D).global_position
	var dir := global_position - src
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = -global_transform.basis.z    # gdy pozycje się nakładają — pchnij do tyłu
		dir.y = 0.0
	var force := knockback if knockback >= 0.0 else 6.0
	_knockback = dir.normalized() * force
	_knockback.y = 3.0

	# FAZA 2: HIT-REACT additive (zachwianie tulowia/glowy ~0.12 s). Kierunek OD zrodla (XZ swiatowy),
	# reuse 'dir' policzonego wyzej. Czysto wizualne (gasnie w _anim_additive), nie psuje lokomocji.
	_hitreact_dir = dir.normalized()
	_hitreact_t = HITREACT_TIME

	# HP: gdy wpięty HealthComponent — to ON liczy HP/śmierć (DoD). amount>0 (bezpośrednie wywołanie)
	# kierujemy do niego; amount==0 to czysty hook FX (DamageService już zadał obrażenia komponentowi).
	if _health != null:
		if amount > 0.0:
			_health.apply_damage(amount, from)
		return
	# Fallback (brak HealthComponent): klasyczne odjęcie HP w tym pliku.
	hp = maxf(0.0, hp - amount)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		_die()

# Mostek z HealthComponent: HP zmienione -> mirror do pola hp (HUD/wrogowie czytają hp) + sygnał HUD.
func _on_health_hp_changed(current: float, _maximum: float) -> void:
	hp = current
	hp_changed.emit(hp, max_hp)

# Śmierć przez HealthComponent -> wspólna ścieżka _die.
func _on_health_died(_from: Node) -> void:
	_die()

func _die() -> void:
	if _dead_emitted:
		return                # idempotencja: HealthComponent.died + ewentualny fallback nie dublują
	_dead_emitted = true
	is_dead = true
	is_attacking = false
	is_dodging = false
	_attack_anim_t = 0.0
	_dodge_t = 0.0
	hp = 0.0
	# Zamknij TIMELINE ataku na smierci: bez tego cios ktory dosiegnal w ANTICIPATION przechodzilby
	# do ACTIVE (otwarcie okna hitboxa) JUZ PO smierci gracza — _tick_attack_timeline tyka bezwarunkowo.
	# (Pre-existing; domykane przy okazji nowej sciezki smierci.) Zamknij tez okno hitboxa na wszelki wypadek.
	if _atk_phase != AtkPhase.NONE:
		_atk_phase = AtkPhase.NONE
		_atk_phase_t = 0.0
		if _hitbox != null:
			_hitbox.close_window()
	# FAZA 2: poza SMIERCI (przewrocenie) — animowana additive w _anim_additive (warstwa 7). Czysto
	# wizualne; respawn nadal steruje Main (timer + respawn()), ktory zeruje _dying (patrz respawn()).
	_dying = true
	_death_t = 0.0
	# Wyzeruj squash/stretch i skale modelu PRZED poza smierci — inaczej gracz ginacy w trakcie
	# ladowania/lotu zachowuje rozlana/rozciagnieta sylwetke przez cala animacje przewrocenia
	# (death branch pisze tylko scale.y, .x/.z zostawaly z ostatniej klatki squash/stretch).
	_stretch = 0.0
	if _model != null:
		_model.scale = Vector3.ONE
	# Zdejmij nakladke additive (rotacja) — death branch wraca wczesnie i nie un-bake'uje jej sam.
	_add_torso = Vector3.ZERO
	_add_head = Vector3.ZERO
	hp_changed.emit(hp, max_hp)
	died.emit()
	# Uwaga: faktyczny respawn z opóźnieniem steruje Main (timer + wywołanie respawn()).

func respawn() -> void:
	is_dead = false
	_dead_emitted = false
	if _health != null:
		_health.revive_full()       # HealthComponent: zdejmij flagę śmierci + pełne HP
	hp = max_hp
	stamina = max_stamina
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_combo_count = 0
	_combo_timer = 0.0
	_attack_cd = 0.0
	_attack_anim_t = 0.0
	_dodge_t = 0.0
	_dodge_cd = 0.0
	is_attacking = false
	is_dodging = false
	# Wyzeruj TIMELINE ataku po odrodzeniu (czystosc — nie polegaj na samo-korekcie timeline'u).
	_atk_phase = AtkPhase.NONE
	_atk_phase_t = 0.0
	# FAZA 2: zdejmij poze smierci — wstajemy prosto (wyzeruj przewrocenie i skale modelu).
	_dying = false
	_death_t = 0.0
	if _model != null:
		_model.rotation.z = 0.0
		_model.scale = Vector3.ONE
	_stretch = 0.0
	# Wyzeruj nakladke additive (rotacja) — nastepny _anim_additive zaczyna od czystej bazy.
	_add_torso = Vector3.ZERO
	_add_head = Vector3.ZERO
	_iframes = respawn_iframes   # nietykalność po odrodzeniu
	global_position = respawn_point
	# Teleport: wyzeruj interpolację, żeby postać nie „smużyła" z punktu śmierci do respawnu.
	reset_physics_interpolation()
	if _pivot != null:
		_pivot.global_position = global_position + Vector3(0.0, 1.6, 0.0)
	hp_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)
	combo_changed.emit(_combo_count)   # HUD: wyzeruj wskaźnik combo po respawnie
	respawned.emit()

# ============================================================================
#  BŁYSK TRAFIENIA (emisja na całym modelu, gasnąca przez Tween)
# ============================================================================

# Krótki czerwony błysk emisji na całym modelu (ok. 0,18 s). NIE rusza albedo.
func _flash_hit() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	var meshes := _collect_meshes(_model)
	for mi in meshes:
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.15, 0.1)
		mat.emission_energy_multiplier = 2.0
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	for mi in meshes:
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		# Wygaszamy mnożnik emisji do 0 — model wraca do normalnych kolorów.
		_flash_tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.18)
	# Po wygaśnięciu błysku WYŁĄCZAMY emisję na meshach (chain() = sekwencyjnie po
	# równoległych tweenach powyżej). Bez tego emission_enabled zostałoby na stałe true
	# na każdym meshu modelu (mnożnik 0 = niewidoczne, ale to ukryta zmiana stanu, która
	# mogłaby zaskoczyć przy dokładaniu kolejnych efektów emisji).
	_flash_tween.chain().tween_callback(func() -> void:
		for mi in meshes:
			var m := mi.material_override as StandardMaterial3D
			if m != null:
				m.emission_enabled = false
	)

# ============================================================================
#  FEEL (5): AFTERIMAGE uniku — duch modelu (klon pozy) gasnacy w miejscu
# ============================================================================
# Tworzy lekki "duch": jeden MeshInstance3D z polaczonym meshem aktualnej pozy modelu, w GLOBALNEJ
# transformacie (top_level), z dodatnia emisja na chlodny blekit. Gasnie Tweenem i sam sie zwalnia.
# Tanio: 1 node + 1 material per duch, max 3 na unik, zycie 0.22 s. Brak wplywu na rozgrywke.
func _spawn_afterimage() -> void:
	if _model == null:
		return
	var meshes := _collect_meshes(_model)
	if meshes.is_empty():
		return
	# Ghost jako kontener w GLOBALNEJ pozie modelu — kopiujemy KAZDY mesh ze wzgledna transformata,
	# by zachowac aktualne zgiecia konczyn (poza zamrozona w chwili spawnu).
	var ghost := Node3D.new()
	ghost.top_level = true
	get_tree().current_scene.add_child(ghost)
	ghost.global_transform = _model.global_transform
	var inv := _model.global_transform.affine_inverse()
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.albedo_color = Color(0.4, 0.7, 1.0, 0.5)
	ghost_mat.emission_enabled = true
	ghost_mat.emission = Color(0.35, 0.6, 1.0)
	ghost_mat.emission_energy_multiplier = 1.6
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for src in meshes:
		var gi := MeshInstance3D.new()
		gi.mesh = src.mesh
		gi.material_override = ghost_mat
		gi.transform = inv * src.global_transform   # poza wzgledem roota modelu (zamrozona)
		ghost.add_child(gi)
	# Gasniecie: alpha + emisja -> 0, potem free. set_ignore_time_scale(true) — duch gasnie w REALNYM
	# czasie, niezaleznie od bullet-time perfect-dodge (Engine.time_scale 0.05). Bez tego duch z poprzed-
	# niej klatki dasha wisialby ~20x dluzej na ekranie podczas slow-mo (kosmetyczny smuga). Zgodnie z
	# timerami hitstopu, ktore juz przekazuja ignore_time_scale=true.
	var tw := ghost.create_tween()
	tw.set_ignore_time_scale(true)
	tw.set_parallel(true)
	tw.tween_property(ghost_mat, "albedo_color:a", 0.0, AFTERIMAGE_LIFE)
	tw.tween_property(ghost_mat, "emission_energy_multiplier", 0.0, AFTERIMAGE_LIFE)
	tw.chain().tween_callback(ghost.queue_free)

# Zbiera wszystkie MeshInstance3D z poddrzewa modelu (tułów, głowa, kończyny).
func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node == null:
		return out
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_collect_meshes(child))
	return out

# ============================================================================
#  GETTERY dla HUD
# ============================================================================

func get_hp_ratio() -> float:
	return 0.0 if max_hp <= 0.0 else hp / max_hp

func get_stamina_ratio() -> float:
	return 0.0 if max_stamina <= 0.0 else stamina / max_stamina

func get_combo() -> int:
	return _combo_count
