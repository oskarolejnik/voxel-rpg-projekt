class_name VoxelWorld
extends Node3D
## VoxelWorld.gd — menedżer proceduralnego świata voxelowego.
##
## Odpowiada za:
##  1) szum (FastNoiseLite) i deterministyczną heightmapę surface_height(),
##  2) współdzielone materiały (stały + woda + propy) — jeden na cały świat (batching),
##  3) streaming chunków wokół gracza (render_distance) z kolejką budowania,
##  4) helpery do spawnu gracza: height_at() oraz prime() (natychmiastowy teren startowy),
##  5) „kill plane” — gdyby gracz wypadł pod świat, podnosi go z powrotem na grunt,
##  6) deterministyczny hash pozycji świata (feature_hash) dla roślinności/obiektów/propów.
##
## Player.gd NIE jest modyfikowany — gracz dostaje pozycję z Main.gd.

# --- Stałe streamingu / skali (styl Cube World: voxel 0,5 m) ---
# UWAGA: definiujemy je WPROST (a nie czytamy z VoxelChunk.*), aby uniknąć
# cyklicznej zależności const-od-innej-klasy z class_name (ryzyko „Could not resolve class”).
# MUSZĄ być IDENTYCZNE z odpowiednikami w Chunk.gd.
#
# REGUŁA SKALI: wszystko w METRACH (pozycje, height_at, world_to_chunk, kill plane)
# liczymy przez CHUNK_SIZE * VOXEL_SIZE i * VOXEL_SIZE. Wszystko w VOXELACH
# (progi biomów, SEA_LEVEL, amplituda szumu, pętle) podwajamy względem wersji 1 m.
#   CHUNK_SIZE=32 voxele × 0,5 = 16 m (bez zmian realnie)
#   WORLD_HEIGHT=96 voxeli × 0,5 = 48 m (bez zmian realnie)
#   SEA_LEVEL=24 voxeli × 0,5 = 12 m (bez zmian realnie)
const CHUNK_SIZE: int = 32           # 32 voxele = 16 m
const WORLD_HEIGHT: int = 96         # 96 voxeli = 48 m
const SEA_LEVEL: int = 24            # 24 voxeli = 12 m
const VOXEL_SIZE: float = 0.5        # 0,5 m/voxel (styl Cube World)

# --- LOD / zasięg (Faza 2B): render_distance ROZBITY na dwa pierścienie (w chunkach) ---
# NEAR (<= near_dist): pełny detal + kolizja + propy + woda (ścieżka 2A, _lod_step=1).
# FAR  (near_dist < r <= far_dist): zgrubny step=2, BEZ kolizji/propów/wody (_lod_step=2).
# far_dist = najdalszy budowany pierścień => render_distance to teraz alias far_dist.
# 4 -> 7 daje 64 m -> 112 m zasięgu, a koszt rośnie głównie na TANICH chunkach FAR.
@export var near_dist: int = 3           # promień pełnego detalu (3 × 16 m = 48 m) — odchudzone na 4GB
@export var far_dist: int = 5            # najdalszy zgrubny pierścień (5 × 16 m = 80 m) — mniej draw calls/VRAM
@export var chunks_per_frame: int = 2    # ile NOWYCH zadań submitujemy max/klatkę (throttling submitu)

# Kroki próbkowania LOD przekazywane chunkowi (1=NEAR pełny, 2=FAR zgrubny). MUSZĄ być
# spójne z VoxelChunk.LOD_FAR_STEP (=2). Trzymamy jako stałe dla czytelności wyboru per chunk.
const LOD_STEP_NEAR: int = 1
const LOD_STEP_FAR: int = 2

## Alias zgodności: render_distance == far_dist (najdalszy budowany pierścień). Stary kod/
## debug odwołujący się do render_distance dalej działa (np. logi). Setter mapuje na far_dist.
var render_distance: int:
	get:
		return far_dist
	set(value):
		far_dist = value

# --- Streaming wielowątkowy (Faza 2A: WorkerThreadPool) ---
# MAX_IN_FLIGHT: ile zadań build_data() może chodzić RÓWNOCZEŚNIE w puli. Pula jest
# WSPÓŁDZIELONA z silnikiem (fizyka/audio/import), więc nie zalewamy jej — 3 zostawia
# wątki dla reszty na laptopie (RTX 3050 4GB). Reszta kolejki czeka w _build_queue.
const MAX_IN_FLIGHT: int = 3
# Ile finalizacji (tworzenie węzłów + add_child na GŁÓWNYM watku) wykonujemy max/klatkę.
# Limituje koszt finalize na głównym (add_child + rejestracja kolizji w PhysicsServer),
# żeby odbiór kilku gotowych chunków naraz nie dał mikro-zacięcia.
const MAX_FINALIZE_PER_FRAME: int = 1

# --- Parametry terenu (w VOXELACH) ---
# NAPRAWA SKALI BIOMÓW (review #MAJOR): poprzednio BASE=20, AMP=40 dawało
# max surface_y = round(20 + 1*40) = 60 voxeli. Próg śniegu SNOW_MIN_Y=68 był
# NIEOSIĄGALNY (śniegu w ogóle nie było), a ROCK_MIN_Y=56 dotykalny tylko na
# skrajnych pikach szumu. Podnosimy bazę i amplitudę tak, by progi biomów realnie
# się pojawiły, zachowując czytelną proporcję metrów:
#   surface_y ∈ [24, 88] voxeli  ->  realnie 12..44 m terenu nad y=0
#   BEACH ≤ 26 (13 m), ROCK ≥ 56 (28 m), SNOW ≥ 68 (34 m) — wszystkie osiągalne.
const BASE_HEIGHT: float = 14.0          # z kontrastem szumu daje jeziora (doliny) i szczyty (śnieg)
const HEIGHT_AMPLITUDE: float = 64.0     # amplituda do 64 voxeli × 0,5 = 32 m (szczyty ~44 m)
# KILL_PLANE_Y jest w METRACH (dno świata to y=0 m niezależnie od VOXEL_SIZE) — NIE podwajać.
const KILL_PLANE_Y: float = -8.0         # poniżej tego Y „ratujemy” gracza

# --- Deterministyczny hash pozycji świata -> [0,1). Stały seed => stabilny świat. ---
const FEATURE_SEED: int = 0x9E37  # stały „ziarno” roślinności

