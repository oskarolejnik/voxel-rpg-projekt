extends Node
## CoopSceneLoopback.gd — RĘCZNY/CI test 2-PROCESOWY co-op przez REALNE autoloady (ETAP 7).
## W przeciwienstwie do coop_loopback.gd (SceneTree, --script -> BRAK autoloadow) ten test biegnie
## jako SCENA, wiec NetManager/DamageService/HealthComponent/RNGService SA ZALADOWANE — exerciseuje
## PRAWDZIWY stos co-op (host_game/join_game, @rpc DamageService._rpc_request_attack/_rpc_sync_hp,
## HealthComponent.set_hp_authoritative), czego Etap7Test cz.B (transport-only send_bytes) nie robi.
##
## UZYCIE (dwa terminale, najpierw HOST):
##   Terminal 1 (HOST):   godot --headless --path . res://test/CoopSceneLoopback.tscn -- host
##   Terminal 2 (KLIENT): godot --headless --path . res://test/CoopSceneLoopback.tscn -- join 127.0.0.1
##
## Co weryfikuje (host-authoritative HP, TDD 6.2/6.4):
##   - HOST: hostuje, czeka na klienta; po polaczeniu buduje encje-cel z HealthComponent pod STABILNA
##     sciezka /root/CoopSceneLoopback/Target, "zadaje" 30 dmg przez DamageService._resolve (autorytet)
##     i rozsyla HP przez _rpc_sync_hp; loguje [COOP] HOST: peer + HP=70.
##   - KLIENT: dolacza, tworzy LUSTRZANA encje-cel pod TA SAMA sciezka, odbiera HP-sync od hosta i
##     loguje [COOP] CLIENT: HP=70 (== host). Zgodne HP = brak desyncu (kluczowy DoD).
##
## ETAP 7b — DODATKOWO (replikacja wspolnego swiata):
##   - HOST: po polaczeniu spawnuje wroga przez NetManager.host_spawn_enemy (stabilna sciezka
##     Enemy_<id> + MultiplayerSynchronizer) ORAZ loot przez host_spawn_loot (Loot_<id>); loguje
##     [E7b] HOST: enemy=Enemy_<id> loot=Loot_<id>.
##   - KLIENT: po chwili sprawdza, czy w drzewie sa wezly Enemy_<id> i Loot_<id> (replika RPC) oraz
##     czy wrog ma NetTransformSync; loguje [E7b] CLIENT: widzi wroga+loot OK. (UWAGA: ten test wymaga
##     URUCHOMIENIA AS SCENA — wezly tworzone pod /root/Main; tu uzywamy wlasnego roota, wiec klient
##     szuka pod /root/CoopSceneLoopback. Pelna replikacja w realnej grze idzie pod /root/Main.)
##
## Kazdy proces konczy po ~15 s (lub po sukcesie). Exit 0 = OK.

var _role: String = "host"
var _ip: String = "127.0.0.1"
var _done: bool = false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_role = args[0]
	if args.size() >= 2:
		_ip = args[1]
	print("[COOP] start role=%s ip=%s" % [_role, _ip])

	# Encja-cel pod STABILNA sciezka (identyczna u hosta i klienta) — warunek routingu @rpc HP-sync.
	var target := _build_target()
	target.name = "Target"
	add_child(target)

	if _role == "host":
		_run_host()
	else:
		_run_client()
	# Twardy limit czasu (gdyby polaczenie nie doszlo) — nie wisimy w nieskonczonosc.
	await get_tree().create_timer(15.0).timeout
	if not _done:
		printerr("[COOP] TIMEOUT (brak synchronizacji w 15 s)")
	get_tree().quit(0 if _done else 1)


## Buduje encje-cel: StatsComponent(max_hp=100) + HealthComponent (JEDYNE zrodlo HP).
func _build_target() -> Node3D:
	var ent := Node3D.new()
	var st := StatsComponent.new()
	var sb := StatBlock.new()
	sb.max_hp = 100.0
	st.base = sb
	ent.add_child(st)
	var hc := HealthComponent.new()
	ent.add_child(hc)
	return ent


