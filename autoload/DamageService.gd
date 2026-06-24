extends Node
## DamageService.gd (autoload) — JEDNO wejscie calej walki (TDD 4, ROADMAP 4 krok 1).
##
## Host-authoritative: w SP NetManager.has_authority(target) == true -> rozstrzygamy LOKALNIE.
## W Etapie 7 klient bedzie tylko slal intencje (RPC) i odbieral wynik; logika ponizej NIE
## zmienia sie — dolozymy jedynie transport. To celowo cienka warstwa: owija ISTNIEJACY
## kontrakt target.take_damage(amount, from), zeby zero zmienic w odczuciu gry, a zyskac
## centralny punkt liczenia (krytyk -> pancerz po przebiciu -> odpornosci -> dmg -> lifesteal).
##
## Kolejnosc rozstrzygania (TDD 4): krytyk -> pancerz(po przebiciu) -> odpornosci ->
## take_damage -> lifesteal/statusy -> FX. Jedno miejsce = latwy balans i pozniejsza replikacja.

## Emitowany po KAZDYM rozstrzygnietym trafieniu (hook pod FX/HUD/loot-proki). source/target moga
## byc null po stronie odbiorcy-RPC; w SP zawsze realne wezly.
signal hit_resolved(source: Node, target: Node, final_damage: float, was_crit: bool)


## Publiczne wejscie. W SP/HOST (autorytet stanu) rozstrzyga od razu; KLIENT pokazuje FX i prosi
## hosta o rozstrzygniecie przez @rpc (TDD 6.4). HP/smierc/loot zmienia WYLACZNIE host (autorytet
## stanu), wiec bramkujemy has_state_authority() (== is_host), a NIE has_authority() — inaczej klient
## liczylby HP wlasnej postaci lokalnie (dwa zrodla HP = desync). Klient: FX kosmetyczny + request_attack.
func request_hit(source: Node, target: Node, hit: HitData) -> void:
	if target == null or not is_instance_valid(target):
		return
	if NetManager.has_state_authority(target):
		_resolve(source, target, hit)
	else:
		# KLIENT (Etap 7): tylko kosmetyka (flash/numbers) + prosba do hosta o autorytatywny cios.
		# Host waliduje (cel zywy / zasieg) i rozstrzyga _resolve; wynik HP wraca przez HealthSync.
		_predict_fx(source, target, hit)
		_request_attack_to_host(source, target, hit)


## Rdzen liczenia obrazen (host LUB single-player). Zwraca finalne obrazenia (przydatne testom).
func _resolve(source: Node, target: Node, hit: HitData) -> float:
	var dmg := hit.base_damage

	# 1) KRYTYK — szansa i mnoznik na koncu liczenia bazowego (TDD 3.1: krytyk w DamageService).
	var was_crit := false
	if hit.crit_chance > 0.0 and _combat_rand() < hit.crit_chance:
		dmg *= hit.crit_mult
		was_crit = true

	# 2) PANCERZ po przebiciu — kopia kontraktu z Enemy.take_damage: eff = armor * (1 - pierce).
	#    Czytamy pole 'armor' (0..1) jesli istnieje (kontrakt Enemy); brak -> 0.
	var armor := 0.0
	if "armor" in target:
		armor = clampf(float(target.armor), 0.0, 1.0)
	var eff_armor := armor * (1.0 - clampf(hit.armor_pierce, 0.0, 1.0))
	dmg *= (1.0 - eff_armor)

	# 3) ODPORNOSCI typu (hit.tags vs target.resistances) — wpiecie afiksow lootu w Etapie 2.
	#    Szkielet: jesli cel ma slownik resistances i tag pasuje, redukujemy. Bezpieczne gdy brak.
	dmg = _apply_resistances(target, hit, dmg)

	dmg = maxf(0.0, dmg)

	# 4) ZADANIE OBRAZEN — istniejacy kontrakt, BEZ zmian w grze. Wolamy HealthComponent jesli jest,
	#    inaczej fallback na take_damage(amount, from, knockback) (monolityczny Player/Enemy).
	#    Sila odrzutu plynie z HitData (jedno zrodlo per-cios) zamiast hardkodu w odbiorcy.
	_deal(target, dmg, source, hit.knockback)

	# 5) LIFESTEAL — leczy zrodlo proporcjonalnie do zadanych obrazen (afiksy/Szal Krwi w GDD).
	if hit.lifesteal > 0.0 and source != null and is_instance_valid(source):
		var heal_amt := dmg * hit.lifesteal
		if heal_amt > 0.0:
			_heal(source, heal_amt)

	# 6) on_hit_effects (statusy/proki) — AUDYT #5: ignite/chill/poison/stun z afiksow/elementu.
	#    Każdy fx = { kind:StringName(element|"stun"), mag:float, dur:float }. Aplikuje host (autorytet).
	if not hit.on_hit_effects.is_empty():
		for fx in hit.on_hit_effects:
			if fx is Dictionary:
				_apply_status(target, fx, source)

	# 7) ETAP 7: REPLIKACJA HP host -> klienci (TDD 6.2 "klient tylko wyswietla"). Po autorytatywnej
	#    mutacji rozsylamy current_hp celu, by KLIENCI widzieli ZGODNE HP (brak desyncu). No-op w SP.
	_broadcast_hp(target)

	hit_resolved.emit(source, target, dmg, was_crit)
	return dmg


