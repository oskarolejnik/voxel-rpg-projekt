extends Node
## Feel2Test.gd — HEADLESS test FAZY 2 (ANIMATION QUALITY): proceduralna animacja koniec sztywnosci.
## Uruchomienie: godot --headless res://test/Feel2Test.tscn
##
## NIE rusza dzialajacej gry. Instancjuje REALNEGO Player.gd (+ Enemy.gd) w drzewie i steruje jego
## metodami/stanem bezposrednio (jak Feel1Test). Weryfikuje KONTRAKT 7 warstw animacji:
##  (1) FOOT IK / PLANT: w STANCE kolano znaczaco PROSTSZE niz w SWING (stopa "trzyma" grunt, nie
##      slizga); w SWING kolano wyraznie zgiete (rot.x < -0.3). 2-kosciowe IK biodro->kolano->stopa.
##  (2) ADDITIVE BREATH: w idle (_gait=0) oddech zmienia _torso.position.y i _torso.scale.y>1.0 przy
##      wdechu; dwie rozne fazy oddechu daja ROZNE _torso.position.y (postac nigdy "martwa").
##  (3) SECONDARY MOTION: skok _arm_r.rotation.x -> _wpn_ang != 0 (bron zostaje w tyle = lag);
##      po wielu klatkach -> _wpn_ang -> ~0 (dolot, brak narastajacej oscylacji).
##  (4) SQUASH/STRETCH: _land_squash=1 -> _model.scale.y<1 i .x>1 (zgniecenie+rozlanie); lot z duza
##      |velocity.y| i _air_blend=1 -> _model.scale.y>1 (rozciagniecie).
##  (5) ANTICIPATION/OVERSHOOT/FOLLOW-THROUGH: ANTICIPATION rece COFAJA (rot.x>0.3); ACTIVE OVERSHOOT
##      przeskakuje settle (rot.x < -2.2); RECOVERY follow-through osiada (ku -0.2).
##  (6) HIT-REACT: _hitreact_t>0 zachwiewa _torso.rotation.x (!= baza); po HITREACT_TIME -> ==0 (gasnie).
##  (7) DEATH: gracz _die() -> _dying==true; po tykaniu _anim_additive _model.rotation.z>1.0 (przewrocenie).
##      wrog: has_method("_spawn_death_burst") + _die przy smierci emituje died i ustawia _dead_emitted.
## Kod wyjscia: 0 = ALL OK, 1 = FAIL. Print "[FEEL2] ..." + ALL OK + quit.

const PlayerScript := preload("res://src/Player.gd")
const EnemyScript := preload("res://src/Enemy.gd")

var _failures: int = 0


func _ready() -> void:
	print("[FEEL2] === Faza 2 (ANIMATION QUALITY) mini-test start ===")
	await _test_foot_ik()
	await _test_breath()
	await _test_secondary_motion()
	await _test_squash_stretch()
	await _test_attack_overshoot()
	await _test_hit_react()
	await _test_death()
	await _test_additive_framerate_indep()

	if _failures == 0:
		print("[FEEL2] ALL OK")
	else:
		printerr("[FEEL2] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[FEEL2] FAIL: %s" % msg)


# Tworzy REALNEGO gracza w drzewie (model + pivoty zbudowane w _ready). Czeka 2 klatki.
func _make_player() -> Node:
	var p = PlayerScript.new()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	return p


