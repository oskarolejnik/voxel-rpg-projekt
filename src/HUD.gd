extends CanvasLayer
## HUD.gd — stylizowany HUD action-RPG, budowany W KODZIE (Control + StyleBoxFlat, bez tekstur).
## Aktualizacja przez sygnały gracza (hp_changed/stamina_changed/combo_changed/died/respawned/
## level_changed/leveled_up/class_*), podłączane w Main. Bez class_name — Main instancjonuje przez preload.
##
## REDESIGN (HUD „ładny"):
##  * paski = StyleBoxFlat (zaokrąglone, obramowane, ciemny track + nasycone wypełnienie),
##  * PŁYNNE wypełnienia (lerp w _process, frame-rate independent) zamiast skoków,
##  * HP ma GHOST-TRAIL: jasny ślad chwilowo zostaje po obrażeniach i dogania (jak w bijatykach),
##  * typografia z OUTLINE+cieniem (czytelna nad jasnym światem), liczby na pasku HP,
##  * panel statystyk (lewy-górny) spina HP/Stamina/Zasób + Poziom/XP w jedną ramkę,
##  * subtelny CELOWNIK na środku (action-RPG),
##  * zachowane: screen-flash (impakt/krytyk), ekran śmierci, pipsy COMBO (Ranger), AWANS.
##
## KONTRAKT (testy E3/E7/Feel4 zależą): metody-sloty (niżej), screen-flash (flash/_flash_*),
## pipsy combo (_combo_pips jako ColorRect.color == COMBO_PIP_ON/OFF, _combo_root, setup_combo,
## on_class_combo_changed, set_combo). NIE zmieniać tych nazw/typów.

const PAD: float = 18.0       # margines od krawędzi ekranu
const BAR_W: float = 280.0    # szerokość paska HP/Stamina/Zasób
const HP_H: float = 22.0      # wysokość paska HP (główny)
const SUB_H: float = 14.0     # wysokość pasków stamina/zasób (drugorzędne)
const GAP: float = 7.0        # odstęp pionowy między paskami
const RADIUS: float = 6.0     # promień zaokrąglenia rogów pasków

# Kolory motywu.
const COL_PANEL: Color = Color(0.05, 0.06, 0.08, 0.50)   # tło panelu statystyk
const COL_PANEL_BORDER: Color = Color(1.0, 1.0, 1.0, 0.09)
const COL_TRACK: Color = Color(0.03, 0.03, 0.04, 0.72)   # rowek paska (pod wypełnieniem)
const COL_TRACK_BORDER: Color = Color(0.0, 0.0, 0.0, 0.55)
const COL_HP: Color = Color(0.84, 0.20, 0.22)            # wypełnienie HP (krwista czerwień)
const COL_HP_TRAIL: Color = Color(1.0, 0.80, 0.46, 0.92) # ghost-trail HP (ciepły bursztyn = świeże obrażenia)
const COL_STAM: Color = Color(0.28, 0.74, 0.92)          # stamina (chłodny błękit)
const COL_RES_DEFAULT: Color = Color(0.92, 0.42, 0.16)   # zasób klasy (domyślnie Furia)
const COL_TEXT: Color = Color(0.95, 0.96, 0.98)
const COL_TEXT_DIM: Color = Color(0.74, 0.80, 0.90)

# --- Paski HP (3 warstwy: track + ghost-trail + wypełnienie) + liczba ---
var _hp_track: Panel
var _hp_ghost: ProgressBar
var _hp_bar: ProgressBar
var _hp_text: Label
var _hp_cur: int = 100
var _hp_max: int = 100
var _hp_t: float = 1.0        # docelowy ułamek HP (0..1); _hp_bar.value dąży do niego
# --- Stamina + Zasób klasy ---
var _stam_bar: ProgressBar
var _stam_t: float = 1.0
var _res_group: Control       # cała grupa zasobu (do show/hide)
var _res_bar: ProgressBar
var _res_label: Label
var _res_max: float = 100.0
var _res_t: float = 0.0
# --- Poziom / XP ---
var _level_label: Label
var _xp_label: Label
var _levelup_label: Label
# --- Panel statystyk (rodzic lewego stosu) ---
var _stat_panel: Panel
# --- Licznik wrogów / combo melee (prawy-górny) ---
var _enemy_label: Label
var _combo_label: Label

