class_name StatusEffectComponent
extends Node
## StatusEffectComponent.gd — statusy bojowe (audyt #5): DoT (burn/poison/bleed), chill (slow),
## stun, weaken. Sibling encji (Enemy/Player). HOST-AUTHORITATIVE: DoT tyka TYLKO na hoscie i idzie
## przez DamageService.apply_dot (HP + replikacja, BEZ take_damage -> NIE wyzwala hitstunu/odrzutu).
## Chill/stun/weaken to FLAGI czytane przez ruch/AI encji (speed_mult / is_stunned / damage_taken_mult).
## Czasy odliczane niezaleznie od FPS. Refresh (NIE stack): ponowne nalozenie odnawia czas + silę.

enum Kind { BURN, POISON, BLEED, CHILL, STUN, WEAKEN }

## Element (tag afiksu/wroga) -> rodzaj statusu.
const ELEMENT_TO_KIND := {
	&"fire": Kind.BURN,
	&"poison": Kind.POISON,
	&"bleed": Kind.BLEED,
	&"frost": Kind.CHILL,
	&"lightning": Kind.WEAKEN,
	&"dark": Kind.WEAKEN,
}
## Rodzaj DoT -> element (pod odpornosci w DamageService.apply_dot).
const KIND_ELEMENT := {
	Kind.BURN: &"fire",
	Kind.POISON: &"poison",
	Kind.BLEED: &"bleed",
}

const DOT_INTERVAL: float = 0.5     # s między tykami DoT
const CHILL_SLOW: float = 0.4       # -40% prędkości podczas chill
const WEAKEN_AMP: float = 0.2       # +20% otrzymywanych obrażeń podczas weaken

signal status_applied(kind: int)

var _host: Node = null
var _health: HealthComponent = null
var _effects: Dictionary = {}       # kind:int -> { mag:float (DPS dla DoT), time_left:float, source:Node }
var _dot_accum: float = 0.0


func _ready() -> void:
	_host = get_parent()
	if _host != null:
		for c in _host.get_children():
			if c is HealthComponent:
				_health = c
				break


func _is_dot(kind: int) -> bool:
	return kind == Kind.BURN or kind == Kind.POISON or kind == Kind.BLEED


## Nakłada status. duration<=0 (lub magnitude<=0 dla DoT) => no-op. Refresh istniejącego (NIE stack).
func apply(kind: int, magnitude: float, duration: float, source: Node = null) -> void:
	if duration <= 0.0:
		return
	if _is_dot(kind) and magnitude <= 0.0:
		return
	_effects[kind] = { "mag": maxf(0.0, magnitude), "time_left": duration, "source": source }
	status_applied.emit(kind)


## Nakłada status z elementu (fire->burn, frost->chill, poison->poison, lightning->weaken). Nieznany => no-op.
func apply_element(element: StringName, magnitude: float, duration: float, source: Node = null) -> void:
	if ELEMENT_TO_KIND.has(element):
		apply(int(ELEMENT_TO_KIND[element]), magnitude, duration, source)


func is_stunned() -> bool:
	return _effects.has(Kind.STUN)

func speed_mult() -> float:
	return (1.0 - CHILL_SLOW) if _effects.has(Kind.CHILL) else 1.0

func damage_taken_mult() -> float:
	return (1.0 + WEAKEN_AMP) if _effects.has(Kind.WEAKEN) else 1.0

func has(kind: int) -> bool:
	return _effects.has(kind)

func active_count() -> int:
	return _effects.size()

func clear_all() -> void:
	_effects.clear()
	_dot_accum = 0.0


func _physics_process(delta: float) -> void:
	if _effects.is_empty():
		return
	# Odliczanie czasu trwania (na wszystkich peerach — by lokalny CC nie wisiał wiecznie u klienta).
	var expired: Array = []
	for kind in _effects:
		var e: Dictionary = _effects[kind]
		e["time_left"] = float(e["time_left"]) - delta
		if float(e["time_left"]) <= 0.0:
			expired.append(kind)
	for kind in expired:
		_effects.erase(kind)
	# DoT — TYLKO host (HP autorytatywne; klient widzi spadek HP przez DamageService sync).
	var host_auth := NetManager == null or NetManager.has_state_authority(_host)
	if host_auth and _health != null and not _health.is_dead:
		_dot_accum += delta
		while _dot_accum >= DOT_INTERVAL and not _effects.is_empty():
			_dot_accum -= DOT_INTERVAL
			_tick_dot()


## Jeden tyk wszystkich aktywnych DoT (burn/poison/bleed) na wspólnym interwale. mag = DPS.
func _tick_dot() -> void:
	if DamageService == null:
		return
	for kind in [Kind.BURN, Kind.POISON, Kind.BLEED]:
		if not _effects.has(kind):
			continue
		var e: Dictionary = _effects[kind]
		var per_tick := float(e["mag"]) * DOT_INTERVAL
		DamageService.apply_dot(_host, per_tick, KIND_ELEMENT.get(kind, &""), e.get("source", null))
		if _health != null and _health.is_dead:
			return
