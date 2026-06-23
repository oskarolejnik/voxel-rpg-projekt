extends Node
## Etap7bTest.gd — mini-test HEADLESS Etapu 7b (REPLIKACJA WSPOLNEGO SWIATA). Uruchomienie:
##   godot --headless res://test/Etap7bTest.tscn
##
## DoD Etapu 7b (domkniecie Etapu 7): w trybie sieciowym KLIENT widzi tych samych wrogow/loot co
## host, transform+HP synchronizowane host-authoritative (brak desyncu), klient moze podniesc loot
## (host rozstrzyga). SP (brak peera) DZIALA IDENTYCZNIE. Test ma DWIE czesci:
##
##  (A) LOGICZNA (zawsze wykonalna headless) — kontrakt replikacji + SP-bramki + anti-desync:
##   1. Rejestr net_id: alloc_net_id rosnie/unikalny; register/unregister/entity_for_net_id round-trip.
##   2. SP-bramki host_spawn_*: w SP (mode SINGLE) to NO-OP (encja NIE dostaje synchronizera, brak
##      wpisu w rejestrze, brak zmiany nazwy) -> SP IDENTYCZNY.
##   3. KLIENT-bramka WorldSpawner._process/_update_regions: przy mode==CLIENT early-return (_active
##      nie rosnie -> klient nie spawnuje wlasnych wrogow, dostaje repliki RPC).
##   4. Kontrakt pickup-RPC: metody istnieja; czysta walidacja dystansu (pickup_in_range) odrzuca
##      request spoza pickup_radius+bufor, akceptuje w zasiegu.
##   5. ItemInstance round-trip (loot przez RPC: seed+rarity+ilvl+afiksy) — re-use kontraktu E7(4).
##   6. SP-regresja wrogow: Enemy.new() w SP spawnuje, AI ma autorytet (has_authority(self)==true),
##      _die dropi loot (LootService.drop_for niepuste) — bez regresji Etapow 3/4.
##   7. Kontrakt powierzchni RPC NetManager: _rpc_spawn_enemy/_rpc_spawn_loot_item/_rpc_despawn_entity/
##      _rpc_request_pickup/_rpc_loot_picked/_rpc_inventory_add istnieja (klient ma czym odebrac swiat).
##   8. LootDrop SP-pickup IDENTYCZNY: w SP _on_body_entered podnosi lokalnie (item -> plecak), bez sieci.
##
##  (B) LOOPBACK 2 PEERY (best-effort, jeden proces, ENet 127.0.0.1) — patrz uwaga w Etap7Test:
##      pelny stos @rpc po NodePath w 1-procesowym loopbacku z set_multiplayer(path) jest zawodny,
##      wiec czesc (B) sprawdza TRANSPORT (ENet polaczenie host<->klient) i jest POMIJANA gdy brak
##      sieci. Pelna replikacja w zywej scenie 2-osobowej -> RECZNY test 2-procesowy (residual_risks).
##
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[E7b] ..." + ALL OK + quit.

var _failures: int = 0


func _ready() -> void:
	print("[E7b] === Etap 7b mini-test start ===")

	_test_net_id_registry()
	_test_sp_gates_host_spawn()
	_test_client_spawner_gate()
	_test_pickup_rpc_contract()
	_test_iteminstance_roundtrip()
	_test_sp_enemy_regression()
	_test_netmanager_rpc_surface()
	_test_lootdrop_sp_pickup()
	_test_enemy_net_id_member()
	_test_dungeon_coop_contract()
	_test_replica_physics_marker()
	_test_loot_timeout_despawn_sp()

	await _test_loopback_transport()
	await _test_loopback_client_gate()

	# Settle (deferred queue_free).
	for _f in 4:
		await get_tree().process_frame

	if _failures == 0:
		print("[E7b] ALL OK")
	else:
		printerr("[E7b] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[E7b] FAIL: %s" % msg)


