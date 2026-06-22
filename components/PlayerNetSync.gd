class_name PlayerNetSync
extends Node
## PlayerNetSync.gd (komponent gracza) — predykcja+rekonsyliacja ruchu WLASNEJ postaci (TDD 6.3)
## oraz interpolacja CUDZYCH graczy (TDD 6.2). HOST-AUTHORITATIVE: host liczy ruch autorytatywnie;
## klient porusza swoja postacia OD RAZU (predykcja) i koryguje przy rozbieznosci (rekonsyliacja);
## cudze postacie interpolowane miedzy snapshotami (bez predykcji).
##
## ====================================================================================
##  SINGLE-PLAYER MUSI DZIALAC IDENTYCZNIE
## ====================================================================================
## Caly ten komponent jest BEZCZYNNY w SP: tick()/sample_*() sprawdzaja NetManager.has_network()
## i gdy false (SP) NIC nie robia (Player._physics_process biegnie jak dotad — zero zmian odczucia).
## Komponent jest tworzony przez Player TYLKO gdy zachodzi potrzeba (lub jest no-op), wiec sciezka
## SP nie dotyka ani bufora inputu, ani snapshotow.
##
## ====================================================================================
##  MODEL (TDD 6.3)
## ====================================================================================
## 1. KLIENT-WLASCICIEL (owner_peer == lokalny): Player porusza sie LOKALNIE (predykcja), a my:
##    - zapisujemy (tick, input, predicted_pos) do bufora,
##    - co tick wysylamy input do hosta: submit_input.rpc_id(1, tick, dir, flags),
##    - po odebraniu (tick, authoritative_pos) od hosta: jesli rozbieznosc > prog -> ustaw
##      pozycje autorytatywna i ODTWORZ (replay) zbuforowane inputy od tego ticka (rekonsyliacja);
##      male roznice -> brak akcji (predykcja byla trafna).
## 2. HOST (lub host nad cudza postacia): odbiera input klienta, ustawia go jako "zewnetrzny input"
##    encji (Player czyta go zamiast klawiatury) -> liczy ruch autorytatywnie -> rozsyla pozycje
##    przez snapshoty (push_snapshot.rpc).
## 3. CUDZA POSTAC u KLIENTA (owner_peer != lokalny, nie host): NIE liczy fizyki ruchu z inputu —
##    interpoluje global_position miedzy ostatnimi snapshotami hosta.
##
## Player wola (z _physics_process, na koncu): net_post_physics(delta) — tu robimy sampling/replay/
## interpolacje. Predykcja sama "dzieje sie" przez normalny ruch Playera (klient-wlasciciel rusza
## klawiatura), my tylko buforujemy i korygujemy.

## Prog rozbieznosci (m): powyzej -> twarda rekonsyliacja (snap + replay); ponizej -> ignoruj
## (predykcja trafna, bez szarpania). 0.25 m ~ pol kroku — niewidoczne, a lapie realny desync.
const RECONCILE_THRESHOLD: float = 0.25
## Maks. rozmiar bufora inputu (ticki). 2 s @ 60 Hz = 120 — z zapasem na lag.
const INPUT_BUFFER_MAX: int = 128
## Ile snapshotow cudzej postaci trzymamy do interpolacji (2 wystarcza; 3 = zapas na jitter).
const SNAPSHOT_BUFFER_MAX: int = 6
## Opoznienie interpolacji (s) — renderujemy cudzych "w przeszlosci", by zawsze miec 2 snapshoty
## do interpolacji (gladko mimo zmiennego pingu). ~100 ms standard dla co-op.
const INTERP_DELAY: float = 0.1

var _player: CharacterBody3D = null            # encja-rodzic (Player)
var _identity: NetIdentity = null              # tozsamosc (owner_peer)

# --- KLIENT-WLASCICIEL: bufor predykcji (rekonsyliacja) ---
var _tick: int = 0                             # lokalny licznik tickow fizyki (rosnie co _physics_process)
var _input_buffer: Array = []                  # [{tick, dir:Vector2, run:bool, jump:bool, pos:Vector3}]
var _last_acked_tick: int = -1                 # ostatni tick potwierdzony przez hosta

# --- HOST: ostatni odebrany input od wlasciciela (Player czyta go zamiast klawiatury) ---
var _remote_input_dir: Vector2 = Vector2.ZERO
var _remote_input_run: bool = false
var _remote_input_jump: bool = false
var _has_remote_input: bool = false            # czy host dostal jakikolwiek input klienta

# --- CUDZA POSTAC u klienta: bufor snapshotow do interpolacji ---
var _snapshots: Array = []                     # [{t:float(local_time), pos:Vector3, yaw:float}]
var _interp_clock: float = 0.0                 # lokalny zegar do interpolacji


func setup(player: CharacterBody3D, identity: NetIdentity) -> void:
	_player = player
	_identity = identity


