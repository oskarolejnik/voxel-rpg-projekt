extends CanvasLayer
## HUD.gd — OZDOBNY pixel-art HUD (voxel/fantasy-RPG), w pełni rysowany w kodzie (draw_rect, pixel-perfect).
## Styl: drewniano-złote ramki, szklane „tubki" pasków z połyskiem + klejnoty na końcach.
## LEWY-GÓRNY: MEDALION z TWARZĄ postaci + paski HP(ghost-trail) / Stamina / Furia.
## DÓŁ-ŚRODEK: pasek XP z poziomem (medalik) i progresem, pod nim HOTBAR rozdzielony na
##   5 slotów SKILLI  ||  sekcję PRZEDMIOTÓW użytkowych (miksturki/jednorazówki).
## ZERO tekstur z zewnątrz — wszystko autorskie (czyste prawa do gry). Własne pixel-cyfry + ikony + twarz.
##
## Aktualizacja przez sygnały gracza (hp_changed/stamina_changed/combo_changed/died/respawned/
## level_changed/leveled_up/class_*), podłączane w Main. Bez class_name — Main instancjonuje przez preload.
##
## KONTRAKT (testy E3/E7/Feel4): metody-sloty (niżej), screen-flash (flash/_flash_*), pipsy COMBO
## (_combo_pips jako ColorRect.color == COMBO_PIP_ON/OFF, _combo_root, setup_combo, on_class_combo_changed,
## set_combo). NIE zmieniać tych nazw/typów.

const PAD: float = 16.0
const SKILL_SLOTS: int = 5
const ITEM_SLOTS: int = 3

# Paleta ramki (drewno + złoto) + wnętrza.
const C_OUTLINE: Color = Color8(34, 22, 14)
const C_WOOD_D: Color = Color8(92, 56, 28)
const C_WOOD: Color = Color8(132, 84, 42)
const C_WOOD_L: Color = Color8(176, 122, 64)
const C_GOLD: Color = Color8(214, 162, 70)
const C_GOLD_L: Color = Color8(246, 216, 132)
const C_INNER: Color = Color8(26, 22, 30)
const C_INNER_HI: Color = Color8(44, 38, 50)
const C_INNER_SKILL: Color = Color8(26, 30, 48)    # wnętrze slotu skilla (chłodne)
const C_INNER_ITEM: Color = Color8(26, 38, 30)     # wnętrze slotu przedmiotu (zielonkawe)

# Kolory pasków.
const COL_HP: Color = Color8(202, 48, 54)
const COL_HP_TRAIL: Color = Color8(246, 212, 120)
const COL_STAM: Color = Color8(62, 150, 222)
const COL_RES_DEFAULT: Color = Color8(230, 108, 40)
const COL_XP: Color = Color8(112, 200, 72)
const COL_NUM: Color = Color8(248, 250, 255)
const COL_NUM_EDGE: Color = Color(0.04, 0.04, 0.06, 0.96)

# Pixel-font 3x5.
const GLYPHS: Dictionary = {
	"0": ["###", "# #", "# #", "# #", "###"],
	"1": [" # ", "## ", " # ", " # ", "###"],
	"2": ["###", "  #", "###", "#  ", "###"],
	"3": ["###", "  #", "###", "  #", "###"],
	"4": ["# #", "# #", "###", "  #", "  #"],
	"5": ["###", "#  ", "###", "  #", "###"],
	"6": ["###", "#  ", "###", "# #", "###"],
	"7": ["###", "  #", "  #", "  #", "  #"],
	"8": ["###", "# #", "###", "# #", "###"],
	"9": ["###", "# #", "###", "  #", "###"],
	"/": ["  #", "  #", " # ", "#  ", "#  "],
	"x": ["   ", "# #", " # ", "# #", "   "],
	# Litery kardynalne dla kompasu (N/E/S/W) — własny pixel-font 3x5.
	"N": ["# #", "###", "###", "# #", "# #"],
	"E": ["###", "#  ", "###", "#  ", "###"],
	"S": ["###", "#  ", "###", "  #", "###"],
	"W": ["# #", "# #", "# #", "###", "# #"],
}