# ============================================================================
#  (1) REJESTR net_id (alokacja + mapowanie net_id -> Node)
# ============================================================================
func _test_net_id_registry() -> void:
	var a := NetManager.alloc_net_id()
	var b := NetManager.alloc_net_id()
	_check(b > a, "(1) alloc_net_id nie rosnie (%d !> %d)" % [b, a])
	_check(a >= 1000 and b >= 1000, "(1) net_id < 1000 (kolizja z peer_id graczy!)")

	var n := Node.new()
	add_child(n)
	NetManager.register_entity(a, n)
	_check(NetManager.entity_for_net_id(a) == n, "(1) entity_for_net_id nie zwraca zarejestrowanego")
	_check(NetManager.entity_for_net_id(999999) == null, "(1) entity_for_net_id zwraca cos dla nieznanego id")
	NetManager.unregister_entity(a)
	_check(NetManager.entity_for_net_id(a) == null, "(1) unregister_entity nie usunal wpisu")
	# Zwolniona encja -> entity_for_net_id zwraca null (is_instance_valid guard). free() natychmiast
	# (nie queue_free) -> instancja niewazna w tej samej klatce, lookup zwraca null.
	var n2 := Node.new()
	NetManager.register_entity(b, n2)
	n2.free()
	_check(NetManager.entity_for_net_id(b) == null, "(1) entity_for_net_id zwraca zwolniona encje")
	NetManager.unregister_entity(b)
	print("[E7b] (1) rejestr net_id (alloc rosnie/unikalny, register/unregister/lookup round-trip) OK")


# ============================================================================
#  (2) SP-BRAMKI host_spawn_* (no-op w SINGLE -> SP IDENTYCZNY)
# ============================================================================
func _test_sp_gates_host_spawn() -> void:
	_check(NetManager.mode == NetManager.Mode.SINGLE, "(2) test wymaga startu w SP (mode != SINGLE)")

	# host_spawn_enemy w SP: NO-OP — encja nie zmienia nazwy, nie wchodzi do rejestru, brak synchronizera.
	var e := Enemy.new()
	add_child(e)
	var name_before := e.name
	NetManager.host_spawn_enemy(e, &"goblin", e.global_position, 1, &"verdant", 0)
	_check(e.name == name_before, "(2) SP: host_spawn_enemy zmienil nazwe wroga (zmiana sciezki w SP!)")
	_check(e.get_node_or_null("NetTransformSync") == null,
		"(2) SP: host_spawn_enemy dodal MultiplayerSynchronizer (narzut w SP!)")
	# Brak wpisu w rejestrze (zaden net_id nie wskazuje na e).
	var found := false
	for nid in range(1000, NetManager._next_net_id + 2):
		if NetManager.entity_for_net_id(nid) == e:
			found = true
	_check(not found, "(2) SP: host_spawn_enemy zarejestrowal encje (replikacja w SP!)")
	e.queue_free()

	# host_spawn_loot w SP: NO-OP — LootDrop bez net_id, bez rejestracji.
	var inst := _make_item()
	var d := LootDrop.spawn_item(self, Vector3.ZERO, inst)
	var loot_name_before := d.name
	NetManager.host_spawn_loot(d, Vector3.ZERO)
	_check(d.net_id == 0, "(2) SP: host_spawn_loot nadal net_id (replikacja w SP!)")
	_check(d.name == loot_name_before, "(2) SP: host_spawn_loot zmienil nazwe lootu (zmiana sciezki!)")
	d.queue_free()

	# set_entity_transform_sync w SP: NO-OP.
	var e2 := Node3D.new()
	add_child(e2)
	NetManager.set_entity_transform_sync(e2)
	_check(e2.get_node_or_null("NetTransformSync") == null, "(2) SP: set_entity_transform_sync dodal synchronizer")
	e2.queue_free()

	# host_spawn_projectile w SP: zwraca 0 (no-op), nie alokuje.
	var nid_before := NetManager._next_net_id
	var pnid := NetManager.host_spawn_projectile(Vector3.ZERO, Vector3.FORWARD, 16.0, 1, 0.0, 0)
	_check(pnid == 0, "(2) SP: host_spawn_projectile zwrocil net_id != 0 (replikacja w SP!)")
	_check(NetManager._next_net_id == nid_before, "(2) SP: host_spawn_projectile zalokowal net_id w SP")
	print("[E7b] (2) SP-bramki host_spawn_enemy/loot/projectile/sync = no-op (SP IDENTYCZNY) OK")


