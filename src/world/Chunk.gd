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

# --- LOD (Faza 2B): 2-poziomowy LOD = większa głębia widoku TANIO ---
# Krok próbkowania zgrubnego (FAR) mesha: co LOD_FAR_STEP voxeli (2 => komórki 2×2 = 1×1 m).
# CHUNK_SIZE MUSI być podzielne przez LOD_FAR_STEP (32 % 2 == 0). Trzymanie LOD jako "step"
# (1=NEAR pełny, 2=FAR zgrubny) ułatwia przyszły LOD3 (step 4) bez zmian architektury.
const LOD_FAR_STEP: int = 2
# Głębokość fartucha (skirt) w VOXELACH, doklejanego w dół wzdłuż 4 krawędzi zgrubnego chunku.
# Bezpiecznie pokrywa typową różnicę wysokości na szwie LOD↔LOD i LOD↔NEAR (zwykle 0-2 voxele).
# 12 voxeli = 6 m kurtyny (review #minor: 4 m było marginalne na stromiznach — różnica wysokości
# na szwie potrafi przekroczyć 8 voxeli; podniesienie nie dokłada ŻADNYCH quadów, tylko wydłuża
# istniejące w dół). Kurtyna schodzi w DÓŁ i jest pionowa => gracz na ziemi jej nie widzi
# (zasłonięta własną krawędzią terenu), a daleki dystans + mgła chowają jej dolny brzeg.
const SKIRT_DEPTH: int = 12

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

# --- Drobne propy (osobny mesh, bez kolizji) — DETALICZNE MIKRO-VOXELE (styl Cube World) ---
# Propy budujemy z MIKRO-VOXELI (MV = 0,0625 m = 1/8 voxela terenu), żeby były
# ROZPOZNAWALNE (grzyb z białymi kropkami, kwiat z płatkami, źdźbła trawy) — kontrast
# skali wobec terenu 0,5 m. Każdy detaliczny prop (z wewn. cullingiem w VoxelModel,
# emitujemy tylko skorupę) mierzony realnie: grzyb ~288 ścian (~576 tri), kwiat ~94
# ściany (~188 tri), kępka 5 źdźbeł ~34 ściany. Dlatego GĘSTOŚĆ i LIMIT są zbite:
#   suma prob. 0,26 -> 0,082 (≈3,2× rzadziej); limit 200 -> 90.
# Realny budżet tri/chunk (po przeliczeniu z modeli): typowy ~9-11k tri (≈74-90 propów
# w naturalnym rozkładzie), patologiczny chunk 90×grzyb ≈ 52k tri. Czyli znacznie BEZPIECZNIEJ
# niż dawne szacunki — limit 90 jest hojny i mógłby być nawet podniesiony. Nadal 1 draw
# call/chunk (jeden PropsMesh, ten sam props_material). Komfortowe na RTX 3050 4GB.
const MV: float = VOXEL_SIZE * 0.125    # 0,0625 m — bok mikro-voxela propów
const PROP_GRASS_PROB: float = 0.060    # było 0.18 — kępki trawy
const PROP_FLOWER_PROB: float = 0.018   # było 0.06
const PROP_MUSHROOM_PROB: float = 0.004 # było 0.02 — grzyb jest najdroższy (najwięcej ścian) => najrzadszy
const MAX_PROPS_PER_CHUNK: int = 90     # było 200 (twardy bezpiecznik tri/chunk)
const PROP_S: float = VOXEL_SIZE * 0.5  # 0,25 m — referencja skali (kafel propa)

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
# --- Salty detalicznych mikro-voxelowych propów (rozłączne zakresy 60+, bez kolizji) ---
const SALT_MUSHROOM_SPOT: int = 60       # rozsyp białych kropek: SALT_MUSHROOM_SPOT+ly (rezerwuje 60..64)
const SALT_FLOWER_PETALS: int = 65       # 4 vs 6 płatków
const SALT_GRASS_COUNT: int = 66         # liczba źdźbeł 3..5
const SALT_GRASS_POSX: int = 67          # rozrzut podstaw źdźbeł X
const SALT_GRASS_POSZ: int = 68          # rozrzut podstaw źdźbeł Z
const SALT_GRASS_HEIGHT: int = 70        # wysokość źdźbła: +i (rezerwuje 70..74)
const SALT_GRASS_LEAN: int = 75          # pochylenie źdźbła: +i (rezerwuje 75..79)

# --- FINE-LEAF: drobne sub-voxele puszystych koron (tylko NEAR, tylko skorupa korony) ---
# Liść powierzchniowy (≥1 sąsiad AIR/WATER) renderujemy NIE jako kostkę 0,5 m, lecz jako
# klaster LEAF_SUB³ sub-voxeli (bok = VOXEL_SIZE/LEAF_SUB) z deterministycznymi prześwitami
# (światło przebija) + wariacją zieleni per sub-voxel. Liść WEWNĘTRZNY (otoczony) pomijamy
# całkiem (0 geometrii). Wszystko OFF-THREAD-safe: czysta arytmetyka + feature_hash + lokalny
# SurfaceTool + VoxelModel.emit_to_static (static). Pień WOOD i terrain bez zmian.
const LEAF_SUB: int = 2                   # podział na sub-voxele (2 -> 0,25 m; 3 -> ~0,167 m)
# DAPPLE NA POZIOMIE VOXELA LIŚCIA (0,5 m): ~32% powierzchniowych liści wycinamy w całość =>
# duże szpary światła w koronie. Każdy ZACHOWANY liść staje się puszystym klastrem sub-voxeli.
# WYJĄTEK (review #MAJOR): liść ZAKOTWICZONY (stykający się z WOOD lub terenem) NIGDY nie jest
# wycinany w całość — inaczej powstałby prześwit przez pień/ziemię, których ściana ku liściowi
# została już cullowana przez _is_face_visible (is_solid(LEAVES)==true). Patrz _classify_leaf.
const LEAF_VOXEL_DAPPLE: float = 0.32     # P(wycięcia całego NIEzakotwiczonego liścia)
# PRZEŚWIT POJEDYNCZEGO SUB-VOXELA (review #MAJOR tri-count): przy SUB=2 KAŻDY zachowany klaster
# bez tego byłby pełnym 2×2×2 (8 komórek, 0 wnętrza) => identyczna sylwetka jak kostka 0,5 m,
# tylko 48 tri zamiast ≤12. Wycięcie 1-3 z 8 sub-voxeli (a) tworzy REALNĄ postrzępioną „puszystość”
# na skali 0,25 m (nie tylko drobniej pokrojona kostka), (b) ZMNIEJSZA liczbę emitowanych ścian.
# 0.18 daje ~1,4 wyciętego sub-voxela/klaster średnio => klaster nieregularny, lekki, dappled.
const LEAF_SUB_GAP_PROB: float = 0.18     # P(wycięcia POJEDYNCZEGO sub-voxela) — działa też przy SUB=2
const LEAF_TINT_AMP: float = 0.06         # ±jasność per sub-voxel (pod AGX+glow: bezpiecznie < knee)
const LEAF_WARM_AMP: float = 0.03         # ±ciepło/chłód (zieleń); jesień ma własny, cieplejszy rozrzut
# Twardy bezpiecznik tri/chunk (4GB): budżet liczony w EMITOWANYCH ŚCIANACH (review #minor — sub-voxele
# NIE skalują się 1:1 z tri, a skorupa klastra zależy od prześwitów i SUB). Po wyczerpaniu liście
# wracają do kostki 0,5 m (degradacja zamiast dziur). ~9000 ścian => ~18000 tri liści/chunk: ~6-8 drzew
# typowych, sufit dla patologicznego gęstego lasu. Próg w ścianach jest stabilny wobec zmian SUB/dapple.
const LEAF_FACE_BUDGET: int = 9000
# Salty fine-leaf (rozłączne, jednowartościowe bazy; +sub_i tylko dla gap/tint/warm). KAŻDA decyzja
# DEKORELUJE WARSTWY Y (review #MAJOR diagonal stripes): dawne składanie y do argumentu Z (wz+y)
# aliasowało różne voxele świata o równym (wz+y) do tej samej decyzji => widoczna ukośna kratka
# prześwitów. NIE używamy SALT+y (y to LOKALNE Y chunku 0..95 — wpadałoby w okna sąsiednich saltów),
# tylko MIESZAMY y do współrzędnych hasha mnożnikami pierwszymi (patrz _emit_leaf_cluster): dapple
# z hx=wx*K+y*P, hz=wz*K-y*Q (salt stały), gap/tint/warm analogicznie ze swoim scramblem. Salt stały
# => bazy mogą leżeć blisko siebie. Indeks sub-voxela 0..LEAF_SUB³-1 (max 26 dla SUB=3) dodajemy do
# bazy gap/tint/warm, więc okna 100..126 / 130..156 / 160..186 są rozłączne.
const SALT_LEAF_VOXEL_DAPPLE: int = 80   # wycięcie całego liścia (1 wartość; y mieszany w coords)
const SALT_LEAF_SUB_GAP: int = 100       # prześwit sub-voxela: +sub_i (rezerwuje 100..126 dla SUB=3)
const SALT_LEAF_TINT: int = 130          # jasność sub-voxela: +sub_i (rezerwuje 130..156)
const SALT_LEAF_WARM: int = 160          # ciepło sub-voxela:  +sub_i (rezerwuje 160..186)
# Flagi maski zwracanej przez _classify_leaf (bit0 = powierzchniowy, bit1 = zakotwiczony).
const LEAF_FLAG_SURFACE: int = 1
const LEAF_FLAG_ANCHORED: int = 2

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