# --- ETAP 4: identyfikatory biomów (StringName). Spójne z BiomeResource.id i loot_biome wroga.
#   verdant   = Verdant Hollow (umiarkowany, tier 1, start)
#   emberwaste= Emberwaste     (pustynia/ogień, tier 2, mid)
#   frosthelm = Frosthelm Peaks(śnieg/mróz, tier 3, szczyt)
const BIOME_VERDANT: StringName = &"verdant"
const BIOME_EMBERWASTE: StringName = &"emberwaste"
const BIOME_FROSTHELM: StringName = &"frosthelm"

# Szum wysokości terenu (deterministyczny seed).
var _noise: FastNoiseLite

# Drugi, wolniejszy szum do drobnej wariacji koloru (tint per blok).
var _tint_noise: FastNoiseLite
var _biome_noise: FastNoiseLite   # regionalny biom koloru (Faza 2C) == temperatura (Etap 4)
var _humid_noise: FastNoiseLite   # ETAP 4: wilgotność (drugi wymiar podziału biomów)

# Słownik załadowanych (W DRZEWIE + sfinalizowanych) chunków: Vector2i -> VoxelChunk.
var _loaded: Dictionary = {}

# Chunki z zadaniem build_data() W LOCIE (jeszcze nie w drzewie). coord -> { "chunk":, "task":, "lod": }.
# Węzeł żyje POZA drzewem do czasu finalize() (add_child dopiero po is_task_completed).
var _pending: Dictionary = {}

# Chunki, które wypadły z zasięgu, gdy ich zadanie było w locie. coord -> { "chunk":, "task":, "lod": }.
# NIE wolno ich zwalniać dopóki task chodzi (use-after-free) — reapujemy po is_task_completed().
var _abandoned: Dictionary = {}

# REBUILD (Faza 2B): chunki, których ZAŁADOWANY LOD ≠ potrzebny — nowa wersja budowana W TLE,
# podczas gdy STARA (innego lod) wciąż wisi w _loaded i JEST WIDOCZNA. coord -> { "chunk":, "task":, "lod": }.
# Anty-migotanie: stary węzeł znika DOPIERO po finalize nowego (zero błysku/dziury na zmianie LOD).
# Niezmiennik "jeden chunk na coord" zachowany — klucz to coord, a nie (coord,lod): w danej chwili
# coord ma dokładnie jeden docelowy LOD, więc nigdy nie potrzeba dwóch wpisów naraz.
var _rebuild: Dictionary = {}

# Kolejka chunków do zbudowania: TYLKO coordy (posortowane: najbliżej najpierw).
# LOD (krok próbkowania) NIE jest tu trzymany (review #MAJOR — usuwa klasę nieaktualnego 'lod'):
# coord może wisieć w kolejce wiele klatek, a w międzyczasie gracz przekracza granicę near_dist.
# Gdybyśmy zapamiętali lod przy DODAWANIU do kolejki, chunk zbudowałby się ze STARYM lodem (np. FAR
# bezkolizyjny pod nadchodzącym graczem). Dlatego lod liczymy DOPIERO w _submit_chunk (pop), z
# AKTUALNEGO środka => wpis w kolejce nigdy nie niesie przeterminowanego lod.
var _build_queue: Array[Vector2i] = []

# Referencja do gracza (do liczenia środka streamingu i kill-plane).
var _player: Node3D = null

# Ostatnio policzony środek (w chunkach). Duża wartość startowa => pierwsze przeliczenie pewne.
var _last_center: Vector2i = Vector2i(2147483647, 2147483647)

# Współdzielone materiały (tworzone raz).
var solid_material: ShaderMaterial
var water_material: ShaderMaterial
var props_material: ShaderMaterial


func _ready() -> void:
	_setup_noise()
	_setup_materials()


# --- Konfiguracja szumu ---
func _setup_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.seed = 1337
	# /2 względem 0.014: indeksy voxeli są 2× gęstsze na ten sam metr (VOXEL_SIZE=0.5),
	# więc dzielimy częstotliwość, by wzgórza miały ten sam REALNY rozmiar.
	_noise.frequency = 0.007
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.5

	_tint_noise = FastNoiseLite.new()
	_tint_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_tint_noise.seed = 9001
	# /2 względem 0.35: ziarno ma przypadać „na voxel”, a voxele są 2× gęstsze.
	_tint_noise.frequency = 0.175

	_biome_noise = FastNoiseLite.new()
	_biome_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_biome_noise.seed = 4242
	_biome_noise.frequency = 0.0025   # duże strefy biomów koloru (anty-powtarzalność) == TEMPERATURA

	# ETAP 4: drugi niskoczęstotliwościowy szum = WILGOTNOŚĆ. Inny seed => niezależny od temperatury,
	# więc temperatura×wilgotność daje 2D podział na strefy (a nie jeden pas). Ta sama częstotliwość
	# co _biome_noise (duże, czytelne strefy). Deterministyczny: stały seed -> stały podział z mapy.
	_humid_noise = FastNoiseLite.new()
	_humid_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_humid_noise.seed = 2024
	_humid_noise.frequency = 0.0025


# --- Konfiguracja materiałów ---
func _setup_materials() -> void:
	# Stały: ShaderMaterial (Faza 0B) — vertex-color albedo (sRGB→lin w shaderze) +
	# hemisferyczny ambient + edge-AO + rim. Linearyzacja sRGB jest w shaderze, więc
	# zachowujemy soczyste barwy (zamiennik dawnego vertex_color_is_srgb).
	solid_material = ShaderMaterial.new()
	solid_material.shader = load("res://src/world/terrain.gdshader")

	# Woda: półprzezroczysta, lekko błyszcząca; albedo_color.a mnoży kolor wierzchołka.
	# Woda: stylizowany ShaderMaterial (Faza 1B) — głębia/piana z DEPTH_TEXTURE, fresnel,
	# animowana tafla. Przezroczystość i double-sided ustawia sam shader (ALPHA + cull_disabled).
	water_material = ShaderMaterial.new()
	water_material.shader = load("res://src/world/water.gdshader")

	# Propy (drobne kostki: trawa/kwiaty/grzyby): jak solid, ale to OSOBNY materiał,
	# żeby cały świat collektował się w jednym batchu propów (1 draw call/chunk).
	# Bez AO (kolory liczone w Chunk._build_*), CULL_BACK (mini-kostki to pełne sześciany).
	# Propy: ShaderMaterial z wiatrem (Faza 1A). Albedo z COLOR.rgb (sRGB→lin w shaderze),
	# waga sway z COLOR.a. Kołysanie czubków liczone w GPU (vertex), bez kosztu budowy chunku.
	props_material = ShaderMaterial.new()
	props_material.shader = load("res://src/world/props.gdshader")


