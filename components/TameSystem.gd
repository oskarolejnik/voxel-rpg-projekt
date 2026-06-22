class_name TameSystem
extends Node
## TameSystem.gd (komponent) — OSWAJANIE bestii (ETAP 6, model Cube World / GDD 9).
##
## Petla oswajania: oslab dzika bestie do <35% HP, podejdz blisko i uzyj item-oswajacza zdobytego
## w terenie (klawisz T). Gate: poziom gracza >= 5. Po spelnieniu warunkow wrog staje sie PETEM
## (ALLY) gracza i walczy u jego boku, skalujac sie z pet_damage/pet_hp gracza. 1 AKTYWNY pet
## (nowe oswojenie zastepuje poprzedniego; typ ladu​je w "stajni" save'a).
##
## Komponent wisi pod graczem (dziecko Player). Czyta jego LevelComponent + StatsComponent.
## HOST-ONLY (NetManager.has_authority) — w SP zawsze liczy lokalnie; Etap 7 doda RPC do hosta.
##
## Item-oswajacz: kontrakt `charm_provider` -> bool (czy gracz MA i zuzywa 1x charm). Domyslnie
## prosty licznik `charm_count` (drop z bestii wpina sie w grze; test ustawia licznik/flage). To
## trzyma TameSystem niezaleznym od konkretnego InventoryComponent (loot-pipeline poza rdzeniem E6).

const TAME_HP_FRACTION: float = 0.35      # cel musi miec < 35% HP (GDD 9)
const TAME_MIN_LEVEL: int = 5             # od poziomu 5 (ROADMAP/GDD 9)
const TAME_RANGE: float = 4.0             # gracz musi byc blisko celu
const TAME_CHARM_ITEM: StringName = &"tame_charm"   # item-oswajacz (drop z bestii)

signal pet_changed(pet_id: StringName)
signal tame_failed(reason: StringName)    # &"level"/&"hp"/&"no_item"/&"no_target"/&"chance"

## Liczba posiadanych item-oswajaczy (drop z terenu). add_charm() dosypuje; oswojenie zuzywa 1.
var charm_count: int = 0
## Opcjonalny zewnetrzny dostawca charma: func() -> bool (zwraca true i ZUZYWA 1 charm). Gdy ustawiony,
## ma pierwszenstwo nad charm_count (np. podpiecie do InventoryComponent). Pusty -> uzyj charm_count.
var charm_provider: Callable = Callable()

var _player: Node3D = null
var _level: LevelComponent = null
var _stats: StatsComponent = null
var _active_pet: Node3D = null            # JEDEN aktywny pet
var _stable: Array[StringName] = []       # oswojone typy (stajnia -> save.pet_stable)


## Wpiecie zaleznosci (Player wola w _build_progression). level/stats sluza do gate'u i skalowania.
func setup(player: Node3D, level: LevelComponent, stats: StatsComponent) -> void:
	_player = player
	_level = level
	_stats = stats


## Dosypuje item-oswajacze (hook dropu z bestii / lootu). Bezpieczne (>=0).
func add_charm(n: int = 1) -> void:
	charm_count = maxi(0, charm_count + n)


func active_pet() -> Node3D:
	return _active_pet if (_active_pet != null and is_instance_valid(_active_pet)) else null


func active_pet_id() -> StringName:
	var p := active_pet()
	if p != null and "variant_id" in p:
		return StringName(p.variant_id)
	return &""


func stable() -> Array[StringName]:
	return _stable.duplicate()


# ============================================================================
#  GLOWNE WEJSCIE — proba oswojenia (klawisz T)
# ============================================================================
## Proba oswojenia wskazanego/najblizszego celu. Zwraca true gdy sukces. Emituje tame_failed(reason)
## przy odrzuceniu (gate/HP/brak itemu/brak celu/szansa). Kolejnosc bramek = czytelny feedback.
func try_tame(target: Enemy = null) -> bool:
	if NetManager != null and not NetManager.has_authority(_player):
		return false                      # Etap 7: RPC do hosta; SP zawsze host
	# 1) GATE poziomu (od lvl 5).
	if _level == null or _level.level < TAME_MIN_LEVEL:
		tame_failed.emit(&"level")
		return false
	# 2) Cel (wskazany lub najblizszy oswajalny w zasiegu).
	if target == null:
		target = _nearest_tameable()
	if target == null or not is_instance_valid(target):
		tame_failed.emit(&"no_target")
		return false
	if not _is_tameable(target):
		tame_failed.emit(&"no_target")
		return false
	# 3) GATE HP < 35% (oslab bestie najpierw).
	if _hp_fraction(target) >= TAME_HP_FRACTION:
		tame_failed.emit(&"hp")
		return false
	# 4) Item-oswajacz w ekwipunku (zdobyty w terenie) — sprawdz POSIADANIE, ale jeszcze NIE zuzywaj.
	if not _has_charm():
		tame_failed.emit(&"no_item")
		return false
	# 5) Szansa: pewne gdy tame_difficulty_mult <= 1; trudniejsze bestie -> szansa (1/diff).
	#    ETAP 6 (review): rzut PRZED zuzyciem charma — nieudana proba NIE marnuje zdobytego w terenie
	#    item-oswajacza (consume-on-success-only). GDD 9 milczy o consume-on-fail; wybieramy lagodniej.
	if not _roll_success(target):
		tame_failed.emit(&"chance")
		return false
	# 6) Sukces pewny -> dopiero teraz zuzyj charm i przeksztalc cel w peta.
	if not _consume_charm():
		tame_failed.emit(&"no_item")       # wyscig: charm zniknal miedzy sprawdzeniem a zuzyciem
		return false
	_commit_tame(target)
	return true