# ETAP 3 (Ranger): pipsy COMBO (0..combo_max) — OSOBNY widget od melee "Combo xN" (_combo_label/
# set_combo). Zasób builder/finisher klasy (GDD 4.3). Budowane przez setup_combo() z Main TYLKO dla
# Rangera (kind COMBO_FOCUS). Kolory jako const, by test mógł policzyć zapalone pipsy.
const COMBO_PIP_ON: Color = Color(1.0, 0.78, 0.25, 0.98)    # zapalony pip (ciepły złoty akcent)
const COMBO_PIP_OFF: Color = Color(0.18, 0.20, 0.22, 0.70)  # pusty slot combo
const COMBO_PIP_SIZE: float = 16.0
const COMBO_PIP_GAP: float = 6.0
var _combo_root: Control          # kontener pipsów (obok panelu; ukryty do setup_combo)
var _combo_caption: Label
var _combo_pips: Array[ColorRect] = []

# Ekran śmierci.
var _death_overlay: ColorRect
var _death_label: Label

# Celownik (środek ekranu).
var _crosshair: Panel

# FAZA 4 (2): SCREEN-FLASH na impakcie/krytyku — pełnoekranowy ColorRect, krótki rozbłysk.
# Krytyk = złotawy/mocniejszy, zwykły mocny cios = lekki biały. Własny licznik w _process.
var _flash_overlay: ColorRect
var _flash_t: float = 0.0
var _flash_dur: float = 0.0
var _flash_peak: float = 0.0
const FLASH_COL_CRIT: Color = Color(1.0, 0.86, 0.45)   # złotawy krytyk
const FLASH_COL_HIT: Color = Color(1.0, 1.0, 1.0)      # biały mocny cios

func _ready() -> void:
	_build_stat_panel()
	_build_top_right()
	_build_crosshair()
	_build_overlays()