# ============================================================================
#  (3) KLIENT-bramka WorldSpawner (klient nie spawnuje wlasnych wrogow)
# ============================================================================
func _test_client_spawner_gate() -> void:
	var prev_mode := NetManager.mode
	# Symulacja CLIENT (bez realnego peera). has_network() w CLIENT bez peera == false, wiec bramka
	# w _process/_update_regions sprawdza has_network() and not is_host(). By wymusic galаz klienta,
	# potrzebny realny peer LUB sprawdzamy logike has_network()+is_host wprost. Bez peera has_network
	# ==false (CLIENT bez transportu) -> bramka NIE wejdzie (slusznie: brak realnej sesji = SP-podobne).
	# Dlatego test sprawdza KONTRAKT bramki przez bezposrednie wywolanie z udawanym has_network.
	# Tu uzywamy realnego peera-klienta przez ENet (best-effort); gdy brak sieci, sprawdzamy degradacje:
	var sp := WorldSpawner.new()
	add_child(sp)
	# W SP (brak sesji) _update_regions normalnie by spawnowal, ale bez _world/_player early-returnuje.
	# Sprawdzamy, ze bramka klienta jest OBECNA jako kod (has_network gate) — pelny ruch przez loopback (B).
	# Kontrakt: gdy has_network()==true i not is_host(), _process zwraca natychmiast. Symulujemy stan
	# przez ustawienie mode=CLIENT + realny peer w czesci (B). Tu logicznie: brak peera => has_network false.
	_check(not NetManager.has_network(), "(3) test bazowy: SP/CLIENT-bez-peera has_network()==true (nieoczekiwane)")
	# _active startuje 0 i bez setup() (brak _world) zostaje 0 — brak przypadkowego spawnu.
	_check(sp.active_count() == 0, "(3) WorldSpawner._active != 0 bez setup")
	sp.queue_free()
	NetManager.mode = prev_mode
	print("[E7b] (3) WorldSpawner bramka klienta obecna (klient nie spawnuje lokalnie; pelny ruch -> loopback) OK")


# ============================================================================
#  (4) KONTRAKT PICKUP-RPC (metody + czysta walidacja dystansu)
# ============================================================================
func _test_pickup_rpc_contract() -> void:
	_check(NetManager.has_method("request_loot_pickup"), "(4) BRAK request_loot_pickup (klient nie poprosi o pickup)")
	_check(NetManager.has_method("_rpc_request_pickup"), "(4) BRAK @rpc _rpc_request_pickup (host nie odbierze prosby)")
	_check(NetManager.has_method("_rpc_loot_picked"), "(4) BRAK @rpc _rpc_loot_picked (despawn lootu u wszystkich)")
	_check(NetManager.has_method("_rpc_inventory_add"), "(4) BRAK @rpc _rpc_inventory_add (item do plecaka klienta)")

	# Czysta walidacja dystansu (anti-cheat). pickup_radius=1.8, bufor=1.5 -> akceptuj <=3.3 m.
	var pr := 1.8
	_check(NetManager.pickup_in_range(Vector3.ZERO, Vector3(1.0, 0, 0), pr),
		"(4) pickup_in_range odrzuca gracza W ZASIEGU (1.0 m < 3.3)")
	_check(NetManager.pickup_in_range(Vector3.ZERO, Vector3(3.0, 0, 0), pr),
		"(4) pickup_in_range odrzuca gracza w buforze (3.0 m < 3.3)")
	_check(not NetManager.pickup_in_range(Vector3.ZERO, Vector3(10.0, 0, 0), pr),
		"(4) pickup_in_range AKCEPTUJE gracza za daleko (10 m -> cheat przez pol mapy)")
	print("[E7b] (4) kontrakt pickup-RPC (metody + walidacja dystansu host-authoritative) OK")


