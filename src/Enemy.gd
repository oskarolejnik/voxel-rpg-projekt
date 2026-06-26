class_name Enemy
extends CharacterBody3D
## Enemy.gd — pierwszy wróg (Goblin Critter) + AI (ETAP 3, RUNDA 1).
##
## Mały, krępy stwór z voxeli (BoxMesh przez _cube). Maszyna stanów:
##   IDLE → PATROL → CHASE → ATTACK, z leashem (powrotem do domu) i histerezą.
## Rozdział obowiązków jak u gracza:
##   _physics_process — fizyka: grawitacja, wybór stanu, ruch, auto-podskok, move_and_slide,
##   _process         — wizuale: obrót modelu w stronę celu/ruchu, kołysanie kończyn, błysk.
##
## Kontrakt z graczem: gracz jest w grupie "player", ma metodę take_damage(amount, from).
## Wróg jest w grupie "enemies" i ma opcjonalne pole armor (0..1) + metodę take_damage —
## czyta je rdzeń walki gracza (combo→przebicie pancerza).

signal died(enemy: Enemy)        # emitowany tuż przed queue_free() — Main liczy ubitych

# ============================================================================
#  STATYSTYKI (eksporty — łatwy tuning)
# ============================================================================
@export var max_hp: float = 30.0
@export var move_speed: float = 3.5           # wolniejszy od gracza (speed=6) → da się uciec
@export var attack_damage: float = 8.0
@export var attack_range: float = 2.0         # zasięg ataku w zwarciu
@export var attack_cooldown: float = 1.2      # s między atakami
@export var attack_windup: float = 0.35       # s "zamachu" przed zadaniem dmg (można odskoczyć)
@export var attack_entry_delay: float = 0.35  # s zwłoki PRZED pierwszym ciosem po wejściu w zwarcie
                                              # (gracz ma okno na unik, zanim padnie pierwsze trafienie)
@export var aggro_radius: float = 12.0        # promień wykrycia gracza → CHASE
@export var leash_radius: float = 18.0        # gracz dalej niż to → powrót do PATROL
@export var patrol_radius: float = 6.0        # promień drobnego błądzenia wokół domu
@export var turn_speed: float = 10.0          # szybkość obrotu modelu (lerp_angle)
@export var knockback_force: float = 5.0      # odrzut przy trafieniu
@export var hit_flash_time: float = 0.12      # s mignięcia na biało

# Opcjonalny pancerz (0..1 = % redukcji obrażeń). Czyta go gracz (przebicie combo).
@export var armor: float = 0.0

# ============================================================================
#  ETAP 2 — LOOT (kontekst dropu czytany przez LootService.drop_for)
# ============================================================================
# Tablica lootu (LootTableResource). Pusta -> LootService daje sensowny default (vertical slice).
@export var loot_table: LootTableResource
# Poziom itemu dropu (skaluje wartosci afiksow); Etap 4 ustawi wg biomu/dystansu. Domyslnie 1.
@export var loot_ilvl: int = 1
# Biom dropu (filtr afiksow tematycznych); Etap 4 ustawi z get_biome. Domyslnie verdant.
@export var loot_biome: StringName = &"verdant"
# ETAP 4: PREMIA RZADKOSCI z loot_tier biomu (BiomeResource.loot_tier - 1). 0 = verdant (tier1),
# 1 = emberwaste (tier2), 2 = frosthelm (tier3). Czytana przez LootService._roll_rarity — przesuwa
# wagi rzadkosci ku wyzszym tierom (analogicznie do magic_find), wiec bogatszy biom realnie dropi
# lepiej. Spawner ustawia ja z EnemyDB.biome(biome_id).loot_tier (wczesniej pole bylo martwe).
@export var loot_tier_bonus: int = 0
# Etap 2: emitowany przy smierci z policzonym dropem (Main spawnuje LootDrop). Niesie pozycje +
# liste wpisow z LootService.drop_for (item/zloto). Pozwala spawnowac loot ZANIM encja zniknie.
signal loot_dropped(world_pos: Vector3, drops: Array)

# ============================================================================
#  ETAP 1 — WARIANTY (Brute/Slinger) + droga komponentowa
# ============================================================================
# Profil AI / sposób ataku: &"melee" (zwarcie) lub &"ranged" (Slinger — spawnuje pocisk).
@export var ai_profile: StringName = &"melee"
# Slinger: prędkość pocisku (m/s) i lekka grawitacja (>0 = łuk; 0 = prosto). Pierce 0 (1 cel).
@export var projectile_speed: float = 16.0
@export var projectile_gravity: float = 0.0
@export var projectile_pierce: int = 0
# Krytyk pocisku/ciosu wroga (domyślnie bez krytyka — zwykły mob).
@export var crit_chance: float = 0.0
@export var crit_mult: float = 1.5

# ============================================================================
#  ETAP 4 — WARIANTY BIOMOWE + TELEGRAFY (threat_tier)
# ============================================================================
# Klasa zagrożenia (z EnemyResource.threat_tier): &"trash"/&"elite"/&"boss". Steruje TELEGRAFEM
# ataku (elite/boss pokazują strefę-zapowiedź HazardZone preview przed ciosem — czytelność hordy).
@export var threat_tier: StringName = &"trash"
# Skala modelu (Brute = krępy/większy elite; default 1.0). Ustawiana z wariantu.
@export var body_scale: float = 1.0
# Reskin biomowy: nadpisuje paletę skóry/oczu (ognisty/lodowy wariant). Pusty -> domyślny goblin.
@export var skin_tint: Color = Color(0, 0, 0, 0)        # a==0 => brak reskinu
@export var eye_tint: Color = Color(0, 0, 0, 0)         # a==0 => domyślne żółte oczy
# Element ciosu (tag dosypywany do HitData: &"fire"/&"frost"...). Pusty -> brak elementu.
@export var element: StringName = &""
# Identyfikator wariantu (diagnostyka / loot). Np. &"goblin"/&"brute"/&"slinger"/&"ember_brute".
@export var variant_id: StringName = &"goblin"

# ============================================================================
#  FAZA 5 — ROAMING ELITE (wedrujacy elite, widoczny z daleka jako cel/zagrozenie, model CW)
# ============================================================================
# Czy ten wrog jest WEDRUJACYM ELITE (WorldSpawner promuje rzadko). Wizualnie wyrozniony: wieksza
# skala + emisyjna AURA (OmniLight pulsujacy) + boost statow; szeroki patrol/leash (wedruje po
# swiecie). NIE wplywa na walke gracza poza silniejszym wrogiem (power-fantasy zachowane: nadal
# kosisz hordy, elite to mini-cel). Pole czytane przez loot (wyzszy ilvl) i wizual.
var _is_roaming_elite: bool = false
# Aura emisyjna roaming-elite (OmniLight3D) — pulsuje, czytelna z daleka. null gdy nie-elite.
var _elite_aura: OmniLight3D = null
const ELITE_AURA_BASE_ENERGY: float = 2.2
const ELITE_AURA_RANGE: float = 6.0
var _elite_aura_phase: float = 0.0

# Aktywny telegraf bieżącego ciosu (HazardZone preview). Zwalniany po zadaniu ciosu / przerwaniu.
var _telegraph: HazardZone = null

# ART OVERHAUL: PERSYSTENTNY ZNACZNIK KLASY ZAGROŻENIA (elite/boss). Unoszący się marker nad głową
# (emisyjny) — delikatnie pulsuje/bobuje w _process, by groźba czytała się z daleka. Pierścień u stóp
# jest statyczny (część _model). Kolor wg tier (elite=bursztyn, boss=czerwień) + element. Tani: same
# emisyjne meshe (ZERO świateł — nie obciąża budżetu always-on lights z Art Bible). null = trash.
var _threat_marker: Node3D = null
var _threat_marker_phase: float = 0.0

# ============================================================================
#  #11 — BOSS: UNIKATOWA MECHANIKA (ENRAGE poniżej 50% HP)
# ============================================================================
# Lock-key dungeonu prowadzi do bossa; żeby finał nie był "najgrubszym trashem", boss dostaje fazę
# ENRAGE: przy spadku HP <=50% raz wchodzi w szał — szybsze i mocniejsze ciosy + szybszy ruch (czytelny
# zwrot walki: "boss się wkurzył"). Wizualnie: emisyjna AURA wściekłości (czerwony OmniLight) + lekkie
# powiększenie sylwetki. Mechanika GATED na threat_tier==&"boss" ORAZ jawnie włączona set_boss_mechanics
# (default off): zwykłe moby i elity NIGDY nie szałują (wsteczna zgodność). Trigger w _on_health_hp_changed
# (Enemy już słucha hp_changed z HealthComponent) — jedno źródło HP, brak osobnego pollingu.
@export var boss_mechanics: bool = false        # czy boss ma fazę enrage (DungeonRun włącza dla bossa)
@export var enrage_hp_frac: float = 0.5         # próg HP (ułamek max) wejścia w szał
@export var enrage_damage_mult: float = 1.5     # mnożnik dmg po szale
@export var enrage_speed_mult: float = 1.35     # mnożnik prędkości ruchu po szale
@export var enrage_attack_speed_mult: float = 1.4  # mnożnik szybkości ataku (skraca attack_cooldown)
var _enraged: bool = false                       # jednorazowa flaga szału (nie cofa się przy leczeniu)
# Aura szału (OmniLight3D) — czerwona, pulsuje szybciej niż aura elite. null póki nie wkurzony.
var _enrage_aura: OmniLight3D = null
const ENRAGE_AURA_BASE_ENERGY: float = 3.0
const ENRAGE_AURA_RANGE: float = 7.0
var _enrage_aura_phase: float = 0.0

# ETAP 4: konfiguruje wroga z EnemyResource PRZED dodaniem do drzewa (więc _build_components
# zobaczy już docelowe staty). WOŁAĆ tuż po Enemy.new(), ZANIM add_child / _ready. Mapuje
# StatBlock -> eksporty (max_hp/dmg/armor/speed/krytyk), ai_profile, threat_tier, loot (table/biome).
# Bezpieczne na null (zostają domyślne goblinowe wartości).
func configure_from_resource(res: EnemyResource) -> void:
	if res == null:
		return
	variant_id = res.id if res.id != &"" else variant_id
	ai_profile = res.ai_profile
	threat_tier = res.threat_tier
	disposition = res.disposition   # EKOSYSTEM: hostile/neutral/passive -> AIComponent (przez _build_components)
	poise = res.poise               # COMBAT: pula poise (odporność na stagger); 0 = trash
	_poise_current = poise
	if res.loot_table != null:
		loot_table = res.loot_table
	var sb: StatBlock = res.stats
	if sb != null:
		max_hp = sb.max_hp
		hp = sb.max_hp
		attack_damage = sb.damage
		armor = clampf(sb.armor, 0.0, 1.0)
		crit_chance = sb.crit_chance
		crit_mult = sb.crit_mult
		move_speed = sb.move_speed
		# attack_cooldown == 1/attack_speed (spójnie z StatBlock: attack_speed == 1/cooldown).
		if sb.attack_speed > 0.0:
			attack_cooldown = 1.0 / sb.attack_speed
	# Parametry wariantu spoza StatBlock (windup/zasięg/telegraf/reskin) wnosi metadata zasobu.
	_apply_variant_meta(res)

# Czyta opcjonalne pola wariantu z EnemyResource.variant_meta (Dictionary) — windup, attack_range,
# projectile, skala ciała, reskin (skin/eye), element. Pozwala trzymać liczby wariantów w .tres bez
# rozszerzania StatBlock. Brak pola -> zostaje obecna (goblinowa) wartość.
func _apply_variant_meta(res: EnemyResource) -> void:
	if not ("variant_meta" in res):
		return
	var m: Dictionary = res.variant_meta
	attack_windup = float(m.get("attack_windup", attack_windup))
	attack_range = float(m.get("attack_range", attack_range))
	attack_entry_delay = float(m.get("attack_entry_delay", attack_entry_delay))
	aggro_radius = float(m.get("aggro_radius", aggro_radius))
	leash_radius = float(m.get("leash_radius", leash_radius))
	projectile_speed = float(m.get("projectile_speed", projectile_speed))
	projectile_gravity = float(m.get("projectile_gravity", projectile_gravity))
	projectile_pierce = int(m.get("projectile_pierce", projectile_pierce))
	body_scale = float(m.get("body_scale", body_scale))
	element = StringName(m.get("element", element))
	if m.has("skin_tint"):
		skin_tint = m["skin_tint"]
	if m.has("eye_tint"):
		eye_tint = m["eye_tint"]


# ============================================================================
#  FAZA 5 — PROMOCJA W ROAMING ELITE (wolane przez WorldSpawner PRZED add_child)
# ============================================================================
## Czyni z tego wroga WEDRUJACEGO ELITE: podbija staty (HP/dmg), powieksza model, ustawia threat_tier
## na elite (telegraf ciosu), POSZERZA patrol/leash/aggro (wedruje szeroko po swiecie) i oznacza do
## budowy AURY emisyjnej w _build_components/_ready. WOLAC tuz po configure_from_resource, ZANIM
## add_child (jak configure_from_resource — staty wejda do StatsComponent). Mnozniki konserwatywne:
## elite ma byc mini-celem, nie scianą — power-fantasy hordy zostaje (ROADMAP6).
func promote_to_roaming_elite() -> void:
	_is_roaming_elite = true
	# Staty: +120% HP, +40% dmg — wyrazny "mini-boss" w terenie, ale wciaz do ubicia w kilka ciosow.
	max_hp *= 2.2
	hp = max_hp
	attack_damage *= 1.4
	# threat_tier elite => telegraf ciosu (czytelnosc) jesli nie byl juz elite/boss.
	if threat_tier == &"trash":
		threat_tier = &"elite"
	# Wizualnie wiekszy (sylwetka "celu" z daleka). Mnoznik na istniejaca skale wariantu.
	body_scale = maxf(body_scale, 1.0) * 1.35
	# WEDROWKA: szeroki patrol + dlugi leash + duzy aggro => realnie krazy po swiecie, a nie stoi w
	# miejscu (model CW: widoczne, przemieszczajace sie zagrozenie). Szybszy o ~15% by "scigal" feel.
	patrol_radius = maxf(patrol_radius, 22.0)
	leash_radius = maxf(leash_radius, 40.0)
	aggro_radius = maxf(aggro_radius, 18.0)
	move_speed *= 1.12
	# Lepszy loot (mini-cel oplaca sie ubic): +1 do bonusu rzadkosci.
	loot_tier_bonus += 1


## Diagnostyka / test: czy to wedrujacy elite.
func is_roaming_elite() -> bool:
	return _is_roaming_elite


# ============================================================================
#  #11 — API BOSSA: WLACZENIE UNIKATOWEJ MECHANIKI (wolane przez DungeonRun._spawn_one_enemy)
# ============================================================================
## Wlacza faze ENRAGE bossa (default OFF -> zwykle moby/elity nieruszone). Sensowna TYLKO dla
## threat_tier==&"boss" (sam enrage i tak jest gated na ten tier w _on_health_hp_changed), ale flagę
## trzymamy osobno, by jawnie wyrazic "to boss z mechanika" i pozwolic testowi/encji ja sprawdzic.
func set_boss_mechanics(on: bool) -> void:
	boss_mechanics = on


## Diagnostyka / test: czy boss jest w fazie szalu (enrage). Trash/elite: zawsze false.
func is_enraged() -> bool:
	return _enraged

# ETAP 1: komponenty wpięte w realną encję (DoD: atak idzie ścieżką komponentów). Gdy z jakiegoś
# powodu nie powstaną, kod ma BEZPIECZNE fallbacki (eksporty + wbudowana maszyna), więc gra działa.
var _stats: StatsComponent = null               # JEDYNE źródło staty (gdy wpięty)
var _health: HealthComponent = null             # JEDYNE źródło HP (gdy wpięty); hp niżej je mirroruje
var _hurtbox: HurtboxComponent = null           # cel hitboxów gracza (Area3D, warstwa enemy_hurtbox)
var _hitbox: HitboxComponent = null             # okno ataku w zwarciu (Area3D); ranged używa Projectile
# Maszyna stanów jako komponent (host-only). Gdy null -> używamy wbudowanej maszyny w tym pliku.
var _ai: AIComponent = null
var _status: StatusEffectComponent = null   # AUDYT #5: statusy (DoT/chill/stun/weaken) — sibling

# ============================================================================
#  STAN
# ============================================================================
# ETAP 6: FOLLOW dodane na końcu, by mapowanie enum AIComponent.State -> Enemy.State zostalo 1:1
# (tick() zwraca int rzutowany na ten enum). Pet uzywa FOLLOW; wrog nigdy w nim nie jest.
enum State { IDLE, PATROL, CHASE, ATTACK, FOLLOW }
var _state: State = State.IDLE

var hp: float = 30.0
var _target: Node3D = null                    # gracz (push z Main lub fallback z grupy)
var _home: Vector3 = Vector3.ZERO             # punkt startu (środek patrolu / leash)

# ETAP 7b: net_id replikacji (0 = SP / niezarejestrowany). Host nadaje przy host_spawn_enemy;
# klient odtwarza replike z tym samym id (despawn/late-join routuja po nim). W SP zostaje 0.
# Jawne pole klasowe (nie tylko lokalna NetIdentity) — przejrzysty kontrakt, mirror LootDrop.net_id.
var net_id: int = 0

# ETAP 7b: KLIENT-replika (host_authoritative) — gdy ustawione, ten wrog jest CZYSTA REPLIKA u klienta:
# pozycje narzuca MultiplayerSynchronizer, wiec WLASNA fizyka (grawitacja/move_and_slide) jest wylaczona,
# by nie walczyc z synchronizerem (anti-jitter, review #minor). SP/host: zawsze false -> pelna fizyka.
var _is_net_replica: bool = false

# ============================================================================
#  ETAP 6 — ALLEGIANCE (wrog / pet) + skalowanie peta wg gracza
# ============================================================================
# HOSTILE = zwykly wrog (celuje w gracza). ALLY = oswojony pet (celuje w wrogow, leash do gracza).
# Konwersji dokonuje TameSystem.convert_to_pet(): przelacza flage allegiance w AIComponent (cel
# odwrocony) + przeklada warstwy hurtbox/hitbox na strone gracza (pet nie bije gracza, nie jest bity
# przez sojusznikow, JEST bity przez wrogow — GDD 9). Reuse calej maszyny Enemy/AIComponent.
enum Allegiance { HOSTILE, ALLY }
var allegiance: int = Allegiance.HOSTILE
# EKOSYSTEM (GDD Świat §4): 0=hostile/1=neutral/2=passive. Ustawiane przez configure_from_resource
# z EnemyResource.disposition; przekazywane do AIComponent w _build_components. Pet (ALLY) ignoruje.
var disposition: int = 0
var _pet_owner: Node3D = null                 # gracz-wlasciciel (anchor leasha + zrodlo skalowania)
var _patrol_target: Vector3 = Vector3.ZERO
var _face_dir: Vector3 = Vector3.ZERO         # kierunek do obrotu modelu w _process