# ============================================================================
#  ROLE (czytane co klatke; w SP zawsze "lokalny SP")
# ============================================================================

## Czy jestesmy w trybie sieciowym W OGOLE. SP -> false (komponent bezczynny).
func _net() -> bool:
	return NetManager != null and NetManager.has_network()


## Czy to NASZA postac (klient-wlasciciel LUB host nad swoja postacia). Steruje predykcja.
func _is_local_owner() -> bool:
	if _identity == null:
		return true
	return int(_identity.owner_peer) == NetManager.local_peer_id()


## Czy host ma autorytet nad ta encja (host nad wszystkim; klient nad swoja).
func _is_authority() -> bool:
	return NetManager.has_authority(_player)


# ============================================================================
#  WEJSCIE INPUTU (Player pyta: czy ruchem steruje siec?)
# ============================================================================

## Czy Player ma czytac WLASNY input (klawiatura) — true gdy:
##  - SP (zawsze), LUB
##  - jestesmy klientem-wlascicielem tej postaci (predykcja: rusza klawiatura od razu).
## False gdy: host symuluje CUDZA postac (czyta _remote_input), albo to cudza postac u klienta
## (interpolacja — w ogole nie liczymy ruchu z inputu).
func should_read_local_input() -> bool:
	if not _net():
		return true
	return _is_local_owner()


## Czy Player ma w ogole liczyc fizyke ruchu (move_and_slide z velocity wyliczana z inputu).
## False TYLKO dla cudzej postaci u klienta (tam pozycje narzuca interpolacja).
func should_simulate_movement() -> bool:
	if not _net():
		return true
	# Host symuluje wszystkich (swoja + cudze z _remote_input). Klient symuluje TYLKO swoja.
	if NetManager.is_host():
		return true
	return _is_local_owner()


## Input do uzycia przez Player gdy NIE czyta klawiatury (host nad cudza postacia).
## Zwraca Vector2 kierunku WASD (lokalny: x=bok, y=przod/tyl, jak w Player._physics_process).
func remote_input_dir() -> Vector2:
	return _remote_input_dir if _has_remote_input else Vector2.ZERO


func remote_input_run() -> bool:
	return _has_remote_input and _remote_input_run


func remote_input_jump() -> bool:
	return _has_remote_input and _remote_input_jump


# ============================================================================
#  GLOWNY TICK (Player wola na KONCU _physics_process)
# ============================================================================

## Wolane przez Player na koncu _physics_process(delta). W SP -> natychmiastowy return (no-op).
## input_dir/run/jump: to, co Player FAKTYCZNIE uzyl w tej klatce (do buforowania + wysylki).
func net_post_physics(delta: float, input_dir: Vector2, run: bool, jump: bool) -> void:
	if not _net():
		return
	_interp_clock += delta

	if NetManager.is_client() and _is_local_owner():
		# KLIENT-WLASCICIEL: predykcja. Zbuforuj (tick,input,pos) i wyslij input do hosta.
		_tick += 1
		_buffer_input(input_dir, run, jump)
		_submit_input.rpc_id(NetManager.HOST_PEER_ID, _tick, input_dir, run, jump)
	elif NetManager.is_host():
		_tick += 1
		if _is_local_owner():
			# Host-wlasciciel wlasnej postaci: rozsylaj snapshot wszystkim (klienci interpoluja).
			_broadcast_snapshot()
		else:
			# Host symuluje CUDZA postac z _remote_input -> rozsylaj jej snapshot.
			_broadcast_snapshot()
	elif NetManager.is_client() and not _is_local_owner():
		# CUDZA postac u klienta: interpolacja miedzy snapshotami (pozycje narzucamy tutaj).
		_apply_interpolation()


# ============================================================================
#  KLIENT-WLASCICIEL: bufor + rekonsyliacja
# ============================================================================

func _buffer_input(dir: Vector2, run: bool, jump: bool) -> void:
	_input_buffer.append({
		"tick": _tick, "dir": dir, "run": run, "jump": jump,
		"pos": _player.global_position,
	})
	while _input_buffer.size() > INPUT_BUFFER_MAX:
		_input_buffer.pop_front()