## Podaje referencję gracza (woła Main.gd po spawnie).
func set_player(p: Node3D) -> void:
	_player = p

## Liczba aktualnie załadowanych chunków (diagnostyka).
func get_loaded_count() -> int:
	return _loaded.size()


# --- Heightmapa ---

## Wysokość powierzchni (indeks najwyższego stałego bloku) dla danej kolumny świata.
## Zwraca int w zakresie [1, WORLD_HEIGHT-1]. Deterministyczna.
## Weryfikacja skali (po naprawie progów biomów): round(24 + n*64) voxeli, n∈[0,1] =>
## surface_y ∈ [24, 88] voxeli × 0,5 m = 12..44 m. Dzięki temu ROCK (56=28 m) i
## SNOW (68=34 m) są realnie osiągalne (wcześniej max był 60 voxeli => brak śniegu).
func surface_height(world_x: int, world_z: int) -> int:
	# FBM ma realnie wąski zakres (~[-0.45,0.45]); mnożymy przez kontrast, by teren
	# schodził pod poziom morza (jeziora) i wybijał w szczyty (śnieg), zamiast skupiać
	# się wokół środka. clampf tworzy płaskie dna jezior i płaskowyże szczytów (OK stylistycznie).
	var raw := _noise.get_noise_2d(float(world_x), float(world_z))
	var n := clampf(raw * 1.6 + 0.5, 0.0, 1.0)
	var h := int(round(BASE_HEIGHT + n * HEIGHT_AMPLITUDE))
	return clampi(h, 1, WORLD_HEIGHT - 1)


## Drobna wariacja koloru (tint) per blok — deterministyczna z pozycji.
## Zwraca wartość ~[-0.055, 0.055]. Amplituda podbita z 0.04: drobniejsze voxele
## zniosą większy mikrokontrast i mocniej łamią „płachty jednego koloru” (Cube World).
func tint_at(world_x: int, world_y: int, world_z: int) -> float:
	var v := _tint_noise.get_noise_3d(float(world_x), float(world_y), float(world_z))
	return v * 0.055


## --- Deterministyczny hash pozycji świata -> [0,1). ---
## Wariant integerowego mixu (wang/xorshift). NIE używamy randf() — wynik MUSI być
## powtarzalny. `salt` rozróżnia niezależne „rzuty kostką”. Zwraca równomierne [0,1).
##
## UWAGA (świadome): mnożenia int mogą przekroczyć 64-bity i CICHO się zawinąć modulo
## 2^64 — to CELOWE; maska `h & 0x3FFFFFFF` sprowadza wynik do [0, 2^30). NIE „naprawiać”.
func feature_hash(wx: int, wz: int, salt: int = 0) -> float:
	var h: int = wx * 73856093
	h ^= wz * 19349663
	h ^= (FEATURE_SEED + salt) * 83492791
	h = (h ^ (h >> 13)) * 1274126177
	h ^= (h >> 16)
	# Maska do 30 bitów (dodatnie) i normalizacja do [0,1).
	return float(h & 0x3FFFFFFF) / float(0x40000000)


## Wysokość (Y wierzchu terenu, w metrach) dla pozycji w metrach — do spawnu gracza.
## POPRAWNE bez zmian skali: sy rośnie 2× (amplituda ×2), VOXEL_SIZE maleje 2× -> metry stałe.
## Regionalny współczynnik biomu koloru [-1,1] (niska częstotliwość => duże strefy). Faza 2C.
func biome_factor(world_x: int, world_z: int) -> float:
	return _biome_noise.get_noise_2d(float(world_x), float(world_z))


## ETAP 4 (DoD): zwraca ID biomu dla kolumny świata (StringName). DETERMINISTYCZNY — czysta
## funkcja niemutowanych szumów (temperatura=_biome_noise, wilgotność=_humid_noise) + stałego
## offsetu dystansu: ten sam (world_x, world_z) ZAWSZE daje ten sam biom; 3 strefy są realnie
## obecne na mapie. Spójny z biome_factor (2C) — temperatura to ten sam szum, więc paleta trawy
## (sucha/bujna w Chunk._solid_color) idzie w parze z biomem (ciepły<->Emberwaste, chłodny<->bujny).
##
## Model temperatura×wilgotność (klasyczny Whittaker-light, 3 strefy z dwuwymiarowego szumu):
##   temp = _biome_noise [-1,1]  (ciepło na +; chłód na -)
##   hum  = _humid_noise [-1,1]  (wilgotno na +; sucho na -)
##   - chłodno (temp <= COLD_T)                -> Frosthelm Peaks (mróz)
##   - ciepło (temp >= HOT_T) i SUCHO (hum<0)  -> Emberwaste (pustynia/ogień)
##   - reszta (umiarkowane / ciepłe+wilgotne)  -> Verdant Hollow (start)
## Progi dobrane tak, by każda strefa zajmowała sensowny ułamek mapy (test E4 weryfikuje 3 strefy).
const BIOME_COLD_TEMP: float = -0.15      # poniżej tego = mróz (Frosthelm)
const BIOME_HOT_TEMP: float = 0.12        # powyżej tego (i sucho) = pustynia (Emberwaste)

func get_biome(world_x: int, world_z: int) -> StringName:
	var temp := _biome_noise.get_noise_2d(float(world_x), float(world_z))   # [-1,1]
	var hum := _humid_noise.get_noise_2d(float(world_x), float(world_z))    # [-1,1]
	if temp <= BIOME_COLD_TEMP:
		return BIOME_FROSTHELM
	if temp >= BIOME_HOT_TEMP and hum < 0.0:
		return BIOME_EMBERWASTE
	return BIOME_VERDANT


