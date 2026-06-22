extends CanvasLayer
## LobbyUI.gd — MINIMALNE lobby co-op (ETAP 7): Host / Join(IP). Pozwala uruchomić sesję bez
## edytora. SP jest trybem DOMYŚLNYM: dopóki nie klikniesz Host/Join, NetManager.mode==SINGLE i gra
## działa lokalnie jak dotąd (zero wpływu na single-player). Toggle klawiszem F1 (chowa/pokazuje).
##
## Przepływ:
##  - HOST: NetManager.host_game(port) -> listen-server, host gra jako peer 1, klienci dołączają.
##  - JOIN: NetManager.join_game(ip, port) -> klient; po połączeniu dostaje seed świata (RPC) i
##    generuje teren LOKALNIE. Spawn własnej postaci robi warstwa co-op w Main (peer_joined).
##  - LEAVE: NetManager.leave() -> powrót do SP.
##
## To celowo prosta nakładka (Control + przyciski w kodzie), nie pełny ekran menu — DoD Etapu 7
## wymaga JEDYNIE możliwości uruchomienia co-op. Wygląd/menu główne to Etap 8 (polish).

const PANEL_W: float = 300.0

var _root: Control
var _panel: PanelContainer
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _status: Label
var _host_btn: Button
var _join_btn: Button
var _leave_btn: Button


func _ready() -> void:
	layer = 20                                          # nad HUD-em walki i ekwipunkiem
	_build_ui()
	_refresh()
	# Reaguj na zmiany sesji (status w panelu).
	if NetManager != null:
		NetManager.session_started.connect(func(_h: bool) -> void: _refresh())
		NetManager.session_ended.connect(func() -> void: _refresh())
		NetManager.peer_joined.connect(func(_p: int) -> void: _refresh())
		NetManager.peer_left.connect(func(_p: int) -> void: _refresh())
		NetManager.connection_failed.connect(func() -> void:
			_set_status("Połączenie nieudane"); _refresh())


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.position = Vector2(16.0, 70.0)
	_panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
	_root.add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_panel.add_child(vb)

	var title := Label.new()
	title.text = "CO-OP (F1)"
	title.add_theme_font_size_override("font_size", 16)
	vb.add_child(title)

	_status = Label.new()
	_status.text = "Tryb: Single-player"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_status)

	var ip_row := HBoxContainer.new()
	var ip_lbl := Label.new(); ip_lbl.text = "IP:"
	ip_row.add_child(ip_lbl)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(160.0, 0.0)
	ip_row.add_child(_ip_edit)
	vb.add_child(ip_row)

	var port_row := HBoxContainer.new()
	var port_lbl := Label.new(); port_lbl.text = "Port:"
	port_row.add_child(port_lbl)
	_port_edit = LineEdit.new()
	_port_edit.text = str(NetManager.DEFAULT_PORT if NetManager != null else 27015)
	_port_edit.custom_minimum_size = Vector2(80.0, 0.0)
	port_row.add_child(_port_edit)
	vb.add_child(port_row)

	_host_btn = Button.new()
	_host_btn.text = "Hostuj grę"
	_host_btn.pressed.connect(_on_host)
	vb.add_child(_host_btn)

	_join_btn = Button.new()
	_join_btn.text = "Dołącz (IP)"
	_join_btn.pressed.connect(_on_join)
	vb.add_child(_join_btn)

	_leave_btn = Button.new()
	_leave_btn.text = "Rozłącz (wróć do SP)"
	_leave_btn.pressed.connect(_on_leave)
	vb.add_child(_leave_btn)

	# SP-REGRESJA WIZUALNA (review #minor): w czystym single-player panel co-op jest UKRYTY domyślnie —
	# SP wygląda IDENTYCZNIE jak przed Etapem 7 (zero zmiany odczucia). Gracz odsłania go klawiszem F1,
	# a po wejściu w tryb sieciowy (host/join) panel sam się pokazuje (_refresh). Mandat: "SP identycznie".
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		_panel.visible = not _panel.visible


func _on_host() -> void:
	if NetManager == null:
		return
	var port := int(_port_edit.text) if _port_edit.text.is_valid_int() else NetManager.DEFAULT_PORT
	if NetManager.host_game(port):
		_set_status("Hostuję na porcie %d (peer 1)" % port)
	else:
		_set_status("Nie udało się hostować (port zajęty?)")
	_refresh()


func _on_join() -> void:
	if NetManager == null:
		return
	var ip := _ip_edit.text.strip_edges()
	var port := int(_port_edit.text) if _port_edit.text.is_valid_int() else NetManager.DEFAULT_PORT
	if NetManager.join_game(ip, port):
		_set_status("Łączę z %s:%d..." % [ip, port])
	else:
		_set_status("Nie udało się rozpocząć łączenia")
	_refresh()


func _on_leave() -> void:
	if NetManager != null:
		NetManager.leave()
	_set_status("Tryb: Single-player")
	_refresh()


func _set_status(s: String) -> void:
	if _status != null:
		_status.text = s


## Odświeża dostępność przycisków + status wg trybu NetManager.
func _refresh() -> void:
	if NetManager == null:
		return
	var networked := NetManager.has_network()
	_host_btn.disabled = networked
	_join_btn.disabled = networked
	_leave_btn.disabled = not networked
	_ip_edit.editable = not networked
	_port_edit.editable = not networked
	if not networked:
		if _status.text.begins_with("Łączę"):
			pass    # zostaw komunikat łączenia
		elif NetManager.mode == NetManager.Mode.SINGLE:
			_set_status("Tryb: Single-player")
	else:
		var role := "HOST" if NetManager.is_host() else "KLIENT"
		_set_status("%s — graczy: %d/%d (peer %d)" % [
			role, NetManager.peer_count(), NetManager.MAX_PLAYERS, NetManager.local_peer_id()])
		if _panel != null:
			_panel.visible = true   # w trybie sieciowym panel widoczny (status sesji); SP zostaje ukryty
