class_name VoxelModel
extends RefCounted
## VoxelModel.gd — mesher DETALICZNYCH modeli z malutkich voxeli (styl Cube World).
##
## Jeden plik z dwoma trybami emisji TEGO SAMEGO meshera:
##   A) emit_to(st, def, origin, voxel_size)  — dopisuje geometrię do istniejącego
##      SurfaceTool (PROPY: jeden PropsMesh/chunk, 1 draw call, sway w COLOR.a),
##   B) build_mesh(def, voxel_size, offset)    — buduje standalone ArrayMesh
##      (POSTAĆ: zastępuje ~17 BoxMesh; bez sway).
##
## KLUCZOWA DECYZJA: face culling robimy względem WŁASNYCH voxeli modelu (czy sąsiedni
## voxel w Dictionary jest pusty), dokładnie jak teren patrzy na sąsiada w
## VoxelChunk._is_face_visible. Eliminuje to wszystkie ściany WEWNĘTRZNE — model emituje
## tylko zewnętrzną skorupę (pełny sześcian N³ voxeli daje 6N² ścian zamiast 6N³).
##
## Stałe winding/normalne kopiujemy LOKALNIE z Chunk.gd (nie `const X = VoxelChunk.FACE_VERTS`
## — to ryzyko „Could not resolve class", o którym ostrzega VoxelWorld.gd). Nawijanie CW
## od zewnątrz, bit-w-bit zgodne z _emit_cube/_emit_face, więc nic nie wpada pod culling BACK
## (props_material i terrain.gdshader oba renderują cull_back).

# Domyślny bok mikro-voxela: 1/8 voxela terenu. Teren 0,5 m vs detal 0,0625 m = 8× drobniej
# => kontrast skali Cube World. UWAGA: MICRO to tylko FALLBACK domyślnego argumentu emit_to/
# build_mesh — KANONICZNA wartość propów żyje w Chunk.MV (Chunk zawsze podaje MV jawnie),
# a postać podaje Player.VS. Trzymamy literał, żeby nie tworzyć fałszywej zależności.
const MICRO: float = 0.0625                       # 0,0625 m — domyślny (fallback) bok mikro-voxela

# 6 kierunków sąsiadów dla face cullingu (kolejność: +X,-X,+Y,-Y,+Z,-Z).
# Kolejność MUSI indeksować się 1:1 z FACE_VERTS (culling wybiera ścianę po tym samym fi).
const NEIGHBORS: Array[Vector3i] = [
	Vector3i( 1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i( 0, 1, 0), Vector3i( 0,-1, 0),
	Vector3i( 0, 0, 1), Vector3i( 0, 0,-1),
]

# Cztery narożniki każdej z 6 ścian jednostkowego sześcianu (0..1), CCW patrząc OD ZEWNĄTRZ.
# IDENTYCZNE z VoxelChunk.FACE_VERTS (linie 98-111).
const FACE_VERTS: Array = [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],   # +X
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],   # -X
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],   # +Y
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],   # -Y
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],   # +Z
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],   # -Z
]

# Stała normalna per ściana (twarde, płaskie krawędzie voxela — ostre i tanie).
const FACE_NORMALS: Array[Vector3] = [
	Vector3( 1, 0, 0), Vector3(-1, 0, 0),
	Vector3( 0, 1, 0), Vector3( 0,-1, 0),
	Vector3( 0, 0, 1), Vector3( 0, 0,-1),
]


## Definicja modelu = siatka zajętych voxeli (lokalne współrzędne całkowite) -> kolor.
## Klucz Vector3i jest jednocześnie kluczem cullingu (sąsiad = klucz +/- oś).
## Wybór Dictionary (nie Packed*): modele są małe, a O(1) lookup sąsiada to serce cullingu.
class VoxelDef extends RefCounted:
	var cells: Dictionary = {}            # Vector3i -> Color (albedo, sRGB jak w Blocks)
	var sway: Dictionary = {}             # Vector3i -> float (0..1) — OPCJONALNE, tylko propy

	## Wstawia voxel (nadpisuje istniejący). sway_w!=0 zapisuje wagę kołysania.
	func set_voxel(p: Vector3i, col: Color, sway_w: float = 0.0) -> void:
		cells[p] = col
		if sway_w != 0.0:
			sway[p] = sway_w

	## Czy w komórce jest voxel (pusto = brak klucza => rysuj ścianę).
	func is_filled(p: Vector3i) -> bool:
		return cells.has(p)

	## Waga sway w komórce (0 gdy brak).
	func sway_at(p: Vector3i) -> float:
		return sway.get(p, 0.0)

	## Wypełnia prostopadłościan [fr, to) (to wyłączne) kolorem. Wygodny helper do rzeźbienia.
	func fill_box(fr: Vector3i, to: Vector3i, col: Color, sway_w: float = 0.0) -> void:
		for x in range(fr.x, to.x):
			for y in range(fr.y, to.y):
				for z in range(fr.z, to.z):
					set_voxel(Vector3i(x, y, z), col, sway_w)

	## Czy model jest pusty.
	func is_empty() -> bool:
		return cells.is_empty()


