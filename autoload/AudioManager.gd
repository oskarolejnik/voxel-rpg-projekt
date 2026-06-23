extends Node
## AudioManager.gd (autoload) — ETAP 8. Centralny system dzwieku: szyny Master/SFX/Music
## (AudioServer) + API play_sfx(id)/play_music(id) podpiete pod istniejace sygnaly walki/lootu/
## progresji/cyklu doby.
##
## ZASADA BEZPIECZNYCH PLACEHOLDEROW (mandat Etapu 8): NIE dolaczamy plikow dzwiekowych — uzytkownik
## wrzuci CC0 na koncu. System DZIALA OD RAZU: gdy plik dla danego id NIE istnieje, play_sfx/play_music
## to NO-OP (zero crashy, zero bledow w logu poza jednorazowym info). Po wrzuceniu plikow do
## res://assets/audio/sfx/ i .../music/ (wg manifestu README) dzwiek gra BEZ ZMIANY KODU (drop-in).
##
## Szyny tworzymy W KODZIE (AudioServer), wiec projekt nie zalezy od default_bus_layout.tres:
##   Master (bus 0, zawsze istnieje) <- SFX, Music (dzieci Mastera). Glosnosci ustawia GameSettings.
##
## Mapowanie id -> sciezka pliku jest deklaratywne (SFX_FILES / MUSIC_FILES). Dodanie nowego dzwieku
## = dodanie wpisu + wrzucenie pliku; reszta (cache, no-op gdy brak) dziala automatycznie.

# Nazwy szyn audio (spojne z GameSettings: master/sfx/music volume).
const BUS_MASTER := &"Master"
const BUS_SFX := &"SFX"
const BUS_MUSIC := &"Music"

# Katalogi assetow (uzytkownik wrzuca tu pliki CC0 — patrz assets/audio/README.md).
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"

# Mapowanie logicznych id -> nazwa pliku. Obsuluje kilka rozszerzen (ogg/wav/mp3) — bierzemy
# pierwsze ISTNIEJACE. Brak pliku = play to no-op (placeholder). Lista pokrywa hooki Etapu 8.
const SFX_FILES := {
	&"attack": "attack",            # zamach gracza (LMB)
	&"hit": "hit",                  # trafienie wroga
	&"crit": "crit",                # trafienie krytyczne (osobny akcent; fallback na hit)
	&"player_hurt": "player_hurt",  # gracz oberwal
	&"death": "death",              # smierc wroga
	&"player_death": "player_death",# smierc gracza
	&"loot": "loot",                # podniesiony loot (item)
	&"gold": "gold",                # podniesione zloto (fallback na loot)
	&"levelup": "levelup",          # awans poziomu
	&"ability": "ability",          # finisher/skill zasobu klasy (R)
	&"dodge": "dodge",              # unik/dash
	&"perfect_dodge": "perfect_dodge", # udany perfect-dodge (fallback na dodge)
	&"ui_click": "ui_click",        # klikniecie w menu
}

const MUSIC_FILES := {
	&"explore": "explore",          # spokojna eksploracja (dzien)
	&"combat": "combat",            # walka
	&"night": "night",              # noc/ambient (fallback na explore)
	&"menu": "menu",                # menu glowne
}

# FALLBACKI drop-in (kontrakt README "wrzuc plik -> dziala"): gdy brak DEDYKOWANEGO pliku dla id,
# uzyj pliku BAZOWEGO. Dzieki temu uzytkownik, ktory wrzuci tylko loot.ogg, slyszy go takze przy
# zlocie (gold), a crit/perfect_dodge dziedzicza po hit/dodge. Fallback jest W play_sfx/play_music
# (nie w wolajacym), wiec obietnica manifestu dziala dla KAZDEGO wolajacego, nie tylko crit.
const SFX_FALLBACK := {
	&"gold": &"loot",
	&"crit": &"hit",
	&"perfect_dodge": &"dodge",
}
const MUSIC_FALLBACK := {
	&"night": &"explore",
}

const EXTENSIONS: Array[String] = [".ogg", ".wav", ".mp3"]

# Pula playerow SFX (round-robin) — kilka rownoczesnych dzwiekow bez ucinania.
const SFX_POOL_SIZE := 12
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0

# Player muzyki (jeden strumien, crossfade-lite przez prosty restart).
var _music_player: AudioStreamPlayer
var _current_music: StringName = &""

