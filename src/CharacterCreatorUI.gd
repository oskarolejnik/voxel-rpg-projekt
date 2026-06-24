extends Control
## CharacterCreatorUI.gd — EKRAN kreatora postaci (GDD sek.6). Spina warstwę danych (ContentDB +
## CharacterCreator) z UI: listy ras/klas/pochodzeń, pole imienia + Losuj, podsumowanie, Stwórz ->
## CharacterDefinition (walidacja) + zapis JSON (user://characters/, GDD sek.9). Standalone — nie
## ingeruje we flow gry/testów. Po utworzeniu emituje character_created(def).
## (Podgląd 3D postaci dochodzi w osobnym kroku — tu szkielet UI + logika.)

signal character_created(def)

const COL_BG := Color(0.06, 0.07, 0.10, 1.0)
const COL_PANEL := Color(0.10, 0.11, 0.15, 0.95)
const COL_SEL := Color(0.95, 0.78, 0.35)        # podświetlenie wybranego (złoty akcent jak HUD)
const COL_DIM := Color(0.78, 0.82, 0.90)

var _cc := CharacterCreator.new()
var _name_edit: LineEdit
var _summary: RichTextLabel
var _status: Label
var _race_btns: Dictionary = {}
var _class_btns: Dictionary = {}
var _origin_btns: Dictionary = {}
var _name_seed: int = 1
# Podgląd 3D (voxelowy manekin w SubViewport — reaguje kolorem na rasę/klasę, obraca się).
var _preview_vp: SubViewport
var _preview_rig: Node3D
var _skin_mat: StandardMaterial3D
var _tunic_mat: StandardMaterial3D
var _legs_mat: StandardMaterial3D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24.0; root.offset_top = 18.0; root.offset_right = -24.0; root.offset_bottom = -18.0
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var title := Label.new()
	title.text = "TWORZENIE POSTACI"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COL_SEL)
	root.add_child(title)

	# Środek: [3 kolumny wyboru] po lewej + [podgląd 3D] po prawej.
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 16)
	root.add_child(mid)
	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_stretch_ratio = 2.3
	cols.add_theme_constant_override("separation", 16)
	mid.add_child(cols)
	cols.add_child(_make_column("RASA", ContentDB.races(), _on_pick_race, _race_btns))
	cols.add_child(_make_column("KLASA", ContentDB.classes(), _on_pick_class, _class_btns))
	cols.add_child(_make_column("POCHODZENIE", ContentDB.origins(), _on_pick_origin, _origin_btns))
	mid.add_child(_build_preview())

	# Dolny pasek: imię + Losuj + Stwórz.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)
	var nlab := Label.new(); nlab.text = "Imię:"; nlab.add_theme_color_override("font_color", COL_DIM)
	bottom.add_child(nlab)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(220.0, 0.0)
	_name_edit.placeholder_text = "wpisz lub wylosuj…"
	_name_edit.text_changed.connect(func(t: String) -> void: _cc.set_name(t); _refresh())
	bottom.add_child(_name_edit)
	var rnd := Button.new(); rnd.text = "Losuj"
	rnd.pressed.connect(_on_random_name)
	bottom.add_child(rnd)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var create := Button.new(); create.text = "Stwórz postać"
	create.add_theme_font_size_override("font_size", 18)
	create.pressed.connect(_on_create)
	bottom.add_child(create)

	# Podsumowanie + status.
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.custom_minimum_size = Vector2(0.0, 72.0)
	_summary.add_theme_stylebox_override("normal", _panel_style())
	root.add_child(_summary)
	_status = Label.new()
	_status.add_theme_color_override("font_color", COL_DIM)
	root.add_child(_status)

	_refresh()

	# Tryb zrzutu: auto-wybór + screenshot (CREATOR_SHOT=1, okno).
	if OS.get_environment("CREATOR_SHOT") != "":
		await _auto_shot()


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8.0)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	return sb


