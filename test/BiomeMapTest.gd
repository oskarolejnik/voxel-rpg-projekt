extends SceneTree
## WORLDGEN P5 verifier (headless): sampluje get_biome + surface_height po siatce, by POTWIERDZIĆ
## że biomy są PRZESTRZENNYMI REGIONAMI (nie koncentrycznymi pierścieniami) i że teren jest CIĄGŁY
## (brak klifów/„murów" na granicach biomów). Uruchom: godot --headless --script test/BiomeMapTest.gd

func _init() -> void:
	var w := VoxelWorld.new()
	w.world_seed = 1337
	w._setup_noise()

	# Kalibracja: zmierz ROZKŁAD _region_noise (z warpem) na siatce — by dobrać SPATIAL_RANGE pod realną amplitudę.
	var rmin := 9.0
	var rmax := -9.0
	var rsum := 0.0
	var rsum2 := 0.0
	var rn := 0
	for gz in range(-6000, 6001, 150):
		for gx in range(-6000, 6001, 150):
			var wx := w._warp_noise.get_noise_2d(gx, gz) * w.WARP_AMP
			var wz := w._warp_noise.get_noise_2d(gx + 1000.0, gz - 1000.0) * w.WARP_AMP
			var r := w._region_noise.get_noise_2d(gx + wx, gz + wz)
			rmin = minf(rmin, r); rmax = maxf(rmax, r); rsum += r; rsum2 += r * r; rn += 1
	var rmean := rsum / rn
	var rstd := sqrt(rsum2 / rn - rmean * rmean)
	print("=== region_noise dist: min=%.3f max=%.3f mean=%.3f std=%.3f (n=%d)" % [rmin, rmax, rmean, rstd, rn])

	var EXTENT := 4800
	var STEP := 200
	var chars := {
		&"verdant": "F", &"plains": ".", &"swamp": "s", &"mountains": "^",
		&"emberwaste": "d", &"frosthelm": "*", &"volcanic": "V",
	}
	print("=== BIOME MAP  seed=1337  cell=%dm  center=spawn  (F las . rowniny s bagno ^ gory d pustynia * snieg V wulkan) ===" % STEP)
	var counts := {}
	for gz in range(-EXTENT, EXTENT + 1, STEP):
		var line := ""
		for gx in range(-EXTENT, EXTENT + 1, STEP):
			var b: StringName = w.get_biome(gx, gz)
			line += chars.get(b, "?")
			counts[b] = int(counts.get(b, 0)) + 1
		print(line)
	print("=== counts: ", counts)
	print("=== spawn(0,0)=", w.get_biome(0, 0), "  +400m=", w.get_biome(400, 0), "  +800m=", w.get_biome(800, 0))

	# CIĄGŁOŚĆ terenu: max |Δsurface_y| między sąsiednimi próbkami (krok 4) po WIELU transektach (x i z,
	# różne offsety) — globalny worst-case. Klif (swap profilu na granicy biomu) => duży skok; naturalne
	# strome stoki gór bywają ~30-40 vox/4u, ale skok >>50 = podejrzany „mur".
	# Mierzymy per-1-jednostka (nie krok 4) — realny próg ściany. Histogram + percentyle.
	var maxd := 0
	var maxx := 0
	var maxz := 0
	var n20 := 0
	var n30 := 0
	var n40 := 0
	var ntot := 0
	var TR := 6000
	for off in range(-5000, 5001, 250):
		var py := w.surface_height(-TR, off)
		for gx in range(-TR + 1, TR):
			var cy := w.surface_height(gx, off)
			var dlt := absi(cy - py)
			ntot += 1
			if dlt >= 20: n20 += 1
			if dlt >= 30: n30 += 1
			if dlt >= 40: n40 += 1
			if dlt > maxd:
				maxd = dlt; maxx = gx; maxz = off
			py = cy
	print("=== continuity (41 transektow x, krok 1u): max=%d vox @ (%d,%d)" % [maxd, maxx, maxz])
	print("=== sciany/1u: >=20vox: %d (%.3f%%)  >=30: %d (%.4f%%)  >=40: %d  z %d probek" % [n20, 100.0*n20/ntot, n30, 100.0*n30/ntot, n40, ntot])

	# Sweep dystansowy (+x): potwierdz, ze wysokie biomy POJAWIAJA sie dalej (trend trudnosci dziala).
	var seen := {}
	for km in range(0, 32, 1):
		var b: StringName = w.get_biome(km * 1000, 0)
		if not seen.has(b):
			seen[b] = km
	print("=== first-seen biome by distance (+x, km): ", seen)
	quit()