# Ikony pasków (#=jasny, o=ciemny akcent).
const IC_HEART: Array = [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."]
const IC_BOLT: Array = ["..##.", ".##..", "####.", "..##.", ".##..", "##..."]
const IC_FLAME: Array = ["..#..", ".###.", ".###.", "#####", "#####", ".###."]
const IC_SKULL: Array = [".#####.", "#######", "#o###o#", "#######", ".#####.", ".#.#.#."]
# Twarz postaci do medalionu (h=włosy, s=skóra, e=oko, m=usta, .=puste).
const IC_FACE: Array = [
	"..hhhhh..", ".hhhhhhh.", "hhhhhhhhh", "hsssssssh",
	"hsesssesh", "hsssssssh", "hssmmmssh", ".hsssssh.", "..sssss..",
]

# --- Warstwy ---
var _painter: Control
var _combo_root: Control
var _combo_pips: Array[ColorRect] = []
var _levelup_label: Label
var _flash_overlay: ColorRect
var _death_overlay: ColorRect
var _death_label: Label

# --- Stan animowany ---
var _hp_f: float = 1.0;    var _hp_t: float = 1.0;    var _hp_ghost: float = 1.0
var _hp_cur: int = 100;    var _hp_max: int = 100
var _stam_f: float = 1.0;  var _stam_t: float = 1.0
var _stam_cur: int = 100;  var _stam_max: int = 100
var _res_on: bool = false; var _res_f: float = 0.0;   var _res_t: float = 0.0
var _res_cur: int = 0;     var _res_max: float = 100.0; var _res_col: Color = COL_RES_DEFAULT
var _xp_f: float = 0.0;    var _xp_t: float = 0.0
var _level: int = 1;       var _xp: int = 0;          var _xp_next: int = 50
var _enemies: int = 0;     var _combo: int = 1
var _skill_sel: int = 0    # podświetlony slot skilla (aktywny)
var _show_crosshair: bool = true   # celownik TPS (środek ekranu)
# HOTBAR — dane slotów (rysowane w _paint). Skille: ikona+klawisz+cooldown; przedmioty: ikona+licznik.
var _skill_slots: Array = []   # [{icon:String, key:String, cd:float(0..1), secs:float}]
var _item_slots: Array = []    # [{icon:String, count:int}]
# READY-GLOW: krótki rozbłysk slotu skilla w momencie zejścia z cooldownu (telegraf „gotowe!").
# Na slot: poprzedni cd (do wykrycia przejścia >0 -> 0) + maleńcy timer rozbłysku (sekundy).
var _skill_prev_cd: Array = []     # [float] poprzedni cd na slot (wykrycie zbocza)
var _skill_glow: Array = []        # [float] pozostały czas rozbłysku (s), 0 = brak
const READY_GLOW_DUR: float = 0.45 # czas zaniku rozbłysku (s)
const READY_GLOW_COL: Color = Color(1.0, 0.92, 0.55)  # ciepły złoty błysk gotowości
# Ikony hotbara (autorskie 5x5/5x7 piksele; rysowane _blit jednokolorowo z tintem z _hotbar_icon).
const IC_WHIRL: Array = ["..#..", "#.#.#", ".###.", "#.#.#", "..#.."]
const IC_DASH: Array = [".#...", "..#..", "...#.", "..#..", ".#..."]
const IC_POTION: Array = ["..#..", ".###.", "..#..", ".###.", "#####", "#####", ".###."]
const IC_SHIELD: Array = ["#####", "#####", "#####", "#####", ".###.", "..#.."]
const IC_ARROW: Array = ["..#..", ".###.", "#####", "..#..", "..#.."]
const IC_ICE: Array = ["#.#.#", ".###.", "#####", ".###.", "#.#.#"]
const IC_AURA: Array = [".###.", "#...#", "#...#", "#...#", ".###."]

# --- KOMPAS + RADAR (nawigacja eksploracji) ---
# Kompas: pasek kierunków świata (N/E/S/W) na górze-środku, tintowany biomem gracza
# (telegraf kierunku progresji). Radar: małe kółko nad medalionem z blipami wrogów (grupa "enemies")
# względem gracza. Wszystko null-safe — HUD budowany zanim istnieją referencje gracza/świata.
var _player_ref: Node3D = null          # gracz (pozycja+yaw); może być null
var _world_ref: Node = null             # VoxelWorld (get_biome); może być null
var _compass_yaw: float = 0.0           # bieżący yaw gracza (rad), aktualizowany w _process
const COMPASS_W: float = 220.0          # szerokość paska kompasu
const COMPASS_H: float = 16.0           # wysokość paska kompasu
const COMPASS_FOV: float = PI           # kąt widoczny na pasku (180°: ±90° od kursu)
const RADAR_R: float = 30.0             # promień radaru (px)
const RADAR_RANGE: float = 40.0         # zasięg radaru w metrach (świat -> px)
# Tint pasma kompasu wg biomu (kierunek progresji): zieleń/ember/mróz.
const COMPASS_BIOME_TINT: Dictionary = {
	&"verdant": Color8(96, 168, 88),
	&"emberwaste": Color8(214, 120, 56),
	&"frosthelm": Color8(150, 200, 236),
}
const COMPASS_TINT_DEFAULT: Color = Color8(120, 132, 150)
# Kardynalne kierunki (8 rumbów) — kolejność zgodna z yaw rosnącym (0=N, CW).
const COMPASS_DIRS: Array = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

# Screen-flash.
var _flash_t: float = 0.0
var _flash_dur: float = 0.0
var _flash_peak: float = 0.0
const FLASH_COL_CRIT: Color = Color(1.0, 0.86, 0.45)
const FLASH_COL_HIT: Color = Color(1.0, 1.0, 1.0)

# Vignette niskiego HP — pulsująca czerwona ramka przy krawędziach ekranu (telegraf zagrożenia).
# Aktywna dopiero poniżej progu; im niżej HP, tym mocniejsza. Zero kosztu przy pełnym HP.
var _vig_phase: float = 0.0                  # faza sinusoidy (rad), narastana w _process
const VIG_HP_THRESH: float = 0.25            # próg aktywacji (frakcja HP)
const VIG_SPEED: float = 5.5                 # prędkość pulsu (rad/s)
const VIG_ALPHA_MAX: float = 0.42            # maks. alpha vignette przy HP≈0
const VIG_BAND: float = 0.18                 # grubość pasma vignette jako frakcja min(vp)
const VIG_COL: Color = Color(0.78, 0.06, 0.08)  # czerwień zagrożenia

# Pipsy COMBO (Ranger) — ColorRect, kontrakt E3.
const COMBO_PIP_ON: Color = Color(1.0, 0.78, 0.25, 0.98)
const COMBO_PIP_OFF: Color = Color(0.18, 0.20, 0.22, 0.70)
const COMBO_PIP_SIZE: float = 16.0
const COMBO_PIP_GAP: float = 6.0


class _Painter extends Control:
	var hud
	func _draw() -> void:
		if hud != null:
			hud._paint(self)


func _ready() -> void:
	_painter = _Painter.new()
	_painter.hud = self
	_painter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_painter)

	# Hotbar: domyślne puste sloty (Main je wypełnia przez set_skill_slot/set_item_slot).
	_skill_slots.clear()
	_skill_prev_cd.clear()
	_skill_glow.clear()
	for i in SKILL_SLOTS:
		_skill_slots.append({"icon": "", "key": str(i + 1), "cd": 0.0, "secs": 0.0})
		_skill_prev_cd.append(0.0)
		_skill_glow.append(0.0)
	_item_slots.clear()
	for i in ITEM_SLOTS:
		_item_slots.append({"icon": "", "count": 0})

	_combo_root = Control.new()
	_combo_root.position = Vector2(PAD, 140.0)
	_combo_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_root.visible = false
	add_child(_combo_root)

	_levelup_label = Label.new()
	_levelup_label.text = ""
	_levelup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_levelup_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_levelup_label.offset_top = 140.0
	_levelup_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_levelup_label.add_theme_font_size_override("font_size", 28)
	_levelup_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	_levelup_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_levelup_label.add_theme_constant_override("outline_size", 8)
	_levelup_label.modulate.a = 0.0
	_levelup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_levelup_label)

	_flash_overlay = ColorRect.new()
	_flash_overlay.color = Color(FLASH_COL_HIT.r, FLASH_COL_HIT.g, FLASH_COL_HIT.b, 0.0)
	_flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.visible = false
	add_child(_flash_overlay)

	_death_overlay = ColorRect.new()
	_death_overlay.color = Color(0, 0, 0, 0)
	_death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.visible = false
	add_child(_death_overlay)
	_death_label = Label.new()
	_death_label.text = "Zginąłeś\nRespawn..."
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_label.add_theme_font_size_override("font_size", 40)
	_death_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_death_label.add_theme_constant_override("outline_size", 8)
	_death_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(_death_label)

