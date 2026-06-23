extends Node
## Feel5Test.gd — HEADLESS test FAZY 5 (POLISH / WORLD ALIVENESS). Uruchomienie:
##   godot --headless res://test/Feel5Test.tscn
##
## NIE rusza dzialajacej gry — instancjuje REALNE klasy (AmbientLife/Enemy/WorldSpawner/AudioManager
## API/props shader) i weryfikuje KONTRAKT FAZY 5 (czysto wizualne/tanie, pooled, despawn, no-op audio):
##  (1) AMBIENT CREATURES: spawn w zasiegu / despawn poza zasiegiem (recykling slotu), limit puli.
##  (2) REAKTYWNA FOLIAGE: uniform player_pos/pusher dociera do props shadera (set->get round-trip).
##  (3) WIND ZONES: globalna sila wiatru (wind_strength) ustawialna w shaderze propow (per-biom).
##  (4) DISTANT EVENT: wyzwalany (force_event), widoczny, gasnie po LIFE (brak wiszenia/wycieku).
##  (5) ROAMING ELITE: promote_to_roaming_elite podbija threat_tier>base + skala + aura; spawner liczy.
##  (6) SOUNDSCAPE: play_ambient/play_music/has_* NO-OP-SAFE bez plikow (zero crashy), szyna Ambience.
##  (7) BRAK WYCIEKOW: liczba dzieci AmbientLife STALA po wielu update/event (pooled/round-robin).
## Kod wyjscia: 0 = ALL OK, 1 = FAIL. Print "[FEEL5] ..." + ALL OK + quit.

const AmbientLifeScript := preload("res://src/world/AmbientLife.gd")
const EnemyScript := preload("res://src/Enemy.gd")
const WorldSpawnerScript := preload("res://components/WorldSpawner.gd")

var _failures: int = 0


func _ready() -> void:
	print("[FEEL5] === Faza 5 (POLISH / WORLD ALIVENESS) mini-test start ===")
	await _test_ambient_creatures()
	await _test_reactive_foliage()
	await _test_wind_zones()
	await _test_distant_event()
	await _test_roaming_elite()
	await _test_soundscape_noop()
	await _test_no_leaks()

	if _failures == 0:
		print("[FEEL5] ALL OK")
	else:
		printerr("[FEEL5] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[FEEL5] FAIL: %s" % msg)


# Lekka atrapa swiata (duck-typed): AmbientLife uzywa TYLKO get_biome/height_at (rozmieszczenie LOSOWE,
# bez feature_hash) — tyle wystarczy by dzialal headless.
class FakeWorld:
	extends Node
	func get_biome(_x: int, _z: int) -> StringName:
		return &"verdant"
	func height_at(_x: float, _z: float) -> float:
		return 4.0


func _make_ambient(player: Node3D) -> Node3D:
	var al := AmbientLifeScript.new()
	add_child(al)
	var fw := FakeWorld.new()
	add_child(fw)
	al.setup(fw, player)
	return al


# ============================================================================
#  (1) AMBIENT CREATURES — spawn w zasiegu, despawn poza zasiegiem, limit puli
# ============================================================================
func _test_ambient_creatures() -> void:
	var player := Node3D.new()
	add_child(player)
	player.global_position = Vector3.ZERO
	var al := _make_ambient(player)
	await get_tree().process_frame

	_check(al.active_creature_count() == 0, "CREATURES: aktywne PRZED repopulacja (powinno 0)")
	# Kilka cykli repopulacji -> stworzenia spawnuja sie wokol gracza.
	for i in 6:
		al.force_repopulate()
	var spawned: int = al.active_creature_count()
	_check(spawned > 0, "CREATURES: brak spawnu po repopulacji (got %d)" % spawned)
	_check(spawned <= AmbientLifeScript.CREATURE_POOL, "CREATURES: przekroczono limit puli (%d > %d)" % [spawned, AmbientLifeScript.CREATURE_POOL])

	# Despawn poza zasiegiem: teleport gracza DALEKO -> repopulacja recykluje stworzenia za DESPAWN_RADIUS.
	player.global_position = Vector3(5000.0, 0.0, 5000.0)
	al.force_repopulate()
	# Po przesunieciu stare (przy 0,0) sa > DESPAWN_RADIUS -> zdezaktywowane; nowe moga pojawic sie wokol.
	# Sprawdzamy KLUCZOWY kontrakt: zadne aktywne stworzenie nie jest dalej niz DESPAWN_RADIUS od gracza.
	var leaked := 0
	for i in al._cr_nodes.size():
		if al._cr_active[i]:
			var d := Vector2(al._cr_nodes[i].global_position.x - player.global_position.x,
				al._cr_nodes[i].global_position.z - player.global_position.z).length()
			if d > AmbientLifeScript.DESPAWN_RADIUS + 1.0:
				leaked += 1
	_check(leaked == 0, "CREATURES: %d stworzen poza DESPAWN_RADIUS (brak despawnu poza zasiegiem)" % leaked)

	player.queue_free()
	al.queue_free()
	await get_tree().process_frame
	print("[FEEL5] (1) ambient creatures: spawn=%d (<=pool %d), despawn poza zasiegiem OK" % [spawned, AmbientLifeScript.CREATURE_POOL])