## Rdzeń: dla każdego voxela, dla każdej z 6 ścian — rysuj TYLKO gdy sąsiad pusty.
## st         — docelowy SurfaceTool (PRIMITIVE_TRIANGLES, już begun)
## def        — VoxelDef (cells + sway)
## voxel_size — bok mikro-voxela w metrach (np. 0.0625)
## offset     — przesunięcie modelu w metrach (lokalne w chunku / w węźle postaci)
## use_sway   — true: COLOR.a = def.sway_at(p); false: COLOR.a = 0
## Zwraca liczbę wyemitowanych ścian (diagnostyka budżetu tri).
static func _emit(st: SurfaceTool, def: VoxelDef, voxel_size: float,
		offset: Vector3, use_sway: bool) -> int:
	var faces := 0
	for p: Vector3i in def.cells:
		var base_col: Color = def.cells[p]
		var sway_w := def.sway_at(p) if use_sway else 0.0
		# Kolor wierzchołka: RGB=albedo, A=sway (DOKŁADNIE jak _emit_cube linia 436).
		var c := Color(base_col.r, base_col.g, base_col.b, sway_w)
		var origin := offset + Vector3(p.x, p.y, p.z) * voxel_size
		for fi in 6:
			# FACE CULLING WEWNĘTRZNY: sąsiad zajęty => ściana niewidoczna, pomiń.
			if def.is_filled(p + NEIGHBORS[fi]):
				continue
			var corners: Array = FACE_VERTS[fi]
			var p0 := origin + (corners[0] as Vector3) * voxel_size
			var p1 := origin + (corners[1] as Vector3) * voxel_size
			var p2 := origin + (corners[2] as Vector3) * voxel_size
			var p3 := origin + (corners[3] as Vector3) * voxel_size
			st.set_normal(FACE_NORMALS[fi])
			# CW od zewnątrz: tri1 = p0,p2,p1 | tri2 = p0,p3,p2 (jak _emit_cube/_emit_face).
			st.set_color(c); st.add_vertex(p0)
			st.set_color(c); st.add_vertex(p2)
			st.set_color(c); st.add_vertex(p1)
			st.set_color(c); st.add_vertex(p0)
			st.set_color(c); st.add_vertex(p3)
			st.set_color(c); st.add_vertex(p2)
			faces += 1
	return faces


# --- TRYB A: PROPY — emit do współdzielonego PropsMesh (sway aktywne) ---
## Woła _build_* w Chunk.gd przez _emit_model. 'origin' to DOWOLNY offset metrowy —
## w praktyce Chunk._emit_model podaje offset wyliczony z bbox-centrowania XZ (NIE prosty
## dolny-lewy róg), żeby model trafiał w środek kafla. Sway-faza pozostaje stabilna, bo
## props.gdshader liczy fazę wiatru z POZYCJI ŚWIATOWEJ wierzchołka (MODEL_MATRIX*VERTEX),
## a nie z wartości tego offsetu — geometria emituje się tu po prostu jako origin+p*size.
static func emit_to(st: SurfaceTool, def: VoxelDef, origin: Vector3,
		voxel_size: float = MICRO) -> int:
	return _emit(st, def, voxel_size, origin, true)   # use_sway = true


# --- TRYB B: POSTAĆ — standalone ArrayMesh (bez sway) ---
## Zwraca gotowy ArrayMesh do MeshInstance3D.mesh. Materiał ustawia woła­jący
## (StandardMaterial3D z vertex_color_use_as_albedo — patrz Player._make_char_material).
## Normalne ustawiane ręcznie (płaskie, ostre voxele) — NIE wołamy generate_normals.
static func build_mesh(def: VoxelDef, voxel_size: float = 0.09,
		offset: Vector3 = Vector3.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if def == null or def.is_empty():
		return st.commit()   # pusty ArrayMesh (bezpieczny dla MeshInstance3D)
	_emit(st, def, voxel_size, offset, false)         # use_sway = false (A=0)
	return st.commit()                                # ArrayMesh, 1 surface
