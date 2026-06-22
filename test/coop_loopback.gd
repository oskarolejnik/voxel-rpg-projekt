extends SceneTree
## coop_loopback.gd — RĘCZNY test 2-PROCESOWY co-op (ETAP 7). Weryfikuje realny stos NetManager
## (host_game/join_game) między DWOMA osobnymi procesami Godota, czego nie da się w pełni odwzorować
## w 1 procesie (Etap7Test część B robi loopback przez dwa SceneMultiplayer — wystarcza do CI/DoD).
##
## UŻYCIE (dwa terminale):
##   Terminal 1 (HOST):    godot --headless --path . --script res://test/coop_loopback.gd -- host
##   Terminal 2 (KLIENT):  godot --headless --path . --script res://test/coop_loopback.gd -- join 127.0.0.1
##
## HOST: hostuje na DEFAULT_PORT i czeka, aż dołączy klient -> wypisze "[LOOP] HOST: peer dołączył".
## KLIENT: łączy się i po połączeniu wypisze "[LOOP] CLIENT: połączono, peer=...".
## Oba kończą po ~15 s. To dowód, że host_game/join_game działają end-to-end na realnym ENet.
##
## UWAGA: ten skrypt używa AUTOLOADU NetManager (dostępnego w trybie --script, bo autoloady ładują
## się z project.godot). Jeśli w Twoim środowisku autoloady nie ładują się w --script, uruchom przez
## scenę: skopiuj logikę do węzła i odpal scenę. Tu trzymamy wariant SceneTree dla prostoty CLI.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var role := "host"
	var ip := "127.0.0.1"
	if args.size() >= 1:
		role = args[0]
	if args.size() >= 2:
		ip = args[1]
	print("[LOOP] start role=%s ip=%s" % [role, ip])

	# NetManager to autoload — w trybie --script bywa niedostępny; fallback na surowy ENet.
	var nm = root.get_node_or_null("/root/NetManager")
	if nm != null:
		_run_with_netmanager(nm, role, ip)
	else:
		print("[LOOP] NetManager autoload niedostępny w --script — używam surowego ENet (kontrakt ten sam).")
		_run_raw(role, ip)


func _run_with_netmanager(nm, role: String, ip: String) -> void:
	if role == "host":
		var ok = nm.host_game(nm.DEFAULT_PORT)
		print("[LOOP] HOST host_game=", ok, " czekam na klienta...")
		nm.peer_joined.connect(func(pid: int) -> void: print("[LOOP] HOST: peer dołączył id=", pid))
	else:
		var ok = nm.join_game(ip, nm.DEFAULT_PORT)
		print("[LOOP] CLIENT join_game=", ok)
		nm.session_started.connect(func(is_host: bool) -> void:
			print("[LOOP] CLIENT: połączono, host_session=", is_host, " peer=", nm.local_peer_id()))
	_pump(15.0)


func _run_raw(role: String, ip: String) -> void:
	var port := 27015
	var mp := SceneMultiplayer.new()
	set_multiplayer(mp)
	var peer := ENetMultiplayerPeer.new()
	if role == "host":
		print("[LOOP] HOST create_server=", peer.create_server(port, 3))
		mp.peer_connected.connect(func(id: int) -> void: print("[LOOP] HOST: peer dołączył id=", id))
	else:
		print("[LOOP] CLIENT create_client=", peer.create_client(ip, port))
		mp.connected_to_server.connect(func() -> void: print("[LOOP] CLIENT: połączono, uid=", mp.get_unique_id()))
	mp.multiplayer_peer = peer
	_pump(15.0)


func _pump(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		OS.delay_msec(16)
		# process_frame pompuje autoloadowy multiplayer; surowy mp pompujemy przez idle.
		var mp := get_multiplayer()
		if mp != null and mp.multiplayer_peer != null:
			mp.poll()
	print("[LOOP] koniec (", seconds, "s).")
	quit(0)