var _idle_timer: float = 0.0
var _patrol_timer: float = 0.0
var _attack_timer: float = 0.0                # cooldown między atakami
var _windup_timer: float = 0.0
var _attacking: bool = false                  # czy trwa cykl zamachu
# COMBAT (reaktywność — audyt rank #1): hitstun + poise. Każdy cios ustawia _hitstun_t (krótka pauza
# windupu i ruchu własnego — cios "rejestruje się" na wrogu). Złamanie poise (_poise_current<=0)
# PRZERYWA atak (anuluje _attacking + telegraf) i wydłuża stagger. Trash (poise 0) przerywa się
# każdym ciosem; elity/bossy mają poise i opierają się, regenerując ją między ciosami. Knockback osobno.
const HITSTUN_TIME: float = 0.12              # s krótkiego znieruchomienia po każdym ciosie
const STAGGER_TIME: float = 0.35              # s dłuższego stuna po złamaniu poise
const POISE_REGEN: float = 2.0                # poise/s regenerowane poza hitstunem
var poise: float = 0.0                        # max poise (z EnemyResource); 0 = trash
var _poise_current: float = 0.0               # bieżąca poise; <=0 => break (przerwanie ataku)
var _hitstun_t: float = 0.0                   # >0 => windup i ruch własny zamrożone
var _flash_timer: float = 0.0
var _walk_phase: float = 0.0

# FEEL (3): FLINCH (szarpniecie modelu na trafieniu) — wizualne, niezalezne od HP/knockbacku.
const FLINCH_TIME: float = 0.11      # s trwania szarpniecia
const FLINCH_OFFSET: float = 0.14    # m maksymalnego przesuniecia modelu w kierunku ciosu
const FLINCH_TILT: float = 0.35      # rad maksymalnego przechylu (pitch) od uderzenia
var _flinch_t: float = 0.0
var _flinch_dir: Vector3 = Vector3.ZERO   # znormalizowany kierunek OD zrodla (XZ)

# Knockback jako gasnący wektor (jak u gracza) — przeżywa nadpisanie velocity przez AI.
# Doliczany do velocity PO wyborze stanu i wygaszany przez move_toward.
var _knockback: Vector3 = Vector3.ZERO
@export var knockback_decay: float = 18.0     # tempo wygaszania odrzutu (jednostki/s)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)

# Model i pivoty kończyn.
var _model: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
# Czworonóg (beast): zmienia interpretację pivotów na 4 NOGI (przód = _arm_*, tył = _leg_*) i pozę ataku
# (zwierzę nie unosi "ręki" jak humanoid — robi krótki przedni wymach/szarpnięcie pyskiem). Ustawiane w
# _build_silhouette_beast; reszta rigu (chód, flinch, błysk) działa bez zmian (te same 4 pivoty).
var _is_beast: bool = false
var _is_floating: bool = false   # ART OVERHAUL: stwory latające (wywern/żywiołak) — hover w _process
var _float_phase: float = 0.0

# Materiały + bazowe kolory do błysku trafienia (TYPOWANE — pułapka "Cannot infer type").
var _mats: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []

func _ready() -> void:
	add_to_group("enemies")        # świat liczy, gracz wykrywa
	# Warstwy kolizji: wróg na warstwie 3, zderza się WYŁĄCZNIE z terenem (warstwa 1).
	# Dzięki temu wrogowie nie wpychają się nawzajem ani w gracza (warstwa 2) — AI działa
	# po dystansie XZ, a chód po terenie zostaje nienaruszony.
	collision_layer = 1 << 2       # warstwa 3 (bit 2) = wrogowie
	collision_mask = 1             # maska = tylko teren (warstwa 1, bit 0)
	hp = max_hp
	_home = global_position
	_patrol_target = _home
	_idle_timer = randf_range(1.5, 3.5)
	_build_body()
	_build_components()            # ETAP 1: Stats/Health/Hurtbox/Hitbox/AI (droga komponentowa)

# ETAP 1: buduje stos komponentów encji i wpina go w istniejące pola/sygnały.
# Po tym: HP żyje w HealthComponent (hp mirroruje), trafienia gracza lecą do _hurtbox (Area3D) ->
# DamageService -> HealthComponent, AI tyka przez AIComponent, atak melee otwiera okno _hitbox.
func _build_components() -> void:
	# 0) ETAP 7 — NetIdentity z JAWNYM owner_peer = HOST (peer 1). Wrogowie sa host-owned: AI/HP/loot
	#    liczy WYLACZNIE host (TDD 6.2). Jawne ustawienie (a nie poleganie na domyslnym 1) sprawia, ze
	#    NetManager.has_authority(enemy) u klienta jednoznacznie zwraca false (owner_peer != peer klienta)
	#    -> klient nie ma autorytetu nad wrogiem (anti-cheat HP). W SP owner_peer=1 == lokalny peer (no-op).
	var ident := NetIdentity.new()
	ident.owner_peer = NetManager.HOST_PEER_ID if NetManager != null else 1
	add_child(ident)

	# 1) StatsComponent z base StatBlock zbudowanym z eksportów (jedno źródło staty wroga).
	_stats = StatsComponent.new()
	var block := StatBlock.new()
	block.max_hp = max_hp
	block.damage = attack_damage
	block.armor = clampf(armor, 0.0, 1.0)
	block.crit_chance = crit_chance
	block.crit_mult = crit_mult
	block.move_speed = move_speed
	_stats.base = block
	add_child(_stats)

	# 2) HealthComponent — JEDYNE źródło HP. Śmierć -> _die (hook pod loot Etap 2). hp mirroruje.
	_health = HealthComponent.new()
	add_child(_health)
	_health.died.connect(_on_health_died)
	_health.hp_changed.connect(_on_health_hp_changed)
	_health.damaged.connect(_on_health_damaged)   # FEEL (3): flinch (szarpniecie modelu) na obrazeniach
	hp = _health.current_hp

	# 3) HurtboxComponent (Area3D) — cel hitboxów gracza. Kształt ~ kapsuła ciała.
	_hurtbox = HurtboxComponent.new()
	_hurtbox.setup_as_enemy()
	var hs := CollisionShape3D.new()
	var hcap := CapsuleShape3D.new()
	hcap.height = 1.3
	hcap.radius = 0.45
	hs.shape = hcap
	hs.position = Vector3(0.0, 0.65, 0.0)
	_hurtbox.add_child(hs)
	add_child(_hurtbox)

	# 4) HitboxComponent (Area3D) — okno ataku w zwarciu (ranged używa Projectile, hitbox nieaktywny).
	_hitbox = HitboxComponent.new()
	_hitbox.setup_as_enemy(0.2)                 # wąski łuk z przodu wroga
	_hitbox.set_hit_builder(func(_t: Node) -> HitData: return _build_hit())
	var bs := CollisionShape3D.new()
	var bsph := SphereShape3D.new()
	bsph.radius = attack_range
	bs.shape = bsph
	_hitbox.add_child(bs)
	add_child(_hitbox)

	# 5) AIComponent — maszyna stanów host-only (refaktor wbudowanej maszyny). Konfiguracja z eksportów.
	_ai = AIComponent.new()
	add_child(_ai)
	_ai.configure({
		"move_speed": move_speed,
		"attack_range": attack_range,
		"aggro_radius": aggro_radius,
		"leash_radius": leash_radius,
		"patrol_radius": patrol_radius,
		"attack_entry_delay": attack_entry_delay,
		"allegiance_hostile": true,
		"disposition": disposition,
	})
	_ai.set_home(_home)

	# AUDYT #5: StatusEffectComponent (DoT/chill/stun/weaken). PO HealthComponent (czyta je w _ready).
	_status = StatusEffectComponent.new()
	add_child(_status)

# ============================================================================
#  BUDOWA: kolizja + model voxelowy
# ============================================================================
func _build_body() -> void:
	# Kolizja (kapsuła, mniejsza niż gracz; stopy na y=0).
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.3
	capsule.radius = 0.35
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.65, 0.0)
	add_child(shape)

	_build_voxel_enemy()

## FEEL 3: ROZRÓŻNIONE SYLWETKI — Goblin/Brute/Slinger/Beast czytają się Z DALEKA jako inne archetypy
## (readability hordy), nie ten sam model w 3 rozmiarach. Wspólna paleta + reskin biomowy; różni się
## PROPORCJA/SYLWETKA/AKCENT. Wszystkie tworzą TE SAME pivoty (_arm_l/_arm_r/_leg_l/_leg_r + _model),
## więc rig/animacja (_animate_legs, swing ramion, flinch) działa bez zmian. Kind z variant_id:
##   goblin  — krępy, duża głowa, długie szpony, żółte oczy (trash, szybki).
##   brute   — masywny, zgarbiony, ogromne bary, mała głowa, ŚWIECĄCY rdzeń na piersi + maczuga (elite).
##   slinger — smukły, wysoki, kaptur, świecąca KULA pocisku w dłoni (ranged, czytelny "rzucacz").
##   beast   — POZIOMY czworonóg: wydłużony tułów wzdłuż osi patrzenia, głowa/pysk z przodu, 4 nogi
##             (przód _arm_l/_arm_r + tył _leg_l/_leg_r). BUGFIX: dzik/jeleń/wilk renderowały się jako
##             humanoidalny goblin — teraz mają sylwetkę zwierzęcia (kłus diagonalny: tył o π względem przodu).
# Lista "rdzeni" wariantów-czworonogów (po podłańcuchu, by ember_/frost_/dire_ prefiksy i _herd sufiksy
# też trafiały). Ekosystem (GDD Świat §4) zna: wilk, niedźwiedź, jeleń, dzik, kozioł, owca, bawół, lis,
# jaszczur. Dorzucam je wszystkie, by każdy czworonóg dostał sylwetkę zwierzęcia, nie humanoida.
const _BEAST_VARIANTS: PackedStringArray = [
	"boar", "deer", "wolf", "goat", "sheep", "bear", "fox", "buffalo",
	"lizard", "beast",
]
func _enemy_kind() -> StringName:
	var v := String(variant_id)
	if v.ends_with("brute"):
		return &"brute"
	if v.ends_with("slinger"):
		return &"slinger"
	# BUGFIX czworonogi: dopasowanie po PODŁAŃCUCHU (frost_wolf/dire_wolf/ice_wolf/ember_boar... → beast).
	# ART OVERHAUL — roster stworów: routing po PODŁAŃCUCHU variant_id (przed generycznym czworonogiem).
	if v.find("spider") != -1 or v.find("widow") != -1 or v.find("arachnid") != -1 or v.find("weaver") != -1 or v.find("broodmother") != -1 or v.find("tarantula") != -1:
		return &"spider"
	if v.find("scorpion") != -1 or v.find("scorpio") != -1 or v.find("stinger") != -1 or v.find("sandstinger") != -1 or v.find("deathstalker") != -1:
		return &"scorpion"
	if v.find("serpent") != -1 or v.find("snake") != -1 or v.find("viper") != -1 or v.find("cobra") != -1 or v.find("naga") != -1 or v.find("adder") != -1 or v.find("python") != -1:
		return &"serpent"
	if v.find("frog") != -1 or v.find("toad") != -1:
		return &"frog"
	if v.find("treant") != -1 or v.find("tree") != -1 or v.find("oak") != -1 or v.find("grove") != -1:
		return &"treant"
	if v.find("golem") != -1 or v.find("giant") != -1 or v.find("colossus") != -1:
		return &"golem"
	if v.find("wyvern") != -1 or v.find("drake") != -1 or v.find("wyrm") != -1:
		return &"wyvern"
	if v.find("spirit") != -1 or v.find("elemental") != -1 or v.find("wisp") != -1 or v.find("demon") != -1 or v.find("magma") != -1 or v.find("lava") != -1 or v.find("ifrit") != -1:
		return &"spirit"
	if v.find("worm") != -1 or v.find("sandworm") != -1 or v.find("burrow") != -1:
		return &"worm"
	for core in _BEAST_VARIANTS:
		if v.find(core) != -1:
			return &"beast"
	return &"goblin"

# Wspólna paleta wariantu (z reskinem biomowym). Zwraca [skin, skin_d, eyes, mouth, loin, accent].
func _variant_palette() -> Array:
	var skin := Color(0.30, 0.55, 0.22)    # zielona skóra
	var skin_d := Color(0.22, 0.42, 0.16)  # ciemniejsza (kończyny/uszy)
	var eyes := Color(1.00, 0.85, 0.10)    # świecące żółte oczy
	var mouth := Color(0.10, 0.06, 0.05)   # paszcza
	var loin := Color(0.35, 0.24, 0.14)    # przepaska brązowa
	# Akcent emisyjny (rdzeń bruta / kula slingera) — domyślnie pochodna oczu, by element pasował.
	var accent := Color(1.00, 0.70, 0.15)
	# ETAP 4: reskin biomowy (ognisty/lodowy). a>0 => nadpisz paletę; skin_d = przyciemniona skóra.
	if skin_tint.a > 0.0:
		skin = Color(skin_tint.r, skin_tint.g, skin_tint.b)
		skin_d = skin.darkened(0.28)
	if eye_tint.a > 0.0:
		eyes = Color(eye_tint.r, eye_tint.g, eye_tint.b)
		accent = eyes
	return [skin, skin_d, eyes, mouth, loin, accent]

func _build_voxel_enemy() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	# ETAP 4: skala ciała wariantu (Brute = krępy/większy elite). Pivoty/animacja niezmienione
	# (dziedziczą skalę), kapsuła kolizji zostaje — większy model nie psuje chodu po terenie.
	if body_scale != 1.0:
		_model.scale = Vector3.ONE * body_scale
	match _enemy_kind():
		&"brute":
			_build_silhouette_brute()
		&"slinger":
			_build_silhouette_slinger()
		&"beast":
			_build_silhouette_beast()
		&"spider":
			_build_silhouette_spider()
		&"scorpion":
			_build_silhouette_scorpion()
		&"serpent":
			_build_silhouette_serpent()
		&"frog":
			_build_silhouette_frog()
		&"treant":
			_build_silhouette_treant()
		&"golem":
			_build_silhouette_golem()
		&"wyvern":
			_build_silhouette_wyvern()
		&"spirit":
			_build_silhouette_spirit()
		&"worm":
			_build_silhouette_worm()
		_:
			_build_silhouette_goblin()
	# FAZA 5: ROAMING ELITE — emisyjna AURA (OmniLight pulsujacy) czytelna z daleka jako "cel". Kolor
	# wg elementu (ogien/mroz) lub zloty (neutralny). Tani: jedno swiatlo bez cieni + distance fade.
	if _is_roaming_elite:
		_build_elite_aura()
	# ART OVERHAUL: CZYTELNOŚĆ KLASY ZAGROŻENIA — elite/boss dostają PERSYSTENTNY, tani, co-op-safe
	# znacznik (emisyjny pierścień u stóp + unoszący się marker nad głową), by groźba czytała się
	# NATYCHMIAST z daleka, zanim padnie cios. Czysto wizualne (zero światła = brak kosztu always-on
	# lights; mesh emisyjny zamiast OmniLight), deterministyczne (te same dane na wszystkich klientach).
	if threat_tier == &"elite" or threat_tier == &"boss":
		_build_threat_marker()


# FAZA 5: aura roaming-elite — OmniLight3D pulsujacy nad torsem. Bez cieni (tanio), distance fade
# (daleki elite nie kosztuje). Kolor wg elementu wariantu. Pulsacja w _process (_elite_aura_phase).
func _build_elite_aura() -> void:
	if _elite_aura != null:
		return
	var col := Color(1.0, 0.78, 0.25)        # neutralny: zloty (krolewski "elite")
	if element == &"fire":
		col = Color(1.0, 0.45, 0.15)
	elif element == &"frost":
		col = Color(0.5, 0.8, 1.0)
	var l := OmniLight3D.new()
	l.name = "EliteAura"
	l.light_color = col
	l.light_energy = ELITE_AURA_BASE_ENERGY
	l.omni_range = ELITE_AURA_RANGE
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 40.0
	l.distance_fade_length = 12.0
	l.position = Vector3(0.0, 1.1, 0.0)
	add_child(l)
	_elite_aura = l

# ART OVERHAUL: kolor klasy zagrożenia. Element ma priorytet (ognisty elite świeci pomarańczem,
# lodowy błękitem); inaczej tier: elite=bursztyn (mini-cel), boss=czerwień (śmiertelne zagrożenie).
func _threat_tint() -> Color:
	if element == &"fire":
		return Color(1.0, 0.5, 0.18)
	if element == &"frost":
		return Color(0.45, 0.78, 1.0)
	if element == &"poison":
		return Color(0.55, 1.0, 0.4)
	if threat_tier == &"boss":
		return Color(1.0, 0.22, 0.16)        # boss: groźna czerwień
	return Color(1.0, 0.72, 0.2)             # elite: królewski bursztyn

# ART OVERHAUL: PERSYSTENTNY ZNACZNIK KLASY ZAGROŻENIA (elite/boss). Dwie czytelne z daleka rzeczy,
# obie CZYSTO EMISYJNE (zero świateł — nie obciąża budżetu always-on lights z Art Bible):
#   1) PIERŚCIEŃ U STÓP — wieniec niskich emisyjnych kostek na ziemi (radialnie wokół wroga). Statyczny
#      (część _model), natychmiast komunikuje "to nie zwykły trash".
#   2) UNOSZĄCY SIĘ MARKER nad głową — diament (elite) lub korona z 3 kolców (boss). Bobuje/pulsuje w
#      _process (_threat_marker_phase). Wysokość markera zależna od sylwetki (czworonóg jest niski).
# Wszystko deterministyczne (te same dane → identyczny wygląd na każdym kliencie; co-op-safe, zero RNG).
func _build_threat_marker() -> void:
	if _threat_marker != null or _model == null:
		return
	var col := _threat_tint()
	var is_boss := threat_tier == &"boss"

	# 1) PIERŚCIEŃ U STÓP — wieniec emisyjnych kostek na poziomie ziemi (y≈0.04, w lokalu _model).
	var ring_r := 0.62 if not is_boss else 0.80
	var seg := 10 if not is_boss else 12
	for i in seg:
		var a := TAU * float(i) / float(seg)
		var px := cos(a) * ring_r
		var pz := sin(a) * ring_r
		_cube(_model, Vector3(0.12, 0.05, 0.12), Vector3(px, 0.04, pz), col, true)

	# 2) UNOSZĄCY SIĘ MARKER — osobny węzeł nad głową (bob/pulsacja w _process). Wysokość wg sylwetki:
	#    czworonóg jest niski (grzbiet ~0.85), humanoid wysoki (głowa ~1.7).
	var top_y := 1.25 if _is_beast else 2.05
	var m := Node3D.new()
	m.name = "ThreatMarker"
	m.position = Vector3(0.0, top_y, 0.0)
	_model.add_child(m)
	if is_boss:
		# BOSS: korona z 3 kolców (środkowy wyższy) — sylwetka "władcy lochu".
		_cube(m, Vector3(0.10, 0.30, 0.10), Vector3(0.0, 0.0, 0.0), col, true)
		_cube(m, Vector3(0.09, 0.20, 0.09), Vector3(-0.16, -0.04, 0.0), col, true)
		_cube(m, Vector3(0.09, 0.20, 0.09), Vector3(0.16, -0.04, 0.0), col, true)
	else:
		# ELITE: diament (kostka obrócona o 45° wokół Z i Y → romb czytelny z każdej strony).
		var dm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.22, 0.22)
		dm.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 1.0
		mat.metallic = 0.0
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 2.2
		dm.material_override = mat
		dm.rotation = Vector3(0.0, deg_to_rad(45.0), deg_to_rad(45.0))
		m.add_child(dm)
	_threat_marker = m

