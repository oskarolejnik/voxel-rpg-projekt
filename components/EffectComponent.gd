class_name EffectComponent
extends Node
## EffectComponent.gd — LOOT Faza 4+5: wykonawca PROCÓW wyposażenia i setów (EffectResource). Sibling
## encji, bliźniak StatusEffectComponent. HOST-AUTHORITATIVE.
##
## Trzy szyny wyzwalaczy:
##   • DamageService.hit_resolved => ON_HIT / ON_CRIT (was_crit) / ON_KILL (cel padł od ciosu).
##   • HealthComponent.damaged WŁAŚCICIELA => ON_HURT (np. tarcza setu Mur Obrońcy przy niskim HP).
##   • _process (host) => ON_EQUIP_AURA — periodiczny HoT party (Światło Przymierza), bez zdarzenia.
##
## Determinizm co-op: bramka has_state_authority => proki rozstrzyga TYLKO host; szansa z RNGService.combat
## (jeden strumień, jeden autorytet => każdy peer widzi ten sam wynik przez replikację HP/statusów).
## Cooldowny żyją w PAMIĘCI (_cooldowns) — NIGDY w SaveData => zapis round-trip nie niesie stanu proka.
## Skutki idą istniejącymi, replikowanymi kanałami (StatusEffectComponent.apply_element -> DamageService
## .apply_dot + broadcast HP, HealthComponent.heal). Klient NIE losuje i NIE aplikuje — tylko wyświetla.

# payload (StringName) -> element StatusEffectComponent (DoT/chill). Reszta payloadów (heal/aoe) niżej.
const PAYLOAD_ELEMENT := {
	&"burn": &"fire", &"poison": &"poison", &"bleed": &"bleed", &"chill": &"frost", &"frost": &"frost",
}
const AURA_INTERVAL: float = 1.0          # s między tykami aury (ON_EQUIP_AURA HoT)
const SHIELD_HP_FRACTION: float = 0.35    # "tarcza" (payload shield) odpala tylko poniżej tego ułamka HP

var _owner: Node = null
var _inv: Node = null
var _effects: Array[EffectResource] = []          # świeżo z InventoryComponent.collect_effects()
var _auras: Array[EffectResource] = []            # podzbiór ON_EQUIP_AURA (tyka w _process)
var _cooldowns: Dictionary = {}                   # EffectResource -> sekunda gotowości (monotoniczna)
var _aura_accum: float = 0.0


## Wołane przez Main po stworzeniu InventoryComponent. Podpina rebuild listy efektów (na zmianę ekwipunku),
## szynę trafień i szynę obrażeń właściciela (ON_HURT). Idempotentne (bezpieczne przy ponownym wywołaniu).
func setup(owner_node: Node, inv: Node) -> void:
	_owner = owner_node
	_inv = inv
	if inv != null and inv.has_signal("inventory_changed") and not inv.inventory_changed.is_connected(_rebuild):
		inv.inventory_changed.connect(_rebuild)
	if DamageService != null and not DamageService.hit_resolved.is_connected(_on_hit_resolved):
		DamageService.hit_resolved.connect(_on_hit_resolved)
	# ON_HURT — szyna OBRAŻEŃ WŁAŚCICIELA (HealthComponent.damaged), NIE hit_resolved.
	var owner_hp := _find_health(_owner)
	if owner_hp != null and not owner_hp.damaged.is_connected(_on_owner_damaged):
		owner_hp.damaged.connect(_on_owner_damaged)
	_rebuild()


func _rebuild() -> void:
	if _inv != null and _inv.has_method("collect_effects"):
		_effects = _inv.collect_effects()
	else:
		_effects = []
	# Podzbiór aur (ON_EQUIP_AURA) — tykają w _process, nie na zdarzeniu. Reset akumulatora przy zmianie.
	_auras = []
	for e in _effects:
		if e != null and e.trigger == EffectResource.Trigger.ON_EQUIP_AURA:
			_auras.append(e)
	_aura_accum = 0.0
	set_process(not _auras.is_empty())


# ── Szyna trafień (ON_HIT / ON_CRIT / ON_KILL) ───────────────────────────────
func _on_hit_resolved(source: Node, target: Node, _dmg: float, was_crit: bool) -> void:
	if source != _owner or _effects.is_empty():
		return
	# Autorytet: TYLKO host rozstrzyga proki (na kliencie no-op => zero podwójnych/rozjechanych skutków).
	if NetManager != null and not NetManager.has_state_authority(_owner):
		return
	if target == null or not is_instance_valid(target):
		return
	var killed := _target_dead(target)
	for e in _effects:
		if e == null or not _trigger_matches(e, was_crit, killed):
			continue
		if not _try_fire(e):
			continue
		_dispatch(e, target)


# ── Szyna obrażeń właściciela (ON_HURT) ──────────────────────────────────────
func _on_owner_damaged(_amount: float, from: Node, _current_hp: float) -> void:
	if _effects.is_empty():
		return
	if NetManager != null and not NetManager.has_state_authority(_owner):
		return
	for e in _effects:
		if e == null or e.trigger != EffectResource.Trigger.ON_HURT:
			continue
		if not _try_fire(e):
			continue
		# Cel = napastnik `from` (thorns/retaliacja); shield/heal działają na właściciela niezależnie od celu.
		_dispatch(e, from)


