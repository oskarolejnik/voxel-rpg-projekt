extends CanvasLayer
## PauseMenu.gd — ETAP 8. Menu PAUZY: ESC -> pauza (get_tree().paused) + Wznow / Ustawienia /
## Wyjscie do menu glownego. Osadzony w grze (Main). Wysoka warstwa (nad HUD/ekwipunkiem).
##
## INTEGRACJA Z GRACZEM (review-safe): Player.gd tez reaguje na ESC (toggle kursora). Zeby nie
## kolidowac, PauseMenu obsluguje ESC w _unhandled_input i KONSUMUJE zdarzenie
## (get_viewport().set_input_as_handled()) — wtedy Player._unhandled_input juz go nie dostanie.
## Player ma osobny gate (jest_pauza) by nie chodzic/atakowac przy spauzowanej grze.
##
## PAUZA: get_tree().paused = true zatrzymuje fizyke/_process wezlow z PROCESS_MODE_INHERIT. To menu
## ma PROCESS_MODE_ALWAYS (dziala w pauzie). AudioManager tez ALWAYS (muzyka/klik graja w pauzie).
##
## CO-OP: w trybie sieciowym TWARDA pauza calej sceny zatrzymalaby tez zdalnych — wiec gdy
## NetManager.has_network() pauza jest "miekka" (tylko ekran menu + kursor, bez get_tree().paused),
## by nie zamrozic sesji innym graczom. SP: pelna pauza.

signal exit_to_menu_requested

const SettingsMenuScript := preload("res://src/SettingsMenu.gd")

var _root: Control
var _menu_panel: Control
var _settings: Control
var _is_paused: bool = false
var _prev_mouse_mode: int = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	layer = 30                                  # nad HUD (0..10), ekwipunkiem, lobby (20)
	process_mode = Node.PROCESS_MODE_ALWAYS     # menu dziala, gdy gra spauzowana
	_build_ui()
	_set_visible(false)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Przyciemnienie tla.
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	# Panel z przyciskami (wycentrowany).
	_menu_panel = CenterContainer.new()
	_menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_menu_panel)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320.0, 0.0)
	_menu_panel.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "PAUZA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	vb.add_child(title)

	_add_button(vb, "Wznow", _on_resume)
	_add_button(vb, "Ustawienia", _on_settings)
	_add_button(vb, "Wyjscie do menu", _on_exit_to_menu)


func _add_button(parent: VBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, 44.0)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# ============================================================================
#  ESC — toggle pauzy (konsumuje zdarzenie, by Player nie przelaczyl kursora)
# ============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if (event as InputEventKey).physical_keycode != KEY_ESCAPE:
		return
	# Jesli otwarte sa ustawienia — ESC cofa do panelu pauzy, nie odpauzowuje od razu.
	if _settings != null and is_instance_valid(_settings):
		_close_settings()
		get_viewport().set_input_as_handled()
		return
	toggle_pause()
	get_viewport().set_input_as_handled()   # NIE pozwol Player._unhandled_input ruszyc kursora


func toggle_pause() -> void:
	if _is_paused:
		resume()
	else:
		pause()


func is_game_paused() -> bool:
	return _is_paused


func pause() -> void:
	if _is_paused:
		return
	# Nie otwieraj pauzy, gdy widoczne MENU GLOWNE (gra juz "spauzowana" za menu startowym) ani gdy
	# modalne UI (ekwipunek/drzewko) trzyma input — niech najpierw ono sie zamknie (spojnosc ESC).
	if _main_menu_visible() or (GameState != null and GameState.ui_capturing_input):
		return
	_is_paused = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# SP: twarda pauza (zatrzymuje fizyke/AI). CO-OP: miekka (nie zamrazaj sesji innym).
	if not _is_networked():
		get_tree().paused = true
	if GameState != null:
		GameState.paused = true             # gate dla Player (nie chodzi/atakuje w pauzie)
	_set_visible(true)
	_show_menu_panel()
	_click()


func resume() -> void:
	if not _is_paused:
		return
	_is_paused = false
	get_tree().paused = false
	if GameState != null:
		GameState.paused = false
	_close_settings()
	_set_visible(false)
	# Wroc do trybu gry (zlap kursor). Gdy gracz mial kursor odsloniety celowo — i tak zlap (gra).
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_click()


func _set_visible(v: bool) -> void:
	if _root != null:
		_root.visible = v


func _show_menu_panel() -> void:
	if _menu_panel != null:
		_menu_panel.visible = true


# ============================================================================
#  PRZYCISKI
# ============================================================================
func _on_resume() -> void:
	resume()


func _on_settings() -> void:
	_click()
	if _settings != null and is_instance_valid(_settings):
		return
	_settings = SettingsMenuScript.new()
	_settings.closed.connect(_close_settings)
	_root.add_child(_settings)
	if _menu_panel != null:
		_menu_panel.visible = false          # schowaj przyciski pauzy pod panelem ustawien


func _close_settings() -> void:
	if _settings != null and is_instance_valid(_settings):
		_settings.queue_free()
	_settings = null
	if _menu_panel != null and _is_paused:
		_menu_panel.visible = true           # wroc do przyciskow pauzy


func _on_exit_to_menu() -> void:
	_click()
	# Najpierw odpauzuj (inaczej menu glowne byloby spauzowane), potem zglos zadanie do Main.
	_is_paused = false
	get_tree().paused = false
	if GameState != null:
		GameState.paused = false
	_close_settings()
	_set_visible(false)
	exit_to_menu_requested.emit()


func _is_networked() -> bool:
	return NetManager != null and NetManager.has_method("has_network") and NetManager.has_network()


## Czy menu glowne jest aktualnie widoczne (gra spauzowana za nim) — wtedy ESC nie otwiera pauzy.
func _main_menu_visible() -> bool:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return false
	var mm := tree.root.find_child("MainMenu", true, false)
	return mm != null and (mm as CanvasLayer).visible


func _click() -> void:
	if AudioManager != null and AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx(&"ui_click")