# ============================================================================
#  HELPERY STYLU (StyleBoxFlat + outline label) — zero zależności od plików theme
# ============================================================================
func _sb(fill: Color, radius: float, border_col: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	sb.corner_radius_bottom_left = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	if border_w > 0:
		sb.border_color = border_col
		sb.set_border_width_all(border_w)
	return sb

# Pasek postępu w stylu HUD: ciemny track + zaokrąglone, nasycone wypełnienie. value/max w 0..1.
func _make_bar(w: float, h: float, fill_col: Color, with_track: bool) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.custom_minimum_size = Vector2(w, h)
	bar.size = Vector2(w, h)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if with_track:
		bar.add_theme_stylebox_override("background", _sb(COL_TRACK, RADIUS, COL_TRACK_BORDER, 1))
	else:
		bar.add_theme_stylebox_override("background", _sb(Color(0, 0, 0, 0), RADIUS, Color(0, 0, 0, 0), 0))
	bar.add_theme_stylebox_override("fill", _sb(fill_col, RADIUS, Color(0, 0, 0, 0), 0))
	return bar

# Etykieta z czytelnym konturem + lekkim cieniem (nad jasnym światem).
func _make_label(text: String, size: int, col: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	l.add_theme_constant_override("outline_size", 6 if bold else 5)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.45))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Zachowane z poprzedniej wersji — pipsy COMBO budowane jako ColorRect (kontrakt testu E3).
func _make_rect(color: Color, size: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# ============================================================================
#  PANEL STATYSTYK (lewy-górny): HP (track+ghost+fill+liczba), Stamina, Zasób, Poziom/XP
# ============================================================================
func _build_stat_panel() -> void:
	var inner := 11.0
	var x := inner
	var w := BAR_W
	# Wysokość panelu: HP + Stamina + Zasób + 2 linie tekstu.
	var panel_h := inner * 2.0 + HP_H + GAP + SUB_H + GAP + SUB_H + GAP + 22.0 + 18.0

	_stat_panel = Panel.new()
	_stat_panel.position = Vector2(PAD, PAD)
	_stat_panel.custom_minimum_size = Vector2(w + inner * 2.0, panel_h)
	_stat_panel.size = _stat_panel.custom_minimum_size
	_stat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_panel.add_theme_stylebox_override("panel", _sb(COL_PANEL, 10.0, COL_PANEL_BORDER, 1))
	add_child(_stat_panel)

	# --- HP: track + ghost-trail (za wypełnieniem) + wypełnienie + liczba ---
	var hp_y := inner
	_hp_track = Panel.new()
	_hp_track.position = Vector2(x, hp_y)
	_hp_track.size = Vector2(w, HP_H)
	_hp_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_track.add_theme_stylebox_override("panel", _sb(COL_TRACK, RADIUS, COL_TRACK_BORDER, 1))
	_stat_panel.add_child(_hp_track)

	_hp_ghost = _make_bar(w, HP_H, COL_HP_TRAIL, false)   # ślad obrażeń — POD wypełnieniem
	_hp_ghost.position = Vector2(x, hp_y)
	_stat_panel.add_child(_hp_ghost)

	_hp_bar = _make_bar(w, HP_H, COL_HP, false)           # właściwe HP — na wierzchu śladu
	_hp_bar.position = Vector2(x, hp_y)
	_stat_panel.add_child(_hp_bar)

	_hp_text = _make_label("100 / 100", 13, COL_TEXT, true)
	_hp_text.position = Vector2(x, hp_y - 1.0)
	_hp_text.size = Vector2(w, HP_H)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stat_panel.add_child(_hp_text)

	# --- Stamina (pod HP) ---
	var st_y := hp_y + HP_H + GAP
	_stam_bar = _make_bar(w, SUB_H, COL_STAM, true)
	_stam_bar.position = Vector2(x, st_y)
	_stat_panel.add_child(_stam_bar)
	var st_cap := _make_label("STAMINA", 9, COL_TEXT_DIM)
	st_cap.position = Vector2(x + 7.0, st_y - 2.0)
	_stat_panel.add_child(st_cap)

	# --- Zasób klasy (pod staminą; ukryty do setup_class_resource) ---
	var rs_y := st_y + SUB_H + GAP
	_res_group = Control.new()
	_res_group.position = Vector2.ZERO
	_res_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_res_group.visible = false
	_stat_panel.add_child(_res_group)
	_res_bar = _make_bar(w, SUB_H, COL_RES_DEFAULT, true)
	_res_bar.position = Vector2(x, rs_y)
	_res_bar.value = 0.0
	_res_group.add_child(_res_bar)
	_res_label = _make_label("", 9, COL_TEXT_DIM)
	_res_label.position = Vector2(x + 7.0, rs_y - 2.0)
	_res_group.add_child(_res_label)

	# --- Poziom + XP (na dole panelu) ---
	var lv_y := rs_y + SUB_H + GAP + 2.0
	_level_label = _make_label("Poziom 1", 15, COL_TEXT, true)
	_level_label.position = Vector2(x, lv_y)
	_stat_panel.add_child(_level_label)
	_xp_label = _make_label("XP 0 / 50", 11, COL_TEXT_DIM)
	_xp_label.position = Vector2(x, lv_y + 19.0)
	_stat_panel.add_child(_xp_label)

	# --- Chwilowy napis awansu (środek-góra ekranu) ---
	_levelup_label = _make_label("", 30, Color(1.0, 0.9, 0.35), true)
	_levelup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_levelup_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_levelup_label.offset_top = 120.0
	_levelup_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_levelup_label.modulate.a = 0.0
	add_child(_levelup_label)

	# --- Pipsy COMBO (Ranger) — obok panelu, na wysokości zasobu; ukryte do setup_combo ---
	_combo_root = Control.new()
	_combo_root.position = Vector2(PAD + w + inner * 2.0 + 12.0, PAD + rs_y)
	_combo_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_root.visible = false
	add_child(_combo_root)
	_combo_caption = _make_label("COMBO", 10, Color(1.0, 0.85, 0.4))
	_combo_caption.position = Vector2(0.0, 0.0)
	_combo_root.add_child(_combo_caption)

func _build_top_right() -> void:
	# Licznik wrogów (prawy-górny róg) — zakotwiczony do prawej, wyrównanie do prawej.
	_enemy_label = _make_label("", 15, COL_TEXT, true)
	_enemy_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_enemy_label.offset_right = -PAD
	_enemy_label.offset_top = PAD
	add_child(_enemy_label)

	# Combo melee "Combo xN" (pod licznikiem wrogów; OSOBNA etykieta od pipsów Rangera).
	_combo_label = _make_label("", 17, Color(1.0, 0.82, 0.3), true)
	_combo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_combo_label.offset_right = -PAD
	_combo_label.offset_top = PAD + 26.0
	add_child(_combo_label)

func _build_crosshair() -> void:
	# Subtelna kropka na środku — pomoc w celowaniu (action-RPG), nie przeszkadza.
	_crosshair = Panel.new()
	_crosshair.custom_minimum_size = Vector2(5.0, 5.0)
	_crosshair.size = Vector2(5.0, 5.0)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -2.5
	_crosshair.offset_top = -2.5
	_crosshair.offset_right = 2.5
	_crosshair.offset_bottom = 2.5
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.add_theme_stylebox_override("panel", _sb(Color(1.0, 1.0, 1.0, 0.45), 3.0, Color(0, 0, 0, 0.5), 1))
	add_child(_crosshair)

func _build_overlays() -> void:
	# Pełnoekranowy SCREEN-FLASH (nad światem, POD ekranem śmierci).
	_flash_overlay = ColorRect.new()
	_flash_overlay.color = Color(FLASH_COL_HIT.r, FLASH_COL_HIT.g, FLASH_COL_HIT.b, 0.0)
	_flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.visible = false
	add_child(_flash_overlay)

	# Ekran śmierci (na samej górze).
	_death_overlay = ColorRect.new()
	_death_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.visible = false
	add_child(_death_overlay)
	_death_label = _make_label("Zginąłeś\nRespawn...", 40, COL_TEXT, true)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_overlay.add_child(_death_label)

# ============================================================================
#  ANIMACJA W _process — płynne wypełnienia + ghost-trail HP + zanik flasha
# ============================================================================
func _process(delta: float) -> void:
	# Paski dążą PŁYNNIE do wartości docelowych (frame-rate independent).
	if _hp_bar != null:
		_hp_bar.value = lerpf(_hp_bar.value, _hp_t, _sm(15.0, delta))
		# Ghost-trail: przy LECZENIU dogania natychmiast (snap w górę), przy OBRAŻENIACH zostaje
		# z tyłu i powoli dogania (jasny ślad = świeżo utracone HP).
		if _hp_bar.value >= _hp_ghost.value:
			_hp_ghost.value = _hp_bar.value
		else:
			_hp_ghost.value = lerpf(_hp_ghost.value, _hp_bar.value, _sm(3.5, delta))
	if _stam_bar != null:
		_stam_bar.value = lerpf(_stam_bar.value, _stam_t, _sm(18.0, delta))
	if _res_bar != null:
		_res_bar.value = lerpf(_res_bar.value, _res_t, _sm(15.0, delta))

	# Screen-flash zanik.
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
		var a := _flash_peak * (_flash_t / _flash_dur) if _flash_dur > 0.0 else 0.0
		_flash_overlay.color.a = clampf(a, 0.0, 1.0)
		if _flash_t == 0.0:
			_flash_overlay.visible = false

# Wygładzanie wykładnicze (frame-rate independent): alpha do lerp(a,b,alpha).
func _sm(k: float, delta: float) -> float:
	return 1.0 - exp(-k * delta)

# ============================================================================
#  SCREEN-FLASH (impakt/krytyk) — woła Main z hit_resolved gdy bije GRACZ
# ============================================================================
## is_crit -> złotawy, mocniejszy (peak 0.30, 0.18 s); inaczej lekki biały (peak 0.14, 0.10 s).
## Mocniejszy flash NADPISUJE słabszy (max), słabszy nie przerywa silniejszego.
func flash(is_crit: bool) -> void:
	if _flash_overlay == null:
		return
	var peak := 0.30 if is_crit else 0.14
	var dur := 0.18 if is_crit else 0.10
	var col := FLASH_COL_CRIT if is_crit else FLASH_COL_HIT
	if peak >= _flash_peak or _flash_t <= 0.0:
		_flash_peak = peak
		_flash_dur = dur
		_flash_t = dur
		_flash_overlay.color = Color(col.r, col.g, col.b, peak)
	_flash_overlay.visible = true

# ============================================================================
#  SLOTY SYGNAŁÓW GRACZA (podłączane w Main)
# ============================================================================
func on_hp_changed(current: float, maximum: float) -> void:
	_hp_max = int(round(maximum))
	_hp_cur = int(round(clampf(current, 0.0, maximum)))
	_hp_t = 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	if _hp_text != null:
		_hp_text.text = "%d / %d" % [_hp_cur, _hp_max]

func on_stamina_changed(current: float, maximum: float) -> void:
	_stam_t = 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)

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
#  LICZNIK WROGÓW / COMBO MELEE
# ============================================================================
func set_enemy_count(n: int) -> void:
	_enemy_label.text = "Wrogowie: %d" % n