# ============================================================================
#  REPLIKACJA HP (host -> klienci) — autorytatywny stan HP po _resolve/heal
# ============================================================================

## HOST: rozsyla autorytatywne HP encji do klientow (po sciezce stabilnej u wszystkich peerow).
## No-op w SP/u klienta. Encje bez HealthComponent (fasada take_damage) pomijamy — ich HP nie jest
## w komponentowym zrodle prawdy (vertical slice: pelne HP-encje maja HealthComponent).
func _broadcast_hp(target: Node) -> void:
	if NetManager == null or not NetManager.has_network() or not NetManager.is_host():
		return
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var hc := _find_health(target)
	if hc == null:
		return
	_rpc_sync_hp.rpc(target.get_path(), hc.current_hp, hc.is_dead)


## KLIENT: odbiera autorytatywne HP encji od hosta i ustawia je LOKALNIE (nie liczy — tylko stosuje).
## Host ignoruje (sam jest zrodlem). Sciezka encji jest identyczna u hosta i klienta (stabilny spawn).
@rpc("authority", "call_remote", "reliable")
func _rpc_sync_hp(target_path: NodePath, current_hp: float, is_dead: bool) -> void:
	if NetManager == null or NetManager.is_host():
		return
	var tree := get_tree()
	if tree == null:
		return
	var target: Node = tree.root.get_node_or_null(target_path)
	if target == null or not is_instance_valid(target):
		return
	var hc := _find_health(target)
	if hc == null:
		return
	hc.set_hp_authoritative(current_hp, is_dead, target)


## Zadaje obrazenia: preferuje HurtboxComponent/HealthComponent (komponentowa droga Etapu 1),
## fallback na monolityczny take_damage(amount, from, knockback). Knockback niesie HitData ->
## take_damage dostaje gotowa SILE odrzutu (per-cios), a kierunek liczy odbiorca z pozycji 'from'.
func _deal(target: Node, dmg: float, source: Node, knockback: float) -> void:
	# Droga komponentowa: HurtboxComponent (sibling) -> HealthComponent.apply_damage.
	# Encje gry maja OBA (HealthComponent liczy HP/smierc + take_damage robi knockback/flash/wybudzenie
	# AI). Gdy oba sa obecne, wolamy HEALTHCOMPONENT (zrodlo prawdy HP) ORAZ take_damage z 0 dmg, by
	# odebrac FX/odrzut bez podwojnego odejmowania HP (kontrakt: take_damage(0, from, knockback)).
	var hc := _find_health(target)
	if hc != null:
		hc.apply_damage(dmg, source)
		if target.has_method("take_damage"):
			target.take_damage(0.0, source, knockback)
		return
	if target.has_method("take_damage"):
		target.take_damage(dmg, source, knockback)


