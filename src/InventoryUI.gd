class_name InventoryUI
extends CanvasLayer
## InventoryUI.gd — ekran ekwipunku + toast lootu (Etap 2). OSOBNA warstwa CanvasLayer (layer=5),
## NAD bojowym HUD-em (layer domyslny 0) — nie koliduje z paskami HP/stamina/combo z Etapu 0/1.
##
## Zawiera:
##   - Ekran ekwipunku (toggle klawiszem I): 7 slotow noszonych + siatka plecaka. Klik w item
##     plecaka -> equip (do naturalnego slotu); klik w slot noszony -> unequip (do plecaka).
##   - Tooltip + porownywarka: najazd na item plecaka pokazuje jego afiksy ORAZ aktualnie
##     zalozony w tym slocie (porownanie wartosci kluczowych statow).
##   - Toast lootu: krotki komunikat w KOLORZE RZADKOSCI (LootService.rarity_color), znika sam.
##
## Czytelnosc walki: gdy ekwipunek otwarty -> pokazujemy kursor; gdy zamkniety -> oddajemy go grze
## (capture), zeby kamera/atak dzialaly jak wczesniej. Toast NIE lapie myszy (MOUSE_FILTER_IGNORE).
##
## Wpiecie: Main tworzy InventoryUI i wola bind_inventory(inv). Toggle obsluguje sama (input).

const UI_LAYER: int = 5
const TOAST_LIFETIME: float = 3.2
const SLOT_SIZE: float = 56.0
const SLOT_GAP: float = 8.0

## Etykiety slotow noszonych (kolejnosc = InventoryComponent.EquipSlot).
const EQUIP_LABELS: Array[String] = ["Bron", "Glowa", "Tulow", "Nogi", "Buty", "Trinket 1", "Trinket 2"]

var _inv: InventoryComponent = null

var _root: Control                 # panel ekwipunku (chowany/pokazywany)
var _equip_slots: Array[Panel] = []
var _backpack_grid: GridContainer
var _tooltip: PanelContainer
var _tooltip_label: RichTextLabel
var _gold_label: Label

var _toast_box: VBoxContainer      # stos toastow (najnowszy na dole)

var _open: bool = false
var _mouse_mode_before: int = Input.MOUSE_MODE_CAPTURED   # tryb kursora sprzed otwarcia (przywracany przy zamknieciu)


func _ready() -> void:
	layer = UI_LAYER
	_build_panel()
	_build_toasts()
	_set_open(false)


# ============================================================================
#  WPIECIE
# ============================================================================

func bind_inventory(inv: InventoryComponent) -> void:
	_inv = inv
	if _inv != null:
		_inv.inventory_changed.connect(_refresh)
	if GameState != null:
		GameState.gold_changed.connect(_on_gold_changed)
		_on_gold_changed(GameState.gold)
	_refresh()


# ============================================================================
#  INPUT (toggle I) — osobny od walki; nie ruszamy mapy input gracza
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I:
		_set_open(not _open)
		get_viewport().set_input_as_handled()
		return
	# ESC gdy ekwipunek otwarty: zamknij ekwipunek i POCHLON event, by NIE doleciał do
	# Player._toggle_mouse() (jeden autorytet kursora, Etap 2 review #5). Gdy zamkniety -> ESC
	# przelatuje do Playera jak dawniej (menu/zwolnienie kursora).
	if _open and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _set_open(value: bool) -> void:
	if value == _open:
		return
	# Jeden autorytet kursora (Etap 2 review #5): gdy INNY panel (np. drzewko umiejetnosci) juz lapie
	# input, NIE otwieramy ekwipunku rownolegle i NIE ruszamy mouse_mode — inaczej dwa UI biłyby sie o
	# kursor i po zamknieciu jednego zostawalby zly stan (VISIBLE/CAPTURED). Lustro guardu z SkillTreeUI.
	# Headless tego nie wykrywa.
	if value and GameState != null and GameState.ui_capturing_input and not _open:
		return
	_open = value
	_root.visible = value
	if GameState != null:
		GameState.ui_capturing_input = value   # bramkuje lokomocje gracza (Etap 2 review #4)
	if value:
		_mouse_mode_before = Input.mouse_mode   # zapamietaj, by przywrocic przy zamknieciu
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh()
	else:
		_hide_tooltip()
		# Przywracamy POPRZEDNI tryb kursora (nie wymuszamy CAPTURED), zeby nie krasc kursora
		# zwolnionego wczesniej przez ESC-menu (Etap 2 review #5).
		Input.mouse_mode = _mouse_mode_before


# ============================================================================
#  BUDOWA PANELU
# ============================================================================