# ============================================================================
#  PRYMITYWY RYSOWANIA (pixel-perfect)
# ============================================================================
func _lighten(c: Color, a: float) -> Color:
	return Color(minf(c.r + a, 1.0), minf(c.g + a, 1.0), minf(c.b + a, 1.0), c.a)

func _darken(c: Color, a: float) -> Color:
	return Color(maxf(c.r - a, 0.0), maxf(c.g - a, 0.0), maxf(c.b - a, 0.0), c.a)

func _px(ci: CanvasItem, x: float, y: float, w: float, h: float, col: Color) -> void:
	ci.draw_rect(Rect2(roundf(x), roundf(y), maxf(roundf(w), 0.0), maxf(roundf(h), 0.0)), col)

func _disc(ci: CanvasItem, cx: float, cy: float, r: float, col: Color) -> void:
	var yy := -r
	while yy <= r:
		var hw := sqrt(maxf(0.0, r * r - yy * yy))
		if hw > 0.5:
			_px(ci, cx - hw, cy + yy, hw * 2.0, 2.0, col)
		yy += 2.0

func _gem(ci: CanvasItem, cx: float, cy: float, r: float, col: Color) -> void:
	_disc(ci, cx, cy, r + 1.5, C_OUTLINE)
	_disc(ci, cx, cy, r, _darken(col, 0.10))
	_disc(ci, cx, cy, r * 0.78, col)
	_disc(ci, cx - r * 0.32, cy - r * 0.32, r * 0.34, _lighten(col, 0.50))

func _blit(ci: CanvasItem, bmp: Array, x: float, y: float, u: int, col: Color) -> void:
	var dark := _darken(col, 0.45)
	for r in bmp.size():
		var row: String = bmp[r]
		for cidx in row.length():
			var ch := row[cidx]
			if ch == "#":
				_px(ci, x + cidx * u, y + r * u, u, u, col)
			elif ch == "o":
				_px(ci, x + cidx * u, y + r * u, u, u, dark)

# Wielokolorowa bitmapa (np. twarz) — mapowanie znak->kolor.
func _blit_pal(ci: CanvasItem, bmp: Array, x: float, y: float, u: int, pal: Dictionary) -> void:
	for r in bmp.size():
		var row: String = bmp[r]
		for cidx in row.length():
			var ch := row[cidx]
			if pal.has(ch):
				_px(ci, x + cidx * u, y + r * u, u, u, pal[ch])

func _text_w(s: String, u: int) -> float:
	return s.length() * 4 * u - u

func _text(ci: CanvasItem, s: String, x: float, y: float, u: int, col: Color) -> void:
	var ox := x
	for i in s.length():
		var g = GLYPHS.get(s[i], null)
		if g != null:
			for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				_blit(ci, g, ox + d.x, y + d.y, u, COL_NUM_EDGE)
			_blit(ci, g, ox, y, u, col)
		ox += 4 * u

func _text_centered(ci: CanvasItem, s: String, cx: float, cy: float, u: int, col: Color) -> void:
	_text(ci, s, cx - _text_w(s, u) * 0.5, cy - 2.5 * u, u, col)

# ============================================================================
#  OZDOBNE ELEMENTY
# ============================================================================
func _ornate_bar(ci: CanvasItem, x: float, y: float, w: float, h: float, frac: float, ghost: float, base: Color, trail: Color) -> void:
	var t := 3.0
	_px(ci, x - t - 1.0, y - t - 1.0, w + 2.0 * t + 2.0, h + 2.0 * t + 2.0, C_OUTLINE)
	_px(ci, x - t, y - t, w + 2.0 * t, h + 2.0 * t, C_WOOD)
	_px(ci, x - t, y - t, w + 2.0 * t, 1.0, C_WOOD_L)
	_px(ci, x - t, y - t, 1.0, h + 2.0 * t, C_WOOD_L)
	_px(ci, x - t, y + h + t - 1.0, w + 2.0 * t, 1.0, C_WOOD_D)
	_px(ci, x + w + t - 1.0, y - t, 1.0, h + 2.0 * t, C_WOOD_D)
	_px(ci, x - 1.0, y - 1.0, w + 2.0, h + 2.0, C_GOLD)
	_px(ci, x - 1.0, y - 1.0, w + 2.0, 1.0, C_GOLD_L)
	_px(ci, x, y, w, h, C_INNER)
	var gw := roundf(w * clampf(ghost, 0.0, 1.0) / 2.0) * 2.0
	var fw := roundf(w * clampf(frac, 0.0, 1.0) / 2.0) * 2.0
	if gw > fw:
		_px(ci, x, y, gw, h, trail)
	if fw > 0.0:
		_px(ci, x, y, fw, h, base)
		_px(ci, x, y, fw, 2.0, _lighten(base, 0.22))
		_px(ci, x, y + 1.0, fw, 1.0, _lighten(base, 0.42))
		_px(ci, x, y + h - 2.0, fw, 2.0, _darken(base, 0.26))
	_gem(ci, x + w + t + 3.0, y + h * 0.5, h * 0.62, base)

