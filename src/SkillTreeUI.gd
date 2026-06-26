class_name SkillTreeUI
extends CanvasLayer
## SkillTreeUI.gd — ekran drzewka pasywow (ETAP 3, GDD 10/11). Budowane W KODZIE (Control), bez .tscn.
##
## - Toggle klawiszem K (osobny od walki i ekwipunku; nie ruszamy mapy input gracza).
## - Rysuje wezly (PassiveNodeResource) wg layoutu drzewka + LINIE prerekwizytow (requires).
## - Klik LMB w wezel: alokuj (jesli mozna). Klik PPM: cofnij (jesli nikt nie zalezy).
## - Licznik wolnych punktow + przycisk RESPEC (zwrot punktow za Orby).
## - Kolory wezlow: zielony=wziety, bialy=mozna wziac, szary=zablokowany (prereq/poziom/punkty),
##   zloty obrys=keystone.
##
## Wpiecie: Main tworzy SkillTreeUI i wola bind_player(player). UI czyta SkillTreeComponent +
## LevelComponent z gracza i wola jego publiczne API (allocate_node/deallocate_node/respec_tree).

const NODE_R: float = 26.0          # promien wezla (px)
const PANEL_W: float = 640.0
const PANEL_H: float = 560.0

var _player: Node = null
var _tree_comp: SkillTreeComponent = null
var _level_comp: LevelComponent = null

var _open: bool = false
var _mouse_mode_before: int = Input.MOUSE_MODE_CAPTURED

var _root: Control
var _graph: Control                 # kontener wezlow/linii (srodek panelu)
var _points_label: Label
var _info_label: Label
var _respec_btn: Button
var _node_buttons: Dictionary = {}  # StringName(id) -> Button
var _respec_index: int = 0          # ile razy juz respecowano (koszt schodkowy)


func _ready() -> void:
	_build_panel()
	_set_open(false)


## Wpiecie gracza: pobiera komponenty progresji i buduje graf wezlow.
func bind_player(player: Node) -> void:
	_player = player
	if player == null:
		return
	if player.has_method("skill_tree_component"):
		_tree_comp = player.skill_tree_component()
	if player.has_method("level_component"):
		_level_comp = player.level_component()
	# Odswiezaj licznik punktow na zmiane alokacji/poziomu.
	if _tree_comp != null and not _tree_comp.allocation_changed.is_connected(_on_allocation_changed):
		_tree_comp.allocation_changed.connect(_on_allocation_changed)
		_tree_comp.respec_done.connect(_on_respec_done)
	if _level_comp != null and not _level_comp.level_changed.is_connected(_on_level_changed):
		_level_comp.level_changed.connect(_on_level_changed)
	_build_graph()
	_refresh()


# ============================================================================
#  INPUT (toggle K)
# ============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_K:
		_set_open(not _open)
		get_viewport().set_input_as_handled()
		return
	if _open and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _set_open(value: bool) -> void:
	if value == _open:
		return
	# Jeden autorytet kursora (Etap 2 review #5): gdy INNY panel (np. ekwipunek) juz lapie input,
	# NIE otwieramy drzewka rownolegle i NIE ruszamy mouse_mode — inaczej dwa UI biłyby sie o kursor
	# i po zamknieciu jednego zostawalby zly stan (VISIBLE/CAPTURED). Headless tego nie wykrywa.
	if value and GameState != null and GameState.ui_capturing_input and not _open:
		return
	_open = value
	_root.visible = value
	if GameState != null:
		GameState.ui_capturing_input = value
	if value:
		_mouse_mode_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh()
	else:
		Input.mouse_mode = _mouse_mode_before


# ============================================================================
#  BUDOWA PANELU
# ============================================================================
func _build_panel() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	_root.theme = UITheme.get_theme()                # wspólny motyw drewno-złoto (koniec szarości silnika)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := ColorRect.new()
	panel.color = Color(0.08, 0.09, 0.12, 0.96)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.size = Vector2(PANEL_W, PANEL_H)
	panel.position = -panel.size * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)

	var title := Label.new()
	title.text = "DRZEWKO UMIEJETNOSCI"
	title.position = Vector2(16.0, 10.0)
	panel.add_child(title)

	_points_label = Label.new()
	_points_label.text = "Punkty: 0"
	_points_label.position = Vector2(16.0, 34.0)
	_points_label.modulate = Color(1.0, 0.9, 0.3)
	panel.add_child(_points_label)

	_info_label = Label.new()
	_info_label.text = "LMB: alokuj   PPM: cofnij   K: zamknij"
	_info_label.position = Vector2(16.0, PANEL_H - 30.0)
	_info_label.modulate = Color(0.75, 0.78, 0.85)
	panel.add_child(_info_label)

	_respec_btn = Button.new()
	_respec_btn.text = "RESPEC (Orby)"
	_respec_btn.position = Vector2(PANEL_W - 160.0, 30.0)
	_respec_btn.size = Vector2(144.0, 30.0)
	_respec_btn.pressed.connect(_on_respec_pressed)
	panel.add_child(_respec_btn)

	# Kontener grafu (srodek panelu). Wezly pozycjonujemy wzgledem jego srodka.
	_graph = Control.new()
	_graph.position = Vector2(PANEL_W * 0.5, 150.0)
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_graph)