# Poziom szczegółowości tego chunku jako KROK próbkowania voxeli (Faza 2B).
# 1 = NEAR (pełny detal: voxele + kolizja + propy + woda — ścieżka jak w 2A).
# 2 = FAR  (zgrubny: tylko heightmap co 2 voxele -> _r_solid_mesh, BEZ kolizji/propów/wody).
# Ustawiany przez VoxelWorld PRZED add_task/generate (niemutowany w trakcie taska => thread-safe).
var _lod_step: int = 1

# Czy chunk ma jakąkolwiek stałą geometrię (decyduje o tym, czy dodajemy kolizję).
var _has_solid: bool = false

# Licznik wygenerowanych propów (twardy limit MAX_PROPS_PER_CHUNK).
var _prop_count: int = 0

# --- Wyniki build_data() (wypełniane OFF-THREAD, czytane w finalize() na GŁÓWNYM watku) ---
# To CZYSTE zasoby (ArrayMesh / Shape3D), wolno je tworzyć na wątku roboczym.
# finalize() je tylko podpina do węzłów (MeshInstance3D / CollisionShape3D) i robi add_child.
var _r_solid_mesh: ArrayMesh = null      # gotowy mesh stałej geometrii (lub null)
var _r_water_mesh: ArrayMesh = null      # gotowy mesh wody (lub null)
var _r_props_mesh: ArrayMesh = null      # gotowy mesh drobnych propów (lub null)
var _r_leaf_mesh: ArrayMesh = null       # fine-leaf: korony liści (NEAR) — OSOBNY mesh, BEZ kolizji
var _r_collision_shape: Shape3D = null   # gotowy trimesh shape ze stałej geometrii (lub null)

# Strażnicy cyklu życia (sanity): build_data() policzone? finalize() wykonany?
var _data_ready: bool = false
var _finalized: bool = false


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


## OFF-THREAD. Liczy dane voxeli + składa GOTOWE zasoby (ArrayMesh solid/water/props) do pól
## _r_*. Shape3D kolizji NIE jest tu liczony (create_trimesh_shape nie jest thread-safe —
## godot#69076); powstaje na głównym watku w finalize(). ŻADNYCH operacji na drzewie sceny.
## Może być wołane z WorkerThreadPool (jeden task = jeden chunk = własne SurfaceToole) ALBO
## synchronicznie z głównego watku (prime). 'world' (VoxelWorld) i 'self' muszą żyć do końca taska.
##
## Thread-safety: czyta TYLKO niemutowane szumy world (surface_height/tint_at/biome_factor —
## konfigurowane raz w _ready i nigdy potem) i czystą arytmetykę feature_hash. Pisze WYŁĄCZNIE
## do własnych pól tego chunku (_voxels/_heightmap/_r_*). VoxelModel.emit_to jest static i bezstanowe.
## 'lod_step' (Faza 2B): 1 = NEAR (pełny detal), 2 = FAR (zgrubny). Domyślnie 1, by stare
## ścieżki (generate/_build_chunk_sync wołające build_data bez lod) zawsze dawały pełny grunt.
## VoxelWorld wpisuje _lod_step PRZED add_task; parametr jest dla synchronicznych wywołań.
func build_data(chunk_coord: Vector2i, world: VoxelWorld, lod_step: int = -1) -> void:
	_coord = chunk_coord
	if lod_step > 0:
		_lod_step = lod_step
	if _lod_step <= 1:
		_generate_data(world)        # PEŁNY: _voxels + _heightmap + propy -> _r_props_mesh
		_build_mesh(world)           # -> _r_solid_mesh / _r_water_mesh (kolizja liczona w finalize)
	else:
		_build_coarse(world)         # ZGRUBNY: tylko heightmap (krok) -> _r_solid_mesh + skirts
	_data_ready = true


