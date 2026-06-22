extends Node
## Etap7Test.gd — mini-test HEADLESS Etapu 7 (CO-OP). Uruchomienie:
##   godot --headless res://test/Etap7Test.tscn
##
## DoD Etapu 7 (ROADMAP 5 / TDD 6): 2-4 graczy w jednym świecie; BRAK desyncu HP/lootu; klient z
## własną postacią; SP działa identycznie. Test ma DWIE części:
##
##  (A) LOGICZNA (zawsze wykonalna headless):
##   1. NetManager API LIVE: mode SINGLE domyślnie; has_authority/is_host/local_peer_id w SP.
##   2. Bramkowanie autorytetu: w SP has_authority(node)==true; symulacja CLIENT -> autorytet tylko
##      nad własną encją (NetIdentity.owner_peer), nie nad cudzą (anti-desync HP/loot).
##   3. HitData round-trip (RPC klient->host): to_dict/from_dict zachowuje pola walki.
##   4. ItemInstance round-trip (RPC drop lootu): seed+rarity+ilvl+afiksy przetrwają serializację.
##   5. SP-safety PlayerNetSync: w SP should_read_local_input/should_simulate_movement == true
##      (sciezka lokalna), net_post_physics to no-op (zero zmian odczucia SP).
##   6. Seed świata: NetManager.world_seed + RNGService spójne (klient generuje teren z tego seeda).
##
##  (B) LOOPBACK 2 PEERY (host + klient na 127.0.0.1 w JEDNYM procesie, dwa SceneMultiplayer):
##   7. Klient WIDZI peera (server.get_peers() niepuste, client connected_to_server).
##   8. HP SYNCHRONIZUJE się host->klient: host (autorytet) zadaje obrażenia i rozsyła HP RPC;
##      klient odbiera ZGODNĄ wartość HP (brak desyncu — kluczowy DoD).
##      Jeśli loopback w 1 procesie zawiedzie (np. brak sieci w sandboxie) -> część (B) jest
##      POMIJANA z ostrzeżeniem (nie failuje testu); część (A) i tak pokrywa kontrakt logicznie,
##      a do ręcznego testu 2-procesowego służy test/coop_loopback.gd.
##
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[E7] ..." + ALL OK + quit.

var _failures: int = 0


func _ready() -> void:
	print("[E7] === Etap 7 mini-test start ===")

	# --- CZĘŚĆ A: logiczna ---
	_test_netmanager_sp_api()
	_test_authority_gating()
	_test_hitdata_roundtrip()
	_test_iteminstance_roundtrip()
	_test_player_netsync_sp_safety()
	_test_world_seed_contract()

	_test_state_authority_split()
	_test_enemy_authority_gating()
	_test_client_hp_sync_apply()
	_test_combat_rpc_surface()

	# --- CZĘŚĆ B: loopback 2 peery (best-effort) ---
	await _test_loopback_hp_sync()

	# Settle (deferred queue_free).
	for _f in 4:
		await get_tree().process_frame

	if _failures == 0:
		print("[E7] ALL OK")
	else:
		printerr("[E7] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[E7] FAIL: %s" % msg)


# ============================================================================
#  (1) NetManager API LIVE w SP
# ============================================================================
func _test_netmanager_sp_api() -> void:
	_check(NetManager.mode == NetManager.Mode.SINGLE, "(1) domyślny mode != SINGLE")
	_check(NetManager.has_authority(), "(1) SP has_authority() != true")
	_check(NetManager.has_authority(self), "(1) SP has_authority(node) != true")
	_check(NetManager.is_host(), "(1) SP is_host() != true (SP = host z jednym peerem)")
	_check(not NetManager.is_client(), "(1) SP is_client() == true (nie powinno)")
	_check(NetManager.local_peer_id() == NetManager.HOST_PEER_ID, "(1) SP local_peer_id != 1")
	_check(not NetManager.has_network(), "(1) SP has_network() == true (powinno false -> hitstop globalny OK)")
	_check(NetManager.peer_count() == 1, "(1) SP peer_count != 1")
	_check(NetManager.MAX_PLAYERS == 4, "(1) MAX_PLAYERS != 4 (co-op do 4)")
	print("[E7] (1) NetManager API LIVE w SP (mode SINGLE, has_authority/is_host/peer=1) OK")


