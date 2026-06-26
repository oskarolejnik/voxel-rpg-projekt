extends CanvasLayer
## MainMenu.gd — MENU GLOWNE (ETAP 8 polish). Nakladka startowa w Main: gra rusza ZA menu (spauzowana),
## a "Nowa gra"/"Kontynuuj" chowa menu i oddaje sterowanie. Dzieki temu NIE zmieniamy sceny startowej
## (Main.tscn zostaje) — caly przeplyw Etapow 0-7 (spawn/HUD/co-op/dungeony) dziala bez przepisania.
##
## Pozycje:
##   - Nowa gra      -> start_new_game (Main: czysty start, kursor zlapany, gra odpauzowana)
##   - Kontynuuj     -> continue_game (widoczne tylko gdy istnieje zapis postaci — SaveManager)
##   - Ustawienia    -> wbudowany SettingsMenu (grafika preset + glosnosc + mysz)
##   - Wyjscie       -> zamkniecie gry (z zapisem ustawien)
##
## Spojnosc z HUD: ten sam jezyk (PL), ciemne tlo, czytelne duze przyciski. Audio: muzyka "menu"
## (jesli plik CC0 wrzucony — inaczej cisza) + klik UI.
##
## SP-SAFETY: menu nie dotyka logiki gry/sieci; tylko pauza + widocznosc + sygnaly do Main.

const SettingsMenuScript := preload("res://src/SettingsMenu.gd")

signal new_game_requested
signal continue_requested
signal multiplayer_requested   # „Multiplayer (Co-op)" — Main pokazuje LobbyUI (Host/Join)

var _root: Control
var _buttons_box: VBoxContainer
var _continue_btn: Button
var _settings: Control
var _has_save: bool = false


func _ready() -> void:
	layer = 50                                   # nad HUD/lobby, pod SettingsMenu (warstwa wewn.)
	process_mode = Node.PROCESS_MODE_ALWAYS      # widoczne i klikalne gdy gra spauzowana
	_has_save = _save_exists()
	_build_ui()
	# Pokaz menu = spauzuj gre pod spodem (gracz nie biega, gdy patrzy w menu).
	show_menu()
	# Muzyka menu (no-op gdy brak pliku CC0).
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_music"):
		am.play_music(&"menu")


# ============================================================================
#  BUDOWA UI
# ============================================================================
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Tlo (ciemny gradient-lite: jeden ciemny ColorRect, czytelne i tanie).
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vb)

	var title := Label.new()
	title.text = "VOXEL RPG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.96, 0.85, 0.52))   # złoty — spójnie z motywem/HUD
	title.add_theme_color_override("font_outline_color", Color(0.13, 0.09, 0.05, 0.9))
	title.add_theme_constant_override("outline_size", 6)
	vb.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "vertical slice"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.6, 0.7, 0.85)
	vb.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 20.0)
	vb.add_child(spacer)

	_buttons_box = VBoxContainer.new()
	_buttons_box.add_theme_constant_override("separation", 10)
	vb.add_child(_buttons_box)

	_add_menu_button(_buttons_box, "Nowa gra", _on_new_game)
	_continue_btn = _add_menu_button(_buttons_box, "Kontynuuj", _on_continue)
	_continue_btn.disabled = not _has_save
	_continue_btn.visible = _has_save
	_add_menu_button(_buttons_box, "Multiplayer (Co-op)", _on_multiplayer)
	_add_menu_button(_buttons_box, "Ustawienia", _on_settings)
	_add_menu_button(_buttons_box, "Wyjscie", _on_quit)

	# Wbudowany ekran ustawien (ukryty do czasu klikniecia "Ustawienia").
	_settings = SettingsMenuScript.new()
	_settings.visible = false
	_root.add_child(_settings)
	_settings.closed.connect(_on_settings_closed)


func _add_menu_button(parent: VBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280.0, 48.0)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# ============================================================================
#  POKAZ / UKRYJ (pauza gry pod spodem)
# ============================================================================
func show_menu() -> void:
	visible = true
	_set_paused(true)
	# Kursor widoczny w menu (gra moze go lapac).
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_menu() -> void:
	visible = false
	if _settings != null:
		_settings.visible = false
	_set_paused(false)


func _set_paused(p: bool) -> void:
	if GameState != null and GameState.has_method("set_paused"):
		GameState.set_paused(p)
	else:
		get_tree().paused = p


# ============================================================================
#  CALLBACKI POZYCJI MENU
# ============================================================================
func _on_new_game() -> void:
	_click()
	hide_menu()
	# Sterowanie wraca do gracza (kursor zlapany).
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	new_game_requested.emit()


func _on_continue() -> void:
	_click()
	hide_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	continue_requested.emit()


## Multiplayer: NIE chowamy menu ani nie odpauzowujemy — Main pokazuje LobbyUI (Host/Join) NAD menu,
## kursor zostaje widoczny. Wejście do gry następuje dopiero po nawiązaniu sesji (Main._on_session_started).
func _on_multiplayer() -> void:
	_click()
	multiplayer_requested.emit()


func _on_settings() -> void:
	_click()
	if _settings != null:
		_buttons_box.get_parent().visible = false   # schowaj pozycje menu pod ekranem ustawien
		_settings.visible = true
		if _settings.has_method("_refresh_from_settings"):
			_settings._refresh_from_settings()


func _on_settings_closed() -> void:
	if _settings != null:
		_settings.visible = false
	# Przywroc widocznosc pozycji menu.
	if _buttons_box != null:
		_buttons_box.get_parent().visible = true


func _on_quit() -> void:
	_click()
	if GameSettings != null:
		GameSettings.save_settings()
	get_tree().quit()


# ============================================================================
#  Helpery
# ============================================================================
func _save_exists() -> bool:
	# Kontynuuj dostepne gdy istnieje zapis postaci. SaveManager.CHAR_PATH (user://saves/character.json).
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and "CHAR_PATH" in sm:
		return FileAccess.file_exists(sm.CHAR_PATH)
	return FileAccess.file_exists("user://saves/character.json")


func _click() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.play_sfx(&"ui_click")
