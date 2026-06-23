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

# ============================================================================
#  ETAP 7b — REJESTR ENCJI SWIATA (wrogowie / loot / pociski) do replikacji
# ============================================================================
## Licznik net_id encji swiata. Graczom zostawiamy ich peer_id (1..MAX), encjom 1000+ (rozlaczne
## przestrzenie -> brak kolizji ze sciezkami graczy Player_<peer>). HOST jest jedynym autorytetem
## rostera encji (alloc_net_id wola tylko host); klient odtwarza encje pod TA SAMA nazwa z RPC.
var _next_net_id: int = 1000

## net_id -> Node. HOST: oryginal (Enemy/LootDrop); KLIENT: replika. Sciezka stabilna u obu peerow
## (Enemy_<id>/Loot_<id>/Proj_<id>) => istniejacy _rpc_sync_hp dziala na replikach BEZ ZMIAN.
var _world_entities: Dictionary = {}                  # int(net_id) -> Node

## ETAP 7b — pelne dane spawnu wrogow/loot (do FULL ROSTER dla late-join). net_id -> Dictionary.
## Host trzyma "przepis" kazdej zywej encji swiata, by przy dolaczeniu nowego peera odtworzyc go u
## niego (analogicznie do _rpc_set_world_seed.rpc_id). Pociski pomijamy (zyja <5s, nie warto).
var _entity_spawn_data: Dictionary = {}              # int(net_id) -> { kind, ... }

## Sygnaly sesji (UI/lobby/Main spina spawn/despawn graczy).
signal peer_joined(peer_id: int)                      # klient dolaczyl (u hosta) / my dolaczylismy
signal peer_left(peer_id: int)                        # klient odszedl
signal session_started(is_host_session: bool)        # host_game/join_game powiodlo sie
signal session_ended()                                # leave() / utrata polaczenia -> wrocilismy do SP
signal connection_failed()                            # join_game nie zdolal sie polaczyc
signal world_seed_received(seed: int)                 # klient dostal seed swiata od hosta

## ETAP 7b — DUNGEON CO-OP: host wchodzi/wychodzi z dungeonu -> rozsyla (seed,tier,biome) klientom,
## ktorzy buduja TEN SAM uklad lokalnie (deterministyczny z seeda). DungeonManager (po stronie klienta)
## subskrybuje te sygnaly i woła _enter_dungeon/_exit_dungeon — wtedy repliki wrogow dungeonu (host_spawn
## _enemy z parent="Main/DungeonRun") laduja pod pasujaca sciezka u klienta (path-match dla HP-sync).
signal dungeon_load_requested(seed: int, tier: int, biome: StringName)
signal dungeon_exit_requested()


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
	_world_entities.clear()
	_entity_spawn_data.clear()
	_next_net_id = 1000
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
	_world_entities.clear()
	_entity_spawn_data.clear()
	_next_net_id = 1000
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


# ============================================================================
#  ETAP 7b — REJESTR + ALOKACJA net_id encji swiata
# ============================================================================

## HOST-ONLY: alokuje nowy net_id dla encji swiata. Klient nigdy nie woła (dostaje net_id w RPC).
func alloc_net_id() -> int:
	_next_net_id += 1
	return _next_net_id


func register_entity(net_id: int, node: Node) -> void:
	_world_entities[net_id] = node


func unregister_entity(net_id: int) -> void:
	_world_entities.erase(net_id)
	_entity_spawn_data.erase(net_id)


## net_id -> Node (wazny). null gdy brak / zwolniony (idempotencja despawnu).
func entity_for_net_id(net_id: int) -> Node:
	var n = _world_entities.get(net_id, null)
	return n if (n != null and is_instance_valid(n)) else null