# Kolumna: nagłówek + przewijalna lista przycisków (display_name), callback(id).
func _make_column(header: String, items: Array, cb: Callable, into: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var h := Label.new(); h.text = header
	h.add_theme_font_size_override("font_size", 16)
	h.add_theme_color_override("font_color", COL_SEL)
	box.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_theme_stylebox_override("panel", _panel_style())
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for it in items:
		var b := Button.new()
		b.text = String(it.display_name)
		b.tooltip_text = String(it.get("lore")) if it.get("lore") != null else ""
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var rid: StringName = it.id
		b.pressed.connect(func() -> void: cb.call(rid))
		list.add_child(b)
		into[rid] = b
	return box


func _highlight(btns: Dictionary, sel: StringName) -> void:
	for id in btns:
		(btns[id] as Button).modulate = COL_SEL if id == sel else Color.WHITE


func _on_pick_race(id: StringName) -> void:
	_cc.set_race(id)
	_highlight(_race_btns, id)
	_update_preview()
	_refresh()

func _on_pick_class(id: StringName) -> void:
	_cc.set_class(id)
	_highlight(_class_btns, id)
	_update_preview()
	_refresh()

func _on_pick_origin(id: StringName) -> void:
	_cc.set_origin(id)
	_highlight(_origin_btns, id)
	_refresh()

func _on_random_name() -> void:
	if _cc.def.race_id == &"":
		_status.text = "Najpierw wybierz rasę, by wylosować pasujące imię."
		return
	_name_seed += 1
	var nm := _cc.random_name(_cc.def.race_id, _name_seed * 7919)
	_name_edit.text = nm
	_cc.set_name(nm)
	_refresh()

func _on_create() -> void:
	_cc.set_name(_name_edit.text)
	var def := _cc.finalize()
	if def == null:
		var miss: Array[String] = []
		if def == null and _cc.def.race_id == &"": miss.append("rasa")
		if _cc.def.class_id == &"": miss.append("klasa")
		if _cc.def.char_name.strip_edges() == "": miss.append("imię")
		_status.text = "Uzupełnij: " + ", ".join(miss)
		return
	var path := _save(def)
	_status.text = "Utworzono postać: %s  →  %s" % [def.full_name(), path]
	# AUDYT (namespace): wybór klasy z kreatora PROPAGUJE do progresji. def.class_id to kanoniczne id
	# ContentDB (polskie) — to samo, którego używają SkillDB.tree() i ClassResourceComponent.build_for(),
	# więc wybrana klasa od razu dostaje swoje drzewko + właściwy pasek zasobu (dawniej choice ginął).
	if GameState != null and def != null:
		GameState.class_id = def.class_id
	character_created.emit(def)

func _save(def: CharacterDefinition) -> String:
	DirAccess.make_dir_recursive_absolute("user://characters")
	var safe := def.char_name.strip_edges().to_lower().replace(" ", "_")
	if safe == "": safe = "postac"
	var path := "user://characters/%s.json" % safe
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(def.to_dict(), "  "))
		f.close()
	return path

func _refresh() -> void:
	var rid := _cc.def.race_id
	var cid := _cc.def.class_id
	var oid := _cc.def.origin_id
	var rn := ContentDB.get_race(rid)
	var cn := ContentDB.class_by_id(cid)
	var on := ContentDB.get_origin(oid)
	var rt := rn.display_name if rn != null else "—"
	var ct := cn.display_name if cn != null else "—"
	var ot := on.display_name if on != null else "(brak)"
	var role := String(cn.role) if cn != null else ""
	var nm := _cc.def.char_name.strip_edges()
	_summary.text = "[b]Rasa:[/b] %s    [b]Klasa:[/b] %s %s   [b]Pochodzenie:[/b] %s\n[b]Imię:[/b] %s" % [
		rt, ct, ("(" + role + ")" if role != "" else ""), ot, (nm if nm != "" else "—")]


