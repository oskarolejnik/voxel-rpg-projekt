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

@export var render_distance: int = 4     # promień w chunkach (4 × 16 m = 64 m; jest zapas FPS)
@export var chunks_per_frame: int = 2    # 2 chunki/klatkę — szybsze ładowanie (mamy zapas wydajności)

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

# Szum wysokości terenu (deterministyczny seed).
var _noise: FastNoiseLite

# Drugi, wolniejszy szum do drobnej wariacji koloru (tint per blok).
var _tint_noise: FastNoiseLite
var _biome_noise: FastNoiseLite   # regionalny biom koloru (Faza 2C)

# Słownik załadowanych chunków: Vector2i (chunk_coord) -> VoxelChunk.
var _loaded: Dictionary = {}

# Kolejka coordów do zbudowania (posortowana: najbliżej gracza najpierw).
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
	_biome_noise.frequency = 0.0025   # duże strefy biomów koloru (anty-powtarzalność)


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


# --- Pętla streamingu ---
func _process(_delta: float) -> void:
	if _player == null:
		return

	var center := world_to_chunk(_player.global_position)
	if center != _last_center:
		_update_chunks(center)
		_last_center = center

	# Buduj do chunks_per_frame chunków z kolejki.
	var built := 0
	while built < chunks_per_frame and not _build_queue.is_empty():
		var coord: Vector2i = _build_queue.pop_front()
		# Mogło się zdezaktualizować (np. odsunięcie), więc sprawdzamy ponownie.
		if not _loaded.has(coord):
			_build_chunk(coord)
		built += 1

	_check_kill_plane(center)


## Aktualizuje zbiór potrzebnych chunków: dodaje brakujące do kolejki, usuwa nadmiarowe.
func _update_chunks(center: Vector2i) -> void:
	var rd := render_distance
	var rd_sq := (rd + 0.5) * (rd + 0.5)   # kołowe odsianie rogów (mniej chunków)

	# Zbiór potrzebnych coordów (do szybkiego sprawdzania przy usuwaniu).
	var needed: Dictionary = {}

	# Kandydaci do zbudowania, z dystansem do środka (do sortowania).
	var to_queue: Array[Vector2i] = []

	for dx in range(-rd, rd + 1):
		for dz in range(-rd, rd + 1):
			# Kołowe odsianie: pomiń rogi poza promieniem.
			if float(dx * dx + dz * dz) > rd_sq:
				continue
			var coord := Vector2i(center.x + dx, center.y + dz)
			needed[coord] = true
			if not _loaded.has(coord) and not _build_queue.has(coord):
				to_queue.append(coord)

	# Sortuj kandydatów rosnąco po dystansie od środka — najbliżej budujemy najpierw.
	to_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a.x - center.x) * (a.x - center.x) + (a.y - center.y) * (a.y - center.y)
		var db := (b.x - center.x) * (b.x - center.x) + (b.y - center.y) * (b.y - center.y)
		return da < db
	)
	for coord in to_queue:
		_build_queue.append(coord)

	# Usuń z kolejki coordy spoza zasięgu (np. po szybkim ruchu gracza).
	var filtered: Array[Vector2i] = []
	for coord in _build_queue:
		if needed.has(coord):
			filtered.append(coord)
	_build_queue = filtered

	# Posortuj CAŁĄ kolejkę względem AKTUALNEGO środka — nie tylko nowych kandydatów.
	_build_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a.x - center.x) * (a.x - center.x) + (a.y - center.y) * (a.y - center.y)
		var db := (b.x - center.x) * (b.x - center.x) + (b.y - center.y) * (b.y - center.y)
		return da < db
	)

	# Usuń (queue_free) chunki poza zasięgiem.
	var to_remove: Array[Vector2i] = []
	for coord in _loaded.keys():
		if not needed.has(coord):
			to_remove.append(coord)
	for coord in to_remove:
		var chunk: VoxelChunk = _loaded[coord]
		if is_instance_valid(chunk):
			chunk.queue_free()
		_loaded.erase(coord)


## Buduje pojedynczy chunk i wstawia do drzewa.
func _build_chunk(coord: Vector2i) -> void:
	var chunk := VoxelChunk.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	# NAPRAWA SKALI: pozycja chunku w METRACH = coord * (CHUNK_SIZE * VOXEL_SIZE) = coord * 16 m.
	# Bez tego chunki stanęłyby w odstępie 32 m z 16-metrowymi dziurami w terenie.
	var span: float = float(CHUNK_SIZE) * VOXEL_SIZE   # 16 m
	chunk.position = Vector3(coord.x * span, 0.0, coord.y * span)
	add_child(chunk)
	chunk.generate(coord, self)
	_loaded[coord] = chunk


## Natychmiastowa (synchroniczna) budowa kwadratu (2*radius+1) wokół środka.
## Wołane RAZ przed/po spawnie gracza, żeby nie spadł przez niezaładowany teren.
##
## WAŻNE: celowo NIE ustawiamy tu _last_center (sentinel wymusza pełne przeliczenie
## streamingu w pierwszym _process — inaczej świat zatrzymałby się na chunkach z prime).
func prime(center: Vector2i, radius: int = 1) -> void:
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var coord := Vector2i(center.x + dx, center.y + dz)
			if not _loaded.has(coord):
				_build_chunk(coord)


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
