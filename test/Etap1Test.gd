extends Node
## Etap1Test.gd — mini-test HEADLESS Etapu 1 (DoD). NIE rusza działającej gry (Main.tscn).
## Uruchomienie: godot --headless res://test/Etap1Test.tscn
##
## Sprawdza ścieżkę walki Etapu 1 (ROADMAP 4 / TDD 4):
##  (1) DamageService.request_hit -> HurtboxComponent/HealthComponent: HP celu SPADA, a śmierć
##      (HealthComponent.died) emituje sygnał (hook pod loot Etap 2).
##  (2) Pancerz po przebiciu liczony w DamageService (armor 0.5, pierce 0.5 -> eff 0.25).
##  (3) BuffComponent zmienia staty PRZEZ pipeline (StatsComponent.get_stat).
##  (4) Krytyk liczony w DamageService (crit_chance=1 -> dmg * crit_mult).
##  (5) Lifesteal: źródło leczy się proporcjonalnie do zadanych obrażeń.
##  (6) Realny Enemy.take_damage emituje sygnał died (kontrakt śmierci wroga).
##  (7) Hitstop bezpieczny dla co-opu: w SP NetManager.has_network()==false.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[E1] ..." + ALL OK + quit.

const EPS: float = 0.0001

var _failures: int = 0


func _ready() -> void:
	print("[E1] === Etap 1 mini-test start ===")
	_test_damage_pipeline()
	await _test_death_signal()
	_test_armor_pierce()
	_test_buff_pipeline()
	_test_crit()
	_test_lifesteal()
	_test_enemy_take_damage_death()
	_test_hitstop_coop_safe()
	_test_knockback_passthrough()
	await _test_hitbox_area_path()
	_test_ai_component_chase()

	if _failures == 0:
		print("[E1] ALL OK")
	else:
		printerr("[E1] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[E1] FAIL: %s" % msg)


# ---------------------------------------------------------------------------
#  Pomocnik: encja-cel z komponentowym stosem (StatsComponent + HealthComponent + Hurtbox).
#  Ma pole `armor` (kontrakt DamageService) i opcjonalnie BuffComponent.
# ---------------------------------------------------------------------------
func _make_target(max_hp: float, armor: float = 0.0) -> CharacterBody3D:
	var ent := CharacterBody3D.new()
	ent.set_script(_DummyEntity)
	ent.armor = armor

	var stats := StatsComponent.new()
	var block := StatBlock.new()
	block.max_hp = max_hp
	stats.base = block
	ent.add_child(stats)

	var health := HealthComponent.new()
	ent.add_child(health)

	var hurt := HurtboxComponent.new()
	ent.add_child(hurt)

	add_child(ent)   # _ready() komponentów: HealthComponent ustawi current_hp = max_hp
	return ent


func _health_of(ent: Node) -> HealthComponent:
	for c in ent.get_children():
		if c is HealthComponent:
			return c as HealthComponent
	return null


func _stats_of(ent: Node) -> StatsComponent:
	for c in ent.get_children():
		if c is StatsComponent:
			return c as StatsComponent
	return null


# (1) DamageService -> HealthComponent: HP spada.
func _test_damage_pipeline() -> void:
	var target := _make_target(30.0, 0.0)
	var hc := _health_of(target)
	_check(hc != null, "brak HealthComponent na celu")
	_check(absf(hc.current_hp - 30.0) < EPS, "startowe HP != 30 (%.2f)" % hc.current_hp)

	var hit := HitData.new()
	hit.source = self
	hit.base_damage = 12.0
	hit.crit_chance = 0.0
	DamageService.request_hit(self, target, hit)

	print("[E1] po ciosie 12 dmg: HP=%.2f (oczekiwane 18)" % hc.current_hp)
	_check(absf(hc.current_hp - 18.0) < EPS, "HP po ciosie != 18 (%.2f)" % hc.current_hp)
	target.queue_free()