func _heal(source: Node, amount: float) -> void:
	var hc := _find_health(source)
	if hc != null:
		hc.heal(amount)
		_broadcast_hp(source)   # ETAP 7: lifesteal tez replikuje HP zrodla do klientow
	elif source.has_method("heal"):
		source.heal(amount)


## Odpornosci: zaczatek pod Etap 2. target.resistances: StringName(element)->float(0..1 lub %).
## Bierzemy max odpornosc sposrod tagow trafienia (np. [&"fire"] vs resistances[&"fire"]).
func _apply_resistances(target: Node, hit: HitData, dmg: float) -> float:
	if hit.tags.is_empty():
		return dmg
	if not ("resistances" in target):
		return dmg
	var res = target.resistances
	if not (res is Dictionary) or (res as Dictionary).is_empty():
		return dmg
	var best := 0.0
	for tag in hit.tags:
		if (res as Dictionary).has(tag):
			var r := float((res as Dictionary)[tag])
			if r > 1.0:
				r = r / 100.0          # toleruj zapis w procentach
			best = maxf(best, clampf(r, 0.0, 0.95))
	return dmg * (1.0 - best)


## KLIENT (Etap 7): predykcja KOSMETYCZNA — NIGDY HP. Emituje hit_resolved z final_damage 0,
## by lokalne FX/numbers/hitstop encji odpalily sie od razu (responsywnosc), a autorytatywne HP
## przyjdzie z hosta. W SP nieosiagalne (has_state_authority zawsze true). Bezpieczne: zero mutacji HP.
func _predict_fx(source: Node, target: Node, _hit: HitData) -> void:
	hit_resolved.emit(source, target, 0.0, false)


# ============================================================================
#  WALKA PO SIECI (TDD 6.4) — klient klik -> @rpc do hosta -> walidacja -> _resolve
# ============================================================================

## Maksymalny dystans (m) miedzy atakujacym a celem, ktory host akceptuje od klienta (anti-cheat
## zasiegu). Z duzym zapasem na pingowe rozjazdy pozycji (predykcja vs autorytet) — cel: odrzucic
## ewidentny cheat (cios przez pol mapy), nie psuc grywalnosci. Bron melee siega ~2.2 m + bufor.
const MAX_ATTACK_RANGE: float = 6.0

## KLIENT: wysyla intencje ataku do hosta (peer 1). source/target jako NodePath (autoloady i encje
## maja IDENTYCZNE sciezki u hosta dzieki stabilnemu nazewnictwu spawnu). HitData jako dict (RPC-safe).
func _request_attack_to_host(source: Node, target: Node, hit: HitData) -> void:
	if NetManager == null or not NetManager.has_network() or NetManager.is_host():
		return
	if source == null or not is_instance_valid(source) or not source.is_inside_tree():
		return
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	_rpc_request_attack.rpc_id(NetManager.HOST_PEER_ID,
		source.get_path(), target.get_path(), hit.to_dict())


## HOST: odbiera intencje ataku klienta, WALIDUJE (anti-cheat: cel istnieje/zywy, zasieg) i dopiero
## wtedy rozstrzyga autorytatywnie. KLIENT nie woła tego (any_peer -> tylko host wykonuje cialo).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_attack(source_path: NodePath, target_path: NodePath, hit_dict: Dictionary) -> void:
	if NetManager == null or not NetManager.is_host():
		return
	var tree := get_tree()
	if tree == null:
		return
	var source: Node = tree.root.get_node_or_null(source_path)
	var target: Node = tree.root.get_node_or_null(target_path)
	if target == null or not is_instance_valid(target):
		return
	# Anti-cheat: tylko host liczy HP (autorytet stanu) — odrzuc, gdyby cel nie nalezal do hosta.
	if not NetManager.has_state_authority(target):
		return
	# Anti-cheat zasiegu: cios musi byc fizycznie mozliwy (atakujacy w poblizu celu).
	if source is Node3D and target is Node3D:
		var d := (source as Node3D).global_position.distance_to((target as Node3D).global_position)
		if d > MAX_ATTACK_RANGE:
			return
	# Walidacja "cel zywy": gdy ma HealthComponent i jest martwy -> odrzuc (brak phantom-kill).
	var hc := _find_health(target)
	if hc != null and hc.is_dead:
		return
	var hit := HitData.from_dict(hit_dict)
	hit.source = source
	_resolve(source, target, hit)