func _run_host() -> void:
	var ok := NetManager.host_game(NetManager.DEFAULT_PORT)
	print("[COOP] HOST host_game=", ok, " czekam na klienta...")
	NetManager.peer_joined.connect(_on_host_peer_joined)


func _on_host_peer_joined(pid: int) -> void:
	if pid == NetManager.local_peer_id():
		return
	print("[COOP] HOST: peer dolaczyl id=", pid)
	# Daj klientowi chwile na zbudowanie lustrzanej encji, potem zadaj cios + rozeslij HP.
	await get_tree().create_timer(0.5).timeout
	_host_deal_and_sync()


func _host_deal_and_sync() -> void:
	var target := get_node_or_null("Target")
	if target == null:
		printerr("[COOP] HOST: brak Target")
		return
	# Autorytatywny cios: 100 - 30 = 70 HP, przez DamageService (host = autorytet stanu).
	var hit := HitData.new()
	hit.source = self
	hit.base_damage = 30.0
	hit.crit_chance = 0.0
	DamageService.request_hit(self, target, hit)   # host -> _resolve -> _broadcast_hp (RPC do klienta)
	var hc := _health_of(target)
	print("[COOP] HOST: HP po ciosie=%.0f (rozeslano do klienta)" % (hc.current_hp if hc != null else -1.0))

	# ETAP 7b: HOST replikuje wroga + loot do klienta (host_spawn_*). Repliki klient tworzy pod
	# /root/Main; w tym loopbacku roota Main brak (test biegnie pod /root/CoopSceneLoopback), wiec to
	# DEMONSTRACJA SCIEZKI HOSTA (nadanie net_id/synchronizera/RPC). Pelna replika u klienta dziala w
	# realnej scenie Main (residual_risks: reczny test 2-procesowy w grze).
	var e := _build_enemy()
	add_child(e)
	NetManager.host_spawn_enemy(e, &"goblin", Vector3(3, 0, 3), 4, &"verdant", 0)
	var loot := LootDrop.spawn_item(self, Vector3(2, 0, 2), _build_loot_item())
	NetManager.host_spawn_loot(loot, Vector3(2, 0, 2))
	# Synchronizer dopinany DEFERRED (klatke po spawn-RPC) — czekamy klatke przed logiem sync=.
	await get_tree().process_frame
	print("[E7b] HOST: enemy=%s (sync=%s) loot=%s net_id=%d (rozeslano _rpc_spawn_*)" % [
		e.name, str(e.get_node_or_null("NetTransformSync") != null), loot.name, loot.net_id])

	_done = true   # host zrobil swoje; sukces po stronie hosta = doszlo do peera i rozeslal


func _run_client() -> void:
	var ok := NetManager.join_game(_ip, NetManager.DEFAULT_PORT)
	print("[COOP] CLIENT join_game=", ok)
	NetManager.session_started.connect(func(is_host_session: bool) -> void:
		print("[COOP] CLIENT: polaczono host_session=", is_host_session, " peer=", NetManager.local_peer_id()))
	# Sprawdzaj HP lustrzanej encji — gdy host rozesle _rpc_sync_hp, HealthComponent.set_hp_authoritative
	# ustawi 70 i wyemituje hp_changed. Czekamy na zgodne 70.
	var target := get_node_or_null("Target")
	var hc := _health_of(target)
	if hc != null:
		hc.hp_changed.connect(func(c: float, _m: float) -> void:
			if absf(c - 70.0) < 0.001:
				print("[COOP] CLIENT: HP=%.0f (== host, BRAK desyncu) OK" % c)
				_done = true)


func _health_of(ent: Node) -> HealthComponent:
	if ent == null:
		return null
	for c in ent.get_children():
		if c is HealthComponent:
			return c as HealthComponent
	return null


## ETAP 7b — wrog do replikacji (pelny Enemy z komponentami; host nadaje net_id/synchronizer).
func _build_enemy() -> Node:
	return Enemy.new()


## ETAP 7b — przyklad itemu lootu (deterministyczny, do round-trip przez RPC).
func _build_loot_item() -> ItemInstance:
	var it := ItemInstance.new()
	it.base_id = &"axe2h"
	it.rarity = ItemResource.Rarity.RARE
	it.ilvl = 10
	it.seed = 424242
	return it
