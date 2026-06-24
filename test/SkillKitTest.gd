extends Node
## SkillKitTest.gd — HEADLESS test per-klasowych zestawow skilli (krok #7).
## Uruchomienie: godot --headless res://test/SkillKitTest.tscn. Print "[SKILLKIT] ..." + ALL OK.
##
##  (1) _build_progression dla klasy NIE-wojownika (mage) buduje finisher/aktyw (nie null) z poprawnym
##      zasobem klasy (mana) i tagiem &"ranged".
##  (2) Ranger dostaje ranged finisher z pierce (tag &"pierce").
##  (3) Wojownik niezmieniony: finisher = whirlwind, tag &"melee" (BEZ regresji).
##  (4) Klasa nieznana (rogue) dostaje melee finisher (fallback, nie null).
##  (5) _perform_skill na ranged-tagged skillu spawnuje Projectile jako dziecko rodzica gracza
##      (sciezka spawnu) bez bledu.
## Kod wyjscia: 0 = ALL OK, 1 = FAIL.

const PlayerScript := preload("res://src/Player.gd")

var _failures: int = 0


func _ready() -> void:
	print("[SKILLKIT] === test per-klasowych skilli (krok #7) start ===")
	await _test()
	if _failures == 0:
		print("[SKILLKIT] ALL OK")
	else:
		printerr("[SKILLKIT] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[SKILLKIT] FAIL: %s" % msg)


# Tworzy gracza danej klasy. class_id MUSI byc ustawiony PRZED add_child (_build_progression czyta
# go w _ready). Zwraca gotowy Player (dziecko tego testu) po 2 klatkach.
func _make_player(cls: StringName) -> Node:
	if GameState != null:
		GameState.class_id = cls
	var p = PlayerScript.new()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	return p


func _test() -> void:
	# (1) Mag: ranged finisher (mana).
	var mage = await _make_player(&"mag")
	var msk: SkillResource = mage._skill_finisher
	_check(msk != null, "mag: _build_progression NIE zbudowal finishera (null)")
	if msk != null:
		_check(msk.cost_resource == &"mana", "mag: zasob finishera != mana (jest %s)" % msk.cost_resource)
		_check(msk.tags.has(&"ranged"), "mag: finisher nie ma tagu &ranged")
	print("[SKILLKIT] (1) mag -> finisher ranged (mana) OK")

	# (5) _perform_skill na ranged finisherze spawnuje Projectile pod rodzicem gracza.
	var before := _count_projectiles()
	mage._perform_skill(msk, null)
	var after := _count_projectiles()
	_check(after > before, "mag: _perform_skill(ranged) NIE zespawnowal Projectile (przed %d, po %d)" % [before, after])
	print("[SKILLKIT] (5) ranged skill spawnuje Projectile OK")
	# Ubij zespawnowane pociski OD RAZU (zanim physics frame zawola get_world_3d w pustym swiecie testu).
	for c in get_children():
		if c is Projectile:
			c.free()
	mage.queue_free()
	await get_tree().process_frame

	# (2) Ranger: ranged + pierce (focus).
	var ranger = await _make_player(&"lucznik")
	var rsk: SkillResource = ranger._skill_finisher
	_check(rsk != null, "ranger: finisher null")
	if rsk != null:
		_check(rsk.tags.has(&"ranged"), "ranger: finisher nie ma tagu &ranged")
		_check(rsk.tags.has(&"pierce"), "ranger: finisher nie ma tagu &pierce")
		_check(rsk.cost_resource == &"focus", "ranger: zasob finishera != focus (jest %s)" % rsk.cost_resource)
	print("[SKILLKIT] (2) ranger -> ranged + pierce (focus) OK")
	ranger.queue_free()
	await get_tree().process_frame

	# (3) Wojownik niezmieniony: whirlwind, melee.
	var warrior = await _make_player(&"wojownik")
	var wsk: SkillResource = warrior._skill_finisher
	_check(wsk != null and wsk.id == &"whirlwind", "wojownik: finisher != whirlwind (regresja)")
	if wsk != null:
		_check(wsk.tags.has(&"melee"), "wojownik: finisher nie ma tagu &melee")
		_check(wsk.cost_resource == &"rage", "wojownik: zasob finishera != rage")
	print("[SKILLKIT] (3) wojownik -> whirlwind (melee, rage) BEZ regresji OK")
	warrior.queue_free()
	await get_tree().process_frame

	# (4) Klasa nieznana -> melee fallback (nie null).
	var rogue = await _make_player(&"lotrzyk")
	var rgk: SkillResource = rogue._skill_finisher
	_check(rgk != null, "rogue: finisher null (fallback nie zadzialal)")
	if rgk != null:
		_check(rgk.tags.has(&"melee"), "rogue: fallback finisher nie jest melee")
	print("[SKILLKIT] (4) rogue -> melee fallback (nie null) OK")
	rogue.queue_free()
	await get_tree().process_frame


# Ile Projectile wisi jako bezposrednie dzieci tego testu (rodzic gracza = miejsce spawnu pociskow).
func _count_projectiles() -> int:
	var n := 0
	for c in get_children():
		if c is Projectile:
			n += 1
	return n