# (1b) Śmierć przez HealthComponent emituje sygnał died (hook pod loot Etap 2).
func _test_death_signal() -> void:
	var target := _make_target(10.0, 0.0)
	var hc := _health_of(target)
	var died_emitted := [false]
	hc.died.connect(func(_from: Node) -> void: died_emitted[0] = true)

	var hit := HitData.new()
	hit.source = self
	hit.base_damage = 999.0
	hit.crit_chance = 0.0
	DamageService.request_hit(self, target, hit)

	# died.emit jest synchroniczny w apply_damage, ale poczekajmy klatkę dla pewności.
	await get_tree().process_frame
	print("[E1] śmierć: HP=%.2f, died=%s" % [hc.current_hp, str(died_emitted[0])])
	_check(hc.current_hp <= 0.0, "HP po zabójczym ciosie > 0 (%.2f)" % hc.current_hp)
	_check(hc.is_dead, "HealthComponent.is_dead != true po śmierci")
	_check(died_emitted[0], "sygnał died NIE został wyemitowany (hook pod loot)")
	target.queue_free()


# (2) Pancerz po przebiciu w DamageService: armor 0.5, pierce 0.5 -> eff 0.25 -> dmg*0.75.
func _test_armor_pierce() -> void:
	var target := _make_target(100.0, 0.5)
	var hc := _health_of(target)

	var hit := HitData.new()
	hit.source = self
	hit.base_damage = 20.0
	hit.armor_pierce = 0.5
	hit.crit_chance = 0.0
	DamageService.request_hit(self, target, hit)
	# eff = 0.5 * (1 - 0.5) = 0.25; dmg = 20 * (1 - 0.25) = 15; HP = 100 - 15 = 85.
	print("[E1] pancerz+przebicie: HP=%.2f (oczekiwane 85)" % hc.current_hp)
	_check(absf(hc.current_hp - 85.0) < EPS, "armor/pierce: HP != 85 (%.2f)" % hc.current_hp)
	target.queue_free()


# (3) BuffComponent zmienia staty przez pipeline (DoD: buff testowy -> get_stat).
func _test_buff_pipeline() -> void:
	# Encja-holder: StatsComponent + BuffComponent jako rodzeństwo (BuffComponent znajdzie stats bratem).
	var holder := Node.new()
	add_child(holder)

	var stats := StatsComponent.new()
	var block := StatBlock.new()
	block.damage = 18.0
	stats.base = block
	holder.add_child(stats)        # _ready: rebuild (brak providerów na razie)

	var buffs := BuffComponent.new()
	holder.add_child(buffs)        # _ready: register_provider(self) na bracie StatsComponent

	var before := stats.get_stat(&"damage")
	_check(absf(before - 18.0) < EPS, "buff: damage przed buffem != 18 (%.2f)" % before)

	# Testowy buff: +50% damage (INCREASED 0.5) -> 18 * 1.5 = 27.
	buffs.apply_buff(&"test_rage", [
		StatModifier.make(&"damage", StatModifier.Op.INCREASED, 0.5),
	], 5.0)
	var after := stats.get_stat(&"damage")
	print("[E1] buff +50%% damage: %.2f -> %.2f (oczekiwane 27)" % [before, after])
	_check(absf(after - 27.0) < EPS, "buff przez pipeline: damage != 27 (%.2f)" % after)

	# Zdjęcie buffa wraca do bazy.
	buffs.remove_buff(&"test_rage")
	var removed := stats.get_stat(&"damage")
	_check(absf(removed - 18.0) < EPS, "po zdjęciu buffa damage != 18 (%.2f)" % removed)

	holder.queue_free()


# (4) Krytyk w DamageService: crit_chance=1 -> dmg * crit_mult.
func _test_crit() -> void:
	var target := _make_target(1000.0, 0.0)
	var hc := _health_of(target)

	var hit := HitData.new()
	hit.source = self
	hit.base_damage = 10.0
	hit.crit_chance = 1.0       # gwarantowany krytyk
	hit.crit_mult = 2.0
	DamageService.request_hit(self, target, hit)
	# 10 * 2.0 = 20; HP = 1000 - 20 = 980.
	print("[E1] krytyk x2: HP=%.2f (oczekiwane 980)" % hc.current_hp)
	_check(absf(hc.current_hp - 980.0) < EPS, "krytyk: HP != 980 (%.2f)" % hc.current_hp)
	target.queue_free()


