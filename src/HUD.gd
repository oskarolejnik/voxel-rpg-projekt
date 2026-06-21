extends CanvasLayer
## HUD.gd — paski HP i staminy + licznik wrogów/combo + ekran śmierci.
## Wszystko budowane W KODZIE (Control + ColorRect-y), bez zależności od StyleBox-ów.
## Aktualizacja przez sygnały gracza (hp_changed/stamina_changed/combo_changed/died/respawned),
## podłączane w Main. Bez class_name — Main instancjonuje przez preload.

const BAR_W: float = 260.0   # szerokość paska (px)
const BAR_H: float = 22.0    # wysokość paska
const PAD: float = 16.0      # margines od krawędzi ekranu

# Wypełnienia pasków — zmieniamy ich szerokość przy aktualizacji.
var _hp_fill: ColorRect
var _stam_fill: ColorRect
var _hp_label: Label
var _stam_label: Label
var _enemy_label: Label   # licznik wrogów (prawy górny róg)
var _combo_label: Label   # wskaźnik combo (pod licznikiem wrogów; osobna etykieta)

# Ekran śmierci.
var _death_overlay: ColorRect
var _death_label: Label

func _ready() -> void:
	_build_bars()
	_build_death_screen()

func _build_bars() -> void:
	# --- Pasek HP (lewy górny róg) ---
	var hp_bg := _make_rect(Color(0.0, 0.0, 0.0, 0.55), Vector2(BAR_W, BAR_H))
	hp_bg.position = Vector2(PAD, PAD)
	add_child(hp_bg)
	_hp_fill = _make_rect(Color(0.80, 0.16, 0.16, 0.95), Vector2(BAR_W, BAR_H))
	hp_bg.add_child(_hp_fill)   # wypełnienie jako dziecko tła (kurczy się od prawej)
	_hp_label = Label.new()
	_hp_label.text = "HP"
	_hp_label.position = Vector2(6.0, 1.0)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bg.add_child(_hp_label)

	# --- Pasek staminy (pod HP) ---
	var st_bg := _make_rect(Color(0.0, 0.0, 0.0, 0.55), Vector2(BAR_W, BAR_H))
	st_bg.position = Vector2(PAD, PAD + BAR_H + 6.0)
	add_child(st_bg)
	_stam_fill = _make_rect(Color(0.22, 0.62, 0.86, 0.95), Vector2(BAR_W, BAR_H))
	st_bg.add_child(_stam_fill)
	_stam_label = Label.new()
	_stam_label.text = "STAMINA"
	_stam_label.position = Vector2(6.0, 1.0)
	_stam_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st_bg.add_child(_stam_label)

	# --- Licznik wrogów (prawy górny róg) ---
	# Zakotwiczamy prawą krawędź i wyrównujemy tekst do prawej zamiast magicznego offsetu -180,
	# żeby etykieta zawsze trzymała się rogu niezależnie od długości tekstu (np. lokalizacji).
	_enemy_label = Label.new()
	_enemy_label.text = ""
	_enemy_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_enemy_label.offset_right = -PAD
	_enemy_label.offset_top = PAD
	_enemy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_enemy_label)

	# --- Wskaźnik combo (pod licznikiem wrogów, OSOBNA etykieta) ---
	# Combo i licznik wrogów NIE dzielą już jednej etykiety — nie nadpisują się nawzajem.
	_combo_label = Label.new()
	_combo_label.text = ""
	_combo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_combo_label.offset_right = -PAD
	_combo_label.offset_top = PAD + 24.0   # tuż pod licznikiem wrogów
	_combo_label.modulate = Color(1.0, 0.85, 0.3)   # ciepły akcent, by combo rzucało się w oczy
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_combo_label)

# Tworzy prostokąt o danym kolorze i rozmiarze. HUD nie łapie kliknięć.
func _make_rect(color: Color, size: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _build_death_screen() -> void:
	# Pełnoekranowa, początkowo przezroczysta nakładka.
	_death_overlay = ColorRect.new()
	_death_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.visible = false
	add_child(_death_overlay)

	_death_label = Label.new()
	_death_label.text = "Zginąłeś\nRespawn..."
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(_death_label)

# ============================================================================
#  SLOTY SYGNAŁÓW GRACZA (podłączane w Main)
# ============================================================================
func on_hp_changed(current: float, maximum: float) -> void:
	var frac := 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	_hp_fill.size.x = BAR_W * frac

func on_stamina_changed(current: float, maximum: float) -> void:
	var frac := 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	_stam_fill.size.x = BAR_W * frac

# Animowane przyciemnienie przy śmierci.
func on_player_died() -> void:
	_death_overlay.visible = true
	var tw := create_tween()
	tw.tween_property(_death_overlay, "color:a", 0.65, 0.4)

# Wyczyszczenie nakładki po respawnie.
func on_player_respawned() -> void:
	var tw := create_tween()
	tw.tween_property(_death_overlay, "color:a", 0.0, 0.4)
	tw.tween_callback(func(): _death_overlay.visible = false)

# ============================================================================
#  LICZNIK WROGÓW / COMBO (woła Main / rdzeń walki)
# ============================================================================
func set_enemy_count(n: int) -> void:
	_enemy_label.text = "Wrogowie: %d" % n

# Combo pokazujemy dopiero od x2 (x1 = pojedynczy cios, nic ciekawego). Osobna etykieta.
func set_combo(n: int) -> void:
	if n > 1:
		_combo_label.text = "Combo x%d" % n
	else:
		_combo_label.text = ""
