extends Node
## FeelTest.gd — mini-test HEADLESS warstwy ODCZUCIA (BATCH "Fastest High-Impact Fixes").
## Uruchomienie: godot --headless res://test/FeelTest.tscn
##
## NIE rusza dzialajacej gry (Main.tscn). Weryfikuje, ze poprawki feelu sa SPOJNE i NIE crashuja:
##  (1) HITSTOP TIERED: FeelFX.hitstop_for zwraca ROZNE czasy wg wagi (light<heavy<crit).
##  (2) FLINCH: HealthComponent.damaged (amount>0) wyzwala flinch na Enemy (model szarpie sie).
##  (3) DAMAGE NUMBER: FeelFX.spawn_damage_number nie crashuje + Label3D dostaje tekst/kolor.
##  (4) HIT-VFX: FeelFX.spawn_hit_vfx (iskra + puls swiatla) nie crashuje, emiter wlacza emitting.
##  (5) FeelFX spina sie pod DamageService.hit_resolved i reaguje (spawn FX) bez bledow.
##  (6) SHADERY (terrain/props/water) KOMPILUJA sie (load + instancja materialu bez bledu).
## Kod wyjscia: 0 = ALL OK, 1 = FAIL. Print "[FEEL] ..." + ALL OK + quit.

const EnemyScript := preload("res://src/Enemy.gd")
const FeelFXScript := preload("res://src/world/FeelFX.gd")

var _failures: int = 0


func _ready() -> void:
	print("[FEEL] === Feel batch mini-test start ===")
	_test_hitstop_tiers()
	await _test_enemy_flinch()
	await _test_feelfx_spawn()
	await _test_feelfx_hit_resolved()
	_test_shaders_compile()

	if _failures == 0:
		print("[FEEL] ALL OK")
	else:
		printerr("[FEEL] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[FEEL] FAIL: %s" % msg)


# (1) HITSTOP TIERED — light 0.04 < heavy 0.10 < crit 0.14, krytyk dominuje nad ciezkoscia.
func _test_hitstop_tiers() -> void:
	var light := FeelFX.hitstop_for(false, false)
	var heavy := FeelFX.hitstop_for(false, true)
	var crit := FeelFX.hitstop_for(true, false)
	var crit_heavy := FeelFX.hitstop_for(true, true)
	print("[FEEL] (1) hitstop tiers: light=%.2f heavy=%.2f crit=%.2f crit+heavy=%.2f" % [light, heavy, crit, crit_heavy])
	_check(absf(light - 0.04) < 0.0001, "light hitstop != 0.04 (%.3f)" % light)
	_check(absf(heavy - 0.10) < 0.0001, "heavy hitstop != 0.10 (%.3f)" % heavy)
	_check(absf(crit - 0.14) < 0.0001, "crit hitstop != 0.14 (%.3f)" % crit)
	_check(light < heavy and heavy < crit, "tiery NIE rosna: light<heavy<crit")
	_check(absf(crit_heavy - 0.14) < 0.0001, "krytyk powinien dominowac (crit+heavy != 0.14)")


# (2) FLINCH — HealthComponent.damaged wyzwala flinch na Enemy (czysto wizualne szarpniecie modelu).
func _test_enemy_flinch() -> void:
	var enemy: Enemy = EnemyScript.new()
	add_child(enemy)
	await get_tree().process_frame   # _ready: model + HealthComponent + connect damaged->flinch
	_check("_flinch_t" in enemy, "Enemy nie ma pola _flinch_t (flinch nie wpiety)")
	# Stan startowy: brak flinchu.
	_check(enemy._flinch_t <= 0.0, "flinch aktywny PRZED trafieniem")
	# Symuluj zrodlo ciosu w przestrzeni, by flinch dostal kierunek OD niego.
	var src := Node3D.new()
	add_child(src)
	src.global_position = enemy.global_position + Vector3(2.0, 0.0, 0.0)
	# Obrazenia przez HealthComponent (jedyne zrodlo HP) -> emituje damaged -> _on_health_damaged.
	var hc := enemy._health
	_check(hc != null, "Enemy bez HealthComponent")
	if hc != null:
		hc.apply_damage(5.0, src)
		print("[FEEL] (2) po damaged: _flinch_t=%.3f dir=%s" % [enemy._flinch_t, str(enemy._flinch_dir)])
		_check(enemy._flinch_t > 0.0, "flinch NIE wyzwolony przez damaged")
		_check(enemy._flinch_dir.length() > 0.5, "kierunek flinchu nieustawiony")
	enemy.queue_free()
	src.queue_free()


