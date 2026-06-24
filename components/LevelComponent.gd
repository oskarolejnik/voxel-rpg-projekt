class_name LevelComponent
extends Node
## LevelComponent.gd (komponent) — poziomy/XP i przyznawanie punktow umiejetnosci (Etap 3, GDD 10).
##
## DoD Etapu 3: zabicie wroga -> grant_xp() -> krzywa XP -> lvl up -> +1 punkt umiejetnosci + sygnal.
## Poziom MAX 99 (GDD 10), trwaly i nieutracalny (filar "Trwaly wzrost").
##
## KRZYWA XP (wzor, deterministyczny): koszt awansu z poziomu L na L+1:
##   xp_to_next(L) = round(BASE * pow(L, EXP)),  BASE=50, EXP=1.5
## To gladka krzywa wielomianowa: 1->2 = 50 XP, 50->51 ~= 17 677, 98->99 ~= 48 520;
## suma 1..99 ~= 1,6 mln XP. Liczby zostaja w komponencie (jedno zrodlo prawdy progresji).
##
## PUNKTY (GDD 10): +1 punkt umiejetnosci na poziom (awanse 2..99 -> 98 pkt). Co 5 poziomow
## dodatkowy "punkt mocy" (na keystone/notable) — trzymany osobno (power_points), zsumowany w
## available_points() z normalnymi (drzewko nie rozroznia w Etapie 3, ale dane sa rozdzielone pod GDD).
##
## Stan jest CZYSTYM stanem postaci (przenosny przez SaveData: level/xp/allocated_passives).
## Komponent NIE czyta StatBlock — poziom skaluje progresje i odblokowuje wezly (min_level),
## a nie staty bezposrednio (staty rosna z lootu i z alokowanych pasywow — GDD filar "loot to moc").

const MAX_LEVEL: int = 99
const XP_BASE: float = 50.0
const XP_EXP: float = 1.5
const POWER_POINT_EVERY: int = 5     # co 5 lvl dodatkowy punkt mocy (GDD 10)

## BAZOWA MOC PER POZIOM (GDD filar "Trwaly wzrost"): kazdy poziom POWYZEJ 1 dodaje skromny,
## natychmiastowy bonus do mocy, zeby awans NIE byl pusty u klas bez (jeszcze) drzewka. To NIE
## zastepuje lootu/pasywow — to delikatna podloga skalowana liniowo poziomem (INCREASED, sumowana
## w puli statow). Lvl 1 = +0% (wsteczna zgodnosc bazy). Lvl 50 ~= +49%/+24.5%, lvl 99 ~= +98%/+49%.
const BASELINE_HP_PER_LEVEL: float = 0.01      # +1% max_hp na poziom (INCREASED)
const BASELINE_DMG_PER_LEVEL: float = 0.005    # +0.5% damage na poziom (INCREASED)
const BASELINE_SOURCE: StringName = &"level"   # source modyfikatorow bazowej mocy (do filtrowania)

signal xp_gained(amount: int, current_xp: int, xp_to_next: int)
signal leveled_up(new_level: int, points_gained: int)
signal level_changed(level: int, xp: int, xp_to_next: int)

var level: int = 1
var xp: int = 0                      # XP zgromadzone W OBREBIE biezacego poziomu (resetuje sie po awansie)

## Punkty wydawalne w drzewku. spent_points liczymy z faktycznej alokacji (SkillTreeComponent),
## ale komponent poziomu trzyma ILE LACZNIE przyznano — available = granted - spent.
var granted_points: int = 0          # suma przyznanych punktow umiejetnosci (z awansow)
var granted_power_points: int = 0    # suma przyznanych punktow mocy (co 5 lvl)

## Ile punktow aktualnie wydanych w drzewku (ustawia SkillTreeComponent po alokacji/respec).
var _spent_points: int = 0

## Opcjonalny StatsComponent, ktorego pula ma byc przeliczona po zmianie poziomu (bazowa moc rosnie).
## Pusty -> komponent dziala jak dawniej (czysty stan, bez wpiecia w staty). Wsteczna zgodnosc.
var _stats: StatsComponent = null


# ============================================================================
#  Krzywa XP (wzor — jedno zrodlo prawdy)
# ============================================================================

## Koszt awansu z poziomu L na L+1. Dla L>=MAX_LEVEL zwraca 0 (cap — nie zbieramy juz XP).
static func xp_to_next(lvl: int) -> int:
	if lvl >= MAX_LEVEL:
		return 0
	return int(round(XP_BASE * pow(float(lvl), XP_EXP)))


## Laczny XP potrzebny, by z poziomu 1 dojsc do `target_level` (do debug/UI/testow).
static func total_xp_for_level(target_level: int) -> int:
	var sum := 0
	for l in range(1, clampi(target_level, 1, MAX_LEVEL)):
		sum += xp_to_next(l)
	return sum


func xp_to_next_current() -> int:
	return xp_to_next(level)


func is_max_level() -> bool:
	return level >= MAX_LEVEL


# ============================================================================
#  Przyznawanie XP i awans
# ============================================================================