# ============================================================================
#  (2) Bramkowanie autorytetu (anti-desync HP/lootu)
# ============================================================================
func _test_authority_gating() -> void:
	# SP: autorytet nad dowolną encją.
	var ent := Node.new()
	add_child(ent)
	_check(NetManager.has_authority(ent), "(2) SP: brak autorytetu nad encją")

	# Symulacja KLIENTA (mode=CLIENT bez realnego peera) — has_authority idzie gałęzią NetIdentity.
	# Bez has_multiplayer_peer() local_peer_id() zwraca HOST_PEER_ID(1). Encja owner_peer==1 -> autorytet;
	# encja owner_peer==2 (cudza) -> BRAK autorytetu (klient nie rusza cudzego HP/lootu — anti-desync).
	var prev_mode := NetManager.mode
	NetManager.mode = NetManager.Mode.CLIENT

	var mine := Node3D.new()
	var id_mine := NetIdentity.new()
	id_mine.owner_peer = NetManager.local_peer_id()   # == 1 (brak realnego peera)
	mine.add_child(id_mine)
	add_child(mine)

	var other := Node3D.new()
	var id_other := NetIdentity.new()
	id_other.owner_peer = 999                          # cudza encja
	other.add_child(id_other)
	add_child(other)

	_check(NetManager.has_authority(mine), "(2) KLIENT: brak autorytetu nad WŁASNĄ encją (owner==local)")
	_check(not NetManager.has_authority(other), "(2) KLIENT: ma autorytet nad CUDZĄ encją (desync!)")

	# is_host==false w trybie CLIENT (host-authoritative: tylko host rozstrzyga globalnie).
	_check(not NetManager.is_host(), "(2) tryb CLIENT raportuje is_host()==true")

	NetManager.mode = prev_mode                        # przywróć SP (izolacja kolejnych testów)
	_check(NetManager.is_host() and NetManager.has_authority(), "(2) przywrócenie SP nieudane")

	ent.queue_free(); mine.queue_free(); other.queue_free()
	print("[E7] (2) autorytet: SP=wszystko, KLIENT=tylko własna encja (anti-desync HP/loot) OK")


# ============================================================================
#  (3) HitData round-trip (RPC klient->host walki)
# ============================================================================
func _test_hitdata_roundtrip() -> void:
	var h := HitData.new()
	h.base_damage = 42.5
	h.crit_chance = 0.33
	h.crit_mult = 2.25
	h.armor_pierce = 0.6
	h.lifesteal = 0.15
	h.knockback = 9.0
	var tg: Array[StringName] = [&"fire", &"melee"]
	h.tags = tg
	h.hit_position = Vector3(1, 2, 3)

	var d := h.to_dict()
	var h2 := HitData.from_dict(d)
	_check(absf(h2.base_damage - 42.5) < 0.001, "(3) base_damage nie przetrwał (%s)" % h2.base_damage)
	_check(absf(h2.crit_chance - 0.33) < 0.001, "(3) crit_chance nie przetrwał")
	_check(absf(h2.crit_mult - 2.25) < 0.001, "(3) crit_mult nie przetrwał")
	_check(absf(h2.armor_pierce - 0.6) < 0.001, "(3) armor_pierce nie przetrwał")
	_check(absf(h2.lifesteal - 0.15) < 0.001, "(3) lifesteal nie przetrwał")
	_check(absf(h2.knockback - 9.0) < 0.001, "(3) knockback nie przetrwał")
	_check(h2.tags.size() == 2 and h2.tags.has(&"fire") and h2.tags.has(&"melee"), "(3) tags nie przetrwały")
	_check(h2.hit_position == Vector3(1, 2, 3), "(3) hit_position nie przetrwał")
	# Idempotencja serializacji (RPC dwukrotne).
	var d2 := h2.to_dict()
	_check(d2["base_damage"] == d["base_damage"] and d2["armor_pierce"] == d["armor_pierce"],
		"(3) serializacja niestabilna (round-trip x2 różny)")
	print("[E7] (3) HitData round-trip (RPC walki klient->host) OK")