## GŁÓWNY WĄTEK. Tworzy węzły (MeshInstance3D / CollisionShape3D) z gotowych zasobów build_data()
## i podpina je przez add_child. NIC nie liczy. Wołane DOPIERO po is_task_completed()==true
## (bariera pamięci wait_for_task_completion gwarantuje widoczność zapisów taska) albo wprost
## po synchronicznym build_data() (prime). Idempotentne (guard _finalized).
##
## WYMAGANIE: self MUSI być już w drzewie (VoxelWorld robi add_child(chunk) tuż przed finalize),
## żeby add_child dzieci i rejestracja kolizji w PhysicsServer działały na głównym watku.
func finalize(world: VoxelWorld) -> void:
	if _finalized:
		return

	# --- Powierzchnia stała ---
	if _r_solid_mesh != null:
		var solid_mi := MeshInstance3D.new()
		solid_mi.name = "SolidMesh"
		solid_mi.mesh = _r_solid_mesh
		solid_mi.material_override = world.solid_material
		add_child(solid_mi)

	# --- Powierzchnia wody (BEZ kolizji) ---
	if _r_water_mesh != null:
		var water_mi := MeshInstance3D.new()
		water_mi.name = "WaterMesh"
		water_mi.mesh = _r_water_mesh
		water_mi.material_override = world.water_material
		add_child(water_mi)

	# --- Drobne propy (BEZ kolizji) ---
	if _r_props_mesh != null:
		var props_mi := MeshInstance3D.new()
		props_mi.name = "PropsMesh"
		props_mi.mesh = _r_props_mesh
		props_mi.material_override = world.props_material
		add_child(props_mi)

	# --- Korony liści fine-leaf (BEZ kolizji) — ten sam materiał co teren (vertex-color albedo) ---
	if _r_leaf_mesh != null:
		var leaf_mi := MeshInstance3D.new()
		leaf_mi.name = "LeafMesh"
		leaf_mi.mesh = _r_leaf_mesh
		leaf_mi.material_override = world.solid_material
		add_child(leaf_mi)

	# --- Kolizja: trimesh tylko ze stałej geometrii — i TYLKO dla chunków NEAR (Faza 2B) ---
	# create_trimesh_shape() liczymy TU, na GŁÓWNYM watku (NIE off-thread — patrz BLOCKER
	# w _build_mesh: godot#69076). Koszt ~0,1-0,5 ms/chunk, throttlowany MAX_FINALIZE_PER_FRAME.
	# FAR (_lod_step>1) jest BEZKOLIZYJNY: gracz po nim nie chodzi (zaczyna się za near_dist),
	# a pominięcie create_trimesh_shape zeruje koszt głównego watku dla dali => far_dist może
	# rosnąć tanio. Zanim gracz dojdzie na FAR, VoxelWorld przebuduje chunk na NEAR (z kolizją).
	# Guard `_r_collision_shape == null` chroni przed dublem przy idempotentnym finalize.
	if _lod_step <= 1 and _r_solid_mesh != null:
		if _r_collision_shape == null:
			_r_collision_shape = _r_solid_mesh.create_trimesh_shape()
		if _r_collision_shape != null:
			var col := CollisionShape3D.new()
			col.shape = _r_collision_shape
			add_child(col)

	# Zwolnij surowe dane voxeli — niepotrzebne po zbudowaniu (oszczędność RAM przy wielu chunkach).
	_voxels = PackedByteArray()
	_heightmap = PackedInt32Array()
	_finalized = true


## Pełny cykl SYNCHRONICZNY: dane → mesh → kolizja → węzły. Dla prime()/kill-plane,
## gdzie gracz nie może spaść przez niezaładowany teren (musi powstać od ręki, na głównym watku).
## Wymaga, by self był już w drzewie (jak dotąd: VoxelWorld add_child(chunk) PRZED generate()).
func generate(chunk_coord: Vector2i, world: VoxelWorld) -> void:
	build_data(chunk_coord, world)
	finalize(world)


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

	# Po pętli: jeśli powstały jakiekolwiek propy, zcommituj ArrayMesh do POLA (OFF-THREAD).
	# Węzeł MeshInstance3D + add_child powstaje dopiero w finalize() na GŁÓWNYM watku.
	if _prop_count > 0:
		var props_mesh := st_props.commit()
		if props_mesh != null and props_mesh.get_surface_count() > 0:
			_r_props_mesh = props_mesh   # tylko zapamiętaj gotowy zasób


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
	# Wierzch bloku trawy (lokalnie, w metrach). OFFSET=0 dla detalicznych modeli
	# (review): modele mikro-voxelowe są szerokie (grzyb ~0,6 m) i są centrowane w XZ
	# na środku kafla przez _build_* (przesunięcie base o -pół-szerokości). Dodatkowy
	# losowy offset wypchnąłby najszersze propy poza kafel, a na skraju chunku poza chunk
	# (nakładanie na szwie). Modele mają własny mikro-rozrzut (źdźbła/płatki), więc nic nie tracimy.
	const PROP_OFFSET_MAX: float = 0.0
	var top := float(sy + 1) * VOXEL_SIZE
	var ox := world.feature_hash(wx, wz, SALT_PROP_OX) * PROP_OFFSET_MAX
	var oz := world.feature_hash(wx, wz, SALT_PROP_OZ) * PROP_OFFSET_MAX
	# Środek kafla w XZ (model centrujemy względem tego punktu w _build_*).
	var base := Vector3(float(x) * VOXEL_SIZE + ox + VOXEL_SIZE * 0.5, top,
			float(z) * VOXEL_SIZE + oz + VOXEL_SIZE * 0.5)

	if roll < PROP_MUSHROOM_PROB:
		_build_mushroom(st, base, world, wx, wz)
		_prop_count += 1
	elif roll < PROP_MUSHROOM_PROB + PROP_FLOWER_PROB:
		_build_flower(st, base, world, wx, wz)
		_prop_count += 1
	elif roll < PROP_MUSHROOM_PROB + PROP_FLOWER_PROB + PROP_GRASS_PROB:
		_build_grass_tuft(st, base, world, wx, wz)
		_prop_count += 1


## Renderuje detaliczny model mikro-voxelowy do współdzielonego PropsMesh (st).
## Model (VoxelModel.VoxelDef) jest CENTROWANY w XZ na 'base' (środek kafla) i kładziony
## dołem (min y) na base.y. Sway już zapisany per voxel w defie (COLOR.a). Wewnętrzny
## culling ścian robi VoxelModel._emit — emitujemy tylko zewnętrzną skorupę.
## Bok mikro-voxela = MV (0,0625 m). Nawijanie CW spójne z terenem i _emit_face.
func _emit_model(st: SurfaceTool, def: VoxelModel.VoxelDef, base: Vector3) -> void:
	if def.is_empty():
		return
	# Bounding box modelu (w jednostkach MV) do centrowania XZ i osadzenia dołu na base.y.
	var min_x := 1 << 30; var max_x := -(1 << 30)
	var min_y := 1 << 30
	var min_z := 1 << 30; var max_z := -(1 << 30)
	for k: Vector3i in def.cells:
		min_x = mini(min_x, k.x); max_x = maxi(max_x, k.x)
		min_y = mini(min_y, k.y)
		min_z = mini(min_z, k.z); max_z = maxi(max_z, k.z)
	# Środek XZ modelu (w MV) — przesuwamy tak, by trafił w base (środek kafla),
	# a dół (min_y) na base.y. offset to wektor metrowy dodawany do p*MV w VoxelModel._emit.
	var cx := float(min_x + max_x + 1) * 0.5
	var cz := float(min_z + max_z + 1) * 0.5
	var offset := Vector3(base.x - cx * MV, base.y - float(min_y) * MV, base.z - cz * MV)
	VoxelModel.emit_to(st, def, offset, MV)


## Mikro-wariacja jasności koloru propa (deterministyczna, ±amp).
func _prop_tint(col: Color, world: VoxelWorld, wx: int, wz: int, salt: int, amp: float) -> Color:
	var v := (world.feature_hash(wx, wz, salt) - 0.5) * 2.0 * amp
	return Color(
		clampf(col.r + v, 0.0, 1.0),
		clampf(col.g + v, 0.0, 1.0),
		clampf(col.b + v, 0.0, 1.0),
		col.a
	)