func _build_panel() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # blokuje klik "przez" panel do gry
	_root.visible = false                            # start ukryty (_set_open(false) w _ready early-returnuje)
	add_child(_root)

	# Przyciemnione tlo (nieco przezroczyste — widac gre za spodem).
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	# Centralny panel.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 460)
	panel.position = Vector2(-310, -230)   # wycentrowanie wzgledem PRESET_CENTER
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# Naglowek + zloto.
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Ekwipunek"
	title.add_theme_font_size_override("font_size", 22)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_gold_label = Label.new()
	_gold_label.text = "Zloto: 0"
	_gold_label.modulate = Color(0.95, 0.82, 0.3)
	header.add_child(_gold_label)
	vbox.add_child(header)

	# Sekcja: sloty noszone (7).
	var eq_title := Label.new()
	eq_title.text = "Zalozone (klik = zdejmij)"
	eq_title.modulate = Color(0.8, 0.8, 0.85)
	vbox.add_child(eq_title)

	var eq_row := HBoxContainer.new()
	eq_row.add_theme_constant_override("separation", int(SLOT_GAP))
	vbox.add_child(eq_row)
	for i in InventoryComponent.EQUIP_SLOT_COUNT:
		var slot := _make_slot(EQUIP_LABELS[i])
		_equip_slots.append(slot)
		eq_row.add_child(slot)
		var idx := i
		slot.gui_input.connect(func(e: InputEvent) -> void: _on_equip_slot_input(e, idx))
		slot.mouse_entered.connect(func() -> void: _on_equip_hover(idx))
		slot.mouse_exited.connect(_hide_tooltip)

	# Sekcja: plecak (siatka).
	var bp_title := Label.new()
	bp_title.text = "Plecak (klik = zaloz)"
	bp_title.modulate = Color(0.8, 0.8, 0.85)
	vbox.add_child(bp_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(596, 220)
	vbox.add_child(scroll)
	_backpack_grid = GridContainer.new()
	_backpack_grid.columns = 9
	_backpack_grid.add_theme_constant_override("h_separation", int(SLOT_GAP))
	_backpack_grid.add_theme_constant_override("v_separation", int(SLOT_GAP))
	scroll.add_child(_backpack_grid)

	# Tooltip (porownywarka) — plywajacy, chowany.
	_tooltip = PanelContainer.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_tooltip.z_index = 10
	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.custom_minimum_size = Vector2(260, 0)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(_tooltip_label)
	_root.add_child(_tooltip)

	# Podpowiedz na dole.
	var hint := Label.new()
	hint.text = "I — zamknij ekwipunek"
	hint.modulate = Color(0.7, 0.7, 0.75)
	vbox.add_child(hint)


func _make_slot(label_text: String) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.16, 0.9)
	sb.border_color = Color(0.35, 0.35, 0.4)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	# Etykieta slotu (na dole, drobna).
	var lbl := Label.new()
	lbl.name = "Caption"
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.modulate = Color(0.6, 0.6, 0.65)
	lbl.position = Vector2(3, SLOT_SIZE - 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lbl)
	# Wskaznik zawartosci (kolorowy kwadrat = rzadkosc; pusty = brak).
	var dot := ColorRect.new()
	dot.name = "Dot"
	dot.color = Color(0, 0, 0, 0)
	dot.size = Vector2(SLOT_SIZE - 16, SLOT_SIZE - 24)
	dot.position = Vector2(8, 6)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(dot)
	return p


# ============================================================================
#  ODSWIEZANIE
# ============================================================================

func _refresh() -> void:
	if _inv == null:
		return
	# Sloty noszone.
	for i in _equip_slots.size():
		var item := _inv.get_equipped(i)
		var dot := _equip_slots[i].get_node("Dot") as ColorRect
		if item != null:
			dot.color = LootService.rarity_color(item.rarity)
		else:
			dot.color = Color(0, 0, 0, 0)

	# Plecak.
	for child in _backpack_grid.get_children():
		child.queue_free()
	for bi in _inv.backpack.size():
		var item: ItemInstance = _inv.backpack[bi]
		var cell := _make_slot("")
		var dot2 := cell.get_node("Dot") as ColorRect
		dot2.color = LootService.rarity_color(item.rarity)
		_backpack_grid.add_child(cell)
		var index := bi
		cell.gui_input.connect(func(e: InputEvent) -> void: _on_backpack_input(e, index))
		cell.mouse_entered.connect(func() -> void: _on_backpack_hover(index))
		cell.mouse_exited.connect(_hide_tooltip)


func _on_gold_changed(amount: int) -> void:
	if _gold_label != null:
		_gold_label.text = "Zloto: %d" % amount


# ============================================================================
#  INTERAKCJE: klik equip/unequip
# ============================================================================

func _on_backpack_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _inv != null:
			_inv.equip_from_backpack(index)
			_hide_tooltip()


