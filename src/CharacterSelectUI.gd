extends CanvasLayer
## CharacterSelectUI.gd — ROSTER: ekran wyboru postaci SPOŚRÓD zapisanych (każda = własny świat/seed).
## Pokazywany z menu („Kontynuuj"). Lista z SaveManager.list_characters(); klik -> character_chosen(sd);
## „Nowa postać" -> new_requested (kreator); „Wstecz" -> cancelled (menu). Nakładka CanvasLayer (jak kreator),
## PROCESS_MODE_ALWAYS (klikalna mimo pauzy menu). Motyw drewno-złoto z UITheme.

signal character_chosen(sd)
signal new_requested
signal cancelled

const COL_BG := Color(0.06, 0.07, 0.10, 0.97)
const COL_GOLD := Color(0.95, 0.78, 0.35)
const COL_DIM := Color(0.78, 0.82, 0.90)


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.get_theme()   # wspólny motyw drewno-złoto (class_name UITheme)
	add_child(root)

	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(420.0, 0.0)
	center.add_child(col)

	var title := Label.new()
	title.text = "WYBIERZ POSTAĆ"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COL_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var chars: Array = SaveManager.list_characters() if SaveManager != null else []
	if chars.is_empty():
		var none := Label.new()
		none.text = "(brak zapisanych postaci — stwórz nową)"
		none.add_theme_color_override("font_color", COL_DIM)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(none)
	for sd in chars:
		var b := Button.new()
		var nm: String = sd.char_name if sd.char_name != "" else "Bezimienny"
		b.text = "%s   —   %s   (poz. %d)" % [nm, String(sd.class_id), sd.level]
		b.custom_minimum_size = Vector2(420.0, 40.0)
		b.pressed.connect(character_chosen.emit.bind(sd))   # bind => kliknięcie wysyła TĘ postać
		col.add_child(b)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	col.add_child(spacer)

	var nb := Button.new()
	nb.text = "+ Nowa postać"
	nb.custom_minimum_size = Vector2(420.0, 40.0)
	nb.pressed.connect(new_requested.emit)
	col.add_child(nb)

	var back := Button.new()
	back.text = "Wstecz"
	back.custom_minimum_size = Vector2(420.0, 36.0)
	back.pressed.connect(cancelled.emit)
	col.add_child(back)
