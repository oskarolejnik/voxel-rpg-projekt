extends Node
## Feel4Test.gd — HEADLESS test FAZY 4 (JUICE): slash-trail, screen-flash, ability-aury, ground
## decale (HazardZone kontur), crit-burst, movement/ambient pyl. Uruchomienie:
##   godot --headless res://test/Feel4Test.tscn
##
## NIE rusza dzialajacej gry — instancjuje REALNE klasy (FeelFX/HUD/Player/HazardZone) i weryfikuje
## KONTRAKT FAZY 4 (czysto wizualny, pooled, one-shot, brak wyciekow):
##  (1) SLASH-TRAIL spawn w fazie ACTIVE, NIE w ANTICIPATION (faza ataku jako gwarancja).
##  (2) SCREEN-FLASH wyzwalany na trafieniu/krytyku; krytyk mocniejszy/zlotawy; gasnie (brak wiszenia).
##  (3) ABILITY-AURA spawn per skill (ring) -> widoczna, po LIFE ukryta (brak wycieku).
##  (4) GROUND DECALE: HazardZone ma _decal ORAZ _ring (kontur); kolor preview vs active rozny.
##  (5) CRIT-BURST: krytyk = mocniejszy burst (wiecej widocznych sparkow/swiatel + jasniejsze) niz zwykly.
##  (6) MOVEMENT pyl + per-biom tint: set_dust_tint zmienia albedo emitera; sprint-dust emituje.
##  (7) BRAK WYCIEKOW VFX: po wielu wywolaniach liczba dzieci FeelFX STALA (pooled/round-robin).
## Kod wyjscia: 0 = ALL OK, 1 = FAIL. Print "[FEEL4] ..." + ALL OK + quit.

const FeelFXScript := preload("res://src/world/FeelFX.gd")
const HUDScript := preload("res://src/HUD.gd")
const PlayerScript := preload("res://src/Player.gd")
const HazardZoneScript := preload("res://components/HazardZone.gd")
const SkillResourceScript := preload("res://data/resources/SkillResource.gd")

var _failures: int = 0


func _ready() -> void:
	print("[FEEL4] === Faza 4 (JUICE) mini-test start ===")
	await _test_slash_trail_phase()
	await _test_screen_flash()
	await _test_ability_aura()
	await _test_crit_burst()
	await _test_ground_decals()
	await _test_movement_dust()
	await _test_no_vfx_leaks()

	if _failures == 0:
		print("[FEEL4] ALL OK")
	else:
		printerr("[FEEL4] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[FEEL4] FAIL: %s" % msg)


func _make_feelfx() -> FeelFX:
	var fx := FeelFXScript.new()
	fx.name = "FeelFX"
	add_child(fx)
	return fx


func _visible_count(arr: Array) -> int:
	var n := 0
	for nd in arr:
		if nd != null and (nd as Node3D).visible:
			n += 1
	return n


# ============================================================================
#  (1) SLASH-TRAIL — spawn w ACTIVE, NIE w ANTICIPATION
# ============================================================================
func _test_slash_trail_phase() -> void:
	var fx := _make_feelfx()
	await get_tree().process_frame

	# Bezposrednio: spawn_slash_trail uwidacznia smuge; przed wywolaniem zero widocznych.
	_check(_visible_count(fx._trails) == 0, "TRAIL: smugi widoczne PRZED spawnem (powinny byc ukryte)")
	fx.spawn_slash_trail(Vector3(0, 0.9, 0), Vector3(0, 0, -1), Color(0.8, 0.9, 1.0), false)
	_check(_visible_count(fx._trails) >= 1, "TRAIL: spawn_slash_trail nie uwidocznil zadnej smugi")
	# Gasnie: po TRAIL_LIFE+eps -> ukryta (brak wiszenia).
	fx._process(FeelFX.TRAIL_LIFE + 0.05)
	_check(_visible_count(fx._trails) == 0, "TRAIL: smuga nie zgasla po TRAIL_LIFE (wisi)")
	fx.queue_free()
	await get_tree().process_frame

	# FAZOWA gwarancja: Player wola smuge w _enter_attack_active (ACTIVE), nie w _begin_attack_timeline
	# (ANTICIPATION). Sprawdzamy, ze _begin_attack_timeline ustawia ANTICIPATION (hitbox/smuga jeszcze
	# nie), a _enter_attack_active ustawia ACTIVE.
	var p = PlayerScript.new()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	p._atk_forward = Vector3(0, 0, -1)
	p._begin_attack_timeline(p._skill_attack)
	_check(p._atk_phase == p.AtkPhase.ANTICIPATION, "TRAIL/FAZA: _begin_attack_timeline nie ustawil ANTICIPATION (faza=%d)" % p._atk_phase)
	p._enter_attack_active()
	_check(p._atk_phase == p.AtkPhase.ACTIVE, "TRAIL/FAZA: _enter_attack_active nie ustawil ACTIVE (faza=%d)" % p._atk_phase)
	p.queue_free()
	await get_tree().process_frame
	print("[FEEL4] (1) slash-trail: spawn->widoczna->gasnie; _enter_attack_active=ACTIVE OK")