# ============================================================================
#  ETAP 7b — SPAWN WROGOW (host replikuje -> klienci tworza replike)
# ============================================================================
## HOST: replikuje zespawnowanego wroga do klientow. SP -> natychmiastowy no-op (jedyne zrodlo to
## lokalny WorldSpawner/DungeonRun). Klient TU NIE WCHODZI (jego _process/_spawn_enemies sa bramkowane).
## Nadaje STABILNA nazwe Enemy_<id> (== u klienta -> HP-sync trafia), dopina MultiplayerSynchronizer
## transformu, rejestruje encje i rozsyla RPC. Despawn po smierci/usunieciu wroga -> _rpc_despawn_entity.
##
## parent_subpath (ETAP 7b, fix path-mismatch): wzgledna sciezka POD /root, gdzie u klienta ma
## powstac replika (np. "Main" dla wrogow swiata, "Main/DungeonRun" dla wrogow dungeonu). Klient
## tworzy replike DOKLADNIE pod ta sciezka, wiec get_path() repliki == get_path() oryginalu u hosta
## => DamageService._rpc_sync_hp (routuje po NodePath) trafia. Pusta -> domyslnie "Main" (swiat).
func host_spawn_enemy(e: Node, enemy_id: StringName, pos: Vector3, ilvl: int, biome: StringName,
		tier_bonus: int, parent_subpath: String = "Main") -> void:
	if not has_network() or not is_host():
		return                                         # SP/klient: nic
	if e == null or not is_instance_valid(e):
		return
	var nid := alloc_net_id()
	e.name = "Enemy_%d" % nid
	if "net_id" in e:
		e.set("net_id", nid)                           # Enemy.net_id (jawne pole klasowe; mirror LootDrop)
	register_entity(nid, e)
	_entity_spawn_data[nid] = {
		"kind": "enemy", "enemy_id": enemy_id, "pos": pos,
		"ilvl": ilvl, "biome": biome, "tier_bonus": tier_bonus,
		"parent": parent_subpath,
	}
	# Autorytet (host) PRZED dolaczeniem synchronizera (warunek poprawnej replikacji transformu).
	e.set_multiplayer_authority(HOST_PEER_ID)
	# Despawn repliki u klientow przy smierci wroga (Enemy.died emitowany tuz przed queue_free).
	if e.has_signal("died"):
		e.died.connect(func(_x): _despawn_world_entity(nid))
	# KOLEJNOSC (review #minor, anti "Node not found"): NAJPIERW rozeslij spawn (klient buduje replike),
	# DOPIERO w nastepnej klatce dopnij synchronizer u hosta — klient ma wtedy czas na add_child repliki,
	# zanim poleca pierwsze delty transformu. Reliable RPC spawnu i tak dotrze przed kolejnym tickiem,
	# ale deferred eliminuje przejsciowe bledy "Node not found" w oknie wyscigu (transparentne wizualnie).
	_rpc_spawn_enemy.rpc(nid, enemy_id, pos, ilvl, biome, tier_bonus, parent_subpath)
	_deferred_attach_transform_sync.call_deferred(nid)


## KLIENT: tworzy replike wroga pod TA SAMA sciezka Enemy_<id>. Host ignoruje (ma oryginal).
## Idempotentne (powtorny roster / late-join nie dubluje). AI repliki jest i tak host-only (owner=HOST),
## wiec u klienta wrog porusza sie WYLACZNIE przez MultiplayerSynchronizer (interpolacja), nie przez AI.
@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_enemy(nid: int, enemy_id: StringName, pos: Vector3, ilvl: int, biome: StringName,
		tier_bonus: int, parent_subpath: String = "Main") -> void:
	if is_host():
		return
	if entity_for_net_id(nid) != null:
		return                                         # juz istnieje (idempotencja)
	# Replika laduje POD ta sama sciezka co oryginal u hosta (parent_subpath) -> get_path() repliki
	# == get_path() oryginalu => HP-sync (DamageService._rpc_sync_hp po NodePath) trafia. Dla wrogow
	# dungeonu parent = "Main/DungeonRun" (klient musi miec wlasna instancje runu — patrz load_dungeon).
	var parent := _node_under_root(parent_subpath)
	if parent == null:
		return                                         # brak rodzica (np. klient nie wszedl w dungeon)
	var res: EnemyResource = EnemyDB.enemy(enemy_id) if EnemyDB != null else null
	var e := Enemy.new()
	e.configure_from_resource(res)
	e.loot_ilvl = ilvl
	e.loot_biome = biome
	e.loot_tier_bonus = tier_bonus
	e.name = "Enemy_%d" % nid
	e.net_id = nid
	e.position = pos
	parent.add_child(e)
	e.global_position = pos
	# Cel = lokalny gracz klienta (obrot modelu/FX); AI host-only i tak nie tyka u klienta.
	if GameState != null and "local_player" in GameState and GameState.local_player != null:
		e.set_target(GameState.local_player as Node3D)
	e.set_multiplayer_authority(HOST_PEER_ID)
	set_entity_transform_sync(e)
	# ETAP 7b (review #minor): u klienta replika NIE liczy wlasnej fizyki (grawitacja/move_and_slide)
	# — transform pochodzi WYLACZNIE z NetTransformSync. Inaczej fizyka walczy z synchronizerem (jitter,
	# kumulacja velocity.y). Wolane PO add_child (set_physics_process wymaga wezla w drzewie).
	if e.has_method("mark_as_net_replica"):
		e.mark_as_net_replica()
	register_entity(nid, e)