## A) Kępka trawy — DETALICZNA: 3-5 cienkich źdźbeł (słupki 1×N MV) o różnej wysokości
## i pochyleniu. Sway rośnie ku czubkowi (zakodowany w defie -> COLOR.a).
func _build_grass_tuft(st: SurfaceTool, base: Vector3, world: VoxelWorld, wx: int, wz: int) -> void:
	_emit_model(st, _model_grass_tuft(world, wx, wz), base)

## B) Kwiatek — DETALICZNY: smukła łodyga + listek + główka (żółty środek 2×2 + 4-6 płatków).
func _build_flower(st: SurfaceTool, base: Vector3, world: VoxelWorld, wx: int, wz: int) -> void:
	_emit_model(st, _model_flower(world, wx, wz), base)

## C) Grzybek — DETALICZNY muchomor: kremowy trzonek + kopulasty kapelusz z białymi kropkami.
func _build_mushroom(st: SurfaceTool, base: Vector3, world: VoxelWorld, wx: int, wz: int) -> void:
	_emit_model(st, _model_mushroom(world, wx, wz), base)


# ============================================================================
#  GENERATORY DETALICZNYCH MODELI PROPÓW (siatka mikro-voxeli Vector3i, y=0 = nasada)
#  Sway w defie: 0 = nasada (zakotwiczona), rośnie ku górze (czubki gną się na wietrze).
# ============================================================================

## KĘPKA TRAWY: 3-5 cienkich źdźbeł (słupki 1×N MV), różna wysokość + lekkie pochylenie.
func _model_grass_tuft(world: VoxelWorld, wx: int, wz: int) -> VoxelModel.VoxelDef:
	var d := VoxelModel.VoxelDef.new()
	var blades := 3 + int(world.feature_hash(wx, wz, SALT_GRASS_COUNT) * 3.0)   # 3,4,5
	var cx := 4
	var cz := 4
	for i in blades:
		# Podstawa źdźbła (deterministyczny rozrzut w obrębie małej kępki).
		var bx := cx + int(round((world.feature_hash(wx + i, wz, SALT_GRASS_POSX) - 0.5) * 4.0))
		var bz := cz + int(round((world.feature_hash(wx, wz + i, SALT_GRASS_POSZ) - 0.5) * 4.0))
		# Wysokość 4..8 MV (0,25..0,5 m) — różna na źdźbło.
		var h := 4 + int(world.feature_hash(wx + i * 3, wz + i * 5, SALT_GRASS_HEIGHT + i) * 5.0)
		# Pochylenie (kierunek + siła; przesunięcie XZ rosnące ku górze).
		var lean_x := (world.feature_hash(wx + i * 7, wz, SALT_GRASS_LEAN + i) - 0.5) * 1.6
		var lean_z := (world.feature_hash(wx, wz + i * 11, SALT_GRASS_LEAN + i) - 0.5) * 1.6
		# Tint per źdźbło (ciągły zakres saltów: SALT_GRASS_TINT 20..22).
		var col := _prop_tint(Blocks.PROP_GRASS_TUFT, world, wx + i, wz, SALT_GRASS_TINT + (i % 3), 0.07)
		for y in h:
			var t := float(y) / float(maxi(1, h - 1))    # 0 u nasady, 1 na czubku
			var ox := int(round(lean_x * t * float(h) * 0.5))
			var oz := int(round(lean_z * t * float(h) * 0.5))
			var c := col.lightened(0.10 * t)             # czubek lekko jaśniejszy
			# Sway: nasada 0, czubek ~1 (źdźbła gną się najmocniej).
			d.set_voxel(Vector3i(bx + ox, y, bz + oz), c, t)
	return d


## KWIAT: cienka łodyga MV + listek + główka (żółty środek 2×2 + 4-6 płatków wokół).
func _model_flower(world: VoxelWorld, wx: int, wz: int) -> VoxelModel.VoxelDef:
	var d := VoxelModel.VoxelDef.new()
	var stem_col := _prop_tint(Blocks.PROP_FLOWER_STEM, world, wx, wz, SALT_FLOWER_STEM, 0.05)
	var petal_col: Color = Blocks.FLOWER_COLORS[
		int(world.feature_hash(wx, wz, SALT_FLOWER_COLOR) * float(Blocks.FLOWER_COLORS.size()))
	]
	var core_col := Blocks.FLOWER_CORE

	var cx := 3
	var cz := 3
	var stem_h := 6
	var max_y := stem_h + 2   # szczyt główki (do normalizacji sway)
	# Łodyga 1×1 MV z lekkim wygięciem (przesunięcie X ku górze) + listek.
	for y in stem_h:
		var bend := int(round(float(y) * 0.25))
		var sw := float(y) / float(max_y) * 0.5     # łodyga gnie się umiarkowanie
		d.set_voxel(Vector3i(cx + bend, y, cz), stem_col, sw)
		if y == 2:
			d.set_voxel(Vector3i(cx + bend + 1, y, cz), stem_col, sw)
			d.set_voxel(Vector3i(cx + bend + 2, y, cz), stem_col.lightened(0.05), sw)

	var hx := cx + int(round(float(stem_h) * 0.25))
	var hy := stem_h
	# Żółty środek 2×2×2 (główka kołysze się najmocniej -> sway ~1).
	for dy in 2:
		for dx in 2:
			for dz in 2:
				d.set_voxel(Vector3i(hx + dx, hy + dy, cz + dz), core_col, 1.0)
	# Płatki: 4 lub 6 wokół środka (warstwa dolna główki).
	var six := world.feature_hash(wx, wz, SALT_FLOWER_PETALS) < 0.5
	var py := hy
	var dirs4: Array[Vector2i] = [
		Vector2i( 2, 0), Vector2i(-2, 0), Vector2i(0,  2), Vector2i(0, -2)
	]
	var dirs6: Array[Vector2i] = [
		Vector2i( 2, 0), Vector2i(-2, 0), Vector2i( 1,  2), Vector2i(-1,  2),
		Vector2i( 1, -2), Vector2i(-1, -2)
	]
	var dirs: Array[Vector2i] = dirs6 if six else dirs4
	for dd in dirs:
		# Płatek + wypełnienie między środkiem a płatkiem (spójna główka).
		d.set_voxel(Vector3i(hx + dd.x, py, cz + dd.y), petal_col, 1.0)
		# Łącznik (szprycha) przez signi, NIE dd.x/2: int-dzielenie ucina nieparzyste
		# kierunki dirs6 do 0, więc szprychy płatków diagonalnych nakładałyby się na jedną komórkę.
		d.set_voxel(Vector3i(hx + signi(dd.x), py, cz + signi(dd.y)), petal_col.lightened(0.04), 1.0)
	return d


