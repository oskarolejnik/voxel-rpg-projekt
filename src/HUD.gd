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

# ETAP 3: pasek zasobu klasy (Mana/Furia/Focus) — pod staminą. Tryb/kolor ustawia setup_class_resource.
var _res_bg: ColorRect
var _res_fill: ColorRect
var _res_label: Label
var _res_max: float = 100.0
# ETAP 3 (Ranger): pipsy COMBO (0..combo_max) — OSOBNY widget od melee "Combo xN" (_combo_label/
# set_combo). To zasob builder/finisher klasy (GDD 4.3). Budowane przez setup_combo() z Main TYLKO
# dla Rangera (kind COMBO_FOCUS); inne klasy nie maja tego widgetu. Kolory wystawione jako const,
# by test mogl policzyc zapalone pipsy.
const COMBO_PIP_ON: Color = Color(1.0, 0.78, 0.25, 0.98)    # zapalony pip (cieply zloty akcent)
const COMBO_PIP_OFF: Color = Color(0.18, 0.20, 0.22, 0.70)  # pusty slot combo
const COMBO_PIP_SIZE: float = 16.0
const COMBO_PIP_GAP: float = 6.0
var _combo_root: Control          # kontener pipsow (obok paska FOCUS; ukryty do setup_combo)
var _combo_caption: Label
var _combo_pips: Array[ColorRect] = []
# ETAP 3: poziom + XP (lewy górny, pod paskami) + chwilowy napis "AWANS!".
var _level_label: Label
var _xp_label: Label
var _levelup_label: Label

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

	# --- ETAP 3: pasek zasobu klasy (pod staminą). Domyslnie ukryty do setup_class_resource. ---
	_res_bg = _make_rect(Color(0.0, 0.0, 0.0, 0.55), Vector2(BAR_W, BAR_H))
	_res_bg.position = Vector2(PAD, PAD + (BAR_H + 6.0) * 2.0)
	_res_bg.visible = false
	add_child(_res_bg)
	_res_fill = _make_rect(Color(0.85, 0.25, 0.15, 0.95), Vector2(BAR_W, BAR_H))  # domyslnie Furia
	_res_bg.add_child(_res_fill)
	_res_label = Label.new()
	_res_label.text = ""
	_res_label.position = Vector2(6.0, 1.0)
	_res_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_res_bg.add_child(_res_label)

	# --- ETAP 3: poziom + XP (pod paskiem zasobu) ---
	_level_label = Label.new()
	_level_label.text = "Poziom 1"
	_level_label.position = Vector2(PAD, PAD + (BAR_H + 6.0) * 3.0)
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_level_label)
	_xp_label = Label.new()
	_xp_label.text = "XP 0 / 50"
	_xp_label.position = Vector2(PAD, PAD + (BAR_H + 6.0) * 3.0 + 20.0)
	_xp_label.modulate = Color(0.8, 0.85, 0.95)
	_xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_xp_label)

	# --- ETAP 3: chwilowy napis awansu (środek ekranu) ---
	_levelup_label = Label.new()
	_levelup_label.text = ""
	_levelup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_levelup_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_levelup_label.offset_top = 120.0
	_levelup_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_levelup_label.modulate = Color(1.0, 0.9, 0.3, 0.0)
	_levelup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_levelup_label)

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

	# --- ETAP 3: pipsy COMBO (Ranger), OBOK paska zasobu (FOCUS), na tej samej wysokości. ---
	# Pusty kontener + etykieta; właściwe pipsy tworzy setup_combo (zna combo_max). Ukryty do wtedy,
	# więc klasy bez combo (Mag/Wojownik) nie widzą tego widgetu.
	_combo_root = Control.new()
	_combo_root.position = Vector2(PAD + BAR_W + 12.0, PAD + (BAR_H + 6.0) * 2.0)
	_combo_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_root.visible = false
	add_child(_combo_root)
	_combo_caption = Label.new()
	_combo_caption.text = "COMBO"
	_combo_caption.position = Vector2(0.0, 0.0)
	_combo_caption.modulate = Color(1.0, 0.85, 0.4)
	_combo_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_root.add_child(_combo_caption)

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

# ============================================================================
#  ETAP 3 — ZASOB KLASY + POZIOM/XP (sloty podłączane w Main)
# ============================================================================

## Konfiguruje pasek zasobu klasy: etykieta (MANA/FURIA/FOCUS), kolor, maksimum. Pokazuje pasek.
func setup_class_resource(label: String, color: Color, maximum: float) -> void:
	_res_max = maxf(1.0, maximum)
	_res_label.text = label
	_res_fill.color = color
	_res_bg.visible = true

## Aktualizacja wypełnienia paska zasobu (current/maximum). Maksimum aktualizujemy, gdy rośnie z loota.
func on_class_resource_changed(_name: StringName, current: float, maximum: float) -> void:
	if maximum > 0.0:
		_res_max = maximum
	var frac := 0.0 if _res_max <= 0.0 else clampf(current / _res_max, 0.0, 1.0)
	_res_fill.size.x = BAR_W * frac

## ETAP 3 (Ranger): buduje N pipsów COMBO (0..maximum) jako osobny widget obok paska FOCUS.
## Woła Main TYLKO dla Rangera (kind COMBO_FOCUS). To NIE jest melee "Combo xN" (set_combo) —
## tu pokazujemy zasób builder/finisher (GDD 4.3). Ponowne wywołanie przebudowuje pipsy (np. gdy
## combo_max urośnie z lootu) — etykieta i kontener zostają.
func setup_combo(maximum: int) -> void:
	var n := maxi(0, maximum)
	for pip in _combo_pips:
		pip.queue_free()
	_combo_pips.clear()
	var x0 := 64.0   # tuż za etykietą "COMBO"
	for i in n:
		var pip := _make_rect(COMBO_PIP_OFF, Vector2(COMBO_PIP_SIZE, COMBO_PIP_SIZE))
		pip.position = Vector2(x0 + float(i) * (COMBO_PIP_SIZE + COMBO_PIP_GAP), 2.0)
		_combo_root.add_child(pip)
		_combo_pips.append(pip)
	_combo_root.visible = n > 0

## ETAP 3 (Ranger): zapala `count` pierwszych pipsów (reszta pusta). Gdy maximum różni się od liczby
## pipsów (np. wzrost combo_max), najpierw przebudowuje widget. count clamp do [0, liczba pipsów].
func on_class_combo_changed(count: int, maximum: int) -> void:
	if maximum != _combo_pips.size():
		setup_combo(maximum)
	var lit := clampi(count, 0, _combo_pips.size())
	for i in _combo_pips.size():
		_combo_pips[i].color = COMBO_PIP_ON if i < lit else COMBO_PIP_OFF

## Poziom + XP (pasek tekstowy). xp_to_next=0 oznacza MAX (poziom 99).
func on_level_changed(level: int, xp: int, xp_to_next: int) -> void:
	_level_label.text = "Poziom %d" % level
	if xp_to_next <= 0:
		_xp_label.text = "MAX"
	else:
		_xp_label.text = "XP %d / %d" % [xp, xp_to_next]

## Krótki błysk "AWANS!" przy zdobyciu poziomu (FX bez audio).
func on_leveled_up(new_level: int, points_gained: int) -> void:
	_levelup_label.text = "AWANS! Poziom %d  (+%d pkt)" % [new_level, points_gained]
	var tw := create_tween()
	_levelup_label.modulate.a = 1.0
	tw.tween_interval(1.2)
	tw.tween_property(_levelup_label, "modulate:a", 0.0, 0.6)