# Medalion z TWARZĄ postaci (drewno+złoto, nity).
func _medallion(ci: CanvasItem, cx: float, cy: float, r: float) -> void:
	_disc(ci, cx, cy, r + 2.0, C_OUTLINE)
	_disc(ci, cx, cy, r, C_WOOD)
	_disc(ci, cx - 1.0, cy - 1.0, r - 1.0, C_WOOD_L)
	_disc(ci, cx, cy, r - 4.0, C_GOLD)
	_disc(ci, cx - 1.0, cy - 1.0, r - 5.0, C_GOLD_L)
	_disc(ci, cx, cy, r - 6.0, C_OUTLINE)
	_disc(ci, cx, cy, r - 8.0, C_INNER)
	_disc(ci, cx, cy, r - 9.0, Color8(40, 44, 60))   # tło portretu
	# Twarz.
	var pal := {"h": Color8(96, 60, 34), "s": Color8(235, 194, 150), "e": Color8(42, 40, 58), "m": Color8(156, 82, 82)}
	var fu := 3
	_blit_pal(ci, IC_FACE, cx - IC_FACE[0].length() * fu * 0.5, cy - IC_FACE.size() * fu * 0.5, fu, pal)
	# Nity (złote studsy) co 45°.
	for k in 8:
		var ang := float(k) * PI / 4.0
		_disc(ci, cx + cos(ang) * (r - 1.5), cy + sin(ang) * (r - 1.5), 2.6, C_GOLD_L)

# Mały medalik z numerem poziomu (na lewym końcu paska XP).
func _badge(ci: CanvasItem, cx: float, cy: float, r: float, level: int) -> void:
	_disc(ci, cx, cy, r + 2.0, C_OUTLINE)
	_disc(ci, cx, cy, r, C_GOLD)
	_disc(ci, cx - 1.0, cy - 1.0, r - 1.0, C_GOLD_L)
	_disc(ci, cx, cy, r - 3.0, C_OUTLINE)
	_disc(ci, cx, cy, r - 4.0, C_INNER)
	_text_centered(ci, str(level), cx, cy, 2, C_GOLD_L)

func _ornate_slot(ci: CanvasItem, x: float, y: float, s: float, selected: bool, inner: Color) -> void:
	var frame := C_GOLD_L if selected else C_WOOD
	_px(ci, x - 3.0, y - 3.0, s + 6.0, s + 6.0, C_OUTLINE)
	_px(ci, x - 2.0, y - 2.0, s + 4.0, s + 4.0, frame)
	_px(ci, x - 2.0, y - 2.0, s + 4.0, 1.0, _lighten(frame, 0.18))
	_px(ci, x - 2.0, y + s + 1.0, s + 4.0, 1.0, _darken(frame, 0.22))
	_px(ci, x - 1.0, y - 1.0, s + 2.0, s + 2.0, C_GOLD_L if selected else C_GOLD)
	_px(ci, x, y, s, s, inner)
	_px(ci, x, y, s, 2.0, _lighten(inner, 0.06))
	_disc(ci, x - 2.0, y + s * 0.5, 2.4, C_GOLD_L)
	_disc(ci, x + s + 2.0, y + s * 0.5, 2.4, C_GOLD_L)

# Ozdobny pionowy separator między sekcjami hotbara.
func _divider(ci: CanvasItem, x: float, y: float, h: float) -> void:
	_px(ci, x - 1.0, y - 1.0, 6.0, h + 2.0, C_OUTLINE)
	_px(ci, x, y, 4.0, h, C_WOOD)
	_px(ci, x, y, 4.0, 2.0, C_WOOD_L)
	_disc(ci, x + 2.0, y + h * 0.5, 3.0, C_GOLD_L)