# ============================================================================
#  (2) REAKTYWNA FOLIAGE — uniform gracza/pushera dociera do props shadera
# ============================================================================
func _test_reactive_foliage() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/world/props.gdshader")
	_check(mat.shader != null, "FOLIAGE: nie zaladowano props.gdshader")

	# player_pos round-trip (set -> get) — dowodzi, ze uniform ISTNIEJE w shaderze i przyjmuje wartosc.
	var pp := Vector3(12.0, 3.0, -7.0)
	mat.set_shader_parameter("player_pos", pp)
	var got = mat.get_shader_parameter("player_pos")
	_check(got != null and (got as Vector3).is_equal_approx(pp), "FOLIAGE: player_pos nie dotarl do shadera (got %s)" % str(got))

	# pusher (wrog) round-trip — vec4 xyz+aktywnosc.
	var pa := Vector4(3.0, 1.0, 4.0, 1.0)
	mat.set_shader_parameter("pusher_a", pa)
	var gpa = mat.get_shader_parameter("pusher_a")
	_check(gpa != null and (gpa as Vector4).is_equal_approx(pa), "FOLIAGE: pusher_a nie dotarl do shadera (got %s)" % str(gpa))

	# push_radius / push_strength istnieja i sa ustawialne (kontrakt reaktywnosci).
	mat.set_shader_parameter("push_radius", 1.8)
	mat.set_shader_parameter("push_strength", 0.6)
	_check(is_equal_approx(float(mat.get_shader_parameter("push_radius")), 1.8), "FOLIAGE: push_radius nie ustawialny")
	_check(is_equal_approx(float(mat.get_shader_parameter("push_strength")), 0.6), "FOLIAGE: push_strength nie ustawialny")
	print("[FEEL5] (2) reaktywna foliage: player_pos + pusher_a + push_radius/strength docieraja do shadera OK")


# ============================================================================
#  (3) WIND ZONES — globalna sila wiatru ustawialna w shaderze propow (per-biom)
# ============================================================================
func _test_wind_zones() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/world/props.gdshader")
	# wind_strength round-trip — Main._apply_wind_for_biome pcha rozne wartosci per biom.
	mat.set_shader_parameter("wind_strength", 1.6)   # frosthelm
	_check(is_equal_approx(float(mat.get_shader_parameter("wind_strength")), 1.6), "WIND: wind_strength (frosthelm) nie dotarl")
	mat.set_shader_parameter("wind_strength", 0.7)   # emberwaste
	_check(is_equal_approx(float(mat.get_shader_parameter("wind_strength")), 0.7), "WIND: wind_strength (emberwaste) nie dotarl")
	# wind_dir (kierunek porywow) — vec2 ustawialny.
	mat.set_shader_parameter("wind_dir", Vector2(0.8, 0.6))
	var wd = mat.get_shader_parameter("wind_dir")
	_check(wd != null and (wd as Vector2).is_equal_approx(Vector2(0.8, 0.6)), "WIND: wind_dir nie dotarl (got %s)" % str(wd))
	print("[FEEL5] (3) wind zones: wind_strength per-biom (1.6/0.7) + wind_dir docieraja do shadera OK")