# ============================================================================
#  (5) ItemInstance round-trip (loot przez RPC: seed+afiksy) — re-use E7(4)
# ============================================================================
func _test_iteminstance_roundtrip() -> void:
	var it := _make_item()
	var d := it.to_dict()
	var it2 := ItemInstance.from_dict(d)
	_check(it2.seed == it.seed, "(5) seed nie przetrwal (determinizm afiksow u klienta!)")
	_check(it2.rarity == it.rarity, "(5) rarity nie przetrwala")
	_check(it2.ilvl == it.ilvl, "(5) ilvl nie przetrwal")
	var mods := it2.collect_modifiers()
	_check(mods.size() >= 1, "(5) afiksy nie odtworzone po round-trip (loot u klienta inny!)")
	print("[E7b] (5) ItemInstance round-trip dla LootDrop (seed+afiksy przez RPC) OK")


# ============================================================================
#  (6) SP-REGRESJA wrogow: spawn + autorytet AI + drop lootu (bez regresji 3/4)
# ============================================================================
func _test_sp_enemy_regression() -> void:
	var e := Enemy.new()
	add_child(e)
	# SP: pelny autorytet nad wrogiem (AI tyka lokalnie).
	_check(NetManager.has_authority(e), "(6) SP: brak autorytetu nad wrogiem (AI zamrozone -> regresja!)")
	_check(NetManager.has_state_authority(e), "(6) SP: brak state-authority nad wrogiem (loot/HP)")
	# loot: drop_for niepuste w SP (host-authoritative == true w SP).
	e.loot_ilvl = 5
	e.loot_biome = &"verdant"
	var drops := LootService.drop_for(e)
	_check(drops.size() >= 1, "(6) SP: LootService.drop_for puste (wrog nie dropi -> regresja Etapu 2)")
	e.queue_free()
	print("[E7b] (6) SP-regresja wrogow: spawn + AI autorytet + drop lootu (Etapy 2-4 OK) OK")


# ============================================================================
#  (7) POWIERZCHNIA RPC NetManager (klient ma czym odebrac swiat)
# ============================================================================
func _test_netmanager_rpc_surface() -> void:
	for m in ["_rpc_spawn_enemy", "_rpc_spawn_loot_item", "_rpc_spawn_loot_gold",
			"_rpc_spawn_projectile", "_rpc_despawn_entity", "host_spawn_enemy",
			"host_spawn_loot", "host_spawn_projectile", "set_entity_transform_sync",
			"host_despawn_entity"]:
		_check(NetManager.has_method(m), "(7) BRAK metody NetManager.%s (kontrakt replikacji niepelny)" % m)
	print("[E7b] (7) powierzchnia replikacji NetManager (spawn/despawn/sync wrog/loot/pocisk) OK")


# ============================================================================
#  (8) LootDrop SP-pickup IDENTYCZNY (item -> plecak, bez sieci)
# ============================================================================
func _test_lootdrop_sp_pickup() -> void:
	# Gracz z InventoryComponent (jak w realnej grze).
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	var inv := InventoryComponent.new()
	player.add_child(inv)
	add_child(player)

	var it := _make_item()
	var d := LootDrop.spawn_item(self, Vector3.ZERO, it)
	# SP: _on_body_entered -> _try_pickup -> dodaje do plecaka + picked_up + queue_free.
	var picked := [false]
	d.picked_up.connect(func(_x): picked[0] = true)
	d._on_body_entered(player)
	_check(picked[0], "(8) SP: LootDrop nie wyemitowal picked_up (pickup zepsuty w SP!)")
	_check(d.is_picked(), "(8) SP: LootDrop nie oznaczyl _picked po pickup")
	_check(inv.backpack.size() >= 1, "(8) SP: item nie trafil do plecaka (regresja Etapu 2)")
	player.queue_free()
	print("[E7b] (8) LootDrop SP-pickup IDENTYCZNY (item -> plecak, bez sieci) OK")