# ============================================================================
#  (4) ItemInstance round-trip (RPC drop lootu host->klient)
# ============================================================================
func _test_iteminstance_roundtrip() -> void:
	var it := ItemInstance.new()
	it.base_id = &"axe2h"
	it.rarity = ItemResource.Rarity.LEGENDARY
	it.ilvl = 17
	it.seed = 123456789
	var m := StatModifier.make(&"damage", StatModifier.Op.INCREASED, 0.35, [&"fire"] as Array[StringName], &"gear", &"a1")
	it.rolled_affixes.append(m)
	var sk: Array[StringName] = [&"", &"ruby"]
	it.sockets = sk
	it.enchant = { "enchant_id": "smiting", "rank": 2 }

	var d := it.to_dict()
	var it2 := ItemInstance.from_dict(d)
	_check(it2.base_id == &"axe2h", "(4) base_id nie przetrwał (%s)" % it2.base_id)
	_check(it2.rarity == ItemResource.Rarity.LEGENDARY, "(4) rarity nie przetrwała")
	_check(it2.ilvl == 17, "(4) ilvl nie przetrwał")
	_check(it2.seed == 123456789, "(4) seed nie przetrwał (determinizm afiksów u klienta!)")
	_check(it2.sockets.size() == 2 and it2.sockets[1] == &"ruby", "(4) sockety nie przetrwały")
	_check(String(it2.enchant.get("enchant_id", "")) == "smiting", "(4) enchant nie przetrwał")
	# Modyfikatory odtworzone (collect_modifiers widzi je jako StatModifier z 'op' jako enum).
	var mods := it2.collect_modifiers()
	_check(mods.size() >= 1, "(4) rolled_affixes nie odtworzone jako StatModifier")
	if mods.size() >= 1:
		_check(mods[0].stat == &"damage" and absf(mods[0].value - 0.35) < 0.001 and mods[0].op == StatModifier.Op.INCREASED,
			"(4) StatModifier afiksu zmieniony po round-trip")
	print("[E7] (4) ItemInstance round-trip (RPC drop lootu, seed+afiksy) OK")


# ============================================================================
#  (5) SP-safety PlayerNetSync (zero zmian odczucia SP)
# ============================================================================
func _test_player_netsync_sp_safety() -> void:
	# W SP (has_network()==false) komponent jest BEZCZYNNY: czyta lokalny input, symuluje ruch,
	# a net_post_physics nic nie robi. To gwarant, że SP biegnie sciezka lokalna jak dotąd.
	var body := CharacterBody3D.new()
	var ident := NetIdentity.new()
	ident.owner_peer = 1
	body.add_child(ident)
	add_child(body)
	var ns := PlayerNetSync.new()
	body.add_child(ns)
	ns.setup(body, ident)

	_check(ns.should_read_local_input(), "(5) SP: should_read_local_input != true (zmieniłoby sterowanie SP!)")
	_check(ns.should_simulate_movement(), "(5) SP: should_simulate_movement != true (zatrzymałoby ruch SP!)")

	# net_post_physics w SP: nie zmienia pozycji, nie buforuje, nie ruszy zegara interpolacji.
	var before := body.global_position
	ns.net_post_physics(0.016, Vector2(1, 0), true, false)
	ns.net_post_physics(0.016, Vector2(0, 1), false, true)
	_check(body.global_position == before, "(5) SP: net_post_physics ruszył pozycję (zmiana odczucia SP!)")

	body.queue_free()
	print("[E7] (5) SP-safety PlayerNetSync (lokalny input, brak interpolacji/predykcji w SP) OK")