# Combo melee pokazujemy dopiero od x2 (x1 = pojedynczy cios). Osobna etykieta od pipsów Rangera.
func set_combo(n: int) -> void:
	if n > 1:
		_combo_label.text = "Combo x%d" % n
	else:
		_combo_label.text = ""

# ============================================================================
#  ETAP 3 — ZASÓB KLASY + POZIOM/XP
# ============================================================================
## Konfiguruje pasek zasobu: etykieta (MANA/FURIA/FOCUS), kolor wypełnienia, maksimum. Pokazuje grupę.
func setup_class_resource(label: String, color: Color, maximum: float) -> void:
	_res_max = maxf(1.0, maximum)
	_res_label.text = label
	_res_bar.add_theme_stylebox_override("fill", _sb(color, RADIUS, Color(0, 0, 0, 0), 0))
	_res_group.visible = true

## Aktualizacja wypełnienia paska zasobu (płynnie w _process). Maksimum aktualizujemy gdy rośnie z loota.
func on_class_resource_changed(_name: StringName, current: float, maximum: float) -> void:
	if maximum > 0.0:
		_res_max = maximum
	_res_t = 0.0 if _res_max <= 0.0 else clampf(current / _res_max, 0.0, 1.0)

## ETAP 3 (Ranger): buduje N pipsów COMBO (0..maximum) obok panelu. Woła Main TYLKO dla Rangera
## (kind COMBO_FOCUS). To NIE jest melee "Combo xN" (set_combo). Ponowne wywołanie przebudowuje pipsy.
func setup_combo(maximum: int) -> void:
	var n := maxi(0, maximum)
	for pip in _combo_pips:
		pip.queue_free()
	_combo_pips.clear()
	var x0 := 62.0   # tuż za etykietą "COMBO"
	for i in n:
		var pip := _make_rect(COMBO_PIP_OFF, Vector2(COMBO_PIP_SIZE, COMBO_PIP_SIZE))
		pip.position = Vector2(x0 + float(i) * (COMBO_PIP_SIZE + COMBO_PIP_GAP), 0.0)
		_combo_root.add_child(pip)
		_combo_pips.append(pip)
	_combo_root.visible = n > 0

