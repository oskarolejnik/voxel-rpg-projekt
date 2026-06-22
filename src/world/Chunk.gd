class_name VoxelChunk
extends StaticBody3D
## Chunk.gd — pojedynczy kawałek świata (CHUNK_SIZE×CHUNK_SIZE w XZ, WORLD_HEIGHT warstw Y).
##
## Styl Cube World: voxel = 0,5 m, siatka 2× gęstsza (32×96×32 = 98 304 voxele/chunk),
## ale REALNA skala w metrach identyczna jak poprzednio (chunk = 16 m, morze = 12 m).
##
## Odpowiada za:
##  1) wygenerowanie danych voxeli z heightmapy (FastNoiseLite z VoxelWorld),
##  2) rozmieszczenie roślinności/obiektów (drzewa, krzaki, kamienie) — wpisywane do _voxels,
##  3) NOWĄ warstwę drobnych propów (trawa/kwiaty/grzyby) jako OSOBNY MeshInstance3D
##     (bez kolizji, mini-kostki 0,25 m) — serce „sześcianów różnej wielkości”,
##  4) zbudowanie mesha (SurfaceTool + ArrayMesh) z face cullingiem i kolorem wierzchołków,
##  5) kolizję (ConcavePolygonShape3D z trimesh) — tylko z powierzchni STAŁEJ (bez wody).
##
## Struktura węzłów po wygenerowaniu:
##   VoxelChunk (StaticBody3D)  [pozycja = chunk_coord * CHUNK_SIZE * VOXEL_SIZE w METRACH]
##   ├── MeshInstance3D "SolidMesh"   (materiał stały — kolizja liczona z tego mesha)
##   ├── MeshInstance3D "WaterMesh"   (materiał wody, alpha — tylko jeśli jest woda)
##   ├── MeshInstance3D "PropsMesh"   (drobne propy, BEZ kolizji — tylko jeśli są propy)
##   └── CollisionShape3D             (tylko jeśli chunk ma jakąkolwiek stałą geometrię)

# --- Stałe świata (styl Cube World). MUSZĄ być identyczne z VoxelWorld.gd. ---
# Konwencja: 1 voxel = 0,5 metra. Stałe „w voxelach” podwojone względem wersji 1 m,
# co przy VOXEL_SIZE=0.5 daje TĘ SAMĄ realną skalę metrów.
const CHUNK_SIZE: int = 32          # 32 voxele = 16 m
const WORLD_HEIGHT: int = 96        # 96 voxeli = 48 m
const SEA_LEVEL: int = 24           # 24 voxeli = 12 m
const VOXEL_SIZE: float = 0.5       # 0,5 m/voxel

# --- Progi wysokości powierzchni (w VOXELACH — podwojone) ---
# JEDNO źródło prawdy dla _block_for i _place_features (i gradientu trawy w _solid_color).
# Po naprawie skali biomów w VoxelWorld.gd (BASE=24, AMP=64 => max surface_y=88)
# wszystkie progi są realnie OSIĄGALNE: BEACH(26) < ROCK(56) < SNOW(68) <= 88.
const BEACH_MAX_Y: int = SEA_LEVEL + 2   # +2 voxele = +1 m plaży (jak dawniej +1 przy 1 m)
const ROCK_MIN_Y: int = 56               # 56 voxeli × 0,5 = 28 m (bez zmian realnie)
const SNOW_MIN_Y: int = 68               # 68 voxeli × 0,5 = 34 m (bez zmian realnie)

# --- Roślinność i obiekty: parametry rozmieszczania ---
# Determinizm: world.feature_hash. Wszystkie wpisy do _voxels TYLKO w obręb chunku.
# TREE_CROWN_RADIUS podwojony (4 -> realnie ta sama korona). Margines od krawędzi liczymy
# od MAKSYMALNEGO promienia korony wariantu (5) + perturbacja brzegu (+~0,6 => +1) + trzon
# 2×2 (+1) = 7 voxeli (review #minor). Przy TREE_MARGIN=6 najdalszy liść trafiał DOKŁADNIE
# w ostatni rząd chunku, więc każdy wzrost perturbacji ścinałby korony na szwach chunków.
const TREE_CROWN_RADIUS: int = 4     # bazowy promień korony (warianty: 3..5)
const TREE_MARGIN: int = 7           # margines od krawędzi chunku (max r=5 + perturbacja +1 + trzon +1)
# Prawdopodobieństwa /4 względem wersji 1 m: kafli XZ jest teraz 4× więcej na ten sam metr,
# więc bez tego świat byłby przeładowany roślinnością (estetyka + wydajność).
const TREE_PROB: float = 0.006      # było 0.025
const BUSH_PROB: float = 0.015      # było 0.06
const ROCK_PROB: float = 0.003      # było 0.012

# --- Drobne propy (osobny mesh, bez kolizji) ---
# Prawdopodobieństwa per kafel trawy (osobny „rzut” na typ propa).
const PROP_GRASS_PROB: float = 0.18     # kępki trawy (zmniejszone dla wydajności przy 0,5 m)
const PROP_FLOWER_PROB: float = 0.06
const PROP_MUSHROOM_PROB: float = 0.02
# Twardy limit propów na chunk (wydajność). Podniesiony ze 160 (review #MAJOR):
# przy ~0,53 łącznego prawdopodobieństwa i ~1024 kaflach trawy spodziewamy się ~540
# propów; limit 160 ścinał je już po ~1/3 chunku (pętla idzie liniowo x->z), więc
# propy kumulowały się w jednym rogu chunku, a reszta była łysa. 600 mieści cały
# rozkład, a to nadal 1 draw call/chunk i ~<36k tri w skrajnym chunku — pomijalne.
const MAX_PROPS_PER_CHUNK: int = 200
const PROP_S: float = VOXEL_SIZE * 0.5  # bok mini-kostki = 0,25 m (pół voxela)