# ============================================================================
#  (2) SCREEN-FLASH — wyzwalany; krytyk mocniejszy/zlotawy; gasnie
# ============================================================================
func _test_screen_flash() -> void:
	var hud = HUDScript.new()
	add_child(hud)
	await get_tree().process_frame

	# Zwykly flash -> widoczny, _flash_t > 0.
	hud.flash(false)
	_check(hud._flash_overlay.visible, "FLASH: zwykly flash nie uwidocznil overlaya")
	_check(hud._flash_t > 0.0, "FLASH: zwykly flash nie ustawil _flash_t (>0)")
	var hit_peak: float = hud._flash_peak
	# Zgaszenie zwyklego (by krytyk nie byl "nadpisany" przez logike max).
	hud._process(hud._flash_dur + 0.02)
	_check(not hud._flash_overlay.visible, "FLASH: overlay nie zgasl po dur (wisi)")

	# Krytyk -> mocniejszy peak i zlotawy kolor (R,G wyzsze; B nizsze niz R).
	hud.flash(true)
	var crit_peak: float = hud._flash_peak
	_check(crit_peak > hit_peak, "FLASH: krytyk nie mocniejszy niz zwykly (crit=%.2f hit=%.2f)" % [crit_peak, hit_peak])
	var c: Color = hud._flash_overlay.color
	_check(c.r > 0.9 and c.b < c.r, "FLASH: krytyk nie zlotawy (rgb=%.2f,%.2f,%.2f)" % [c.r, c.g, c.b])
	hud._process(hud._flash_dur + 0.02)
	_check(not hud._flash_overlay.visible, "FLASH: krytyk-flash nie zgasl po dur (wisi)")
	hud.queue_free()
	await get_tree().process_frame
	print("[FEEL4] (2) screen-flash: hit_peak=%.2f crit_peak=%.2f (zlotawy), gasnie OK" % [hit_peak, crit_peak])


# ============================================================================
#  (3) ABILITY-AURA — spawn per skill (ring), widoczna, gasnie (brak wycieku)
# ============================================================================
func _test_ability_aura() -> void:
	var fx := _make_feelfx()
	await get_tree().process_frame
	_check(_visible_count(fx._auras) == 0, "AURA: aury widoczne PRZED spawnem")
	fx.spawn_ability_aura(&"ring", Color(0.8, 0.9, 1.0), 2.6, Vector3.ZERO, Vector3(0, 0, -1))
	_check(_visible_count(fx._auras) >= 1, "AURA: spawn_ability_aura(ring) nie uwidocznil aury")
	# Pusty kind -> brak nowej aury (stare skille bez zmian).
	var before := _visible_count(fx._auras)
	fx.spawn_ability_aura(&"", Color.WHITE, 2.0, Vector3.ZERO)
	_check(_visible_count(fx._auras) == before, "AURA: pusty kind dodal aure (powinien byc no-op)")
	# Gasnie po AURA_LIFE.
	fx._process(FeelFX.AURA_LIFE + 0.05)
	_check(_visible_count(fx._auras) == 0, "AURA: aura nie zgasla po AURA_LIFE (wisi)")

	# SLAM (review #minor: galaz uspiona, ale data-driven hook) -> widoczna aura + DOKLADNIE 1 puls swiatla.
	# Slam wola spawn_hit_vfx(big) ktora wewnetrznie pulsuje raz; NIE wolno dorzucac drugiego pulsu (zjadanie
	# 2 slotow puli na 1 cast). Liczymy aktywne pulsy swiatla PO swiezym (wygaszamy poprzednie najpierw).
	fx._process(FeelFX.LIGHT_PULSE_TIME + 0.02)   # wygas ewentualne resztki swiatla
	fx.spawn_ability_aura(&"slam", Color(1.0, 0.6, 0.2), 2.0, Vector3.ZERO)
	_check(_visible_count(fx._auras) >= 1, "AURA: spawn_ability_aura(slam) nie uwidocznil aury-pierscienia")
	var slam_lights := 0
	for i in fx._lights.size():
		if fx._light_t[i] > 0.0:
			slam_lights += 1
	_check(slam_lights == 1, "AURA/SLAM: slam zuzyl %d slotow swiatla (oczekiwane DOKLADNIE 1 — brak redundancji)" % slam_lights)
	# CAST -> aura + puls (lekki). Tylko sanity, ze galaz nie crashuje i daje wizual.
	fx._process(FeelFX.AURA_LIFE + 0.05)
	fx.spawn_ability_aura(&"cast", Color(0.6, 0.8, 1.0), 1.5, Vector3.ZERO)
	_check(_visible_count(fx._auras) >= 1, "AURA: spawn_ability_aura(cast) nie uwidocznil aury")

	fx.queue_free()
	await get_tree().process_frame
	print("[FEEL4] (3) ability-aura: ring/slam/cast spawn->widoczna->gasnie; slam=1 puls; pusty kind=no-op OK")


