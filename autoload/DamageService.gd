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


## Publiczne wejscie. W SP (autorytet) rozstrzyga od razu; w Etapie 7 klient pojdzie galezia RPC.
func request_hit(source: Node, target: Node, hit: HitData) -> void:
	if target == null or not is_instance_valid(target):
		return
	if NetManager.has_authority(target):
		_resolve(source, target, hit)
	else:
		# Etap 7: KLIENT pokazuje tylko FX (predykcja kosmetyczna) i prosi hosta o rozstrzygniecie.
		# W Etapie 0/1 ta galaz jest nieosiagalna (has_authority zawsze true), trzyma ksztalt API.
		_predict_fx(source, target, hit)


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

	# 6) on_hit_effects (statusy/proki) — hook pod Etap 2 (ignite/chill/poison...). Na razie no-op.
	# for fx in hit.on_hit_effects: _apply_status(target, fx)

	hit_resolved.emit(source, target, dmg, was_crit)
	return dmg


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


## KLIENT (Etap 7): tylko kosmetyka, NIGDY HP. W SP nieosiagalne.
func _predict_fx(_source: Node, _target: Node, _hit: HitData) -> void:
	pass


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