# ============================================================================
#  GŁÓWNE RYSOWANIE HUD
# ============================================================================
func _paint(ci: CanvasItem) -> void:
	var vp: Vector2 = ci.size

	# --- LEWY-GÓRNY: medalion (twarz) + paski HP / Stamina / [Furia] ---
	var r := 30.0
	var bx := PAD + 2.0 * r + 6.0
	var bw := 196.0
	var bh := 14.0
	var step := bh + 8.0

	var rows: Array = []
	rows.append({"f": _hp_f, "g": _hp_ghost, "c": COL_HP, "tr": COL_HP_TRAIL, "ic": IC_HEART, "ict": Color8(240, 80, 86), "num": "%d/%d" % [_hp_cur, _hp_max]})
	rows.append({"f": _stam_f, "g": _stam_f, "c": COL_STAM, "tr": COL_STAM, "ic": IC_BOLT, "ict": Color8(140, 200, 250), "num": "%d/%d" % [_stam_cur, _stam_max]})
	if _res_on:
		rows.append({"f": _res_f, "g": _res_f, "c": _res_col, "tr": _res_col, "ic": IC_FLAME, "ict": _lighten(_res_col, 0.20), "num": "%d/%d" % [_res_cur, int(_res_max)]})

	var stack_h := rows.size() * step - 8.0
	var y0 := PAD + 6.0
	var cy := y0 + stack_h * 0.5
	for i in rows.size():
		var rdef = rows[i]
		var y := y0 + i * step
		_ornate_bar(ci, bx, y, bw, bh, rdef["f"], rdef["g"], rdef["c"], rdef["tr"])
		_blit(ci, rdef["ic"], bx + 4.0, y + bh * 0.5 - 9.0, 3, rdef["ict"])
		_text_centered(ci, rdef["num"], bx + bw * 0.5, y + bh * 0.5, 2, COL_NUM)
	_medallion(ci, PAD + r, cy, r)

	# --- Licznik wrogów + combo (prawy-górny) ---
	if _enemies > 0:
		var es := str(_enemies)
		var ex := vp.x - PAD - (_text_w(es, 2) + 27.0)
		_blit(ci, IC_SKULL, ex, PAD, 3, Color8(220, 224, 232))
		_text(ci, es, ex + 27.0, PAD + 4.0, 2, COL_NUM)
	if _combo > 1:
		var cs := "x%d" % _combo
		_text(ci, cs, vp.x - PAD - _text_w(cs, 3), PAD + 28.0, 3, Color8(255, 210, 80))

	# --- DÓŁ-ŚRODEK: pasek XP (medalik z poziomem + progres), pod nim HOTBAR (skille | przedmioty) ---
	var slot := 44.0
	var gap := 8.0
	var skills_w := SKILL_SLOTS * slot + (SKILL_SLOTS - 1) * gap
	var items_w := ITEM_SLOTS * slot + (ITEM_SLOTS - 1) * gap
	var divider := 26.0
	var total := skills_w + divider + items_w
	var x0 := (vp.x - total) * 0.5
	var sy := vp.y - PAD - slot - 4.0

	# Pasek XP nad hotbarem: medalik poziomu po lewej + tubka progresu + liczby.
	var xph := 14.0
	var xpy := sy - 12.0 - xph - 6.0
	var br := xph * 0.95
	var xpx := x0 + br * 2.0
	var xpw := total - br * 2.0
	_ornate_bar(ci, xpx, xpy, xpw, xph, _xp_f, _xp_f, COL_XP, COL_XP)
	var xs := "%d/%d" % [_xp, _xp_next] if _xp_next > 0 else "MAX"
	_text_centered(ci, xs, xpx + xpw * 0.5, xpy + xph * 0.5, 2, COL_NUM)
	_badge(ci, x0 + br, xpy + xph * 0.5, br, _level)

	# Sekcja SKILLI (5 slotów): ramka + ikona + cooldown (ciemna zasłona od góry + sekundy) + klawisz.
	for i in SKILL_SLOTS:
		var sx := x0 + i * (slot + gap)
		var sd: Dictionary = _skill_slots[i] if i < _skill_slots.size() else {}
		_ornate_slot(ci, sx, sy, slot, i == _skill_sel, C_INNER_SKILL)
		_draw_slot_icon(ci, sx, sy, slot, String(sd.get("icon", "")))
		var cd: float = float(sd.get("cd", 0.0))
		if cd > 0.01:
			# Zasłona maleje z wysokości slotu (cd=1 pełna -> cd=0 brak) = klasyczny sweep cooldownu.
			_px(ci, sx, sy, slot, slot * clampf(cd, 0.0, 1.0), Color(0.0, 0.0, 0.0, 0.55))
			var secs: float = float(sd.get("secs", 0.0))
			if secs >= 0.1:
				_text_centered(ci, str(int(ceil(secs))), sx + slot * 0.5, sy + slot * 0.5, 3, COL_NUM)
		# READY-GLOW: ciepły rozbłysk slotu tuż po zejściu z cooldownu (maleje w czasie).
		if i < _skill_glow.size() and _skill_glow[i] > 0.0:
			var gf := clampf(_skill_glow[i] / READY_GLOW_DUR, 0.0, 1.0)
			# Wypełnienie slotu (jasność) + jaśniejsza złota obwódka — telegraf „gotowe!".
			_px(ci, sx, sy, slot, slot, Color(READY_GLOW_COL.r, READY_GLOW_COL.g, READY_GLOW_COL.b, 0.45 * gf))
			_px(ci, sx - 1.0, sy - 1.0, slot + 2.0, 2.0, Color(C_GOLD_L.r, C_GOLD_L.g, C_GOLD_L.b, gf))
			_px(ci, sx - 1.0, sy + slot - 1.0, slot + 2.0, 2.0, Color(C_GOLD_L.r, C_GOLD_L.g, C_GOLD_L.b, gf))
			_px(ci, sx - 1.0, sy - 1.0, 2.0, slot + 2.0, Color(C_GOLD_L.r, C_GOLD_L.g, C_GOLD_L.b, gf))
			_px(ci, sx + slot - 1.0, sy - 1.0, 2.0, slot + 2.0, Color(C_GOLD_L.r, C_GOLD_L.g, C_GOLD_L.b, gf))
		_text(ci, String(sd.get("key", str(i + 1))), sx + 3.0, sy + slot - 13.0, 2, Color8(150, 180, 220))
	# Separator.
	_divider(ci, x0 + skills_w + divider * 0.5 - 2.0, sy - 2.0, slot + 4.0)
	# Sekcja PRZEDMIOTÓW użytkowych (miksturki/jednorazówki): ramka + ikona + licznik sztuk.
	var ix0 := x0 + skills_w + divider
	for i in ITEM_SLOTS:
		var ix := ix0 + i * (slot + gap)
		var it: Dictionary = _item_slots[i] if i < _item_slots.size() else {}
		_ornate_slot(ci, ix, sy, slot, false, C_INNER_ITEM)
		_draw_slot_icon(ci, ix, sy, slot, String(it.get("icon", "")))
		var cnt: int = int(it.get("count", 0))
		if cnt > 0:
			_text(ci, str(cnt), ix + slot - _text_w(str(cnt), 2) - 5.0, sy + slot - 13.0, 2, COL_NUM)

	# --- KOMPAS (góra-środek) — kurs + tint biomu gracza (kierunek progresji) ---
	_compass(ci, roundf(vp.x * 0.5), PAD, _compass_yaw, _biome_tint())
	# --- RADAR (nad medalionem, lewy-górny) — blipy wrogów względem gracza ---
	_radar(ci, PAD + r, cy + stack_h * 0.5 + RADAR_R + 14.0, _gather_enemy_blips())

	# --- VIGNETTE NISKIEGO HP (krawędzie ekranu) — pulsująca czerwień zagrożenia ---
	var vig_a := _vignette_alpha(_hp_f, _vig_phase)
	if vig_a > 0.0:
		_vignette(ci, vp, vig_a)

	# --- CELOWNIK (środek ekranu) — system kamery TPS ---
	if _show_crosshair:
		_crosshair(ci, roundf(vp.x * 0.5), roundf(vp.y * 0.5))

# Celownik TPS: 4 ząbki + środkowa kropka, z ciemnym konturem (czytelny nad każdym tłem).
func _crosshair(ci: CanvasItem, cx: float, cy: float) -> void:
	var col := Color(1.0, 1.0, 1.0, 0.88)
	var edge := Color(0.0, 0.0, 0.0, 0.55)
	var gap := 5.0
	var ln := 7.0
	var th := 2.0
	# Ząbki: (x, y, w, h) — góra, dół, lewo, prawo.
	var arms := [
		Vector4(cx - th * 0.5, cy - gap - ln, th, ln),
		Vector4(cx - th * 0.5, cy + gap, th, ln),
		Vector4(cx - gap - ln, cy - th * 0.5, ln, th),
		Vector4(cx + gap, cy - th * 0.5, ln, th),
	]
	for a in arms:
		_px(ci, a.x - 1.0, a.y - 1.0, a.z + 2.0, a.w + 2.0, edge)
	_px(ci, cx - th * 0.5 - 1.0, cy - th * 0.5 - 1.0, th + 2.0, th + 2.0, edge)
	for a in arms:
		_px(ci, a.x, a.y, a.z, a.w, col)
	_px(ci, cx - th * 0.5, cy - th * 0.5, th, th, col)