## Dodaje XP (hook smierci wroga). Obsluguje wielokrotny awans w jednym wywolaniu (duzy drop XP).
## Po awansie(-ach) emituje sygnaly. Na MAX_LEVEL nadmiar XP jest pochlaniany (cap, brak overflow).
func grant_xp(amount: int) -> void:
	if amount <= 0 or is_max_level():
		return
	xp += amount
	var total_points_gained := 0
	var levels_gained := 0
	# Petla awansow: dopoki XP starcza na nastepny poziom i nie osiagnieto capa.
	while not is_max_level():
		var need := xp_to_next(level)
		if need <= 0 or xp < need:
			break
		xp -= need
		level += 1
		levels_gained += 1
		var gained := _grant_points_for_level(level)
		total_points_gained += gained
		leveled_up.emit(level, gained)
	if is_max_level():
		xp = 0                        # cap: nie trzymamy nadmiaru po 99
	xp_gained.emit(amount, xp, xp_to_next(level))
	if levels_gained > 0:
		_notify_stats()                # bazowa moc per poziom wzrosla -> przelicz pule statow
		level_changed.emit(level, xp, xp_to_next(level))


## Przyznaje punkty za OSIAGNIETY poziom `lvl` (>=2). +1 umiejetnosci; co 5 lvl dodatkowy punkt mocy.
## Zwraca ile punktow UMIEJETNOSCI przyznano (do sygnalu/HUD).
func _grant_points_for_level(lvl: int) -> int:
	var pts := 1
	granted_points += pts
	if lvl % POWER_POINT_EVERY == 0:
		granted_power_points += 1
	return pts


# ============================================================================
#  Ksiegowanie punktow (most do SkillTreeComponent)
# ============================================================================

## Ile punktow do wydania zostalo (granted - spent). Power-pointy sumujemy razem (Etap 3 uproszczenie).
func available_points() -> int:
	return maxi(0, (granted_points + granted_power_points) - _spent_points)


func total_points() -> int:
	return granted_points + granted_power_points


func spent_points() -> int:
	return _spent_points


## Ustawia liczbe wydanych punktow (wola SkillTreeComponent po kazdej zmianie alokacji/respec).
func set_spent_points(n: int) -> void:
	_spent_points = maxi(0, n)


# ============================================================================
#  Zapis/odczyt stanu (SaveData)
# ============================================================================

## Wstawia poziom/XP do stanu. granted_* jest funkcja poziomu, wiec odtwarzamy je deterministycznie
## z `level` (nie trzeba dodatkowego pola w SaveData — punkty = funkcja osiagnietego poziomu).
func load_from(p_level: int, p_xp: int) -> void:
	level = clampi(p_level, 1, MAX_LEVEL)
	xp = maxi(0, p_xp)
	_recompute_granted_from_level()
	_notify_stats()                    # po wczytaniu poziomu bazowa moc moze byc inna -> przelicz
	level_changed.emit(level, xp, xp_to_next(level))


## Odtwarza granted_points/granted_power_points z biezacego poziomu (deterministycznie).
## Punkty za awanse 2..level: po 1 na poziom; co 5 lvl dodatkowy punkt mocy.
func _recompute_granted_from_level() -> void:
	granted_points = maxi(0, level - 1)            # awanse 2..level -> level-1 punktow
	granted_power_points = level / POWER_POINT_EVERY


# ============================================================================
#  Bazowa moc per poziom (provider StatsComponentu — TDD 3.2)
# ============================================================================

## Wpina komponent jako PROVIDER do StatsComponentu (jak InventoryComponent / drzewko). Po wpieciu
## kazda zmiana poziomu przelicza pule statow. Idempotentne; pusty p_stats odpina (powrot do
## dawnego zachowania — czysty stan bez wplywu na staty). Wsteczna zgodnosc: domyslnie NIE wpiety.
func attach_stats(p_stats: StatsComponent) -> void:
	if p_stats == _stats:
		return
	if _stats != null:
		_stats.unregister_provider(self)
	_stats = p_stats
	if _stats != null:
		_stats.register_provider(self)     # rebuild + stats_changed


## Bazowa moc per poziom jako modyfikatory (INCREASED), skalowane liczba poziomow POWYZEJ 1.
## Lvl 1 -> pusta lista (zero bonusu, wsteczna zgodnosc bazy). Kazdy modyfikator ma source=&"level".
## Zwraca Array[StatModifier] — kontrakt providera StatsComponentu.
func collect_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	var lvl_above := maxi(0, level - 1)
	if lvl_above <= 0:
		return out
	var tags: Array[StringName] = [&"level"]
	out.append(StatModifier.make(&"max_hp", StatModifier.Op.INCREASED,
		BASELINE_HP_PER_LEVEL * float(lvl_above), tags, BASELINE_SOURCE, &"baseline_hp"))
	out.append(StatModifier.make(&"damage", StatModifier.Op.INCREASED,
		BASELINE_DMG_PER_LEVEL * float(lvl_above), tags, BASELINE_SOURCE, &"baseline_dmg"))
	return out


## Przelicza pule statow, jesli komponent jest wpiety (po awansie / wczytaniu). No-op gdy niewpiety.
func _notify_stats() -> void:
	if _stats != null and is_instance_valid(_stats):
		_stats.rebuild_modifiers()