# --- Rozdzielna przestrzeń saltów dla feature_hash (review #minor: bez korelacji) ---
# Każda niezależna decyzja MUSI mieć własny, nienachodzący salt. Warianty per-voxel
# (perturbacje koron/krzaków/głazów) rezerwują CIĄGŁY zakres (base..base+span).
const SALT_TREE: int = 1                 # czy postawić drzewo na kaflu
const SALT_BUSH: int = 2                 # czy postawić krzak
const SALT_ROCK: int = 3                 # czy postawić kamień
const SALT_TREE_VARIANT: int = 4         # wariant rozmiaru drzewa
const SALT_BUSH_BIG: int = 5             # duży krzak?
const SALT_ROCK_VARIANT: int = 6         # wariant rozmiaru głazu
const SALT_TREE_HEIGHT: int = 7          # ±1 wysokość pnia
const SALT_TREE_CROWN: int = 30          # perturbacja brzegu korony: SALT_TREE_CROWN+dy
const SALT_TREE_AUTUMN: int = 9          # czy liście jesienne
const SALT_ROCK_EDGE: int = 40           # perturbacja brzegu głazu: SALT_ROCK_EDGE+dy
const SALT_BUSH_EDGE: int = 50           # perturbacja brzegu krzaka: SALT_BUSH_EDGE+dy
const SALT_ROCK_MOSSY: int = 17          # czy głaz z porostem
const SALT_PROP_TYPE: int = 12           # wybór typu propa (trawa/kwiat/grzyb)
const SALT_FLOWER_COLOR: int = 13        # kolor główki kwiatka
const SALT_PROP_OX: int = 14             # offset X propa w kaflu
const SALT_PROP_OZ: int = 15             # offset Z propa w kaflu
const SALT_FLOWER_STEM: int = 16         # tint łodygi kwiatka
const SALT_GRASS_TINT: int = 20          # tint źdźbeł: SALT_GRASS_TINT+i (rezerwuje 20..22)
const SALT_MUSHROOM_CAP: int = 18        # czerwony vs brązowy kapelusz

# 6 kierunków sąsiadów dla face cullingu (kolejność: +X,-X,+Y,-Y,+Z,-Z).
const NEIGHBORS: Array[Vector3i] = [
	Vector3i( 1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i( 0, 1, 0), Vector3i( 0,-1, 0),
	Vector3i( 0, 0, 1), Vector3i( 0, 0,-1),
]

# Cztery narożniki każdej z 6 ścian jednostkowego sześcianu, w kolejności CCW
# patrząc OD ZEWNĄTRZ (zgodnie z domyślnym cullingiem BACK Godota).
const FACE_VERTS: Array = [
	# +X (prawo)
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	# -X (lewo)
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],
	# +Y (góra)
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	# -Y (dół)
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	# +Z (przód)
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	# -Z (tył)
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]

# Stała normalna per ściana (twarde, płaskie krawędzie voxela — ostre i tanie).
const FACE_NORMALS: Array[Vector3] = [
	Vector3( 1, 0, 0), Vector3(-1, 0, 0),
	Vector3( 0, 1, 0), Vector3( 0,-1, 0),
	Vector3( 0, 0, 1), Vector3( 0, 0,-1),
]

# Dane voxeli: płaska tablica bajtów (typ bloku). Indeksowanie przez _idx().
var _voxels: PackedByteArray = PackedByteArray()

# Cache heightmapy kolumn (CHUNK_SIZE×CHUNK_SIZE), liczonej RAZ w _generate_data
# (review #minor: wcześniej surface_height liczone było 2× na kolumnę — w _generate_data
# i ponownie w _place_features — po 4 oktawy FBM na próbkę). Indeks: x + CHUNK_SIZE*z.
var _heightmap: PackedInt32Array = PackedInt32Array()

# Współrzędne chunku (w jednostkach chunków, nie metrów).
var _coord: Vector2i = Vector2i.ZERO

# Czy chunk ma jakąkolwiek stałą geometrię (decyduje o tym, czy dodajemy kolizję).
var _has_solid: bool = false

# Licznik wygenerowanych propów (twardy limit MAX_PROPS_PER_CHUNK).
var _prop_count: int = 0


func _idx(x: int, y: int, z: int) -> int:
	# Układ pamięci: x najszybciej, potem z, potem y.
	return x + CHUNK_SIZE * (z + CHUNK_SIZE * y)


func _set_voxel(x: int, y: int, z: int, t: int) -> void:
	_voxels[_idx(x, y, z)] = t


## Lokalny odczyt voxela. Poza zakresem Y/XZ zwracamy AIR.
func get_voxel(x: int, y: int, z: int) -> int:
	if y < 0 or y >= WORLD_HEIGHT:
		return Blocks.Type.AIR
	if x < 0 or x >= CHUNK_SIZE or z < 0 or z >= CHUNK_SIZE:
		return Blocks.Type.AIR
	return _voxels[_idx(x, y, z)]


## Pełny cykl: dane → mesh → kolizja. Wołane przez VoxelWorld po add_child().
func generate(chunk_coord: Vector2i, world: VoxelWorld) -> void:
	_coord = chunk_coord
	_generate_data(world)
	_build_mesh(world)