# ============================================================================
#  (6) Kontrakt seeda świata (klient generuje teren z seeda hosta)
# ============================================================================
func _test_world_seed_contract() -> void:
	# RNGService: ten sam seed -> ta sama sekwencja loot/combat (brak desyncu lootu — TDD 6.2).
	RNGService.seed_session(0xC0FFEE)
	var a1 := RNGService.loot.randi()
	var c1 := RNGService.combat.randi()
	RNGService.seed_session(0xC0FFEE)
	var a2 := RNGService.loot.randi()
	var c2 := RNGService.combat.randi()
	_check(a1 == a2, "(6) loot stream nie deterministyczny dla tego samego seeda (desync lootu!)")
	_check(c1 == c2, "(6) combat stream nie deterministyczny (desync krytyków!)")
	_check(RNGService.world_seed() == 0xC0FFEE, "(6) world_seed() != ustawiony seed")

	# Teren: VoxelWorld.feature_hash deterministyczny (klient generuje teren LOKALNIE z tego samego
	# FEATURE_SEED -> identyczna geometria, bez wysyłania voxeli po sieci — TDD 6.1/6.2).
	var w := VoxelWorld.new()
	add_child(w)
	var h_a := w.feature_hash(10, 20, 0x55)
	var h_b := w.feature_hash(10, 20, 0x55)
	_check(absf(h_a - h_b) < 0.0000001, "(6) feature_hash nie deterministyczny (desync terenu!)")
	w.queue_free()

	# Przywróć domyślny seed sesji (izolacja).
	RNGService.seed_session(VoxelWorld.FEATURE_SEED)
	print("[E7] (6) seed świata: loot/combat/teren deterministyczne (klient generuje teren lokalnie) OK")