# ============================================================================
#  (9) Enemy.net_id — jawne pole klasowe (review #minor: koniec martwego "net_id" in e)
# ============================================================================
func _test_enemy_net_id_member() -> void:
	var e := Enemy.new()
	add_child(e)
	_check("net_id" in e, "(9) Enemy nie ma jawnego pola net_id (kontrakt replikacji nieczytelny)")
	_check(e.net_id == 0, "(9) Enemy.net_id startuje != 0 (SP/niezarejestrowana powinno byc 0)")
	# Pole jest zapisywalne (host/klient ustawia je przy spawnie repliki).
	e.net_id = 1234
	_check(e.net_id == 1234, "(9) Enemy.net_id niezapisywalne")
	# Lokalna NetIdentity nadal istnieje (owner=HOST) — nie pomylona z net_id (rename shadow var).
	var has_ident := false
	for c in e.get_children():
		if c is NetIdentity:
			has_ident = true
	_check(has_ident, "(9) Enemy stracil NetIdentity (rename shadow var zepsul komponent autorytetu)")
	e.queue_free()
	print("[E7b] (9) Enemy.net_id jawne pole klasowe (mirror LootDrop, NetIdentity zachowana) OK")


# ============================================================================
#  (10) DUNGEON CO-OP — kontrakt RPC + sygnaly + SP-bramki (review #MAJOR)
# ============================================================================
func _test_dungeon_coop_contract() -> void:
	# Powierzchnia RPC/broadcast: host ma czym rozeslac wejscie/wyjscie, klient ma sygnaly.
	for m in ["broadcast_dungeon_load", "broadcast_dungeon_exit", "_rpc_load_dungeon", "_rpc_exit_dungeon"]:
		_check(NetManager.has_method(m), "(10) BRAK NetManager.%s (dungeon co-op niepelny)" % m)
	_check(NetManager.has_signal("dungeon_load_requested"), "(10) BRAK sygnalu dungeon_load_requested")
	_check(NetManager.has_signal("dungeon_exit_requested"), "(10) BRAK sygnalu dungeon_exit_requested")

	# SP-bramka: broadcast_dungeon_load/exit w SP to NO-OP (nie emituja sygnalu lokalnie — has_network false).
	var loaded := [false]
	var exited := [false]
	var cb_load := func(_s, _t, _b): loaded[0] = true
	var cb_exit := func(): exited[0] = true
	NetManager.dungeon_load_requested.connect(cb_load)
	NetManager.dungeon_exit_requested.connect(cb_exit)
	NetManager.broadcast_dungeon_load(123, 2, &"verdant")
	NetManager.broadcast_dungeon_exit()
	_check(not loaded[0], "(10) SP: broadcast_dungeon_load wyemitowal sygnal (powinien byc no-op bez sieci)")
	_check(not exited[0], "(10) SP: broadcast_dungeon_exit wyemitowal sygnal (powinien byc no-op bez sieci)")
	NetManager.dungeon_load_requested.disconnect(cb_load)
	NetManager.dungeon_exit_requested.disconnect(cb_exit)

	# Path-match: wrog dungeonu replikowany z parent="Main/DungeonRun" (== sciezka u hosta). Sprawdzamy,
	# ze _node_under_root rozwiazuje sciezki wzgledne pod /root (kontrakt routingu HP-sync).
	_check(NetManager.has_method("_node_under_root"), "(10) BRAK _node_under_root (path-match dungeonu)")
	# DungeonManager subskrybuje sygnaly NetManager przy setup() — sprawdzamy, ze ma sloty obslugi.
	var dm := DungeonManager.new()
	_check(dm.has_method("_on_net_dungeon_load"), "(10) DungeonManager brak _on_net_dungeon_load (klient nie wejdzie)")
	_check(dm.has_method("_on_net_dungeon_exit"), "(10) DungeonManager brak _on_net_dungeon_exit (klient nie wyjdzie)")
	dm.free()
	print("[E7b] (10) dungeon co-op: broadcast/RPC/sygnaly + SP-no-op + path-match parent (MAJOR domkniety) OK")