# --- 1) Generacja danych voxeli z heightmapy ---
func _generate_data(world: VoxelWorld) -> void:
	# Inicjalizujemy całą tablicę zerami (AIR). resize zeruje nowe elementy.
	_voxels.resize(CHUNK_SIZE * WORLD_HEIGHT * CHUNK_SIZE)
	_voxels.fill(Blocks.Type.AIR)

	# Cache heightmapy: liczymy surface_height RAZ na kolumnę i zapisujemy do _heightmap.
	_heightmap.resize(CHUNK_SIZE * CHUNK_SIZE)

	for x in CHUNK_SIZE:
		for z in CHUNK_SIZE:
			var wx := _coord.x * CHUNK_SIZE + x
			var wz := _coord.y * CHUNK_SIZE + z
			var sy := world.surface_height(wx, wz)
			_heightmap[x + CHUNK_SIZE * z] = sy

			# Kolumna stałych bloków od 0 do sy włącznie.
			for y in range(0, sy + 1):
				_set_voxel(x, y, z, _block_for(y, sy))

			# Woda: jeśli powierzchnia jest poniżej poziomu morza, zalewamy puste warstwy.
			if sy < SEA_LEVEL:
				for y in range(sy + 1, SEA_LEVEL + 1):
					_set_voxel(x, y, z, Blocks.Type.WATER)

	# Roślinność i obiekty — PO terenie i wodzie.
	_place_features(world)


## Odczyt zcache'owanej wysokości kolumny (tylko dla x,z W OBRĘBIE chunku).
func _surface_at(x: int, z: int) -> int:
	return _heightmap[x + CHUNK_SIZE * z]


## Przydział typu bloku w zależności od wysokości warstwy względem powierzchni.
func _block_for(world_y: int, surface_y: int) -> int:
	if world_y > surface_y:
		return Blocks.Type.AIR
	if world_y == surface_y:
		# Powierzchnia: plaża / śnieg / skała / trawa (progi z nazwanych stałych).
		if surface_y <= BEACH_MAX_Y:
			return Blocks.Type.SAND
		if surface_y >= SNOW_MIN_Y:
			return Blocks.Type.SNOW
		if surface_y >= ROCK_MIN_Y:
			return Blocks.Type.ROCK
		return Blocks.Type.GRASS
	# Poniżej powierzchni: warstwa gleby, niżej skała. Grubość gleby podwojona (6),
	# by realnie pozostać przy ~3 m ziemi jak przy voxelu 1 m.
	if world_y >= surface_y - 6:
		return Blocks.Type.DIRT
	return Blocks.Type.ROCK


# --- Roślinność, obiekty i propy: wpis do _voxels TYLKO w obrębie tego chunku ---
func _place_features(world: VoxelWorld) -> void:
	# Jeden SurfaceTool na CAŁY chunk zbiera wszystkie drobne propy do jednego mesha
	# (1 draw call/chunk, bez kolizji). Budujemy go równolegle z rozmieszczaniem.
	var st_props := SurfaceTool.new()
	st_props.begin(Mesh.PRIMITIVE_TRIANGLES)
	_prop_count = 0

	# Propy stawiamy z marginesem 1 od krawędzi chunku (review #minor): największy
	# prop (kapelusz grzyba 0,5 m + offset) wystaje wtedy najwyżej na styk z sąsiadem,
	# a nie poza obrys chunku. To eliminuje nakładanie się propów dwóch chunków na szwie.
	for x in CHUNK_SIZE:
		for z in CHUNK_SIZE:
			var wx := _coord.x * CHUNK_SIZE + x
			var wz := _coord.y * CHUNK_SIZE + z
			var sy := _surface_at(x, z)             # z cache (review #minor: bez 2× szumu)
			var surface_t := get_voxel(x, sy, z)   # typ bloku powierzchni (GRASS/ROCK/...)

			var on_grass := surface_t == Blocks.Type.GRASS

			# --- DRZEWO: tylko na trawie, korona+trzon w całości w chunku (margines TREE_MARGIN) ---
			if on_grass \
			and x >= TREE_MARGIN and x <= CHUNK_SIZE - 1 - TREE_MARGIN \
			and z >= TREE_MARGIN and z <= CHUNK_SIZE - 1 - TREE_MARGIN:
				if world.feature_hash(wx, wz, SALT_TREE) < TREE_PROB:
					_place_tree(world, x, sy, z, wx, wz)
					continue   # nie stawiaj krzaka/kamienia/propa na tym samym kaflu

			# --- KRZAK: na trawie, gęściej; kula liści r=1..2 mieści się przy marginesie 2 ---
			if on_grass \
			and x >= 2 and x <= CHUNK_SIZE - 1 - 2 \
			and z >= 2 and z <= CHUNK_SIZE - 1 - 2:
				if world.feature_hash(wx, wz, SALT_BUSH) < BUSH_PROB:
					_place_bush(world, x, sy, z, wx, wz)
					continue

			# --- KAMIEŃ: na trawie LUB skale (nie piasek/woda), poniżej sufitu świata ---
			if (on_grass or surface_t == Blocks.Type.ROCK) \
			and sy > BEACH_MAX_Y and sy < WORLD_HEIGHT - 3 \
			and x >= 3 and x <= CHUNK_SIZE - 1 - 3 \
			and z >= 3 and z <= CHUNK_SIZE - 1 - 3:
				if world.feature_hash(wx, wz, SALT_ROCK) < ROCK_PROB:
					_place_rock(world, x, sy, z, wx, wz)
					continue

			# --- DROBNE PROPY: tylko na czystej trawie, z marginesem 1 od krawędzi ---
			# Budujemy je do osobnego mesha (st_props), NIE do _voxels.
			# WAŻNE (review #MAJOR): limit MAX_PROPS_PER_CHUNK jest na tyle wysoki, że
			# mieści cały oczekiwany rozkład — propy NIE kumulują się w jednym rogu chunku.
			# Sprawdzenie limitu zostaje jako twardy bezpiecznik wydajności (skrajne chunki).
			if on_grass and _prop_count < MAX_PROPS_PER_CHUNK \
			and x >= 1 and x <= CHUNK_SIZE - 2 \
			and z >= 1 and z <= CHUNK_SIZE - 2:
				_place_props(st_props, world, x, sy, z, wx, wz)

	# Po pętli: jeśli powstały jakiekolwiek propy, zbuduj jeden lekki MeshInstance3D.
	if _prop_count > 0:
		var props_mesh := st_props.commit()
		if props_mesh != null and props_mesh.get_surface_count() > 0:
			var props_mi := MeshInstance3D.new()
			props_mi.name = "PropsMesh"
			props_mi.mesh = props_mesh
			props_mi.material_override = world.props_material
			add_child(props_mi)