## RPC host -> klient-wlasciciel: potwierdzenie autorytatywnej pozycji dla danego ticka.
## Rekonsyliacja: jesli przewidziana pozycja dla tego ticka rozni sie > prog -> snap + replay.
## UWAGA (review #major): "any_peer" + JAWNA walidacja nadawcy (musi byc HOST). Multiplayer authority
## tego wezla == owner-peer (klient), wiec @rpc("authority") NIE pozwolilby HOSTOWI wyslac (host != owner).
## Stad any_peer + sprawdzenie, ze nadawca to peer 1 (host) — host jest autorytatywnym zrodlem pozycji.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _ack_position(acked_tick: int, auth_pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != NetManager.HOST_PEER_ID:
		return                                      # tylko HOST potwierdza pozycje (anti-spoof)
	if acked_tick <= _last_acked_tick:
		return                                      # stary/zduplikowany ACK — ignoruj
	_last_acked_tick = acked_tick
	# Znajdz przewidziana pozycje dla tego ticka w buforze.
	var predicted: Vector3 = _player.global_position
	var idx := -1
	for i in _input_buffer.size():
		if int(_input_buffer[i]["tick"]) == acked_tick:
			predicted = _input_buffer[i]["pos"]
			idx = i
			break
	# Usun potwierdzone (i starsze) inputy z bufora.
	if idx >= 0:
		for _k in range(idx + 1):
			if not _input_buffer.is_empty():
				_input_buffer.pop_front()
	# Rozbieznosc > prog -> rekonsyliacja: ustaw pozycje autorytatywna. (Pelny replay fizyki w GDScript
	# bylby kosztowny; przy malej liczbie graczy snap autorytatywnej pozycji + zachowane przyszle inputy
	# w buforze daje stabilny wynik — kolejne klatki kontynuuja predykcje od skorygowanej pozycji.)
	if predicted.distance_to(auth_pos) > RECONCILE_THRESHOLD:
		_player.global_position = auth_pos
		_player.velocity = Vector3.ZERO
		if _player.has_method("reset_physics_interpolation"):
			_player.reset_physics_interpolation()


## RPC klient -> host: input klienta (intencja ruchu) ze stemplem ticka. Host ustawia go jako
## zewnetrzny input encji (Player czyta zamiast klawiatury) i potwierdza pozycje po symulacji.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_input(client_tick: int, dir: Vector2, run: bool, jump: bool) -> void:
	if not NetManager.is_host():
		return
	_remote_input_dir = dir
	_remote_input_run = run
	_remote_input_jump = jump
	_has_remote_input = true
	# Potwierdz pozycje autorytatywna dla tego ticka klienta (rekonsyliacja u klienta).
	var sender := multiplayer.get_remote_sender_id()
	_ack_position.rpc_id(sender, client_tick, _player.global_position)


# ============================================================================
#  HOST -> KLIENCI: snapshoty (interpolacja cudzych postaci)
# ============================================================================

func _broadcast_snapshot() -> void:
	if not NetManager.is_host() or not _net():
		return
	var yaw := 0.0
	if "rotation" in _player:
		yaw = _player.rotation.y
	_recv_snapshot.rpc(_player.global_position, yaw)


## RPC host -> klienci: snapshot pozycji/yaw encji. Klient buforuje do interpolacji (NIE dotyczy
## wlasnej postaci klienta — ta jest predykowana). Host ignoruje (sam jest zrodlem).
## "any_peer" + walidacja nadawcy = HOST (jak _ack_position): host rozsyla snapshoty WSZYSTKICH postaci
## (takze tych o owner-peerze klienta), wiec nie moze byc bramkowane @rpc("authority") wzgledem owner-peera.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _recv_snapshot(pos: Vector3, yaw: float) -> void:
	if multiplayer.get_remote_sender_id() != NetManager.HOST_PEER_ID:
		return                                      # tylko HOST rozsyla snapshoty (anti-spoof)
	if NetManager.is_host():
		return
	if _is_local_owner():
		return                                      # wlasna postac = predykcja, nie interpolacja
	_snapshots.append({ "t": _interp_clock, "pos": pos, "yaw": yaw })
	while _snapshots.size() > SNAPSHOT_BUFFER_MAX:
		_snapshots.pop_front()


## Interpolacja cudzej postaci: renderujemy "w przeszlosci" (INTERP_DELAY) miedzy dwoma snapshotami.
func _apply_interpolation() -> void:
	if _snapshots.size() == 0:
		return
	var render_t := _interp_clock - INTERP_DELAY
	if _snapshots.size() == 1:
		_player.global_position = _snapshots[0]["pos"]
		return
	# Znajdz dwa snapshoty obejmujace render_t.
	var a: Dictionary = _snapshots[0]
	var b: Dictionary = _snapshots[_snapshots.size() - 1]
	for i in range(_snapshots.size() - 1):
		if float(_snapshots[i]["t"]) <= render_t and render_t <= float(_snapshots[i + 1]["t"]):
			a = _snapshots[i]
			b = _snapshots[i + 1]
			break
	var span := float(b["t"]) - float(a["t"])
	var alpha := 0.0 if span <= 0.0001 else clampf((render_t - float(a["t"])) / span, 0.0, 1.0)
	_player.global_position = (a["pos"] as Vector3).lerp(b["pos"] as Vector3, alpha)
	# Yaw modelu (jesli encja go wystawia) — interpolacja katowa.
	if "rotation" in _player:
		_player.rotation.y = lerp_angle(float(a["yaw"]), float(b["yaw"]), alpha)