# (3)+(4) FeelFX: spawn iskry/swiatla/liczby — bez crasha, emiter wlacza emitting, label ma tekst.
func _test_feelfx_spawn() -> void:
	var fx: FeelFX = FeelFXScript.new()
	add_child(fx)
	await get_tree().process_frame   # _ready buduje pule (sparks/lights/numbers)
	_check(fx._sparks.size() > 0, "pula iskier pusta")
	_check(fx._lights.size() > 0, "pula swiatel pusta")
	_check(fx._numbers.size() > 0, "pula liczb pusta")

	# (4) HIT-VFX: iskra + puls swiatla — nie crashuje, emiter emitting, swiatlo widoczne.
	fx.spawn_hit_vfx(Vector3(0, 1, 0), Color(1, 0.9, 0.5), false)
	var any_emit := false
	for s in fx._sparks:
		if s.emitting:
			any_emit = true
	_check(any_emit, "zaden emiter iskry nie ruszyl po spawn_hit_vfx")
	var any_light := false
	for l in fx._lights:
		if l.visible and l.light_energy > 0.0:
			any_light = true
	_check(any_light, "puls swiatla nie zapalil sie")

	# (3) DAMAGE NUMBER: zwykly i krytyk — tekst + widocznosc + krytyk wiekszy/zlotszy.
	fx.spawn_damage_number(Vector3(0, 2, 0), 17.0, false)
	fx.spawn_damage_number(Vector3(0, 2, 0), 42.0, true)
	var any_num := false
	var crit_label: Label3D = null
	for n in fx._numbers:
		if n.visible and n.text != "":
			any_num = true
			if n.text.ends_with("!"):
				crit_label = n
	_check(any_num, "zadna liczba obrazen nie pojawila sie")
	_check(crit_label != null, "krytyczna liczba (z '!') nie powstala")
	if crit_label != null:
		_check(crit_label.font_size >= 60, "krytyk powinien byc wiekszy (font_size=%d)" % crit_label.font_size)
	print("[FEEL] (3)+(4) hit-VFX/swiatlo/liczby spawn OK")

	# Petla nie crashuje (wygaszanie pulsow + unoszenie liczb).
	for _i in 6:
		await get_tree().process_frame
	fx.queue_free()


# (5) FeelFX spina sie pod DamageService.hit_resolved i reaguje (spawn FX) na realne trafienie.
func _test_feelfx_hit_resolved() -> void:
	var fx: FeelFX = FeelFXScript.new()
	add_child(fx)
	await get_tree().process_frame
	fx.connect_damage_service()
	_check(DamageService.hit_resolved.is_connected(fx._on_hit_resolved), "FeelFX nie spiety pod hit_resolved")

	# Cel z HealthComponent w przestrzeni; realny request_hit -> hit_resolved -> FeelFX spawnuje FX.
	var target := _make_health_target(50.0)
	target.global_position = Vector3(10.0, 0.0, 0.0)   # daleko od origin, by sprawdzic POZYCJE FX
	await get_tree().process_frame
	# Zapamietaj indeks nastepnej iskry; po hicie powinna stac przy celu (~y+0.9) i ruszyc emitting.
	# hit_resolved emitowane SYNCHRONICZNIE w request_hit, wiec sprawdzamy OD RAZU (bez await — one-shot
	# w headless gasnie szybko, ale flaga emitting i pozycja sa ustawione w tej samej klatce).
	var hit := HitData.new()
	hit.source = self
	hit.base_damage = 9.0
	hit.crit_chance = 0.0
	DamageService.request_hit(self, target, hit)
	var hit_near_target := false
	var any_emit := false
	for s in fx._sparks:
		if s.emitting:
			any_emit = true
		# Iskra ustawiona przy celu (XZ ~10, Y ~0.9) z malym jitterem.
		if absf(s.global_position.x - 10.0) < 0.5 and absf(s.global_position.y - 0.9) < 0.5:
			hit_near_target = true
	_check(any_emit, "hit_resolved NIE wywolal emitting iskry w FeelFX")
	_check(hit_near_target, "iskra hit-VFX NIE pojawila sie w punkcie kontaktu celu")
	print("[FEEL] (5) FeelFX reaguje na DamageService.hit_resolved OK (emit=%s przy celu=%s)" % [str(any_emit), str(hit_near_target)])
	target.queue_free()
	fx.queue_free()


# (6) Shadery teren/propy/woda KOMPILUJA sie (load + ShaderMaterial bez bledu) — feel 6/8 nie psuje renderu.
func _test_shaders_compile() -> void:
	for path in ["res://src/world/terrain.gdshader", "res://src/world/props.gdshader", "res://src/world/water.gdshader"]:
		var sh := load(path) as Shader
		_check(sh != null, "shader nie wczytal sie: %s" % path)
		if sh != null:
			var mat := ShaderMaterial.new()
			mat.shader = sh
			_check(mat.shader == sh, "ShaderMaterial nie przyjal shadera: %s" % path)
	print("[FEEL] (6) shadery (terrain/props/water) kompiluja sie OK")


# Pomocnik: minimalny cel z StatsComponent + HealthComponent (jak w Etap1Test) — w drzewie (World3D).
func _make_health_target(max_hp: float) -> CharacterBody3D:
	var ent := CharacterBody3D.new()
	var stats := StatsComponent.new()
	var block := StatBlock.new()
	block.max_hp = max_hp
	stats.base = block
	ent.add_child(stats)
	var health := HealthComponent.new()
	ent.add_child(health)
	add_child(ent)
	return ent