# Zapis tylko gdy w obrębie chunku (XZ) i w pionie (Y) — twardy bezpiecznik.
func _try_set_feature(x: int, y: int, z: int, t: int) -> void:
	if y < 0 or y >= WORLD_HEIGHT:
		return
	if x < 0 or x >= CHUNK_SIZE or z < 0 or z >= CHUNK_SIZE:
		return
	_set_voxel(x, y, z, t)


## Drzewo — pień WOOD (trzon 1×1 lub 2×2) + korona LEAVES jako kula z postrzępionym
## brzegiem (perturbacja per voxel) i lekkim spłaszczeniem (szersza niż wyższa).
## Warianty rozmiaru (SALT_TREE_VARIANT) + ±1 wysokość (SALT_TREE_HEIGHT) + ~10% jesiennych (SALT_TREE_AUTUMN).
func _place_tree(world: VoxelWorld, x: int, sy: int, z: int, wx: int, wz: int) -> void:
	# Wariant: 0=sapling, 1=default, 2=duże (SALT_TREE_VARIANT).
	var variant := int(world.feature_hash(wx, wz, SALT_TREE_VARIANT) * 3.0)   # 0,1,2
	var trunk_h := 8
	var r := 3
	var fat := false   # trzon 2×2?
	match variant:
		0:
			trunk_h = 8;  r = 3; fat = false
		1:
			trunk_h = 10; r = 4; fat = true
		_:
			trunk_h = 12; r = 5; fat = true
	# ±1 voxel wysokości pnia (SALT_TREE_HEIGHT), żeby drzewa tego samego typu się różniły.
	trunk_h += int(world.feature_hash(wx, wz, SALT_TREE_HEIGHT) * 3.0) - 1   # -1,0,+1

	# ~10% drzew jesiennych (SALT_TREE_AUTUMN) — ciepły wariant liści.
	var leaf_type := Blocks.Type.LEAVES
	if world.feature_hash(wx, wz, SALT_TREE_AUTUMN) < 0.10:
		leaf_type = Blocks.Type.LEAVES_AUTUMN

	var base_y := sy + 1                      # pierwszy blok pnia nad ziemią
	var top_y := base_y + trunk_h - 1         # wierzchołek pnia

	# Pień. Trzon 2×2 dla wariantów średni/duży, inaczej 1×1.
	for ty in range(base_y, top_y + 1):
		_try_set_feature(x, ty, z, Blocks.Type.WOOD)
		if fat:
			_try_set_feature(x + 1, ty, z, Blocks.Type.WOOD)
			_try_set_feature(x, ty, z + 1, Blocks.Type.WOOD)
			_try_set_feature(x + 1, ty, z + 1, Blocks.Type.WOOD)

	# Korona: kula LEAVES o promieniu r wokół punktu nad wierzchołkiem pnia.
	var cy := top_y + 1                       # środek korony
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				# 1) Pion lekko spłaszczony (korona szersza niż wyższa) — mnożnik 1.3 na dy.
				var d2 := dx * dx + int(round(float(dy * dy) * 1.3)) + dz * dz
				# 2) Próg promienia perturbowany per voxel => poszarpany, naturalny brzeg.
				#    Zakres ~[-0.6, +0.6] voxela. Deterministyczne (SALT_TREE_CROWN+dy).
				var edge := (world.feature_hash(wx + dx, wz + dz, SALT_TREE_CROWN + dy) - 0.5) * 1.2
				var rr := float(r) + edge
				if float(d2) > rr * rr:
					continue
				# Nie zamazuj samego pnia liśćmi w jego trzonie.
				if dx == 0 and dz == 0 and (cy + dy) <= top_y:
					continue
				# Ochrona pni SĄSIEDNICH drzew: nie zamazuj istniejącego WOOD liściem.
				if get_voxel(x + dx, cy + dy, z + dz) == Blocks.Type.WOOD:
					continue
				_try_set_feature(x + dx, cy + dy, z + dz, leaf_type)


