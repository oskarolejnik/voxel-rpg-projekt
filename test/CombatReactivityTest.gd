extends Node
## CombatReactivityTest.gd — headless test reaktywności walki (audyt rank #1): hitstun + poise-break.
## Uruchomienie: godot --headless res://test/CombatReactivityTest.tscn
##
##  (1) TRASH (poise 0): pojedynczy cios PRZERYWA atak (_attacking->false) i ustawia hitstun.
##  (2) hitstun PAUZUJE windup: _process_attack_windup nie dekrementuje _windup_timer gdy _hitstun_t>0.
##  (3) ELITE (poise>0): pierwsze ciosy NIE przerywają ataku; dopiero złamanie poise przerywa.
##  (4) configure_from_resource czyta poise z .tres (brute>0, goblin=0) i wiąże ją z encją.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL.

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[CR] FAIL: %s" % msg)


## Buduje wroga z zadaną pulą poise (allegiance hostile, trash domyślnie). add_child -> _ready
## (buduje AIComponent/HealthComponent itd.). Poise ustawiamy po skonstruowaniu, przed testem.
func _make_enemy(poise_val: float) -> Enemy:
	var e := Enemy.new()
	add_child(e)
	e.poise = poise_val
	e._poise_current = poise_val
	return e


func _attacker() -> Node3D:
	var a := Node3D.new()
	add_child(a)
	a.global_position = Vector3(2.0, 0.0, 0.0)
	return a


func _ready() -> void:
	print("[CR] === Combat reactivity test start ===")
	_test_trash_interrupted_every_hit()
	_test_hitstun_pauses_windup()
	_test_elite_resists_until_poise_break()
	_test_configure_reads_poise()
	if _failures == 0:
		print("[CR] ALL OK")
	else:
		printerr("[CR] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


# ---------------------------------------------------------------------------
#  (1) TRASH (poise 0) — każdy cios przerywa atak i staggeruje
# ---------------------------------------------------------------------------
func _test_trash_interrupted_every_hit() -> void:
	var e := _make_enemy(0.0)
	e._attacking = true
	e._windup_timer = 0.5
	e.take_damage(0.0, _attacker())
	_check(not e._attacking, "TRASH: cios nie przerwal ataku (_attacking nadal true)")
	_check(e._hitstun_t > 0.0, "TRASH: brak hitstunu po ciosie")
	e.queue_free()
	print("[CR] (1) trash przerywany kazdym ciosem OK")


# ---------------------------------------------------------------------------
#  (2) hitstun pauzuje windup (przy wysokiej poise cios nie przerywa, tylko zamraża rytm)
# ---------------------------------------------------------------------------
func _test_hitstun_pauses_windup() -> void:
	var e := _make_enemy(5.0)
	e._attacking = true
	e._windup_timer = 0.5
	e._hitstun_t = 0.2
	e._process_attack_windup(0.1, true, 1.0)
	_check(absf(e._windup_timer - 0.5) < 0.0001, "hitstun NIE pauzuje windupu (timer=%.3f, oczekiwane 0.5)" % e._windup_timer)
	_check(e._attacking, "hitstun sam (bez zlamania poise) nie powinien przerywac ataku")
	e.queue_free()
	print("[CR] (2) hitstun pauzuje windup OK")


# ---------------------------------------------------------------------------
#  (3) ELITE (poise 3) — opiera się, dopiero 3. cios łamie poise i przerywa atak
# ---------------------------------------------------------------------------
func _test_elite_resists_until_poise_break() -> void:
	var e := _make_enemy(3.0)
	e._attacking = true
	e._windup_timer = 0.5
	var atk := _attacker()
	e.take_damage(0.0, atk)        # poise 3 -> 2
	_check(e._attacking, "ELITE: 1. cios nie powinien przerwac (poise 3)")
	e.take_damage(0.0, atk)        # 2 -> 1
	_check(e._attacking, "ELITE: 2. cios nie powinien przerwac")
	e.take_damage(0.0, atk)        # 1 -> 0 -> break
	_check(not e._attacking, "ELITE: 3. cios (zlamanie poise) powinien przerwac atak")
	e.queue_free()
	print("[CR] (3) elite opiera sie do zlamania poise OK")


# ---------------------------------------------------------------------------
#  (4) configure_from_resource czyta poise (.tres -> encja); trash ma 0, elita >0
# ---------------------------------------------------------------------------
func _test_configure_reads_poise() -> void:
	if EnemyDB == null:
		_check(false, "brak EnemyDB do testu (4)")
		return
	EnemyDB.reload()
	var brute_res: EnemyResource = EnemyDB.enemy(&"brute")
	var goblin_res: EnemyResource = EnemyDB.enemy(&"goblin")
	_check(brute_res != null and brute_res.poise > 0.0, "brute.tres (elite) nie ma poise > 0")
	_check(goblin_res != null and goblin_res.poise == 0.0, "goblin (trash) powinien miec poise 0 (jest %.1f)" % (goblin_res.poise if goblin_res != null else -1.0))
	var e := Enemy.new()
	e.configure_from_resource(brute_res)
	add_child(e)
	_check(e.poise > 0.0, "Enemy po configure z brute.tres ma poise 0 (oczekiwane >0)")
	e.queue_free()
	print("[CR] (4) configure_from_resource czyta poise OK")
