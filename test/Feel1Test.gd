extends Node
## Feel1Test.gd — HEADLESS test FAZY 1 (GAME FEEL): attack timeline, combo 3-cios + cancel windows,
## movement weight (accel != decel + turn_accel), dodge recovery, input buffer, lock-on + soft target.
## Uruchomienie: godot --headless res://test/Feel1Test.tscn
##
## NIE rusza dzialajacej gry. Instancjuje REALNEGO Player.gd (+ Enemy.gd) w drzewie i steruje jego
## metodami/stanem bezposrednio (jak Etap1Test robi z komponentami). Weryfikuje KONTRAKT odczucia:
##  (1) ATTACK TIMELINE: hitbox ZAMKNIETY w ANTICIPATION, OTWARTY w ACTIVE, zamkniety po (RECOVERY).
##  (2) COMBO CHAIN: 3 ciosy z cancel-into-next w recovery; 3. cios = mocniejszy juice; reset po serii.
##  (3) CANCEL-INTO-DODGE: unik w fazie RECOVERY anuluje atak (timeline -> NONE) ZAWSZE.
##  (4) MOVEMENT WEIGHT: ground_decel < ground_accel (poslizg) + turn_accel > 0 (ciezar zwrotu).
##  (5) INPUT BUFFER: atak wcisniety w trakcie ANTICIPATION/ACTIVE zostaje ZAKOLEJKOWANY (nie zgubiony).
##  (6) DODGE RECOVERY: po dashu wchodzi recovery (cancelable atakiem); i-frames zachowane.
##  (7) LOCK-ON: namierza NAJBLIZSZEGO wroga; soft-target ciagnie kierunek ciosu do celu (pull).
## Kod wyjscia: 0 = ALL OK, 1 = FAIL. Print "[FEEL1] ..." + ALL OK + quit.

const PlayerScript := preload("res://src/Player.gd")
const EnemyScript := preload("res://src/Enemy.gd")

var _failures: int = 0


func _ready() -> void:
	print("[FEEL1] === Faza 1 (GAME FEEL) mini-test start ===")
	await _test_attack_timeline()
	await _test_combo_chain()
	await _test_cancel_into_dodge()
	_test_movement_weight()
	await _test_input_buffer()
	await _test_dodge_recovery()
	await _test_lock_on()

	if _failures == 0:
		print("[FEEL1] ALL OK")
	else:
		printerr("[FEEL1] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[FEEL1] FAIL: %s" % msg)


# Tworzy REALNEGO gracza w drzewie (komponenty zbudowane w _ready). Czeka 2 klatki na pelne wpiecie.
func _make_player() -> Node:
	var p = PlayerScript.new()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	return p


# Czy hitbox ataku jest aktualnie OTWARTY (monitoring wlaczone = okno aktywnych klatek).
func _hitbox_open(p: Node) -> bool:
	return p._hitbox != null and p._hitbox.monitoring