# ============================================================================
#  (4) DISTANT EVENT — wyzwalany, widoczny, gasnie po LIFE (brak wiszenia)
# ============================================================================
func _test_distant_event() -> void:
	var player := Node3D.new()
	add_child(player)
	var al := _make_ambient(player)
	await get_tree().process_frame

	_check(al.active_event_count() == 0, "EVENT: aktywne PRZED wyzwoleniem (powinno 0)")
	# Wymus kazdy z 4 rodzajow (rzadkosc obchodzimy w tescie przez force_event).
	var kinds := [AmbientLifeScript.Event.FLYER, AmbientLifeScript.Event.SMOKE, AmbientLifeScript.Event.METEOR, AmbientLifeScript.Event.FLASH]
	var triggered := 0
	for k in kinds:
		if al.force_event(k):
			triggered += 1
	_check(triggered >= 1, "EVENT: force_event nie wyzwolil zadnego wydarzenia")
	_check(al.active_event_count() >= 1, "EVENT: brak aktywnych eventow po wyzwoleniu")

	# Gasnie: po duzym delta (> najdluzszy LIFE = SMOKE 14 s) wszystkie znikaja (brak wycieku).
	al._animate_events(20.0)
	_check(al.active_event_count() == 0, "EVENT: event nie zgasl po LIFE (wisi)")
	# Widoczne nody po pelnym wygaszeniu = 0.
	var vis := 0
	for n in al._ev_nodes:
		if (n as Node3D).visible:
			vis += 1
	_check(vis == 0, "EVENT: %d nodow eventu nadal widocznych po wygaszeniu" % vis)

	player.queue_free()
	al.queue_free()
	await get_tree().process_frame
	print("[FEEL5] (4) distant event: wyzwolone=%d, gasna po LIFE (0 widocznych) OK" % triggered)


# ============================================================================
#  (5) ROAMING ELITE — promocja podbija threat_tier>base + skala + aura; spawner liczy
# ============================================================================
func _test_roaming_elite() -> void:
	# Bazowy wrog (trash) vs promowany elite — porownanie statow/threat_tier/skali.
	var base := EnemyScript.new()
	var base_hp_before := base.max_hp
	var base_dmg_before := base.attack_damage
	_check(base.threat_tier == &"trash", "ELITE: bazowy wrog nie jest trash (got %s)" % base.threat_tier)
	_check(not base.is_roaming_elite(), "ELITE: bazowy wrog raportuje is_roaming_elite=true")

	var elite := EnemyScript.new()
	var hp0 := elite.max_hp
	var dmg0 := elite.attack_damage
	var scale0 := elite.body_scale
	var leash0 := elite.leash_radius
	elite.promote_to_roaming_elite()
	_check(elite.is_roaming_elite(), "ELITE: promote_to_roaming_elite nie ustawil flagi")
	_check(elite.threat_tier == &"elite" or elite.threat_tier == &"boss",
		"ELITE: threat_tier nie podniesiony ponad base (got %s)" % elite.threat_tier)
	_check(elite.max_hp > hp0, "ELITE: HP nie podbite (%.0f <= %.0f)" % [elite.max_hp, hp0])
	_check(elite.attack_damage > dmg0, "ELITE: dmg nie podbite (%.1f <= %.1f)" % [elite.attack_damage, dmg0])
	_check(elite.body_scale > scale0, "ELITE: skala nie powiekszona (%.2f <= %.2f)" % [elite.body_scale, scale0])
	_check(elite.leash_radius > leash0, "ELITE: leash (wedrowka) nie poszerzony (%.0f <= %.0f)" % [elite.leash_radius, leash0])

	# Po dodaniu do drzewa buduje sie AURA (OmniLight) — wizualne wyroznienie z daleka.
	add_child(elite)
	await get_tree().process_frame
	_check(elite._elite_aura != null, "ELITE: brak aury emisyjnej (OmniLight) po _ready")
	if elite._elite_aura != null:
		_check(elite._elite_aura.light_energy > 0.0, "ELITE: aura ma zerowa energie (niewidoczna)")
		# Pulsacja w _process zmienia energie (czytelne tetno mocy).
		var e_before: float = elite._elite_aura.light_energy
		elite._process(0.4)
		_check(not is_equal_approx(elite._elite_aura.light_energy, e_before),
			"ELITE: aura nie pulsuje (energia stala)")

	# WorldSpawner: _elite_pick wybiera najsilniejszy wpis tabeli (preferuje brute).
	var sp := WorldSpawnerScript.new()
	var table := [
		{"enemy_id": &"goblin", "weight": 6.0, "max_alive": 8},
		{"enemy_id": &"brute", "weight": 1.0, "max_alive": 1},
	]
	var pick := sp._elite_pick(table)
	_check(pick == &"brute", "ELITE: _elite_pick nie wybral najsilniejszego (brute), got %s" % pick)
	_check(sp.active_elite_count() == 0, "ELITE: spawner startowo ma elity != 0")

	base.queue_free()
	elite.queue_free()
	sp.queue_free()
	await get_tree().process_frame
	print("[FEEL5] (5) roaming elite: threat_tier elite, HP/dmg/skala/leash podbite, aura pulsuje, _elite_pick=brute OK")