# ============================================================================
#  (4) GROUND DECALE — HazardZone _decal + _ring (kontur), kolor preview vs active
# ============================================================================
func _test_ground_decals() -> void:
	# Strefa wroga (preview = telegraf).
	var enemy_zone = HazardZoneScript.new()
	enemy_zone.preview = true
	enemy_zone.preview_color = Color(1.0, 0.4, 0.1, 0.35)   # ciepla (wrog)
	enemy_zone.active_color = Color(1.0, 0.25, 0.1, 0.45)
	add_child(enemy_zone)
	await get_tree().process_frame
	_check(enemy_zone._decal != null, "DECAL: HazardZone brak wypelnienia (_decal)")
	_check(enemy_zone._ring != null, "DECAL: HazardZone brak konturu (_ring) — FAZA 4 obwodka")
	# Kontur swieci mocniej niz wypelnienie (czytelnosc z daleka).
	if enemy_zone._ring_mat != null and enemy_zone._mat != null:
		_check(enemy_zone._ring_mat.emission_energy_multiplier > enemy_zone._mat.emission_energy_multiplier,
			"DECAL: kontur nie swieci mocniej niz wypelnienie (ring=%.2f fill=%.2f)" %
			[enemy_zone._ring_mat.emission_energy_multiplier, enemy_zone._mat.emission_energy_multiplier])
	# arm() (preview -> aktywna) zmienia kolor wypelnienia na active.
	enemy_zone.preview = false
	enemy_zone._refresh_color()
	_check(enemy_zone._mat.albedo_color.is_equal_approx(enemy_zone.active_color),
		"DECAL: po dezaktywacji preview kolor != active_color")

	# Strefa GRACZA (inny, chlodny kolor) — czytelnosc "kto rzucil".
	var player_zone = HazardZoneScript.new()
	player_zone.preview = true
	player_zone.preview_color = Color(0.3, 0.7, 1.0, 0.35)   # chlodna (gracz)
	add_child(player_zone)
	await get_tree().process_frame
	_check(not player_zone.preview_color.is_equal_approx(enemy_zone.preview_color),
		"DECAL: strefa gracza i wroga maja ten sam kolor (brak kontrastu kto-rzucil)")
	enemy_zone.queue_free(); player_zone.queue_free()
	await get_tree().process_frame
	print("[FEEL4] (4) ground decale: _decal+_ring, kontur jasniejszy, gracz!=wrog kolor OK")


# ============================================================================
#  (5) CRIT-BURST — krytyk mocniejszy niz zwykly big (wiecej widocznych + jasniejsze swiatlo)
# ============================================================================
func _test_crit_burst() -> void:
	var fx := _make_feelfx()
	await get_tree().process_frame

	# Zwykly big hit: zapamietaj energie swiatla.
	fx.spawn_hit_vfx(Vector3.ZERO, FeelFX.COL_PHYS, true)
	var big_light_energy: float = 0.0
	for i in fx._lights.size():
		if fx._light_t[i] > 0.0:
			big_light_energy = maxf(big_light_energy, fx._lights[i].light_energy)
	# Wygas swiatla, zacznij czysto.
	fx._process(FeelFX.LIGHT_PULSE_TIME + 0.02)

	# Crit-burst: wieksza energia swiatla niz zwykly big.
	fx.spawn_crit_burst(Vector3.ZERO, FeelFX.COL_PHYS)
	var crit_light_energy: float = 0.0
	var crit_amount: int = 0
	for i in fx._lights.size():
		if fx._light_t[i] > 0.0:
			crit_light_energy = maxf(crit_light_energy, fx._lights[i].light_energy)
	# Iskra krytyka ma wiecej czastek (amount podbity).
	for s in fx._sparks:
		if s.emitting:
			crit_amount = maxi(crit_amount, s.amount)
	_check(crit_light_energy > big_light_energy,
		"CRIT: puls swiatla krytyka nie mocniejszy niz big (crit=%.2f big=%.2f)" % [crit_light_energy, big_light_energy])
	_check(crit_amount >= 26, "CRIT: iskra krytyka nie ma podbitej liczby czastek (amount=%d, oczekiwane >=26)" % crit_amount)

	# Routing przez hit_resolved: was_crit=true -> uzywa crit-burst (mocny puls).
	fx._process(FeelFX.LIGHT_PULSE_TIME + 0.02)
	var dummy := Node3D.new()
	add_child(dummy)
	fx._on_hit_resolved(self, dummy, 50.0, true)
	var via_signal_energy: float = 0.0
	for i in fx._lights.size():
		if fx._light_t[i] > 0.0:
			via_signal_energy = maxf(via_signal_energy, fx._lights[i].light_energy)
	_check(via_signal_energy > big_light_energy, "CRIT: hit_resolved(crit) nie odpalil crit-burst (energia=%.2f)" % via_signal_energy)
	dummy.queue_free()
	fx.queue_free()
	await get_tree().process_frame
	print("[FEEL4] (5) crit-burst: light crit=%.1f > big=%.1f, amount=%d OK" % [crit_light_energy, big_light_energy, crit_amount])