## ETAP 4: tier lootu wg dystansu od spawnu (model Cube World — „skalowanie po dystansie”).
## Deterministyczny, niezależny od biomu (biom daje TEMAT lootu, dystans daje MOC/ilvl). Zwraca
## krok 1..N: 1 blisko spawnu, rośnie co RING_METERS. Używany przez spawner do ilvl wrogów.
const DISTANCE_RING_METERS: float = 80.0   # co tyle metrów od spawnu rośnie tier dystansu
const DISTANCE_TIER_MAX: int = 5

func distance_tier(world_x: float, world_z: float) -> int:
	var d := Vector2(world_x, world_z).length()
	return clampi(1 + int(floor(d / DISTANCE_RING_METERS)), 1, DISTANCE_TIER_MAX)

func height_at(x: float, z: float) -> float:
	var sy := surface_height(int(floor(x)), int(floor(z)))
	# Wierzch bloku powierzchni = (sy + 1) * VOXEL_SIZE.
	return float(sy + 1) * VOXEL_SIZE


## Zamiana pozycji świata (METRY) na współrzędne chunku.
## NAPRAWA SKALI: szerokość chunku w METRACH = CHUNK_SIZE * VOXEL_SIZE (= 32 × 0,5 = 16 m),
## a nie samo CHUNK_SIZE (=32). Bez tego streaming centruje się na złym chunku i gracz
## „goni” teren (chunki rozjeżdżają się 2× względem pozycji).
func world_to_chunk(pos: Vector3) -> Vector2i:
	var span: float = float(CHUNK_SIZE) * VOXEL_SIZE   # 16 m
	return Vector2i(floori(pos.x / span), floori(pos.z / span))


# --- Pętla streamingu (wielowątkowa: submit -> poll, BEZ blokowania głównego watku) ---
func _process(_delta: float) -> void:
	if _player == null:
		return

	var center := world_to_chunk(_player.global_position)
	if center != _last_center:
		_update_chunks(center)
		_last_center = center

	# 1) SUBMIT: dorzucaj zadania build_data() do puli, póki jest miejsce (MAX_IN_FLIGHT),
	#    coś jest w kolejce i nie przekroczyliśmy throttlingu submitu (chunks_per_frame).
	#    UWAGA (2B): MAX_IN_FLIGHT liczy _pending + _rebuild razem — rebuildy też zajmują pulę,
	#    więc nie zalewamy jej przy wielu zmianach LOD naraz (budżet wątków pod 4GB nietknięty).
	var submitted := 0
	while submitted < chunks_per_frame \
			and (_pending.size() + _rebuild.size()) < MAX_IN_FLIGHT \
			and not _build_queue.is_empty():
		var coord: Vector2i = _build_queue.pop_front()
		# Mogło się zdezaktualizować (już zbudowane / w locie / porzucone z żywym taskiem) —
		# pomiń bez liczenia submitu w dół. _abandoned (review): nie submituj drugiej instancji
		# coordu, którego stary task jeszcze chodzi (czeka na reap w _reap_abandoned).
		# Jeśli coord JEST w _loaded ale o złym LOD, to ścieżka rebuild (_update_chunks), nie tu.
		if _loaded.has(coord) or _pending.has(coord) or _abandoned.has(coord) or _rebuild.has(coord):
			continue
		# LOD liczony TERAZ, z AKTUALNEGO środka (review #MAJOR — nie z chwili wrzucenia do kolejki).
		_submit_chunk(coord, _lod_for(coord, center))
		submitted += 1

	# 2) POLL: odbierz ukończone zadania (nieblokująco) i sfinalizuj na GŁÓWNYM watku.
	_poll_pending(center)

	_check_kill_plane(center)


## Wybór docelowego LOD-kroku dla coordu wg dystansu od środka. NEAR (krok 1) w promieniu
## near_dist (z półchunkowym zapasem, jak _coord_in_range), FAR (krok 2) dalej. Determinizm:
## czysta funkcja dystansu => ten sam coord ma w danej chwili dokładnie jeden docelowy LOD.
func _lod_for(coord: Vector2i, center: Vector2i) -> int:
	var dx := coord.x - center.x
	var dz := coord.y - center.y
	var d2 := float(dx * dx + dz * dz)
	if d2 <= (near_dist + 0.5) * (near_dist + 0.5):
		return LOD_STEP_NEAR
	return LOD_STEP_FAR


## Zleca build_data() chunku do WorkerThreadPool z wybranym LOD (krok próbkowania). Węzeł
## powstaje na głównym watku, ale NIE jest dodawany do drzewa — żyje w _pending do finalize().
## _lod_step ustawiamy PRZED add_task (niemutowane w trakcie taska => thread-safe wg kontraktu 2A).
func _submit_chunk(coord: Vector2i, lod: int) -> void:
	var chunk := VoxelChunk.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk._lod_step = lod
	# Pozycja w METRACH = coord * (CHUNK_SIZE * VOXEL_SIZE) = coord * 16 m. Ustawiana na węźle
	# POZA drzewem (bezpieczne, brak sygnałów drzewa) — finalize() doda go już z tą pozycją.
	var span: float = float(CHUNK_SIZE) * VOXEL_SIZE   # 16 m
	chunk.position = Vector3(coord.x * span, 0.0, coord.y * span)
	# OFF-THREAD: build_data(coord, self, lod). high_priority=false (chunki tła nie blokują gracza
	# natychmiast — prime() obsługuje teren pod stopami synchronicznie). self żyje przez całą scenę.
	var task_id := WorkerThreadPool.add_task(
		chunk.build_data.bind(coord, self, lod),
		false,
		"voxel_build_%d_%d_l%d" % [coord.x, coord.y, lod]
	)
	_pending[coord] = { "chunk": chunk, "task": task_id, "lod": lod }


## REBUILD (2B): buduje NOWĄ wersję chunku o 'new_lod' W TLE, podczas gdy stara (innego lod)
## wciąż wisi w _loaded i jest widoczna. Stary węzeł znika dopiero po finalize nowego
## (_poll_rebuild) => zero migotania/dziur na zmianie LOD. Nie tworzy 2. instancji w _loaded.
func _request_rebuild(coord: Vector2i, new_lod: int) -> void:
	if _rebuild.has(coord):
		return                                    # już się przebudowuje
	var chunk := VoxelChunk.new()
	chunk.name = "Chunk_%d_%d_rebuild" % [coord.x, coord.y]
	chunk._lod_step = new_lod
	var span: float = float(CHUNK_SIZE) * VOXEL_SIZE
	chunk.position = Vector3(coord.x * span, 0.0, coord.y * span)
	var task_id := WorkerThreadPool.add_task(
		chunk.build_data.bind(coord, self, new_lod),
		false,
		"voxel_rebuild_%d_%d_l%d" % [coord.x, coord.y, new_lod]
	)
	_rebuild[coord] = { "chunk": chunk, "task": task_id, "lod": new_lod }