# ============================================================================
#  PODGLĄD 3D (SubViewport + voxelowy manekin; reaguje kolorem na rasę/klasę, obraca się)
# ============================================================================
func _build_preview() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_stretch_ratio = 1.0
	var h := Label.new(); h.text = "PODGLĄD"
	h.add_theme_font_size_override("font_size", 16)
	h.add_theme_color_override("font_color", COL_SEL)
	box.add_child(h)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _panel_style())
	box.add_child(frame)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(svc)
	_preview_vp = SubViewport.new()
	_preview_vp.transparent_bg = true
	_preview_vp.own_world_3d = true
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(_preview_vp)

	# Środowisko (ambient, by manekin nie był czarny w osobnym World3D).
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.62)
	env.ambient_light_energy = 1.0
	we.environment = env
	_preview_vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -34.0, 0.0)
	light.light_energy = 1.2
	_preview_vp.add_child(light)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.05, 3.1)
	cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	_preview_vp.add_child(cam)

	_preview_rig = Node3D.new()
	_preview_vp.add_child(_preview_rig)
	_build_mannequin()
	return box

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m

func _build_mannequin() -> void:
	_skin_mat = _mat(Color(0.92, 0.76, 0.60))
	_tunic_mat = _mat(Color(0.30, 0.45, 0.75))
	_legs_mat = _mat(Color(0.22, 0.20, 0.26))
	# (mesh_size, pozycja, materiał)
	_box(Vector3(0.42, 0.42, 0.42), Vector3(0.0, 1.55, 0.0), _skin_mat)     # głowa
	_box(Vector3(0.54, 0.62, 0.32), Vector3(0.0, 1.05, 0.0), _tunic_mat)    # tułów
	_box(Vector3(0.16, 0.52, 0.16), Vector3(-0.36, 1.05, 0.0), _skin_mat)   # ręka L
	_box(Vector3(0.16, 0.52, 0.16), Vector3(0.36, 1.05, 0.0), _skin_mat)    # ręka P
	_box(Vector3(0.18, 0.62, 0.18), Vector3(-0.14, 0.42, 0.0), _legs_mat)   # noga L
	_box(Vector3(0.18, 0.62, 0.18), Vector3(0.14, 0.42, 0.0), _legs_mat)    # noga P

func _box(sz: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	_preview_rig.add_child(mi)

# Skóra wg rasy, tunika wg klasy (proste mapy — pełna personalizacja wyglądu osobno).
func _update_preview() -> void:
	if _skin_mat == null:
		return
	match _cc.def.race_id:
		&"sylvani": _skin_mat.albedo_color = Color(0.86, 0.82, 0.66)
		&"grimhold": _skin_mat.albedo_color = Color(0.80, 0.62, 0.48)
		&"embrani": _skin_mat.albedo_color = Color(0.85, 0.55, 0.45)
		&"orguni": _skin_mat.albedo_color = Color(0.55, 0.70, 0.50)
		&"feruni": _skin_mat.albedo_color = Color(0.78, 0.66, 0.52)
		_: _skin_mat.albedo_color = Color(0.92, 0.76, 0.60)
	var cn := ContentDB.class_by_id(_cc.def.class_id)
	if cn != null:
		match cn.role:
			&"tank": _tunic_mat.albedo_color = Color(0.55, 0.55, 0.60)
			&"healer": _tunic_mat.albedo_color = Color(0.85, 0.82, 0.55)
			&"support": _tunic_mat.albedo_color = Color(0.80, 0.70, 0.35)
			&"ranged_dps": _tunic_mat.albedo_color = Color(0.30, 0.55, 0.40)
			_: _tunic_mat.albedo_color = Color(0.65, 0.30, 0.28)   # melee_dps

func _process(delta: float) -> void:
	if _preview_rig != null:
		_preview_rig.rotate_y(delta * 0.7)   # powolny obrót prezentacyjny


# --- Zrzut ekranu (CREATOR_SHOT) ---
func _auto_shot() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	await get_tree().process_frame
	_on_pick_race(&"sylvani")
	_on_pick_class(&"lucznik")
	_on_pick_origin(&"lowca")
	_on_random_name()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/oskar/Downloads/voxel-rpg/_creator_shot.png")
	get_tree().quit()
