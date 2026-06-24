extends Node
## SpawnValidityTest.gd — QUICK-WIN: POPRAWNE pozycje spawnu (bez wody/klifow).
## Uruchomienie: godot --headless res://test/SpawnValidityTest.tscn
##
## Weryfikuje czysty predykat WorldSpawner.is_valid_spawn_ground(ground_y, slope_delta):
##  (1) grunt PONIZEJ poziomu morza (woda) -> odrzucony.
##  (2) grunt DOKLADNIE na poziomie morza -> odrzucony (brzeg/plaza pod woda).
##  (3) grunt nad woda, plaski (maly slope) -> POPRAWNY.
##  (4) grunt nad woda, ale STROMY (slope > prog) -> odrzucony (klif).
##  (5) grunt nad woda, slope DOKLADNIE na progu -> POPRAWNY (inkluzywny prog).
##  (6) staly poziom morza spojny z VoxelWorld (SEA_LEVEL * VOXEL_SIZE).
## Kod wyjscia: 0 = ALL OK, 1 = FAIL. Print "[SPAWN] ...".

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[SPAWN] FAIL: %s" % msg)


func _ready() -> void:
	print("[SPAWN] === Spawn validity test start ===")
	var sea := WorldSpawner.SEA_LEVEL_METERS
	var slope_ok := 1.0                          # plaski teren (znaczaco ponizej progu klifu)
	var slope_cliff := WorldSpawner.MAX_SLOPE_DELTA + 1.0   # ponad prog klifu

	# (1) pod woda -> odrzucony
	_check(not WorldSpawner.is_valid_spawn_ground(sea - 2.0, slope_ok),
		"grunt pod poziomem morza zaakceptowany (woda)")

	# (2) dokladnie na poziomie morza -> odrzucony (height_at <= sea = woda)
	_check(not WorldSpawner.is_valid_spawn_ground(sea, slope_ok),
		"grunt dokladnie na poziomie morza zaakceptowany")

	# (3) nad woda + plaski -> POPRAWNY
	_check(WorldSpawner.is_valid_spawn_ground(sea + 4.0, slope_ok),
		"plaski grunt nad woda odrzucony (powinien byc poprawny)")

	# (4) nad woda ale klif -> odrzucony
	_check(not WorldSpawner.is_valid_spawn_ground(sea + 4.0, slope_cliff),
		"stromy klif zaakceptowany (slope %.1f > prog %.1f)" % [slope_cliff, WorldSpawner.MAX_SLOPE_DELTA])

	# (5) slope dokladnie na progu -> POPRAWNY (prog inkluzywny: <=)
	_check(WorldSpawner.is_valid_spawn_ground(sea + 4.0, WorldSpawner.MAX_SLOPE_DELTA),
		"slope dokladnie na progu odrzucony (prog powinien byc inkluzywny)")

	# (6) poziom morza spojny ze swiatem
	_check(is_equal_approx(sea, float(VoxelWorld.SEA_LEVEL) * VoxelWorld.VOXEL_SIZE),
		"SEA_LEVEL_METERS niespojny z VoxelWorld (%.2f)" % sea)

	if _failures == 0:
		print("[SPAWN] ALL OK")
	else:
		printerr("[SPAWN] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