# (5) Lifesteal: źródło leczy się proporcjonalnie do zadanych obrażeń.
func _test_lifesteal() -> void:
	var source := _make_target(100.0, 0.0)
	var src_hc := _health_of(source)
	# Ranimy źródło, by miało co leczyć.
	src_hc.apply_damage(50.0, null)
	_check(absf(src_hc.current_hp - 50.0) < EPS, "lifesteal setup: HP źródła != 50")

	var target := _make_target(200.0, 0.0)
	var hit := HitData.new()
	hit.source = source
	hit.base_damage = 40.0
	hit.crit_chance = 0.0
	hit.lifesteal = 0.25         # 25% z 40 = 10 HP leczenia
	DamageService.request_hit(source, target, hit)
	print("[E1] lifesteal 25%% z 40: HP źródła=%.2f (oczekiwane 60)" % src_hc.current_hp)
	_check(absf(src_hc.current_hp - 60.0) < EPS, "lifesteal: HP źródła != 60 (%.2f)" % src_hc.current_hp)
	source.queue_free()
	target.queue_free()


# (6) Realny Enemy.take_damage emituje died (kontrakt śmierci wroga, hook pod loot).
func _test_enemy_take_damage_death() -> void:
	var enemy := Enemy.new()
	enemy.max_hp = 30.0
	add_child(enemy)              # _ready ustawi hp = max_hp i zbuduje ciało
	enemy.hp = 30.0

	var died_emitted := [false]
	enemy.died.connect(func(_e: Enemy) -> void: died_emitted[0] = true)

	enemy.take_damage(15.0, self)
	_check(absf(enemy.hp - 15.0) < EPS, "Enemy HP po 15 dmg != 15 (%.2f)" % enemy.hp)
	enemy.take_damage(20.0, self)   # zabójczy cios
	print("[E1] Enemy.take_damage: hp=%.2f, died=%s" % [enemy.hp, str(died_emitted[0])])
	_check(enemy.hp <= 0.0, "Enemy HP po zabójczym ciosie > 0")
	_check(died_emitted[0], "Enemy.died NIE wyemitowany (hook pod loot Etap 2)")
	# Enemy._die() woła queue_free() — nie zwalniamy ręcznie.


# (7) Hitstop bezpieczny dla co-opu: w SP NetManager.has_network()==false (globalny time_scale OK).
func _test_hitstop_coop_safe() -> void:
	_check(NetManager.has_network() == false, "has_network() != false w SP (hitstop globalny niedozwolony!)")
	_check(NetManager.has_authority(self) == true, "has_authority() != true w SP")
	print("[E1] co-op-safe: has_network=false, has_authority=true (hitstop globalny dozwolony w SP)")


# (8) HitData.knockback DOCIERA do odbiorcy (per-cios siła, nie hardkod). Cel ma take_damage,
#     który zapamiętuje ostatnią siłę odrzutu; DamageService przekazuje hit.knockback.
func _test_knockback_passthrough() -> void:
	var ent := CharacterBody3D.new()
	ent.set_script(_KnockTarget)
	ent.armor = 0.0
	var stats := StatsComponent.new()
	var block := StatBlock.new()
	block.max_hp = 100.0
	stats.base = block
	ent.add_child(stats)
	var health := HealthComponent.new()
	ent.add_child(health)
	add_child(ent)

	var hit := HitData.new()
	hit.source = self
	hit.base_damage = 5.0
	hit.crit_chance = 0.0
	hit.knockback = 13.0          # niestandardowa siła per-cios
	DamageService.request_hit(self, ent, hit)
	print("[E1] knockback passthrough: last_knockback=%.2f (oczekiwane 13)" % ent.last_knockback)
	_check(absf(ent.last_knockback - 13.0) < EPS, "knockback z HitData nie dotarł (%.2f != 13)" % ent.last_knockback)
	ent.queue_free()