# ── Szyna aury (ON_EQUIP_AURA) — periodiczny HoT, host-only ──────────────────
func _process(delta: float) -> void:
	if _auras.is_empty():
		return
	if NetManager != null and not NetManager.has_state_authority(_owner):
		return
	_aura_accum += delta
	if _aura_accum < AURA_INTERVAL:
		return
	_aura_accum -= AURA_INTERVAL
	_aura_tick()


## Jeden tyk wszystkich aur (wydzielone, by test mógł wywołać bez czekania na klatki).
func _aura_tick() -> void:
	for e in _auras:
		if e != null:
			_apply_aura(e)


func _apply_aura(e: EffectResource) -> void:
	# Party HoT: leczy właściciela + sojuszników (grupa "player") w promieniu. magnitude = HP/tyk.
	_heal_owner(e.magnitude)
	if e.radius > 0.0 and _owner is Node3D:
		var center: Vector3 = (_owner as Node3D).global_position
		for node in get_tree().get_nodes_in_group("player"):
			if node == _owner or not (node is Node3D) or not is_instance_valid(node):
				continue
			if (node as Node3D).global_position.distance_to(center) <= e.radius:
				var hp := _find_health(node)
				if hp != null:
					hp.heal(e.magnitude)


func _trigger_matches(e: EffectResource, was_crit: bool, killed: bool) -> bool:
	match e.trigger:
		EffectResource.Trigger.ON_HIT:
			return true
		EffectResource.Trigger.ON_CRIT:
			return was_crit
		EffectResource.Trigger.ON_KILL:
			return killed
		_:
			return false    # ON_HURT (osobna szyna) / ON_DASH / ON_EQUIP_AURA (aura) — nie na szynie trafień


# ── Cooldown + szansa (jeden punkt decyzji, współdzielony przez wszystkie szyny) ──
## Zwraca true i UZBRAJA cooldown gdy efekt ma wystrzelić; false gdy na cooldownie lub szansa nie wyszła.
## chance==1.0 NIE losuje (oszczędza strumień). <1.0 => jeden draw u hosta (determinizm per-seed).
func _try_fire(e: EffectResource) -> bool:
	if not _off_cooldown(e):
		return false
	if e.chance < 1.0 and RNGService != null and RNGService.combat.randf() > e.chance:
		return false
	_arm_cooldown(e)
	return true


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _off_cooldown(e: EffectResource) -> bool:
	return _now() >= float(_cooldowns.get(e, 0.0))


func _arm_cooldown(e: EffectResource) -> void:
	if e.cooldown > 0.0:
		_cooldowns[e] = _now() + e.cooldown


# ── Dyspozytor skutków ───────────────────────────────────────────────────────
func _dispatch(e: EffectResource, target: Node) -> void:
	match e.payload:
		&"burn", &"poison", &"bleed", &"chill", &"frost":
			_apply_status(target, e.payload, e.magnitude, e.duration)
		&"heal":
			_heal_owner(e.magnitude)
		&"shield":
			_shield_owner(e.magnitude)
		&"frost_nova":
			_aoe_status(target, &"frost", e.magnitude, e.duration, e.radius)
		&"fire_nova":
			_aoe_status(target, &"fire", e.magnitude, e.duration, e.radius)
		&"earthquake":
			_aoe_status(target, &"bleed", e.magnitude, e.duration, e.radius)
		_:
			pass    # multishot / dash_charge / aura_crit / haste — rozszerzenia kolejnych faz


func _apply_status(target: Node, payload: StringName, mag: float, dur: float) -> void:
	var status := _find_status(target)
	if status != null:
		status.apply_element(PAYLOAD_ELEMENT.get(payload, &"fire"), mag, dur, _owner)


## AoE: ten sam status na wszystkich wrogach w promieniu od trafionego celu (fire/frost_nova/earthquake).
func _aoe_status(center_target: Node, element: StringName, mag: float, dur: float, radius: float) -> void:
	if radius <= 0.0 or not (center_target is Node3D):
		return
	var center: Vector3 = (center_target as Node3D).global_position
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		if (node as Node3D).global_position.distance_to(center) > radius:
			continue
		var status := _find_status(node)
		if status != null:
			status.apply_element(element, mag, dur, _owner)


func _heal_owner(amount: float) -> void:
	if amount <= 0.0 or _owner == null:
		return
	var hp := _find_health(_owner)
	if hp != null:
		hp.heal(amount)


## "Tarcza" v1 (payload shield) = defensywny burst leczenia, TYLKO gdy właściciel nisko (<35% HP).
## Replikowane przez standardowy broadcast HP. (Pełny system absorbcji to późniejsze rozszerzenie.)
func _shield_owner(amount: float) -> void:
	if amount <= 0.0 or _owner == null:
		return
	var hp := _find_health(_owner)
	if hp == null or hp.max_hp() <= 0.0:
		return
	if hp.current_hp / hp.max_hp() < SHIELD_HP_FRACTION:
		hp.heal(amount)


# ── Pomocnicze (lokalizacja komponentów-dzieci) ──────────────────────────────
func _find_status(node: Node) -> StatusEffectComponent:
	if node == null:
		return null
	for c in node.get_children():
		if c is StatusEffectComponent:
			return c
	return null


func _find_health(node: Node) -> HealthComponent:
	if node == null:
		return null
	for c in node.get_children():
		if c is HealthComponent:
			return c
	return null


func _target_dead(target: Node) -> bool:
	var hp := _find_health(target)
	return hp != null and hp.is_dead