# Bazowa wysokość markera zagrożenia (wokół niej bobuje w _process). Czworonóg niski → marker niżej.
func _threat_marker_base_y() -> float:
	return 1.25 if _is_beast else 2.05

# --- GOBLIN — krępy, duża głowa, długie szpony (sylwetka bazowa, szybki trash) ---
func _build_silhouette_goblin() -> void:
	var pal := _variant_palette()
	var skin: Color = pal[0]; var skin_d: Color = pal[1]; var eyes: Color = pal[2]
	var mouth: Color = pal[3]; var loin: Color = pal[4]

	# --- Tułów (krępy) + przepaska — statyczne ---
	_cube(_model, Vector3(0.56, 0.46, 0.36), Vector3(0.0, 0.78, 0.0), skin)
	_cube(_model, Vector3(0.58, 0.12, 0.38), Vector3(0.0, 0.56, 0.0), loin)

	# --- Głowa (duża) + uszy + oczy (świecące) + paszcza ---
	_cube(_model, Vector3(0.62, 0.56, 0.56), Vector3(0.0, 1.30, 0.0), skin)
	_cube(_model, Vector3(0.12, 0.26, 0.10), Vector3(-0.36, 1.42, 0.0), skin_d)  # ucho L
	_cube(_model, Vector3(0.12, 0.26, 0.10), Vector3(0.36, 1.42, 0.0), skin_d)   # ucho R
	_cube(_model, Vector3(0.13, 0.10, 0.05), Vector3(-0.14, 1.34, -0.29), eyes, true)  # oko L (przód = -Z)
	_cube(_model, Vector3(0.13, 0.10, 0.05), Vector3(0.14, 1.34, -0.29), eyes, true)   # oko R
	_cube(_model, Vector3(0.34, 0.08, 0.05), Vector3(0.0, 1.14, -0.29), mouth)   # paszcza

	# --- Nogi: pivoty w biodrach y=0.56; krótkie, stopy ~y=0 ---
	_leg_l = _make_pivot(_model, Vector3(-0.16, 0.56, 0.0))
	_leg_r = _make_pivot(_model, Vector3(0.16, 0.56, 0.0))
	for leg in [_leg_l, _leg_r]:
		_cube(leg, Vector3(0.22, 0.46, 0.24), Vector3(0.0, -0.28, 0.0), skin_d)

	# --- Ręce: pivoty w barkach y=0.98; długie szpony ---
	_arm_l = _make_pivot(_model, Vector3(-0.36, 0.98, 0.0))
	_arm_r = _make_pivot(_model, Vector3(0.36, 0.98, 0.0))
	for arm in [_arm_l, _arm_r]:
		_cube(arm, Vector3(0.18, 0.50, 0.20), Vector3(0.0, -0.25, 0.0), skin)     # ramię
		_cube(arm, Vector3(0.20, 0.14, 0.22), Vector3(0.0, -0.55, 0.0), skin_d)   # dłoń/szpon

# --- BRUTE — masywny, zgarbiony, OGROMNE bary, mała głowa wciśnięta w kark, świecący rdzeń + maczuga.
# Sylwetka "ściana mięśni" czytelna z daleka: szeroki górny trójkąt, krótkie nogi, broń w prawej dłoni.
func _build_silhouette_brute() -> void:
	var pal := _variant_palette()
	var skin: Color = pal[0]; var skin_d: Color = pal[1]; var eyes: Color = pal[2]
	var mouth: Color = pal[3]; var accent: Color = pal[5]

	# Tułów SZEROKI i głęboki (beczka klatki) + masywne bary jako osobny blok (trójkątna sylwetka góry).
	_cube(_model, Vector3(0.82, 0.52, 0.52), Vector3(0.0, 0.80, 0.0), skin)        # klatka
	_cube(_model, Vector3(1.02, 0.26, 0.56), Vector3(0.0, 1.06, 0.0), skin_d)      # naramienny wał (bary)
	# ŚWIECĄCY RDZEŃ na piersi (czytelny akcent elity z daleka — "serce mocy").
	_cube(_model, Vector3(0.18, 0.18, 0.06), Vector3(0.0, 0.86, -0.27), accent, true)

	# Głowa MAŁA, wciśnięta nisko między bary (brak szyi) — kontrast z goblinem (duża głowa).
	_cube(_model, Vector3(0.40, 0.36, 0.40), Vector3(0.0, 1.34, 0.02), skin)
	_cube(_model, Vector3(0.10, 0.07, 0.05), Vector3(-0.10, 1.36, -0.21), eyes, true)  # oko L
	_cube(_model, Vector3(0.10, 0.07, 0.05), Vector3(0.10, 1.36, -0.21), eyes, true)   # oko R
	_cube(_model, Vector3(0.26, 0.06, 0.05), Vector3(0.0, 1.22, -0.21), mouth)         # zacięty pysk

	# Nogi KRÓTKIE i grube (przysadziste) — pivoty niżej, krok ciężki.
	_leg_l = _make_pivot(_model, Vector3(-0.22, 0.50, 0.0))
	_leg_r = _make_pivot(_model, Vector3(0.22, 0.50, 0.0))
	for leg in [_leg_l, _leg_r]:
		_cube(leg, Vector3(0.30, 0.46, 0.32), Vector3(0.0, -0.25, 0.0), skin_d)

	# Ręce DŁUGIE i grube, zwisające nisko (postawa goryla) — pivoty szeroko na barach.
	_arm_l = _make_pivot(_model, Vector3(-0.52, 1.02, 0.0))
	_arm_r = _make_pivot(_model, Vector3(0.52, 1.02, 0.0))
	for arm in [_arm_l, _arm_r]:
		_cube(arm, Vector3(0.26, 0.60, 0.28), Vector3(0.0, -0.30, 0.0), skin)       # potężne ramię
		_cube(arm, Vector3(0.30, 0.20, 0.32), Vector3(0.0, -0.66, 0.0), skin_d)     # wielka pięść
	# MACZUGA w prawej dłoni (trzon + głowica z emisyjnym okuciem) — czytelna groźba melee z daleka.
	_cube(_arm_r, Vector3(0.10, 0.46, 0.10), Vector3(0.0, -0.92, -0.04), Color(0.32, 0.22, 0.13))  # trzon
	_cube(_arm_r, Vector3(0.26, 0.24, 0.26), Vector3(0.0, -1.18, -0.04), Color(0.40, 0.40, 0.44))  # głowica
	_cube(_arm_r, Vector3(0.30, 0.06, 0.30), Vector3(0.0, -1.06, -0.04), accent, true)             # okucie świecące

# --- SLINGER — smukły, WYSOKI, w kapturze, świecąca KULA pocisku w lewej dłoni. Sylwetka "rzucacza":
# wąskie bary, długi tułów, broń-orb wyniesiona. Czytelny ranged-zagrożenie z daleka (inny niż melee).
func _build_silhouette_slinger() -> void:
	var pal := _variant_palette()
	var skin: Color = pal[0]; var skin_d: Color = pal[1]; var eyes: Color = pal[2]
	var accent: Color = pal[5]
	var hood := skin_d.darkened(0.18)   # kaptur ciemniejszy niż skóra (czytelna szata)

	# Tułów SMUKŁY i WYSOKI (wydłużony) + szata/peleryna kaptura.
	_cube(_model, Vector3(0.42, 0.62, 0.34), Vector3(0.0, 0.86, 0.0), skin)        # wąski długi tułów
	_cube(_model, Vector3(0.50, 0.30, 0.40), Vector3(0.0, 1.06, 0.04), hood)       # kołnierz szaty
	_cube(_model, Vector3(0.36, 0.10, 0.30), Vector3(0.0, 0.60, 0.0), hood)        # rąbek szaty

	# Głowa w KAPTURZE — czaszka + okap kaptura nad oczami; oczy świecą z cienia kaptura.
	_cube(_model, Vector3(0.40, 0.42, 0.40), Vector3(0.0, 1.42, 0.0), skin)        # głowa
	_cube(_model, Vector3(0.46, 0.20, 0.46), Vector3(0.0, 1.60, 0.0), hood)        # czubek kaptura
	_cube(_model, Vector3(0.46, 0.10, 0.10), Vector3(0.0, 1.46, -0.20), hood)      # okap nad oczami
	_cube(_model, Vector3(0.09, 0.06, 0.05), Vector3(-0.10, 1.40, -0.21), eyes, true)  # oko L (świeci z cienia)
	_cube(_model, Vector3(0.09, 0.06, 0.05), Vector3(0.10, 1.40, -0.21), eyes, true)   # oko R

	# Nogi DŁUGIE i smukłe (wysoka postawa) — pivoty wyżej, wąski rozstaw.
	_leg_l = _make_pivot(_model, Vector3(-0.12, 0.60, 0.0))
	_leg_r = _make_pivot(_model, Vector3(0.12, 0.60, 0.0))
	for leg in [_leg_l, _leg_r]:
		_cube(leg, Vector3(0.16, 0.58, 0.20), Vector3(0.0, -0.30, 0.0), skin_d)

	# Ręce smukłe — pivoty wąsko. Prawa "rzucająca" w przód.
	_arm_l = _make_pivot(_model, Vector3(-0.28, 1.04, 0.0))
	_arm_r = _make_pivot(_model, Vector3(0.28, 1.04, 0.0))
	for arm in [_arm_l, _arm_r]:
		_cube(arm, Vector3(0.14, 0.52, 0.16), Vector3(0.0, -0.26, 0.0), skin)       # chude ramię
		_cube(arm, Vector3(0.16, 0.12, 0.18), Vector3(0.0, -0.54, 0.0), skin_d)     # dłoń
	# ŚWIECĄCA KULA POCISKU w lewej dłoni (uniesiona, gotowa do rzutu) — emisyjny akcent ranged.
	_cube(_arm_l, Vector3(0.22, 0.22, 0.22), Vector3(0.0, -0.64, -0.06), accent, true)

# --- BEAST — POZIOMY CZWORONÓG (dzik/jeleń/wilk/kozioł...). BUGFIX: te warianty renderowały się jako
# pionowy humanoid (goblin). Teraz: wydłużony TUŁÓW wzdłuż osi patrzenia (przód = -Z), GŁOWA/PYSK z przodu,
# 4 NOGI. Mapowanie pivotów pod ISTNIEJĄCY rig (zero nowego systemu animacji):
#   _arm_l/_arm_r = przednia para nóg (pivoty z PRZODU, przy -Z)
#   _leg_l/_leg_r = tylna para nóg   (pivoty z TYŁU, przy +Z)
# Chód (_process) daje wtedy KŁUS DIAGONALNY: w ścieżce chodu _arm_l = +swing, _leg_l = -swing → przód i
# tył tej samej strony są o π w przeciwfazie; a _arm_l/_arm_r oraz _leg_l/_leg_r są wzajemnie w opozycji →
# para FL+BR i FR+BL pracuje razem (poprawny trucht zwierzęcia). Nogi obracają się na X (przód/tył wzdłuż
# -Z), więc wymach jest zgodny z kierunkiem ruchu. Sylwetka pozioma czyta się z daleka jako ZWIERZĘ.
func _build_silhouette_beast() -> void:
	_is_beast = true
	var pal := _variant_palette()
	var skin: Color = pal[0]; var skin_d: Color = pal[1]; var eyes: Color = pal[2]
	var mouth: Color = pal[3]

	# --- TUŁÓW POZIOMY: wydłużony wzdłuż Z (głębokość > szerokość/wysokość). Niski grzbiet ~y=0.62. ---
	_cube(_model, Vector3(0.44, 0.40, 0.86), Vector3(0.0, 0.62, 0.06), skin)        # główny korpus
	_cube(_model, Vector3(0.40, 0.30, 0.30), Vector3(0.0, 0.66, -0.30), skin)       # bark/kłąb (przód masywniejszy)
	_cube(_model, Vector3(0.34, 0.26, 0.26), Vector3(0.0, 0.60, 0.42), skin_d)      # zad (tył węższy, ciemniejszy)

	# --- SZYJA + GŁOWA/PYSK z przodu (-Z), pochylone nisko (sylwetka pasącego się/szarżującego zwierza). ---
	_cube(_model, Vector3(0.24, 0.24, 0.26), Vector3(0.0, 0.60, -0.52), skin)       # szyja
	_cube(_model, Vector3(0.30, 0.28, 0.34), Vector3(0.0, 0.54, -0.74), skin)       # głowa
	_cube(_model, Vector3(0.18, 0.16, 0.22), Vector3(0.0, 0.48, -0.94), skin_d)     # pysk/ryj
	_cube(_model, Vector3(0.16, 0.06, 0.05), Vector3(0.0, 0.44, -1.04), mouth)      # nozdrza/morda
	# Uszy (sterczą do góry-tyłu) — pomagają sylwetce głowy zwierzęcia.
	_cube(_model, Vector3(0.08, 0.16, 0.08), Vector3(-0.12, 0.70, -0.66), skin_d)   # ucho L
	_cube(_model, Vector3(0.08, 0.16, 0.08), Vector3(0.12, 0.70, -0.66), skin_d)    # ucho R
	# Oczy po BOKACH głowy (zwierzęce, świecące — czytelne z daleka).
	_cube(_model, Vector3(0.05, 0.08, 0.10), Vector3(-0.16, 0.58, -0.74), eyes, true)  # oko L
	_cube(_model, Vector3(0.05, 0.08, 0.10), Vector3(0.16, 0.58, -0.74), eyes, true)   # oko R

	# --- OGON z tyłu (+Z) — drobny akcent sylwetki. ---
	_cube(_model, Vector3(0.08, 0.10, 0.20), Vector3(0.0, 0.62, 0.58), skin_d)

	# --- 4 NOGI: pivoty na wysokości brzucha (y=0.46), nogi zwisają w dół. Przód z -Z, tył z +Z. ---
	# PRZEDNIA para = _arm_l/_arm_r (ścieżka "ramion" w _process je animuje). Pivoty przy barku (-Z).
	_arm_l = _make_pivot(_model, Vector3(-0.16, 0.46, -0.28))
	_arm_r = _make_pivot(_model, Vector3(0.16, 0.46, -0.28))
	# TYLNA para = _leg_l/_leg_r (ścieżka "nóg"). Pivoty przy zadzie (+Z).
	_leg_l = _make_pivot(_model, Vector3(-0.15, 0.46, 0.34))
	_leg_r = _make_pivot(_model, Vector3(0.15, 0.46, 0.34))
	for leg in [_arm_l, _arm_r, _leg_l, _leg_r]:
		_cube(leg, Vector3(0.16, 0.46, 0.18), Vector3(0.0, -0.23, 0.0), skin_d)     # noga
		_cube(leg, Vector3(0.17, 0.10, 0.20), Vector3(0.0, -0.44, 0.0), mouth)      # kopyto/łapa (ciemna)


# ============================================================================
#  ART OVERHAUL — ROSTER STWORÓW (9 sylwetek): spider/scorpion/serpent/frog/treant/golem/wyvern/spirit/worm.
#  Każdy ustawia _arm_l/_arm_r/_leg_l/_leg_r (kontrakt animacji _process). Wywern/żywiołak: _is_floating.
# ============================================================================


# --- SPIDER — niski, SZEROKI pełzacz (lodowe/bagienne pająki). Sylwetka: bulwiasty ODWŁOK z tyłu (+Z),
# mniejszy GŁOWOTUŁÓW z przodu (-Z), 8 RADIALNYCH nóg (zginają się w górę-potem-w-dół), klaster
# świecących oczu z przodu. Czyta się NATYCHMIAST jako pająk: pozioma, przysadzista, „pajęcza gwiazda" nóg.
# Mapowanie pivotów pod ISTNIEJĄCY rig (zero nowej animacji): przednia para nóg = _arm_l/_arm_r,
# środkowo-tylna para = _leg_l/_leg_r → ścieżka chodu daje DIAGONALNY skitter (FL+BR / FR+BL w przeciwfazie).
# Pozostałe 4 nogi STATYCZNE (wprost na _model). _is_beast=true: niski znacznik zagrożenia + szarżowy
# wymach przedniej pary zamiast humanoidalnego „ciosu ręką" (pasuje do drapieżnego rzutu pająka).
func _build_silhouette_spider() -> void:
	_is_beast = true
	var pal := _variant_palette()
	var skin: Color = pal[0]; var skin_d: Color = pal[1]; var eyes: Color = pal[2]
	var mouth: Color = pal[3]

	# --- ODWŁOK: duży, BULWIASTY, niesiony z tyłu (+Z) i lekko uniesiony — dominanta sylwetki. ---
	_cube(_model, Vector3(0.62, 0.50, 0.66), Vector3(0.0, 0.50, 0.34), skin)        # bulwa odwłoka
	_cube(_model, Vector3(0.50, 0.36, 0.30), Vector3(0.0, 0.58, 0.66), skin_d)      # tylny garb odwłoka
	# Świecące znamię na grzbiecie odwłoka (akcent „jadowitego/lodowego" pająka, czytelny z góry/z daleka).
	_cube(_model, Vector3(0.14, 0.06, 0.22), Vector3(0.0, 0.76, 0.40), eyes, true)

	# --- GŁOWOTUŁÓW: mniejszy, niżej, z PRZODU (-Z) — łączy odwłok z głową/nogami. ---
	_cube(_model, Vector3(0.42, 0.30, 0.40), Vector3(0.0, 0.40, -0.18), skin)       # głowotułów
	# Szczękoczułki/kły z przodu (ciemne) — drapieżny pysk pająka.
	_cube(_model, Vector3(0.10, 0.12, 0.10), Vector3(-0.09, 0.30, -0.42), mouth)    # kieł L
	_cube(_model, Vector3(0.10, 0.12, 0.10), Vector3(0.09, 0.30, -0.42), mouth)     # kieł R

	# --- KLASTER ŚWIECĄCYCH OCZU z przodu (-Z): 4 oka (2 duże + 2 małe) — pajęcza „twarz" z daleka. ---
	_cube(_model, Vector3(0.10, 0.09, 0.05), Vector3(-0.11, 0.46, -0.38), eyes, true)  # duże oko L
	_cube(_model, Vector3(0.10, 0.09, 0.05), Vector3(0.11, 0.46, -0.38), eyes, true)   # duże oko R
	_cube(_model, Vector3(0.06, 0.06, 0.05), Vector3(-0.05, 0.52, -0.38), eyes, true)  # małe oko L
	_cube(_model, Vector3(0.06, 0.06, 0.05), Vector3(0.05, 0.52, -0.38), eyes, true)   # małe oko R

	# --- 4 ANIMOWANE NOGI (skitter). Każda: udo (skos w GÓRĘ-na zewnątrz) + goleń (w DÓŁ do stopy ~y=0).
	#     Pivoty na wysokości głowotułowia (y=0.42), rozstawione radialnie. Obrót na X = pełzanie. ---
	# PRZEDNIA para = _arm_l/_arm_r (pivoty z przodu, -Z).
	_arm_l = _make_pivot(_model, Vector3(-0.26, 0.42, -0.12))
	_arm_r = _make_pivot(_model, Vector3(0.26, 0.42, -0.12))
	# ŚRODKOWO-TYLNA para = _leg_l/_leg_r (pivoty z tyłu, +Z).
	_leg_l = _make_pivot(_model, Vector3(-0.26, 0.42, 0.16))
	_leg_r = _make_pivot(_model, Vector3(0.26, 0.42, 0.16))
	# Lewe nogi wychylone w lewo (-x), prawe w prawo (+x); zgięcie „kolanowe" w górę, potem goleń w dół.
	var anim_legs := [
		[_arm_l, -1.0, -0.30],   # przednia L: w lewo i lekko do przodu
		[_arm_r,  1.0, -0.30],   # przednia R
		[_leg_l, -1.0,  0.20],   # tylna L: w lewo i lekko do tyłu
		[_leg_r,  1.0,  0.20],   # tylna R
	]
	for entry in anim_legs:
		var leg: Node3D = entry[0]
		var sx: float = entry[1]
		var sz: float = entry[2]
		# udo: unosi się w GÓRĘ i na zewnątrz (pajęczy „łuk" stawu).
		_cube(leg, Vector3(0.30, 0.10, 0.10), Vector3(sx * 0.18, 0.10, sz), skin_d)
		# goleń: opada w DÓŁ do stopy przy ziemi.
		_cube(leg, Vector3(0.09, 0.34, 0.09), Vector3(sx * 0.34, -0.18, sz), skin_d)
		# stopa (ciemny czubek dotykający ziemi).
		_cube(leg, Vector3(0.10, 0.08, 0.10), Vector3(sx * 0.36, -0.38, sz), mouth)

	# --- 4 STATYCZNE NOGI (wprost na _model, bez pivota): druga przednia i druga tylna para,
	#     przesunięte w Z, by 8 nóg tworzyło pełną pajęczą „gwiazdę". Ta sama geometria łuku. ---
	var static_legs := [
		[-1.0, -0.40],  # przednia-zewn. L
		[ 1.0, -0.40],  # przednia-zewn. R
		[-1.0,  0.42],  # tylna-zewn. L
		[ 1.0,  0.42],  # tylna-zewn. R
	]
	for s in static_legs:
		var sx: float = s[0]
		var sz: float = s[1]
		# udo (w górę-na zewnątrz) — barki nóg na wysokości stawu y≈0.52.
		_cube(_model, Vector3(0.30, 0.10, 0.10), Vector3(sx * 0.36, 0.52, sz), skin_d)
		# goleń (w dół do ziemi).
		_cube(_model, Vector3(0.09, 0.34, 0.09), Vector3(sx * 0.52, 0.24, sz), skin_d)
		# stopa.
		_cube(_model, Vector3(0.10, 0.08, 0.10), Vector3(sx * 0.54, 0.04, sz), mouth)