## Alpha vignette niskiego HP. Czysta funkcja (testowalna bez sceny):
## 0 powyżej progu VIG_HP_THRESH; poniżej — narasta liniowo do VIG_ALPHA_MAX przy HP=0,
## modulowana pulsem sinusoidalnym (0.5+0.5*sin) wg fazy t. Zawsze w [0, VIG_ALPHA_MAX].
func _vignette_alpha(hp_frac: float, t: float) -> float:
	var hf := clampf(hp_frac, 0.0, 1.0)
	if hf >= VIG_HP_THRESH:
		return 0.0
	var depth := (VIG_HP_THRESH - hf) / VIG_HP_THRESH   # 0 na progu -> 1 przy HP=0
	var pulse := 0.5 + 0.5 * sin(t)                      # 0..1
	return clampf(VIG_ALPHA_MAX * depth * pulse, 0.0, VIG_ALPHA_MAX)

## Rysuje czerwone pasma przy krawędziach ekranu (4 gradientowe kroki na pasmo).
## alpha = wynik _vignette_alpha. Krawędzie ciemniejsze do środka -> efekt vignette.
func _vignette(ci: CanvasItem, vp: Vector2, alpha: float) -> void:
	var band := minf(vp.x, vp.y) * VIG_BAND
	var steps := 4
	for s in steps:
		# Od krawędzi (s=0, pełna alpha) do wnętrza (zanik) — kwadratowy spadek.
		var f := 1.0 - float(s) / float(steps)
		var a := alpha * f * f
		var col := Color(VIG_COL.r, VIG_COL.g, VIG_COL.b, a)
		var inset := band * (float(s) / float(steps))
		var th := band / float(steps) + 1.0
		# Góra / dół / lewo / prawo.
		_px(ci, 0.0, inset, vp.x, th, col)
		_px(ci, 0.0, vp.y - inset - th, vp.x, th, col)
		_px(ci, inset, 0.0, th, vp.y, col)
		_px(ci, vp.x - inset - th, 0.0, th, vp.y, col)

# ============================================================================
#  KOMPAS + RADAR (nawigacja)
# ============================================================================
## Kardynalny kierunek (rumb) z yaw (rad). yaw=0 -> "N", rośnie zgodnie z ruchem
## wskazówek (N->E->S->W). Czysta funkcja (testowalna bez sceny).
func heading_label(yaw: float) -> String:
	var deg := fposmod(rad_to_deg(yaw) + 22.5, 360.0)
	var idx := int(deg / 45.0) % COMPASS_DIRS.size()
	return COMPASS_DIRS[idx]

## Tint kompasu wg biomu pod graczem (VoxelWorld.get_biome). Null-safe: brak gracza/świata
## lub brak metody => kolor domyślny. NIE rzuca, gdy referencje jeszcze nie istnieją.
func _biome_tint() -> Color:
	if _world_ref == null or not is_instance_valid(_world_ref):
		return COMPASS_TINT_DEFAULT
	if _player_ref == null or not is_instance_valid(_player_ref):
		return COMPASS_TINT_DEFAULT
	if not _world_ref.has_method("get_biome"):
		return COMPASS_TINT_DEFAULT
	var p := _player_ref.global_position
	var biome: StringName = _world_ref.get_biome(int(floor(p.x)), int(floor(p.z)))
	return COMPASS_BIOME_TINT.get(biome, COMPASS_TINT_DEFAULT)

## Pasek kompasu (góra-środek): tło-tubka tintowana biomem gracza + znaczniki N/E/S/W
## przesuwające się wraz z yaw. Kreska kursu w środku. Null-safe (yaw przekazany).
func _compass(ci: CanvasItem, cx: float, top: float, yaw: float, tint: Color) -> void:
	var x := cx - COMPASS_W * 0.5
	var y := top
	var t := 3.0
	# Ramka drewno+złoto (jak _ornate_bar, uproszczona).
	_px(ci, x - t - 1.0, y - t - 1.0, COMPASS_W + 2.0 * t + 2.0, COMPASS_H + 2.0 * t + 2.0, C_OUTLINE)
	_px(ci, x - t, y - t, COMPASS_W + 2.0 * t, COMPASS_H + 2.0 * t, C_WOOD)
	_px(ci, x - t, y - t, COMPASS_W + 2.0 * t, 1.0, C_WOOD_L)
	_px(ci, x - 1.0, y - 1.0, COMPASS_W + 2.0, COMPASS_H + 2.0, C_GOLD)
	# Wnętrze tintowane biomem (telegraf kierunku progresji).
	_px(ci, x, y, COMPASS_W, COMPASS_H, _darken(tint, 0.30))
	_px(ci, x, y, COMPASS_W, 2.0, _lighten(tint, 0.10))
	# Znaczniki kardynalne — mapowanie kąta względnego (-FOV/2..+FOV/2) na px paska.
	var half := COMPASS_FOV * 0.5
	var marks := {"N": 0.0, "E": PI * 0.5, "S": PI, "W": PI * 1.5}
	for label in marks.keys():
		var rel := wrapf(marks[label] - yaw, -PI, PI)
		if absf(rel) <= half:
			var mx := cx + (rel / half) * (COMPASS_W * 0.5 - 8.0)
			_text_centered(ci, label, mx, y + COMPASS_H * 0.5, 2, COL_NUM)
	# Kreska kursu (środek) — aktualny kierunek patrzenia.
	_px(ci, cx - 1.0, y - 4.0, 2.0, COMPASS_H + 8.0, C_GOLD_L)