## Odbiera ukończone zadania: is_task_completed() jest TANI i NIEBLOKUJĄCY (właściwy poll).
## wait_for_task_completion() wołamy TYLKO na już ukończonym tasku — zwraca natychmiast i
## zwalnia wewnętrzny uchwyt (inaczej przeciek). NIGDY nie blokujemy tu głównego watku.
func _poll_pending(center: Vector2i) -> void:
	# Najpierw sprzątnij porzucone (chunki spoza zasięgu, których task w końcu dobiegł końca).
	_reap_abandoned()
	# Obsłuż gotowe rebuildy LOD (swap stary->nowy bez migotania) PRZED nowymi finalizacjami:
	# rebuildy do NEAR niosą kolizję pod nadchodzącego gracza => najwyższy priorytet.
	_poll_rebuild(center)

	# Zbierz ukończone (nie modyfikujemy słownika w trakcie iteracji).
	var done: Array[Vector2i] = []
	for coord in _pending:
		if WorkerThreadPool.is_task_completed(_pending[coord]["task"]):
			done.append(coord)

	# Finalizuj max MAX_FINALIZE_PER_FRAME/klatkę (reszta poczeka — i tak jest gotowa w polach).
	var finalized := 0
	for coord in done:
		if finalized >= MAX_FINALIZE_PER_FRAME:
			break
		# Mógł zostać przejęty przez prime() między zebraniem 'done' a tą iteracją
		# (prime eraseuje z _pending) — pomiń, jeśli już nie ma go w _pending.
		if not _pending.has(coord):
			continue
		var entry: Dictionary = _pending[coord]
		_pending.erase(coord)
		# Już ukończony => zwraca od razu; służy do ZWOLNIENIA uchwytu taska (nie blokuje).
		WorkerThreadPool.wait_for_task_completion(entry["task"])
		var chunk: VoxelChunk = entry["chunk"]
		# Twardy bezpiecznik niezmiennika „jeden chunk na coord” (review #minor): gdyby coord
		# trafił już do _loaded inną ścieżką (np. prime), zwolnij ten węzeł zamiast nadpisywać.
		if _loaded.has(coord):
			if is_instance_valid(chunk):
				chunk.free()
			continue
		# Gracz mógł się w międzyczasie odsunąć — chunk zbędny. Nigdy nie był w drzewie => free().
		if not _coord_in_range(coord, center):
			if is_instance_valid(chunk):
				chunk.free()
			continue
		add_child(chunk)        # GŁÓWNY: wstaw węzeł do drzewa (z gotową pozycją/nazwą)
		chunk.finalize(self)    # GŁÓWNY: zbuduj MeshInstance3D/CollisionShape3D z gotowych zasobów
		_loaded[coord] = chunk
		finalized += 1


## Sprząta chunki porzucone (spoza zasięgu), ale TYLKO gdy ich task już ukończony.
## Nigdy nie były w drzewie -> free() (nie queue_free). Para wait_for_task_completion zwalnia uchwyt.
func _reap_abandoned() -> void:
	var reaped: Array[Vector2i] = []
	for coord in _abandoned:
		if WorkerThreadPool.is_task_completed(_abandoned[coord]["task"]):
			reaped.append(coord)
	for coord in reaped:
		var entry: Dictionary = _abandoned[coord]
		_abandoned.erase(coord)
		WorkerThreadPool.wait_for_task_completion(entry["task"])  # już ukończony => natychmiast
		var chunk: VoxelChunk = entry["chunk"]
		if is_instance_valid(chunk):
			chunk.free()


## Obsługa gotowych REBUILDÓW LOD (2B). Gdy task nowej wersji ukończony: dodaj nowy węzeł do
## drzewa i sfinalizuj, a DOPIERO POTEM zwolnij starą wersję z _loaded => stary znika gdy nowy
## już renderuje (anty-migotanie/anty-dziura). Throttling: max MAX_FINALIZE_PER_FRAME (finalize
## NEAR liczy create_trimesh_shape na głównym watku — to samo gardło co zwykłe finalizacje).
func _poll_rebuild(center: Vector2i) -> void:
	var done: Array[Vector2i] = []
	for coord in _rebuild:
		if WorkerThreadPool.is_task_completed(_rebuild[coord]["task"]):
			done.append(coord)

	var finalized := 0
	for coord in done:
		if finalized >= MAX_FINALIZE_PER_FRAME:
			break
		var entry: Dictionary = _rebuild[coord]
		_rebuild.erase(coord)
		WorkerThreadPool.wait_for_task_completion(entry["task"])  # ukończony => natychmiast, zwalnia uchwyt
		var new_chunk: VoxelChunk = entry["chunk"]
		# Coord mógł wypaść z zasięgu w międzyczasie — nowy węzeł zbędny, nigdy nie był w drzewie.
		# Stary (jeśli wciąż w _loaded) usunie normalnie _update_chunks; tu tylko zwalniamy nowy.
		if not _coord_in_range(coord, center):
			if is_instance_valid(new_chunk):
				new_chunk.free()
			continue
		# Stary mógł zniknąć inną ścieżką (np. wypadł z zasięgu i queue_free w _update_chunks).
		# Wtedy traktujemy nowy jak świeże wczytanie (o ile coord nadal potrzebny).
		var old_chunk: VoxelChunk = _loaded.get(coord, null)
		add_child(new_chunk)        # GŁÓWNY: nowy do drzewa (z gotową pozycją/nazwą)
		new_chunk.finalize(self)    # GŁÓWNY: zbuduj MeshInstance3D/CollisionShape3D (kolizja tylko NEAR)
		_loaded[coord] = new_chunk
		# DOPIERO TERAZ usuń starą wersję — nowy już renderuje, brak błysku/dziury.
		if old_chunk != null and is_instance_valid(old_chunk) and old_chunk != new_chunk:
			old_chunk.queue_free()
		finalized += 1


