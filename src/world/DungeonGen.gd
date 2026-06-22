class_name DungeonGen
extends RefCounted
## DungeonGen.gd — DETERMINISTYCZNY generator ukladu dungeonu (ETAP 5, GDD 8 / TDD 7.3).
##
## DWIE warstwy, obie z `entrance_seed` (jedno zrodlo determinizmu):
##   1) LAYOUT (logika): graf pokoi na siatce gridowej (BSP-light: pokoje rozmieszczone w
##      kolumnach wg glebi, polaczone korytarzami) + ZAMEK-KLUCZ. Czysta arytmetyka (ten sam
##      seed -> ten sam uklad: liczba/typy pokoi, pozycja bossa, pozycja klucza). TESTOWALNE
##      headless bez sceny (Etap5Test sprawdza determinizm i spojnosc grafu).
##   2) GEOMETRIA (voxele): build_room_mesh() buduje ArrayMesh + Shape3D pokoju w WATKU
##      (SurfaceTool + ten sam pipeline meshingu co teren/propy — zero zacinania glownego watku;
##      reuse WorkerThreadPool przez DungeonRun). NIE zalezy od FastNoiseLite swiata (instancja
##      efemeryczna, nie chunk trwalego swiata).
##
## Sciezka krytyczna (GDD 8): ENTRANCE -> COMBAT x k -> TREASURE -> COMBAT x m -> MINIBOSS ->
## BOSS, + 1-3 odnogi (SECRET/LOOT/LOCKED). Drzwi do BOSS sa ZABLOKOWANE; KLUCZ lezy na sciezce
## osiagalnej PRZED drzwiami (w MINIBOSS lub TREASURE/SECRET) — gwarancja: pokoj klucza ma
## indeks glebi (depth) < indeks pokoju bossa, a graf jest SPOJNY od wejscia (BFS) => klucz
## zawsze osiagalny zanim trafisz na zamkniete drzwi bossa.
##
## DETERMINIZM (kontrakt Etap 7 co-op): host liczy entrance_seed (z feature_hash chunka), klienci
## generuja TEN SAM uklad lokalnie z samego seeda (nic poza seed+tier po sieci). Uzywamy LOKALNEGO
## RandomNumberGenerator(seed) — NIE globalnych strumieni RNGService (te sa dla loot/combat).

# --- Typy pokoi (rola w grafie). int do latwej serializacji/testu. ---
enum RoomType { ENTRANCE, COMBAT, TREASURE, MINIBOSS, BOSS, SECRET }

# --- Skala geometrii pokoju (w METRACH; spojnie ze swiatem: voxel 0,5 m) ---
const VOXEL_SIZE: float = 0.5
## Rozmiar komorki gridu ukladu w METRACH (rozstaw srodkow pokoi). Pokoj jest mniejszy (margines
## na korytarze). 24 m daje wyrazne, osobne pokoje z laczacymi korytarzami.
const GRID_CELL_M: float = 24.0
## Wymiary pojedynczego pokoju w VOXELACH (podloga; wysokosc osobno). Pokoj ~ 16x16 voxeli = 8x8 m.
const ROOM_W: int = 16
const ROOM_D: int = 16
const ROOM_H: int = 10            # wysokosc w voxelach (5 m) — sufit nad glowa
const WALL_T: int = 1             # grubosc sciany w voxelach
const CORRIDOR_W: int = 4         # szerokosc korytarza w voxelach (2 m)

# --- Parametry ukladu (skalowane tierem dungeonu) ---
## Bazowa liczba pokoi walki na sciezce krytycznej (przed minibossem) — rosnie z tierem.
const BASE_COMBAT_MIN: int = 2
const BASE_COMBAT_MAX: int = 4
## Maks. liczba odnog (SECRET/LOOT) doczepianych do sciezki.
const MAX_BRANCHES: int = 3

# --- Salty (rozlaczne "rzuty" lokalnego RNG; kolejnosc pobran = determinizm) ---
const SALT_COMBAT_COUNT: int = 0x100
const SALT_BRANCH_COUNT: int = 0x200