## GRZYB (muchomor): kremowy trzonek 2×2 MV + kopulasty kapelusz (dome) z białymi kropkami.
## Czerwony lub brązowy kapelusz (SALT_MUSHROOM_CAP).
func _model_mushroom(world: VoxelWorld, wx: int, wz: int) -> VoxelModel.VoxelDef:
	var d := VoxelModel.VoxelDef.new()
	var cap_col := Blocks.MUSHROOM_RED if world.feature_hash(wx, wz, SALT_MUSHROOM_CAP) < 0.5 \
		else Blocks.MUSHROOM_BROWN
	var stem_col := Blocks.MUSHROOM_STEM
	var spot_col := Blocks.MUSHROOM_SPOT

	# Trzonek: słupek 2×2 MV, wys. 4 (lekki cień u dołu). Sway minimalny (sztywny u ziemi).
	var stem_h := 4
	for y in stem_h:
		for dx in 2:
			for dz in 2:
				var sc := stem_col.darkened(0.06 * float(stem_h - 1 - y) / float(stem_h))
				d.set_voxel(Vector3i(dx + 3, y, dz + 3), sc, 0.0)

	# Kapelusz: dome. Promień maleje ku górze (kopuła). Środek nad trzonkiem.
	var cap_y0 := stem_h - 1            # kapelusz nachodzi 1 MV na trzonek (połączenie)
	var cap_levels := 5
	var R_BASE := 4.5                   # promień u podstawy kapelusza (MV)
	var ccx := 4
	var ccz := 4
	var top_y := cap_y0 + cap_levels - 1
	for ly in cap_levels:
		var t := float(ly) / float(cap_levels - 1)      # 0 dół kapelusza, 1 czubek
		var r := R_BASE * cos(t * 0.5 * PI) + 0.6       # dome: najszerszy u dołu
		var y := cap_y0 + ly
		var r2 := r * r
		# Sway kapelusza: rośnie ku czubkowi, max ~0,20 (grzyb gnie się delikatnie).
		var sw := 0.20 * float(y) / float(maxi(1, top_y))
		for dx in range(-5, 6):
			for dz in range(-5, 6):
				var fx := float(dx) + 0.5
				var fz := float(dz) + 0.5
				if fx * fx + fz * fz > r2:
					continue
				# Ujemne klucze Vector3i są poprawne (słownik je przyjmuje), a _emit_model
				# i tak recentruje model po bboxie — dawny guard gx<0/gz<0 ścinał kopułę
				# tylko po stronie -X/-Z (asymetryczny grzyb). Usunięty => dome symetryczny.
				var gx := ccx + dx
				var gz := ccz + dz
				# Białe kropki: deterministyczny pierścień plamek na górnej połowie kapelusza.
				var col := cap_col
				if t > 0.15 and t < 0.95:
					var spot := world.feature_hash(wx + gx * 7, wz + gz * 13, SALT_MUSHROOM_SPOT + ly)
					var edge_ring := (fx * fx + fz * fz) > (r2 * 0.25)
					if spot < 0.16 and edge_ring:
						col = spot_col
				d.set_voxel(Vector3i(gx, y, gz), col, sw)
	return d