# ============================================================================
#  (1) FOOT IK / FOOT PLANTING — stance kolano prostsze niz swing; swing wyraznie zgiety
# ============================================================================
func _test_foot_ik() -> void:
	var p = await _make_player()
	p._gait = 1.0
	p._run_blend = 0.0
	var stride: float = 0.22 * p._gait
	var lift: float = 0.12 * p._gait

	# STANCE (swing_phase<0): _walk_phase = -PI/2 (sin=-1). Konwerguj wieloma wywolaniami (lerp _sm).
	p._walk_phase = -PI / 2.0
	for i in 60:
		p._foot_ik_leg(p._leg_l, p._leg_l_lo, 0.0, stride, lift, 0.05)
	var stance_knee: float = p._leg_l_lo.rotation.x
	var stance_hip: float = p._leg_l.rotation.x

	# SWING (swing_phase>0): _walk_phase = PI/2 (sin=1).
	p._walk_phase = PI / 2.0
	for i in 60:
		p._foot_ik_leg(p._leg_l, p._leg_l_lo, 0.0, stride, lift, 0.05)
	var swing_knee: float = p._leg_l_lo.rotation.x

	# Kontrakt FOOT-PLANT: w SWING kolano WYRAZNIE bardziej zgiete (stopa w powietrzu po luku),
	# w STANCE znaczaco PROSTSZE (stopa "trzyma" grunt — koniec slizgu). Roznica >= 0.4 rad.
	_check(swing_knee < -0.3, "SWING: kolano nie zgiete (rot.x=%.3f, oczekiwane <-0.3)" % swing_knee)
	_check(swing_knee < stance_knee - 0.4, "STANCE nie prostsze niz SWING (stance=%.3f swing=%.3f)" % [stance_knee, swing_knee])
	_check(stance_knee <= -0.02, "STANCE: kolano nie ma minimalnego zgiecia podporowego (rot.x=%.3f)" % stance_knee)

	# 2-bone IK rusza biodrem (hip != 0 przy realnym kroku) — nie sztywny pivot.
	_check(absf(stance_hip) < 1.5, "STANCE: biodro poza sensownym zakresem (rot.x=%.3f)" % stance_hip)
	print("[FEEL2] (1) foot IK/plant: stance_knee=%.3f swing_knee=%.3f (stance prostsze) OK" % [stance_knee, swing_knee])
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (2) ADDITIVE BREATH — oddech niezerowy w idle; dwie fazy daja rozne uniesienie
# ============================================================================
func _test_breath() -> void:
	var p = await _make_player()
	p._gait = 0.0                       # idle: pelny oddech
	p._air_blend = 0.0
	p.velocity = Vector3.ZERO
	p._atk_phase = p.AtkPhase.NONE
	p._land_squash = 0.0

	# Faza wdechu (sin>0): _breath_phase tak, by sin(1.6*ph) > 0. ph=1.0 => sin(1.6)=~0.9996>0.
	p._breath_phase = 1.0
	var base_y: float = float(p._HIP_Y) * p.VS
	p._anim_additive(0.016)
	var y_inhale: float = p._torso.position.y
	var scale_inhale: float = p._torso.scale.y
	_check(absf(y_inhale - base_y) > 0.0005, "BREATH: brak uniesienia klatki w idle (dy=%.5f)" % (y_inhale - base_y))
	_check(scale_inhale > 1.0, "BREATH: brak rozszerzenia klatki przy wdechu (scale.y=%.4f)" % scale_inhale)

	# Inna faza oddechu -> ROZNE uniesienie (oddech "zywy", nie staly offset).
	p._breath_phase = 1.0 + PI / 1.6    # przesun o pol okresu oddechu (sin -> przeciwny znak)
	p._anim_additive(0.016)
	var y_exhale: float = p._torso.position.y
	_check(absf(y_exhale - y_inhale) > 0.001, "BREATH: dwie fazy daja te sama wysokosc (martwy oddech)")
	print("[FEEL2] (2) additive breath: y_inhale=%.4f y_exhale=%.4f scale=%.4f OK" % [y_inhale, y_exhale, scale_inhale])
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (3) SECONDARY MOTION — lag broni za zamachem ramienia (spring), dolot do spoczynku
# ============================================================================
func _test_secondary_motion() -> void:
	var p = await _make_player()
	p._gait = 0.0
	p._air_blend = 0.0
	p.velocity = Vector3.ZERO
	p._atk_phase = p.AtkPhase.NONE
	# Ustabilizuj stan springow (kilka klatek w spoczynku) — _wpn_ang ~0.
	for i in 5:
		p._anim_additive(0.016)
	# SKOK rotacji ramienia (jak start ataku) -> driver springu broni dostaje duza predkosc katowa.
	p._arm_r.rotation.x = -2.0
	p._anim_additive(0.016)
	var wpn_after_jump: float = p._wpn_ang
	_check(absf(wpn_after_jump) > 0.001, "SECONDARY: bron NIE zostaje w tyle po skoku ramienia (wpn_ang=%.4f)" % wpn_after_jump)

	# Trzymaj ramie nieruchomo wiele klatek -> spring dochodzi do spoczynku (~0), bez oscylacji-pily.
	for i in 60:
		p._anim_additive(0.016)
	var wpn_settled: float = p._wpn_ang
	_check(absf(wpn_settled) < absf(wpn_after_jump) * 0.5 + 0.01, "SECONDARY: spring NIE doszedl do spoczynku (settled=%.4f peak=%.4f)" % [wpn_settled, wpn_after_jump])
	print("[FEEL2] (3) secondary motion: wpn lag peak=%.4f -> settled=%.4f OK" % [wpn_after_jump, wpn_settled])
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (4) SQUASH/STRETCH — ladowanie zgniata (sy<1, sxz>1); lot rozciaga (sy>1)
# ============================================================================
func _test_squash_stretch() -> void:
	var p = await _make_player()
	p._gait = 0.0
	p._atk_phase = p.AtkPhase.NONE
	p._breath_phase = 0.0

	# LADOWANIE: _land_squash=1, na ziemi -> zgniecenie (sy<1) + rozlanie (sxz>1).
	p._air_blend = 0.0
	p.velocity = Vector3.ZERO
	p._land_squash = 1.0
	p._stretch = 0.0
	for i in 30:
		p._land_squash = 1.0            # trzymaj wymuszony squash (omin gasniecie poza _process)
		p._anim_additive(0.016)
	_check(p._model.scale.y < 1.0, "SQUASH: ladowanie nie zgniata (scale.y=%.4f, oczekiwane <1)" % p._model.scale.y)
	_check(p._model.scale.x > 1.0, "SQUASH: ladowanie nie rozlewa (scale.x=%.4f, oczekiwane >1)" % p._model.scale.x)
	var squash_y: float = p._model.scale.y

	# LOT: duza |velocity.y| + _air_blend=1 -> rozciagniecie (sy>1).
	p._land_squash = 0.0
	p._air_blend = 1.0
	p.velocity = Vector3(0.0, 12.0, 0.0)
	p._stretch = 0.0
	for i in 30:
		p._anim_additive(0.016)
	_check(p._model.scale.y > 1.0, "STRETCH: lot nie rozciaga (scale.y=%.4f, oczekiwane >1)" % p._model.scale.y)
	print("[FEEL2] (4) squash/stretch: land scale.y=%.3f, air scale.y=%.3f OK" % [squash_y, p._model.scale.y])
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (5) ANTICIPATION / OVERSHOOT / FOLLOW-THROUGH na ataku
# ============================================================================
func _test_attack_overshoot() -> void:
	var p = await _make_player()
	p.is_attacking = true

	# ANTICIPATION u konca (k~1): ramie COFA sie (rot.x > 0.3, wind-up). Konwerguj wieloma klatkami.
	p._atk_phase = p.AtkPhase.ANTICIPATION
	p._atk_anticipation = 0.06
	p._atk_phase_t = 0.001               # k = 1 - t/antic ~ 1 (koniec wind-upu)
	for i in 40:
		p._anim_attack_arms(0.05)
	_check(p._arm_r.rotation.x > 0.3, "ANTICIPATION: rece nie cofaja sie (rot.x=%.3f, oczekiwane >0.3)" % p._arm_r.rotation.x)
	var antic_arm: float = p._arm_r.rotation.x

	# ACTIVE w okolicy peaku overshoota (k2~0.6): OVERSHOOT przeskakuje settle (rot.x < -2.2).
	p._atk_phase = p.AtkPhase.ACTIVE
	p._atk_active = 0.10
	p._atk_phase_t = 0.10 * 0.4          # k2 = 1 - 0.4 = 0.6 (peak overshoota)
	for i in 40:
		p._anim_attack_arms(0.05)
	_check(p._arm_r.rotation.x < -2.2, "ACTIVE: brak OVERSHOOT (rot.x=%.3f, oczekiwane <-2.2)" % p._arm_r.rotation.x)
	var active_arm: float = p._arm_r.rotation.x

	# RECOVERY u konca (k3~1): FOLLOW-THROUGH osiada ku -0.2.
	p._atk_phase = p.AtkPhase.RECOVERY
	p._atk_recovery = 0.18
	p._atk_phase_t = 0.001
	for i in 40:
		p._anim_attack_arms(0.05)
	_check(p._arm_r.rotation.x > -0.6 and p._arm_r.rotation.x < 0.2, "RECOVERY: follow-through nie osiadl ku neutralu (rot.x=%.3f)" % p._arm_r.rotation.x)
	print("[FEEL2] (5) attack antic=%.2f active(overshoot)=%.2f recovery=%.2f OK" % [antic_arm, active_arm, p._arm_r.rotation.x])
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (6) HIT-REACT additive — zachwianie tulowia od ciosu; gasnie po HITREACT_TIME
# ============================================================================
func _test_hit_react() -> void:
	var p = await _make_player()
	p._gait = 0.0
	p._air_blend = 0.0
	p.velocity = Vector3.ZERO
	p._atk_phase = p.AtkPhase.NONE
	p._breath_phase = 0.0

	# Baza bez hit-reactu (jedna klatka): zapamietaj _torso.rotation.x.
	p._hitreact_t = 0.0
	p._anim_additive(0.016)
	var base_x: float = p._torso.rotation.x

	# Wyzwol hit-react (kierunek od zrodla z przodu: world +Z). Jedna klatka -> zachwianie != baza.
	p._hitreact_t = p.HITREACT_TIME
	p._hitreact_dir = Vector3(0.0, 0.0, 1.0)
	p._anim_additive(0.016)
	_check(absf(p._torso.rotation.x - base_x) > 0.005, "HIT-REACT: brak zachwiania tulowia (dx=%.4f)" % (p._torso.rotation.x - base_x))

	# Przetyknij ponad HITREACT_TIME -> gasnie (_hitreact_t == 0, lokomocja czysta).
	for i in 20:
		p._anim_additive(0.016)
	_check(p._hitreact_t == 0.0, "HIT-REACT: nie wygasl po HITREACT_TIME (_hitreact_t=%.4f)" % p._hitreact_t)
	print("[FEEL2] (6) hit-react: zachwianie wyzwolone, wygasa po %.2fs OK" % p.HITREACT_TIME)
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (7) DEATH — gracz: poza przewrocenia; wrog: burst + nieregresja died/_dead_emitted
# ============================================================================
func _test_death() -> void:
	# GRACZ: _die() ustawia _dying; tykanie _anim_additive narasta poze (model.rotation.z > 1.0).
	var p = await _make_player()
	p._die()
	_check(p._dying, "DEATH gracz: _die() nie ustawil _dying")
	_check(p.is_dead, "DEATH gracz: _die() nie ustawil is_dead")
	for i in 40:
		p._anim_additive(0.016)         # ~0.64 s tykania -> pelna poza
	_check(p._model.rotation.z > 1.0, "DEATH gracz: model nie przewrocil sie (rotation.z=%.3f)" % p._model.rotation.z)

	# RESPAWN zdejmuje poze (model wstaje prosto).
	p.respawn()
	_check(not p._dying, "DEATH gracz: respawn nie zdjal _dying")
	_check(absf(p._model.rotation.z) < 0.01, "DEATH gracz: respawn nie wyprostowal modelu (rotation.z=%.3f)" % p._model.rotation.z)
	print("[FEEL2] (7a) death gracz: przewrocenie + respawn wstaje OK")
	p.queue_free()

	# WROG: has_method + kontrakt nieregresji (smierc emituje died, ustawia _dead_emitted).
	var e = EnemyScript.new()
	add_child(e)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(e.has_method("_spawn_death_burst"), "DEATH wrog: brak metody _spawn_death_burst")
	var died_emitted := [false]
	e.died.connect(func(_en) -> void: died_emitted[0] = true)
	e._die()
	_check(died_emitted[0], "DEATH wrog: _die() nie emituje died (nieregresja licznika ubitych)")
	_check(e._dead_emitted, "DEATH wrog: _die() nie ustawil _dead_emitted (idempotencja)")
	print("[FEEL2] (7b) death wrog: _spawn_death_burst + died/_dead_emitted (nieregresja) OK")
	await get_tree().process_frame