# --- SCORPION — niski, OPANCERZONY, POZIOMY drapieżnik pustyni. Sylwetka czyta się NATYCHMIAST:
# płaski segmentowany odwłok, DWIE wielkie przednie SZCZYPCE (pincery) wyniesione do przodu, oraz
# SEGMENTOWANY OGON wygięty w łuk nad grzbietem zakończony ŚWIECĄCYM ŻĄDŁEM. Mapowanie pivotów pod
# istniejący rig (zero nowej animacji), tak jak BEAST:
#   _arm_l/_arm_r = przednie SZCZYPCE (ścieżka "ramion" je animuje — w ataku robią SZARŻOWY wymach
#                   do przodu przez gałąź _is_beast w _process; w chodzie lekko kołyszą jak para nóg)
#   _leg_l/_leg_r = animowana para nóg KROCZĄCYCH (trucht diagonalny jak u zwierzęcia)
# Dodatkowe nogi (środkowa + tylna para) są STATYCZNE — wypełniają sylwetkę wieloodnóża, bez ruchu.
# Sylwetka POZIOMA + uniesiony łuk ogona = jednoznaczny SKORPION, odróżnialny od goblin/brute/slinger/beast.
func _build_silhouette_scorpion() -> void:
	_is_beast = true  # niski poziomy potwór: gait diagonalny + niżej marker zagrożenia + szarżowy atak
	var pal := _variant_palette()
	var skin: Color = pal[0]; var skin_d: Color = pal[1]; var eyes: Color = pal[2]
	var mouth: Color = pal[3]; var accent: Color = pal[5]

	# --- ODWŁOK/CEFALOTORAKS: płaski, segmentowany, wydłużony wzdłuż Z. Niski grzbiet ~y=0.30. ---
	_cube(_model, Vector3(0.50, 0.24, 0.46), Vector3(0.0, 0.30, -0.30), skin)        # głowotułów (przód, szerszy)
	_cube(_model, Vector3(0.44, 0.22, 0.30), Vector3(0.0, 0.30, 0.04), skin_d)       # segment odwłoka 1
	_cube(_model, Vector3(0.38, 0.20, 0.26), Vector3(0.0, 0.30, 0.32), skin)         # segment odwłoka 2
	_cube(_model, Vector3(0.30, 0.18, 0.22), Vector3(0.0, 0.30, 0.56), skin_d)       # segment odwłoka 3 (zwęża się)
	# Oczy świecące na przedzie głowotułowia (drapieżny akcent czytelny z daleka).
	_cube(_model, Vector3(0.07, 0.07, 0.05), Vector3(-0.12, 0.38, -0.52), eyes, true)  # oko L
	_cube(_model, Vector3(0.07, 0.07, 0.05), Vector3(0.12, 0.38, -0.52), eyes, true)   # oko R

	# --- OGON: SEGMENTOWANY ŁUK wznoszący się od zadu (+Z) w górę i wracający do przodu nad grzbietem,
	#     zakończony ŻĄDŁEM ze ŚWIECĄCYM rdzeniem jadu. Czysto statyczny, ale to DOMINANTA sylwetki. ---
	_cube(_model, Vector3(0.18, 0.18, 0.18), Vector3(0.0, 0.44, 0.66), skin_d)       # nasada ogona (wznosi się)
	_cube(_model, Vector3(0.16, 0.18, 0.16), Vector3(0.0, 0.66, 0.70), skin)         # segment 1
	_cube(_model, Vector3(0.15, 0.18, 0.15), Vector3(0.0, 0.88, 0.64), skin_d)       # segment 2
	_cube(_model, Vector3(0.14, 0.16, 0.14), Vector3(0.0, 1.06, 0.48), skin)         # segment 3 (łuk nad grzbietem)
	_cube(_model, Vector3(0.13, 0.16, 0.13), Vector3(0.0, 1.16, 0.26), skin_d)       # segment 4 (przegina do przodu)
	_cube(_model, Vector3(0.12, 0.14, 0.12), Vector3(0.0, 1.16, 0.04), skin)         # segment 5
	_cube(_model, Vector3(0.13, 0.13, 0.13), Vector3(0.0, 1.10, -0.16), mouth)       # bańka jadowa (ciemna)
	_cube(_model, Vector3(0.07, 0.20, 0.07), Vector3(0.0, 0.96, -0.26), accent, true)  # ŻĄDŁO świecące (kolec w dół-przód)

	# --- PRZEDNIE SZCZYPCE = _arm_l/_arm_r. Pivoty przy przodzie głowotułowia (-Z), wyniesione do przodu.
	#     Ramię odnóża + klejnotowate PINCERY (dwie szczęki) — wielkie, groźne, czytelne. Animowane: w
	#     ataku robią szarżowy wymach przez gałąź _is_beast; w chodzie lekko kołyszą się. ---
	_arm_l = _make_pivot(_model, Vector3(-0.28, 0.30, -0.46))
	_arm_r = _make_pivot(_model, Vector3(0.28, 0.30, -0.46))
	for arm in [_arm_l, _arm_r]:
		_cube(arm, Vector3(0.14, 0.13, 0.34), Vector3(0.0, 0.0, -0.18), skin_d)      # przedramię szczypiec (do przodu)
		_cube(arm, Vector3(0.26, 0.18, 0.20), Vector3(0.0, 0.0, -0.40), skin)        # dłoń/klejnot szczypiec
		_cube(arm, Vector3(0.08, 0.10, 0.22), Vector3(-0.08, 0.04, -0.58), skin_d)   # szczęka górna pincera
		_cube(arm, Vector3(0.08, 0.10, 0.22), Vector3(0.06, -0.04, -0.58), skin_d)   # szczęka dolna pincera

	# --- KROCZĄCA para nóg (animowana) = _leg_l/_leg_r. Środek tułowia, zwisają na boki-w dół. ---
	_leg_l = _make_pivot(_model, Vector3(-0.24, 0.30, 0.0))
	_leg_r = _make_pivot(_model, Vector3(0.24, 0.30, 0.0))
	for leg in [_leg_l, _leg_r]:
		_cube(leg, Vector3(0.30, 0.07, 0.08), Vector3(-0.14, -0.02, 0.0), skin_d)    # udo (wystaje na bok)
		_cube(leg, Vector3(0.07, 0.26, 0.07), Vector3(-0.26, -0.16, 0.0), mouth)     # goleń (w dół do ziemi)
	# Lustro dla prawej (pivot odbity automatycznie przez X, więc dodajemy drugie odnóże po przeciwnej stronie).
	# Uwaga: _leg_l ma odnóże w -X, _leg_r też w -X względem własnego pivota → wizualnie L sięga w lewo,
	# R sięga „do środka". By obie szły NA ZEWNĄTRZ, dokładamy lustrzane odnóże na prawym pivocie:
	_cube(_leg_r, Vector3(0.30, 0.07, 0.08), Vector3(0.28, -0.02, 0.0), skin_d)      # udo prawe (na zewnątrz, +X)
	_cube(_leg_r, Vector3(0.07, 0.26, 0.07), Vector3(0.40, -0.16, 0.0), mouth)       # goleń prawa
	_cube(_leg_l, Vector3(0.30, 0.07, 0.08), Vector3(-0.16, -0.02, 0.0), skin_d)     # (wzmocnienie L — spójna grubość)

	# --- STATYCZNE dodatkowe nogi (środkowa + tylna para) — wypełniają wieloodnóże, bez animacji. ---
	# Każda: udo wystające na bok + goleń do ziemi. Po obu stronach, na różnych z.
	for z in [0.24, 0.46]:
		for sx in [-1.0, 1.0]:
			_cube(_model, Vector3(0.28, 0.07, 0.08), Vector3(sx * 0.30, 0.28, z), skin_d)   # udo
			_cube(_model, Vector3(0.07, 0.24, 0.07), Vector3(sx * 0.42, 0.14, z), mouth)     # goleń
	# Przednia statyczna para (tuż za szczypcami) — dopełnia 8 odnóży skorpiona.
	for sx2 in [-1.0, 1.0]:
		_cube(_model, Vector3(0.26, 0.07, 0.08), Vector3(sx2 * 0.30, 0.28, -0.18), skin_d)   # udo
		_cube(_model, Vector3(0.07, 0.24, 0.07), Vector3(sx2 * 0.42, 0.14, -0.18), mouth)     # goleń


# --- SERPENT — bagienny WĄŻ. Brak nóg: gruby SERPENTYNOWY tułów ze złożonych segmentów wijących się
# nisko po ziemi w esicę (S-curve przez naprzemienny offset w X), z PRZODU (-Z) uniesiona GŁOWA/KAPTUR
# z świecącymi oczami + kłami. Sylwetka POZIOMA, falująca — czyta się NATYCHMIAST jako wąż, inna niż
# pionowe humanoidy (goblin/brute/slinger) i niż czworonóg (beast). Mapowanie pivotów pod ISTNIEJĄCY
# rig (zero nowej animacji): cztery pivoty = SEGMENTY-falowniki tułowia. W ścieżce chodu _arm_l=+swing,
# _arm_r=-swing, _leg_l=-swing, _leg_r=+swing → sąsiednie segmenty obracają się w przeciwfazie, więc
# wymach na X unosi/opuszcza kolejne garby ciała = SLITHER (przetaczająca się fala). Każdy segment ma
# geometrię wysuniętą do TYŁU (+Z) od swojego pivotu, by obrót.x czytelnie podnosił/opuszczał garb.
func _build_silhouette_serpent() -> void:
	var pal := _variant_palette()
	var skin: Color = pal[0]; var skin_d: Color = pal[1]; var eyes: Color = pal[2]
	var mouth: Color = pal[3]; var accent: Color = pal[5]
	var belly := skin_d.lightened(0.12)   # jaśniejszy brzuch — czytelny spód węża

	# --- ESICA TUŁOWIA: naprzemienny offset w X buduje statyczny kształt S, a pivoty dodają falę. ---
	# Niski grzbiet ~y=0.30 (gruby wąż leżący na ziemi). Przód = -Z.

	# Segment 1 (najbliżej głowy) = _arm_l. Pivot z przodu, geometria wysunięta do tyłu (+Z).
	_arm_l = _make_pivot(_model, Vector3(0.12, 0.30, -0.30))
	_cube(_arm_l, Vector3(0.44, 0.42, 0.46), Vector3(-0.04, 0.0, 0.22), skin)
	_cube(_arm_l, Vector3(0.34, 0.10, 0.40), Vector3(-0.04, -0.18, 0.22), belly)   # brzuch

	# Segment 2 = _arm_r (przeciwny offset w X — wygięcie S).
	_arm_r = _make_pivot(_model, Vector3(-0.12, 0.30, 0.18))
	_cube(_arm_r, Vector3(0.42, 0.40, 0.46), Vector3(0.06, 0.0, 0.22), skin_d)
	_cube(_arm_r, Vector3(0.32, 0.10, 0.40), Vector3(0.06, -0.17, 0.22), belly)

	# Segment 3 = _leg_l (z powrotem w +X).
	_leg_l = _make_pivot(_model, Vector3(0.10, 0.30, 0.66))
	_cube(_leg_l, Vector3(0.36, 0.34, 0.44), Vector3(-0.06, 0.0, 0.20), skin)
	_cube(_leg_l, Vector3(0.26, 0.09, 0.38), Vector3(-0.06, -0.14, 0.20), belly)

	# Segment 4 = _leg_r (ogon — zwęża się, lekki akcent w -X).
	_leg_r = _make_pivot(_model, Vector3(-0.06, 0.30, 1.10))
	_cube(_leg_r, Vector3(0.26, 0.26, 0.42), Vector3(0.03, 0.0, 0.18), skin_d)
	_cube(_leg_r, Vector3(0.14, 0.14, 0.34), Vector3(0.03, -0.02, 0.40), skin_d)   # czubek ogona
	_cube(_leg_r, Vector3(0.07, 0.10, 0.18), Vector3(0.03, 0.0, 0.58), accent, true) # świecący kolec ogona

	# --- SZYJA uniesiona + GŁOWA/KAPTUR z PRZODU (-Z) — statyczne (nie na pivocie, mocna sylwetka). ---
	_cube(_model, Vector3(0.30, 0.34, 0.30), Vector3(0.14, 0.46, -0.46), skin)      # szyja wznosząca się
	_cube(_model, Vector3(0.36, 0.40, 0.30), Vector3(0.10, 0.70, -0.62), skin)      # podstawa głowy uniesiona
	# KAPTUR kobry (rozłożysty kołnierz — natychmiast czyta się jako wąż) po bokach głowy.
	_cube(_model, Vector3(0.66, 0.30, 0.10), Vector3(0.10, 0.70, -0.52), skin_d)    # rozłożony kaptur
	# Pysk wysunięty do przodu (-Z).
	_cube(_model, Vector3(0.30, 0.24, 0.30), Vector3(0.10, 0.66, -0.84), skin)      # głowa/pysk
	_cube(_model, Vector3(0.22, 0.10, 0.14), Vector3(0.10, 0.58, -0.98), mouth)     # paszcza
	# KŁY (jasne, sterczące w dół z przodu paszczy).
	_cube(_model, Vector3(0.05, 0.12, 0.05), Vector3(0.03, 0.50, -0.96), belly)     # kieł L
	_cube(_model, Vector3(0.05, 0.12, 0.05), Vector3(0.17, 0.50, -0.96), belly)     # kieł R
	# OCZY świecące po bokach uniesionej głowy — czytelny groźny akcent z daleka.
	_cube(_model, Vector3(0.06, 0.10, 0.08), Vector3(-0.02, 0.72, -0.78), eyes, true)  # oko L
	_cube(_model, Vector3(0.06, 0.10, 0.08), Vector3(0.22, 0.72, -0.78), eyes, true)   # oko R