# Cache zaladowanych strumieni id->AudioStream (lub null = brak pliku, juz sprawdzony).
var _stream_cache: Dictionary = {}

# Czy w ogole zglosilismy info o trybie placeholder (zeby nie spamic logu).
var _warned_placeholder: bool = false


func _ready() -> void:
	# Audio dziala nawet gdy gra jest spauzowana (menu pauzy) — inaczej muzyka menu by zamarla.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_build_players()
	# Glosnosc startowa z GameSettings (jesli autoload istnieje). Kolejnosc w project.godot:
	# GameSettings PRZED AudioManager, wiec wartosci sa juz wczytane z user://settings.cfg.
	if GameSettings != null and GameSettings.has_method("apply_audio"):
		GameSettings.apply_audio()
	# CENTRALNY hook walki: po kazdym rozstrzygnietym trafieniu graj "crit" (krytyk) lub "hit".
	# To jedyny sygnal autoloadowy, ktory wystarczy podpiac tutaj — atak/loot/smierc/levelup woła
	# Main (zdarzenia nie-autoloadowe), zachowujac jedno miejsce decyzji o kazdym dzwieku.
	if DamageService != null and DamageService.has_signal("hit_resolved"):
		DamageService.hit_resolved.connect(_on_hit_resolved)


## Po kazdym rozstrzygnietym trafieniu: krytyk -> "crit" (fallback na hit gdy brak pliku), zwykle
## obrazenia -> "hit". 0 dmg (predykcja klienta / cios pochloniety) pomijamy, by nie spamowac.
func _on_hit_resolved(_source: Node, _target: Node, final_damage: float, was_crit: bool) -> void:
	if final_damage <= 0.0:
		return
	if was_crit and has_sfx(&"crit"):
		play_sfx(&"crit")
	else:
		play_sfx(&"hit")


# ============================================================================
#  SZYNY (AudioServer) — tworzone w kodzie, niezalezne od bus_layout.tres
# ============================================================================
## Tworzy szyny SFX i Music jako dzieci Mastera, jesli jeszcze nie istnieja. Idempotentne
## (po reimporcie/restartcie nie duplikuje). Master (index 0) zawsze istnieje w Godocie.
func _ensure_buses() -> void:
	_ensure_bus(BUS_SFX)
	_ensure_bus(BUS_MUSIC)


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, String(bus_name))
	AudioServer.set_bus_send(idx, String(BUS_MASTER))


func _build_players() -> void:
	# Pula SFX.
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = String(BUS_SFX)
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx_players.append(p)
	# Muzyka.
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = String(BUS_MUSIC)
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)


# ============================================================================
#  GLOSNOSC (woła GameSettings.apply_audio) — linear 0..1 -> dB na szynie
# ============================================================================
## Ustawia glosnosc szyny (linear 0..1). volume<=0 -> mute (cisza), inaczej linear->dB.
func set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.0001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


func set_master_volume(linear: float) -> void:
	set_bus_volume(BUS_MASTER, linear)


func set_sfx_volume(linear: float) -> void:
	set_bus_volume(BUS_SFX, linear)


func set_music_volume(linear: float) -> void:
	set_bus_volume(BUS_MUSIC, linear)


# ============================================================================
#  API ODTWARZANIA — bezpieczne placeholdery (no-op gdy brak pliku)
# ============================================================================
## Odtwarza efekt dzwiekowy o danym id. Gdy plik nie istnieje -> NO-OP (placeholder, zero crashy).
## pitch_scale pozwala lekko zroznicowac powtarzajace sie dzwieki (np. seria ciosow). Bezpieczne
## w headless (--audio-driver Dummy) i gdy assety nie sa jeszcze wrzucone.
func play_sfx(id: StringName, pitch_scale: float = 1.0) -> void:
	var stream := _resolve_sfx(id)
	if stream == null:
		_note_placeholder()
		return
	var p := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = stream
	p.pitch_scale = clampf(pitch_scale, 0.5, 2.0)
	p.play()


## Odtwarza muzyke o danym id (zapetlona). Ten sam utwor juz gra -> nic (brak restartu). Brak pliku
## -> NO-OP. Zatrzymanie biezacej muzyki: stop_music(). id == &"" -> stop_music().
func play_music(id: StringName) -> void:
	if id == &"":
		stop_music()
		return
	if id == _current_music and _music_player != null and _music_player.playing:
		return
	var stream := _resolve_music(id)
	if stream == null:
		_current_music = id   # zapamietaj intencje; gdy plik dolozą i zmieni sie kontekst, ruszy
		_note_placeholder()
		return
	_current_music = id
	# Zapetlenie: jesli import nie ustawil loop, wymuszamy go dla strumieni wspierajacych loop.
	_apply_loop(stream)
	if _music_player != null:
		_music_player.stream = stream
		_music_player.play()