## Kwadrat dystansu chunkowego coord->center (do sortowania kolejki/priorytetów).
func _dist2(coord: Vector2i, center: Vector2i) -> int:
	var dx := coord.x - center.x
	var dz := coord.y - center.y
	return dx * dx + dz * dz


## Czy coord jest już w kolejce budowania (_build_queue trzyma teraz same coordy).
func _queued(coord: Vector2i) -> bool:
	return _build_queue.has(coord)


## Czy coord mieści się w aktualnym promieniu (kołowe odsianie, jak _update_chunks).
func _coord_in_range(coord: Vector2i, center: Vector2i) -> bool:
	var rd := far_dist
	var dx := coord.x - center.x
	var dz := coord.y - center.y
	return float(dx * dx + dz * dz) <= (rd + 0.5) * (rd + 0.5)


## Sprawdza, czy coord o aktualnym lod 'have' powinien ZOSTAĆ na swoim lodzie mimo że
## _lod_for sugeruje inny — pas histerezy zapobiega thrashingowi (rebuild tam i z powrotem)
## gdy gracz drepcze/krąży wokół granicy NEAR|FAR.
##
## DWUSTRONNA MARTWA STREFA (review #minor THRASHING): _lod_for przełącza próg na (near_dist+0.5)^2.
##  - Już-NEAR schodzi do FAR DOPIERO za GÓRNYM progiem d2 > (near_dist+1)^2 ("trzymaj NEAR dłużej",
##    kolizja z zapasem przed graczem).
##  - Już-FAR awansuje do NEAR DOPIERO po wejściu GŁĘBIEJ niż DOLNY próg d2 <= (near_dist-0.5)^2
##    (a NIE od razu na (near_dist+0.5)^2 z _lod_for). Między progami (near_dist-0.5 .. near_dist+1)
##    jest martwa strefa: chunk trzyma swój obecny LOD, więc oscylacja gracza dokładnie na granicy
##    NIE generuje par rebuildów NEAR(~356 ms)/FAR w kółko (te nasycały MAX_IN_FLIGHT i głodziły dal).
## Kolizja bezpieczna: nadchodzący gracz przekracza dolny próg, dostaje NEAR raz i już zostaje.
func _within_hysteresis(coord: Vector2i, center: Vector2i, have: int) -> bool:
	var dx := coord.x - center.x
	var dz := coord.y - center.y
	var d2 := float(dx * dx + dz * dz)
	if have == LOD_STEP_NEAR:
		# Już-NEAR: zostań NEAR póki w pasie (near_dist+1). Dopiero dalej pozwól zejść na FAR.
		return d2 <= (near_dist + 1.0) * (near_dist + 1.0)
	# Już-FAR: NIE awansuj do NEAR, dopóki nie wejdzie głębiej niż dolny próg (martwa strefa).
	return d2 > (near_dist - 0.5) * (near_dist - 0.5)


