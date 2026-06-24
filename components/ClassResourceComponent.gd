class_name ClassResourceComponent
extends Node
## ClassResourceComponent.gd (komponent) — ZASOB KLASY (Etap 3, GDD 4 / ROADMAP 6).
##
## Zasoby sa ASYMETRYCZNE (inny rytm zarzadzania moca):
##   Mag      -> MANA   : pula bazowa ~100, regen ~5/s (skaluje z lootem). Skille kosztuja mane.
##   Wojownik -> FURIA  : 0..100, +6 za zadany cios wrecz, +4 za otrzymany cios, zanik 5/s po 3 s
##                        ciszy. Finishery konsumuja Furie. (ROADMAP 6 / GDD 4.2)
##   Ranger   -> COMBO (0..5, calkowite, buderzy +1) + FOCUS (wolno regenerujacy zasob na uniki).
##
## Komponent jest WSPOLNYM zrodlem zasobu i podpina sie pod AbilityComponent przez Callable:
##   pool(name)            -> float   (resource_pool: ile mamy)
##   spend(name, amount)   -> void    (resource_spend: wydatek, np. finisher)
## Dzieki temu AbilityComponent (koszt/CD/cast) jest neutralny wzgledem klasy. Stamina ZOSTAJE
## w gestii encji (Player) — ten komponent dorzuca zasob KLASY obok niej (HUD pokazuje oba).
##
## Klasa pochodzi z GameState/CharacterAppearance (class_id). build_for() ustawia tryb i bazy.
## Regen/decay licza sie w _process (host-authoritative: zasob to stan logiki, nie sieci — w co-opie
## host trzyma prawde, klient dostaje snapshot; tu SP -> liczymy lokalnie).
##
## SKALOWANIE z lootem/pasywami (Etap 3 review): komponent trzyma referencje do StatsComponentu
## (set_stats) i czyta z niego mnozniki generacji/puli. To zamyka petle zwrotna pasywu "Furia Bitwy"
## (rage_gen +25% -> realnie wiecej Furii za cios), a takze utrzymuje mana_max/rage_max/focus_max
## w synchronie z lootem przez subskrypcje stats_changed (jednorazowy odczyt nie nadazal za +max).

enum Kind { MANA, RAGE, COMBO_FOCUS }   # Mag / Wojownik / Ranger

signal resource_changed(name: StringName, current: float, maximum: float)
signal combo_changed(count: int, maximum: int)   # tylko Ranger (combo to inny widget)

## Tryb wg klasy.
var kind: Kind = Kind.RAGE
var class_id: StringName = &"wojownik"   # AUDYT (namespace): kanon = id ContentDB (polskie)

## StatsComponent zrodla mnoznikow (rage_gen) i pul (mana_max). Ustawia encja przez set_stats().
## Gdy null -> mnozniki = 1.0, pule = bazy (komponent dziala samodzielnie, np. w testach).
var _stats: StatsComponent = null

# --- MANA ---
var mana: float = 0.0
var mana_max: float = 100.0
var mana_regen: float = 5.0              # /s (GDD 4.1)

# --- FURIA (rage) ---
var rage: float = 0.0
var rage_max: float = 100.0
const RAGE_PER_HIT_DEALT: float = 6.0    # ROADMAP 6: +6 za trafienie wrecz
const RAGE_PER_HIT_TAKEN: float = 4.0    # ROADMAP 6: +4 za otrzymany cios
const RAGE_DECAY: float = 5.0            # /s zaniku
const RAGE_DECAY_DELAY: float = 3.0      # s ciszy zanim ruszy zanik
var _rage_idle: float = 0.0              # s od ostatniej zmiany "w gore" (buildowania)

# --- COMBO + FOCUS (Ranger) ---
var combo: int = 0
var combo_max: int = 5                   # GDD 4: Combo 0..5
var focus: float = 0.0
var focus_max: float = 100.0
var focus_regen: float = 8.0             # /s — wolniejszy niz stamina/mana (zasob na uniki)