## Krzak — kulista kępka LEAVES (r=1 lub r=2) tuż nad ziemią, z perturbowanym brzegiem.
## Duży wariant (SALT_BUSH_BIG) dostaje krótką łodygę WOOD pod spodem.
func _place_bush(world: VoxelWorld, x: int, sy: int, z: int, wx: int, wz: int) -> void:
	var big := world.feature_hash(wx, wz, SALT_BUSH_BIG) < 0.4
	var r := 2 if big else 1
	var cy := sy + 1 + r            # środek kuli nad ziemią
	if big:
		_try_set_feature(x, sy + 1, z, Blocks.Type.WOOD)   # krótka łodyga
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var edge := (world.feature_hash(wx + dx, wz + dz, SALT_BUSH_EDGE + dy) - 0.5) * 1.0
				var rr := float(r) + edge
				if float(dx * dx + dy * dy + dz * dz) > rr * rr:
					continue
				if get_voxel(x + dx, cy + dy, z + dz) == Blocks.Type.WOOD:
					continue
				_try_set_feature(x + dx, cy + dy, z + dz, Blocks.Type.LEAVES)


## Kamień — nieregularny głaz jako spłaszczona elipsoida z voxeli + perturbacja brzegu.
## Warianty rozmiaru (SALT_ROCK_VARIANT); ~20% głazów z porostem (ROCK_MOSSY, SALT_ROCK_MOSSY).
func _place_rock(world: VoxelWorld, x: int, sy: int, z: int, wx: int, wz: int) -> void:
	# Wariant: 0=otoczak, 1=głaz, 2=skała (SALT_ROCK_VARIANT).
	var variant := int(world.feature_hash(wx, wz, SALT_ROCK_VARIANT) * 3.0)   # 0,1,2
	var rx := 1
	var ry := 1
	var rz := 1
	match variant:
		0:
			rx = 1; ry = 1; rz = 1
		1:
			rx = 2; ry = 1; rz = 2
		_:
			rx = 3; ry = 2; rz = 2

	# ~20% głazów z porostem.
	var rock_type := Blocks.Type.ROCK
	if world.feature_hash(wx, wz, SALT_ROCK_MOSSY) < 0.20:
		rock_type = Blocks.Type.ROCK_MOSSY

	# Elipsoida „wystająca z ziemi” (tylko górna połowa: dy >= 0).
	for dx in range(-rx, rx + 1):
		for dy in range(0, ry + 1):
			for dz in range(-rz, rz + 1):
				var nx := float(dx) / float(rx)
				var ny := float(dy) / float(ry)
				var nz := float(dz) / float(rz)
				var edge := (world.feature_hash(wx + dx, wz + dz, SALT_ROCK_EDGE + dy) - 0.5) * 0.5
				if nx * nx + ny * ny + nz * nz > 1.0 + edge:
					continue
				_try_set_feature(x + dx, sy + 1 + dy, z + dz, rock_type)


# --- DROBNE PROPY (mini-kostki, osobny mesh, bez kolizji) ---

## Wybiera i buduje jeden prop na kaflu trawy (deterministycznie). Inkrementuje _prop_count.
func _place_props(st: SurfaceTool, world: VoxelWorld, x: int, sy: int, z: int, wx: int, wz: int) -> void:
	var roll := world.feature_hash(wx, wz, SALT_PROP_TYPE)
	# Wierzch bloku trawy (lokalnie, w metrach) + losowy offset w obrębie kafla.
	# OFFSET ZACIŚNIĘTY (review #minor): poprzednio ox/oz ∈ [0, 0,5 m), przez co
	# najszersze propy (źdźbła trawy z offsetem +s, kapelusz grzyba 0,5 m) wychodziły
	# poza obrys kafla, a na skraju chunku nawet poza chunk. Ograniczamy offset do
	# PROP_OFFSET_MAX, tak by największy prop zmieścił się w kaflu 0,5 m.
	const PROP_OFFSET_MAX: float = VOXEL_SIZE * 0.25   # 0,125 m
	var top := float(sy + 1) * VOXEL_SIZE
	var ox := world.feature_hash(wx, wz, SALT_PROP_OX) * PROP_OFFSET_MAX
	var oz := world.feature_hash(wx, wz, SALT_PROP_OZ) * PROP_OFFSET_MAX
	var base := Vector3(float(x) * VOXEL_SIZE + ox, top, float(z) * VOXEL_SIZE + oz)

	if roll < PROP_MUSHROOM_PROB:
		_build_mushroom(st, base, world, wx, wz)
		_prop_count += 1
	elif roll < PROP_MUSHROOM_PROB + PROP_FLOWER_PROB:
		_build_flower(st, base, world, wx, wz)
		_prop_count += 1
	elif roll < PROP_MUSHROOM_PROB + PROP_FLOWER_PROB + PROP_GRASS_PROB:
		_build_grass_tuft(st, base, world, wx, wz)
		_prop_count += 1


## Mała kostka o dowolnym rozmiarze i pozycji (lokalnej w chunku, w METRACH).
## Używa TEGO SAMEGO nawijania CW co teren (FACE_VERTS/FACE_NORMALS) — bez ryzyka cullingu.
## Bez AO — propy są małe, AO nic nie wnosi, a oszczędza obliczenia.
func _emit_cube(st: SurfaceTool, origin: Vector3, size: float, col: Color, sway: float = 0.0) -> void:
	# Wagę „sway" (0=podstawa, 1=czubek) zapisujemy w ALFIE koloru — props.gdshader
	# używa jej do kołysania czubków na wietrze; RGB pozostaje albedo.
	var c := Color(col.r, col.g, col.b, sway)
	for fi in 6:
		var normal: Vector3 = FACE_NORMALS[fi]
		var corners: Array = FACE_VERTS[fi]
		var p0 := origin + (corners[0] as Vector3) * size
		var p1 := origin + (corners[1] as Vector3) * size
		var p2 := origin + (corners[2] as Vector3) * size
		var p3 := origin + (corners[3] as Vector3) * size
		st.set_normal(normal)
		# Trójkąt 1: p0,p2,p1  |  Trójkąt 2: p0,p3,p2  (CW od zewnątrz — jak _emit_face).
		st.set_color(c); st.add_vertex(p0)
		st.set_color(c); st.add_vertex(p2)
		st.set_color(c); st.add_vertex(p1)
		st.set_color(c); st.add_vertex(p0)
		st.set_color(c); st.add_vertex(p3)
		st.set_color(c); st.add_vertex(p2)