# --- FROG — TRUJĄCA ŻABA (bagno). Sylwetka NISKA i SZEROKA: przysadzisty, rozlany tułów tuż nad ziemią,
# OGROMNA linia paszczy przez cały przód, dwa wielkie WYBAŁUSZONE świecące oczy na czubku głowy, krótkie
# przednie łapki + potężne ZŁOŻONE tylne nogi gotowe do skoku. Brodawki w kolorze accent (toksyczny look).
# Mapowanie pivotów pod istniejący rig (zero nowego systemu animacji):
#   _arm_l/_arm_r = krótkie PRZEDNIE łapki (delikatny wymach X — "podpieranie się")
#   _leg_l/_leg_r = wielkie TYLNE nogi (wymach X czyta się jak napinanie/luz przed skokiem)
# Chód (_process) daje wtedy żywą, niską pulsację kończyn — żaba "drży" gotowa do hopu.
func _build_silhouette_frog() -> void:
	var pal := _variant_palette()
	var skin: Color = pal[0]; var skin_d: Color = pal[1]; var eyes: Color = pal[2]
	var mouth: Color = pal[3]; var accent: Color = pal[5]

	# --- TUŁÓW: bardzo SZEROKI i niski, lekko spłaszczony (rozlana ropuszla sylwetka tuż nad ziemią). ---
	_cube(_model, Vector3(0.92, 0.42, 0.66), Vector3(0.0, 0.30, 0.06), skin)         # główny korpus (szeroki)
	_cube(_model, Vector3(0.78, 0.20, 0.52), Vector3(0.0, 0.14, 0.04), skin_d)       # podbrzusze (ciemniejsze)
	# Brodawki/grzbiet trujący — emisyjne plamy accent rozsiane po grzbiecie (czytelny "toksyczny" znak).
	_cube(_model, Vector3(0.12, 0.08, 0.12), Vector3(-0.26, 0.50, 0.12), accent, true)  # brodawka L
	_cube(_model, Vector3(0.12, 0.08, 0.12), Vector3(0.26, 0.50, 0.12), accent, true)   # brodawka R
	_cube(_model, Vector3(0.10, 0.07, 0.10), Vector3(0.0, 0.52, 0.22), accent, true)    # brodawka środkowa-tył

	# --- GŁOWA: szeroka, zlana z tułowiem, wysunięta do przodu (-Z). OGROMNA linia paszczy przez cały przód. ---
	_cube(_model, Vector3(0.86, 0.34, 0.40), Vector3(0.0, 0.34, -0.36), skin)        # czoło/głowa (szeroka)
	_cube(_model, Vector3(0.84, 0.08, 0.06), Vector3(0.0, 0.22, -0.55), mouth)       # gigantyczna linia paszczy
	_cube(_model, Vector3(0.20, 0.06, 0.05), Vector3(-0.20, 0.27, -0.55), mouth)     # kącik paszczy L (uśmiech w górę)
	_cube(_model, Vector3(0.20, 0.06, 0.05), Vector3(0.20, 0.27, -0.55), mouth)      # kącik paszczy R

	# --- OCZY: dwa WIELKIE wybałuszone bąble na CZUBKU głowy (kopuły) + świecące źrenice. Sylwetka żaby. ---
	_cube(_model, Vector3(0.26, 0.26, 0.26), Vector3(-0.24, 0.58, -0.30), skin_d)    # gałka oczna L (bąbel)
	_cube(_model, Vector3(0.26, 0.26, 0.26), Vector3(0.24, 0.58, -0.30), skin_d)     # gałka oczna R (bąbel)
	_cube(_model, Vector3(0.14, 0.14, 0.10), Vector3(-0.24, 0.60, -0.42), eyes, true)  # świecąca źrenica L
	_cube(_model, Vector3(0.14, 0.14, 0.10), Vector3(0.24, 0.60, -0.42), eyes, true)   # świecąca źrenica R

	# --- PRZEDNIE łapki (krótkie) = _arm_l/_arm_r. Pivoty z przodu-boku, łapki wsparte o ziemię. ---
	_arm_l = _make_pivot(_model, Vector3(-0.34, 0.20, -0.26))
	_arm_r = _make_pivot(_model, Vector3(0.34, 0.20, -0.26))
	for arm in [_arm_l, _arm_r]:
		_cube(arm, Vector3(0.12, 0.20, 0.14), Vector3(0.0, -0.10, 0.0), skin_d)      # cienka łapka
		_cube(arm, Vector3(0.18, 0.06, 0.20), Vector3(0.0, -0.20, -0.04), skin_d)    # rozłożysta dłoń (palce)

	# --- TYLNE nogi (wielkie, ZŁOŻONE w "Z" — gotowe do skoku) = _leg_l/_leg_r. Pivoty z tyłu-boku, wysoko. ---
	_leg_l = _make_pivot(_model, Vector3(-0.42, 0.34, 0.28))
	_leg_r = _make_pivot(_model, Vector3(0.42, 0.34, 0.28))
	for leg in [_leg_l, _leg_r]:
		_cube(leg, Vector3(0.22, 0.26, 0.30), Vector3(0.0, 0.02, 0.10), skin)        # masywne udo (wystaje w górę-tył)
		_cube(leg, Vector3(0.16, 0.30, 0.16), Vector3(0.0, -0.18, 0.04), skin_d)     # podudzie (w dół)
		_cube(leg, Vector3(0.26, 0.06, 0.32), Vector3(0.0, -0.32, -0.06), skin_d)    # wielka błoniasta stopa (przód)


# --- TREANT — WYSOKIE drzewo-istota (forest). Najwyższa sylwetka w grze: gruby pień-tułów z korą
# (warstwy lekko poprzesuwanych kostek), korzeniowe stopy, dwie długie GAŁĘZIOWE ręce z gałązkowymi
# palcami, mały mszysty/liściasty czubek i ŚWIECĄCE oczy w wydrążonej twarzy. Rooted, wolny, górujący.
# Mapowanie pivotów pod istniejący rig (zero nowej animacji): _arm_l/_arm_r = dwie konarowe ręce (kołyszą
# się/zadają cios); _leg_l/_leg_r = korzeniowe "stopy" (delikatne kołysanie korzeni przy ruchu).
func _build_silhouette_treant() -> void:
	var pal := _variant_palette()
	var skin: Color = pal[0]; var skin_d: Color = pal[1]; var eyes: Color = pal[2]
	var mouth: Color = pal[3]; var accent: Color = pal[5]
	# Kora: ciemnobrązowe drewno niezależne od zielonej skóry wariantu (chyba że reskin biomowy nadpisze).
	var bark := Color(0.34, 0.24, 0.15)
	var bark_d := Color(0.24, 0.17, 0.10)
	var leaf := Color(0.22, 0.48, 0.18)     # liściasty/mszysty czubek (zieleń lasu)
	var leaf_d := Color(0.16, 0.36, 0.13)
	# Reskin biomowy (ogień/mróz): jeśli paleta wariantu nadpisana, ciągnij korę/liście za skórą wariantu.
	if skin_tint.a > 0.0:
		bark = skin_d
		bark_d = skin_d.darkened(0.30)
		leaf = skin
		leaf_d = skin.darkened(0.25)

	# --- PIEŃ-TUŁÓW: gruba, WYSOKA kolumna z warstw lekko poprzesuwanych kostek (faktura kory). ---
	_cube(_model, Vector3(0.62, 0.50, 0.56), Vector3(0.04, 0.42, 0.0), bark)        # podstawa pnia
	_cube(_model, Vector3(0.56, 0.46, 0.50), Vector3(-0.05, 0.86, 0.02), bark_d)    # środek (przesunięty L)
	_cube(_model, Vector3(0.52, 0.46, 0.48), Vector3(0.05, 1.28, -0.02), bark)      # górny (przesunięty R)
	_cube(_model, Vector3(0.48, 0.40, 0.44), Vector3(-0.03, 1.66, 0.0), bark_d)     # ramiona/kark pnia
	# Sęki/narośla kory (akcenty faktury, asymetryczne — żywe drewno).
	_cube(_model, Vector3(0.12, 0.16, 0.10), Vector3(0.34, 0.70, -0.20), bark_d)
	_cube(_model, Vector3(0.10, 0.14, 0.10), Vector3(-0.32, 1.14, -0.18), bark_d)

	# --- WYDRĄŻONA TWARZ w pniu (ciemna jama) + ŚWIECĄCE oczy + szczelina-usta. ---
	_cube(_model, Vector3(0.34, 0.30, 0.06), Vector3(0.0, 1.60, -0.26), mouth)         # jama twarzy
	_cube(_model, Vector3(0.10, 0.12, 0.06), Vector3(-0.11, 1.66, -0.30), eyes, true)  # oko L (świeci z jamy)
	_cube(_model, Vector3(0.10, 0.12, 0.06), Vector3(0.11, 1.66, -0.30), eyes, true)   # oko R
	_cube(_model, Vector3(0.22, 0.05, 0.06), Vector3(0.0, 1.48, -0.30), mouth)         # szczelina ust

	# --- MSZYSTY/LIŚCIASTY CZUBEK (korona) — bryła zieleni z drobnym świecącym akcentem (spory/poświata). ---
	_cube(_model, Vector3(0.60, 0.34, 0.56), Vector3(0.0, 1.98, 0.0), leaf)         # główna kępa
	_cube(_model, Vector3(0.40, 0.26, 0.40), Vector3(-0.18, 2.18, -0.10), leaf_d)   # kępa L
	_cube(_model, Vector3(0.38, 0.24, 0.38), Vector3(0.20, 2.16, 0.12), leaf_d)     # kępa R
	_cube(_model, Vector3(0.30, 0.22, 0.30), Vector3(0.0, 2.34, 0.0), leaf)         # czubek
	_cube(_model, Vector3(0.10, 0.10, 0.10), Vector3(0.12, 2.20, -0.18), accent, true)  # świecące spory/owoc

	# --- KORZENIOWE STOPY = _leg_l/_leg_r (pivoty u podstawy pnia; korzenie schodzą do ziemi). ---
	# Rooted: delikatne kołysanie korzeni przy ruchu (rotacja.x w _process daje "naprężanie" korzeni).
	_leg_l = _make_pivot(_model, Vector3(-0.22, 0.30, 0.0))
	_leg_r = _make_pivot(_model, Vector3(0.22, 0.30, 0.0))
	for leg in [_leg_l, _leg_r]:
		_cube(leg, Vector3(0.22, 0.34, 0.24), Vector3(0.0, -0.16, 0.0), bark)        # gruby korzeń
		_cube(leg, Vector3(0.30, 0.10, 0.34), Vector3(0.0, -0.32, 0.0), bark_d)      # rozłożysta stopa
		_cube(leg, Vector3(0.10, 0.08, 0.22), Vector3(0.0, -0.30, -0.22), bark_d)    # korzeń-palec do przodu (-Z)

	# --- GAŁĘZIOWE RĘCE = _arm_l/_arm_r (długie konary z gałązkowymi palcami; kołyszą się / zadają cios). ---
	# Pivoty wysoko na "barkach" pnia. Konary nieco rozłożyste (sylwetka rozkrzewionego drzewa).
	_arm_l = _make_pivot(_model, Vector3(-0.40, 1.56, 0.0))
	_arm_r = _make_pivot(_model, Vector3(0.40, 1.56, 0.0))
	# Lewa ręka — opadający konar.
	_cube(_arm_l, Vector3(0.18, 0.56, 0.18), Vector3(-0.10, -0.26, 0.0), bark)       # konar górny
	_cube(_arm_l, Vector3(0.15, 0.42, 0.15), Vector3(-0.20, -0.62, -0.04), bark_d)   # konar dolny (odgięty)
	_cube(_arm_l, Vector3(0.07, 0.18, 0.07), Vector3(-0.28, -0.86, -0.10), bark_d)   # gałązka-palec
	_cube(_arm_l, Vector3(0.06, 0.14, 0.06), Vector3(-0.14, -0.88, -0.06), bark_d)   # gałązka-palec
	_cube(_arm_l, Vector3(0.10, 0.10, 0.10), Vector3(-0.22, -0.66, -0.04), leaf_d)   # kępka liści na konarze
	# Prawa ręka — symetrycznie po prawej (lustro).
	_cube(_arm_r, Vector3(0.18, 0.56, 0.18), Vector3(0.10, -0.26, 0.0), bark)
	_cube(_arm_r, Vector3(0.15, 0.42, 0.15), Vector3(0.20, -0.62, -0.04), bark_d)
	_cube(_arm_r, Vector3(0.07, 0.18, 0.07), Vector3(0.28, -0.86, -0.10), bark_d)
	_cube(_arm_r, Vector3(0.06, 0.14, 0.06), Vector3(0.14, -0.88, -0.06), bark_d)
	_cube(_arm_r, Vector3(0.10, 0.10, 0.10), Vector3(0.22, -0.66, -0.04), leaf_d)


# --- GOLEM / STONE GIANT — najcięższa, najszersza sylwetka: monolityczny blok skały, OGROMNE głazowe
# bary i pięści (na _arm_l/_arm_r), krępe grube nogi (_leg_l/_leg_r), mała głowa wciśnięta między bary,
# świecący RDZEŃ + pęknięcia (emit) na piersi. Humanoid (NIE _is_beast): zamach unosi prawą pięść jak
# brute, więc głazowe dłonie czytają się jako ciężki cios melee. Mapowanie pivotów: ręce=bary z pięściami,
# nogi=stopy-kolumny. Wszystko deterministyczne (zero RNG, co-op-safe). Sylwetka woła "GŁAZ" z daleka.
func _build_silhouette_golem() -> void:
	var pal := _variant_palette()
	var skin: Color = pal[0]; var skin_d: Color = pal[1]; var eyes: Color = pal[2]
	var accent: Color = pal[5]
	# Kamienne odcienie pochodne palety (biom-reskin baked w pal): jaśniejszy "kant" + ciemna szczelina.
	var rock := skin
	var rock_d := skin_d
	var crack := accent                 # świecący rdzeń/pęknięcia (emisyjny akcent — "serce mocy")

	# --- MONOLITYCZNY TUŁÓW: bardzo szeroki i głęboki blok (najcięższa masa w grze). ---
	_cube(_model, Vector3(1.04, 0.78, 0.66), Vector3(0.0, 0.92, 0.0), rock)          # główny blok skały
	_cube(_model, Vector3(1.10, 0.16, 0.70), Vector3(0.0, 0.56, 0.0), rock_d)        # ciężka podstawa bioder
	# GŁAZOWE BARY jako osobny wał (skrajnie szeroka, kanciasta góra — sygnatura golema).
	_cube(_model, Vector3(1.34, 0.34, 0.74), Vector3(0.0, 1.34, 0.0), rock_d)        # naramienny wał
	# ŚWIECĄCY RDZEŃ + PĘKNIĘCIA na piersi (czytelny żar wewnątrz skały z daleka).
	_cube(_model, Vector3(0.26, 0.26, 0.08), Vector3(0.0, 1.00, -0.34), crack, true)     # rdzeń-serce
	_cube(_model, Vector3(0.07, 0.30, 0.06), Vector3(-0.22, 0.84, -0.34), crack, true)   # pęknięcie L
	_cube(_model, Vector3(0.07, 0.24, 0.06), Vector3(0.24, 1.12, -0.34), crack, true)    # pęknięcie R

	# --- GŁOWA MAŁA, wciśnięta nisko między bary (brak szyi) — głaz-czaszka, świecące oczy-szczeliny. ---
	_cube(_model, Vector3(0.42, 0.40, 0.42), Vector3(0.0, 1.62, 0.02), rock)
	_cube(_model, Vector3(0.10, 0.06, 0.05), Vector3(-0.11, 1.64, -0.22), eyes, true)    # oko L (szczelina)
	_cube(_model, Vector3(0.10, 0.06, 0.05), Vector3(0.11, 1.64, -0.22), eyes, true)     # oko R

	# --- NOGI: krótkie, GRUBE KOLUMNY skały (przysadzista, ciężka postawa). Pivoty nisko. ---
	_leg_l = _make_pivot(_model, Vector3(-0.30, 0.50, 0.0))
	_leg_r = _make_pivot(_model, Vector3(0.30, 0.50, 0.0))
	for leg in [_leg_l, _leg_r]:
		_cube(leg, Vector3(0.40, 0.46, 0.42), Vector3(0.0, -0.26, 0.0), rock_d)      # udo-kolumna
		_cube(leg, Vector3(0.46, 0.16, 0.50), Vector3(0.0, -0.50, 0.04), rock)       # ciężka stopa-głaz

	# --- RĘCE: OGROMNE głazowe ramiona zwisające nisko (postawa goryla) + olbrzymie PIĘŚCI-BOULDERY. ---
	_arm_l = _make_pivot(_model, Vector3(-0.70, 1.34, 0.0))
	_arm_r = _make_pivot(_model, Vector3(0.70, 1.34, 0.0))
	for arm in [_arm_l, _arm_r]:
		_cube(arm, Vector3(0.36, 0.66, 0.40), Vector3(0.0, -0.34, 0.0), rock)        # masywne ramię
		_cube(arm, Vector3(0.50, 0.46, 0.52), Vector3(0.0, -0.78, 0.0), rock_d)      # PIĘŚĆ-GŁAZ (bok)
		_cube(arm, Vector3(0.16, 0.16, 0.06), Vector3(0.0, -0.78, -0.27), crack, true)  # żarząca szczelina w pięści


# --- WYVERN — drapieżny LATAJĄCY gad gór. Sylwetka czytelna z daleka jako SKRZYDLATY ŁOWCA:
# lewitujące smukłe ciało wyniesione (~y1.2), długa SZYJA wygięta w przód + ROGATA głowa ze świecącymi
# oczami (-Z), dwa WIELKIE SKRZYDŁA rozłożone szeroko na _arm_l/_arm_r (rotation.x → trzepot/przechył),
# długi OGON z kolcem za sobą (+Z), dwie podkulone ŁAPY ze szponami na _leg_l/_leg_r. Floater: feet ~0.7+.
# Mapowanie pivotów pod ISTNIEJĄCY rig (zero nowego systemu animacji):
#   _arm_l/_arm_r = skrzydła (szeroko rozłożone → łagodny obrót na X czyta się jako MACHANIE/przechył),
#   _leg_l/_leg_r = podkulone łapy (delikatne kołysanie podczas lotu, krótki "szpon" przy szarży).
func _build_silhouette_wyvern() -> void:
	_is_floating = true
	var pal := _variant_palette()
	var skin: Color = pal[0]; var skin_d: Color = pal[1]; var eyes: Color = pal[2]
	var mouth: Color = pal[3]; var accent: Color = pal[5]

	# --- TUŁÓW LEWITUJĄCY: smukły, wyniesiony (środek ~y1.2). Pierś z przodu masywniejsza, biodra węższe. ---
	_cube(_model, Vector3(0.40, 0.40, 0.62), Vector3(0.0, 1.20, 0.06), skin)        # główny korpus
	_cube(_model, Vector3(0.44, 0.34, 0.30), Vector3(0.0, 1.22, -0.22), skin)       # pierś (przód, do -Z)
	_cube(_model, Vector3(0.30, 0.26, 0.26), Vector3(0.0, 1.16, 0.34), skin_d)      # biodra (tył, +Z)
	# ŚWIECĄCY RDZEŃ na piersi — drapieżny "puls mocy" elementu, czytelny akcent latawca z daleka.
	_cube(_model, Vector3(0.16, 0.16, 0.06), Vector3(0.0, 1.24, -0.36), accent, true)

	# --- SZYJA wygięta w PRZÓD-GÓRĘ + ROGATA GŁOWA (-Z). Predatorska sylwetka węża/smoka. ---
	_cube(_model, Vector3(0.20, 0.24, 0.22), Vector3(0.0, 1.34, -0.40), skin)       # szyja dolna
	_cube(_model, Vector3(0.18, 0.22, 0.20), Vector3(0.0, 1.52, -0.52), skin)       # szyja górna
	_cube(_model, Vector3(0.26, 0.26, 0.34), Vector3(0.0, 1.58, -0.70), skin)       # głowa
	_cube(_model, Vector3(0.16, 0.14, 0.22), Vector3(0.0, 1.50, -0.90), skin_d)     # pysk/szczęka
	_cube(_model, Vector3(0.14, 0.05, 0.05), Vector3(0.0, 1.46, -1.00), mouth)      # paszcza
	# Rogi (wygięte do tyłu-góry) — czytelna "rogata" głowa drapieżnika.
	_cube(_model, Vector3(0.06, 0.20, 0.06), Vector3(-0.10, 1.74, -0.62), skin_d)   # róg L
	_cube(_model, Vector3(0.06, 0.20, 0.06), Vector3(0.10, 1.74, -0.62), skin_d)    # róg R
	# Oczy świecące po bokach głowy (drapieżny wzrok, czytelny z daleka).
	_cube(_model, Vector3(0.05, 0.08, 0.07), Vector3(-0.14, 1.58, -0.78), eyes, true)  # oko L
	_cube(_model, Vector3(0.05, 0.08, 0.07), Vector3(0.14, 1.58, -0.78), eyes, true)   # oko R

	# --- OGON: długi, zwęża się ku tyłowi (+Z), zakończony emisyjnym KOLCEM. Balansuje sylwetkę lotu. ---
	_cube(_model, Vector3(0.20, 0.20, 0.30), Vector3(0.0, 1.14, 0.46), skin)        # nasada ogona
	_cube(_model, Vector3(0.14, 0.14, 0.30), Vector3(0.0, 1.08, 0.72), skin_d)      # środek ogona
	_cube(_model, Vector3(0.09, 0.09, 0.26), Vector3(0.0, 1.02, 0.96), skin_d)      # końcówka
	_cube(_model, Vector3(0.14, 0.14, 0.14), Vector3(0.0, 1.00, 1.14), accent, true)   # kolec/żądło świecące

	# --- SKRZYDŁA = _arm_l/_arm_r: pivoty w barkach (y=1.34), rozłożone SZEROKO w bok. Obrót na X
	#     (rig "ramion") przechyla rozpostarte płaty → czytelny TRZEPOT/przechył lotu. Każde skrzydło:
	#     gruba kość przednia + cienka błona ciągnąca się w bok i lekko do tyłu (+Z). ---
	_arm_l = _make_pivot(_model, Vector3(-0.20, 1.34, -0.02))
	_arm_r = _make_pivot(_model, Vector3(0.20, 1.34, -0.02))
	# Lewe skrzydło (rozciąga się w -X).
	_cube(_arm_l, Vector3(0.46, 0.10, 0.12), Vector3(-0.28, 0.04, -0.04), skin_d)   # kość barkowa
	_cube(_arm_l, Vector3(0.40, 0.06, 0.46), Vector3(-0.68, 0.00, 0.10), skin)      # błona wewnętrzna
	_cube(_arm_l, Vector3(0.34, 0.05, 0.40), Vector3(-1.04, -0.04, 0.18), skin_d)   # błona zewnętrzna
	_cube(_arm_l, Vector3(0.10, 0.14, 0.10), Vector3(-1.24, 0.02, -0.08), skin_d)   # pazur/szczyt skrzydła
	# Prawe skrzydło (lustro w +X).
	_cube(_arm_r, Vector3(0.46, 0.10, 0.12), Vector3(0.28, 0.04, -0.04), skin_d)
	_cube(_arm_r, Vector3(0.40, 0.06, 0.46), Vector3(0.68, 0.00, 0.10), skin)
	_cube(_arm_r, Vector3(0.34, 0.05, 0.40), Vector3(1.04, -0.04, 0.18), skin_d)
	_cube(_arm_r, Vector3(0.10, 0.14, 0.10), Vector3(1.24, 0.02, -0.08), skin_d)

	# --- ŁAPY = _leg_l/_leg_r: pivoty pod brzuchem (y=1.02), PODKULONE w locie. Obrót na X kołysze je
	#     łagodnie; przy szarży robią krótki wymach szponem. Udo + zwisające szpony. ---
	_leg_l = _make_pivot(_model, Vector3(-0.14, 1.02, 0.04))
	_leg_r = _make_pivot(_model, Vector3(0.14, 1.02, 0.04))
	for leg in [_leg_l, _leg_r]:
		_cube(leg, Vector3(0.14, 0.24, 0.16), Vector3(0.0, -0.14, -0.04), skin_d)   # udo (podkulone)
		_cube(leg, Vector3(0.16, 0.10, 0.20), Vector3(0.0, -0.28, -0.10), skin)     # podudzie/stopa
		_cube(leg, Vector3(0.05, 0.10, 0.06), Vector3(-0.05, -0.36, -0.18), mouth)  # szpon L
		_cube(leg, Vector3(0.05, 0.10, 0.06), Vector3(0.05, -0.36, -0.18), mouth)   # szpon R


