extends Node
## NetManager.gd (autoload) — abstrakcja autorytetu sieci (TDD 6 / 6.5). ETAP 7 = LIVE.
##
## Cala mutacja stanu (HP, loot, smierc, postep) przechodzi przez uslugi bramkowane
## has_authority(). W SP zwraca ZAWSZE true — jestesmy autorytetem. W co-opie ten SAM kod
## dziala na HOSCIE, a klient wysyla intencje (RPC) i odbiera stan (Synchronizer). Co-op to
## DOLOZENIE transportu, NIE przepisanie logiki.
##
## ETAP 7 (LIVE): ENet listen-server. host_game(port) tworzy serwer (host = peer 1, gra normalnie),
## join_game(ip, port) dolacza jako klient, leave() konczy sesje i wraca do SINGLE. Limit 4 graczy.
## Swiat: ten sam seed -> klienci generuja teren LOKALNIE (oszczednosc pasma); siec synchronizuje
## TYLKO encje/stan/loot/edycje. has_authority() wg MultiplayerAPI: host ma autorytet nad wszystkim,
## klient tylko nad WLASNA encja (NetIdentity.owner_peer / multiplayer authority owner).
##
## SINGLE-PLAYER MUSI DZIALAC IDENTYCZNIE: gdy mode == SINGLE wszystkie sciezki sa lokalne
## (has_authority -> true, has_network -> false), wiec hitstop/time_scale/AI/loot ida jak dotad.

## Tryby sesji.
enum Mode { SINGLE, HOST, CLIENT }

const HOST_PEER_ID: int = 1                           # listen-server: host = peer 1
const DEFAULT_PORT: int = 27015                       # domyslny port ENet co-op
const MAX_PLAYERS: int = 4                            # co-op do 4 (host + 3 klientow)

var mode: Mode = Mode.SINGLE

## Seed swiata sesji. Host rozsyla go klientom przy dolaczeniu (RPC) -> wszyscy generuja teren
## z TEGO SAMEGO seeda lokalnie + ten sam strumien loot/combat (determinizm = brak desyncu).
var world_seed: int = 0

## Mapowanie peer_id -> encja gracza (wypelniane przez warstwe spawnu w Etapie 7 / Main co-op).
## NetManager NIE trzyma stanu encji — trzyma tylko sesyjne mapowanie (TDD 1.3).
var _player_nodes: Dictionary = {}                    # int(peer) -> Node (encja gracza)

## Sygnaly sesji (UI/lobby/Main spina spawn/despawn graczy).
signal peer_joined(peer_id: int)                      # klient dolaczyl (u hosta) / my dolaczylismy
signal peer_left(peer_id: int)                        # klient odszedl
signal session_started(is_host_session: bool)        # host_game/join_game powiodlo sie
signal session_ended()                                # leave() / utrata polaczenia -> wrocilismy do SP
signal connection_failed()                            # join_game nie zdolal sie polaczyc
signal world_seed_received(seed: int)                 # klient dostal seed swiata od hosta


# ============================================================================
#  SESJA — host / join / leave (ETAP 7 LIVE)
# ============================================================================

## Hostuje sesje co-op (listen-server). Host gra normalnie jako peer 1. Zwraca true przy sukcesie.
## p_seed: seed swiata (domyslnie biezacy RNGService.world_seed) — rozsylany klientom przy dolaczeniu.
func host_game(port: int = DEFAULT_PORT, p_seed: int = -1) -> bool:
	leave()                                            # czysty start (gdyby cos wisialo)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)   # -1: host zajmuje slot peer 1
	if err != OK:
		push_warning("NetManager.host_game: create_server blad %d (port %d)" % [err, port])
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	world_seed = p_seed if p_seed >= 0 else _current_world_seed()
	_sync_gamestate_mode()
	_connect_multiplayer_signals()
	_player_nodes.clear()
	session_started.emit(true)
	return true