## Mikro-wariacja jasności koloru propa (deterministyczna, ±amp).
func _prop_tint(col: Color, world: VoxelWorld, wx: int, wz: int, salt: int, amp: float) -> Color:
	var v := (world.feature_hash(wx, wz, salt) - 0.5) * 2.0 * amp
	return Color(
		clampf(col.r + v, 0.0, 1.0),
		clampf(col.g + v, 0.0, 1.0),
		clampf(col.b + v, 0.0, 1.0),
		col.a
	)


## A) Kępka trawy — 3 źdźbła (mini-kostki) o różnej wysokości, ustawione obok siebie.
func _build_grass_tuft(st: SurfaceTool, base: Vector3, world: VoxelWorld, wx: int, wz: int) -> void:
	var s := PROP_S
	# Trzy źdźbła: drabinka wysokości 1S / 1.5S / 2S, drobne offsety XZ w obrębie voxela.
	# Offsety zmniejszone do ±0,5S (review #minor): razem z zaciśniętym ox/oz cała kępka
	# (źdźbło o boku S) mieści się w kaflu 0,5 m i nie wchodzi na sąsiedni kafel/chunk.
	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(s * 0.5, 0.0, s * 0.25),
		Vector3(-s * 0.25, 0.0, s * 0.5),
	]
	var heights: Array[float] = [s, s * 1.5, s * 2.0]
	for i in 3:
		# Tint per źdźbło: SALT_GRASS_TINT rezerwuje ciągły zakres (20,21,22) — bez kolizji saltów.
		var col := _prop_tint(Blocks.PROP_GRASS_TUFT, world, wx + i, wz, SALT_GRASS_TINT + i, 0.06)
		var o: Vector3 = base + offsets[i]
		# Każde źdźbło to słupek z kostek o boku s, ułożonych w pionie.
		var levels := int(round(heights[i] / s))
		for lv in levels:
			# Sway rośnie ku górze źdźbła (podstawa zakotwiczona, czubek gnie się najmocniej).
			var sway := clampf((float(lv) + 0.5) / float(levels), 0.0, 1.0)
			_emit_cube(st, o + Vector3(0.0, float(lv) * s, 0.0), s, col, sway)


## B) Kwiatek — łodyga (2 kostki S) + większa główka (1.5S) z palety kolorów.
func _build_flower(st: SurfaceTool, base: Vector3, world: VoxelWorld, wx: int, wz: int) -> void:
	var s := PROP_S
	var stem_col := _prop_tint(Blocks.PROP_FLOWER_STEM, world, wx, wz, SALT_FLOWER_STEM, 0.05)
	# Dwie kostki łodygi w pionie (sway rośnie ku górze; główka kołysze się najmocniej).
	_emit_cube(st, base, s, stem_col, 0.1)
	_emit_cube(st, base + Vector3(0.0, s, 0.0), s, stem_col, 0.5)
	# Główka: większa kostka (1.5S), wycentrowana nad łodygą.
	var head_col: Color = Blocks.FLOWER_COLORS[int(world.feature_hash(wx, wz, SALT_FLOWER_COLOR) * float(Blocks.FLOWER_COLORS.size()))]
	var head_s := s * 1.5
	var head_origin := base + Vector3((s - head_s) * 0.5, s * 2.0, (s - head_s) * 0.5)
	_emit_cube(st, head_origin, head_s, head_col, 1.0)


## C) Grzybek — trzonek (1 kostka S) + szerszy kapelusz (2S), czerwony lub brązowy.
func _build_mushroom(st: SurfaceTool, base: Vector3, world: VoxelWorld, wx: int, wz: int) -> void:
	var s := PROP_S
	_emit_cube(st, base, s, Blocks.MUSHROOM_STEM, 0.0)
	var cap_col := Blocks.MUSHROOM_RED if world.feature_hash(wx, wz, SALT_MUSHROOM_CAP) < 0.5 else Blocks.MUSHROOM_BROWN
	var cap_s := s * 2.0
	var cap_origin := base + Vector3((s - cap_s) * 0.5, s, (s - cap_s) * 0.5)
	_emit_cube(st, cap_origin, cap_s, cap_col, 0.35)


