extends Node
## StatusEffectTest.gd — weryfikuje system statusów (audyt #5): DoT/chill/stun/weaken + feed + wiring.
## Uruchomienie: godot --headless res://test/StatusEffectTest.tscn
##
##  (1) BURN DoT: nałożony burn tyka obrażenia HP (przez DamageService.apply_dot, host-only).
##  (2) CHILL: speed_mult() < 1.0 gdy chill aktywny.
##  (3) STUN: is_stunned() true; po wygaśnięciu false.
##  (4) DamageService._apply_status: HitData.on_hit_effects -> status na celu (przez request_hit).
##  (5) HitData round-trip: on_hit_effects przeżywa to_dict/from_dict (co-op RPC).
##  (6) FEED wroga: Enemy z elementem (fire) buduje on_hit_effects w _build_hit.
##  (7) FEED gracza: stat żywiołowy (fire_damage z afiksu) -> on_hit_effects w Player._build_hit.
##  (8) WEAKEN: damage_taken_mult() > 1.0 zwiększa obrażenia DoT.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL.

const EnemyScript := preload("res://src/Enemy.gd")
const PlayerScript := preload("res://src/Player.gd")

var _failures := 0
const K := StatusEffectComponent.Kind


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[ST] FAIL: %s" % msg)


func _make_enemy() -> Enemy:
	var e: Enemy = EnemyScript.new()
	add_child(e)               # _ready -> _build_components: _health + _status
	return e


func _ready() -> void:
	print("[ST] === Status effect test ===")
	if EnemyDB != null:
		EnemyDB.reload()

	# (1) BURN DoT
	var e := _make_enemy()
	_check(e._status != null, "Enemy nie zbudował StatusEffectComponent")
	if e._status != null:
		var hp0: float = e._health.current_hp
		e._status.apply(K.BURN, 20.0, 3.0, null)        # 20 DPS na 3 s
		e._status._physics_process(0.6)                  # 0.6 >= DOT_INTERVAL(0.5) -> 1 tyk -> 10 dmg
		_check(e._health.current_hp < hp0, "BURN nie zadał obrażeń (HP %.1f -> %.1f)" % [hp0, e._health.current_hp])
		_check(absf((hp0 - e._health.current_hp) - 10.0) < 0.5, "BURN tyk != 10 (ubytek %.1f)" % (hp0 - e._health.current_hp))
		print("[ST] (1) BURN DoT tyka HP OK")

	# (2) CHILL
	var e2 := _make_enemy()
	e2._status.apply(K.CHILL, 0.0, 2.0, null)
	_check(e2._status.speed_mult() < 1.0, "CHILL nie spowalnia (speed_mult=%.2f)" % e2._status.speed_mult())
	print("[ST] (2) CHILL speed_mult < 1 OK")

	# (3) STUN + wygaśnięcie
	var e3 := _make_enemy()
	e3._status.apply(K.STUN, 1.0, 0.5, null)
	_check(e3._status.is_stunned(), "STUN nie ustawił is_stunned")
	e3._status._physics_process(0.6)                     # > 0.5 s -> wygasa
	_check(not e3._status.is_stunned(), "STUN nie wygasł po czasie")
	print("[ST] (3) STUN + wygaśnięcie OK")

	# (4) DamageService._apply_status przez request_hit
	var e4 := _make_enemy()
	await get_tree().process_frame                       # hurtbox/health w drzewie
	var hit := HitData.new()
	hit.source = self
	hit.base_damage = 0.0                                 # izolujemy STATUS (nie HP)
	hit.crit_chance = 0.0
	hit.on_hit_effects = [{ "kind": &"poison", "mag": 8.0, "dur": 3.0 }]
	DamageService.request_hit(self, e4, hit)
	_check(e4._status.has(K.POISON), "request_hit nie nałożył statusu z on_hit_effects (poison)")
	print("[ST] (4) DamageService._apply_status (on_hit_effects -> status) OK")

	# (5) HitData round-trip
	var h := HitData.new()
	h.on_hit_effects = [{ "kind": &"fire", "mag": 5.0, "dur": 2.0 }]
	var h2 := HitData.from_dict(h.to_dict())
	_check(h2.on_hit_effects.size() == 1, "on_hit_effects nie przeżył round-trip (rozmiar %d)" % h2.on_hit_effects.size())
	if h2.on_hit_effects.size() == 1:
		_check(StringName(h2.on_hit_effects[0]["kind"]) == &"fire", "round-trip zgubił kind")
		_check(absf(float(h2.on_hit_effects[0]["mag"]) - 5.0) < 0.001, "round-trip zgubił mag")
	print("[ST] (5) HitData on_hit_effects round-trip OK")

	# (6) FEED wroga (element -> on_hit_effects)
	var e5 := _make_enemy()
	e5.element = &"fire"
	var ehit := e5._build_hit()
	var found_fire := false
	for fx in ehit.on_hit_effects:
		if StringName(fx.get("kind", &"")) == &"fire":
			found_fire = true
	_check(found_fire, "Enemy z element=fire nie dołożył burn do on_hit_effects")
	print("[ST] (6) feed wroga (element -> status) OK")

	# (7) FEED gracza (fire_damage z afiksu -> on_hit_effects)
	var p = PlayerScript.new()
	add_child(p)
	await get_tree().process_frame
	if p._stats != null:
		var pmods: Array[StatModifier] = [StatModifier.make(&"fire_damage", StatModifier.Op.FLAT, 8.0)]
		p._stats.add_modifiers(pmods)
		var phit := p._build_hit()
		var pf := false
		for fx in phit.on_hit_effects:
			if StringName(fx.get("kind", &"")) == &"fire":
				pf = true
		_check(pf, "Player z fire_damage nie dołożył burn do on_hit_effects")
		print("[ST] (7) feed gracza (fire_damage -> status) OK")
	p.queue_free()

	# (8) WEAKEN zwiększa obrażenia DoT
	var e6 := _make_enemy()
	e6._status.apply(K.WEAKEN, 1.0, 5.0, null)
	_check(e6._status.damage_taken_mult() > 1.0, "WEAKEN nie zwiększa damage_taken_mult")
	var hpw0: float = e6._health.current_hp
	e6._status.apply(K.BURN, 20.0, 3.0, null)
	e6._status._physics_process(0.6)                     # 10 base * (1+WEAKEN_AMP) = 12
	var dealt := hpw0 - e6._health.current_hp
	_check(dealt > 10.5, "WEAKEN nie wzmocnił DoT (ubytek %.1f, oczekiwane >10.5)" % dealt)
	print("[ST] (8) WEAKEN wzmacnia DoT OK")

	e.queue_free(); e2.queue_free(); e3.queue_free(); e4.queue_free(); e5.queue_free(); e6.queue_free()
	if _failures == 0:
		print("[ST] ALL OK")
	else:
		printerr("[ST] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