## Konfiguruje komponent wg klasy. Wola encja (Player) po poznaniu class_id z GameState/save.
## StatsComponent (opcjonalnie) skaluje mana_max/regen z lootem w przyszlosci — Etap 3 trzyma bazy.
func build_for(p_class_id: StringName) -> void:
	class_id = p_class_id
	# AUDYT (namespace): zasób klasy z DANYCH (ContentDB.class_by_id().resource_kind) zamiast hardkodu
	# id. Dawniej match po ANGIELSKICH id (mage/ranger) -> polskie id kreatora (mag/lucznik) trafiały
	# w fallback RAGE (mag dostawał Furię zamiast Many). Teraz każda z 11 klas dostaje właściwy zasób.
	var rkind: StringName = &"rage"
	if typeof(ContentDB) != TYPE_NIL and ContentDB != null and ContentDB.has_method("class_by_id"):
		var cr = ContentDB.class_by_id(p_class_id)
		if cr != null and cr.resource_kind != &"":
			rkind = cr.resource_kind
	match rkind:
		&"mana":
			kind = Kind.MANA
			mana = mana_max               # mag startuje z pelna mana
		&"focus", &"combo":
			kind = Kind.COMBO_FOCUS
			focus = focus_max
			combo = 0
		_:
			# rage (oraz nieobsłużone jeszcze: faith/essence/chi/nature) -> Furia jako bezpieczny default.
			kind = Kind.RAGE
			rage = 0.0
	_apply_stat_maxima(true)   # dosuń mana_max/rage_max/focus_max do staty (gdy stats juz wpiete)
	_emit_current()


## Wpina StatsComponent (encja wola po build_for). Subskrybuje stats_changed, by pule i mnozniki
## sledzily loot/pasywy (review: jednorazowy odczyt mana_max nie nadazal; rage_gen byl martwy).
func set_stats(p_stats: StatsComponent) -> void:
	if _stats == p_stats:
		return
	if _stats != null and _stats.stats_changed.is_connected(_on_stats_changed):
		_stats.stats_changed.disconnect(_on_stats_changed)
	_stats = p_stats
	if _stats != null and not _stats.stats_changed.is_connected(_on_stats_changed):
		_stats.stats_changed.connect(_on_stats_changed)
	_apply_stat_maxima(true)
	_emit_current()


func _on_stats_changed() -> void:
	_apply_stat_maxima(false)


## Mnoznik generacji Furii z drzewka/lootu (rage_gen). 1.0 gdy brak StatsComponentu (testy/fallback).
func _rage_gen_mult() -> float:
	if _stats == null:
		return 1.0
	var m := _stats.get_stat(&"rage_gen")
	return m if m > 0.0 else 1.0


## Dosuwa pule (mana_max) do staty z zachowaniem UŁAMKA wypelnienia (loot +max nie wyzeruje paska).
## p_init=true (start/po build): mag dostaje pelna mana do nowego maksimum. Emituje resource_changed,
## by HUD odswiezyl maksimum. rage_max/focus_max obecnie bez osobnej staty -> zostaja bazami.
func _apply_stat_maxima(p_init: bool) -> void:
	if _stats == null:
		return
	if kind == Kind.MANA:
		var new_max := _stats.get_stat(&"mana_max")
		if new_max > 0.0 and not is_equal_approx(new_max, mana_max):
			var frac := 1.0 if (p_init or mana_max <= 0.0) else clampf(mana / mana_max, 0.0, 1.0)
			mana_max = new_max
			mana = mana_max * frac
			resource_changed.emit(&"mana", mana, mana_max)
		elif p_init and new_max > 0.0:
			mana_max = new_max


# ============================================================================
#  Most do AbilityComponent (resource_pool / resource_spend)
# ============================================================================

## Ile danego zasobu mamy. Nazwy: &"mana"/&"rage"/&"focus" -> float; &"combo" -> int jako float.
func pool(name: StringName) -> float:
	match name:
		&"mana": return mana
		&"rage": return rage
		&"focus": return focus
		&"combo": return float(combo)
		_: return 0.0


## Wydatek zasobu (np. finisher Furii, kast many, wydanie Combo). Clamp do 0/min. Emituje sygnal.
func spend(name: StringName, amount: float) -> void:
	match name:
		&"mana":
			mana = maxf(0.0, mana - amount)
			resource_changed.emit(&"mana", mana, mana_max)
		&"rage":
			rage = maxf(0.0, rage - amount)
			resource_changed.emit(&"rage", rage, rage_max)
		&"focus":
			focus = maxf(0.0, focus - amount)
			resource_changed.emit(&"focus", focus, focus_max)
		&"combo":
			combo = maxi(0, combo - int(round(amount)))
			combo_changed.emit(combo, combo_max)