# --- 2) Budowa mesha (osobno: stała powierzchnia + woda) ---
func _build_mesh(world: VoxelWorld) -> void:
	var st_solid := SurfaceTool.new()
	st_solid.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_water := SurfaceTool.new()
	st_water.begin(Mesh.PRIMITIVE_TRIANGLES)

	var solid_count: int = 0
	var water_count: int = 0

	# Kolor wody policzony RAZ przed pętlą (review #minor: wcześniej _water_color()
	# robiło lookup słownika na KAŻDY voxel wody — przy WORLD_HEIGHT=96 to tysiące zbędnych wywołań).
	var water_col := _water_color()

	for x in CHUNK_SIZE:
		for z in CHUNK_SIZE:
			for y in WORLD_HEIGHT:
				var t := get_voxel(x, y, z)
				if t == Blocks.Type.AIR:
					continue
				if t == Blocks.Type.WATER:
					# Wodę renderujemy tylko jej GÓRNĄ ścianą (tafla) — tanio i czytelnie.
					if get_voxel(x, y + 1, z) == Blocks.Type.AIR:
						_emit_face(st_water, Vector3i(x, y, z), 2, water_col, false)
						water_count += 1
					continue

				# Blok stały: dla każdej z 6 ścian sprawdzamy sąsiada.
				for fi in 6:
					var n := NEIGHBORS[fi]
					if _is_face_visible(world, x, y, z, n):
						var col := _solid_color(world, t, x, y, z)
						_emit_face(st_solid, Vector3i(x, y, z), fi, col, false)
						solid_count += 1

	_has_solid = solid_count > 0

	# --- Powierzchnia stała: osobny ArrayMesh (źródło kolizji) ---
	var solid_mesh: ArrayMesh = null
	if _has_solid:
		solid_mesh = st_solid.commit()  # ArrayMesh z jedną powierzchnią
		var solid_mi := MeshInstance3D.new()
		solid_mi.name = "SolidMesh"
		solid_mi.mesh = solid_mesh
		solid_mi.material_override = world.solid_material
		add_child(solid_mi)

	# --- Powierzchnia wody: osobny MeshInstance3D, BEZ kolizji ---
	if water_count > 0:
		var water_mesh := st_water.commit()
		var water_mi := MeshInstance3D.new()
		water_mi.name = "WaterMesh"
		water_mi.mesh = water_mesh
		water_mi.material_override = world.water_material
		add_child(water_mi)

	# --- Kolizja: trimesh tylko ze stałej geometrii ---
	if _has_solid and solid_mesh != null:
		var col := CollisionShape3D.new()
		col.shape = solid_mesh.create_trimesh_shape()
		add_child(col)


## Czy ściana stałego voxela (x,y,z) w kierunku n powinna być narysowana.
func _is_face_visible(world: VoxelWorld, x: int, y: int, z: int, n: Vector3i) -> bool:
	var nx := x + n.x
	var ny := y + n.y
	var nz := z + n.z

	# Dno świata: ściana w dół z najniższej warstwy (y==0, -Y) jest niewidoczna — pomijamy.
	if n.y < 0 and y == 0:
		return false

	# Pion (Y) zawsze w obrębie tego chunku — kolumny są tu pełne.
	if n.x == 0 and n.z == 0:
		return not Blocks.is_solid(get_voxel(nx, ny, nz))

	# Granica w X/Z: jeśli sąsiad poza chunkiem, użyj heightmapy sąsiada.
	# Tu MUSIMY wołać world.surface_height (a nie _heightmap z cache), bo kolumna sąsiada
	# leży poza tym chunkiem — nie ma jej w naszym cache. To wciąż jeden lookup szumu na
	# graniczną ścianę. ŚWIADOMY KOMPROMIS (review #minor): nie zaglądamy w _voxels sąsiada,
	# więc featury sąsiada (kamień/krzak przy krawędzi) mogą dać drobne prześwity na szwie —
	# przy mgle i render_distance=4 praktycznie niewidoczne, kolizji ani spadania nie dotyczy.
	if nx < 0 or nx >= CHUNK_SIZE or nz < 0 or nz >= CHUNK_SIZE:
		var wx := _coord.x * CHUNK_SIZE + nx
		var wz := _coord.y * CHUNK_SIZE + nz
		var sy := world.surface_height(wx, wz)
		# Sąsiednia kolumna jest stała na danej wysokości tylko gdy ny <= sy.
		return ny > sy
	# Sąsiad wewnątrz chunku.
	return not Blocks.is_solid(get_voxel(nx, ny, nz))


## Dodaje jedną ścianę (2 trójkąty) do podanego SurfaceTool.
## with_ao=true włącza tani pseudo-AO w kolorze wierzchołków (ciemniejsze wnęki).
func _emit_face(st: SurfaceTool, pos: Vector3i, face_index: int, base_color: Color, with_ao: bool) -> void:
	var normal := FACE_NORMALS[face_index]
	var corners: Array = FACE_VERTS[face_index]
	var origin := Vector3(pos.x, pos.y, pos.z) * VOXEL_SIZE

	# Pozycje 4 narożników (już w lokalnych współrzędnych chunku, w metrach).
	var p0 := origin + (corners[0] as Vector3) * VOXEL_SIZE
	var p1 := origin + (corners[1] as Vector3) * VOXEL_SIZE
	var p2 := origin + (corners[2] as Vector3) * VOXEL_SIZE
	var p3 := origin + (corners[3] as Vector3) * VOXEL_SIZE

	# Pseudo-AO: przyciemnij narożniki sąsiadujące z innymi blokami.
	var c0 := base_color
	var c1 := base_color
	var c2 := base_color
	var c3 := base_color
	if with_ao:
		c0 = _ao_color(base_color, pos, face_index, 0)
		c1 = _ao_color(base_color, pos, face_index, 1)
		c2 = _ao_color(base_color, pos, face_index, 2)
		c3 = _ao_color(base_color, pos, face_index, 3)

	st.set_normal(normal)

	# Nawijanie CW patrząc OD ZEWNĄTRZ — tak Godot rozpoznaje ściany PRZEDNIE.
	# Trójkąt 1: p0, p2, p1
	st.set_color(c0); st.add_vertex(p0)
	st.set_color(c2); st.add_vertex(p2)
	st.set_color(c1); st.add_vertex(p1)
	# Trójkąt 2: p0, p3, p2
	st.set_color(c0); st.add_vertex(p0)
	st.set_color(c3); st.add_vertex(p3)
	st.set_color(c2); st.add_vertex(p2)


