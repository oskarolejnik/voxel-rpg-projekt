class_name AbilityComponent
extends Node
## AbilityComponent.gd (komponent) — wykonuje SkillResource: koszt zasobu, cooldown (cdr),
## cast_time, spawn sceny (pocisk/AoE), odpalenie hitboxa; BUFOR + ANULOWANIE (TDD 1.2, ROADMAP 4
## krok 3). Uzywany przez gracza (atak/dash jako SkillResource) ORAZ przez AIComponent (wrog/pet).
##
## Komponent jest neutralny wzgledem "kto" — encja podpina sie callbackami:
##   - resource_pool: func(name: StringName) -> float        (ile zasobu mamy: stamina/rage...)
##   - resource_spend: func(name: StringName, amount: float) (wydatek; encja pilnuje min/HUD)
##   - perform_skill: func(skill, target) -> void            (faktyczne wykonanie: hitbox/anim/spawn)
## Dzieki temu rdzen (koszt/CD/cast/bufor/cancel) jest WSPOLNY, a specyfika (animacja zamachu,
## kierunek, spawn pocisku) zostaje w encji — zero zmian w odczuciu gry.

signal skill_started(skill: SkillResource)
signal skill_finished(skill: SkillResource)
signal skill_failed(skill: SkillResource, reason: String)

## Bufor wejscia (ROADMAP 4 krok 3): wcisniecie tuz przed koncem CD/castu zostaje "zapamietane".
@export var input_buffer_time: float = 0.18

@export var stats_path: NodePath          # do StatsComponent (cdr/zasoby). Pusta -> brat.

var _stats: StatsComponent = null

## Cooldowny per skill id.
var _cooldowns: Dictionary = {}           # StringName(id) -> float (s pozostale)

## Stan castu.
var _casting: bool = false
var _cast_left: float = 0.0
var _cast_skill: SkillResource = null
var _cast_target: Node = null
var _in_recovery: bool = false            # po wykonaniu, zanim CD zwolni "anim recovery"

## Bufor.
var _buffered_skill: SkillResource = null
var _buffered_target: Node = null
var _buffer_left: float = 0.0

## Callbacki wstrzykiwane przez encje (patrz naglowek).
var resource_pool: Callable = Callable()
var resource_spend: Callable = Callable()
var perform_skill: Callable = Callable()


func _ready() -> void:
	_stats = _resolve_stats()


func _resolve_stats() -> StatsComponent:
	if stats_path != NodePath() and has_node(stats_path):
		return get_node(stats_path) as StatsComponent
	var parent := get_parent()
	if parent != null:
		for child in parent.get_children():
			if child is StatsComponent:
				return child as StatsComponent
	return null


func _process(delta: float) -> void:
	for id in _cooldowns:
		_cooldowns[id] = maxf(0.0, float(_cooldowns[id]) - delta)

	if _casting:
		_cast_left -= delta
		if _cast_left <= 0.0:
			_finish_cast()

	if _buffer_left > 0.0:
		_buffer_left -= delta
		if _buffer_left <= 0.0:
			_buffered_skill = null
			_buffered_target = null
		elif _can_start(_buffered_skill):
			# Okno sie otworzylo (CD zszedl / cast skonczony) -> odpal z bufora.
			var s := _buffered_skill
			var t := _buffered_target
			_buffered_skill = null
			_buffered_target = null
			_buffer_left = 0.0
			_start(s, t)


## Glowne wejscie: probuje uzyc skilla. Jesli teraz nie mozna (CD/cast/zasob) — BUFORUJE.
## Zwraca true jesli wystartowal natychmiast.
func try_use(skill: SkillResource, target: Node = null) -> bool:
	if skill == null:
		return false
	if _can_start(skill) and _has_resource(skill):
		_start(skill, target)
		return true
	# Nie teraz -> bufor (chyba ze brakuje zasobu na trwale — wtedy i tak bufor wygasnie).
	_buffered_skill = skill
	_buffered_target = target
	_buffer_left = input_buffer_time
	return false


## Czy mozna ZACZAC skilla teraz (CD zszedl i nie trwa cast). Zasob sprawdzany osobno.
func _can_start(skill: SkillResource) -> bool:
	if skill == null or _casting:
		return false
	return _cooldown_left(skill.id) <= 0.0


func _has_resource(skill: SkillResource) -> bool:
	if skill.cost_resource == &"" or skill.cost_amount <= 0.0:
		return true
	if resource_pool.is_valid():
		return float(resource_pool.call(skill.cost_resource)) >= skill.cost_amount
	return true


func _start(skill: SkillResource, target: Node) -> void:
	# Pobierz zasob (encja pilnuje minimow/HUD).
	if skill.cost_resource != &"" and skill.cost_amount > 0.0 and resource_spend.is_valid():
		resource_spend.call(skill.cost_resource, skill.cost_amount)

	skill_started.emit(skill)

	if skill.cast_time > 0.0:
		_casting = true
		_cast_left = skill.cast_time
		_cast_skill = skill
		_cast_target = target
	else:
		_execute(skill, target)


func _finish_cast() -> void:
	_casting = false
	var s := _cast_skill
	var t := _cast_target
	_cast_skill = null
	_cast_target = null
	if s != null:
		_execute(s, t)


func _execute(skill: SkillResource, target: Node) -> void:
	# Cooldown z uwzglednieniem cdr ze StatsComponent (TDD 2.3 cdr).
	var cdr := 0.0
	if _stats != null:
		cdr = clampf(_stats.get_stat(&"cdr"), 0.0, 0.9)
	_cooldowns[skill.id] = skill.cooldown * (1.0 - cdr)

	# Faktyczne wykonanie (hitbox/anim/spawn pocisku) deleguje encja.
	if perform_skill.is_valid():
		perform_skill.call(skill, target)

	skill_finished.emit(skill)


## ANULOWANIE (ROADMAP 4 krok 3): np. atak przerwany unikiem TYLKO w fazie recovery/cast.
## Zwraca true jesli faktycznie cos anulowano (encja moze wtedy zresetowac animacje).
func cancel() -> bool:
	var did := false
	if _casting:
		_casting = false
		_cast_skill = null
		_cast_target = null
		_cast_left = 0.0
		did = true
	# Wyczysc bufor (unik kasuje zakolejkowany atak).
	if _buffered_skill != null:
		_buffered_skill = null
		_buffered_target = null
		_buffer_left = 0.0
		did = true
	return did


func is_casting() -> bool:
	return _casting


func _cooldown_left(id: StringName) -> float:
	return float(_cooldowns.get(id, 0.0))


func cooldown_left(id: StringName) -> float:
	return _cooldown_left(id)


## Provider dla StatsComponent: passive_modifiers wpietych skilli (TDD 3.2 pkt 4). Etap 1 szkielet —
## skille wpiete trzyma encja; tu zwracamy puste (rozszerzymy przy drzewku/ekwipunku w Etapie 2/3).
func collect_modifiers() -> Array[StatModifier]:
	return []
