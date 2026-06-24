extends Node
## build_ui_theme.gd — NARZĘDZIE: generuje motyw UI „drewno-złoto" (paleta jak HUD) i zapisuje do
## res://data/ui/wood_gold_theme.tres. Uruchom: godot --headless res://tools/build_ui_theme.tscn
## Motyw wpięty globalnie przez project.godot [gui] theme/custom -> styluje WSZYSTKIE ekrany menu.
## Pixel-font: jeśli istnieje res://assets/fonts/pixel.ttf, użyty jako default_font (drop-in CC0).

const OUT_PATH := "res://data/ui/wood_gold_theme.tres"
const FONT_PATH := "res://assets/fonts/pixel.ttf"

# Paleta zgodna z HUD (drewno + złoto + ciemne wnętrze).
const C_OUTLINE := Color8(34, 22, 14)
const C_WOOD_D := Color8(92, 56, 28)
const C_WOOD := Color8(132, 84, 42)
const C_WOOD_L := Color8(176, 122, 64)
const C_GOLD := Color8(214, 162, 70)
const C_GOLD_L := Color8(246, 216, 132)
const C_INNER := Color8(22, 18, 26)
const C_PANEL := Color8(26, 20, 24)
const C_FIELD := Color8(14, 12, 18)
const C_TEXT := Color8(244, 238, 222)
const C_TEXT_DIM := Color8(190, 178, 150)


func _ready() -> void:
	var t := Theme.new()
	t.default_font_size = 18
	if ResourceLoader.exists(FONT_PATH):
		t.default_font = load(FONT_PATH)
		print("[THEME] pixel-font wpięty: ", FONT_PATH)
	else:
		print("[THEME] brak pixel-fontu (", FONT_PATH, ") — styl ramek/kolorów bez pixel-czcionki (drop-in CC0 później)")

	var btn_n := _sb(C_WOOD, C_GOLD, 2, 8)
	var btn_h := _sb(C_WOOD_L, C_GOLD_L, 2, 8)
	var btn_p := _sb(C_WOOD_D, C_GOLD, 2, 8)
	var btn_d := _sb(C_INNER, Color(C_WOOD.r, C_WOOD.g, C_WOOD.b, 0.45), 2, 8)
	var btn_f := _sb(Color(0, 0, 0, 0), C_GOLD_L, 2, 8)
	var panel := _sb(Color(C_PANEL.r, C_PANEL.g, C_PANEL.b, 0.96), C_WOOD_L, 3, 12)
	var field_n := _sb(C_FIELD, C_GOLD, 2, 6)
	var field_f := _sb(C_FIELD, C_GOLD_L, 2, 6)

	# --- Button (+ pochodne, by OptionButton/CheckButton itp. wyglądały jak drewniane guziki) ---
	for ty in ["Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox"]:
		t.set_stylebox("normal", ty, btn_n)
		t.set_stylebox("hover", ty, btn_h)
		t.set_stylebox("pressed", ty, btn_p)
		t.set_stylebox("disabled", ty, btn_d)
		t.set_stylebox("focus", ty, btn_f)
		t.set_color("font_color", ty, C_GOLD_L)
		t.set_color("font_hover_color", ty, C_TEXT)
		t.set_color("font_pressed_color", ty, C_GOLD)
		t.set_color("font_focus_color", ty, C_TEXT)
		t.set_color("font_disabled_color", ty, C_TEXT_DIM)

	# --- Label / RichTextLabel ---
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_color", "RichTextLabel", C_TEXT)
	t.set_color("default_color", "RichTextLabel", C_TEXT)

	# --- Panel / PanelContainer / TabContainer ---
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "TabContainer", panel)

	# --- LineEdit ---
	t.set_stylebox("normal", "LineEdit", field_n)
	t.set_stylebox("focus", "LineEdit", field_f)
	t.set_color("font_color", "LineEdit", C_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", C_TEXT_DIM)
	t.set_color("caret_color", "LineEdit", C_GOLD_L)
	t.set_color("selection_color", "LineEdit", Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.35))

	# --- HSlider (suwaki ustawień): tor + obszar wypełnienia ---
	t.set_stylebox("slider", "HSlider", _sb(C_INNER, C_WOOD_D, 1, 0))
	t.set_stylebox("grabber_area", "HSlider", _sb(C_GOLD, C_GOLD_L, 0, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _sb(C_GOLD_L, C_GOLD_L, 0, 0))

	# --- ProgressBar (np. głośność/poziomy) ---
	t.set_stylebox("background", "ProgressBar", _sb(C_INNER, C_WOOD_D, 1, 0))
	t.set_stylebox("fill", "ProgressBar", _sb(C_GOLD, C_GOLD, 0, 0))
	t.set_color("font_color", "ProgressBar", C_TEXT)

	# --- TabBar (zakładki ustawień) ---
	t.set_stylebox("tab_selected", "TabBar", _sb(C_WOOD_L, C_GOLD_L, 2, 6))
	t.set_stylebox("tab_unselected", "TabBar", _sb(C_WOOD_D, C_WOOD, 2, 6))
	t.set_stylebox("tab_hovered", "TabBar", _sb(C_WOOD, C_GOLD, 2, 6))
	t.set_color("font_selected_color", "TabBar", C_GOLD_L)
	t.set_color("font_unselected_color", "TabBar", C_TEXT_DIM)

	DirAccess.make_dir_recursive_absolute("res://data/ui")   # ResourceSaver nie tworzy katalogów
	var err := ResourceSaver.save(t, OUT_PATH)
	if err == OK:
		print("[THEME] zapisano motyw drewno-złoto -> ", OUT_PATH)
	else:
		printerr("[THEME] BŁĄD zapisu (%d)" % err)
	get_tree().quit(0 if err == OK else 1)


func _sb(bg: Color, border_col: Color, border_w: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(0)            # pixel-art: KANCIASTE rogi
	s.set_border_width_all(border_w)
	s.border_color = border_col
	s.set_content_margin_all(float(pad))
	return s