# ============================================================================
#  Helpery — losowanie deterministyczne + odnajdywanie komponentow
# ============================================================================

## Strumien 'combat' z RNGService (determinizm = brak desyncu krytykow w co-opie).
## RNGService to autoload (zawsze dostepny); pobranie TYLKO po stronie autorytetu (tu = _resolve).
func _combat_rand() -> float:
	if RNGService != null and RNGService.combat is RandomNumberGenerator:
		return RNGService.combat.randf()
	return randf()


## Znajduje HealthComponent jako dziecko encji (komponentowa droga). Brak -> null (fallback fasady).
func _find_health(entity: Node) -> HealthComponent:
	if entity == null or not is_instance_valid(entity):
		return null
	for c in entity.get_children():
		if c is HealthComponent:
			return c as HealthComponent
	return null


## Znajduje StatusEffectComponent jako dziecko encji (audyt #5). Brak -> null.
func _find_status(entity: Node) -> StatusEffectComponent:
	if entity == null or not is_instance_valid(entity):
		return null
	for c in entity.get_children():
		if c is StatusEffectComponent:
			return c as StatusEffectComponent
	return null


# ============================================================================
#  AUDYT #5 — STATUSY (on_hit_effects -> StatusEffectComponent) + DoT (host-only)
# ============================================================================

## Nakłada status z pojedynczego on_hit_effects. fx = { kind:StringName, mag:float, dur:float } gdzie
## kind to element (&"fire"/&"frost"/&"poison"/&"lightning"/&"dark") albo &"stun". Cel musi mieć
## StatusEffectComponent (inaczej no-op). Host-only (woływane z _resolve, które już ma autorytet).
func _apply_status(target: Node, fx: Dictionary, source: Node) -> void:
	var se := _find_status(target)
	if se == null:
		return
	var what := StringName(fx.get("kind", &""))
	var mag := float(fx.get("mag", 0.0))
	var dur := float(fx.get("dur", 0.0))
	if dur <= 0.0:
		return
	if what == &"stun":
		se.apply(StatusEffectComponent.Kind.STUN, 1.0, dur, source)
	else:
		se.apply_element(what, mag, dur, source)


## DoT / obrażenia statusowe (audyt #5): HOST-ONLY, BEZ take_damage — NIE wyzwala hitstunu/odrzutu
## (inaczej płonący wróg byłby permastunowany ciągłym hitstunem z rank #1). Odporność elementu
## redukuje, weaken celu zwiększa; HP odejmuje HealthComponent (śmierć -> died -> loot/XP); broadcast
## replikuje HP klientom; hit_resolved daje FX/damage-numbers tyków. Woła StatusEffectComponent._tick_dot.
func apply_dot(target: Node, amount: float, element: StringName, source: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if NetManager != null and not NetManager.has_state_authority(target):
		return
	var dmg := amount
	if element != &"" and "resistances" in target:
		var res = target.resistances
		if res is Dictionary and (res as Dictionary).has(element):
			var r := float((res as Dictionary)[element])
			if r > 1.0:
				r = r / 100.0
			dmg *= (1.0 - clampf(r, 0.0, 0.95))
	var se := _find_status(target)
	if se != null:
		dmg *= se.damage_taken_mult()
	dmg = maxf(0.0, dmg)
	if dmg <= 0.0:
		return
	var hc := _find_health(target)
	if hc != null:
		hc.apply_damage(dmg, source)
		_broadcast_hp(target)
	elif target.has_method("take_damage"):
		target.take_damage(dmg, source, 0.0)   # fallback bez HealthComponent: 0 knockback (DoT nie odpycha)
	hit_resolved.emit(source, target, dmg, false)