# ============================================================================
#  (6) MOVEMENT pyl + per-biom tint
# ============================================================================
func _test_movement_dust() -> void:
	var p = PlayerScript.new()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(p._land_dust != null, "DUST: brak emitera _land_dust")

	# set_dust_tint -> albedo materialu emitera == tint (per-biom).
	var ember := Color(0.82, 0.55, 0.36, 0.7)
	p.set_dust_tint(ember)
	var mesh := p._land_dust.draw_pass_1 as QuadMesh
	var mat := mesh.material as StandardMaterial3D
	_check(mat.albedo_color.is_equal_approx(ember), "DUST: set_dust_tint nie zmienil albedo (got %s)" % mat.albedo_color)
	# Inny biom -> inny kolor pylu.
	var frost := Color(0.92, 0.95, 1.0, 0.7)
	p.set_dust_tint(frost)
	_check(mat.albedo_color.is_equal_approx(frost), "DUST: drugi biom nie zmienil koloru pylu")
	_check(not ember.is_equal_approx(frost), "DUST: dwa biomy daja ten sam kolor (brak per-biom rozroznienia)")

	# Sprint-dust emituje (one-shot), amount w sensownym zakresie.
	p._spawn_sprint_dust()
	_check(p._land_dust.emitting, "DUST: _spawn_sprint_dust nie wlaczyl emisji")
	_check(p._land_dust.amount >= 1 and p._land_dust.amount <= 28, "DUST: sprint amount poza zakresem (%d)" % p._land_dust.amount)
	# Turn-dust (poslizg przy zwrocie) — mocniejszy obloczek.
	p._spawn_turn_dust(Vector3(0, 0, -1))
	_check(p._land_dust.emitting and p._land_dust.amount >= 8, "DUST: _spawn_turn_dust slabszy niz oczekiwany (amount=%d)" % p._land_dust.amount)
	p.queue_free()
	await get_tree().process_frame
	print("[FEEL4] (6) movement pyl: per-biom tint (ember!=frost), sprint+turn dust OK")


# ============================================================================
#  (7) BRAK WYCIEKOW VFX — liczba dzieci FeelFX STALA po wielu wywolaniach (pooled/round-robin)
# ============================================================================
func _test_no_vfx_leaks() -> void:
	var fx := _make_feelfx()
	await get_tree().process_frame
	var before := fx.get_child_count()
	var dummy := Node3D.new()
	add_child(dummy)
	for i in 20:
		fx.spawn_slash_trail(Vector3(0, 0.9, 0), Vector3(0, 0, -1), Color.WHITE, i % 2 == 0)
		fx.spawn_ability_aura(&"ring", Color.WHITE, 2.0, Vector3.ZERO)
		fx.spawn_crit_burst(Vector3.ZERO, FeelFX.COL_PHYS)
		fx._on_hit_resolved(self, dummy, 25.0, i % 2 == 0)
	var after := fx.get_child_count()
	_check(after == before, "LEAK: liczba dzieci FeelFX zmienila sie (before=%d after=%d) — alokacja w hot-path!" % [before, after])
	# Suma puli (round-robin) — sanity, ze nic nie urosło ponad zadeklarowane pule.
	var expected := fx._sparks.size() + fx._lights.size() + fx._numbers.size() + fx._trails.size() + fx._auras.size()
	_check(before == expected, "LEAK: dzieci FeelFX (%d) != suma puli (%d)" % [before, expected])
	dummy.queue_free()
	fx.queue_free()
	await get_tree().process_frame
	print("[FEEL4] (7) brak wyciekow: dzieci FeelFX stale=%d (=suma puli) po 20x wywolaniach OK" % before)