func _build_silhouette_spirit() -> void:
	# --- ELEMENTAL SPIRIT (wariant wulkaniczny: ognisty duch / demon lawy). FLOATER bez kontaktu z ziemią:
	# jasny EMISYJNY RDZEŃ unoszący się ~y1.0, owinięty kilkoma ciemnymi odłamkami skały/żaru krążącymi wokół,
	# z 4 wiotkimi MACKAMI/wstęgami zwisającymi pod spodem. Macki mapuję na istniejący rig (zero nowej animacji):
	#   _arm_l/_arm_r = przednia para wstęg (-Z), _leg_l/_leg_r = tylna para (+Z). Łagodny obrót.x w _process
	#   czyta się jako DRYF/falowanie macek (nie chód). Sylwetka: świetlista kula z dymiącymi mackami — natychmiast
	#   odróżnia się od goblina/bruta/slingera/zwierza. Mostly emisyjny, złowieszczy, bez stóp na ziemi.
	_is_floating = true
	var pal := _variant_palette()
	var skin: Color = pal[0]; var skin_d: Color = pal[1]; var eyes: Color = pal[2]
	var accent: Color = pal[5]
	# Odłamki skały/żaru — bardzo ciemne, "ostygła skorupa lawy" wokół rozżarzonego rdzenia (kontrast z emisją).
	var shard := skin_d.darkened(0.55)

	# --- RDZEŃ: rozżarzona kula (warstwowa, by świeciła "mięsiście" z każdej strony) unosząca się ~y1.0. ---
	_cube(_model, Vector3(0.46, 0.46, 0.46), Vector3(0.0, 1.00, 0.0), accent, true)     # jądro (jasne)
	_cube(_model, Vector3(0.60, 0.30, 0.40), Vector3(0.0, 1.00, 0.0), accent, true)     # poprzeczny rozbłysk
	_cube(_model, Vector3(0.30, 0.60, 0.40), Vector3(0.0, 1.00, 0.0), accent, true)     # pionowy rozbłysk

	# --- ZŁOWIESZCZE OCZY z przodu rdzenia (-Z), świecące — twarz ducha czytelna z daleka. ---
	_cube(_model, Vector3(0.10, 0.12, 0.05), Vector3(-0.13, 1.06, -0.26), eyes, true)   # oko L
	_cube(_model, Vector3(0.10, 0.12, 0.05), Vector3(0.13, 1.06, -0.26), eyes, true)    # oko R

	# --- ODŁAMKI SKAŁY/ŻARU krążące wokół rdzenia (ciemne, asymetryczne — "orbitujący gruz"). Statyczne. ---
	_cube(_model, Vector3(0.22, 0.22, 0.22), Vector3(-0.42, 1.16, 0.10), shard)         # górny-lewy
	_cube(_model, Vector3(0.20, 0.20, 0.20), Vector3(0.40, 0.86, -0.06), shard)         # dolny-prawy
	_cube(_model, Vector3(0.18, 0.18, 0.18), Vector3(0.10, 1.40, 0.18), shard)          # nad rdzeniem (tył)
	_cube(_model, Vector3(0.16, 0.16, 0.16), Vector3(-0.18, 0.74, -0.30), shard)        # przód-dół
	# Rozżarzone szczeliny w paru odłamkach (emisyjny żar w pęknięciach skały) — sparingly.
	_cube(_model, Vector3(0.24, 0.06, 0.06), Vector3(-0.42, 1.16, 0.10), accent, true)
	_cube(_model, Vector3(0.06, 0.22, 0.06), Vector3(0.40, 0.86, -0.06), accent, true)

	# --- 4 WIOTKIE MACKI/WSTĘGI zwisające pod rdzeniem (pivoty u podstawy ~y0.74, zwisają w DÓŁ, bez ziemi). ---
	# Przednia para = _arm_l/_arm_r (przy -Z), tylna = _leg_l/_leg_r (przy +Z). Obrót.x w _process → dryf.
	_arm_l = _make_pivot(_model, Vector3(-0.18, 0.74, -0.14))
	_arm_r = _make_pivot(_model, Vector3(0.18, 0.74, -0.14))
	_leg_l = _make_pivot(_model, Vector3(-0.18, 0.74, 0.16))
	_leg_r = _make_pivot(_model, Vector3(0.18, 0.74, 0.16))
	for tend in [_arm_l, _arm_r, _leg_l, _leg_r]:
		_cube(tend, Vector3(0.14, 0.30, 0.14), Vector3(0.0, -0.18, 0.0), skin)          # górny segment (ciało ducha)
		_cube(tend, Vector3(0.10, 0.26, 0.10), Vector3(0.0, -0.40, 0.0), skin_d)        # środkowy (cieńszy, ciemniejszy)
		_cube(tend, Vector3(0.07, 0.18, 0.07), Vector3(0.0, -0.58, 0.0), accent, true)  # żarzący się koniuszek (wisp)


# --- SAND WORM — pionowy, SEGMENTOWANY tubus wynurzający się z ziemi w ŁUKU (kostki piętrzą się
# w górę, potem głowa opada do przodu/-Z), zwieńczony okrągłą PASZCZĄ z pierścieniem zębów i
# świecącym GARDŁEM (emit). Brak nóg. Sylwetka "wieża z piasku" czyta się natychmiast z daleka i
# jest oczywiście różna od humanoidów (goblin/brute/slinger) i poziomego czworonoga (beast).
#
# ANIMACJA: rig obraca CZTERY pivoty na osi X. Mapuję je na CZTERY zawiasy-segmenty wzdłuż łuku
# (od podstawy do głowy), KAŻDY zagnieżdżony w poprzednim (łańcuch), więc obrót.x każdego segmentu
# kumuluje się i całe ciało FALUJE/undulauje. Kolejność łańcucha base->head: _arm_l, _arm_r, _leg_l,
# _leg_r. W ścieżce chodu _arm_l=+swing, _arm_r=-swing, _leg_l=-swing, _leg_r=+swing → sąsiednie
# segmenty są w przeciwfazie → przez tubus przebiega fala (wąż wije się). Geometrię każdego segmentu
# (oraz głowę/paszczę) wieszam NA tych pivotach, by ruch był widoczny; pivoty nie są pustymi stubami.
func _build_silhouette_worm() -> void:
	var pal := _variant_palette()
	var skin: Color = pal[0]; var skin_d: Color = pal[1]; var eyes: Color = pal[2]
	var mouth: Color = pal[3]; var accent: Color = pal[5]

	# --- STOPA/KOPIEC u podstawy (statyczny) — wysypany piach wokół miejsca wynurzenia, kotwiczy
	#     sylwetkę w ziemi (feet at y=0). Szeroki, niski, ciemniejszy. ---
	_cube(_model, Vector3(0.86, 0.22, 0.86), Vector3(0.0, 0.11, 0.10), skin_d)
	_cube(_model, Vector3(0.66, 0.16, 0.66), Vector3(0.20, 0.08, -0.16), skin_d)
	_cube(_model, Vector3(0.58, 0.14, 0.58), Vector3(-0.22, 0.07, 0.22), skin_d)

	# --- DOLNY, najgrubszy SEGMENT tubusa (statyczny, wrośnie z kopca). Pierścieniowe prążki = dwa
	#     ciemniejsze "obręcze" sugerujące segmentację robaka. ---
	_cube(_model, Vector3(0.52, 0.40, 0.52), Vector3(0.0, 0.42, 0.0), skin)
	_cube(_model, Vector3(0.56, 0.06, 0.56), Vector3(0.0, 0.30, 0.0), skin_d)   # obręcz
	_cube(_model, Vector3(0.54, 0.06, 0.54), Vector3(0.0, 0.56, 0.0), skin_d)   # obręcz

	# --- ŁAŃCUCH 4 ZAWIASÓW-SEGMENTÓW wzdłuż ŁUKU. Każdy pivot dziecko poprzedniego; lokalne pos
	#     przesuwa go w górę i stopniowo do przodu (-Z), tworząc krzywiznę "rośnie w górę, potem
	#     głowa nurkuje". Każdy nosi swój walec ciała + obręcz. Grubość maleje ku głowie. ---
	# Segment 1 (base->) = _arm_l
	_arm_l = _make_pivot(_model, Vector3(0.0, 0.66, 0.0))
	_cube(_arm_l, Vector3(0.48, 0.34, 0.48), Vector3(0.0, 0.17, 0.0), skin)
	_cube(_arm_l, Vector3(0.50, 0.06, 0.50), Vector3(0.0, 0.30, 0.0), skin_d)  # obręcz/staw

	# Segment 2 = _arm_r (dziecko _arm_l) — zaczyna lekko nachylać łuk do przodu (-Z).
	_arm_r = _make_pivot(_arm_l, Vector3(0.0, 0.36, -0.04))
	_cube(_arm_r, Vector3(0.44, 0.32, 0.44), Vector3(0.0, 0.16, -0.02), skin)
	_cube(_arm_r, Vector3(0.46, 0.06, 0.46), Vector3(0.0, 0.28, -0.02), skin_d)

	# Segment 3 = _leg_l (dziecko _arm_r) — łuk przechyla się mocniej do przodu, czubek zaczyna opadać.
	_leg_l = _make_pivot(_arm_r, Vector3(0.0, 0.34, -0.12))
	_cube(_leg_l, Vector3(0.40, 0.30, 0.40), Vector3(0.0, 0.13, -0.06), skin)
	_cube(_leg_l, Vector3(0.42, 0.06, 0.42), Vector3(0.0, 0.24, -0.06), skin_d)

	# Segment 4 = _leg_r (dziecko _leg_l) — szyja gnie się do przodu/dół; tu osadzona GŁOWA z paszczą.
	_leg_r = _make_pivot(_leg_l, Vector3(0.0, 0.28, -0.20))
	_cube(_leg_r, Vector3(0.36, 0.26, 0.40), Vector3(0.0, 0.08, -0.10), skin)   # szyja gnąca się w przód

	# --- GŁOWA + OKRĄGŁA PASZCZA z przodu szyji (-Z), w lokalu _leg_r. Czaszka, potem pierścień ZĘBÓW
	#     wokół otworu i ŚWIECĄCE GARDŁO w środku (emit). Pierścień zębów = 8 małych kostek radialnie. ---
	var head_y := 0.06
	var head_z := -0.34
	_cube(_leg_r, Vector3(0.46, 0.42, 0.34), Vector3(0.0, head_y, head_z), skin)        # głowa (bulwiasta)
	_cube(_leg_r, Vector3(0.50, 0.10, 0.30), Vector3(0.0, head_y + 0.18, head_z), skin_d)  # grzbietowy wał głowy
	# ŚWIECĄCE GARDŁO — wpuszczone w czoło paszczy (przód = -Z), emisyjny rdzeń czytelny z daleka.
	_cube(_leg_r, Vector3(0.24, 0.24, 0.10), Vector3(0.0, head_y, head_z - 0.18), accent, true)  # gardło
	_cube(_leg_r, Vector3(0.12, 0.12, 0.06), Vector3(0.0, head_y, head_z - 0.23), eyes, true)    # jaśniejszy rdzeń
	# PIERŚCIEŃ ZĘBÓW wokół otworu paszczy (8 kostek radialnie w płaszczyźnie X/Y, przy przodzie -Z).
	var teeth := 8
	var tr := 0.18
	var mouth_z := head_z - 0.21
	for i in teeth:
		var a := TAU * float(i) / float(teeth)
		var tx := cos(a) * tr
		var ty := head_y + sin(a) * tr
		_cube(_leg_r, Vector3(0.07, 0.07, 0.12), Vector3(tx, ty, mouth_z), mouth)

	# --- OCZKA/SENSORY po bokach głowy (drobne, świecące — "ślepy drapieżnik wyczuwający drgania"). ---
	_cube(_leg_r, Vector3(0.06, 0.07, 0.08), Vector3(-0.22, head_y + 0.10, head_z - 0.04), eyes, true)  # oko L
	_cube(_leg_r, Vector3(0.06, 0.07, 0.08), Vector3(0.22, head_y + 0.10, head_z - 0.04), eyes, true)   # oko R


func _make_pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p