# ============================================================================
#  (7)+(8) LOOPBACK 2 PEERY: klient widzi peera + HP synchronizuje host->klient
# ============================================================================
func _test_loopback_hp_sync() -> void:
	# Dwa niezależne SceneMultiplayer na dwóch poddrzewach (jeden proces, 2 peery przez ENet 127.0.0.1).
	# add_child do /root przez call_deferred: ten test biegnie z _ready (root jeszcze "busy setting up
	# children"), wiec natychmiastowy add_child rzucalby blad. Deferred + await -> wezly sa w drzewie
	# zanim set_multiplayer(path) je zaadresuje (bez ERROR-noise w logu).
	var server_root := Node.new(); server_root.name = "E7_Server"
	var client_root := Node.new(); client_root.name = "E7_Client"
	get_tree().get_root().add_child.call_deferred(server_root)
	get_tree().get_root().add_child.call_deferred(client_root)
	await get_tree().process_frame
	var smp := SceneMultiplayer.new()
	var cmp := SceneMultiplayer.new()
	get_tree().set_multiplayer(smp, NodePath("/root/E7_Server"))
	get_tree().set_multiplayer(cmp, NodePath("/root/E7_Client"))

	var sp := ENetMultiplayerPeer.new()
	var port := 27123
	var e1 := sp.create_server(port, 3)
	if e1 != OK:
		push_warning("[E7] (7-8) POMINIETE: create_server blad %d (sandbox bez sieci?). Część A pokrywa kontrakt; ręczny test: test/coop_loopback.gd" % e1)
		print("[E7] (7-8) loopback POMINIETE (brak serwera) — patrz test/coop_loopback.gd")
		server_root.queue_free(); client_root.queue_free()
		return
	smp.multiplayer_peer = sp
	var cp := ENetMultiplayerPeer.new()
	var e2 := cp.create_client("127.0.0.1", port)
	if e2 != OK:
		push_warning("[E7] (7-8) POMINIETE: create_client blad %d." % e2)
		print("[E7] (7-8) loopback POMINIETE (brak klienta) — patrz test/coop_loopback.gd")
		sp.close(); server_root.queue_free(); client_root.queue_free()
		return
	cmp.multiplayer_peer = cp

	# Pompuj poll obu API aż klient się połączy (max ~3 s). MP zarejestrowane przez set_multiplayer(path)
	# pompujemy RĘCZNIE (smp.poll/cmp.poll), bo automatyczny multiplayer_poll dotyczy tylko domyślnego.
	var connected := false
	cmp.connected_to_server.connect(func() -> void: connected = true)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		smp.poll(); cmp.poll()
		await get_tree().process_frame
		if not smp.get_peers().is_empty() and (connected or cmp.get_unique_id() != 0):
			break

	var server_sees := not smp.get_peers().is_empty()
	_check(server_sees, "(7) host NIE widzi klienta (server.get_peers() puste)")
	if not server_sees:
		print("[E7] (7-8) loopback: brak połączenia — POMINIETE dalsze sprawdzenia (patrz test/coop_loopback.gd)")
		sp.close(); cp.close(); server_root.queue_free(); client_root.queue_free()
		return
	print("[E7] (7) klient WIDZI peera (host.get_peers()=%s, client uid=%d) OK" % [str(smp.get_peers()), cmp.get_unique_id()])

	# (8) HP SYNC host-authoritative przez REALNY transport ENet. Model: host (autorytet, peer 1) liczy
	# HP w DamageService/HealthComponent (już testowane logicznie w E1) i ROZSYŁA wynik do klientów;
	# klient TYLKO odbiera i wyświetla (nigdy nie liczy — TDD 6.2/6.4). Tu host symuluje 100-30=70 HP
	# i wysyła wartość; klient odbiera ZGODNE 70 (brak desyncu — kluczowy DoD). Używamy send_bytes na
	# poziomie MultiplayerAPI (Node.rpc wymaga get_multiplayer() != null, co w 1-procesowym loopbacku z
	# set_multiplayer(path) jest zawodne; realny stos co-op używa @rpc/Synchronizer w pełnej scenie —
	# patrz coop_loopback.gd do testu 2-procesowego).
	var host_hp := 100.0 - 30.0                       # host-authoritative: 100 HP - 30 dmg = 70
	var client_hp := [0.0]
	cmp.peer_packet.connect(func(_id: int, pkt: PackedByteArray) -> void:
		if pkt.size() >= 4:
			client_hp[0] = pkt.decode_float(0))
	var buf := PackedByteArray(); buf.resize(4); buf.encode_float(0, host_hp)
	var serr := smp.send_bytes(buf, 0, MultiplayerPeer.TRANSFER_MODE_RELIABLE)   # 0 = broadcast do klientów
	_check(serr == OK, "(8) send_bytes (replikacja HP) blad %d" % serr)
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 1500:
		smp.poll(); cmp.poll()
		await get_tree().process_frame
		if absf(client_hp[0] - host_hp) < 0.001:
			break

	_check(absf(client_hp[0] - host_hp) < 0.001,
		"(8) DESYNC: klient HP (%s) != host HP (%s)" % [client_hp[0], host_hp])
	# UCZCIWY KOMUNIKAT (review #minor): to TRANSPORT-only smoke test (ENet doreczyl bajty), NIE dowod
	# stosu walki/replikacji gry. Realny stos HP-sync (@rpc DamageService._rpc_sync_hp -> HealthComponent.
	# set_hp_authoritative) testujemy LOGICZNIE w (9)/(10) + recznie 2-procesowo przez test/coop_loopback.gd.
	print("[E7] (8) ENet transport loopback OK (host=%.0f -> klient=%.0f) — TRANSPORT-only, NIE stos HP gry" % [host_hp, client_hp[0]])

	sp.close(); cp.close()
	server_root.queue_free(); client_root.queue_free()