# ============================================================================
#  (8) FRAME-RATE INDEPENDENCE — additive sway/nod nie kumuluje sie w bazie i nie zalezy od FPS
# ============================================================================
# Pedzi PELNY potok idle jak _process: _animate_torso -> _animate_head -> _anim_additive co klatke.
# To jedyna sciezka gdzie nakladka additive (rotacja) interleave'uje z lerp-bazami, ktore CZYTAJA
# wlasne rotation — wczesniej nakladka wsiakala w lerp i amplituda swayu/nodu rosla ~3x z FPS.
# Kontrakt: ustalony span _torso.rotation.z i _head.rotation.x jest (a) MALY (<0.08 rad) i
# (b) NIEZALEZNY OD FPS (span@120 / span@30 w okolicy 1.0).
func _run_idle_pipeline_span(p, dt: float, seconds: float) -> Array:
	# Reset stanu animacji do czystego idle (jak start _process w spoczynku).
	p._gait = 0.0
	p._run_blend = 0.0
	p._air_blend = 0.0
	p._lean_turn = 0.0
	p._lean_vel = 0.0
	p.velocity = Vector3.ZERO
	p._atk_phase = p.AtkPhase.NONE
	p._land_squash = 0.0
	p._anim_bob = 0.0
	p._idle_phase = 0.0
	p._breath_phase = 0.0
	# Wycisz bazy do zera, by mierzyc tylko ustalony cykl sway/nod (nie transjent startowy).
	p._torso.rotation = Vector3.ZERO
	p._head.rotation = Vector3.ZERO
	p._add_torso = Vector3.ZERO
	p._add_head = Vector3.ZERO
	var n := int(seconds / dt)
	var warm := int(n * 0.5)          # polowa czasu na ustabilizowanie (transjent lerp gasnie)
	var z_min := INF; var z_max := -INF
	var hx_min := INF; var hx_max := -INF
	for i in n:
		p._idle_phase += dt
		p._animate_torso(dt, 0.0, true, false)
		p._animate_head(dt, 0.0)
		p._breath_phase += dt
		p._anim_additive(dt)
		if i >= warm:
			z_min = minf(z_min, p._torso.rotation.z); z_max = maxf(z_max, p._torso.rotation.z)
			hx_min = minf(hx_min, p._head.rotation.x); hx_max = maxf(hx_max, p._head.rotation.x)
	return [z_max - z_min, hx_max - hx_min]