# Pomocnik: dodaje jedną kostkę. Opcjonalny 'emit' włącza emisję (świecące oczy).
# Zapamiętuje materiał + bazowy kolor do błysku trafienia.
func _cube(parent: Node3D, size: Vector3, pos: Vector3, color: Color, emit: bool = false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	if emit:
		mat.emission_enabled = true
		mat.emission = color
		# FEEL 3: poświata akcentów (oczy/rdzeń/maczuga/kula) podbita 1.5->2.2 — czytelne emisyjne
		# akcenty z daleka i w cieniu/mgle, BEZ przepału (glow_hdr_threshold=1.0 trzyma bloom w ryzach).
		mat.emission_energy_multiplier = 2.2
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	# Do błysku trafienia (interpolacja albedo do bieli i z powrotem).
	_mats.append(mat)
	_base_colors.append(color)

# ============================================================================
#  REFERENCJA DO CELU
# ============================================================================
func set_target(t: Node3D) -> void:
	_target = t


# ETAP 7b: oznacza wroga jako CZYSTA REPLIKA u klienta (host_authoritative). Pozycje narzuca
# MultiplayerSynchronizer (NetTransformSync), wiec wlasna fizyka tego ciala jest zbedna i wręcz
# szkodliwa (grawitacja kumuluje velocity.y, move_and_slide moze wepchnac replike w teren ZANIM
# synchronizer ja przyciagnie -> mikro-jitter, review #minor). Wylaczamy ja na replice: transform
# pochodzi WYLACZNIE z sieci, klient tylko interpoluje. WOLA TYLKO NetManager._rpc_spawn_enemy
# (czyli wylacznie u klienta w co-opie). SP/host NIGDY tu nie wchodzi -> pelna fizyka jak dotad.
func mark_as_net_replica() -> void:
	_is_net_replica = true
	# Zatrzymujemy _physics_process (zero grawitacji/move_and_slide), ale _process (wizual: obrot
	# modelu z replikowanego _face_dir, kolysanie konczyn, blysk) DZIALA — replika wyglada zywo.
	set_physics_process(false)
	velocity = Vector3.ZERO


# ============================================================================
#  ETAP 6 — KONWERSJA W PETA (ALLY) + skalowanie wg gracza
# ============================================================================
## Zamienia ZYWEGO wroga w peta gracza. WOLANE przez TameSystem PO spelnieniu warunkow oswojenia.
## NIE duplikuje AI — przelacza flage allegiance w AIComponent (cel = wrog, leash = gracz, FOLLOW) i
## przeklada warstwy hurtbox/hitbox na strone gracza. Na koncu skaluje staty peta wg pet_damage/pet_hp
## gracza (silniejszy gracz => silniejszy pet). scale_src = StatsComponent gracza (zrodlo mnoznikow).
func convert_to_pet(owner_node: Node3D, scale_src: StatsComponent) -> void:
	allegiance = Allegiance.ALLY
	_pet_owner = owner_node
	add_to_group("pets")
	remove_from_group("enemies")              # swiat/loot/licznik wrogow NIE liczy peta

	# WARSTWY: cialo peta na warstwie GRACZA (sojusznik). Wrogowie (enemy_hitbox mask player_body)
	# celuja w niego tak jak w gracza; hitbox gracza (mask enemy_body) go NIE trafia.
	collision_layer = 1 << 1                   # bit1 = player_body (warstwa gracza)
	collision_mask = 1                         # tylko teren (jak dotad)

	# HURTBOX peta -> strona gracza: hitboxy WROGOW go wykrywaja, hitbox GRACZA/PETOW — nie.
	if _hurtbox != null:
		_hurtbox.setup_as_player()             # layer = player_body, mask 0

	# HITBOX peta -> bije WROGOW (mask = enemy_body), nie gracza ani innych petow (oba na player_body).
	if _hitbox != null:
		_hitbox.setup_as_player(0.2)           # layer = player_hitbox, mask = enemy_body, waski luk

	# AI: cel = najblizszy wrog (nie gracz), leash do gracza, start FOLLOW. Reuse maszyny.
	if _ai != null:
		_ai.set_allegiance_ally(owner_node)

	apply_pet_scaling(scale_src)


## ETAP 6 — skalowanie peta wg pet_damage/pet_hp gracza. Mnozniki wchodza jako INCREASED przez
## StatsComponent.add_modifiers (pipeline/memoizacja/sygnal -> HealthComponent klamruje max_hp), wiec
## damage i max_hp peta rosna automatycznie. Re-aplikowalne (zdejmuje stary source przed dodaniem).
func apply_pet_scaling(player_stats: StatsComponent) -> void:
	if _stats == null or player_stats == null:
		return
	_stats.remove_modifiers_by_source(&"pet_scaling")   # idempotencja przy ponownym skalowaniu
	var pdmg := player_stats.get_stat(&"pet_damage")    # np. 0.30 => +30% dmg
	var php := player_stats.get_stat(&"pet_hp")          # np. 0.40 => +40% HP
	var mods: Array[StatModifier] = []
	if pdmg != 0.0:
		var m := StatModifier.new()
		m.stat = &"damage"; m.op = StatModifier.Op.INCREASED; m.value = pdmg
		m.source_id = &"pet_scaling"
		mods.append(m)
	if php != 0.0:
		var h := StatModifier.new()
		h.stat = &"max_hp"; h.op = StatModifier.Op.INCREASED; h.value = php
		h.source_id = &"pet_scaling"
		mods.append(h)
	if not mods.is_empty():
		_stats.add_modifiers(mods)
	if _health != null:
		_health.revive_full()                  # swiezy, pelny pet (current_hp = nowy max)

# ============================================================================
#  FIZYKA + AI
# ============================================================================
func _physics_process(delta: float) -> void:
	# 1) Grawitacja
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# 2) Fallback: brak celu → szukaj gracza w grupie (autonomia przy streamingu)
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player") as Node3D

	# Liczniki ataku zawsze tykają.
	_attack_timer = maxf(0.0, _attack_timer - delta)
	# COMBAT (reaktywność): tyk hitstunu + regeneracja poise poza hitstunem (elity wracają do gardy).
	_hitstun_t = maxf(0.0, _hitstun_t - delta)
	if _hitstun_t <= 0.0 and _poise_current < poise:
		_poise_current = minf(poise, _poise_current + POISE_REGEN * delta)

	# Pionowy impuls knockbacku (jednorazowy, jak u gracza) — dodawany do velocity.y.
	if _knockback.y > 0.0:
		velocity.y += _knockback.y
		_knockback.y = 0.0

	# 3) Dystans XZ do gracza (różnice wysokości terenu nie fałszują aggro/leash)
	var has_target := _target != null and is_instance_valid(_target)
	var dist := INF
	if has_target:
		var d := _target.global_position - global_position
		dist = Vector2(d.x, d.z).length()

	# 4) Wybór stanu + 5) ruch poziomy: ETAP 1 deleguje do AIComponent (host-only, TDD 6.2).
	# W SP NetManager.has_authority(self)==true -> AIComponent.tick() liczy lokalnie; w Etapie 7
	# klient pomija tick (velocity przyjdzie przez Synchronizer), ale grawitacja/knockback/
	# move_and_slide nadal działają u niego (płynna interpolacja). Windup ciosu tyka tu zawsze
	# po stronie autorytetu, niezależnie od przejść stanów AI (czytelny zamach + okno na unik).
	if NetManager.has_authority(self):
		if _ai != null:
			_state = _ai.tick(delta) as State    # mapowanie enum 1:1 (IDLE/PATROL/CHASE/ATTACK)
			_process_attack_windup(delta, has_target, dist)
		else:
			# Fallback gdyby AIComponent nie powstał — wbudowana maszyna (bezpieczeństwo).
			match _state:
				State.IDLE:    _state_idle(delta, has_target, dist)
				State.PATROL:  _state_patrol(delta, has_target, dist)
				State.CHASE:   _state_chase(delta, has_target, dist)
				State.ATTACK:  _state_attack(delta, has_target, dist)
		# COMBAT (reaktywność): podczas hitstunu wróg NIE napiera (zamrożenie ruchu własnego);
		# knockback (doliczany niżej) działa dalej, więc trafienie odpycha i przerywa napór.
		if _hitstun_t > 0.0:
			velocity.x = 0.0
			velocity.z = 0.0
		# AUDYT #5: stun zeruje ruch własny (jak hitstun); chill skaluje prędkość. Knockback dalej działa.
		if _status != null:
			if _status.is_stunned():
				velocity.x = 0.0
				velocity.z = 0.0
			else:
				var sm := _status.speed_mult()
				if sm < 1.0:
					velocity.x *= sm
					velocity.z *= sm

	# 5b) Knockback poziomy: doliczamy PO wyborze stanu (stany nadpisują/zerują velocity.x/z),
	# żeby odrzut był widoczny mimo logiki AI. Wygaszamy go przez move_toward co klatkę.
	velocity.x += _knockback.x
	velocity.z += _knockback.z
	_knockback.x = move_toward(_knockback.x, 0.0, knockback_decay * delta)
	_knockback.z = move_toward(_knockback.z, 0.0, knockback_decay * delta)

	# 6) Auto-podskok po terenie voxelowym (gdy się porusza i napotka 1-blokowy stopień).
	# Pomijamy podczas knockbacku, by trafienie pod ścianą nie dawało podwójnego wyskoku.
	if is_on_floor() and is_on_wall() and (absf(velocity.x) + absf(velocity.z)) > 0.1 and _knockback.length_squared() < 0.01:
		velocity.y = 6.5

	# 7) Ruch z kolizją
	move_and_slide()

# ============================================================================
#  ETAP 1 — KONTRAKT AIComponent (encja = "ciało", AIComponent = "mózg")
# ============================================================================
# AIComponent woła te metody w tick(); cała decyzyjność (stany/leash/histereza) siedzi w komponencie.
func ai_get_position() -> Vector3:
	return global_position

func ai_get_target() -> Node3D:
	return _target if (_target != null and is_instance_valid(_target)) else null

func ai_move_towards(point: Vector3, spd: float) -> void:
	_move_towards(point, spd)

func ai_stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0

func ai_face(dir: Vector3) -> void:
	if dir.length() > 0.01:
		_face_dir = dir.normalized()

# Czy CD ataku zszedł i nie trwa już cykl zamachu (windup). AIComponent pyta przed ai_attack().
func ai_can_attack() -> bool:
	return not _attacking and _attack_timer <= 0.0

# Inicjuje cykl ataku: melee -> windup -> okno hitboxa; ranged i tak idzie windup -> Projectile.
# Faktyczne zadanie obrażeń dzieje się po windupie w _process_attack_windup (czytelny zamach).
func ai_attack(target: Node3D) -> void:
	if _attacking or _attack_timer > 0.0:
		return
	if target != null and is_instance_valid(target):
		_target = target
	_attacking = true
	_windup_timer = attack_windup
	# ETAP 4: elite/boss pokazują TELEGRAF (HazardZone preview) na czas windupu — czytelna
	# zapowiedź ciosu w hordzie. Trash (Goblin) nie telegrafuje (czysty błysk ręki wystarcza).
	_spawn_telegraph()

# ETAP 4: tworzy telegraf-zapowiedź ciosu (HazardZone w trybie preview = SAM WIZUAL, zero dmg).
# Tylko elite/boss; promień rośnie z threat_tier (boss czytelniejszy). Ustawiany w miejsce ciosu
# (przed wrogiem dla melee, na celu dla ranged). Zwalniany w _clear_telegraph po ciosie/przerwaniu.
func _spawn_telegraph() -> void:
	if threat_tier != &"elite" and threat_tier != &"boss":
		return
	_clear_telegraph()                       # nigdy dwóch naraz
	var tz := HazardZone.new()
	tz.preview = true                        # telegraf: bez obrażeń (dmg idzie hitboxem/pociskiem)
	tz.duration = maxf(0.05, attack_windup + 0.15)   # żyje tylko przez windup (+zapas)
	tz.radius = 1.6 if threat_tier == &"elite" else 2.4
	# Kolor zależny od elementu wariantu (ognisty=pomarańcz, lodowy=błękit, neutralny=czerwień).
	var col := Color(1.0, 0.35, 0.15, 0.35)
	if element == &"frost":
		col = Color(0.35, 0.7, 1.0, 0.35)
	elif element == &"fire":
		col = Color(1.0, 0.5, 0.1, 0.4)
	tz.preview_color = col
	tz.active_color = Color(col.r, col.g, col.b, 0.5)
	# Telegraf jest CZYSTO WIZUALNY: dmg zadaje hitbox melee / Projectile, NIE ta strefa. Dlatego
	# hit_builder jest pusty (preview nie tyka) i tej strefy NIE wolno arm() (HazardZone.arm ostrzega).
	tz.setup(self, Callable(), (1 << 1))     # maska celu = ciało gracza; preview i tak nie tyka
	var parent := get_parent()
	if parent == null:
		tz.free()
		return
	parent.add_child(tz)
	# Pozycja: melee przed wrogiem (na kierunku _face_dir), ranged na celu (jeśli znany).
	var p := global_position
	if ai_profile == &"ranged" and _target != null and is_instance_valid(_target):
		p = (_target as Node3D).global_position
	elif _face_dir.length() > 0.01:
		p = global_position + _face_dir * (attack_range * 0.6)
	tz.global_position = Vector3(p.x, p.y, p.z)
	_telegraph = tz

# Zwalnia aktywny telegraf (po ciosie, przerwaniu ataku, leashu lub śmierci).
func _clear_telegraph() -> void:
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_telegraph = null

# Tyka windup ataku po stronie autorytetu; po jego zejściu zadaje cios (melee = okno hitboxa,
# ranged = Projectile). Histereza zasięgu *1.3 jak dawniej — gracz może odskoczyć w trakcie windupu.
func _process_attack_windup(delta: float, has_target: bool, dist: float) -> void:
	if not _attacking:
		return
	if _hitstun_t > 0.0:                          # COMBAT: hitstun pauzuje windup — cios przerywa rytm zamachu
		return
	if _status != null and _status.is_stunned(): # AUDYT #5: stun pauzuje atak (ogłuszony wróg nie zadaje ciosu)
		return
	_windup_timer -= delta
	if _windup_timer > 0.0:
		return
	# Windup zakończony — zadaj cios, jeśli cel nadal w zasięgu (mógł odskoczyć).
	if has_target and dist <= attack_range * 1.3:
		if ai_profile == &"ranged":
			_spawn_projectile()
		else:
			# Melee: otwórz okno hitboxa (Area3D) skierowane na cel. Hitbox zbierze ciało/hurtbox
			# gracza i wywoła DamageService (jedno źródło). Fallback bez hitboxa: bezpośredni request.
			if _hitbox != null:
				_hitbox.global_position = global_position + Vector3(0.0, 0.9, 0.0)
				_hitbox.open_window(0.12, _face_dir)
			elif _target != null and is_instance_valid(_target):
				DamageService.request_hit(self, _target, _build_hit())
	_clear_telegraph()                       # telegraf znika z ciosem (czytelność)
	_attacking = false
	_attack_timer = attack_cooldown

# --- IDLE: stoi, tyka licznik, potem PATROL. Aggro → CHASE. ---
func _state_idle(delta: float, has_target: bool, dist: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if has_target and dist <= aggro_radius:
		_state = State.CHASE
		return
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_pick_patrol_target()
		_patrol_timer = 5.0
		_state = State.PATROL

# --- PATROL: idzie do losowego punktu wokół domu. Aggro → CHASE. ---
func _state_patrol(delta: float, has_target: bool, dist: float) -> void:
	if has_target and dist <= aggro_radius:
		_state = State.CHASE
		return
	_move_towards(_patrol_target, move_speed)
	_patrol_timer -= delta
	var to := _patrol_target - global_position
	to.y = 0.0
	if to.length() < 0.8 or _patrol_timer <= 0.0:
		_idle_timer = randf_range(1.5, 3.5)
		_state = State.IDLE

# --- CHASE: idzie do gracza. W zasięgu → ATTACK. Za daleko (leash) → powrót do domu. ---
func _state_chase(_delta: float, has_target: bool, dist: float) -> void:
	if not has_target:
		_patrol_target = _home
		_state = State.PATROL
		return
	if dist > leash_radius:
		_patrol_target = _home
		_state = State.PATROL
		return
	if dist <= attack_range:
		velocity.x = 0.0
		velocity.z = 0.0
		# Mała zwłoka przed pierwszym ciosem: gracz dostaje okno na unik/odskok,
		# zanim padnie pierwsze trafienie (bez tego cios szedł już po samym windupie).
		# maxf, by nie skrócić ewentualnego trwającego cooldownu.
		_attack_timer = maxf(_attack_timer, attack_entry_delay)
		_state = State.ATTACK
		return
	_move_towards(_target.global_position, move_speed)

# --- ATTACK: stoi, patrzy na gracza, wykonuje cykl windup→hit→cooldown. Histereza wyjścia. ---
func _state_attack(delta: float, has_target: bool, dist: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	if not has_target:
		_attacking = false
		_clear_telegraph()
		_patrol_target = _home
		_state = State.PATROL
		return
	# Leash ma priorytet — nawet w trakcie ataku.
	if dist > leash_radius:
		_attacking = false
		_clear_telegraph()
		_patrol_target = _home
		_state = State.PATROL
		return

	# Patrz na gracza (kierunek do obrotu modelu w _process).
	var to := _target.global_position - global_position
	to.y = 0.0
	if to.length() > 0.01:
		_face_dir = to.normalized()

	# Cykl ataku.
	if not _attacking and _attack_timer <= 0.0:
		_attacking = true
		_windup_timer = attack_windup
		_spawn_telegraph()    # ETAP 4: zapowiedź ciosu dla elite/boss (fallback bez AIComponent)
		# (opcjonalnie: unieś prawą rękę — robi to _process gdy _attacking)
	if _attacking:
		_windup_timer -= delta
		if _windup_timer <= 0.0:
			# Zadaj dmg TYLKO jeśli gracz nadal w zasięgu (mógł odskoczyć). Histereza *1.3.
			# ETAP 1: melee przez DamageService (host-authoritative, TDD 4); ranged spawnuje pocisk.
			if dist <= attack_range * 1.3:
				if ai_profile == &"ranged":
					_spawn_projectile()
				elif _target != null and is_instance_valid(_target):
					DamageService.request_hit(self, _target, _build_hit())
			_clear_telegraph()
			_attacking = false
			_attack_timer = attack_cooldown

	# Wyjście do CHASE z histerezą, by stany nie migotały na granicy.
	if not _attacking and dist > attack_range * 1.3:
		_state = State.CHASE

# Ruch w stronę punktu (XZ). Zapamiętuje kierunek do obrotu modelu.
func _move_towards(point: Vector3, spd: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length() > 0.05:
		var dir := to.normalized()
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
		_face_dir = dir
	else:
		velocity.x = 0.0
		velocity.z = 0.0

# Losowy punkt patrolu w promieniu patrol_radius wokół domu.
func _pick_patrol_target() -> void:
	var ang := randf() * TAU
	var r := randf() * patrol_radius
	_patrol_target = _home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)

# ============================================================================
#  WIZUALE: obrót modelu + chód + błysk + zamach
# ============================================================================
func _process(delta: float) -> void:
	if _model == null:
		return

	# FAZA 5: ROAMING ELITE — pulsujaca aura (czytelne "tetno mocy" z daleka). Tania (jedno swiatlo).
	if _elite_aura != null:
		_elite_aura_phase += delta * 2.4
		_elite_aura.light_energy = ELITE_AURA_BASE_ENERGY * (0.8 + 0.35 * (0.5 + 0.5 * sin(_elite_aura_phase)))

	# #11: ENRAGE — czerwona aura pulsuje SZYBCIEJ (gniewne "tetno") niz aura elite. Tania (jedno swiatlo).
	if _enrage_aura != null:
		_enrage_aura_phase += delta * 5.0
		_enrage_aura.light_energy = ENRAGE_AURA_BASE_ENERGY * (0.85 + 0.4 * (0.5 + 0.5 * sin(_enrage_aura_phase)))

	# ART OVERHAUL: ZNACZNIK KLASY ZAGROŻENIA (elite/boss) — marker nad głową delikatnie BOBUJE w górę/dół
	# i powoli obraca się wokół osi pionowej (czytelny "żywy" akcent celu z daleka). Czysto wizualne, tanie.
	if _threat_marker != null:
		_threat_marker_phase += delta
		_threat_marker.position.y = _threat_marker_base_y() + 0.08 * sin(_threat_marker_phase * 2.2)
		_threat_marker.rotation.y = _threat_marker_phase * 1.2

	# ART OVERHAUL: HOVER stworów latających (wywern/żywiołak) — model unosi się i delikatnie buja,
	# więc czyta się jako „w powietrzu" (sylwetka budowana wyżej, brak styku z ziemią).
	if _is_floating:
		_float_phase += delta
		_model.position.y = 0.30 + 0.12 * sin(_float_phase * 1.7)

	# Obrót modelu w stronę _face_dir (przód = -Z), płynnie.
	if _face_dir.length() > 0.01:
		var target_yaw := atan2(-_face_dir.x, -_face_dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, turn_speed * delta)

	# Animacja: zamach (gdy _attacking) ma priorytet na PRAWEJ ręce; reszta = chód.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if _attacking:
		var t := 1.0
		if attack_windup > 0.0:
			t = clampf(1.0 - (_windup_timer / attack_windup), 0.0, 1.0)
		if _is_beast:
			# CZWORONÓG: zwierzę nie unosi "ręki" — robi krótki SZARŻOWY wymach przedniej pary nóg
			# do przodu (paw/ryj w dół-przód), reszta sylwetki napiera. Tył kołysze się jeśli idzie.
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.7 * t, 14.0 * delta)
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.7 * t, 14.0 * delta)
			_animate_legs(delta, hspeed)
		else:
			# Unieś prawą rękę do przodu — szybki, czytelny "zamach szponem".
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.6 * t, 14.0 * delta)
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.0, 10.0 * delta)
			# Nogi nadal mogą się kołysać, jeśli (rzadko) idzie; tu zwykle stoi → spoczynek.
			_animate_legs(delta, hspeed)
	elif hspeed > 0.3:
		_walk_phase += delta * hspeed * 2.2
		var swing := sin(_walk_phase) * 0.6
		_arm_l.rotation.x = swing
		_arm_r.rotation.x = -swing
		_leg_l.rotation.x = -swing
		_leg_r.rotation.x = swing
	else:
		# Powrót do spoczynku (lerp do 0).
		_walk_phase = 0.0
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.0, 10.0 * delta)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.0, 10.0 * delta)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, 10.0 * delta)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, 10.0 * delta)

	# Błysk trafienia: interpoluj albedo do bieli wg _flash_timer, potem przywróć.
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		var k := _flash_timer / hit_flash_time   # 1 → 0
		for i in _mats.size():
			_mats[i].albedo_color = _base_colors[i].lerp(Color.WHITE, k)
		if _flash_timer == 0.0:
			# Pełny powrót do bazowych kolorów.
			for i in _mats.size():
				_mats[i].albedo_color = _base_colors[i]

	# FEEL (3): FLINCH — krotkie szarpniecie modelu (przesuniecie + przechyl) na trafieniu. Gasnie
	# wykladniczo (~0.1 s). To CZYSTO wizual nakladany na pozycje/rotacje MODELU (nie na cialo/HP).
	# Daje "odczuty" cios poza czerwonym flashem — wrog reaguje WIDOCZNIE.
	if _flinch_t > 0.0:
		_flinch_t = maxf(0.0, _flinch_t - delta)
		var f := _flinch_t / FLINCH_TIME             # 1 → 0
		var amp := f * f                             # ostre na starcie, miekkie wygaszenie
		# Przesuniecie modelu w kierunku ciosu (lokalny XZ wzgledem rotacji modelu pomijamy — maly efekt).
		_model.position.x = _flinch_dir.x * FLINCH_OFFSET * amp
		_model.position.z = _flinch_dir.z * FLINCH_OFFSET * amp
		# Przechyl (pitch w kierunku ciosu) — model "kuli sie" od uderzenia.
		_model.rotation.x = -amp * FLINCH_TILT
		if _flinch_t == 0.0:
			_model.position.x = 0.0
			_model.position.z = 0.0
			_model.rotation.x = 0.0