## ETAP 3 (Ranger): zapala `count` pierwszych pipsów (reszta pusta). Gdy maximum != liczbie pipsów,
## najpierw przebudowuje widget. count clamp do [0, liczba pipsów].
func on_class_combo_changed(count: int, maximum: int) -> void:
	if maximum != _combo_pips.size():
		setup_combo(maximum)
	var lit := clampi(count, 0, _combo_pips.size())
	for i in _combo_pips.size():
		_combo_pips[i].color = COMBO_PIP_ON if i < lit else COMBO_PIP_OFF

## Poziom + XP. xp_to_next=0 oznacza MAX (poziom 99).
func on_level_changed(level: int, xp: int, xp_to_next: int) -> void:
	_level_label.text = "Poziom %d" % level
	if xp_to_next <= 0:
		_xp_label.text = "XP — MAX"
	else:
		_xp_label.text = "XP %d / %d" % [xp, xp_to_next]

## Krótki błysk "AWANS!" przy zdobyciu poziomu (FX bez audio).
func on_leveled_up(new_level: int, points_gained: int) -> void:
	_levelup_label.text = "AWANS!  Poziom %d   (+%d pkt)" % [new_level, points_gained]
	var tw := create_tween()
	_levelup_label.modulate.a = 1.0
	tw.tween_interval(1.2)
	tw.tween_property(_levelup_label, "modulate:a", 0.0, 0.6)