# (9) REALNA ścieżka Area3D: HitboxComponent.open_window -> get_overlapping_bodies -> DamageService
#     -> HurtboxComponent/HealthComponent. Dowodzi, że ogniwo Hitbox (Area3D) działa, nie tylko
#     bezpośredni request_hit. Wymaga World3D -> węzły muszą być w drzewie (są: add_child do testu).
func _test_hitbox_area_path() -> void:
	# Źródło ataku (gracz-atrapa) z HitboxComponent na warstwie ataków gracza.
	var src := CharacterBody3D.new()
	src.set_script(_DummyEntity)
	add_child(src)
	src.global_position = Vector3.ZERO

	var hitbox := HitboxComponent.new()
	hitbox.setup_as_player(-1.0)             # arc_dot=-1 -> bez filtra łuku (360°, prostszy test)
	hitbox.use_arc = false
	hitbox.set_hit_builder(func(_t: Node) -> HitData:
		var h := HitData.new()
		h.source = src
		h.base_damage = 9.0
		h.crit_chance = 0.0
		return h)
	var hb_shape := CollisionShape3D.new()
	var hb_sph := SphereShape3D.new()
	hb_sph.radius = 2.0
	hb_shape.shape = hb_sph
	hitbox.add_child(hb_shape)
	src.add_child(hitbox)

	# Cel (wróg-atrapa) z ciałem na warstwie ciała wroga (bit2) + Hurtbox + Health.
	var tgt := CharacterBody3D.new()
	tgt.set_script(_DummyEntity)
	tgt.collision_layer = 1 << 2             # ciało wroga (warstwa 3) — maska hitboxa gracza pyta o nią
	tgt.collision_mask = 0
	var tstats := StatsComponent.new()
	var tblock := StatBlock.new()
	tblock.max_hp = 50.0
	tstats.base = tblock
	tgt.add_child(tstats)
	var thealth := HealthComponent.new()
	tgt.add_child(thealth)
	var thurt := HurtboxComponent.new()
	thurt.setup_as_enemy()
	var thurt_shape := CollisionShape3D.new()
	var thurt_sph := SphereShape3D.new()
	thurt_sph.radius = 0.5
	thurt_shape.shape = thurt_sph
	thurt.add_child(thurt_shape)
	tgt.add_child(thurt)
	add_child(tgt)
	tgt.global_position = Vector3(1.0, 0.0, 0.0)   # 1 m od źródła -> w promieniu hitboxa (2 m)

	# Poczekaj klatkę, by ciała/area zarejestrowały transformy, potem otwórz okno.
	await get_tree().physics_frame
	await get_tree().physics_frame
	hitbox.open_window(0.2, Vector3.ZERO)
	# Area3D potrzebuje paru kroków fizyki, by zaktualizować nakładania.
	for _i in 6:
		await get_tree().physics_frame

	print("[E1] Area3D hitbox path: HP celu=%.2f (oczekiwane 41 = 50-9)" % thealth.current_hp)
	_check(thealth.current_hp <= 49.9, "Area3D hitbox NIE zadał obrażeń (HP=%.2f)" % thealth.current_hp)
	_check(absf(thealth.current_hp - 41.0) < EPS, "Area3D hitbox: HP != 41 (%.2f)" % thealth.current_hp)
	src.queue_free()
	tgt.queue_free()


# (10) AIComponent (host-only) działa jako komponent: idle -> chase, gdy cel w aggro_radius.
#      Dowodzi, że AIComponent.tick() wybiera stan przez kontrakt ai_* (nie martwy kod).
func _test_ai_component_chase() -> void:
	var brain := AIComponent.new()
	var host := Node3D.new()
	host.set_script(_AIHost)
	host.add_child(brain)
	add_child(host)
	brain.configure({ "aggro_radius": 12.0, "leash_radius": 18.0 })
	brain.set_home(Vector3.ZERO)

	# Cel w zasięgu aggro (5 m < 12 m) -> tick powinien przełączyć IDLE -> CHASE.
	var target := Node3D.new()
	add_child(target)
	target.global_position = Vector3(5.0, 0.0, 0.0)
	host.ai_target = target

	# Tick 1: IDLE -> CHASE (wykrycie celu w aggro). Tick 2: CHASE faktycznie steruje ciałem.
	var st1 := brain.tick(0.016)
	var st2 := brain.tick(0.016)
	print("[E1] AIComponent: stany po tick1=%d, tick2=%d (CHASE=%d)" % [st1, st2, AIComponent.State.CHASE])
	_check(st1 == AIComponent.State.CHASE, "AIComponent nie przeszedł w CHASE przy celu w aggro (tick1=%d)" % st1)
	_check(host.move_called, "AIComponent nie wywołał ai_move_towards (mózg nie steruje ciałem)")
	host.queue_free()
	target.queue_free()


# ---------------------------------------------------------------------------
#  Wewnętrzny skrypt celu-atrapy: CharacterBody3D z polem `armor` (kontrakt DamageService).
#  Obrażenia idą przez HealthComponent (komponentowa droga), więc take_damage nie jest potrzebny.
# ---------------------------------------------------------------------------
const _DummyEntity := preload("res://test/DummyEntity.gd")
const _KnockTarget := preload("res://test/KnockTarget.gd")
const _AIHost := preload("res://test/AIHost.gd")