# Animacja samych nóg (używana podczas zamachu).
func _animate_legs(delta: float, hspeed: float) -> void:
	if hspeed > 0.3:
		_walk_phase += delta * hspeed * 2.2
		var swing := sin(_walk_phase) * 0.6
		_leg_l.rotation.x = -swing
		_leg_r.rotation.x = swing
	else:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, 10.0 * delta)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, 10.0 * delta)

# ============================================================================
#  HP, OBRAŻENIA, ŚMIERĆ
# ============================================================================
# ETAP 1: take_damage to teraz HOOK FX + (fallback) HP. DamageService woła go z amount=0, gdy HP
# liczy HealthComponent (FX-only: knockback/flash/wybudzenie AI bez podwójnego odejmowania HP).
# Bezpośrednie wywołanie (np. test) z amount>0 i wpiętym HealthComponent kieruje obrażenia do
# komponentu (jedno źródło HP). knockback>=0 nadpisuje knockback_force (siła per-cios z HitData).
func take_damage(amount: float, from: Node = null, knockback: float = -1.0) -> void:
	if is_dead():
		return

	# FX/zachowanie: błysk + wybudzenie AI do pościgu (nawet gdy źródło poza aggro).
	_flash_timer = hit_flash_time
	if from != null and from is Node3D:
		_target = from as Node3D
	if _ai != null:
		_ai.wake_to_chase()
	if _state == State.IDLE or _state == State.PATROL:
		_state = State.CHASE

	# Odrzut: w kierunku OD źródła (XZ) + lekkie podbicie. Siła z HitData (knockback>=0) lub eksport.
	# Gasnący wektor _knockback (nie velocity wprost) — _physics_process dolicza go PO wyborze stanu.
	if from != null and from is Node3D:
		var away := global_position - (from as Node3D).global_position
		away.y = 0.0
		if away.length() > 0.01:
			var force := knockback if knockback >= 0.0 else knockback_force
			_knockback = away.normalized() * force
			_knockback.y = 3.0         # jednorazowy impuls w górę (zerowany po doliczeniu)

	# COMBAT (reaktywność): hitstun + złamanie poise. Wywoływane dla KAŻDEGO ciosu (DamageService woła
	# take_damage jako hook FX, amount=0), więc tu "rejestruje się" reakcja wroga. Knockback już doliczony.
	_hitstun_t = maxf(_hitstun_t, HITSTUN_TIME)
	_poise_current -= 1.0
	if _poise_current <= 0.0:
		_poise_current = poise                  # reset puli (trash: poise 0 => łamie się każdym ciosem)
		_hitstun_t = maxf(_hitstun_t, STAGGER_TIME)
		if _attacking:                          # PRZERWANIE ataku: telegraf znika, windup anulowany
			_attacking = false
			_clear_telegraph()

	# HP: gdy wpięty HealthComponent — to ON liczy HP/śmierć (DoD). amount>0 kierujemy do niego
	# (bezpośrednie wywołania działają), amount==0 to czysty hook FX (DamageService już odjął HP).
	if _health != null:
		if amount > 0.0:
			_health.apply_damage(amount, from)
		return
	# Fallback (brak HealthComponent): klasyczne odejmowanie HP w tym pliku.
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		_die()

# Czy wróg jest martwy — jedno źródło prawdy (HealthComponent jeśli wpięty, inaczej hp/flaga).
func is_dead() -> bool:
	if _health != null:
		return _health.is_dead
	return hp <= 0.0

var _dead_emitted: bool = false

# Mostek z HealthComponent: HP zmienione -> mirror do publicznego pola hp (HUD/AI/gracz czytają hp).
# #11: tu też wyzwalamy ENRAGE bossa — gdy HP spadnie <=50% maxa (raz). Jedyny punkt prawdy HP, więc
# bez osobnego pollingu. Gated: tylko boss z włączoną mechaniką (boss_mechanics). Nie cofa się przy
# leczeniu (_enraged jednorazowe). _maximum z HealthComponent jest miarodajny (po klamrowaniu staty).
func _on_health_hp_changed(current: float, _maximum: float) -> void:
	hp = current
	if not _enraged and boss_mechanics and threat_tier == &"boss":
		var mx := _maximum if _maximum > 0.0 else max_hp
		if mx > 0.0 and current <= mx * enrage_hp_frac and current > 0.0:
			_enrage()

# #11: WEJSCIE W SZAL — jednorazowy boost statow bossa + wizualna aura wsciekłości. Skraca attack_cooldown
# (szybsze ciosy), podbija attack_damage i move_speed. Mnozniki wchodza tez do _stats (jesli wpiety),
# by HitData liczone przez StatsComponent realnie urosło (a nie tylko goly attack_damage). Idempotentne:
# _enraged blokuje ponowne wejscie (np. wahanie HP wokol progu / leczenie ponizej-powyzej 50%).
func _enrage() -> void:
	if _enraged:
		return
	_enraged = true
	# Staty: gola sciezka eksportow (fallback) — zawsze podbita, by is_enraged + buff byly widoczne.
	attack_damage *= enrage_damage_mult
	move_speed *= enrage_speed_mult
	if enrage_attack_speed_mult > 0.0:
		attack_cooldown = maxf(0.05, attack_cooldown / enrage_attack_speed_mult)
	# Sciezka komponentowa: dosyp INCREASED do StatsComponent (damage/move_speed), by HitData/AI liczone
	# przez staty tez urosly. Re-aplikowalne (source_id), choc enrage i tak odpala sie raz.
	if _stats != null:
		var mods: Array[StatModifier] = []
		var md := StatModifier.new()
		md.stat = &"damage"; md.op = StatModifier.Op.INCREASED
		md.value = enrage_damage_mult - 1.0; md.source_id = &"boss_enrage"
		mods.append(md)
		var ms := StatModifier.new()
		ms.stat = &"move_speed"; ms.op = StatModifier.Op.INCREASED
		ms.value = enrage_speed_mult - 1.0; ms.source_id = &"boss_enrage"
		mods.append(ms)
		_stats.add_modifiers(mods)
	# AI: szybszy ruch wymaga odswiezenia move_speed w AIComponent (czyta go z configure).
	if _ai != null:
		_ai.configure({ "move_speed": move_speed })
	# Wizual: czerwona aura wsciekłości + lekkie powiekszenie sylwetki (czytelny zwrot walki).
	if _model != null:
		_model.scale *= 1.12
	_build_enrage_aura()

# #11: aura ENRAGE — czerwony OmniLight3D pulsujacy szybciej niz aura elite (czytelne "boss sie wkurzyl"
# z daleka). Bez cieni (tanio), distance fade. Pulsacja w _process (_enrage_aura_phase). Idempotentne.
func _build_enrage_aura() -> void:
	if _enrage_aura != null or _model == null:
		return
	var l := OmniLight3D.new()
	l.name = "EnrageAura"
	l.light_color = Color(1.0, 0.18, 0.10)        # gniewna czerwien
	l.light_energy = ENRAGE_AURA_BASE_ENERGY
	l.omni_range = ENRAGE_AURA_RANGE
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 40.0
	l.distance_fade_length = 12.0
	l.position = Vector3(0.0, 1.1, 0.0)
	add_child(l)
	_enrage_aura = l

# FEEL (3): HealthComponent.damaged (amount>0) -> wyzwala FLINCH (szarpniecie modelu). Kierunek OD
# zrodla (jak knockback); brak zrodla -> losowy mikro-flinch. CZYSTO wizualne, zero wplywu na HP/AI.
func _on_health_damaged(amount: float, from: Node, _current_hp: float) -> void:
	if amount <= 0.0 or is_dead():
		return
	var dir := Vector3.ZERO
	if from != null and is_instance_valid(from) and from is Node3D:
		dir = global_position - (from as Node3D).global_position
		dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	_flinch_dir = dir.normalized()
	_flinch_t = FLINCH_TIME

# Śmierć przez HealthComponent -> wspólna ścieżka _die (idempotentna).
func _on_health_died(_from: Node) -> void:
	_die()

func _die() -> void:
	if _dead_emitted:
		return                # idempotencja: HealthComponent.died + ewentualny fallback nie dublują
	_dead_emitted = true
	hp = 0.0
	_clear_telegraph()        # ETAP 4: nie zostawiaj wiszącej zapowiedzi po śmierci elite/boss
	# ETAP 6: pet (ALLY) NIE dropi lootu i NIE emituje died (to daloby graczowi XP/licznik za swojego
	# peta). Pet po prostu znika (TameSystem czysci _active_pet przez is_instance_valid). GDD 9 zostawia
	# furtke na respawn — tu upraszczamy do free (nie psuje walki/lootu/progresji).
	if allegiance == Allegiance.ALLY:
		queue_free()
		return
	# ETAP 2: policz drop ZANIM encja zniknie (LootService HOST-ONLY/deterministyczny). Emitujemy
	# pozycje + liste dropow, by Main zespawnowal LootDrop-y w SWIECIE (nie pod zwalnianym wrogiem).
	# LootService to autoload (zawsze obecny w runtime/teście headless).
	var drops := LootService.drop_for(self)
	if not drops.is_empty():
		loot_dropped.emit(global_position, drops)
	died.emit(self)          # Main/świat policzy ubitych
	_spawn_death_burst()      # FAZA 2: rozpad na voxele + pop (kosmetyczny, world-space) PRZED free
	queue_free()

# FAZA 2: ROZPAD NA VOXELE + POP — zamiast natychmiastowego znikniecia, jeden one-shot burst kawalkow
# (kostki w kolorze skory) z impulsem rozlotu i grawitacja. Spawnowany na RODZICU (nie pod zwalnianym
# wrogiem), z timerem samo-zwolnienia na drzewie sceny. Kosmetyczny: zero wplywu na HP/loot/licznik.
# Wzorzec puli/one-shot/unshaded spojny z FeelFX._make_spark; kolor z _base_colors[0] (skora wroga).
func _spawn_death_burst() -> void:
	if _model == null:
		return
	var parent := get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	var p := GPUParticles3D.new()
	p.amount = 22
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 1.0          # caly burst naraz = "pekniecie" na voxele
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.3, 0.6, 0.3) * body_scale   # objetosc ciala wroga
	pm.gravity = Vector3(0.0, -9.0, 0.0)               # kawalki spadaja
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 60.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0                       # POP: rozlot na zewnatrz
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0                     # kawalki koziolkuja
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.09, 0.09, 0.09) * body_scale  # rozmiar ~ voxela wroga
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _base_colors[0] if _base_colors.size() > 0 else Color(0.30, 0.55, 0.22)
	mat.roughness = 1.0
	mesh.material = mat
	p.draw_pass_1 = mesh
	p.process_material = pm
	parent.add_child(p)
	p.global_position = global_position + Vector3(0.0, 0.7 * body_scale, 0.0)
	p.emitting = true
	var tree := parent.get_tree()

	# JUICE (ART OVERHAUL): kolor „esencji" wg elementu wariantu (ciepły domyślnie).
	var ecol := Color(1.0, 0.86, 0.55)
	match element:
		&"fire": ecol = Color(1.0, 0.50, 0.20)
		&"frost": ecol = Color(0.50, 0.82, 1.0)
		&"poison": ecol = Color(0.60, 1.0, 0.42)
		&"lightning": ecol = Color(0.82, 0.82, 1.0)

	# JUICE: BŁYSK ŚWIATŁA (pop) w chwili śmierci — krótki OmniLight gasnący tweenem (czytelny „kill").
	var fl := OmniLight3D.new()
	fl.omni_range = 3.4 * body_scale
	fl.light_energy = 2.6
	fl.light_color = ecol
	parent.add_child(fl)
	fl.global_position = p.global_position
	var ftw := fl.create_tween()
	ftw.tween_property(fl, "light_energy", 0.0, 0.32)
	ftw.tween_callback(fl.queue_free)

	# JUICE: unoszący się „duszek" energii — esencja wroga ulatuje w górę (emisyjne iskry pod prąd grawitacji).
	var w := GPUParticles3D.new()
	w.amount = 9
	w.lifetime = 0.85
	w.one_shot = true
	w.explosiveness = 0.55
	w.local_coords = false
	var wpm := ParticleProcessMaterial.new()
	wpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	wpm.emission_sphere_radius = 0.22 * body_scale
	wpm.gravity = Vector3(0.0, 1.4, 0.0)        # UNOSZĄ się w górę
	wpm.direction = Vector3(0.0, 1.0, 0.0)
	wpm.spread = 22.0
	wpm.initial_velocity_min = 1.0
	wpm.initial_velocity_max = 2.4
	wpm.damping_min = 0.5
	wpm.damping_max = 1.5
	wpm.scale_min = 0.4
	wpm.scale_max = 0.9
	var wmesh := QuadMesh.new()
	wmesh.size = Vector2(0.12, 0.12) * body_scale
	var wmat := StandardMaterial3D.new()
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmat.albedo_color = ecol
	wmat.emission_enabled = true
	wmat.emission = ecol
	wmat.emission_energy_multiplier = 3.0
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	wmesh.material = wmat
	w.draw_pass_1 = wmesh
	w.process_material = wpm
	parent.add_child(w)
	w.global_position = p.global_position
	w.emitting = true

	# Samo-zwolnienie po lifetime (timery na drzewie sceny, nie na zwalnianym wrogu).
	if tree != null:
		tree.create_timer(0.9).timeout.connect(p.queue_free)
		tree.create_timer(1.2).timeout.connect(w.queue_free)

# ============================================================================
#  ETAP 1 — HitData wroga + Slinger (pocisk)
# ============================================================================

# Buduje HitData ciosu/pocisku wroga (przez StatsComponent jeśli wpięty, inaczej eksporty).
func _build_hit() -> HitData:
	var hit := HitData.new()
	hit.source = self
	hit.base_damage = _stat(&"damage", attack_damage)
	hit.crit_chance = crit_chance
	hit.crit_mult = crit_mult
	hit.knockback = knockback_force
	# typed: HitData.tags to Array[StringName] (4.x strict — literal/ternary daje goly Array).
	var t: Array[StringName] = []
	t.append(&"ranged" if ai_profile == &"ranged" else &"melee")
	# ETAP 4: element wariantu biomowego (fire/frost...) — DamageService czyta tagi pod odporności.
	if element != &"":
		t.append(element)
	hit.tags = t
	# AUDYT #5: wróg z elementem nakłada status na cel (ember->burn, frost->chill, ...). mag ~ 30% dmg.
	if element != &"":
		hit.on_hit_effects = [{ "kind": element, "mag": _stat(&"damage", attack_damage) * 0.3, "dur": 3.0 }]
	return hit

func _stat(key: StringName, fallback: float) -> float:
	if _stats != null:
		return _stats.get_stat(key)
	return fallback

# Slinger: spawnuje Projectile lecący w stronę celu. CCD pociska sam liczy trafienie/teren przez
# DamageService (jedno źródło obrażeń). Maska: teren | ciało gracza (warstwa 2).
func _spawn_projectile() -> void:
	# ETAP 6 (review): CEL POCISKU zalezny od allegiance. WROG strzela w _target (gracz). PET (ALLY)
	# strzela we WROGA rozwiazanego przez AIComponent (_nearest_enemy), bo _target peta jest
	# NIEJEDNOZNACZNY: take_damage() ustawia go na atakujacego wroga, a fallback _physics_process (~L475)
	# na GRACZA. Gdyby ranged pet celowal w _target, smierc celu w trakcie windupu (fallback przestawia
	# _target na gracza) -> pet strzelilby w GRACZA. AI-rozwiazany cel jest jednoznaczny i NIGDY nie jest
	# graczem; brak zywego wroga w zasiegu -> nie strzelaj (pet nie marnuje pocisku w gracza). Lustro
	# maski nizej (body_bit), ktora juz jest allegiance-aware (ALLY -> enemy_body bit2).
	var aim_target: Node3D = _target
	if allegiance == Allegiance.ALLY:
		aim_target = _ai.current_target() if _ai != null else null
	if aim_target == null or not is_instance_valid(aim_target):
		return
	var proj := Projectile.new()
	var origin := global_position + Vector3(0.0, 1.0, 0.0)         # z wysokości tułowia
	var aim: Vector3 = aim_target.global_position + Vector3(0.0, 0.9, 0.0)
	var dir := (aim - origin)
	# ETAP 6 (review): maska pocisku zalezy od allegiance. WROG celuje w teren|cialo gracza (bit1);
	# PET (ALLY) celuje w teren|cialo wroga (enemy_body=bit2) — inaczej pocisk peta trafialby gracza
	# i inne pety (oba na player_body=bit1) i NIE trafialby wrogow. Lustro tego, co convert_to_pet
	# robi dla hitboxa melee. LATENTNE dzis (jedyny oswajalny goblin=melee), ale pulapka pod ranged-pety.
	var body_bit := (1 << 2) if allegiance == Allegiance.ALLY else (1 << 1)
	var mask := (1 << 0) | body_bit                               # teren | cialo celu (wrog: gracz, pet: wrog)
	# Builder HitData per cel (Projectile woła go przy trafieniu) — domknięcie na self.
	proj.setup(self, dir, projectile_speed, func(_t: Node) -> HitData: return _build_hit(),
		mask, projectile_gravity, projectile_pierce)
	# Dodaj do drzewa świata (rodzic Enemy = Main/świat), żeby pocisk żył niezależnie od wroga.
	# global_position ustawiamy DOPIERO po add_child — przed wejściem do drzewa set jest ignorowany
	# (Node3D.get_global_transform ostrzega "!is_inside_tree()" i zwraca identyczność).
	var parent := get_parent()
	if parent != null:
		parent.add_child(proj)
		proj.global_position = origin
	# ETAP 7b: HOST replikuje pocisk do klientow (klient ekstrapoluje wizual lokalnie — TDD 6.4).
	# Spawn pociskow jest i tak host-only (AI host-only -> _spawn_projectile odpala sie wylacznie u
	# autorytetu), wiec host jest jedynym zrodlem. SP -> no-op. Host despawnuje replike na impakcie.
	if NetManager != null and NetManager.has_network() and NetManager.is_host():
		var nid := NetManager.host_spawn_projectile(origin, dir, projectile_speed, mask,
			projectile_gravity, projectile_pierce)
		if nid > 0:
			proj.impacted.connect(func(_p: Vector3, _t: Node) -> void: NetManager.host_despawn_entity(nid))