# ============================================================================
#  ETAP 7b — SPAWN POCISKOW (host replikuje -> klient ekstrapoluje lokalnie)
# ============================================================================
## HOST: replikuje pocisk. Klient odtwarza Projectile z setup(dir,speed,...) i EKSTRAPOLUJE wizual
## lokalnie (Projectile._physics_process: brak autorytetu -> przesuwa wizual bez CCD/dmg). Tanszy niz
## synchronizer (pocisk zyje <5s); despawn liczy host i wysyla _rpc_despawn_entity. SP -> no-op.
func host_spawn_projectile(origin: Vector3, dir: Vector3, speed: float, mask: int, gravity: float,
		pierce: int) -> int:
	if not has_network() or not is_host():
		return 0
	var nid := alloc_net_id()
	_rpc_spawn_projectile.rpc(nid, origin, dir, speed, mask, gravity, pierce)
	return nid


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_projectile(nid: int, origin: Vector3, dir: Vector3, speed: float, mask: int,
		gravity: float, pierce: int) -> void:
	if is_host():
		return
	if entity_for_net_id(nid) != null:
		return
	var main := _main_node()
	if main == null:
		return
	var proj := Projectile.new()
	# _source = null u klienta -> NetManager.has_authority(null)==false -> klient tylko ekstrapoluje
	# wizual (Projectile._physics_process L84), NIE liczy CCD/dmg (host jest autorytetem trafienia).
	proj.setup(null, dir, speed, Callable(), mask, gravity, pierce)
	proj.name = "Proj_%d" % nid
	main.add_child(proj)
	proj.global_position = origin
	register_entity(nid, proj)


# ============================================================================
#  ETAP 7b — SPAWN LOOTU (host replikuje encje LootDrop)
# ============================================================================
## HOST: replikuje encje LootDrop do klientow + nadaje net_id (klient prosi o pickup po net_id).
## SP -> no-op (LootDrop powstaje lokalnie, pickup lokalny). Item serializowany przez to_dict
## (seed+rarity+ilvl+afiksy odtwarzane deterministycznie u klienta z from_dict — juz przetestowane).
func host_spawn_loot(drop: Node, pos: Vector3) -> void:
	if not has_network() or not is_host():
		return
	if drop == null or not is_instance_valid(drop):
		return
	var nid := alloc_net_id()
	drop.name = "Loot_%d" % nid
	if "net_id" in drop:
		drop.set("net_id", nid)
	register_entity(nid, drop)
	var item = drop.get("item")
	var gold := int(drop.get("gold"))
	if item != null:
		var item_dict: Dictionary = item.to_dict()
		_entity_spawn_data[nid] = { "kind": "loot_item", "pos": pos, "item": item_dict }
		_rpc_spawn_loot_item.rpc(nid, pos, item_dict)
	else:
		_entity_spawn_data[nid] = { "kind": "loot_gold", "pos": pos, "gold": gold }
		_rpc_spawn_loot_gold.rpc(nid, pos, gold)
	# Po podniesieniu (host-grant lub SP-local) sprzataj rejestr.
	if drop.has_signal("picked_up"):
		drop.picked_up.connect(func(_d): unregister_entity(nid))


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_loot_item(nid: int, pos: Vector3, item_dict: Dictionary) -> void:
	if is_host():
		return
	if entity_for_net_id(nid) != null:
		return
	var main := _main_node()
	if main == null:
		return
	var inst := ItemInstance.from_dict(item_dict)
	var d := LootDrop.spawn_item(main, pos, inst)
	d.name = "Loot_%d" % nid
	d.net_id = nid
	# KLIENT: podepnij replike pod toast lokalny (Main.bind_remote_loot) — bez tego klient dostaje
	# item do plecaka, ale nie widzi toastu (review #minor). Host laczy picked_up sam (Main).
	if main.has_method("bind_remote_loot"):
		main.bind_remote_loot(d)
	register_entity(nid, d)


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_loot_gold(nid: int, pos: Vector3, gold: int) -> void:
	if is_host():
		return
	if entity_for_net_id(nid) != null:
		return
	var main := _main_node()
	if main == null:
		return
	var d := LootDrop.spawn_gold(main, pos, gold)
	d.name = "Loot_%d" % nid
	d.net_id = nid
	if main.has_method("bind_remote_loot"):
		main.bind_remote_loot(d)
	register_entity(nid, d)