## Mały radar (kółko) z blipami bytów względem gracza. blips: Array[Vector2] (offset świata x,z
## w metrach, względem gracza, już obrócony do lokalnego układu). Null-safe na pustej liście.
func _radar(ci: CanvasItem, cx: float, cy: float, blips: Array) -> void:
	# Tło-tarcza.
	_disc(ci, cx, cy, RADAR_R + 3.0, C_OUTLINE)
	_disc(ci, cx, cy, RADAR_R + 1.5, C_GOLD)
	_disc(ci, cx, cy, RADAR_R, C_INNER)
	# Krzyż osi.
	_px(ci, cx - RADAR_R, cy - 0.5, RADAR_R * 2.0, 1.0, C_INNER_HI)
	_px(ci, cx - 0.5, cy - RADAR_R, 1.0, RADAR_R * 2.0, C_INNER_HI)
	# Gracz (środek).
	_disc(ci, cx, cy, 2.5, C_GOLD_L)
	# Blipy wrogów (czerwone), clamp do tarczy.
	for b in blips:
		var off: Vector2 = b
		var d := off.length()
		if d > RADAR_RANGE:
			continue
		var px := (off / RADAR_RANGE) * RADAR_R
		_disc(ci, cx + px.x, cy + px.y, 2.0, Color8(232, 72, 72))

## Zbiera blipy z grupy "enemies" względem gracza (świat -> lokalny, obrót o yaw -> góra=przód).
## Zwraca Array[Vector2] (px-offsety w metrach). Null-safe: brak gracza/drzewa => [].
func _gather_enemy_blips() -> Array:
	var out: Array = []
	if _player_ref == null or not is_instance_valid(_player_ref):
		return out
	var tree := get_tree()
	if tree == null:
		return out
	var ppos := _player_ref.global_position
	var yaw := _compass_yaw
	var cs := cos(-yaw)
	var sn := sin(-yaw)
	for e in tree.get_nodes_in_group("enemies"):
		if e == null or not (e is Node3D) or not is_instance_valid(e):
			continue
		var ep: Vector3 = (e as Node3D).global_position
		var dx := ep.x - ppos.x
		var dz := ep.z - ppos.z
		# Obrót do lokalnego układu gracza: oś Y radaru = przód (mapujemy -z na +y "do góry").
		var lx := dx * cs - dz * sn
		var lz := dx * sn + dz * cs
		out.append(Vector2(lx, lz))
		if out.size() >= 24:
			break
	return out

# ============================================================================
#  ANIMACJA + FLASH
# ============================================================================
func _process(delta: float) -> void:
	_hp_f = lerpf(_hp_f, _hp_t, _sm(15.0, delta))
	if _hp_f >= _hp_ghost:
		_hp_ghost = _hp_f
	else:
		_hp_ghost = lerpf(_hp_ghost, _hp_f, _sm(3.5, delta))
	_stam_f = lerpf(_stam_f, _stam_t, _sm(18.0, delta))
	_res_f = lerpf(_res_f, _res_t, _sm(15.0, delta))
	_xp_f = lerpf(_xp_f, _xp_t, _sm(10.0, delta))
	# Faza pulsu vignette — narastana tylko przy niskim HP (zero kosztu przy zdrowiu).
	if _hp_f < VIG_HP_THRESH:
		_vig_phase = fposmod(_vig_phase + VIG_SPEED * delta, TAU)
	# Zanik rozbłysków „gotowe!" slotów skilli (tanio, tylko gdy któryś aktywny).
	for i in _skill_glow.size():
		if _skill_glow[i] > 0.0:
			_skill_glow[i] = maxf(0.0, _skill_glow[i] - delta)
	# Yaw kompasu z gracza (jeśli wpięty) — tanio, raz na klatkę. Null-safe.
	if _player_ref != null and is_instance_valid(_player_ref):
		_compass_yaw = _player_ref.global_rotation.y
	if _painter != null:
		_painter.queue_redraw()

	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
		var a := _flash_peak * (_flash_t / _flash_dur) if _flash_dur > 0.0 else 0.0
		_flash_overlay.color.a = clampf(a, 0.0, 1.0)
		if _flash_t == 0.0:
			_flash_overlay.visible = false

func _sm(k: float, delta: float) -> float:
	return 1.0 - exp(-k * delta)

func flash(is_crit: bool) -> void:
	if _flash_overlay == null:
		return
	var peak := 0.30 if is_crit else 0.14
	var dur := 0.18 if is_crit else 0.10
	var col := FLASH_COL_CRIT if is_crit else FLASH_COL_HIT
	if peak >= _flash_peak or _flash_t <= 0.0:
		_flash_peak = peak
		_flash_dur = dur
		_flash_t = dur
		_flash_overlay.color = Color(col.r, col.g, col.b, peak)
	_flash_overlay.visible = true

func _make_rect(color: Color, size: Vector2) -> ColorRect:
	var rr := ColorRect.new()
	rr.color = color
	rr.size = size
	rr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rr

# ============================================================================
#  SLOTY SYGNAŁÓW GRACZA
# ============================================================================
func on_hp_changed(current: float, maximum: float) -> void:
	_hp_max = int(round(maximum))
	_hp_cur = int(round(clampf(current, 0.0, maximum)))
	_hp_t = 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)

func on_stamina_changed(current: float, maximum: float) -> void:
	_stam_max = int(round(maximum))
	_stam_cur = int(round(clampf(current, 0.0, maximum)))
	_stam_t = 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)

func on_player_died() -> void:
	_death_overlay.visible = true
	var tw := create_tween()
	tw.tween_property(_death_overlay, "color:a", 0.65, 0.4)

func on_player_respawned() -> void:
	var tw := create_tween()
	tw.tween_property(_death_overlay, "color:a", 0.0, 0.4)
	tw.tween_callback(func(): _death_overlay.visible = false)

func set_enemy_count(n: int) -> void:
	_enemies = maxi(0, n)

func set_combo(n: int) -> void:
	_combo = n

# Podświetla aktywny slot SKILLA (0..SKILL_SLOTS-1). Do wpięcia z inputu gracza.
func select_hotbar_slot(i: int) -> void:
	_skill_sel = clampi(i, 0, SKILL_SLOTS - 1)

