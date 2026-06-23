extends Control
## SettingsMenu.gd — ETAP 8. Panel USTAWIEN (grafika preset + suwaki glosnosci + czulosc myszy).
## Reuzywalny: osadzany w MainMenu i w PauseMenu (ten sam kod, jedno zrodlo UI ustawien).
##
## Wszystko budowane W KODZIE (Control + kontenery), spojnie z reszta UI (HUD/LobbyUI bez .tscn).
## Czyta/zapisuje przez GameSettings (autoload). Zmiana presetu grafiki emituje
## GameSettings.graphics_preset_changed -> Main aplikuje na zywych wezlach (Environment/VoxelWorld).
##
## Sygnal closed — rodzic (MainMenu/PauseMenu) chowa panel i wraca do swojego ekranu.

signal closed

var _master_slider: HSlider
var _sfx_slider: HSlider
var _music_slider: HSlider
var _mouse_slider: HSlider
var _preset_option: OptionButton
var _master_val: Label
var _sfx_val: Label
var _music_val: Label
var _mouse_val: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # panel lapie klikniecia (nie przebijaja do gry)
	_build_ui()
	_refresh_from_settings()


func _build_ui() -> void:
	# Polprzezroczyste tlo, by panel byl czytelny nad gra/menu.
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440.0, 0.0)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "USTAWIENIA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	vb.add_child(title)

	# --- GRAFIKA: preset Low/High ---
	vb.add_child(_section_label("Grafika"))
	var gfx_row := HBoxContainer.new()
	gfx_row.add_theme_constant_override("separation", 12)
	var gfx_lbl := Label.new()
	gfx_lbl.text = "Jakosc"
	gfx_lbl.custom_minimum_size = Vector2(120.0, 0.0)
	gfx_row.add_child(gfx_lbl)
	_preset_option = OptionButton.new()
	_preset_option.add_item("Niska (Low)", GameSettings.GraphicsPreset.LOW)
	_preset_option.add_item("Wysoka (High)", GameSettings.GraphicsPreset.HIGH)
	_preset_option.custom_minimum_size = Vector2(260.0, 0.0)
	_preset_option.item_selected.connect(_on_preset_selected)
	gfx_row.add_child(_preset_option)
	vb.add_child(gfx_row)

	var gfx_hint := Label.new()
	gfx_hint.text = "Low: zalecane na 4 GB VRAM. High: god-rays/GI/odbicia (mocniejszy GPU)."
	gfx_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gfx_hint.modulate = Color(0.7, 0.76, 0.85)
	gfx_hint.add_theme_font_size_override("font_size", 12)
	vb.add_child(gfx_hint)

	# --- DZWIEK: 3 suwaki ---
	vb.add_child(_section_label("Dzwiek"))
	_master_slider = _add_slider(vb, "Glosnosc glowna")
	_master_val = _slider_value_label(_master_slider)
	_master_slider.value_changed.connect(_on_master_changed)
	_sfx_slider = _add_slider(vb, "Efekty (SFX)")
	_sfx_val = _slider_value_label(_sfx_slider)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_music_slider = _add_slider(vb, "Muzyka")
	_music_val = _slider_value_label(_music_slider)
	_music_slider.value_changed.connect(_on_music_changed)

	# --- MYSZ: czulosc ---
	vb.add_child(_section_label("Sterowanie"))
	_mouse_slider = _add_slider(vb, "Czulosc myszy")
	_mouse_val = _slider_value_label(_mouse_slider)
	_mouse_slider.value_changed.connect(_on_mouse_changed)

	# --- Powrot ---
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	vb.add_child(spacer)
	var back := Button.new()
	back.text = "Powrot"
	back.custom_minimum_size = Vector2(0.0, 40.0)
	back.pressed.connect(_on_back)
	vb.add_child(back)


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.modulate = Color(1.0, 0.9, 0.5)
	return l


## Wiersz: etykieta + suwak 0..1 + (osobno) wartosc %. Zwraca suwak.
func _add_slider(parent: VBoxContainer, label_text: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(160.0, 0.0)
	row.add_child(lbl)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.custom_minimum_size = Vector2(200.0, 0.0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	var val := Label.new()
	val.text = "100%"
	val.custom_minimum_size = Vector2(48.0, 0.0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	s.set_meta("val_label", val)
	parent.add_child(row)
	return s


func _slider_value_label(slider: HSlider) -> Label:
	return slider.get_meta("val_label") as Label


# ============================================================================
#  SYNCHRONIZACJA Z GameSettings
# ============================================================================
func _refresh_from_settings() -> void:
	if GameSettings == null:
		return
	_preset_option.select(int(GameSettings.graphics_preset))
	_set_slider(_master_slider, GameSettings.master_volume)
	_set_slider(_sfx_slider, GameSettings.sfx_volume)
	_set_slider(_music_slider, GameSettings.music_volume)
	_set_slider(_mouse_slider, GameSettings.mouse_sensitivity_normalized())


## Ustawia suwak bez wzbudzania value_changed (zeby refresh nie zapisywal/aplikowal w kolko).
func _set_slider(slider: HSlider, v: float) -> void:
	slider.set_value_no_signal(v)
	_update_val_label(slider, v)


func _update_val_label(slider: HSlider, v: float) -> void:
	var lbl := _slider_value_label(slider)
	if lbl != null:
		lbl.text = "%d%%" % int(round(v * 100.0))


# ============================================================================
#  CALLBACKI UI -> GameSettings (settery zapisuja + aplikuja)
# ============================================================================
func _on_preset_selected(idx: int) -> void:
	_click()
	if GameSettings != null:
		GameSettings.set_graphics_preset(idx as GameSettings.GraphicsPreset)
		GameSettings.save_settings()


func _on_master_changed(v: float) -> void:
	_update_val_label(_master_slider, v)
	if GameSettings != null:
		GameSettings.set_master_volume(v)


func _on_sfx_changed(v: float) -> void:
	_update_val_label(_sfx_slider, v)
	if GameSettings != null:
		GameSettings.set_sfx_volume(v)
		# Krotki podglad dzwieku SFX przy puszczeniu suwaka (jesli plik jest) — natychmiastowy feedback.
		if AudioManager != null and AudioManager.has_method("play_sfx"):
			AudioManager.play_sfx(&"ui_click")


func _on_music_changed(v: float) -> void:
	_update_val_label(_music_slider, v)
	if GameSettings != null:
		GameSettings.set_music_volume(v)


func _on_mouse_changed(v: float) -> void:
	# Suwak 0..1 -> mnoznik MIN..MAX (GameSettings mapuje). Etykieta pokazuje %, bo to relatywne.
	_update_val_label(_mouse_slider, v)
	if GameSettings != null:
		GameSettings.set_mouse_sensitivity_normalized(v)


func _on_back() -> void:
	_click()
	if GameSettings != null:
		GameSettings.save_settings()
	closed.emit()


func _click() -> void:
	if AudioManager != null and AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx(&"ui_click")