func _commit_tame(target: Enemy) -> void:
	# 1 AKTYWNY PET — usun poprzedniego (jego typ zostaje w stajni).
	if _active_pet != null and is_instance_valid(_active_pet):
		(_active_pet as Enemy).queue_free()
	target.convert_to_pet(_player, _stats)     # Enemy -> ALLY (warstwy + AI + skalowanie)
	_active_pet = target
	var pid := StringName(target.variant_id)
	if not _stable.has(pid):
		_stable.append(pid)
	pet_changed.emit(pid)


# ============================================================================
#  WARUNKI / POMOCNIKI
# ============================================================================
func _hp_fraction(e: Enemy) -> float:
	var mx: float = e.max_hp
	if e._health != null:
		mx = e._health.max_hp()                 # JEDNO zrodlo HP (HealthComponent)
	if mx <= 0.0:
		return 0.0
	return clampf(e.hp / mx, 0.0, 1.0)


func _is_tameable(e: Enemy) -> bool:
	if e.is_dead():
		return false
	if e.allegiance == Enemy.Allegiance.ALLY:
		return false                            # juz pet
	var res: EnemyResource = _enemy_res(e)
	return res != null and res.tameable


func _enemy_res(e: Enemy) -> EnemyResource:
	if EnemyDB != null and EnemyDB.has_method("enemy"):
		return EnemyDB.enemy(e.variant_id)
	return null


func _roll_success(e: Enemy) -> bool:
	var res: EnemyResource = _enemy_res(e)
	var diff: float = res.tame_difficulty_mult if res != null else 1.0
	if diff <= 1.0:
		return true                             # zwykle bestie: pewne przy spelnionych warunkach
	var chance := clampf(1.0 / diff, 0.05, 1.0) # trudniejsze: szansa
	return _tame_rand() < chance


func _tame_rand() -> float:
	if RNGService != null and "combat" in RNGService and RNGService.combat is RandomNumberGenerator:
		return RNGService.combat.randf()        # deterministyczne (spojne z DamageService)
	return randf()


## Czy gracz POSIADA item-oswajacz (BEZ zuzycia). Uzywane jako bramka 4 przed rzutem szansy, by
## nieudana proba nie marnowala charma. charm_provider nie ma "peek" (sam zuzywa), wiec dla niego
## zakladamy posiadanie i realnie weryfikujemy przy _consume_charm() na sukcesie (consume-on-success).
func _has_charm() -> bool:
	if charm_provider.is_valid():
		return true
	return charm_count > 0


## Zuzycie item-oswajacza. charm_provider (jesli ustawiony) ma pierwszenstwo; inaczej charm_count.
func _consume_charm() -> bool:
	if charm_provider.is_valid():
		return bool(charm_provider.call())
	if charm_count > 0:
		charm_count -= 1
		return true
	return false


## Najblizszy oswajalny wrog w TAME_RANGE od gracza (skan grupy "enemies").
func _nearest_tameable() -> Enemy:
	if _player == null or not is_instance_valid(_player):
		return null
	var pos: Vector3 = _player.global_position
	var best: Enemy = null
	var best_d := TAME_RANGE * TAME_RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Enemy):
			continue
		var en := e as Enemy
		if not _is_tameable(en):
			continue
		var d: Vector3 = en.global_position - pos
		var dsq := d.x * d.x + d.z * d.z
		if dsq <= best_d:
			best_d = dsq
			best = en
	return best


# ============================================================================
#  SAVE — pet w SaveData (round-trip pet_id + stajnia)
# ============================================================================
## Wpisuje aktywny pet + stajnie do SaveData (Player.write_progression_to_save deleguje tu).
func write_pet_to_save(sd: SaveData) -> void:
	if sd == null:
		return
	sd.pet_id = active_pet_id()                 # &"" gdy brak peta
	sd.pet_stable = _stable.duplicate()


## Odtwarza pet ze stanu save (Main wola po spawnie gracza). pet_id != "" -> spawn ALLY tego typu.
func load_pet_from_save(sd: SaveData) -> void:
	if sd == null:
		return
	_stable = sd.pet_stable.duplicate()
	if sd.pet_id != &"":
		spawn_pet_from_id(sd.pet_id)


## Spawnuje peta danego typu (EnemyDB) jako ALLY przy graczu. Zwraca utworzonego peta (lub null).
func spawn_pet_from_id(pet_type: StringName) -> Enemy:
	var res: EnemyResource = null
	if EnemyDB != null and EnemyDB.has_method("enemy"):
		res = EnemyDB.enemy(pet_type)
	if res == null:
		return null
	var e := Enemy.new()
	e.configure_from_resource(res)
	var parent: Node = _player.get_parent() if (_player != null and _player.get_parent() != null) else self
	parent.add_child(e)                         # _ready buduje komponenty (Stats/Health/AI/hitbox)
	if _player != null and is_instance_valid(_player):
		e.global_position = _player.global_position + Vector3(1.5, 0.0, 0.0)
	e.convert_to_pet(_player, _stats)
	if _active_pet != null and is_instance_valid(_active_pet) and _active_pet != e:
		(_active_pet as Enemy).queue_free()
	_active_pet = e
	if not _stable.has(pet_type):
		_stable.append(pet_type)
	pet_changed.emit(pet_type)
	return e