# Pokaż/ukryj celownik TPS (np. ukryj w menu/ekwipunku).
func set_crosshair_visible(on: bool) -> void:
	_show_crosshair = on

# Wpina referencje nawigacji (kompas/radar). Woła Main, gdy gracz/świat już istnieją.
# Oba parametry opcjonalne i null-safe — HUD działa bez nich (kierunek domyślny, brak blipów).
func set_nav_refs(player: Node3D, world: Node) -> void:
	_player_ref = player
	_world_ref = world
	if _player_ref != null and is_instance_valid(_player_ref):
		_compass_yaw = _player_ref.global_rotation.y

# ============================================================================
#  HOTBAR API (woła Main: ikony+klawisze raz, cooldowny co klatkę)
# ============================================================================
# Definicja ikony hotbara: bitmapa + tint. Pusta nazwa / nieznana -> brak ikony.
func _hotbar_icon(name: String) -> Dictionary:
	match name:
		"whirl": return {"bmp": IC_WHIRL, "col": Color8(150, 210, 255)}   # Wir Ostrzy (finisher)
		"dash": return {"bmp": IC_DASH, "col": Color8(255, 220, 120)}     # unik
		"bolt": return {"bmp": IC_BOLT, "col": Color8(150, 200, 250)}     # skill błyskawiczny
		"flame": return {"bmp": IC_FLAME, "col": Color8(240, 140, 70)}    # skill ognisty
		"potion": return {"bmp": IC_POTION, "col": Color8(220, 90, 90)}   # mikstura
		"shield": return {"bmp": IC_SHIELD, "col": Color8(180, 190, 205)} # tank
		"arrow": return {"bmp": IC_ARROW, "col": Color8(150, 210, 130)}   # łuk/strzał
		"ice": return {"bmp": IC_ICE, "col": Color8(150, 220, 255)}       # mróz
		"aura": return {"bmp": IC_AURA, "col": Color8(230, 200, 120)}     # aura/utility
		_: return {}

func _draw_slot_icon(ci: CanvasItem, x: float, y: float, s: float, name: String) -> void:
	if name == "":
		return
	var d := _hotbar_icon(name)
	if d.is_empty():
		return
	var bmp: Array = d["bmp"]
	var u := 3
	var w := float(String(bmp[0]).length() * u)
	var h := float(bmp.size() * u)
	_blit(ci, bmp, x + (s - w) * 0.5, y + (s - h) * 0.5, u, d["col"])

## Ustawia ikonę i etykietę klawisza slotu skilla (i=0..SKILL_SLOTS-1).
func set_skill_slot(i: int, icon: String, key: String) -> void:
	if i >= 0 and i < _skill_slots.size():
		_skill_slots[i]["icon"] = icon
		_skill_slots[i]["key"] = key

## Ustawia cooldown slotu skilla: frac 0..1 (1=pełny CD) + sekundy do gotowości (do napisu).
## Wykrywa zbocze cd>0 -> cd≈0 (skill właśnie zszedł z cooldownu) i odpala READY-GLOW.
func set_skill_cooldown(i: int, frac: float, secs: float) -> void:
	if i >= 0 and i < _skill_slots.size():
		var nf := clampf(frac, 0.0, 1.0)
		# Zbocze opadające: poprzednio na cooldownie (>0.01), teraz gotowy (≈0) -> rozbłysk.
		if i < _skill_prev_cd.size() and _skill_prev_cd[i] > 0.01 and nf <= 0.01:
			if i < _skill_glow.size():
				_skill_glow[i] = READY_GLOW_DUR
		if i < _skill_prev_cd.size():
			_skill_prev_cd[i] = nf
		_skill_slots[i]["cd"] = nf
		_skill_slots[i]["secs"] = maxf(0.0, secs)

## Ustawia ikonę i licznik sztuk slotu przedmiotu (i=0..ITEM_SLOTS-1).
func set_item_slot(i: int, icon: String, count: int) -> void:
	if i >= 0 and i < _item_slots.size():
		_item_slots[i]["icon"] = icon
		_item_slots[i]["count"] = maxi(0, count)

# ============================================================================
#  ETAP 3 — ZASÓB KLASY + POZIOM/XP
# ============================================================================
func setup_class_resource(label: String, color: Color, maximum: float) -> void:
	_res_max = maxf(1.0, maximum)
	_res_col = color
	_res_on = true

func on_class_resource_changed(_name: StringName, current: float, maximum: float) -> void:
	if maximum > 0.0:
		_res_max = maximum
	_res_cur = int(round(clampf(current, 0.0, _res_max)))
	_res_t = 0.0 if _res_max <= 0.0 else clampf(current / _res_max, 0.0, 1.0)

func setup_combo(maximum: int) -> void:
	var n := maxi(0, maximum)
	for pip in _combo_pips:
		pip.queue_free()
	_combo_pips.clear()
	for i in n:
		var pip := _make_rect(COMBO_PIP_OFF, Vector2(COMBO_PIP_SIZE, COMBO_PIP_SIZE))
		pip.position = Vector2(float(i) * (COMBO_PIP_SIZE + COMBO_PIP_GAP), 0.0)
		_combo_root.add_child(pip)
		_combo_pips.append(pip)
	_combo_root.visible = n > 0

func on_class_combo_changed(count: int, maximum: int) -> void:
	if maximum != _combo_pips.size():
		setup_combo(maximum)
	var lit := clampi(count, 0, _combo_pips.size())
	for i in _combo_pips.size():
		_combo_pips[i].color = COMBO_PIP_ON if i < lit else COMBO_PIP_OFF

func on_level_changed(level: int, xp: int, xp_to_next: int) -> void:
	_level = level
	_xp = xp
	_xp_next = xp_to_next
	_xp_t = 1.0 if xp_to_next <= 0 else clampf(float(xp) / float(xp_to_next), 0.0, 1.0)

func on_leveled_up(new_level: int, points_gained: int) -> void:
	_levelup_label.text = "AWANS!  Poziom %d   (+%d pkt)" % [new_level, points_gained]
	var tw := create_tween()
	_levelup_label.modulate.a = 1.0
	tw.tween_interval(1.2)
	tw.tween_property(_levelup_label, "modulate:a", 0.0, 0.6)