# ============================================================================
#  ETAP 7b — DESPAWN encji swiata (wrog/loot/pocisk) u wszystkich
# ============================================================================
## HOST: usuwa encje u siebie i rozsyla despawn do klientow. Idempotentne.
func _despawn_world_entity(nid: int) -> void:
	if not has_network() or not is_host():
		return
	_rpc_despawn_entity.rpc(nid)
	unregister_entity(nid)


## Publiczny helper dla pociskow (host woła przy impakcie/despawnie pociska). No-op poza hostem.
func host_despawn_entity(nid: int) -> void:
	if nid <= 0:
		return
	_despawn_world_entity(nid)


@rpc("authority", "call_remote", "reliable")
func _rpc_despawn_entity(nid: int) -> void:
	var n := entity_for_net_id(nid)
	if n != null:
		n.queue_free()
	unregister_entity(nid)


# ============================================================================
#  ETAP 7b — MultiplayerSynchronizer transformu (host nadaje, klient interpoluje)
# ============================================================================
## HOST: dopina synchronizer transformu klatke PO rozeslaniu spawnu (klient zdazyl utworzyc replike).
## Encja moze juz nie zyc (np. wrog zginal w tej samej klatce) -> entity_for_net_id zwraca null -> no-op.
func _deferred_attach_transform_sync(nid: int) -> void:
	var e := entity_for_net_id(nid)
	if e != null:
		set_entity_transform_sync(e)