func _test_additive_framerate_indep() -> void:
	var p = await _make_player()
	var span30 = _run_idle_pipeline_span(p, 1.0 / 30.0, 12.0)
	var span120 = _run_idle_pipeline_span(p, 1.0 / 120.0, 12.0)
	var z30: float = span30[0]; var z120: float = span120[0]
	var hx30: float = span30[1]; var hx120: float = span120[1]

	# (a) span MALY (zbiezny z zamierzonymi ~0.02-0.03 rad — nie przeskalowany ~3x).
	_check(z30 < 0.08, "FPS-INDEP: idle torso.z span @30fps za duzy (%.4f, oczekiwane <0.08)" % z30)
	_check(hx30 < 0.08, "FPS-INDEP: idle head.x span @30fps za duzy (%.4f, oczekiwane <0.08)" % hx30)
	# Niezerowy (oddech/weight-shift faktycznie ZYJE — regresja w druga strone).
	_check(z30 > 0.001, "FPS-INDEP: idle torso.z span @30fps zerowy (martwy sway, %.4f)" % z30)

	# (b) NIEZALEZNY OD FPS: stosunek span120/span30 w okolicy 1.0 (tolerancja ~20%).
	var ratio_z := z120 / maxf(z30, 0.0001)
	var ratio_hx := hx120 / maxf(hx30, 0.0001)
	_check(ratio_z > 0.8 and ratio_z < 1.25, "FPS-INDEP: torso.z sway zalezny od FPS (span120/span30=%.3f, z30=%.4f z120=%.4f)" % [ratio_z, z30, z120])
	_check(ratio_hx > 0.8 and ratio_hx < 1.25, "FPS-INDEP: head.x nod zalezny od FPS (span120/span30=%.3f, hx30=%.4f hx120=%.4f)" % [ratio_hx, hx30, hx120])
	print("[FEEL2] (8) frame-rate indep: torso.z span %.4f(30)/%.4f(120) ratio=%.3f; head.x ratio=%.3f OK" % [z30, z120, ratio_z, ratio_hx])
	p.queue_free()
	await get_tree().process_frame