# ============================================================================
#  Generacja zasobu (hooki z walki) — wola Player na trafieniu/obrywaniu
# ============================================================================

## Gracz ZADAL cios wrecz: Wojownik buduje Furie; Ranger dodaje +1 Combo (builder).
## Furia skaluje sie mnoznikiem rage_gen ze StatsComponentu (pasyw "Furia Bitwy" +25% -> realny zysk).
func on_hit_dealt(is_melee: bool = true) -> void:
	match kind:
		Kind.RAGE:
			if is_melee:
				add_rage(RAGE_PER_HIT_DEALT * _rage_gen_mult())
		Kind.COMBO_FOCUS:
			add_combo(1)
		_:
			pass


## Gracz OTRZYMAL cios: Wojownik buduje Furie (+4, takze skalowane przez rage_gen).
func on_hit_taken() -> void:
	if kind == Kind.RAGE:
		add_rage(RAGE_PER_HIT_TAKEN * _rage_gen_mult())


func add_rage(amount: float) -> void:
	if amount <= 0.0:
		return
	rage = clampf(rage + amount, 0.0, rage_max)
	_rage_idle = 0.0                       # reset zaniku — wlasnie buildujemy
	resource_changed.emit(&"rage", rage, rage_max)


func add_combo(amount: int) -> void:
	if amount == 0:
		return
	combo = clampi(combo + amount, 0, combo_max)
	combo_changed.emit(combo, combo_max)


# ============================================================================
#  Regen / zanik (per-frame)
# ============================================================================

func _process(delta: float) -> void:
	match kind:
		Kind.MANA:
			if mana < mana_max:
				mana = minf(mana_max, mana + mana_regen * delta)
				resource_changed.emit(&"mana", mana, mana_max)
		Kind.RAGE:
			# Zanik 5/s DOPIERO po RAGE_DECAY_DELAY s ciszy (bez buildowania).
			if rage > 0.0:
				_rage_idle += delta
				if _rage_idle >= RAGE_DECAY_DELAY:
					rage = maxf(0.0, rage - RAGE_DECAY * delta)
					resource_changed.emit(&"rage", rage, rage_max)
		Kind.COMBO_FOCUS:
			if focus < focus_max:
				focus = minf(focus_max, focus + focus_regen * delta)
				resource_changed.emit(&"focus", focus, focus_max)


# ============================================================================
#  HUD pomocnicze
# ============================================================================

## Zwraca (current, maximum, kolor, etykieta) biezacego paska zasobu — HUD czyta tryb stad,
## by jeden widget obslugiwal wszystkie klasy (GDD 11).
func current_value() -> float:
	match kind:
		Kind.MANA: return mana
		Kind.RAGE: return rage
		Kind.COMBO_FOCUS: return focus
		_: return 0.0


func max_value() -> float:
	match kind:
		Kind.MANA: return mana_max
		Kind.RAGE: return rage_max
		Kind.COMBO_FOCUS: return focus_max
		_: return 1.0


func resource_name() -> StringName:
	match kind:
		Kind.MANA: return &"mana"
		Kind.RAGE: return &"rage"
		Kind.COMBO_FOCUS: return &"focus"
		_: return &""


func display_label() -> String:
	match kind:
		Kind.MANA: return "MANA"
		Kind.RAGE: return "FURIA"
		Kind.COMBO_FOCUS: return "FOCUS"
		_: return ""


func bar_color() -> Color:
	match kind:
		Kind.MANA: return Color(0.30, 0.45, 0.95, 0.95)        # niebieski
		Kind.RAGE: return Color(0.85, 0.25, 0.15, 0.95)        # czerwony
		Kind.COMBO_FOCUS: return Color(0.35, 0.80, 0.45, 0.95) # zielony
		_: return Color.WHITE


func _emit_current() -> void:
	resource_changed.emit(resource_name(), current_value(), max_value())
	if kind == Kind.COMBO_FOCUS:
		combo_changed.emit(combo, combo_max)