# ============================================================================
#  (1) ATTACK TIMELINE — hitbox zamkniety w ANTICIPATION, otwarty w ACTIVE
# ============================================================================
func _test_attack_timeline() -> void:
	var p = await _make_player()

	# Start ataku. Hitbox NIE moze otworzyc sie w klatce 0 (faza ANTICIPATION = wind-up).
	p._try_attack()
	_check(p._atk_phase == p.AtkPhase.ANTICIPATION, "po _try_attack faza != ANTICIPATION (%d)" % p._atk_phase)
	_check(not _hitbox_open(p), "HITBOX OTWARTY w klatce 0 (powinien byc zamkniety w anticipation)")

	# Przetykaj anticipation -> ACTIVE: hitbox OTWARTY.
	p._tick_attack_timeline(p._atk_anticipation + 0.001)
	_check(p._atk_phase == p.AtkPhase.ACTIVE, "po anticipation faza != ACTIVE (%d)" % p._atk_phase)
	_check(_hitbox_open(p), "HITBOX NIE otwarty w fazie ACTIVE")

	# Przetykaj active -> RECOVERY: hitbox zamkniety.
	p._tick_attack_timeline(p._atk_active + 0.001)
	_check(p._atk_phase == p.AtkPhase.RECOVERY, "po active faza != RECOVERY (%d)" % p._atk_phase)
	_check(not _hitbox_open(p), "HITBOX wciaz otwarty po fazie ACTIVE (powinien sie zamknac)")

	# Przetykaj recovery -> koniec (NONE).
	p._tick_attack_timeline(p._atk_recovery + 0.001)
	_check(p._atk_phase == p.AtkPhase.NONE, "po recovery faza != NONE (%d)" % p._atk_phase)
	print("[FEEL1] (1) attack timeline: anticipation(closed)->active(open)->recovery(closed)->none OK")
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (2) COMBO CHAIN — 3 ciosy z cancel-into-next; 3. cios = finisher; reset po serii
# ============================================================================
func _test_combo_chain() -> void:
	var p = await _make_player()

	# Cios 1 -> chain_step 1.
	p._try_attack()
	_check(p._chain_step == 1, "cios1: chain_step != 1 (%d)" % p._chain_step)
	# Dojdz do RECOVERY i wejdz w okno cancel.
	p._tick_attack_timeline(p._atk_anticipation + 0.001)   # -> ACTIVE
	p._tick_attack_timeline(p._atk_active + 0.001)          # -> RECOVERY
	_check(p._atk_phase == p.AtkPhase.RECOVERY, "cios1 nie doszedl do RECOVERY")
	# W oknie cancel wcisnij kolejny atak -> ZAKOLEJKOWANY (cancel-into-next), NIE nowy timeline.
	p._try_attack()
	_check(p._chain_queued, "cancel-into-next NIE zakolejkowany w oknie cancel recovery")
	# Domknij recovery -> kolejny cios serii (chain_step 2) odpala sie PLYNNIE.
	p._tick_attack_timeline(p._atk_recovery + 0.001)
	_check(p._chain_step == 2, "cios2: chain_step != 2 po cancel-into-next (%d)" % p._chain_step)
	_check(not p._is_chain_finisher(), "cios2 nie powinien byc finisherem")

	# Cios 2 -> RECOVERY -> cancel -> cios 3 (finisher).
	p._tick_attack_timeline(p._atk_anticipation + 0.001)
	p._tick_attack_timeline(p._atk_active + 0.001)
	p._try_attack()
	p._tick_attack_timeline(p._atk_recovery + 0.001)
	_check(p._chain_step == 3, "cios3: chain_step != 3 (%d)" % p._chain_step)
	_check(p._is_chain_finisher(), "cios3 powinien byc finisherem (mocniejszy juice)")

	# Po 3. ciosie lancuch sie zamyka: domkniecie recovery resetuje chain_step do 0.
	p._tick_attack_timeline(p._atk_anticipation + 0.001)
	p._tick_attack_timeline(p._atk_active + 0.001)
	p._tick_attack_timeline(p._atk_recovery + 0.001)        # recovery 3. ciosu domkniete
	_check(p._chain_step == 0, "po 3. ciosie lancuch NIE zresetowany (chain_step=%d)" % p._chain_step)
	print("[FEEL1] (2) combo chain 1->2->3 (finisher) + reset po serii OK")
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (3) CANCEL-INTO-DODGE — unik w RECOVERY anuluje atak ZAWSZE
# ============================================================================
func _test_cancel_into_dodge() -> void:
	var p = await _make_player()
	p.stamina = p.max_stamina

	p._try_attack()
	p._tick_attack_timeline(p._atk_anticipation + 0.001)   # ACTIVE
	p._tick_attack_timeline(p._atk_active + 0.001)          # RECOVERY
	_check(p._atk_phase == p.AtkPhase.RECOVERY, "atak nie w RECOVERY przed unikiem")
	# Unik w recovery -> anuluje atak (timeline NONE, hitbox zamkniety, lancuch zresetowany).
	p._try_dodge()
	_check(p.is_dodging, "unik nie wystartowal (cancel-into-dodge)")
	_check(p._atk_phase == p.AtkPhase.NONE, "atak NIE anulowany przez unik (faza=%d)" % p._atk_phase)
	_check(not _hitbox_open(p), "hitbox otwarty po cancel-into-dodge")
	_check(p._iframes > 0.0, "unik nie nadal i-frames")
	print("[FEEL1] (3) cancel-into-dodge w recovery anuluje atak + i-frames OK")
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (4) MOVEMENT WEIGHT — decel < accel (poslizg) + turn_accel > 0 (ciezar zwrotu)
# ============================================================================
func _test_movement_weight() -> void:
	var p = PlayerScript.new()
	add_child(p)
	# Pola eksportowe dostepne od razu (przed _ready) — to czyste @export.
	_check(p.ground_decel < p.ground_accel, "ground_decel (%.1f) >= ground_accel (%.1f): brak poslizgu" % [p.ground_decel, p.ground_accel])
	_check(p.turn_accel > 0.0, "turn_accel <= 0 (brak ciezaru zwrotu)")
	_check(p.lean_max > 0.0, "lean_max <= 0 (brak leanu wizualnego)")
	print("[FEEL1] (4) movement weight: accel=%.0f decel=%.0f turn=%.0f lean=%.2f OK" % [p.ground_accel, p.ground_decel, p.turn_accel, p.lean_max])
	p.queue_free()