## Aktualizuje zbiór potrzebnych chunków: dodaje brakujące do kolejki (z docelowym LOD),
## zleca rebuild gdy załadowany LOD ≠ potrzebny (z histerezą), usuwa nadmiarowe.
func _update_chunks(center: Vector2i) -> void:
	var rd := far_dist
	var rd_sq := (rd + 0.5) * (rd + 0.5)   # kołowe odsianie rogów (mniej chunków)

	# Zbiór potrzebnych coordów (do szybkiego sprawdzania przy usuwaniu).
	var needed: Dictionary = {}

	# Kandydaci do zbudowania: same coordy (lod liczony dopiero przy submitcie).
	var to_queue: Array[Vector2i] = []

	for dx in range(-rd, rd + 1):
		for dz in range(-rd, rd + 1):
			# Kołowe odsianie: pomiń rogi poza promieniem.
			if float(dx * dx + dz * dz) > rd_sq:
				continue
			var coord := Vector2i(center.x + dx, center.y + dz)
			needed[coord] = true
			var want_lod := _lod_for(coord, center)

			# Już załadowany: sprawdź czy LOD się zgadza; jeśli nie i nie ma rebuildu w locie,
			# zleć rebuild (z histerezą NEAR->FAR). Stary węzeł zostaje widoczny do gotowości nowego.
			if _loaded.has(coord):
				var have: int = (_loaded[coord] as VoxelChunk)._lod_step
				if have != want_lod and not _rebuild.has(coord):
					if not _within_hysteresis(coord, center, have):
						_request_rebuild(coord, want_lod)
				continue

			# W LOCIE (_pending) o złym LOD (review #MAJOR — DZIURA KOLIZJI): coord, który wciąż
			# buduje się jako FAR (bezkolizyjny), a gracz w międzyczasie wszedł w near_dist, MUSI
			# dostać korektę NA AWANS (FAR->NEAR) JESZCZE ZANIM stara wersja trafi do _loaded —
			# inaczej sfinalizuje się jako FAR pod nadchodzącym graczem i dopiero NASTĘPNE
			# _update_chunks zleci rebuild (okno ~356 ms bez kolizji przy 8 m/s). Zlecamy rebuild
			# do NEAR mimo braku wpisu w _loaded; _poll_rebuild ma ścieżkę old_chunk==null (świeże
			# wczytanie), więc swap jest bezpieczny, a stary FAR-pending dokończy się i (gdy coord
			# już w _loaded jako NEAR) zostanie odrzucony guardem _loaded.has w _poll_pending.
			# Tylko AWANS (want NEAR): degradacja NEAR->FAR w locie jest nieszkodliwa (poczeka).
			if _pending.has(coord) and want_lod == LOD_STEP_NEAR \
					and int(_pending[coord]["lod"]) != LOD_STEP_NEAR and not _rebuild.has(coord):
				_request_rebuild(coord, LOD_STEP_NEAR)
				continue

			# Nie kolejkuj coordów już W LOCIE (_pending), PORZUCONYCH z żywym taskiem (_abandoned),
			# ani będących w trakcie rebuildu (_rebuild). Pominięcie _pending zapobiega podwójnemu
			# budowaniu. Pominięcie _abandoned (BLOCKER review): bez tego coord, który właśnie
			# wypadł z zasięgu z taskiem w locie, byłby NATYCHMIAST kolejkowany i submitowany jako
			# DRUGA instancja — zmarnowany build + ryzyko nadpisania wpisu _abandoned (wyciek).
			# Coord wróci do streamingu dopiero po zreapowaniu starego taska w _reap_abandoned().
			if not _pending.has(coord) and not _abandoned.has(coord) \
					and not _rebuild.has(coord) and not _queued(coord):
				to_queue.append(coord)

	# Dorzuć nowych kandydatów (cała kolejka i tak zostanie posortowana niżej).
	for coord in to_queue:
		_build_queue.append(coord)

	# Usuń z kolejki coordy spoza zasięgu (np. po szybkim ruchu gracza).
	var filtered: Array[Vector2i] = []
	for coord in _build_queue:
		if needed.has(coord):
			filtered.append(coord)
	_build_queue = filtered

	# Posortuj CAŁĄ kolejkę względem AKTUALNEGO środka — najbliżej budujemy najpierw.
	_build_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _dist2(a, center) < _dist2(b, center)
	)

	# Usuń (queue_free) chunki poza zasięgiem — te SĄ w drzewie i sfinalizowane, więc bezpiecznie.
	var to_remove: Array[Vector2i] = []
	for coord in _loaded.keys():
		if not needed.has(coord):
			to_remove.append(coord)
	for coord in to_remove:
		var chunk: VoxelChunk = _loaded[coord]
		if is_instance_valid(chunk):
			chunk.queue_free()
		_loaded.erase(coord)

	# Chunki W LOCIE, które wypadły z zasięgu: NIE wolno ich zwolnić teraz (task pisze do ich
	# pól na wątku roboczym -> use-after-free). Przenosimy do _abandoned i zwalniamy w _reap_abandoned()
	# dopiero po is_task_completed(). Zaczęte zadanie i tak doliczy się do końca (krótkie).
	var pending_drop: Array[Vector2i] = []
	for coord in _pending.keys():
		if not needed.has(coord):
			pending_drop.append(coord)
	for coord in pending_drop:
		# TWARDY BEZPIECZNIK (BLOCKER review): nie nadpisuj istniejącego wpisu _abandoned —
		# inaczej stary {chunk,task} ginie bez wait_for_task_completion (wyciek uchwytu puli)
		# i bez free() (wyciek węzła). Dzięki guardowi _abandoned w warunku kolejkowania powyżej
		# ta kolizja klucza praktycznie nie powinna już zachodzić, ale zostawiamy bezpiecznik:
		# stary wpis domykamy blokująco (task i tak był krótki) ZANIM wstawimy nowy.
		if _abandoned.has(coord):
			var old_entry: Dictionary = _abandoned[coord]
			WorkerThreadPool.wait_for_task_completion(old_entry["task"])
			var old_chunk: VoxelChunk = old_entry["chunk"]
			if is_instance_valid(old_chunk):
				old_chunk.free()
		_abandoned[coord] = _pending[coord]   # { chunk, task, lod }
		_pending.erase(coord)

	# REBUILDY (2B), które wypadły z zasięgu: nowy węzeł NIGDY nie był w drzewie, ale jego task
	# wciąż pisze do jego pól -> use-after-free przy free() teraz. Przenosimy do _abandoned
	# (reap po is_task_completed), identycznie jak _pending. Stara wersja (w _loaded) zostanie
	# zdjęta przez blok to_remove powyżej (już nieobecna w 'needed'). Bezpiecznik na kolizję klucza.
	var rebuild_drop: Array[Vector2i] = []
	for coord in _rebuild.keys():
		if not needed.has(coord):
			rebuild_drop.append(coord)
	for coord in rebuild_drop:
		if _abandoned.has(coord):
			var old_entry: Dictionary = _abandoned[coord]
			WorkerThreadPool.wait_for_task_completion(old_entry["task"])
			var old_chunk: VoxelChunk = old_entry["chunk"]
			if is_instance_valid(old_chunk):
				old_chunk.free()
		_abandoned[coord] = _rebuild[coord]   # { chunk, task, lod }
		_rebuild.erase(coord)


## Natychmiastowa (synchroniczna) budowa kwadratu (2*radius+1) wokół środka.
## Wołane RAZ przed/po spawnie gracza oraz w kill-plane, żeby gracz nie spadł przez
## niezaładowany teren. NIE używa WorkerThreadPool — teren pod stopami musi powstać OD RĘKI.
##
## WAŻNE: celowo NIE ustawiamy tu _last_center (sentinel wymusza pełne przeliczenie
## streamingu w pierwszym _process — inaczej świat zatrzymałby się na chunkach z prime).
func prime(center: Vector2i, radius: int = 1) -> void:
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var coord := Vector2i(center.x + dx, center.y + dz)
			if _loaded.has(coord):
				# Już w drzewie. Jeśli to chunk FAR (bezkolizyjny) — gracz mógłby przezeń spaść,
				# a prime ma DAĆ GRUNT. Zleć rebuild na NEAR (z kolizją); stary FAR trzyma sylwetkę
				# do gotowości NEAR (anty-dziura). Rzadkie: prime woła się przy spawnie/kill-plane,
				# gdzie coordy i tak są w near_dist => zwykle już NEAR.
				if (_loaded[coord] as VoxelChunk)._lod_step != LOD_STEP_NEAR:
					_request_rebuild(coord, LOD_STEP_NEAR)
				continue
			# Chunk W LOCIE / PORZUCONY / w REBUILDZIE: przejmij task TYLKO jeśli buduje NEAR
			# (pełny grunt + kolizja). Jeśli buduje FAR (bezkolizyjny), NIE używaj go jako gruntu —
			# zbuduj NEAR synchronicznie, a starą wersję zostaw do normalnego sprzątania/reapu.
			# To gwarantuje twardą kolizję pod spawnem/po kill-plane (gracz nie wpadnie w teren).
			if _pending.has(coord):
				if int(_pending[coord]["lod"]) == LOD_STEP_NEAR:
					# Dokończ NATYCHMIAST (blokująco) — prime musi dać gotowy teren w tej klatce.
					# Wyjmujemy z _pending, by _poll_pending nie sfinalizował go drugi raz.
					var entry: Dictionary = _pending[coord]
					_pending.erase(coord)
					WorkerThreadPool.wait_for_task_completion(entry["task"])
					var ch: VoxelChunk = entry["chunk"]
					add_child(ch)
					ch.finalize(self)
					_loaded[coord] = ch
					continue
				# Pending FAR: zostaw go (wypadnie do _abandoned/reap naturalnie), zbuduj NEAR sync.
				_build_chunk_sync(coord)
				continue
			if _abandoned.has(coord):
				if int(_abandoned[coord]["lod"]) == LOD_STEP_NEAR:
					# Przejmujemy NEAR-owy task zamiast budować drugi raz od zera (review #MAJOR):
					# bez tego prime() płaciłby pełny synchroniczny koszt (~98k voxeli na głównym
					# watku!) dla chunku, którego budowa i tak trwała w tle. Wyjmujemy z _abandoned
					# (by _reap_abandoned go nie zwolnił), dokańczamy blokująco i finalizujemy.
					var aentry: Dictionary = _abandoned[coord]
					_abandoned.erase(coord)
					WorkerThreadPool.wait_for_task_completion(aentry["task"])
					var ach: VoxelChunk = aentry["chunk"]
					add_child(ach)
					ach.finalize(self)
					_loaded[coord] = ach
					continue
				# Abandoned FAR: zostaw do reapu, zbuduj NEAR sync.
				_build_chunk_sync(coord)
				continue
			if _rebuild.has(coord):
				# Rebuild w locie dla coordu BEZ wpisu w _loaded (stara wersja zniknęła). Jeśli to
				# rebuild->NEAR, dokończ go blokująco jak _pending; inaczej zbuduj NEAR sync i zostaw
				# rebuild do własnego pollingu (_poll_rebuild odrzuci go guardem _loaded.has).
				if int(_rebuild[coord]["lod"]) == LOD_STEP_NEAR:
					var rentry: Dictionary = _rebuild[coord]
					_rebuild.erase(coord)
					WorkerThreadPool.wait_for_task_completion(rentry["task"])
					var rch: VoxelChunk = rentry["chunk"]
					add_child(rch)
					rch.finalize(self)
					_loaded[coord] = rch
					continue
				_build_chunk_sync(coord)
				continue
			_build_chunk_sync(coord)