# Kolory voxeli pokoi wg roli (vertex-color albedo, jak Blocks). Czytelnosc: boss=czerwien.
const COL_FLOOR: Color = Color(0.34, 0.30, 0.36)       # kamienna podloga (chlodny fiolet-szary)
const COL_WALL: Color = Color(0.26, 0.23, 0.28)        # sciana ciemniejsza
const COL_FLOOR_BOSS: Color = Color(0.40, 0.16, 0.16)  # arena bossa — czerwonawa
const COL_FLOOR_TREASURE: Color = Color(0.40, 0.36, 0.18) # skarbiec — zlotawy
const COL_DOOR_LOCKED: Color = Color(0.85, 0.70, 0.18) # rama drzwi bossa (zlota = klucz)


## ====================================================================
##  WARSTWA 1: LAYOUT (czysta logika, deterministyczna, testowalna)
## ====================================================================

## Opis jednego pokoju w ukladzie (czyste dane — Dictionary dla latwej serializacji/testu).
##   id:int, type:int(RoomType), grid:Vector2i (komorka), depth:int (kolumna = odleglosc od wejscia),
##   center:Vector3 (metry, srodek podlogi), is_locked:bool (czy wejscie zablokowane: tylko BOSS).
## Polaczenia trzymamy osobno (edges) jako pary id.