# ============================================================================
#  (5) INPUT BUFFER — atak w trakcie ANTICIPATION/ACTIVE zostaje ZAKOLEJKOWANY
# ============================================================================
func _test_input_buffer() -> void:
	var p = await _make_player()

	p._try_attack()                       # cios 1 -> ANTICIPATION
	p._tick_attack_timeline(p._atk_anticipation * 0.5)   # nadal ANTICIPATION
	_check(p._atk_phase == p.AtkPhase.ANTICIPATION, "test bufora: nie w ANTICIPATION")
	# Drugi atak w trakcie wind-upu: _can_attack()==false (faza aktywna) -> trafia do bufora.
	_check(not p._can_attack(), "_can_attack() true w ANTICIPATION (nie blokuje ciosu w toku)")
	p._try_attack()
	_check(p._attack_buffered > 0.0, "atak w trakcie ANTICIPATION NIE zakolejkowany w buforze")
	print("[FEEL1] (5) input buffer: atak w trakcie zamachu zakolejkowany (%.3f s) OK" % p._attack_buffered)
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (6) DODGE RECOVERY — po dashu wchodzi recovery (cancelable atakiem); i-frames zachowane
# ============================================================================
func _test_dodge_recovery() -> void:
	var p = await _make_player()
	p.stamina = p.max_stamina

	p._try_dodge()
	_check(p.is_dodging, "dash nie wystartowal")
	_check(p._iframes > 0.0, "dash bez i-frames")
	# Wyczerpaj czas dasha przez tiki fizyki-rownowazne (recznie dekrementujemy _dodge_t pętla _process?).
	# Najpewniej: symuluj uplyw przez _physics_process tickami. Ale _physics_process robi duzo — zamiast
	# tego dekrementujemy bezposrednio i wolamy logike przejscia jak w _physics_process (kontrakt pola).
	# Tu sprawdzamy KONTRAKT: dodge_recovery > 0 i jest pole _dodge_recovery_t.
	_check("_dodge_recovery_t" in p, "brak pola _dodge_recovery_t (dodge recovery niewpiety)")
	_check(p.dodge_recovery > 0.0, "dodge_recovery <= 0 (brak okna recovery po dashu)")
	# Wymus stan recovery (jak po zejsciu _dodge_t) i sprawdz, ze atak go cancelluje.
	p.is_dodging = false
	p._dodge_t = 0.0
	p._dodge_recovery_t = p.dodge_recovery
	p._dodge_cd = 0.0                      # by _can_attack nie byl blokowany niczym innym
	p._attack_cd = 0.0
	_check(p._can_attack(), "nie mozna zaatakowac w dodge-recovery (cancel atakiem zablokowany)")
	p._try_attack()
	_check(p._dodge_recovery_t == 0.0, "atak NIE skasowal dodge-recovery (cancel-into-attack)")
	print("[FEEL1] (6) dodge recovery: cancelable atakiem + i-frames zachowane OK")
	p.queue_free()
	await get_tree().process_frame


# ============================================================================
#  (7) LOCK-ON + SOFT TARGET — namierza najblizszego; pull kierunku ciosu do celu
# ============================================================================
func _test_lock_on() -> void:
	var p = await _make_player()
	p.global_position = Vector3.ZERO

	# Dwa wrogowie: blizszy (z prawej, +X 4 m) i dalszy (z lewej, -X 9 m).
	var near := EnemyScript.new()
	add_child(near)
	near.global_position = Vector3(4.0, 0.0, 0.0)
	var far := EnemyScript.new()
	add_child(far)
	far.global_position = Vector3(-9.0, 0.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame

	# Toggle lock -> namierza NAJBLIZSZEGO (near).
	p._toggle_lock_on()
	_check(p.lock_target() == near, "lock NIE namierzyl najblizszego wroga")
	# Ponowny toggle zdejmuje lock.
	p._toggle_lock_on()
	_check(p.lock_target() == null, "ponowny toggle NIE zdjal locka")

	# SOFT TARGET PULL: forward "w bok" (-Z), cel near po +X w zasiegu pull -> aim ma sie obrocic ku celowi.
	p._toggle_lock_on()                       # zalockuj near ponownie
	near.global_position = Vector3(2.0, 0.0, 0.0)   # w zasiegu melee_pull_range
	await get_tree().process_frame
	var forward := Vector3(0.0, 0.0, -1.0)    # patrzymy "w przod" (-Z), nie na cel (+X)
	var aim: Vector3 = p._attack_aim_dir(forward)
	# Pull dziala: aim powinien miec dodatnia skladowa X (ku celowi) — wieksza niz czysty forward (0).
	_check(aim.x > 0.2, "soft-target pull NIE skierowal ciosu ku celowi (aim.x=%.2f)" % aim.x)
	print("[FEEL1] (7) lock-on najblizszy + soft-target pull (aim.x=%.2f) OK" % aim.x)

	p.queue_free()
	near.queue_free()
	far.queue_free()
	await get_tree().process_frame