# --- 2) Budowa mesha (osobno: stała powierzchnia + woda) ---
func _build_mesh(world: VoxelWorld) -> void:
	var st_solid := SurfaceTool.new()
	st_solid.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_water := SurfaceTool.new()
	st_water.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Fine-leaf: korony liści idą do OSOBNEGO mesha (bez kolizji). Skorupa liści (tysiące
	# drobnych trójkątów) NIE może trafić do trimesh kolizji — to zabijało finalize
	# (create_trimesh_shape na głównym watku) i FPS. Liście nie wymagają kolizji.
	var st_leaf := SurfaceTool.new()
	st_leaf.begin(Mesh.PRIMITIVE_TRIANGLES)

	var solid_count: int = 0
	var water_count: int = 0
	var leaf_count: int = 0

	# Kolor wody policzony RAZ przed pętlą (review #minor: wcześniej _water_color()
	# robiło lookup słownika na KAŻDY voxel wody — przy WORLD_HEIGHT=96 to tysiące zbędnych wywołań).
	var water_col := _water_color()

	# Budżet ŚCIAN liści dla CAŁEGO chunku (twardy bezpiecznik tri/chunk na 4GB; review #minor:
	# w ścianach, nie sub-voxelach — odporne na zmianę SUB/dapple). _build_mesh biegnie wyłącznie
	# dla NEAR (lod_step<=1), więc fine-leaf jest tu zawsze "włączony".
	var leaf_face_budget := LEAF_FACE_BUDGET

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

				# --- FINE-LEAF (NEAR): liście LEAVES/LEAVES_AUTUMN nie jako kostka 0,5 m ---
				# Tylko powierzchniowe (≥1 sąsiad AIR/WATER); wnętrze korony pomijamy całkiem.
				if t == Blocks.Type.LEAVES or t == Blocks.Type.LEAVES_AUTUMN:
					# Jeden przebieg po 6 sąsiadach => maska bitowa (bit0=POWIERZCHNIOWY: ≥1 sąsiad
					# AIR/WATER; bit1=ZAKOTWICZONY: styka się z WOOD/terenem). Typowany int, bez Variantów.
					var lf := _classify_leaf(x, y, z)
					if (lf & LEAF_FLAG_SURFACE) == 0:
						continue   # liść WEWNĘTRZNY (otoczony) => 0 geometrii (oszczędność)
					if leaf_face_budget > 0:
						var lc := _solid_color(world, t, x, y, z)   # baza zieleni/biom/tint (reuse)
						var anchored := (lf & LEAF_FLAG_ANCHORED) != 0
						# Klaster do st_leaf (osobny mesh BEZ kolizji), nie st_solid.
						var faces := _emit_leaf_cluster(st_leaf, world, x, y, z, t, lc, anchored)
						leaf_face_budget -= faces
						if faces > 0:
							leaf_count += 1
						continue
					# Budżet wyczerpany => fallback do zwykłej kostki (degradacja, NIE continue).

				# Blok stały: dla każdej z 6 ścian sprawdzamy sąsiada.
				for fi in 6:
					var n := NEIGHBORS[fi]
					if _is_face_visible(world, x, y, z, n):
						var col := _solid_color(world, t, x, y, z)
						_emit_face(st_solid, Vector3i(x, y, z), fi, col, false)
						solid_count += 1

	_has_solid = solid_count > 0

	# --- OFF-THREAD: commit gotowych zasobów do pól. ZERO operacji na drzewie sceny.
	#     Węzły (MeshInstance3D / CollisionShape3D) + add_child powstają w finalize() na głównym watku.

	# Powierzchnia stała: osobny ArrayMesh (źródło kolizji).
	# UWAGA (BLOCKER): create_trimesh_shape() NIE jest thread-safe w Godot 4.x (godot#69076 —
	# wołane z WorkerThreadPool zawiesza/deadlockuje grę, bo sięga do PhysicsServer3D, który
	# defer-uje na główny wątek; przy prime()/_exit_tree główny czeka blokująco na ten task
	# => klasyczne zakleszczenie). Dlatego TUTAJ (off-thread) liczymy WYŁĄCZNIE commit() ArrayMesh.
	# Trimesh shape powstaje na GŁÓWNYM watku w finalize() (PLAN B z notatek = teraz PLAN A).
	if _has_solid:
		_r_solid_mesh = st_solid.commit()  # ArrayMesh z jedną powierzchnią (czysty zasób, OK off-thread)

	# Powierzchnia wody: osobny ArrayMesh, BEZ kolizji.
	if water_count > 0:
		_r_water_mesh = st_water.commit()

	# Korony liści (fine-leaf): osobny ArrayMesh, BEZ kolizji (skorupa liści NIE w trimesh).
	if leaf_count > 0:
		_r_leaf_mesh = st_leaf.commit()


# --- FINE-LEAF: helpery (tylko NEAR; wołane z _build_mesh) ---

## Jeden przebieg po 6 sąsiadach klasyfikuje voxel liścia (review: scala dwa dawne przebiegi
## w jeden — _is_leaf_surface robiło te same 6 lookupów). Zwraca maskę bitową:
##  LEAF_FLAG_SURFACE  — ≥1 sąsiad to AIR/WATER (liść odsłonięty => renderujemy klaster);
##  LEAF_FLAG_ANCHORED — ≥1 sąsiad to NIE-liść SOLID (WOOD lub dowolny blok terenu) — taki liść
##                       NIGDY nie może zniknąć przez DAPPLE, bo ściana sąsiada ku niemu została
##                       już cullowana w _is_face_visible (is_solid(LEAVES)==true) => wycięcie liścia
##                       zrobiłoby prześwit przez pień/ziemię (review #MAJOR „dziury pień|liście”).
## get_voxel poza zakresem zwraca AIR => brzeg chunku liczy się jako odsłonięty (korony mają
## margines TREE_MARGIN=7 i nie dotykają szwu, więc anchored na szwie nie występuje).
func _classify_leaf(x: int, y: int, z: int) -> int:
	var flags := 0
	for n in NEIGHBORS:
		var nt := get_voxel(x + n.x, y + n.y, z + n.z)
		if nt == Blocks.Type.AIR or nt == Blocks.Type.WATER:
			flags |= LEAF_FLAG_SURFACE
		elif nt != Blocks.Type.LEAVES and nt != Blocks.Type.LEAVES_AUTUMN:
			# Sąsiad jest stały i NIE jest liściem => pień (WOOD) lub teren => liść zakotwiczony.
			flags |= LEAF_FLAG_ANCHORED
	return flags


## Renderuje POWIERZCHNIOWY voxel liścia jako klaster drobnych sub-voxeli (skorupa + prześwity
## + wariacja koloru), reużywając VoxelModel.emit_to_static (wewn. face-culling + CW winding,
## A=0 jawnie => liście nie kołyszą się w shaderze terenu). Zwraca liczbę WYEMITOWANYCH ŚCIAN
## (do odjęcia z budżetu — review #minor: budżet w ścianach, nie sub-voxelach). Determinizm i
## thread-safety: wyłącznie world.feature_hash (czysta arytmetyka) + lokalny VoxelDef + static
## emit — ten sam chunk zawsze daje identyczny mesh, zero operacji na drzewie sceny / _voxels.
##
## DAPPLE (skala liścia): ~LEAF_VOXEL_DAPPLE NIEzakotwiczonych liści znika w całości => duże
## szpary światła. Liść 'anchored' (przy pniu/terenie) jest z dapple WYŁĄCZONY (brak prześwitu
## przez solid). SUB-GAP (skala sub-voxela): LEAF_SUB_GAP_PROB wycina pojedyncze sub-voxele =>
## klaster nieregularny/puszysty (a NIE drobniej pokrojona pełna kostka) i mniej ścian — działa
## też przy SUB=2. Y-warstwy decorrelowane (review #MAJOR): WSZYSTKIE decyzje (dapple/gap/tint/warm)
## mieszają y do współrzędnych hasha mnożnikami pierwszymi przy stałym salcie (NIE wz+y, NIE salt+y)
## => brak ukośnej kratki prześwitów i zachowane rozłączne okna saltów.
func _emit_leaf_cluster(st: SurfaceTool, world: VoxelWorld, x: int, y: int, z: int,
		t: int, base_col: Color, anchored: bool) -> int:
	# Współrzędne świata tego voxela liścia — STABILNA kotwica determinizmu per voxel.
	var wx := _coord.x * CHUNK_SIZE + x
	var wz := _coord.y * CHUNK_SIZE + z

	# DAPPLE na skali liścia: część NIEzakotwiczonych liści znika w całości => światło przebija.
	# Y mieszamy do WSPÓŁRZĘDNYCH hasha różnymi mnożnikami pierwszymi (NIE wz+y, NIE salt+y), więc
	# warstwy korony nie aliasują się do wspólnej ukośnej kratki (review #MAJOR), a salt zostaje stały
	# i rozłączny. Liść zakotwiczony NIGDY nie znika (brak prześwitu przez pień/ziemię).
	if not anchored \
	and world.feature_hash(wx * 31 + y * 23, wz * 17 - y * 11, SALT_LEAF_VOXEL_DAPPLE) < LEAF_VOXEL_DAPPLE:
		return 0

	var sub := LEAF_SUB
	var autumn := t == Blocks.Type.LEAVES_AUTUMN
	var d := VoxelModel.VoxelDef.new()
	var placed := 0
	for sx in sub:
		for sy in sub:
			for sz in sub:
				# Lokalny indeks sub-voxela 0..sub³-1 (rozłączne okno saltów gap/tint/warm).
				var sub_i := sx + sub * (sy + sub * sz)
				# Współrzędne hasha unikalne per sub-voxel W ŚWIECIE (sąsiednie klastry niezależne).
				# Y decorrelowany: mieszamy go w X i Z różnymi mnożnikami pierwszymi (NIE wz+y),
				# żeby warstwy nie tworzyły ukośnych wzorów (review #MAJOR, ten sam fold co dapple).
				var hx := (wx * sub + sx) * 31 + y * 17
				var hz := (wz * sub + sz) * 17 - y * 13
				# Prześwit pojedynczego sub-voxela => klaster nieregularny/puszysty (i mniej ścian).
				if LEAF_SUB_GAP_PROB > 0.0 \
				and world.feature_hash(hx, hz, SALT_LEAF_SUB_GAP + sub_i) < LEAF_SUB_GAP_PROB:
					continue
				# Wariacja koloru per sub-voxel: jasność ± + lekka temperatura ±. Warm ma WŁASNY,
				# niezależny scramble (review #minor: nie arg-swap hz/hx — pełna dekorelacja od tint).
				var lv := (world.feature_hash(hx, hz, SALT_LEAF_TINT + sub_i) - 0.5) * 2.0 * LEAF_TINT_AMP
				var wv := (world.feature_hash(hx + 101, hz + 53, SALT_LEAF_WARM + sub_i) - 0.5) * 2.0 * LEAF_WARM_AMP
				var c: Color
				if autumn:
					# Jesień: cieplejszy rozrzut (R w górę przy dodatnim wv, B w dół) — bursztyn/miedź.
					c = Color(
						clampf(base_col.r + lv + maxf(wv, 0.0), 0.0, 1.0),
						clampf(base_col.g + lv,                 0.0, 1.0),
						clampf(base_col.b + lv - maxf(wv, 0.0), 0.0, 1.0),
						0.0)
				else:
					# Zieleń: jasność ± oraz cieplej/chłodniej (R↑/B↓ vs R↓/B↑).
					c = Color(
						clampf(base_col.r + lv + wv, 0.0, 1.0),
						clampf(base_col.g + lv,      0.0, 1.0),
						clampf(base_col.b + lv - wv, 0.0, 1.0),
						0.0)   # A=0 nominalnie; emit_to_static i tak wymusza A=0 (liście bez sway)
				d.set_voxel(Vector3i(sx, sy, sz), c)
				placed += 1
	if placed == 0:
		return 0
	# Osadzenie: dolny-lewy róg klastra == pozycja voxela liścia w metrach (BEZ recentrowania!).
	# Bok sub-voxela = VOXEL_SIZE/sub => klaster dokładnie wypełnia sześcian voxela liścia.
	# emit_to_static robi culling skorupy klastra + CW winding (NIE pełne 6·sub³ ścian) i A=0.
	var origin := Vector3(x, y, z) * VOXEL_SIZE
	return VoxelModel.emit_to_static(st, d, origin, VOXEL_SIZE / float(sub))


# ============================================================================
#  ZGRUBNY MESH (LOD FAR, step=LOD_FAR_STEP) + SKIRTS — Faza 2B
#  OFF-THREAD (czysty ArrayMesh, zero operacji na drzewie). BEZ wody/propów/kolizji.
#  Czyta WYŁĄCZNIE world.surface_height / world.biome_factor (niemutowane szumy) i własne
#  pola — identyczny kontrakt thread-safety jak _build_mesh. NIE alokuje _voxels (~98k B
#  oszczędności/chunk) ani nie stawia featurów => podniesienie far_dist jest realnie tanie.
# ============================================================================

## Buduje zgrubną powierzchnię: próbkuje surface_height co 'step' voxeli (16×16 komórek dla
## step=2). Na komórkę emituje: górny quad (top) na wierzchu próbkowanej kolumny + boczne
## ściany schodzące do wysokości próbkowanego SĄSIADA (face culling między kolumnami => brak
## dziur WEWNĄTRZ chunku). Szwy MIĘDZY chunkami (LOD↔LOD, LOD↔NEAR) zakrywają skirty (4 krawędzie).
func _build_coarse(world: VoxelWorld) -> void:
	var step := _lod_step
	var cells := CHUNK_SIZE / step                  # 32/2 = 16 kolumn na bok
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Cache próbkowanej heightmapy (w VOXELACH) — indeks: cx + cells*cz. Próbka w ROGU komórki
	# (lx = cx*step), z GLOBALNYCH wx,wz => szwy zgrubnych chunków siadają na tych samych
	# kolumnach świata co voxele NEAR (ta sama funkcja surface_height) => spójna sylwetka.
	var hm := PackedInt32Array()
	hm.resize(cells * cells)
	for cx in cells:
		for cz in cells:
			var wx := _coord.x * CHUNK_SIZE + cx * step
			var wz := _coord.y * CHUNK_SIZE + cz * step
			hm[cx + cells * cz] = world.surface_height(wx, wz)

	var emitted := 0
	for cx in cells:
		for cz in cells:
			var sy := hm[cx + cells * cz]
			var lx := cx * step                       # lokalny voxel-x lewego dolnego rogu komórki
			var lz := cz * step
			var t := _block_for(sy, sy)               # typ powierzchni (GRASS/SAND/ROCK/SNOW)
			# Kolor liczony w ŚRODKU komórki (stabilny). _solid_color bierze LOKALNE x,y,z
			# i sam dolicza wx/wz + gradient trawy po y => ta sama paleta co NEAR (płynne wtopienie).
			var col := _solid_color(world, t, lx + step / 2, sy, lz + step / 2)

			# 1) TOP — górna ściana komórki step×step na wierzchu kolumny.
			_emit_coarse_top(st, lx, sy, lz, step, col)

			# 2) BOKI WEWNĘTRZNE — schodzą do wysokości próbkowanego sąsiada (z cache). Bok tylko gdy
			#    niżej. KIERUNKI WYCHODZĄCE POZA CHUNK SĄ POMINIĘTE (review #minor Z-FIGHT): na granicy
			#    chunku ścianę „bok-do-sąsiada” i tak emituje SKIRT (głębszy, bezstanowy). Gdybyśmy
			#    emitowali tu też _emit_coarse_side w stronę na-zewnątrz, leżałby w tej samej płaszczyźnie
			#    co skirt na tej krawędzi (face 0/1/4/5) i na wysokości [nh..sy] pokrywałby się z nim
			#    => z-fighting na zewnętrznym pierścieniu KAŻDEGO chunku FAR. Skirt sam pokrywa krawędź,
			#    więc wewnątrz emitujemy bok TYLKO ku sąsiadowi LEŻĄCEMU W TYM CHUNKU.
			if cx + 1 < cells:                                               # +X (wewnątrz)
				var nh_px := hm[(cx + 1) + cells * cz]
				if nh_px < sy: _emit_coarse_side(st, lx, lz, sy, nh_px, step, 0, col)
			if cx - 1 >= 0:                                                  # -X (wewnątrz)
				var nh_mx := hm[(cx - 1) + cells * cz]
				if nh_mx < sy: _emit_coarse_side(st, lx, lz, sy, nh_mx, step, 1, col)
			if cz + 1 < cells:                                              # +Z (wewnątrz)
				var nh_pz := hm[cx + cells * (cz + 1)]
				if nh_pz < sy: _emit_coarse_side(st, lx, lz, sy, nh_pz, step, 4, col)
			if cz - 1 >= 0:                                                 # -Z (wewnątrz)
				var nh_mz := hm[cx + cells * (cz - 1)]
				if nh_mz < sy: _emit_coarse_side(st, lx, lz, sy, nh_mz, step, 5, col)

			emitted += 1

	# 3) SKIRTY na 4 krawędziach chunku (zakrywają szwy LOD↔LOD i LOD↔NEAR).
	_emit_coarse_skirts(world, st, hm, cells, step)

	_has_solid = emitted > 0
	if _has_solid:
		_r_solid_mesh = st.commit()
	# _r_water_mesh / _r_props_mesh / _r_collision_shape pozostają null (FAR ich nie ma).
	# Woda FAR pominięta świadomie: w dali i tak rozpływa się w mgle (cz. 3) => mniej draw-calli
	# i zero kosztu DEPTH_TEXTURE wody w dali. Dorzucić dopiero gdyby brzegi jezior w dali raziły.


## Górna ściana zgrubnej komórki (step×step voxeli) na wierzchu kolumny sy. Normalna +Y,
## nawijanie CW od zewnątrz (od góry) — kolejność narożników jak FACE_VERTS[+Y]: p0,p2,p1 / p0,p3,p2.
func _emit_coarse_top(st: SurfaceTool, lx: int, sy: int, lz: int, step: int, col: Color) -> void:
	var x0 := float(lx) * VOXEL_SIZE
	var x1 := float(lx + step) * VOXEL_SIZE
	var z0 := float(lz) * VOXEL_SIZE
	var z1 := float(lz + step) * VOXEL_SIZE
	var y := float(sy + 1) * VOXEL_SIZE          # wierzch bloku powierzchni (= height_at)
	var p0 := Vector3(x0, y, z1)
	var p1 := Vector3(x1, y, z1)
	var p2 := Vector3(x1, y, z0)
	var p3 := Vector3(x0, y, z0)
	st.set_normal(Vector3(0, 1, 0))
	st.set_color(col); st.add_vertex(p0)
	st.set_color(col); st.add_vertex(p2)
	st.set_color(col); st.add_vertex(p1)
	st.set_color(col); st.add_vertex(p0)
	st.set_color(col); st.add_vertex(p3)
	st.set_color(col); st.add_vertex(p2)


## Boczna ściana zgrubnej komórki: prostokąt step (szerokość) × (sy-nh) (wysokość) na danej
## krawędzi. face: 0=+X,1=-X,4=+Z,5=-Z (spójne z FACE_NORMALS). Nawijanie CW od zewnątrz.
## Lekkie przyciemnienie boków (col.darkened) = tania pseudo-bryłowość spójna z AO terenu NEAR.
func _emit_coarse_side(st: SurfaceTool, lx: int, lz: int, sy: int, nh: int, step: int, face: int, col: Color) -> void:
	var x0 := float(lx) * VOXEL_SIZE
	var x1 := float(lx + step) * VOXEL_SIZE
	var z0 := float(lz) * VOXEL_SIZE
	var z1 := float(lz + step) * VOXEL_SIZE
	var y_top := float(sy + 1) * VOXEL_SIZE        # wierzch naszej kolumny
	var y_bot := float(nh + 1) * VOXEL_SIZE        # wierzch sąsiada (gdzie ściana się kończy)
	var n: Vector3 = FACE_NORMALS[face]
	var side_col := col.darkened(0.06)
	var a: Vector3
	var b: Vector3
	var c: Vector3
	var d: Vector3
	match face:
		0:   # +X: ściana w x1, patrzymy w +X.
			a = Vector3(x1, y_bot, z0); b = Vector3(x1, y_top, z0)
			c = Vector3(x1, y_top, z1); d = Vector3(x1, y_bot, z1)
		1:   # -X: ściana w x0, patrzymy w -X.
			a = Vector3(x0, y_bot, z1); b = Vector3(x0, y_top, z1)
			c = Vector3(x0, y_top, z0); d = Vector3(x0, y_bot, z0)
		4:   # +Z: ściana w z1, patrzymy w +Z.
			a = Vector3(x1, y_bot, z1); b = Vector3(x1, y_top, z1)
			c = Vector3(x0, y_top, z1); d = Vector3(x0, y_bot, z1)
		_:   # 5 / -Z: ściana w z0, patrzymy w -Z.
			a = Vector3(x0, y_bot, z0); b = Vector3(x0, y_top, z0)
			c = Vector3(x1, y_top, z0); d = Vector3(x1, y_bot, z0)
	st.set_normal(n)
	# Quad a,b,c,d (CCW geometrycznie wokół ściany) -> trójkąty CW od zewnątrz: a,c,b / a,d,c.
	st.set_color(side_col); st.add_vertex(a)
	st.set_color(side_col); st.add_vertex(c)
	st.set_color(side_col); st.add_vertex(b)
	st.set_color(side_col); st.add_vertex(a)
	st.set_color(side_col); st.add_vertex(d)
	st.set_color(side_col); st.add_vertex(c)


## SKIRTY: pionowe kurtyny w dół wzdłuż 4 krawędzi zgrubnego chunku. Zakrywają pęknięcia
## między tym chunkiem (FAR) a sąsiadem o INNEJ próbie (FAR↔NEAR) lub innej perturbacji (FAR↔FAR).
## BEZSTANOWE: NIE pytamy o LOD sąsiada (to wymagałoby współdzielonego, mutowalnego stanu między
## chunkami => data race z wątkowaniem 2A) — robimy skirt na KAŻDEJ krawędzi. Głębokość SKIRT_DEPTH
## voxeli (12 = 6 m) z zapasem pokrywa różnicę wysokości na szwie. Tanio: 4×cells = 64 quady/chunk FAR.
func _emit_coarse_skirts(world: VoxelWorld, st: SurfaceTool, hm: PackedInt32Array, cells: int, step: int) -> void:
	for c in cells:
		_emit_skirt_segment(world, st, hm, cells, step, 0, c, 1)            # krawędź -X
		_emit_skirt_segment(world, st, hm, cells, step, cells - 1, c, 0)    # krawędź +X
		_emit_skirt_segment(world, st, hm, cells, step, c, 0, 5)            # krawędź -Z
		_emit_skirt_segment(world, st, hm, cells, step, c, cells - 1, 4)    # krawędź +Z


## Jeden segment skirta dla komórki krawędziowej (cx,cz), patrzący w stronę 'face'.
## Re-używa _emit_coarse_side: "sąsiad" = sy_edge - SKIRT_DEPTH (sztuczne dno kurtyny), więc ściana
## powstaje ZAWSZE (nh < sy_edge) i schodzi pełne SKIRT_DEPTH niezależnie od tego, co jest za szwem.
##
## BLOCKER FIX (seam hole na +X/+Z): górę kurtyny liczymy z PRAWDZIWEJ wysokości powierzchni na
## PŁASZCZYŹNIE SZWU (kolumna na granicy chunku), a NIE z próbki komórki cofniętej o 'step' voxeli
## do środka. _build_coarse próbkuje wysokość w DOLNYM ROGU komórki (wx=...+cx*step). Dla krawędzi
## +X (cx=cells-1) i +Z (cz=cells-1) ta próbka leży 'step' voxeli DO ŚRODKA, więc gdy teren rośnie
## na zewnątrz (łagodny stok), prawdziwa wysokość na szwie H(boundary) > H(boundary-step). Sąsiad
## renderuje powierzchnię do H(boundary), a kurtyna brana z H(boundary-step) kończyłaby się NIŻEJ
## => pozioma szczelina U GÓRY kurtyny (zwiększanie SKIRT_DEPTH NIE pomaga — brakuje na górze, nie
## na dole). Dlatego sy_edge = MAX(próbka, surface_height na granicy po całej szerokości 'step').
## Krawędzie -X (cx=0) i -Z (cz=0) próbkują DOKŁADNIE na płaszczyźnie szwu => sy_edge==sy (no-op).
func _emit_skirt_segment(world: VoxelWorld, st: SurfaceTool, hm: PackedInt32Array, cells: int, step: int, cx: int, cz: int, face: int) -> void:
	var sy := hm[cx + cells * cz]
	var lx := cx * step
	var lz := cz * step
	# Prawdziwa wysokość na płaszczyźnie szwu (kolumna graniczna), MAX po szerokości 'step' voxeli.
	var sy_edge := sy
	var base_wx := _coord.x * CHUNK_SIZE
	var base_wz := _coord.y * CHUNK_SIZE
	match face:
		0:   # +X: granica world_x=(_coord.x+1)*CHUNK_SIZE, span po z
			for dz in step:
				sy_edge = maxi(sy_edge, world.surface_height(base_wx + CHUNK_SIZE, base_wz + lz + dz))
		4:   # +Z: granica world_z=(_coord.y+1)*CHUNK_SIZE, span po x
			for dx in step:
				sy_edge = maxi(sy_edge, world.surface_height(base_wx + lx + dx, base_wz + CHUNK_SIZE))
		# face 1 (-X) i 5 (-Z): próbka komórki JUŻ leży na szwie => sy_edge==sy (bez dodatkowych lookupów).
	var t := _block_for(sy_edge, sy_edge)
	var col := _solid_color(world, t, lx + step / 2, sy_edge, lz + step / 2).darkened(0.10)
	var nh := sy_edge - SKIRT_DEPTH
	_emit_coarse_side(st, lx, lz, sy_edge, nh, step, face, col)


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