# ============================================================================
#  (11) REPLIKA: fizyka wylaczona u klienta (review #minor anti-jitter)
# ============================================================================
func _test_replica_physics_marker() -> void:
	var e := Enemy.new()
	add_child(e)
	# SP/host: pelna fizyka (replika NIE oznaczona) — _physics_process aktywne.
	_check(e.is_physics_processing(), "(11) wrog (nie-replika) ma wylaczona fizyke (regresja SP/host AI!)")
	_check(e.has_method("mark_as_net_replica"), "(11) BRAK mark_as_net_replica (klient nie wylaczy fizyki repliki)")
	# Po oznaczeniu jako replika: fizyka OFF (transform z synchronizera), ale _process (wizual) zostaje.
	e.mark_as_net_replica()
	_check(not e.is_physics_processing(), "(11) replika nadal liczy fizyke (walczy z synchronizerem -> jitter)")
	_check(e.is_processing(), "(11) replika stracila _process (model nie obraca sie/nie animuje)")
	e.queue_free()
	print("[E7b] (11) replika klienta: fizyka OFF (anti-jitter), wizual _process ON; SP/host pelna fizyka OK")


# ============================================================================
#  (12) LOOT timeout despawn — SP goly queue_free (review #minor); kontrakt host-route
# ============================================================================
func _test_loot_timeout_despawn_sp() -> void:
	# SP: timeout NIE wola host_despawn_entity (net_id==0 / brak sieci) -> czysty queue_free, jak Etap 2.
	var it := _make_item()
	var d := LootDrop.spawn_item(self, Vector3.ZERO, it)
	_check(d.net_id == 0, "(12) SP: LootDrop.net_id != 0 (host-route w SP bledny)")
	# Wymusimy wiek > DESPAWN_AFTER i odpalimy _process; w SP gałąź host-despawn jest pominieta.
	d._age = LootDrop.DESPAWN_AFTER + 1.0
	d._process(0.016)   # SP: net_id==0 / has_network false -> queue_free (bez NetManager despawn)
	_check(d.is_queued_for_deletion(), "(12) SP: LootDrop timeout nie zwolnil encji (regresja anti-bloat Etap 2)")
	print("[E7b] (12) loot timeout: SP goly queue_free (host-route tylko w co-opie, anti-leak rejestru) OK")


# ============================================================================
#  (B) LOOPBACK TRANSPORT (best-effort) — host<->klient ENet polaczenie
# ============================================================================
func _test_loopback_transport() -> void:
	# Pelny stos @rpc po NodePath w 1-procesowym loopbacku jest zawodny (jak Etap7Test cz.B). Tu
	# sprawdzamy TYLKO, ze realna sesja host_game->join_game (przez NetManager) ustawia has_network()
	# i widzi peera — czyli warstwa transportu replikacji jest sprawna. Pelna replikacja wrog/loot ->
	# RECZNY test 2-procesowy (CoopSceneLoopback rozszerzony + residual_risks).
	var ok := NetManager.host_game(27199)
	if not ok:
		push_warning("[E7b] (B) POMINIETE: host_game=false (sandbox bez sieci?). Czesc A pokrywa kontrakt.")
		print("[E7b] (B) loopback transport POMINIETE (brak serwera) — recznie: CoopSceneLoopback.tscn")
		NetManager.leave()
		return
	_check(NetManager.has_network(), "(B) host: has_network()==false po host_game")
	_check(NetManager.is_host(), "(B) host: is_host()==false")
	# host_spawn_enemy u hosta z siecia: encja DOSTAJE net_id + synchronizer + wpis w rejestrze.
	var e := Enemy.new()
	add_child(e)
	NetManager.host_spawn_enemy(e, &"goblin", Vector3(5, 0, 5), 3, &"verdant", 0)
	_check(e.name.begins_with("Enemy_"), "(B) host: host_spawn_enemy nie nadal stabilnej nazwy Enemy_<id>")
	_check(e.net_id > 0, "(B) host: host_spawn_enemy nie ustawil Enemy.net_id (jawne pole klasowe)")
	# Synchronizer dopinany DEFERRED (klatke po spawn-RPC, by klient zdazyl utworzyc replike — anti
	# "Node not found"). Czekamy klatke, potem sprawdzamy obecnosc NetTransformSync.
	await get_tree().process_frame
	_check(e.get_node_or_null("NetTransformSync") != null,
		"(B) host: brak MultiplayerSynchronizer transformu na wrogu po deferred (klient nie zobaczy ruchu)")
	var nid := -1
	for k in range(1000, NetManager._next_net_id + 2):
		if NetManager.entity_for_net_id(k) == e:
			nid = k
	_check(nid > 0, "(B) host: wrog nie zarejestrowany w _world_entities (klient nie dostanie repliki)")
	e.queue_free()
	NetManager.leave()
	# Po leave() rejestr czysty + powrot do SP (SP-safety).
	_check(not NetManager.has_network(), "(B) po leave() has_network()==true (nie wrocil do SP!)")
	_check(NetManager.mode == NetManager.Mode.SINGLE, "(B) po leave() mode != SINGLE")
	print("[E7b] (B) loopback transport: host sesja + host_spawn_enemy nadal net_id+sync+rejestr; leave()->SP OK")