## Dolacza do sesji co-op jako klient. Zwraca true gdy proba startu OK (sukces/porazka -> sygnaly
## peer_joined/connection_failed pozniej, asynchronicznie przez MultiplayerAPI).
func join_game(ip: String, port: int = DEFAULT_PORT) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_warning("NetManager.join_game: create_client blad %d (%s:%d)" % [err, ip, port])
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	_sync_gamestate_mode()
	_connect_multiplayer_signals()
	_player_nodes.clear()
	return true


## Konczy sesje sieciowa i wraca do SINGLE (SP). Idempotentne. Po tym has_authority()==true,
## has_network()==false -> wszystkie sciezki znow lokalne (SP-safety).
func leave() -> void:
	_disconnect_multiplayer_signals()
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).close()
		multiplayer.multiplayer_peer = null
	var was_networked := mode != Mode.SINGLE
	mode = Mode.SINGLE
	_player_nodes.clear()
	_sync_gamestate_mode()
	if was_networked:
		session_ended.emit()


# ============================================================================
#  AUTORYTET (rdzen — bramkuje DamageService/LootService/AIComponent)
# ============================================================================

## Czy LOKALNY peer ma autorytet nad encja `_n`. SP: zawsze true.
## Co-op: host ma autorytet nad wszystkim; klient TYLKO nad wlasna encja (owner_peer == my peer
## LUB Godotowy multiplayer authority na encji == my peer). Argument opcjonalny (wiele wywolan
## bezkontekstowych w SP/host).
func has_authority(_n: Node = null) -> bool:
	if mode == Mode.SINGLE:
		return true
	if is_host():
		return true
	# KLIENT: autorytet tylko nad WLASNA encja. NetIdentity.owner_peer to KONTRAKT (po TYPIE, nie
	# nazwie wezla) — sprawdzamy go NAJPIERW, bo jest jawnie ustawiany przez warstwe spawnu. Dopiero
	# gdy encja NIE ma NetIdentity, a JEST realny peer sieciowy, fallback na Godotowy authority owner.
	# (Bez realnego peera get_multiplayer_authority() zwraca domyslnie 1 == local_peer_id() i dawalby
	# falszywy autorytet nad CUDZA encja — stad NetIdentity ma priorytet, a fallback tylko z peerem.)
	if _n == null or not is_instance_valid(_n):
		return false
	for c in _n.get_children():
		if c is NetIdentity:
			return int((c as NetIdentity).owner_peer) == local_peer_id()
	if multiplayer != null and multiplayer.has_multiplayer_peer() and _n.is_inside_tree():
		return _n.get_multiplayer_authority() == local_peer_id()
	return false


## AUTORYTET STANU (HP/loot/smierc/postep) — ZAWSZE host (TDD 6.2: "HP/staty encji: host").
## ROZDZIAL POJEC (review #major): has_authority() niesie OWNERSHIP RUCHU (klient ma autorytet nad
## predykcja WLASNEJ postaci), ale HP/loot/smierc NIE moga byc liczone przez klienta — nawet dla
## wlasnej postaci — inaczej powstaja DWA niezalezne zrodla HP (klient liczy swoje, host liczy w
## RemotePlayer) => desync HP gracza. Dlatego mutacje HP/lootu bramkujemy has_state_authority()
## (== is_host()), a predykcje RUCHU bramkujemy has_authority()/is_movement_owner(). SP: zawsze true.
func has_state_authority(_n: Node = null) -> bool:
	return is_host()


## Czy LOKALNY peer jest WLASCICIELEM RUCHU encji (predykcja ruchu wlasnej postaci, TDD 6.3).
## SP: zawsze true. Co-op: host nad wszystkim; klient nad wlasna encja (NetIdentity.owner_peer).
## To NIE daje prawa do mutacji HP/lootu (od tego jest has_state_authority) — tylko do predykcji ruchu.
func is_movement_owner(n: Node = null) -> bool:
	return has_authority(n)


## Czy jestesmy hostem (lub SP — SP to "sesja z jednym peerem-hostem", TDD 6.5).
func is_host() -> bool:
	return mode == Mode.SINGLE or mode == Mode.HOST


## Czy jestesmy klientem (nigdy w SP).
func is_client() -> bool:
	return mode == Mode.CLIENT


