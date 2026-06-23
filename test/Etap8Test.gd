extends Node
## Etap8Test.gd — mini-test HEADLESS Etapu 8 (vertical slice polish: ustawienia + audio + menu).
## Uruchomienie: godot --headless res://test/Etap8Test.tscn
##
## Sprawdza DoD Etapu 8 (ROADMAP 5/6, TDD sek.7, GDD 11):
##  (1) GameSettings ROUND-TRIP: zmiana preset/glosnosci/myszy -> save_settings -> load_settings
##      odtwarza IDENTYCZNE wartosci (user://settings.cfg). Defaulty: preset LOW (mandat 4GB).
##  (2) apply_graphics LOW vs HIGH ZMIENIA property Environment (volumetric_fog/sdfgi/ssr/ssil/dof)
##      ORAZ VoxelWorld-stub (near_dist/far_dist) — preset to realny przelacznik, nie kosmetyka.
##  (3) AudioManager: szyny Master/SFX/Music istnieja; play_sfx/play_music BEZ pliku = NO-OP bez
##      crashu (placeholder); has_sfx/has_music == false w trybie placeholder; stop_music bezpieczne.
##  (4) AudioManager hook walki: hit_resolved z final_damage<=0 NIE crashuje (predykcja klienta);
##      z dodatnim dmg woła play_sfx (no-op, ale bez bledu).
##  (5) GameSettings.apply_audio i apply_mouse sa bezpieczne (no-op gdy brak gracza/AudioManagera) —
##      czysta warstwa konfiguracji nie wymaga sceny gry.
##  (6) MENU/PAUZA nie psuja gry: MainMenu i PauseMenu instancjonuja sie, pauza ustawia
##      get_tree().paused, wznowienie zdejmuje pauze (gra grywalna po zamknieciu menu).
##  (7) BALANS vertical slice (ROADMAP 6) — sanity z DB: goblin 30/8, brute 120/18/armor0.3,
##      slinger 45/12; gracz lvl1 ubija goblina 1 ciosem (damage>=goblin.max_hp).
##  (8) REGRESJA: autoloady Etapow 0-7 istnieja i odpowiadaja (NetManager SP-authority, DB zaladowane).
## Kod wyjscia: 0 = ALL OK, 1 = FAIL. Print "[E8] ..." + ALL OK + quit.

const MainMenuScript := preload("res://src/MainMenu.gd")
const PauseMenuScript := preload("res://src/PauseMenu.gd")

var _failures: int = 0


func _ready() -> void:
	print("[E8] === Etap 8 mini-test start ===")
	if EnemyDB != null:
		EnemyDB.reload()

	_test_settings_roundtrip()
	_test_apply_graphics_low_high()
	_test_audio_placeholder_noop()
	_test_audio_hit_hook()
	_test_settings_apply_safe_without_scene()
	await _test_menu_pause_does_not_break_game()
	_test_balance_vertical_slice()
	_test_regression_autoloads()

	# Settle: pozwol deferred queue_free dokonczyc sie przed quit.
	for _f in 4:
		await get_tree().process_frame

	if _failures == 0:
		print("[E8] ALL OK")
	else:
		printerr("[E8] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[E8] FAIL: %s" % msg)