func stop_music() -> void:
	_current_music = &""
	if _music_player != null:
		_music_player.stop()


func current_music() -> StringName:
	return _current_music


## Czy DEDYKOWANY plik SFX dla danego id istnieje (BEZ fallbacku). Uzywane do warunkowych decyzji
## w wolajacym (np. _on_hit_resolved sprawdza, czy jest osobny crit, zanim zdecyduje crit vs hit).
## Brak fallbacku tutaj jest CELOWY: has_sfx pyta o KONKRETNY plik, nie o "czy cokolwiek zagra".
func has_sfx(id: StringName) -> bool:
	return _get_stream(id, SFX_DIR, SFX_FILES) != null


## Czy DEDYKOWANY plik muzyki dla danego id istnieje (BEZ fallbacku, np. czy jest osobna night).
func has_music(id: StringName) -> bool:
	return _get_stream(id, MUSIC_DIR, MUSIC_FILES) != null


## Rozwiazuje strumien SFX z FALLBACKIEM (kontrakt drop-in). Najpierw dedykowany plik id; gdy brak,
## probuje plik bazowy z SFX_FALLBACK (gold->loot, crit->hit, perfect_dodge->dodge). null gdy obu brak.
func _resolve_sfx(id: StringName) -> AudioStream:
	var s := _get_stream(id, SFX_DIR, SFX_FILES)
	if s != null:
		return s
	if SFX_FALLBACK.has(id):
		return _get_stream(SFX_FALLBACK[id], SFX_DIR, SFX_FILES)
	return null


## Rozwiazuje strumien muzyki z FALLBACKIEM (np. night->explore). null gdy obu brak.
func _resolve_music(id: StringName) -> AudioStream:
	var s := _get_stream(id, MUSIC_DIR, MUSIC_FILES)
	if s != null:
		return s
	if MUSIC_FALLBACK.has(id):
		return _get_stream(MUSIC_FALLBACK[id], MUSIC_DIR, MUSIC_FILES)
	return null


# ============================================================================
#  Ladowanie strumieni (cache + tolerancja braku pliku)
# ============================================================================
## Zwraca AudioStream dla id lub null (brak pliku -> placeholder). Cache'uje wynik (w tym null),
## by nie sprawdzac dysku przy kazdym ciosie. Probuje rozszerzen z EXTENSIONS po kolei.
func _get_stream(id: StringName, dir: String, table: Dictionary) -> AudioStream:
	if _stream_cache.has(id):
		var c = _stream_cache[id]
		return c as AudioStream   # null tez jest poprawnym (zacache'owanym) wynikiem
	var base: String = table.get(id, String(id))
	var found: AudioStream = null
	for ext in EXTENSIONS:
		var path: String = dir + base + String(ext)
		if ResourceLoader.exists(path):
			var res := ResourceLoader.load(path)
			if res is AudioStream:
				found = res as AudioStream
				break
	_stream_cache[id] = found
	return found


## Wymusza zapetlenie dla typow strumieni, ktore to wspieraja (muzyka ma grac w petli niezaleznie
## od ustawien importu pliku CC0). Bezpieczne dla typow bez loop.
func _apply_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD


func _note_placeholder() -> void:
	if _warned_placeholder:
		return
	_warned_placeholder = true
	print("[AudioManager] Tryb placeholder: brak plikow audio w assets/audio/ — play_sfx/play_music",
		" sa no-op. Wrzuc pliki CC0 wg assets/audio/README.md, dzwiek ruszy bez zmian w kodzie.")


## Czysci cache strumieni (np. po wrzuceniu nowych plikow w trakcie dzialania edytora). Opcjonalne.
func reload_assets() -> void:
	_stream_cache.clear()
	_warned_placeholder = false


# ============================================================================
#  STATUS / DIAGNOSTYKA (uzywane przez Etap8Test)
# ============================================================================
## Lista nazw szyn audio (oczekiwane min.: Master, SFX, Music) — sanity dla testu.
func bus_names() -> Array:
	var out: Array = []
	for i in AudioServer.bus_count:
		out.append(AudioServer.get_bus_name(i))
	return out
