class_name UITheme
extends RefCounted
## UITheme.gd — wspólny motyw UI „drewno-złoto" budowany W KODZIE (zero zewnętrznych assetów).
## Spina identyczność wizualną HUD-u (rysowanego ręcznie w HUD.gd) z panelami menu (ekwipunek,
## drzewko umiejętności), które wcześniej wpadały w domyślną szarość silnika — najbardziej rażące
## złamanie identyczności UI. Paleta = DOKŁADNIE te same kolory co HUD.gd (drewno + złoto + wnętrze).
##
## Użycie: dowolny Control.theme = UITheme.get_theme(). Motyw jest cache'owany w static var
## (budowany raz na proces) — kolejne wywołania zwracają ten sam zasób.
##
## Stylizuje: PanelContainer/Panel (ciemne drewno + ~3px złota ramka, zaokrąglenie ~6, miękki cień),
## Label (czarny outline dla czytelności nad światłem), Button (ta sama ramka + warianty hover/pressed).

# Paleta — lustro stałych z HUD.gd (drewno + złoto + wnętrza). Trzymane tu lokalnie, bo HUD.gd nie ma
# class_name (Main instancjonuje go przez preload), więc nie da się ich zaimportować jako stałych typu.
const C_OUTLINE: Color = Color8(34, 22, 14)
const C_WOOD_D: Color = Color8(92, 56, 28)
const C_WOOD: Color = Color8(132, 84, 42)
const C_WOOD_L: Color = Color8(176, 122, 64)
const C_GOLD: Color = Color8(214, 162, 70)
const C_GOLD_L: Color = Color8(246, 216, 132)
const C_INNER: Color = Color8(26, 22, 30)
const C_INNER_HI: Color = Color8(44, 38, 50)

# Cache motywu (budowany raz na proces). static var jest stabilne w Godot 4.x.
static var _theme: Theme = null


## Zwraca współdzielony motyw drewno-złoto (cache'owany). Buduje go przy pierwszym wywołaniu.
static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme


# ============================================================================
#  BUDOWA MOTYWU
# ============================================================================
static func _build_theme() -> Theme:
	var t := Theme.new()

	# --- PanelContainer + Panel: ciemne wnętrze, złota ramka, zaokrąglenie, miękki cień ---
	var panel_sb := _panel_box()
	t.set_stylebox("panel", "PanelContainer", panel_sb)
	t.set_stylebox("panel", "Panel", panel_sb)

	# --- Label: czarny outline dla czytelności nad jasnym światem ---
	t.set_color("font_color", "Label", Color8(244, 236, 220))
	t.set_color("font_outline_color", "Label", Color(0.0, 0.0, 0.0, 1.0))
	t.set_constant("outline_size", "Label", 4)

	# --- Button: ta sama oprawa drewno-złoto + warianty hover/pressed/disabled ---
	t.set_stylebox("normal", "Button", _button_box(C_WOOD_D, C_GOLD, 2))
	t.set_stylebox("hover", "Button", _button_box(C_WOOD, C_GOLD_L, 2))
	t.set_stylebox("pressed", "Button", _button_box(C_OUTLINE, C_GOLD, 3))
	t.set_stylebox("disabled", "Button", _button_box(Color8(54, 44, 36), C_WOOD, 2))
	t.set_stylebox("focus", "Button", _button_box(C_WOOD_D, C_GOLD_L, 2))
	t.set_color("font_color", "Button", C_GOLD_L)
	t.set_color("font_hover_color", "Button", Color8(255, 244, 210))
	t.set_color("font_pressed_color", "Button", C_GOLD)
	t.set_color("font_disabled_color", "Button", Color8(150, 130, 100))
	t.set_color("font_outline_color", "Button", Color(0.0, 0.0, 0.0, 1.0))
	t.set_constant("outline_size", "Button", 3)

	return t


# Główna „skrzynia" panelu: ciemne drewniane wnętrze, ~3px złota ramka, zaokrąglone rogi, miękki cień.
static func _panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_INNER
	sb.border_color = C_GOLD
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	# Margines treści — odsuwa zawartość od złotej ramki (oddech).
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	# Miękki cień rzucany pod panel (głębia, premium feel).
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0.0, 4.0)
	return sb


# Oprawa przycisku: drewniane tło + złota ramka (param), zaokrąglenie, margines treści.
static func _button_box(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb
