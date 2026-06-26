extends Node
## WorldSeedTest.gd — BUGFIX „ciągle ten sam świat": różny world_seed => RÓŻNY teren/biom/jaskinie;
## ten sam world_seed => IDENTYCZNY teren (determinizm zachowany, co-op-safe).
## Uruchomienie: godot --headless res://test/WorldSeedTest.tscn

var _failures: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[SEED] FAIL: %s" % msg)


func _ready() -> void:
	print("[SEED] === world seed test ===")
	# world_seed USTAWIONY PRZED add_child => _ready/_setup_noise użyje go.
	var a := VoxelWorld.new(); a.world_seed = 11111; add_child(a)
	var b := VoxelWorld.new(); b.world_seed = 99999; add_child(b)
	var c := VoxelWorld.new(); c.world_seed = 11111; add_child(c)   # ten sam seed co a

	var diff := 0
	var same_ac := 0
	var total := 0
	for x in range(0, 210, 7):
		for z in range(0, 210, 7):
			total += 1
			if a.surface_height(x, z) != b.surface_height(x, z):
				diff += 1
			if a.surface_height(x, z) == c.surface_height(x, z):
				same_ac += 1
	_check(diff > total / 2, "różny seed dał za mało różnic terenu (%d/%d) — seed nie steruje terenem" % [diff, total])
	_check(same_ac == total, "ten sam seed NIE jest deterministyczny (%d/%d zgodne)" % [same_ac, total])

	# UWAGA: get_biome jest DYSTANSOWO-PASMOWE z założenia (progresja trudności: verdant przy spawnie ->
	# volcanic daleko), więc TYP biomu na danym dystansie jest celowo niezależny od seeda — zmienia się
	# tylko WARP granic pasm (z _biome_noise, teraz seedowanego). Nie traktujemy tego jako kryterium
	# „inny świat" (tym jest teren + jaskinie); raportujemy tylko ile granic się przesunęło.
	var biome_diff := 0
	for x in range(0, 4000, 53):
		if a.get_biome(x, 0) != b.get_biome(x, 0):
			biome_diff += 1

	var cave_diff := 0
	for x in range(0, 120):
		var sy := a.surface_height(x, 5)
		if sy > 30:
			if a.is_cave(x, 10, 5, sy) != b.is_cave(x, 10, 5, sy):
				cave_diff += 1
	_check(cave_diff > 0, "jaskinie identyczne mimo różnego seeda")

	a.queue_free(); b.queue_free(); c.queue_free()
	print("[SEED] teren-diff=%d/%d, biom-diff=%d, jaskinie-diff=%d, determinizm=%d/%d" % [diff, total, biome_diff, cave_diff, same_ac, total])
	if _failures == 0:
		print("[SEED] ALL OK")
	else:
		printerr("[SEED] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