## SYNCHRONICZNA budowa pojedynczego chunku na GŁÓWNYM watku (dla prime/kill-plane).
## ZAWSZE NEAR (pełny detal + kolizja): prime gwarantuje twardy grunt pod spawnem/po kill-plane.
func _build_chunk_sync(coord: Vector2i) -> void:
	var chunk := VoxelChunk.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk._lod_step = LOD_STEP_NEAR   # jawnie NEAR (generate i tak buduje pełny + kolizję)
	# NAPRAWA SKALI: pozycja chunku w METRACH = coord * (CHUNK_SIZE * VOXEL_SIZE) = coord * 16 m.
	# Bez tego chunki stanęłyby w odstępie 32 m z 16-metrowymi dziurami w terenie.
	var span: float = float(CHUNK_SIZE) * VOXEL_SIZE   # 16 m
	chunk.position = Vector3(coord.x * span, 0.0, coord.y * span)
	add_child(chunk)
	chunk.generate(coord, self)   # build_data + finalize synchronicznie (self już w drzewie)
	_loaded[coord] = chunk


# --- Bezpieczeństwo: gdyby gracz wypadł pod świat ---
func _check_kill_plane(center: Vector2i) -> void:
	if _player == null:
		return
	if _player.global_position.y < KILL_PLANE_Y:
		# Upewnij się, że teren pod graczem istnieje, zanim go postawimy.
		prime(center, 1)
		var px := _player.global_position.x
		var pz := _player.global_position.z
		_player.global_position = Vector3(px, height_at(px, pz) + 2.0, pz)
		# Wyzeruj pęd (CharacterBody3D ma „velocity”). Ustawiamy dynamicznie przez set().
		if "velocity" in _player:
			_player.set("velocity", Vector3.ZERO)
		# Profilaktyka: wymuś przeliczenie streamingu w następnej klatce.
		_last_center = Vector2i(2147483647, 2147483647)


# --- Sprzątanie przy zamknięciu / przeładowaniu świata ---
## Przy usuwaniu VoxelWorld są jeszcze taski w locie trzymające referencje do węzłów
## chunków (przez Callable build_data.bind(coord, self)). MUSIMY je domknąć (blokująco —
## to teardown, klatka i tak się nie liczy) ZANIM cokolwiek zwolnimy, inaczej wątek
## roboczy sięgnie do zwolnionej pamięci (use-after-free). Po wait_for_task_completion
## każdy uchwyt jest zwolniony, a węzły (nigdy nie w drzewie) zwalniamy przez free().
func _exit_tree() -> void:
	_drain_all_tasks()


## Domyka WSZYSTKIE taski w locie (_pending + _abandoned + _rebuild) blokująco i zwalnia ich
## węzły (nigdy nie były w drzewie => free()). Po tym wywołaniu żaden wątek roboczy nie pisze
## już do pól chunków ani nie czyta szumu world. Używane przy teardownie (_exit_tree) i — na
## przyszłość — PRZED jakąkolwiek mutacją FastNoiseLite (regeneracja świata / zmiana seeda),
## inaczej równoległe get_noise_* w trakcie rekonfiguracji szumu = data race (notatka integratora).
func _drain_all_tasks() -> void:
	for coord in _pending:
		var entry: Dictionary = _pending[coord]
		WorkerThreadPool.wait_for_task_completion(entry["task"])
		var chunk: VoxelChunk = entry["chunk"]
		if is_instance_valid(chunk):
			chunk.free()
	for coord in _abandoned:
		var aentry: Dictionary = _abandoned[coord]
		WorkerThreadPool.wait_for_task_completion(aentry["task"])
		var achunk: VoxelChunk = aentry["chunk"]
		if is_instance_valid(achunk):
			achunk.free()
	# REBUILDY (2B): też trzymają węzeł poza drzewem + task w locie => domknąć tak samo,
	# inaczej use-after-free przy teardownie (wątek pisze do zwolnionej pamięci nowego chunku).
	for coord in _rebuild:
		var rentry: Dictionary = _rebuild[coord]
		WorkerThreadPool.wait_for_task_completion(rentry["task"])
		var rchunk: VoxelChunk = rentry["chunk"]
		if is_instance_valid(rchunk):
			rchunk.free()
	_pending.clear()
	_abandoned.clear()
	_rebuild.clear()