func _on_equip_slot_input(event: InputEvent, slot: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _inv != null:
			_inv.unequip(slot)
			_hide_tooltip()


# ============================================================================
#  TOOLTIP + POROWNYWARKA
# ============================================================================

func _on_backpack_hover(index: int) -> void:
	if _inv == null or index < 0 or index >= _inv.backpack.size():
		return
	var item := _inv.backpack[index]
	var equipped := _inv.get_equipped(_compare_slot_for(item))
	_show_tooltip(_format_item(item, equipped))


func _on_equip_hover(slot: int) -> void:
	if _inv == null:
		return
	var item := _inv.get_equipped(slot)
	if item == null:
		return
	_show_tooltip(_format_item(item, null))


## Slot noszony, z ktorym porownujemy item plecaka (do porownywarki).
func _compare_slot_for(item: ItemInstance) -> int:
	var ir := ItemDB.item(item.base_id)
	var s := ir.slot if ir != null else ItemResource.Slot.WEAPON
	match s:
		ItemResource.Slot.WEAPON: return InventoryComponent.EquipSlot.WEAPON
		ItemResource.Slot.HELM:   return InventoryComponent.EquipSlot.HELM
		ItemResource.Slot.CHEST:  return InventoryComponent.EquipSlot.CHEST
		ItemResource.Slot.LEGS:   return InventoryComponent.EquipSlot.LEGS
		ItemResource.Slot.BOOTS:  return InventoryComponent.EquipSlot.BOOTS
		_: return InventoryComponent.EquipSlot.TRINKET_1


## Tekst BBCode itemu (nazwa w kolorze rzadkosci + afiksy). Gdy `compare` != null, dokleja sekcje
## porownania (delta kluczowych statow vs zalozony).
func _format_item(item: ItemInstance, compare: ItemInstance) -> String:
	var col := LootService.rarity_color(item.rarity)
	var hex := col.to_html(false)
	var name := _item_name(item)
	var txt := "[color=#%s][b]%s[/b][/color]\n" % [hex, name]
	txt += "[color=#aaaaaa]%s · ilvl %d[/color]\n" % [LootService.rarity_name(item.rarity), item.ilvl]
	txt += "[color=#888888]————————[/color]\n"
	for m in item.collect_modifiers():
		txt += "[color=#cfe8cf]%s[/color]\n" % _format_mod(m)
	# Implicit z definicji (jesli base_id znany).
	var ir := ItemDB.item(item.base_id)
	if ir != null:
		for bm in ir.base_modifiers:
			if bm is StatModifier:
				txt += "[color=#9fb0c0]%s (bazowy)[/color]\n" % _format_mod(bm)
	# Sockety/enchant.
	if not item.sockets.is_empty():
		var filled := 0
		for g in item.sockets:
			if g != &"":
				filled += 1
		txt += "[color=#9aa]Sockety: %d/%d[/color]\n" % [filled, item.sockets.size()]
	if not item.enchant.is_empty():
		txt += "[color=#c8a8e8]Enchant: %s r%d[/color]\n" % [
			String(item.enchant.get("enchant_id", "?")), int(item.enchant.get("rank", 1))]

	if compare != null:
		txt += "[color=#888888]——— vs zalozony ———[/color]\n"
		txt += "[color=#aaaaaa]%s[/color]\n" % _item_name(compare)
	return txt


func _format_mod(m: StatModifier) -> String:
	var v := m.value
	match m.op:
		StatModifier.Op.FLAT:      return "+%.1f %s" % [v, m.stat]
		StatModifier.Op.INCREASED: return "+%.0f%% %s" % [v * 100.0, m.stat]
		StatModifier.Op.MORE:      return "x%.0f%% %s" % [(1.0 + v) * 100.0, m.stat]
	return "%s %s" % [str(v), m.stat]


func _item_name(item: ItemInstance) -> String:
	var ir := ItemDB.item(item.base_id)
	if ir != null and ir.display_name != "":
		return ir.display_name
	return "%s przedmiot" % LootService.rarity_name(item.rarity)


func _show_tooltip(bbcode: String) -> void:
	_tooltip_label.text = bbcode
	_tooltip.visible = true
	# Pozycja przy kursorze (z marginesem, by nie wychodzil za ekran).
	var mp := _root.get_global_mouse_position()
	_tooltip.position = mp + Vector2(18, 18)


func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false


# ============================================================================
#  TOAST LOOTU (kolor rzadkosci, znika sam) — osobny stos, nie lapie myszy
# ============================================================================

func _build_toasts() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast_box.alignment = BoxContainer.ALIGNMENT_END
	_toast_box.offset_bottom = -120.0
	_toast_box.add_theme_constant_override("separation", 4)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_box)


## Publiczne: pokaz toast o znalezionym itemie (Main podpina pod LootDrop.picked_up / drop_for).
func show_item_toast(item: ItemInstance) -> void:
	if item == null:
		return
	var col := LootService.rarity_color(item.rarity)
	_push_toast("%s — %s" % [LootService.rarity_name(item.rarity), _item_name(item)], col)


func show_gold_toast(amount: int) -> void:
	_push_toast("+%d zlota" % amount, Color(0.95, 0.82, 0.3))


func _push_toast(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Tlo pod tekstem (czytelnosc na jasnym terenie).
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	_toast_box.add_child(lbl)
	# Fade out + usuniecie.
	var tw := create_tween()
	tw.tween_interval(TOAST_LIFETIME - 0.8)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lbl.queue_free)
