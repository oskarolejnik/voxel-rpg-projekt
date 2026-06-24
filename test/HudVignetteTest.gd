extends Node
## HudVignetteTest.gd — weryfikuje vignette niskiego HP w HUD (_vignette_alpha).
## Uruchomienie: godot --headless res://test/HudVignetteTest.tscn
##
##  (1) Wysokie HP (>= próg) -> alpha = 0 (zero kosztu / brak efektu).
##  (2) Niskie HP (< próg) -> alpha > 0 (efekt aktywny).
##  (3) Niżej HP = mocniej: przy tej samej fazie pulsu alpha rośnie gdy HP maleje.
##  (4) Puls modulowany sinusoidą: faza w „dolinie" daje 0, faza w „szczycie" daje maks.
##  (5) Alpha nigdy nie przekracza VIG_ALPHA_MAX i nie schodzi poniżej 0.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL.

const HUDScript := preload("res://src/HUD.gd")

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[VIG] FAIL: %s" % msg)


func _ready() -> void:
	print("[VIG] === HUD low-HP vignette test ===")
	var hud = HUDScript.new()

	# Szczyt pulsu: sin(PI/2)=1 -> mnożnik 1.0; dolina: sin(-PI/2)=-1 -> mnożnik 0.0.
	var peak := PI * 0.5
	var trough := -PI * 0.5

	# (1) Wysokie HP -> 0 (na progu i powyżej).
	_check(hud._vignette_alpha(1.0, peak) == 0.0, "pełne HP powinno dać alpha 0")
	_check(hud._vignette_alpha(hud.VIG_HP_THRESH, peak) == 0.0, "HP na progu powinno dać alpha 0")
	_check(hud._vignette_alpha(0.30, peak) == 0.0, "HP > próg powinno dać alpha 0")

	# (2) Niskie HP -> > 0.
	var low := hud._vignette_alpha(0.10, peak)
	_check(low > 0.0, "niskie HP powinno dać alpha > 0 (jest %f)" % low)

	# (3) Niżej HP = mocniej (ta sama faza).
	var a_hi := hud._vignette_alpha(0.20, peak)
	var a_lo := hud._vignette_alpha(0.05, peak)
	_check(a_lo > a_hi, "niższe HP powinno dać mocniejszą vignette (%f vs %f)" % [a_lo, a_hi])

	# (4) Modulacja sinusoidą — dolina = 0, szczyt > 0 dla tego samego HP.
	_check(hud._vignette_alpha(0.10, trough) == 0.0, "dolina pulsu powinna wygasić vignette do 0")
	_check(hud._vignette_alpha(0.10, peak) > hud._vignette_alpha(0.10, trough), "szczyt pulsu > dolina")

	# (5) Granice [0, VIG_ALPHA_MAX].
	var hp := 0.0
	while hp <= hud.VIG_HP_THRESH:
		var ph := -PI
		while ph <= PI:
			var a := hud._vignette_alpha(hp, ph)
			_check(a >= 0.0 and a <= hud.VIG_ALPHA_MAX, "alpha poza zakresem: %f (hp=%f, ph=%f)" % [a, hp, ph])
			ph += 0.5
		hp += 0.05

	hud.free()
	if _failures == 0:
		print("[VIG] ALL OK")
	else:
		printerr("[VIG] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