## Dopina MultiplayerSynchronizer replikujacy global_position (+ _face_dir do obrotu modelu) z hosta
## do klientow. SP -> no-op (zero narzutu: encja nie dostaje synchronizera). Wymaga, by encja miala
## ustawiony multiplayer_authority(HOST) PRZED wywolaniem (host nadaje wartosci, klienci czytaja).
func set_entity_transform_sync(e: Node) -> void:
	if not has_network():
		return                                         # SP: brak synchronizera
	if e == null or not is_instance_valid(e):
		return
	# Nie dubluj (idempotencja przy ponownej rejestracji / late-join).
	if e.get_node_or_null("NetTransformSync") != null:
		return
	var sync := MultiplayerSynchronizer.new()
	sync.name = "NetTransformSync"
	var cfg := SceneReplicationConfig.new()
	var p_pos := NodePath(".:global_position")
	cfg.add_property(p_pos)
	cfg.property_set_spawn(p_pos, false)
	cfg.property_set_replication_mode(p_pos, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	# Kierunek modelu (Enemy._process obraca _model z _face_dir). U klienta AI off -> _face_dir nie
	# aktualizowane; replikacja sprawia, ze model patrzy poprawnie bez kopiowania logiki AI.
	if "_face_dir" in e:
		var p_face := NodePath(".:_face_dir")
		cfg.add_property(p_face)
		cfg.property_set_spawn(p_face, false)
		cfg.property_set_replication_mode(p_face, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = cfg
	sync.public_visibility = true
	e.add_child(sync)
	sync.set_multiplayer_authority(HOST_PEER_ID)


## Sciezka do glownego wezla sceny (Main). Klient tworzy repliki jako jego dzieci (stabilna sciezka).
func _main_node() -> Node:
	return _node_under_root("Main")


## Wezel POD /root o podanej WZGLEDNEJ sciezce (np. "Main", "Main/DungeonRun"). null gdy nie istnieje
## (np. klient nie wszedl jeszcze w dungeon -> brak Main/DungeonRun -> replika wroga dungeonu pominieta,
## a host ponowi roster gdy klient wejdzie). Wspolny helper dla wrogow swiata i dungeonu (path-match).
func _node_under_root(subpath: String) -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	if subpath == "":
		return tree.root
	return tree.root.get_node_or_null(NodePath(subpath))


# ============================================================================
#  ETAP 7b — PICKUP LOOTU CO-OP (klient prosi -> host waliduje -> grant + despawn)
# ============================================================================
## Bufor dystansu (m) ponad pickup_radius akceptowany przez hosta (anti-cheat + ping-rozjazd pozycji).
const PICKUP_RANGE_BUFFER: float = 1.5

## Czysta funkcja walidacji dystansu (testowalna): czy gracz jest dosc blisko lootu, by go podniesc.
static func pickup_in_range(drop_pos: Vector3, player_pos: Vector3, pickup_radius: float) -> bool:
	return drop_pos.distance_to(player_pos) <= pickup_radius + PICKUP_RANGE_BUFFER


## KLIENT: prosi hosta o podniesienie lootu o danym net_id (host rozstrzyga — anti-dup/anti-cheat).
## Host wchodzi sciezka lokalna (LootDrop._on_body_entered -> _host_grant_pickup), nie tu.
func request_loot_pickup(nid: int, peer: int) -> void:
	if is_host():
		return
	_rpc_request_pickup.rpc_id(HOST_PEER_ID, nid, peer)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_pickup(nid: int, peer: int) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer:
		return                                         # anti-spoof: peer prosi za siebie
	var drop := entity_for_net_id(nid)
	if drop == null or not (drop is LootDrop):
		return
	var ld := drop as LootDrop
	if ld.is_picked():
		return                                         # juz podniesiony
	var player := player_for_peer(peer)
	if player == null or not (player is Node3D):
		return
	if not pickup_in_range(ld.global_position, (player as Node3D).global_position, ld.pickup_radius):
		return                                         # za daleko -> odrzuc (anti-cheat)
	# GRANT: host przyznaje zawartosc TEMU graczowi. Item -> replikujemy do plecaka klienta (RPC),
	# bo prawdziwy ekwipunek klient trzyma u siebie (TDD 8: postac przenosna). Zloto -> add_gold u
	# klienta (jego waluta). Despawn LootDrop u WSZYSTKICH + toast u wlasciciela.
	ld.grant_to(player)                                # host: lokalny efekt (gdy gracz to host)/rejestr
	if ld.item != null:
		_rpc_inventory_add.rpc_id(peer, ld.item.to_dict())
	elif ld.gold > 0:
		_rpc_grant_gold.rpc_id(peer, ld.gold)
	ld.mark_picked()
	_rpc_loot_picked.rpc(nid, peer)
	unregister_entity(nid)


@rpc("authority", "call_remote", "reliable")
func _rpc_loot_picked(nid: int, peer: int) -> void:
	var drop := entity_for_net_id(nid)
	if drop != null:
		if peer == local_peer_id() and drop.has_method("show_local_toast"):
			drop.show_local_toast()
		drop.queue_free()
	unregister_entity(nid)


## KLIENT: host przyznal mu item -> dodaj do LOKALNEGO InventoryComponent gracza klienta (jego plecak).
@rpc("authority", "call_remote", "reliable")
func _rpc_inventory_add(item_dict: Dictionary) -> void:
	if is_host():
		return
	var me := local_peer_id()
	var player := player_for_peer(me)
	if player == null:
		return
	for c in player.get_children():
		if c is InventoryComponent:
			(c as InventoryComponent).add_to_backpack(ItemInstance.from_dict(item_dict))
			return


## KLIENT: host przyznal mu zloto -> dodaj do jego GameState (lokalna waluta klienta).
@rpc("authority", "call_remote", "reliable")
func _rpc_grant_gold(amount: int) -> void:
	if is_host():
		return
	if GameState != null and GameState.has_method("add_gold"):
		GameState.add_gold(amount)


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
#  ETAP 7b — DUNGEON CO-OP (host wchodzi -> klienci buduja TEN SAM run lokalnie)
# ============================================================================
## HOST: rozsyla wejscie do dungeonu (seed,tier,biome) WSZYSTKIM klientom. Klient buduje wlasna
## DungeonRun z tego samego seeda (deterministyczny uklad), wiec repliki wrogow dungeonu (parent=
## "Main/DungeonRun") laduja pod pasujaca sciezka -> HP-sync trafia. No-op poza hostem/siecia (SP).
func broadcast_dungeon_load(seed: int, tier: int, biome: StringName) -> void:
	if not is_host() or not has_network():
		return
	_rpc_load_dungeon.rpc(seed, tier, biome)


## HOST: rozsyla wyjscie z dungeonu klientom (znisz lokalna DungeonRun, wroc do swiata). No-op w SP.
func broadcast_dungeon_exit() -> void:
	if not is_host() or not has_network():
		return
	_rpc_exit_dungeon.rpc()


## RPC host -> klient: wejdz do dungeonu. DungeonManager (klient) subskrybuje dungeon_load_requested
## i woła _enter_dungeon(seed,tier,biome). Host ignoruje (sam juz wszedl lokalnie).
@rpc("authority", "call_remote", "reliable")
func _rpc_load_dungeon(seed: int, tier: int, biome: StringName) -> void:
	if is_host():
		return
	dungeon_load_requested.emit(seed, tier, biome)


## RPC host -> klient: wyjdz z dungeonu. DungeonManager (klient) subskrybuje dungeon_exit_requested.
@rpc("authority", "call_remote", "reliable")
func _rpc_exit_dungeon() -> void:
	if is_host():
		return
	dungeon_exit_requested.emit()


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


## HOST: nowy klient sie polaczyl -> rozeslij mu seed swiata + FULL ROSTER encji swiata + zglos lobby.
func _on_peer_connected(peer_id: int) -> void:
	if is_host():
		# Rozeslij seed TYLKO do tego klienta (call_id), by wygenerowal teren lokalnie.
		_rpc_set_world_seed.rpc_id(peer_id, world_seed)
		# ETAP 7b: late-join — odtworz u nowego peera WSZYSTKIE zywe wrogi/loot swiata (inaczej
		# zobaczylby tylko encje zespawnowane PO jego dolaczeniu). Wysylamy tylko do tego peera.
		_broadcast_full_roster(peer_id)
	peer_joined.emit(peer_id)


## HOST: wysyla do JEDNEGO peera "przepis" kazdej zywej encji swiata (wrog/loot). Pociski pomijamy
## (efemeryczne). Po stronie klienta to te same _rpc_spawn_* co przy biezacym spawnie (idempotentne).
func _broadcast_full_roster(peer_id: int) -> void:
	for nid in _entity_spawn_data.keys():
		if entity_for_net_id(nid) == null:
			continue                                   # encja juz nie zyje (lazy cleanup)
		var data: Dictionary = _entity_spawn_data[nid]
		match String(data.get("kind", "")):
			"enemy":
				_rpc_spawn_enemy.rpc_id(peer_id, nid, data["enemy_id"], data["pos"],
					int(data["ilvl"]), data["biome"], int(data["tier_bonus"]),
					String(data.get("parent", "Main")))
			"loot_item":
				_rpc_spawn_loot_item.rpc_id(peer_id, nid, data["pos"], data["item"])
			"loot_gold":
				_rpc_spawn_loot_gold.rpc_id(peer_id, nid, data["pos"], int(data["gold"]))


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