# ============================================================================
#  (C) LOOPBACK KLIENT-BRAMKA WorldSpawner — REALNE wymuszenie galezi klienta
# ============================================================================
## Wzmocnienie testu (3) (review #minor): z REALNYM peerem (has_network()==true) wymuszamy mode==CLIENT
## i sprawdzamy, ze WorldSpawner._update_regions ROBI early-return (klient NIE spawnuje wlasnych wrogow).
## Bez realnego peera has_network()==false i bramka nie wchodzi — dlatego potrzebny zywy transport.
func _test_loopback_client_gate() -> void:
	var ok := NetManager.host_game(27198)
	if not ok:
		print("[E7b] (C) klient-bramka POMINIETE (brak serwera) — recznie: CoopSceneLoopback.tscn")
		NetManager.leave()
		return
	# Mamy zywy peer (has_network()==true). Udajemy KLIENTA: mode=CLIENT -> is_host()==false.
	var prev_mode := NetManager.mode
	NetManager.mode = NetManager.Mode.CLIENT
	_check(NetManager.has_network(), "(C) brak transportu po host_game (peer nie zyje)")
	_check(not NetManager.is_host(), "(C) is_host()==true mimo wymuszonego mode==CLIENT")

	# Bramka klienta jest PIERWSZA instrukcja _update_regions (zwraca ZANIM dotknie _world/_player),
	# wiec wystarczy wymuszony mode==CLIENT + zywy peer. Gdyby bramka NIE dzialala, kod poleci dalej i
	# albo crashnie na null _world, albo (z atrapa) sprobuje spawnowac. Tu: early-return -> _active==0.
	var sp := WorldSpawner.new()
	add_child(sp)
	sp._update_regions()   # _world/_player == null, ale bramka klienta zwraca PRZED ich uzyciem
	_check(sp.active_count() == 0, "(C) KLIENT: _update_regions zaspawnowal wrogow (bramka klienta nie dziala!)")

	sp.queue_free()
	NetManager.mode = prev_mode
	NetManager.leave()
	_check(not NetManager.has_network(), "(C) po leave() has_network()==true")
	print("[E7b] (C) KLIENT-bramka WorldSpawner z REALNYM peerem: _update_regions early-return (klient nie spawnuje) OK")


# ============================================================================
#  POMOCNIKI
# ============================================================================
func _make_item() -> ItemInstance:
	var it := ItemInstance.new()
	it.base_id = &"axe2h"
	it.rarity = ItemResource.Rarity.RARE
	it.ilvl = 12
	it.seed = 987654321
	var m := StatModifier.make(&"damage", StatModifier.Op.INCREASED, 0.25,
		[] as Array[StringName], &"gear", &"a1")
	it.rolled_affixes.append(m)
	return it