## ID lokalnego peera. SP: 1 (wszystko nalezy do peer 1).
func local_peer_id() -> int:
	if mode == Mode.SINGLE:
		return HOST_PEER_ID
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return HOST_PEER_ID


## Czy faktycznie dziala transport sieciowy. W SP ZAWSZE false -> hitstop/time_scale globalny
## dozwolony (TDD 6.4), AI/loot/wszystko lokalne. JEDYNE zrodlo prawdy "czy jestesmy w co-opie".
func has_network() -> bool:
	return mode != Mode.SINGLE and multiplayer != null and multiplayer.has_multiplayer_peer()


# ============================================================================
#  MAPOWANIE peer <-> encja gracza (sesyjne; warstwa spawnu wypelnia)
# ============================================================================

func register_player(peer_id: int, node: Node) -> void:
	_player_nodes[peer_id] = node


func unregister_player(peer_id: int) -> void:
	_player_nodes.erase(peer_id)


func player_for_peer(peer_id: int) -> Node:
	var n = _player_nodes.get(peer_id, null)
	return n if (n != null and is_instance_valid(n)) else null


## Lista aktywnych peerow (host + klienci). SP: [1]. Co-op: [1, ...remote].
func peer_ids() -> Array:
	if not has_network():
		return [HOST_PEER_ID]
	var out: Array = [HOST_PEER_ID]
	for p in multiplayer.get_peers():
		out.append(int(p))
	return out


func peer_count() -> int:
	return peer_ids().size()


# ============================================================================
#  SEED SWIATA (klient generuje teren LOKALNIE z seeda hosta)
# ============================================================================

## Host: rozsyla seed swiata do WSZYSTKICH klientow (po dolaczeniu). Klient generuje teren sam.
func broadcast_world_seed() -> void:
	if not is_host() or not has_network():
		return
	_rpc_set_world_seed.rpc(world_seed)


## RPC: host -> klient. Ustawia seed swiata u klienta i przekazuje go RNGService (loot/combat/teren
## z tego samego ziarna). Klient generuje teren LOKALNIE — geometria voxela NIE leci po sieci.
@rpc("authority", "call_remote", "reliable")
func _rpc_set_world_seed(seed: int) -> void:
	world_seed = seed
	if RNGService != null and RNGService.has_method("seed_session"):
		RNGService.seed_session(seed)
	world_seed_received.emit(seed)


# ============================================================================
#  WEWNETRZNE
# ============================================================================

func _current_world_seed() -> int:
	if RNGService != null and RNGService.has_method("world_seed"):
		return RNGService.world_seed()
	return VoxelWorld.FEATURE_SEED


## Lustrzane odbicie trybu w GameState (wygoda dla reszty kodu; GameState.mode == NetManager.mode).
func _sync_gamestate_mode() -> void:
	if GameState == null:
		return
	match mode:
		Mode.SINGLE: GameState.mode = GameState.Mode.SINGLE
		Mode.HOST:   GameState.mode = GameState.Mode.HOST
		Mode.CLIENT: GameState.mode = GameState.Mode.CLIENT


func _connect_multiplayer_signals() -> void:
	if multiplayer == null:
		return
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _disconnect_multiplayer_signals() -> void:
	if multiplayer == null:
		return
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)


## HOST: nowy klient sie polaczyl -> rozeslij mu seed swiata + zglos lobby.
func _on_peer_connected(peer_id: int) -> void:
	if is_host():
		# Rozeslij seed TYLKO do tego klienta (call_id), by wygenerowal teren lokalnie.
		_rpc_set_world_seed.rpc_id(peer_id, world_seed)
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	unregister_player(peer_id)
	peer_left.emit(peer_id)


## KLIENT: udalo sie polaczyc z hostem (peer 1).
func _on_connected_to_server() -> void:
	peer_joined.emit(local_peer_id())
	session_started.emit(false)


## KLIENT: nie udalo sie polaczyc -> wroc do SP.
func _on_connection_failed() -> void:
	connection_failed.emit()
	leave()


## KLIENT: host zniknal -> wroc do SP (SP-safety: dalej grasz lokalnie).
func _on_server_disconnected() -> void:
	leave()