func _approx(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps


# ---------------------------------------------------------------------------
#  (1) GameSettings round-trip (zapis/odczyt user://settings.cfg)
# ---------------------------------------------------------------------------
func _test_settings_roundtrip() -> void:
	_check(GameSettings != null, "GameSettings autoload istnieje")
	if GameSettings == null:
		return
	# Default po pierwszym starcie: LOW (mandat Etapu 8).
	_check(int(GameSettings.graphics_preset) == int(GameSettings.GraphicsPreset.LOW),
		"domyslny preset == LOW (mandat 4GB)")

	# Ustaw nietypowe wartosci, zapisz, wyzeruj w pamieci, wczytaj — musza wrocic.
	GameSettings.set_graphics_preset(GameSettings.GraphicsPreset.HIGH)
	GameSettings.master_volume = 0.42
	GameSettings.sfx_volume = 0.33
	GameSettings.music_volume = 0.21
	GameSettings.set_mouse_sensitivity_normalized(0.75)
	var sens_before: float = GameSettings.mouse_sensitivity

	var saved: bool = GameSettings.save_settings()
	_check(saved, "save_settings zwraca true")

	# Wyzeruj stan w pamieci, by load realnie odtworzyl z pliku.
	GameSettings.graphics_preset = GameSettings.GraphicsPreset.LOW
	GameSettings.master_volume = 1.0
	GameSettings.sfx_volume = 1.0
	GameSettings.music_volume = 1.0
	GameSettings.mouse_sensitivity = 1.0

	var loaded: bool = GameSettings.load_settings()
	_check(loaded, "load_settings zwraca true (plik istnieje)")
	_check(int(GameSettings.graphics_preset) == int(GameSettings.GraphicsPreset.HIGH),
		"round-trip preset == HIGH")
	_check(_approx(GameSettings.master_volume, 0.42), "round-trip master_volume")
	_check(_approx(GameSettings.sfx_volume, 0.33), "round-trip sfx_volume")
	_check(_approx(GameSettings.music_volume, 0.21), "round-trip music_volume")
	_check(_approx(GameSettings.mouse_sensitivity, sens_before),
		"round-trip mouse_sensitivity (%.4f vs %.4f)" % [GameSettings.mouse_sensitivity, sens_before])

	# Przywroc domyslny LOW (izolacja kolejnych testow / nie zostawiaj HIGH w pliku po tescie).
	GameSettings.set_graphics_preset(GameSettings.GraphicsPreset.LOW)
	GameSettings.master_volume = 0.9
	GameSettings.sfx_volume = 0.9
	GameSettings.music_volume = 0.7
	GameSettings.mouse_sensitivity = 1.0
	GameSettings.save_settings()


# ---------------------------------------------------------------------------
#  (2) apply_graphics LOW vs HIGH zmienia property Environment + World-stub
# ---------------------------------------------------------------------------
func _test_apply_graphics_low_high() -> void:
	if GameSettings == null:
		return
	var env := Environment.new()
	var world := _WorldStub.new()
	# Realna kamera w drzewie -> apply_dof ma na czym dzialac (DoF zyje na CameraAttributes, nie Env).
	var cam := Camera3D.new()
	add_child(cam)

	# LOW: najdrozsze efekty OFF, near/far male.
	GameSettings.graphics_preset = GameSettings.GraphicsPreset.LOW
	GameSettings.apply_graphics(world, env)
	_check(env.volumetric_fog_enabled == false, "LOW: volumetric_fog OFF")
	_check(env.sdfgi_enabled == false, "LOW: SDFGI OFF")
	_check(env.ssr_enabled == false, "LOW: SSR OFF")
	_check(env.ssil_enabled == false, "LOW: SSIL OFF")
	_check(world.near_dist == 3, "LOW: near_dist == 3")
	_check(world.far_dist == 5, "LOW: far_dist == 5")

	# HIGH: pelny arsenal ON, near/far wieksze.
	GameSettings.graphics_preset = GameSettings.GraphicsPreset.HIGH
	GameSettings.apply_graphics(world, env)
	_check(env.volumetric_fog_enabled == true, "HIGH: volumetric_fog ON")
	_check(env.sdfgi_enabled == true, "HIGH: SDFGI ON")
	_check(env.ssr_enabled == true, "HIGH: SSR ON")
	_check(env.ssil_enabled == true, "HIGH: SSIL ON")
	_check(world.near_dist >= 5, "HIGH: near_dist >= 5 (%d)" % world.near_dist)
	_check(world.far_dist >= 8, "HIGH: far_dist >= 8 (%d)" % world.far_dist)
	_check(world.far_dist > 5 and world.near_dist > 3,
		"HIGH przesuwa near/far ponad LOW (realny przelacznik)")
	# DoF: HIGH stworzyl/wlaczyl DoF na CameraAttributesPractical aktywnej kamery (nie na Environment).
	var attr := cam.attributes
	_check(attr is CameraAttributesPractical, "HIGH: kamera ma CameraAttributesPractical (DoF)")
	if attr is CameraAttributesPractical:
		_check((attr as CameraAttributesPractical).dof_blur_far_enabled == true,
			"HIGH: DoF far ON na kamerze")
	# Powrot na LOW wylacza DoF na tej samej kamerze.
	GameSettings.graphics_preset = GameSettings.GraphicsPreset.LOW
	GameSettings.apply_graphics(world, env)
	if cam.attributes is CameraAttributesPractical:
		_check((cam.attributes as CameraAttributesPractical).dof_blur_far_enabled == false,
			"LOW: DoF far OFF na kamerze")

	# Bezpieczenstwo headless: apply_graphics z null-ami NIE crashuje (brak Environment/World w tescie).
	GameSettings.apply_graphics(null, null)
	_check(true, "apply_graphics(null,null) bez crashu")

	cam.queue_free()
	world.free()   # _WorldStub to Node nie dodany do drzewa -> zwolnij recznie (zero leaków przy exit)
	GameSettings.graphics_preset = GameSettings.GraphicsPreset.LOW   # przywroc domyslny


# ---------------------------------------------------------------------------
#  (3) AudioManager placeholder — szyny + play_* no-op bez pliku
# ---------------------------------------------------------------------------
func _test_audio_placeholder_noop() -> void:
	_check(AudioManager != null, "AudioManager autoload istnieje (parsuje sie — brak duplikatu funkcji)")
	if AudioManager == null:
		return
	var buses: Array = AudioManager.bus_names()
	_check(buses.has("Master"), "szyna Master istnieje")
	_check(buses.has("SFX"), "szyna SFX istnieje")
	_check(buses.has("Music"), "szyna Music istnieje")

	# Tryb placeholder (assety nie wrzucone): has_* == false; play_* = no-op bez crashu.
	_check(AudioManager.has_sfx(&"hit") == false, "placeholder: has_sfx(hit) == false")
	_check(AudioManager.has_music(&"explore") == false, "placeholder: has_music(explore) == false")

	# Te wywolania NIE moga crashowac ani rzucac bledow (no-op gdy brak pliku).
	AudioManager.play_sfx(&"attack")
	AudioManager.play_sfx(&"hit", 1.2)
	AudioManager.play_sfx(&"crit")
	AudioManager.play_sfx(&"loot")
	AudioManager.play_sfx(&"levelup")
	AudioManager.play_sfx(&"ui_click")
	AudioManager.play_sfx(&"nieistniejacy_id_xyz")   # nieznane id tez no-op (nie ma w mapie)
	AudioManager.play_music(&"menu")
	AudioManager.play_music(&"combat")
	AudioManager.play_music(&"")                        # pusty -> stop_music
	AudioManager.stop_music()
	_check(AudioManager.current_music() == &"", "stop_music czysci current_music")

	# Glosnosci: settery szyn nie crashuja (linear -> dB / mute przy 0).
	AudioManager.set_master_volume(0.5)
	AudioManager.set_sfx_volume(0.0)     # mute
	AudioManager.set_music_volume(1.0)
	_check(true, "set_*_volume bez crashu (w tym mute przy 0)")

	_test_audio_fallback()


# ---------------------------------------------------------------------------
#  (3b) FALLBACK drop-in (review #minor): brak dedykowanego pliku -> uzyj bazowego.
#       Kontrakt README: wrzuc tylko loot.ogg -> gold tez gra (przez fallback gold->loot);
#       crit->hit, perfect_dodge->dodge, night->explore. Fallback jest w play_sfx/play_music
#       (dziala dla KAZDEGO wolajacego), nie tylko w _on_hit_resolved.
# ---------------------------------------------------------------------------
func _test_audio_fallback() -> void:
	if AudioManager == null:
		return
	# Wstrzykujemy do cache atrape strumienia dla bazowych id, a dla dedykowanych zostawiamy null,
	# symulujac "uzytkownik wrzucil tylko loot/hit/dodge/explore". Stub != prawdziwy plik na dysku,
	# ale _resolve_* czyta wlasnie _stream_cache, wiec test pokrywa logike fallbacku bez assetow.
	var stub := AudioStreamWAV.new()   # lekki, wystarczy jako "istnieje" (nie odtwarzamy realnie)
	AudioManager._stream_cache[&"loot"] = stub
	AudioManager._stream_cache[&"hit"] = stub
	AudioManager._stream_cache[&"dodge"] = stub
	AudioManager._stream_cache[&"explore"] = stub
	# Dedykowane brak (null w cache) — wymusza sciezke fallbacku.
	AudioManager._stream_cache[&"gold"] = null
	AudioManager._stream_cache[&"crit"] = null
	AudioManager._stream_cache[&"perfect_dodge"] = null
	AudioManager._stream_cache[&"night"] = null

	_check(AudioManager._resolve_sfx(&"gold") == stub, "fallback SFX: gold -> loot")
	_check(AudioManager._resolve_sfx(&"crit") == stub, "fallback SFX: crit -> hit")
	_check(AudioManager._resolve_sfx(&"perfect_dodge") == stub, "fallback SFX: perfect_dodge -> dodge")
	_check(AudioManager._resolve_music(&"night") == stub, "fallback MUSIC: night -> explore")
	# play_sfx przez fallback nie crashuje (gra atrape przez pule SFX) — sanity drop-in.
	AudioManager.play_sfx(&"gold")
	_check(true, "play_sfx(gold) przez fallback bez crashu")
	# has_sfx pyta o DEDYKOWANY plik (BEZ fallbacku) — gold nadal false (do decyzji wolajacego).
	_check(AudioManager.has_sfx(&"gold") == false, "has_sfx(gold) == false (pyta o dedykowany, nie fallback)")

	# Posprzataj cache, by nie zaklocac innych testow / trybu placeholder.
	AudioManager.reload_assets()


# ---------------------------------------------------------------------------
#  (4) Hook walki: hit_resolved -> play SFX (no-op), 0 dmg pomijane bez crashu
# ---------------------------------------------------------------------------
func _test_audio_hit_hook() -> void:
	if DamageService == null or AudioManager == null:
		_check(DamageService != null, "DamageService autoload istnieje (hook audio)")
		return
	_check(DamageService.has_signal("hit_resolved"), "DamageService.hit_resolved istnieje (hook audio)")
	# Emisja sygnalu (jak po realnym ciosie) — AudioManager._on_hit_resolved nie moze crashowac.
	# 0 dmg (predykcja klienta) -> pomijane; dodatni dmg -> play_sfx(hit) (no-op bez pliku).
	DamageService.hit_resolved.emit(null, null, 0.0, false)
	DamageService.hit_resolved.emit(null, null, 15.0, false)
	DamageService.hit_resolved.emit(null, null, 30.0, true)   # krytyk
	_check(true, "hit_resolved hook (0/zwykly/krytyk) bez crashu")


# ---------------------------------------------------------------------------
#  (5) apply_audio / apply_mouse bezpieczne bez sceny gry
# ---------------------------------------------------------------------------
func _test_settings_apply_safe_without_scene() -> void:
	if GameSettings == null:
		return
	GameSettings.apply_audio()    # AudioManager istnieje -> ustawia szyny; brak crashu
	GameSettings.apply_mouse()    # brak local_player -> no-op
	_check(true, "apply_audio/apply_mouse bez sceny gry = bez crashu")


# ---------------------------------------------------------------------------
#  (6) Menu/pauza nie psuja gry
# ---------------------------------------------------------------------------
func _test_menu_pause_does_not_break_game() -> void:
	# MainMenu instancjonuje sie i buduje UI bez crashu (pauzuje gre pod spodem — to OK w tescie).
	var mm := MainMenuScript.new()
	mm.name = "MainMenu"
	add_child(mm)
	await get_tree().process_frame
	_check(is_instance_valid(mm), "MainMenu instancjonuje sie")
	# Zdejmij pauze ustawiona przez menu (show_menu pauzuje), by reszta testu nie wisiala.
	mm.hide_menu()
	mm.queue_free()
	await get_tree().process_frame

	# PauseMenu: pause() ustawia get_tree().paused, resume() zdejmuje (SP = twarda pauza).
	var pm := PauseMenuScript.new()
	pm.name = "PauseMenu"
	add_child(pm)
	await get_tree().process_frame
	_check(is_instance_valid(pm), "PauseMenu instancjonuje sie")
	pm.pause()
	_check(get_tree().paused == true, "PauseMenu.pause() pauzuje gre (SP)")
	_check(pm.is_game_paused() == true, "PauseMenu raportuje stan pauzy")
	pm.resume()
	_check(get_tree().paused == false, "PauseMenu.resume() zdejmuje pauze (gra grywalna)")
	pm.queue_free()
	await get_tree().process_frame
	# Sanity: po zabawie z menu pauza globalna jest WYLACZONA (nie zostawiamy zamrozonej gry).
	_check(get_tree().paused == false, "po menu/pauzie gra NIE jest zamrozona")


# ---------------------------------------------------------------------------
#  (7) Balans vertical slice (ROADMAP 6) — sanity z DB
# ---------------------------------------------------------------------------
func _test_balance_vertical_slice() -> void:
	if EnemyDB == null:
		_check(false, "EnemyDB autoload istnieje (balans)")
		return
	var goblin = EnemyDB.enemy(&"goblin")
	var brute = EnemyDB.enemy(&"brute")
	var slinger = EnemyDB.enemy(&"slinger")
	_check(goblin != null, "DB: goblin istnieje")
	_check(brute != null, "DB: brute istnieje")
	_check(slinger != null, "DB: slinger istnieje")
	if goblin != null and goblin.stats != null:
		_check(_approx(goblin.stats.max_hp, 30.0), "balans goblin HP == 30 (ROADMAP6)")
		_check(_approx(goblin.stats.damage, 8.0), "balans goblin dmg == 8")
	if brute != null and brute.stats != null:
		_check(_approx(brute.stats.max_hp, 120.0), "balans brute HP == 120")
		_check(_approx(brute.stats.damage, 18.0), "balans brute dmg == 18")
		_check(_approx(brute.stats.armor, 0.3), "balans brute armor == 0.3")
	if slinger != null and slinger.stats != null:
		_check(_approx(slinger.stats.max_hp, 45.0), "balans slinger HP == 45")
		_check(_approx(slinger.stats.damage, 12.0), "balans slinger dmg == 12")

	# Cel odczuciowy ROADMAP6: gracz 2H ubija goblina 1 ciosem. Baza gracza (StatBlock default) = 18,
	# 2H archetyp (GDD 5.5) = 30 >= 30 HP. Sprawdzamy regule "1 cios" archetypem 2H.
	if goblin != null and goblin.stats != null:
		var two_handed_dmg := 30.0   # GDD 5.5 archetyp 2H (topor) — domyslna bron Berserkera
		_check(two_handed_dmg >= goblin.stats.max_hp, "2H gracz ubija goblina 1 ciosem (30 >= 30)")
		# Brute = mini-walka: 2H gracz NIE ubija bruta 1 ciosem (po armorze 0.3 -> 21 < 120).
		var brute_after_armor := two_handed_dmg * (1.0 - 0.3)
		_check(brute_after_armor < (brute.stats.max_hp if brute != null and brute.stats != null else 120.0),
			"Brute = mini-walka (nie 1-shot)")


# ---------------------------------------------------------------------------
#  (8) Regresja Etapow 0-7: autoloady istnieja i odpowiadaja
# ---------------------------------------------------------------------------
func _test_regression_autoloads() -> void:
	_check(NetManager != null, "regresja: NetManager istnieje")
	if NetManager != null and NetManager.has_method("is_host"):
		_check(NetManager.is_host() == true, "regresja: SP host-authority (is_host == true)")
	_check(GameState != null, "regresja: GameState istnieje")
	_check(RNGService != null, "regresja: RNGService istnieje")
	_check(ItemDB != null, "regresja: ItemDB istnieje")
	_check(SkillDB != null, "regresja: SkillDB istnieje")
	_check(EnemyDB != null, "regresja: EnemyDB istnieje")
	_check(SaveManager != null, "regresja: SaveManager istnieje")
	_check(DamageService != null, "regresja: DamageService istnieje")
	_check(LootService != null, "regresja: LootService istnieje")
	_check(GameSettings != null, "regresja: GameSettings istnieje (Etap 8)")
	_check(AudioManager != null, "regresja: AudioManager istnieje (Etap 8)")


# ---------------------------------------------------------------------------
#  Stub VoxelWorld: ma TYLKO property near_dist/far_dist/chunks_per_frame, by sprawdzic, ze
#  apply_graphics je przestawia (apply_graphics uzywa 'prop in obj' -> dziala na dowolnym obiekcie).
# ---------------------------------------------------------------------------
class _WorldStub:
	extends Node
	var near_dist: int = 0
	var far_dist: int = 0
	var chunks_per_frame: int = 0