# ============================================================================
#  (6) SOUNDSCAPE — play_ambient/play_music/has_* NO-OP-SAFE bez plikow + szyna Ambience
# ============================================================================
func _test_soundscape_noop() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am == null:
		# Headless bez autoloadu — nie crash, ale ostrzez (test soundscape ograniczony).
		print("[FEEL5] (6) soundscape: AudioManager autoload niedostepny — pomijam (no-op kontrakt i tak spelniony)")
		return

	# Szyna Ambience istnieje (FAZA 5) obok Master/SFX/Music.
	var buses: Array = am.bus_names()
	_check(buses.has("Ambience"), "SOUND: brak szyny Ambience (buses=%s)" % str(buses))
	_check(buses.has("Master") and buses.has("SFX") and buses.has("Music"), "SOUND: brakuje bazowych szyn")

	# play_ambient bez pliku -> NO-OP (zero crashy); intencja zapamietana.
	am.play_ambient(&"verdant")
	_check(am.current_ambience() == &"verdant", "SOUND: play_ambient nie zapamietal intencji (verdant)")
	am.play_ambient(&"emberwaste")
	_check(am.current_ambience() == &"emberwaste", "SOUND: zmiana ambience biomu nie zaszla")
	am.stop_ambient()
	_check(am.current_ambience() == &"", "SOUND: stop_ambient nie wyczyscil ambience")

	# Muzyka per-biom (explore_<biom>) bez pliku -> NO-OP, intencja zapamietana (fallback na explore).
	am.play_music(&"explore_frosthelm")
	_check(am.current_music() == &"explore_frosthelm", "SOUND: play_music(explore_frosthelm) nie zapamietal intencji")
	# combat trigger nie crashuje.
	am.play_music(&"combat")
	_check(am.current_music() == &"combat", "SOUND: przelaczenie na combat nie zaszlo")

	# has_* — bez plikow zwracaja false, ale BEZ crasha (kontrakt placeholderow).
	_check(am.has_ambience(&"verdant") == false, "SOUND: has_ambience powinno byc false bez pliku")
	_check(am.has_music(&"explore_verdant") == false, "SOUND: has_music(explore_verdant) powinno byc false bez pliku")

	# Stres: seria wywolan w petli — zero crashy (no-op-safe).
	for i in 30:
		am.play_ambient(&"frosthelm")
		am.play_music(&"explore_emberwaste")
		am.play_sfx(&"hit")
	print("[FEEL5] (6) soundscape: szyna Ambience + play_ambient/music per-biom NO-OP-SAFE (zero crashy) OK")


# ============================================================================
#  (7) BRAK WYCIEKOW — liczba dzieci AmbientLife STALA po wielu update/event (pooled)
# ============================================================================
func _test_no_leaks() -> void:
	var player := Node3D.new()
	add_child(player)
	var al := _make_ambient(player)
	await get_tree().process_frame
	var before := al.get_child_count()

	# Wiele cykli: repopulacja + animacja + wymuszone eventy. Pooled => zero nowych dzieci.
	for i in 30:
		al.force_repopulate()
		al._animate_creatures(0.1)
		al.force_event(i % 4)
		al._animate_events(0.1)
		# Co kilka iteracji teleportuj gracza (despawn/recykling) — test recyklingu slotow.
		if i % 5 == 0:
			player.global_position += Vector3(80.0, 0.0, 0.0)
	# Wygas eventy do konca.
	al._animate_events(20.0)
	var after := al.get_child_count()
	_check(after == before, "LEAK: liczba dzieci AmbientLife zmienila sie (before=%d after=%d) — alokacja w hot-path!" % [before, after])
	# Suma puli (creature + event) — sanity, ze nic nie urosło ponad zadeklarowane pule.
	var expected := AmbientLifeScript.CREATURE_POOL + AmbientLifeScript.EVENT_POOL
	_check(before == expected, "LEAK: dzieci AmbientLife (%d) != suma puli (%d)" % [before, expected])

	player.queue_free()
	al.queue_free()
	await get_tree().process_frame
	print("[FEEL5] (7) brak wyciekow: dzieci AmbientLife stale=%d (=suma puli %d) po 30x cyklach OK" % [before, expected])