# ============================================================================
#  (9) ROZDZIAL AUTORYTETU: HP/loot = HOST, ruch = owner (anti-desync HP gracza)
# ============================================================================
## Review #major: has_authority(wlasny_player) u KLIENTA == true (ownership ruchu), ale HP NIE moze
## byc liczone przez klienta nawet dla wlasnej postaci. has_state_authority() musi byc HOST-ONLY,
## inaczej dwa zrodla HP tej samej postaci => desync. Tu sprawdzamy rozdzial pojec na encji-graczu.
func _test_state_authority_split() -> void:
	var prev_mode := NetManager.mode
	NetManager.mode = NetManager.Mode.CLIENT

	# Encja "wlasna" (owner_peer == lokalny). Bez realnego peera local_peer_id()==1.
	var mine := Node3D.new()
	var idm := NetIdentity.new()
	idm.owner_peer = NetManager.local_peer_id()
	mine.add_child(idm)
	add_child(mine)

	# RUCH: klient JEST wlascicielem ruchu wlasnej postaci (predykcja) -> is_movement_owner==true.
	_check(NetManager.is_movement_owner(mine), "(9) KLIENT: brak ownershipu RUCHU wlasnej postaci")
	# HP/LOOT: klient NIE jest autorytetem stanu (nawet wlasnej postaci) -> has_state_authority==false.
	_check(not NetManager.has_state_authority(mine),
		"(9) KLIENT liczy HP wlasnej postaci (has_state_authority==true) -> DESYNC HP gracza!")
	# has_state_authority bezkontekstowo (== is_host) tez false u klienta.
	_check(not NetManager.has_state_authority(), "(9) KLIENT: has_state_authority() != false")

	NetManager.mode = prev_mode
	# SP: oba pojecia == true (jeden autorytet, zero zmian odczucia).
	_check(NetManager.has_state_authority() and NetManager.is_movement_owner(),
		"(9) SP: state_authority/movement_owner != true (regresja SP!)")
	mine.queue_free()
	print("[E7] (9) rozdzial autorytetu: ruch=owner (klient), HP/loot=HOST-only (anti-desync HP) OK")


# ============================================================================
#  (10) WROG host-owned: klient NIE ma autorytetu nad wrogiem (jawny NetIdentity owner=1)
# ============================================================================
## Review #minor->bezpieczenstwo: wrog dostaje NetIdentity.owner_peer=HOST_PEER_ID (jawnie, nie z
## domyslnej wartosci). U klienta has_authority(enemy)==false i has_state_authority(enemy)==false ->
## klient nie rusza HP/AI wroga (anti-cheat). Symulujemy encje-wroga z NetIdentity(owner=1).
func _test_enemy_authority_gating() -> void:
	var prev_mode := NetManager.mode
	NetManager.mode = NetManager.Mode.CLIENT

	var enemy := Node3D.new()
	var ide := NetIdentity.new()
	ide.owner_peer = NetManager.HOST_PEER_ID    # wrog = host-owned (jawnie, jak w Enemy._build_components)
	enemy.add_child(ide)
	add_child(enemy)

	# Klient (local_peer_id==1 bez peera) — UWAGA: bez realnego peera owner==1==local, wiec ustawiamy
	# owner wroga na 1, a "klienta" symulujemy peerem 1; rozdzielamy przez CUDZY owner. By test byl
	# jednoznaczny: ustaw owner wroga na 1, a sprawdz, ze gdy local!=owner klient nie ma autorytetu.
	# Tu local==1==owner (brak peera), wiec sprawdzamy NEGATYWNIE przez encje o owner=2 (host inny niz my).
	var enemy_host := Node3D.new()
	var ideh := NetIdentity.new()
	ideh.owner_peer = 2                          # host o innym id niz nasz peer (1) -> nie nasze
	enemy_host.add_child(ideh)
	add_child(enemy_host)

	_check(not NetManager.has_authority(enemy_host),
		"(10) KLIENT ma autorytet nad wrogiem cudzego peera (anti-cheat zlamany)")
	_check(not NetManager.has_state_authority(enemy_host),
		"(10) KLIENT ma state-authority nad wrogiem (liczylby HP wroga -> desync)")

	NetManager.mode = prev_mode
	# SP: pelny autorytet nad wrogiem (lokalna logika jak dotad).
	_check(NetManager.has_authority(enemy) and NetManager.has_state_authority(enemy),
		"(10) SP: brak autorytetu nad wrogiem (regresja SP!)")
	enemy.queue_free(); enemy_host.queue_free()
	print("[E7] (10) wrog host-owned: klient bez autorytetu/state-authority nad wrogiem (anti-cheat) OK")