## Kolor stałego bloku: baza z palety + gradient trawy (wysokość) + dodatkowy „akwarelowy”
## rozsyp na kanale G dla roślin + deterministyczna mikro-wariacja per blok.
func _solid_color(world: VoxelWorld, t: int, x: int, y: int, z: int) -> Color:
	var wx := _coord.x * CHUNK_SIZE + x
	var wz := _coord.y * CHUNK_SIZE + z
	var base := Blocks.color_of(t)

	# Gradient trawy nizina -> wyżyna (kotwice z Blocks; progi z JEDNEGO źródła prawdy).
	if t == Blocks.Type.GRASS:
		var f := clampf(float(y - BEACH_MAX_Y) / float(ROCK_MIN_Y - BEACH_MAX_Y), 0.0, 1.0)
		base = Blocks.GRASS_LOW.lerp(Blocks.GRASS_HIGH, f)
		# Regionalny biom koloru (2C): sucha (żółto-zielona) vs bujna (chłodna) łąka.
		var bf := world.biome_factor(wx, wz)   # [-1,1]
		if bf < 0.0:
			base = base.lerp(Blocks.GRASS_DRY, minf(1.0, -bf * 0.7))
		else:
			base = base.lerp(Blocks.GRASS_COOL, minf(1.0, bf * 0.55))

	var v := world.tint_at(wx, y, wz)   # ~[-0.055, 0.055]

	# Dodatkowy rozsyp na zielonym kanale dla typów roślinnych => „akwarelowa” zieleń.
	var gboost := 0.0
	if t == Blocks.Type.GRASS or t == Blocks.Type.LEAVES or t == Blocks.Type.LEAVES_AUTUMN:
		gboost = v * 0.6

	return Color(
		clampf(base.r + v, 0.0, 1.0),
		clampf(base.g + v + gboost, 0.0, 1.0),
		clampf(base.b + v, 0.0, 1.0),
		base.a
	)


func _water_color() -> Color:
	# Alpha bierzemy z materiału wody; tu kolor bazowy (mnoży się z albedo_color).
	return Blocks.color_of(Blocks.Type.WATER)


## Pseudo-AO dla pojedynczego narożnika ściany (klasyczny voxel AO: 1.0/0.85/0.72/0.6).
func _ao_color(base: Color, pos: Vector3i, face_index: int, corner_index: int) -> Color:
	var corner: Vector3 = (FACE_VERTS[face_index][corner_index] as Vector3)
	var normal := FACE_NORMALS[face_index]

	# Dwie osie styczne do ściany (kierunki w płaszczyźnie ściany).
	var tangents := _face_tangents(face_index)
	var ta: Vector3i = tangents[0]
	var tb: Vector3i = tangents[1]

	# Znak przesunięcia narożnika wzdłuż każdej osi stycznej (-1 lub +1).
	var da := _corner_sign(corner, ta)
	var db := _corner_sign(corner, tb)

	# Voxel „przed” ścianą (po stronie normalnej) — punkt odniesienia AO.
	var base_cell := pos + Vector3i(int(normal.x), int(normal.y), int(normal.z))

	var side_a := _solid_at_local(base_cell + ta * da)
	var side_b := _solid_at_local(base_cell + tb * db)
	var corner_c := _solid_at_local(base_cell + ta * da + tb * db)

	var occ := 0
	if side_a: occ += 1
	if side_b: occ += 1
	if side_a and side_b:
		occ = 3
	elif corner_c:
		occ += 1

	var mult := 1.0
	match occ:
		0: mult = 1.0
		1: mult = 0.85
		2: mult = 0.72
		_: mult = 0.6

	return Color(base.r * mult, base.g * mult, base.b * mult, base.a)


## Czy w pozycji lokalnej (może wychodzić poza chunk w X/Z) jest blok stały.
func _solid_at_local(p: Vector3i) -> bool:
	if p.y < 0 or p.y >= WORLD_HEIGHT:
		return false
	if p.x >= 0 and p.x < CHUNK_SIZE and p.z >= 0 and p.z < CHUNK_SIZE:
		return Blocks.is_solid(get_voxel(p.x, p.y, p.z))
	# Poza chunkiem: przyjmujemy „pusto” (świadomy kompromis AO na granicy chunku).
	return false


## Dwie osie styczne (w płaszczyźnie ściany) dla danego indeksu ściany.
func _face_tangents(face_index: int) -> Array:
	match face_index:
		0, 1: return [Vector3i(0, 1, 0), Vector3i(0, 0, 1)]   # ±X -> Y,Z
		2, 3: return [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]   # ±Y -> X,Z
		_:    return [Vector3i(1, 0, 0), Vector3i(0, 1, 0)]   # ±Z -> X,Y


## Znak (-1/+1) przesunięcia narożnika względem środka ściany wzdłuż osi t.
func _corner_sign(corner: Vector3, t: Vector3i) -> int:
	var comp := 0.0
	if t.x != 0: comp = corner.x
	elif t.y != 0: comp = corner.y
	else: comp = corner.z
	# corner ma składowe 0 lub 1; środek ściany to 0.5.
	return 1 if comp > 0.5 else -1