# Buduje wezly (przyciski) + rysunek linii. Pozycje z tree.layout (Vector2 wzgledem srodka).
func _build_graph() -> void:
	for c in _graph.get_children():
		c.queue_free()
	_node_buttons.clear()
	if _tree_comp == null or _tree_comp.tree == null:
		return
	var tree_res := _tree_comp.tree

	# Warstwa linii (Control z _draw) POD wezlami.
	var lines := _LineLayer.new()
	lines.tree_res = tree_res
	lines.tree_comp = _tree_comp
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_graph.add_child(lines)

	for n in tree_res.nodes:
		if n == null:
			continue
		var pos: Vector2 = tree_res.layout.get(n.id, Vector2.ZERO)
		var btn := Button.new()
		btn.toggle_mode = false
		btn.size = Vector2(NODE_R * 2.0, NODE_R * 2.0)
		btn.position = pos - Vector2(NODE_R, NODE_R)
		btn.text = _short_label(n.display_name)
		btn.tooltip_text = _node_tooltip(n)
		btn.focus_mode = Control.FOCUS_NONE
		btn.gui_input.connect(_on_node_gui_input.bind(n.id))
		_graph.add_child(btn)
		_node_buttons[n.id] = btn


func _short_label(s: String) -> String:
	# Pierwsze litery slow (zwiezle na okraglym przycisku); tooltip ma pelna nazwe.
	var parts := s.split(" ", false)
	var out := ""
	for p in parts:
		if p.length() > 0:
			out += p.substr(0, 1)
	return out.to_upper() if out != "" else "?"


func _node_tooltip(n: PassiveNodeResource) -> String:
	var t := n.display_name
	for m in n.modifiers:
		if m is StatModifier:
			t += "\n  %s %s%.0f%s" % [String(m.stat), ("+" if m.value >= 0 else ""),
				(m.value * 100.0 if m.op != StatModifier.Op.FLAT else m.value),
				("%" if m.op != StatModifier.Op.FLAT else "")]
	if n.is_keystone:
		t += "\n[KEYSTONE]"
	if n.min_level > 1:
		t += "\nWymaga poziomu %d" % n.min_level
	return t


# ============================================================================
#  KLIK W WEZEL — alokuj (LMB) / cofnij (PPM)
# ============================================================================
func _on_node_gui_input(event: InputEvent, node_id: StringName) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if _player == null:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if not _player.allocate_node(node_id):
			var reason := _tree_comp.cannot_allocate_reason(node_id) if _tree_comp != null else ""
			_info_label.text = "Nie mozna: %s" % reason
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if not _player.deallocate_node(node_id):
			_info_label.text = "Nie mozna cofnac (zalezne wezly)"
	_refresh()


func _on_respec_pressed() -> void:
	if _player == null:
		return
	var refunded: int = _player.respec_tree(_respec_index)
	if refunded > 0:
		_respec_index += 1
		_info_label.text = "Respec: zwrocono %d pkt" % refunded
	else:
		var cost := SkillTreeComponent.orb_cost_for(_respec_index)
		_info_label.text = "Respec niemozliwy (koszt %d Orb)" % cost
	_refresh()


# ============================================================================
#  ODSWIEZANIE WIDOKU
# ============================================================================
func _refresh() -> void:
	if _tree_comp == null:
		return
	var pts := _tree_comp.points_left()
	_points_label.text = "Punkty: %d   |   Orby: %d" % [pts, (GameState.orbs if GameState != null else 0)]
	for node_id in _node_buttons:
		var btn: Button = _node_buttons[node_id]
		var allocated := _tree_comp.is_allocated(node_id)
		var n := _tree_comp.node(node_id)
		if allocated:
			btn.modulate = Color(0.4, 0.95, 0.5)        # zielony = wziety
		elif _tree_comp.can_allocate(node_id):
			btn.modulate = Color(1.0, 1.0, 1.0)          # bialy = mozna wziac
		else:
			btn.modulate = Color(0.45, 0.45, 0.5)        # szary = zablokowany
		if n != null and n.is_keystone:
			btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	# Przerysuj linie (kolor wg alokacji).
	for c in _graph.get_children():
		if c is _LineLayer:
			c.queue_redraw()


func _on_allocation_changed(_id: StringName, _alloc: bool, _left: int) -> void:
	_refresh()

func _on_respec_done(_refunded: int, _cost: int) -> void:
	_refresh()

func _on_level_changed(_lv: int, _xp: int, _nx: int) -> void:
	_refresh()


# ============================================================================
#  Warstwa linii prerekwizytow (Control z _draw)
# ============================================================================
class _LineLayer extends Control:
	var tree_res: SkillTreeResource
	var tree_comp: SkillTreeComponent

	func _draw() -> void:
		if tree_res == null:
			return
		for n in tree_res.nodes:
			if n == null:
				continue
			var to: Vector2 = tree_res.layout.get(n.id, Vector2.ZERO)
			for req in n.requires:
				var from: Vector2 = tree_res.layout.get(req, Vector2.ZERO)
				var both := tree_comp != null and tree_comp.is_allocated(n.id) and tree_comp.is_allocated(req)
				var col := Color(0.4, 0.95, 0.5, 0.9) if both else Color(0.5, 0.5, 0.55, 0.6)
				draw_line(from, to, col, 3.0)