## Generuje pelny uklad dungeonu. Zwraca Dictionary:
##   { seed, tier, rooms: Array[Dictionary], edges: Array[Vector2i], entrance_id, boss_id,
##     key_room_id, loot_tier }
## DETERMINISTYCZNY: ten sam (seed, tier) ZAWSZE ten sam uklad.
static func generate(entrance_seed: int, tier: int = 1) -> Dictionary:
	tier = maxi(1, tier)
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix(entrance_seed, tier)

	var rooms: Array = []
	var edges: Array = []     # Array[Vector2i] (id_a, id_b)

	# --- Sciezka krytyczna: kolumny gridu (depth rosnie wzdluz +X). ---
	# Liczba pokoi walki rosnie z tierem (T1: 2-3, T3: 4-6). Deterministyczna z lokalnego RNG.
	var combat_count := _combat_count(entrance_seed, tier)

	var next_id := 0
	var depth := 0
	var prev_id := -1

	# Helper inline (lambda nie ma — robimy proceduralnie): dodaj pokoj na sciezce krytycznej.
	# ENTRANCE (depth 0)
	var entrance_id := next_id
	rooms.append(_make_room(next_id, RoomType.ENTRANCE, Vector2i(depth, 0), depth, false))
	prev_id = next_id
	next_id += 1
	depth += 1

	# COMBAT x (combat_count/2 zaokraglone w gore) -> TREASURE -> COMBAT (reszta) -> MINIBOSS -> BOSS
	var first_combat := int(ceil(float(combat_count) / 2.0))
	var second_combat := combat_count - first_combat

	for _i in first_combat:
		rooms.append(_make_room(next_id, RoomType.COMBAT, Vector2i(depth, 0), depth, false))
		edges.append(Vector2i(prev_id, next_id))
		prev_id = next_id; next_id += 1; depth += 1

	# TREASURE (skarbiec na sciezce — gwarantowany loot)
	var treasure_id := next_id
	rooms.append(_make_room(next_id, RoomType.TREASURE, Vector2i(depth, 0), depth, false))
	edges.append(Vector2i(prev_id, next_id))
	prev_id = next_id; next_id += 1; depth += 1

	for _i in second_combat:
		rooms.append(_make_room(next_id, RoomType.COMBAT, Vector2i(depth, 0), depth, false))
		edges.append(Vector2i(prev_id, next_id))
		prev_id = next_id; next_id += 1; depth += 1

	# MINIBOSS (przed bossem — tu domyslnie kladziemy KLUCZ)
	var miniboss_id := next_id
	rooms.append(_make_room(next_id, RoomType.MINIBOSS, Vector2i(depth, 0), depth, false))
	edges.append(Vector2i(prev_id, next_id))
	prev_id = next_id; next_id += 1; depth += 1

	# BOSS (drzwi ZABLOKOWANE — wymaga klucza)
	var boss_id := next_id
	rooms.append(_make_room(next_id, RoomType.BOSS, Vector2i(depth, 0), depth, true))
	edges.append(Vector2i(prev_id, next_id))
	next_id += 1
	depth += 1

	# --- Odnogi (SECRET/LOOT): doczepiane do losowych pokoi sciezki PRZED bossem. ---
	var branch_count := _branch_count(entrance_seed, tier)
	# Pokoje-kandydaci na rodzica odnogi: combat/treasure/miniboss (NIE entrance, NIE boss).
	var branch_parents: Array = []
	for r in rooms:
		var rt: int = r["type"]
		if rt == RoomType.COMBAT or rt == RoomType.TREASURE or rt == RoomType.MINIBOSS:
			branch_parents.append(r)
	# Klucz moze wylądowac w SECRET (alternatywa do MINIBOSS). Wybor deterministyczny nizej.
	var secret_ids: Array = []
	for _b in branch_count:
		if branch_parents.is_empty():
			break
		var parent: Dictionary = branch_parents[rng.randi_range(0, branch_parents.size() - 1)]
		var p_grid: Vector2i = parent["grid"]
		# Odnoga w bok (+Z lub -Z) od rodzica; depth = depth rodzica (rownolegle, nie pchamy bossa).
		var side := 1 if rng.randf() < 0.5 else -1
		var b_grid := Vector2i(p_grid.x, p_grid.y + side)
		# Unikaj kolizji komorki (rzadkie). KOLEJNOSC fallbacku wazna (review #minor): NAJPIERW probuj
		# PRZECIWNA strone (-side, komorka SASIADUJACA z rodzicem) — korytarz rodzic<->odnoga (po prostej
		# Z) NIE przejdzie wtedy przez zaden posredni pokoj. Dopiero gdy i ona zajeta, siegamy po +side*2,
		# ale korytarz przez komorke posrednia +side*1 byly defektem geometrii (~11% ukladow), wiec gdy
		# +side*1 jest zajety, odrzucamy +side*2 (continue) — nie produkujemy korytarza-przez-pokoj.
		if _grid_taken(rooms, b_grid):
			var opp := Vector2i(p_grid.x, p_grid.y - side)
			if not _grid_taken(rooms, opp):
				b_grid = opp
			else:
				# Obie sasiadujace strony zajete: +side*2 przebilby sie przez +side*1 -> pomijamy odnoge.
				continue
		if _grid_taken(rooms, b_grid):
			continue
		var b_depth: int = parent["depth"]
		rooms.append(_make_room(next_id, RoomType.SECRET, b_grid, b_depth, false))
		edges.append(Vector2i(int(parent["id"]), next_id))
		secret_ids.append(next_id)
		next_id += 1

	# --- ZAMEK-KLUCZ: wybor pokoju z kluczem. Gwarancja osiagalnosci PRZED drzwiami bossa: ---
	# klucz lezy w pokoju o depth < depth(boss) i osiagalnym od wejscia (graf spojny). Domyslnie
	# MINIBOSS; jesli istnieje SECRET o depth < boss, czasem (deterministycznie) tam — ale ZAWSZE
	# walidujemy depth < boss_depth. To czyni "zagadke" ciekawsza, nie psujac DoD.
	var boss_depth: int = _room_by_id(rooms, boss_id)["depth"]
	var key_room_id := miniboss_id
	if not secret_ids.is_empty() and rng.randf() < 0.5:
		# Wybierz SECRET o depth < boss_depth (zawsze prawda: odnogi maja depth rodzica < boss).
		var cand: Array = []
		for sid in secret_ids:
			if int(_room_by_id(rooms, sid)["depth"]) < boss_depth:
				cand.append(sid)
		if not cand.is_empty():
			key_room_id = int(cand[rng.randi_range(0, cand.size() - 1)])
	# TWARDY bezpiecznik DoD: jesli (teoretycznie) klucz nie przed bossem -> wroc do MINIBOSS.
	if int(_room_by_id(rooms, key_room_id)["depth"]) >= boss_depth:
		key_room_id = miniboss_id

	# Oznacz pokoj klucza (flaga has_key) — DungeonRun spawnuje pickup klucza tam.
	for i in rooms.size():
		if int(rooms[i]["id"]) == key_room_id:
			rooms[i]["has_key"] = true

	# Tier lootu = tier dungeonu (skalowany glebia wejscia w DungeonEntrance). Skarbiec/boss wyzej.
	var loot_tier := tier

	return {
		"seed": entrance_seed,
		"tier": tier,
		"rooms": rooms,
		"edges": edges,
		"entrance_id": entrance_id,
		"boss_id": boss_id,
		"miniboss_id": miniboss_id,
		"treasure_id": treasure_id,
		"key_room_id": key_room_id,
		"loot_tier": loot_tier,
		"combat_count": combat_count,
	}


## Liczba pokoi walki na sciezce krytycznej (deterministyczna, rosnie z tierem). T1: 2-3 / T3: 4-5.
## Twardy cap 6 (review #minor): wczesniej cap'owane bylo TYLKO hi, ale gdy lo>6 (tier>=6)
## randi_range(lo, maxi(lo,hi)) zwracalo lo>6 — invariant "max 6 pokoi walki" byl falszywy
## (tier 6->7, 7->8, 8->9). Cap'ujemy lo i WYNIK, wiec combat_count NIGDY nie przekroczy 6.
static func _combat_count(entrance_seed: int, tier: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix(entrance_seed ^ SALT_COMBAT_COUNT, tier)
	var lo := mini(BASE_COMBAT_MIN + (tier - 1), 6)   # T1:2 T2:3 T3:4 ... cap 6
	var hi := mini(BASE_COMBAT_MAX + (tier - 1), 6)   # cap 6
	return mini(rng.randi_range(lo, maxi(lo, hi)), 6)


static func _branch_count(entrance_seed: int, tier: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix(entrance_seed ^ SALT_BRANCH_COUNT, tier)
	return rng.randi_range(1, MAX_BRANCHES)


## Buduje opis pokoju. center liczony z gridu (metry): grid.x = glebia (oś +X), grid.y = bok (oś +Z).
static func _make_room(id: int, type: int, grid: Vector2i, depth: int, locked: bool) -> Dictionary:
	var center := Vector3(float(grid.x) * GRID_CELL_M, 0.0, float(grid.y) * GRID_CELL_M)
	return {
		"id": id,
		"type": type,
		"grid": grid,
		"depth": depth,
		"center": center,
		"is_locked": locked,
		"has_key": false,
	}


static func _grid_taken(rooms: Array, grid: Vector2i) -> bool:
	for r in rooms:
		if (r["grid"] as Vector2i) == grid:
			return true
	return false


static func _room_by_id(rooms: Array, id: int) -> Dictionary:
	for r in rooms:
		if int(r["id"]) == id:
			return r
	return {}


## Deterministyczny mix seeda z tierem (integerowy, jak feature_hash/region_seed). Maska dodatnia.
static func _mix(s: int, tier: int) -> int:
	var h := s
	h = (h * 73856093) ^ (tier * 19349663)
	h ^= (h >> 13)
	h = h * 1274126177
	h ^= (h >> 16)
	return h & 0x7FFFFFFFFFFFFFFF


## ====================================================================
##  WALIDACJA GRAFU (uzywana w tescie i jako bezpiecznik) — BFS spojnosc
## ====================================================================

## Czy `target_id` jest osiagalny od `start_id` po krawedziach (nieskierowanych). BFS.
static func is_reachable(layout: Dictionary, start_id: int, target_id: int) -> bool:
	if start_id == target_id:
		return true
	var adj := _adjacency(layout)
	var seen := {start_id: true}
	var queue: Array = [start_id]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for nb in adj.get(cur, []):
			if nb == target_id:
				return true
			if not seen.has(nb):
				seen[nb] = true
				queue.append(nb)
	return false


## Lista sasiedztwa id -> Array[int] (graf nieskierowany z edges).
static func _adjacency(layout: Dictionary) -> Dictionary:
	var adj: Dictionary = {}
	for e in layout.get("edges", []):
		var a: int = (e as Vector2i).x
		var b: int = (e as Vector2i).y
		if not adj.has(a): adj[a] = []
		if not adj.has(b): adj[b] = []
		(adj[a] as Array).append(b)
		(adj[b] as Array).append(a)
	return adj


## Czy CALY graf jest spojny od wejscia (kazdy pokoj osiagalny). DoD: boss osiagalny od wejscia.
static func is_connected_from_entrance(layout: Dictionary) -> bool:
	var rooms: Array = layout.get("rooms", [])
	var entrance_id: int = int(layout.get("entrance_id", 0))
	for r in rooms:
		if not is_reachable(layout, entrance_id, int(r["id"])):
			return false
	return true


## ====================================================================
##  WARSTWA 2: GEOMETRIA (voxele pokoju — budowana w WATKU)
## ====================================================================

## Buduje ArrayMesh GEOMETRII jednego pokoju (podloga + 4 sciany + sufit + otwory na drzwi).
## CZYSTA funkcja (SurfaceTool lokalny) — bezpieczna off-thread (jak Chunk.build_data). Zwraca
## { mesh: ArrayMesh, shape: Shape3D|null }. shape liczony tu NIE jest (create_trimesh_shape nie
## jest thread-safe — godot#69076); DungeonRun liczy shape z mesha na glownym watku w finalize.
##
## `room_type` steruje kolorem podlogi (boss czerwony / skarbiec zlotawy). `door_dirs` to maska
## kierunkow z otworami na drzwi (bity: 0=+X,1=-X,2=+Z,3=-Z) — korytarze laczą pokoje przez te otwory.
static func build_room_mesh(room_type: int, door_dirs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var floor_col := COL_FLOOR
	if room_type == RoomType.BOSS:
		floor_col = COL_FLOOR_BOSS
	elif room_type == RoomType.TREASURE:
		floor_col = COL_FLOOR_TREASURE

	var w := ROOM_W
	var d := ROOM_D
	var h := ROOM_H
	# Otwor drzwi: srodkowe CORRIDOR_W voxeli sciany, od podlogi do polowy wysokosci.
	var door_lo := (w - CORRIDOR_W) / 2
	var door_hi := door_lo + CORRIDOR_W
	var door_h := h / 2 + 1            # wysokosc otworu (voxele)

	# --- Podloga (y=0): pelny prostokat ROOM_W x ROOM_D quadow (top +Y) ---
	for x in w:
		for z in d:
			_emit_box_top(st, x, 0, z, floor_col)

	# --- Sufit (y=h): zamkniecie od gory (top, normalna -Y od spodu widoczna) ---
	for x in w:
		for z in d:
			_emit_ceiling(st, x, h, z, COL_WALL.darkened(0.10))

	# --- Sciany: 4 boki, wysokosc h, z otworami na drzwi wg door_dirs ---
	# +X (x = w-1, face normalna +X), otwor gdy bit0
	_emit_wall_x(st, w, h, true, (door_dirs & 1) != 0, door_lo, door_hi, door_h)
	# -X (x = 0), otwor gdy bit1
	_emit_wall_x(st, w, h, false, (door_dirs & 2) != 0, door_lo, door_hi, door_h)
	# +Z (z = d-1), otwor gdy bit2
	_emit_wall_z(st, d, h, true, (door_dirs & 4) != 0, door_lo, door_hi, door_h)
	# -Z (z = 0), otwor gdy bit3
	_emit_wall_z(st, d, h, false, (door_dirs & 8) != 0, door_lo, door_hi, door_h)

	return st.commit()


## Buduje ArrayMesh KORYTARZA laczacego dwa pokoje (prosty tunel po prostej miedzy srodkami).
## Korytarz to "rura" CORRIDOR_W szeroka, z podloga i scianami, lezaca w przestrzeni MIEDZY
## pokojami. Pozycje liczone w metrach (lokalne wzgledem origin korytarza = srodek miedzy pokojami).
## a_center/b_center w metrach (swiat dungeonu). Zwraca ArrayMesh (podloga + sciany boczne + sufit).
static func build_corridor_mesh(a_center: Vector3, b_center: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := COL_FLOOR.darkened(0.05)
	var wall := COL_WALL
	var half := float(CORRIDOR_W) * VOXEL_SIZE * 0.5
	var ch := float(ROOM_H) * VOXEL_SIZE      # wysokosc korytarza = wysokosc pokoju
	# Kierunek korytarza (poziomy). Pokoje sa wyrownane na osi X lub Z (grid).
	var dir := b_center - a_center
	dir.y = 0.0
	var length := dir.length()
	if length < 0.01:
		return st.commit()
	dir = dir.normalized()
	# Prostopadly (do szerokosci).
	var perp := Vector3(-dir.z, 0.0, dir.x)
	# Korytarz od krawedzi pokoju A do krawedzi pokoju B (cofamy o pol-pokoju z kazdej strony,
	# zeby tunel nie wnikal gleboko w pokoje). Pol-pokoj liczony z OSI DOMINUJACEJ kierunku korytarza
	# (review #minor): X-osiowy -> ROOM_W, Z-osiowy (odnogi SECRET) -> ROOM_D. Dotad uzywano ROOM_W
	# dla obu osi — dziala tylko bo ROOM_W==ROOM_D; zmiana wymiarow dawalaby krzywe/zachodzace korytarze.
	var room_half := float(ROOM_W if absf(dir.x) >= absf(dir.z) else ROOM_D) * VOXEL_SIZE * 0.5
	var start := a_center + dir * (room_half - VOXEL_SIZE)
	var end := b_center - dir * (room_half - VOXEL_SIZE)
	var seg := end - start
	var seg_len := seg.length()
	if seg_len < 0.01:
		return st.commit()
	# Podloga korytarza (2 trojkaty na caly prostokat seg_len x szerokosc).
	var fl0 := start - perp * half
	var fl1 := start + perp * half
	var fl2 := end + perp * half
	var fl3 := end - perp * half
	_emit_quad(st, fl0, fl1, fl2, fl3, Vector3.UP, col)
	# Sufit.
	var up := Vector3(0.0, ch, 0.0)
	_emit_quad(st, fl3 + up, fl2 + up, fl1 + up, fl0 + up, Vector3.DOWN, wall.darkened(0.10))
	# Dwie sciany boczne (pelna wysokosc).
	_emit_quad(st, fl0, fl0 + up, fl3 + up, fl3, -perp, wall)
	_emit_quad(st, fl1 + up, fl1, fl2, fl2 + up, perp, wall)
	return st.commit()


# --- Pomocniki geometrii voxelowej (lokalne wspolrzedne voxeli pokoju, origin = rog pokoju) ---

## Gorna sciana voxela podlogi (top +Y) w (vx, vy, vz). y = (vy)*VOXEL_SIZE (podloga na y=0 ma top=0?).
## Podloga: top na wierzchu bloku y=0 -> y_top = (vy+1)*VOXEL_SIZE? Trzymamy podloge na poziomie 0:
## emitujemy quad na y=0 (po wierzchu bloku podlogi). Prosto: top podlogi = vy*VOXEL_SIZE z vy=... .
## Tu vy to indeks; podloga ma top na y=0.0 dla vy=0 (gracz stoi na 0).
static func _emit_box_top(st: SurfaceTool, vx: int, vy: int, vz: int, col: Color) -> void:
	var s := VOXEL_SIZE
	var x0 := float(vx) * s
	var x1 := float(vx + 1) * s
	var z0 := float(vz) * s
	var z1 := float(vz + 1) * s
	var y := float(vy) * s
	_emit_quad(st,
		Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), Vector3(x0, y, z0),
		Vector3.UP, col)


## Sufit (quad patrzacy w dol, -Y) na wysokosci vy.
static func _emit_ceiling(st: SurfaceTool, vx: int, vy: int, vz: int, col: Color) -> void:
	var s := VOXEL_SIZE
	var x0 := float(vx) * s
	var x1 := float(vx + 1) * s
	var z0 := float(vz) * s
	var z1 := float(vz + 1) * s
	var y := float(vy) * s
	_emit_quad(st,
		Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1),
		Vector3.DOWN, col)


## Sciana wzdluz osi Z (na granicy X). plus_x=true -> sciana na x=w (face +X), inaczej x=0 (face -X).
## door=true wycina otwor: voxele z w [door_lo, door_hi) i y < door_h pomijane.
static func _emit_wall_x(st: SurfaceTool, w: int, h: int, plus_x: bool, door: bool,
		door_lo: int, door_hi: int, door_h: int) -> void:
	var s := VOXEL_SIZE
	var d := ROOM_D
	var xface := float(w) * s if plus_x else 0.0
	var n := Vector3(1, 0, 0) if plus_x else Vector3(-1, 0, 0)
	var col := COL_WALL
	for z in d:
		for y in h:
			if door and z >= door_lo and z < door_hi and y < door_h:
				continue
			var z0 := float(z) * s
			var z1 := float(z + 1) * s
			var y0 := float(y) * s
			var y1 := float(y + 1) * s
			if plus_x:
				_emit_quad(st,
					Vector3(xface, y0, z0), Vector3(xface, y1, z0),
					Vector3(xface, y1, z1), Vector3(xface, y0, z1), n, col)
			else:
				_emit_quad(st,
					Vector3(xface, y0, z1), Vector3(xface, y1, z1),
					Vector3(xface, y1, z0), Vector3(xface, y0, z0), n, col)


## Sciana wzdluz osi X (na granicy Z). plus_z=true -> z=d (face +Z), inaczej z=0 (face -Z).
static func _emit_wall_z(st: SurfaceTool, d: int, h: int, plus_z: bool, door: bool,
		door_lo: int, door_hi: int, door_h: int) -> void:
	var s := VOXEL_SIZE
	var w := ROOM_W
	var zface := float(d) * s if plus_z else 0.0
	var n := Vector3(0, 0, 1) if plus_z else Vector3(0, 0, -1)
	var col := COL_WALL
	for x in w:
		for y in h:
			if door and x >= door_lo and x < door_hi and y < door_h:
				continue
			var x0 := float(x) * s
			var x1 := float(x + 1) * s
			var y0 := float(y) * s
			var y1 := float(y + 1) * s
			if plus_z:
				_emit_quad(st,
					Vector3(x1, y0, zface), Vector3(x1, y1, zface),
					Vector3(x0, y1, zface), Vector3(x0, y0, zface), n, col)
			else:
				_emit_quad(st,
					Vector3(x0, y0, zface), Vector3(x0, y1, zface),
					Vector3(x1, y1, zface), Vector3(x1, y0, zface), n, col)


## Emisja jednego quada (4 wierzcholki CCW od strony normalnej) jako 2 trojkaty. Nawijanie
## p0,p2,p1 / p0,p3,p2 (CW od zewnatrz — spojne z terenem/VoxelModel).
static func _emit_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		n: Vector3, col: Color) -> void:
	st.set_normal(n)
	st.set_color(col); st.add_vertex(p0)
	st.set_color(col); st.add_vertex(p2)
	st.set_color(col); st.add_vertex(p1)
	st.set_color(col); st.add_vertex(p0)
	st.set_color(col); st.add_vertex(p3)
	st.set_color(col); st.add_vertex(p2)