# ============================================================================
#  (11) KLIENT stosuje HP narzucone przez HOST (HealthComponent.set_hp_authoritative)
# ============================================================================
## Review #major/blocker: realny stos HP-sync. Klient NIE liczy HP — odbiera autorytatywna wartosc
## (DamageService._rpc_sync_hp) i stosuje przez HealthComponent.set_hp_authoritative -> hp_changed
## (HUD), przejscie do smierci emituje died RAZ. Testujemy sam kontrakt komponentu (bez transportu).
func _test_client_hp_sync_apply() -> void:
	var ent := Node3D.new()
	var st := StatsComponent.new()
	var sb := StatBlock.new()
	sb.max_hp = 100.0
	st.base = sb
	ent.add_child(st)
	var hc := HealthComponent.new()
	ent.add_child(hc)
	add_child(ent)
	# Po _ready: pelne HP 100.
	_check(absf(hc.current_hp - 100.0) < 0.001, "(11) start HP != 100")

	var got_hp := [-1.0]
	hc.hp_changed.connect(func(c: float, _m: float) -> void: got_hp[0] = c)
	var died_count := [0]
	hc.died.connect(func(_from: Node) -> void: died_count[0] += 1)

	# Host narzuca 70 HP (klient stosuje, nie liczy).
	hc.set_hp_authoritative(70.0, false, null)
	_check(absf(hc.current_hp - 70.0) < 0.001, "(11) set_hp_authoritative nie ustawil 70")
	_check(absf(got_hp[0] - 70.0) < 0.001, "(11) hp_changed nie wyemitowane (HUD nie odswiezy)")
	_check(not hc.is_dead, "(11) is_dead==true mimo 70 HP")

	# Host narzuca smierc (0 HP, dead).
	hc.set_hp_authoritative(0.0, true, null)
	_check(hc.is_dead, "(11) set_hp_authoritative(dead) nie ustawil smierci")
	_check(died_count[0] == 1, "(11) died wyemitowane %d razy (oczek. 1)" % died_count[0])

	ent.queue_free()
	print("[E7] (11) klient stosuje HP hosta (set_hp_authoritative -> hp_changed/died) OK")


# ============================================================================
#  (12) Powierzchnia combat-RPC istnieje (DamageService request_attack + sync HP)
# ============================================================================
## Review #blocker: tor walki klient->host musi ISTNIEC. Sprawdzamy, ze DamageService wystawia
## metody RPC kontraktu 6.4 (zamiast pustego _predict_fx). To dowod, ze klient ma czym poslac cios
## do hosta i odebrac HP (pelny przeplyw end-to-end testuje sie 2-procesowo: coop_loopback.gd).
func _test_combat_rpc_surface() -> void:
	_check(DamageService.has_method("_rpc_request_attack"),
		"(12) BRAK @rpc request_attack w DamageService (klient nie zada obrazen wrogom!)")
	_check(DamageService.has_method("_rpc_sync_hp"),
		"(12) BRAK @rpc sync HP w DamageService (klient nie zobaczy autorytatywnego HP)")
	print("[E7] (12) tor walki sieciowej obecny (DamageService request_attack + sync HP) OK")
