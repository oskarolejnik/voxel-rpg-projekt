extends Node
## Etap3Test.gd — mini-test HEADLESS Etapu 3 (DoD progresja). NIE rusza działającej gry (Main.tscn).
## Uruchomienie: godot --headless res://test/Etap3Test.tscn
##
## Sprawdza DoD Etapu 3 (ROADMAP 5/6 / GDD 4/10 / TDD 2.3-3.2):
##  (1) Krzywa XP: wzor xp_to_next(L)=round(50*L^1.5); monotoniczna; cap na lvl 99.
##  (2) grant_xp -> lvl up -> +1 punkt umiejetnosci (i co 5 lvl punkt mocy).
##  (3) Wielokrotny awans w jednym grant_xp (duzy drop XP) liczy punkty poprawnie.
##  (4) Alokacja wezla (PassiveNodeResource) ZMIENIA get_stat() przez StatsComponent (source &"tree").
##  (5) Prerekwizyty: wezel z `requires` nie wejdzie bez prereq; keystone gated lvl 25.
##  (6) Dealokacja/cofniecie USUWA modyfikator (get_stat wraca) i zwraca punkt.
##  (7) Respec ZWRACA wszystkie punkty i POBIERA walute (Orby); za malo waluty -> brak respecu.
##  (8) Zasob klasy FURIA: +6 za zadany cios, +4 za otrzymany, cap 100, zanik 5/s po 3 s.
##  (9) Zasob klasy MANA (Mag): regen w czasie; COMBO (Ranger): builder +1, cap 5.
## (10) Starter Wojownik/Berserker: drzewko z SkillDB ma 8 wezlow + keystone lvl 25.
## (11) Save round-trip progresji (level/xp/allocated_passives) przez SaveData.
## (14) HUD Ranger: widget pipsów COMBO (setup_combo/on_class_combo_changed) buduje N pipsów i
##      zapala dokładnie `count` — osobny od melee "Combo xN" (set_combo).
## Kod wyjścia: 0 = ALL OK, 1 = FAIL. Print "[E3] ..." + ALL OK + quit.

const EPS: float = 0.0001
# HUD walki bez class_name -> ładujemy przez preload, by przetestować widget pipsów COMBO (Ranger).
const HUDScript := preload("res://src/HUD.gd")

var _failures: int = 0


func _ready() -> void:
	print("[E3] === Etap 3 mini-test start ===")

	_test_xp_curve()
	_test_levelup_grants_point()
	_test_multi_levelup()
	_test_allocate_changes_stat()
	_test_prereq_and_gate()
	_test_deallocate_refunds()
	_test_respec()
	await _test_rage_resource()
	_test_mana_and_combo()
	_test_starter_tree()
	_test_save_roundtrip()
	_test_save_file_roundtrip()
	_test_mana_max_rescale()
	_test_ranger_hud_combo_pips()

	if _failures == 0:
		print("[E3] ALL OK")
	else:
		printerr("[E3] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[E3] FAIL: %s" % msg)


# ---------------------------------------------------------------------------
#  Pomocnicze: zbuduj minimalny stos progresji bez calego Player.gd
# ---------------------------------------------------------------------------

## StatsComponent z bazowym StatBlock (gracz lvl 1) + LevelComponent + SkillTreeComponent.
## Zwraca [stats, level, tree].
func _make_stack(tree_res: SkillTreeResource) -> Array:
	var stats := StatsComponent.new()
	stats.base = StatBlock.new()
	add_child(stats)
	var level := LevelComponent.new()
	add_child(level)
	var tree := SkillTreeComponent.new()
	add_child(tree)
	tree.setup(tree_res, level)
	# tree rejestruje sie jako provider w _ready (po add_child). Wymus rebuild dla pewnosci.
	stats.register_provider(tree)
	return [stats, level, tree]


## Buduje drzewko testowe w kodzie (nie zalezy od plikow .tres):
##  root(+10% damage FLAT-na-stat? nie — INCREASED) -> child(+5 dmg FLAT) ; keystone(min_level 25).
func _make_test_tree() -> SkillTreeResource:
	var t := SkillTreeResource.new()
	t.class_id = &"test"

	var root := PassiveNodeResource.new()
	root.id = &"root"
	root.display_name = "Korzen"
	root.cost_points = 1
	root.modifiers = [StatModifier.make(&"damage", StatModifier.Op.INCREASED, 0.2, [], &"tree", &"root")]

	var child := PassiveNodeResource.new()
	child.id = &"child"
	child.display_name = "Dziecko"
	child.cost_points = 1
	child.requires = [&"root"]
	child.modifiers = [StatModifier.make(&"damage", StatModifier.Op.FLAT, 5.0, [], &"tree", &"child")]

	var keystone := PassiveNodeResource.new()
	keystone.id = &"keystone"
	keystone.display_name = "Keystone"
	keystone.cost_points = 1
	keystone.requires = [&"root"]
	keystone.min_level = 25
	keystone.is_keystone = true
	keystone.modifiers = [StatModifier.make(&"damage", StatModifier.Op.MORE, 0.25, [], &"tree", &"keystone")]

	t.nodes = [root, child, keystone]
	return t


# ---------------------------------------------------------------------------
#  (1) Krzywa XP
# ---------------------------------------------------------------------------
func _test_xp_curve() -> void:
	var l1 := LevelComponent.xp_to_next(1)
	var l2 := LevelComponent.xp_to_next(2)
	var l50 := LevelComponent.xp_to_next(50)
	var cap := LevelComponent.xp_to_next(99)
	_check(l1 == 50, "xp_to_next(1)=50 (jest %d)" % l1)
	_check(l2 > l1 and l50 > l2, "krzywa monotoniczna (l1=%d l2=%d l50=%d)" % [l1, l2, l50])
	_check(cap == 0, "lvl 99 to cap -> xp_to_next(99)=0 (jest %d)" % cap)
	print("[E3] krzywa XP: 1->2=%d, 50->51=%d, 99=cap=%d" % [l1, l50, cap])


# ---------------------------------------------------------------------------
#  (2) lvl up -> +1 punkt
# ---------------------------------------------------------------------------
func _test_levelup_grants_point() -> void:
	var lc := LevelComponent.new()
	add_child(lc)
	var before := lc.available_points()
	lc.grant_xp(LevelComponent.xp_to_next(1))   # dokladnie na 1 awans (lvl 1->2)
	_check(lc.level == 2, "po grant_xp pelnego progu: level=2 (jest %d)" % lc.level)
	_check(lc.available_points() == before + 1, "lvl up -> +1 punkt (przed %d, po %d)" % [before, lc.available_points()])
	print("[E3] lvl up: 1->2, punkty %d -> %d" % [before, lc.available_points()])
	lc.queue_free()


# ---------------------------------------------------------------------------
#  (3) Wielokrotny awans w jednym grant_xp + punkt mocy co 5 lvl
# ---------------------------------------------------------------------------
func _test_multi_levelup() -> void:
	var lc := LevelComponent.new()
	add_child(lc)
	# XP wystarczajacy na dojscie do lvl 6 (awanse 2..6 = 5 punktow umiejetnosci + 1 punkt mocy za lvl 5).
	var need := LevelComponent.total_xp_for_level(6)
	lc.grant_xp(need)
	_check(lc.level == 6, "wieloawans: total_xp_for_level(6) -> level 6 (jest %d)" % lc.level)
	# granted: 5 umiejetnosci (lvl 2..6) + 1 mocy (lvl 5). available = 6 (zaden niewydany).
	_check(lc.available_points() == 6, "lvl 6: 5 umiej + 1 mocy = 6 punktow (jest %d)" % lc.available_points())
	_check(lc.granted_power_points == 1, "punkt mocy co 5 lvl: lvl6 -> 1 (jest %d)" % lc.granted_power_points)
	print("[E3] wieloawans: lvl 6, punkty=%d (mocy=%d)" % [lc.available_points(), lc.granted_power_points])
	lc.queue_free()


# ---------------------------------------------------------------------------
#  (4) Alokacja zmienia get_stat()
# ---------------------------------------------------------------------------
func _test_allocate_changes_stat() -> void:
	var stack := _make_stack(_make_test_tree())
	var stats: StatsComponent = stack[0]
	var level: LevelComponent = stack[1]
	var tree: SkillTreeComponent = stack[2]
	level.grant_xp(LevelComponent.total_xp_for_level(5))   # pare punktow

	var base_dmg := stats.get_stat(&"damage")     # 18 baza
	var ok_root := tree.allocate(&"root")          # +20% increased
	var after_root := stats.get_stat(&"damage")
	_check(ok_root, "alokacja root sie udala")
	_check(absf(after_root - base_dmg * 1.2) < EPS, "root +20%%: %.2f -> %.2f (ozcz %.2f)" % [base_dmg, after_root, base_dmg * 1.2])

	var ok_child := tree.allocate(&"child")        # +5 flat (przed increased)
	var after_child := stats.get_stat(&"damage")
	_check(ok_child, "alokacja child (prereq root spelniony)")
	_check(absf(after_child - (base_dmg + 5.0) * 1.2) < EPS, "child +5 flat: %.2f (ozcz %.2f)" % [after_child, (base_dmg + 5.0) * 1.2])
	print("[E3] alokacja: damage %.2f -> root %.2f -> +child %.2f" % [base_dmg, after_root, after_child])
	_free_stack(stack)


# ---------------------------------------------------------------------------
#  (5) Prerekwizyty + gate poziomu (keystone lvl 25)
# ---------------------------------------------------------------------------
func _test_prereq_and_gate() -> void:
	var stack := _make_stack(_make_test_tree())
	var level: LevelComponent = stack[1]
	var tree: SkillTreeComponent = stack[2]
	level.grant_xp(LevelComponent.total_xp_for_level(5))   # lvl 5 (< 25)

	# child wymaga root — bez root nie wejdzie.
	_check(not tree.allocate(&"child"), "child bez prereq root -> odmowa")
	_check(tree.allocate(&"root"), "root wchodzi (korzen)")
	# keystone wymaga lvl 25 — na lvl 5 odmowa nawet z prereq root.
	_check(not tree.allocate(&"keystone"), "keystone na lvl 5 -> odmowa (gate min_level 25)")
	_check(tree.cannot_allocate_reason(&"keystone").contains("poziom"), "powod keystone = poziom")
	# Dobij do lvl 25 -> keystone wchodzi.
	level.grant_xp(LevelComponent.total_xp_for_level(25) - level.xp - LevelComponent.total_xp_for_level(level.level))
	# (powyzsze moze nie trafic idealnie — uzyj load_from dla pewnosci poziomu)
	level.load_from(25, 0)
	tree._sync_spent_points()   # po zmianie poziomu dostepne punkty inne
	_check(tree.allocate(&"keystone"), "keystone na lvl 25 -> wchodzi (jest punkt + prereq + gate)")
	print("[E3] prereq+gate: keystone zablokowany do lvl 25, potem OK")
	_free_stack(stack)


# ---------------------------------------------------------------------------
#  (6) Dealokacja zwraca punkt i usuwa modyfikator
# ---------------------------------------------------------------------------
func _test_deallocate_refunds() -> void:
	var stack := _make_stack(_make_test_tree())
	var stats: StatsComponent = stack[0]
	var level: LevelComponent = stack[1]
	var tree: SkillTreeComponent = stack[2]
	level.grant_xp(LevelComponent.total_xp_for_level(5))
	var base_dmg := stats.get_stat(&"damage")
	tree.allocate(&"root")
	var pts_after_alloc := level.available_points()
	# Nie da sie cofnac root, gdy child stoi na nim.
	tree.allocate(&"child")
	_check(not tree.deallocate(&"root"), "cofniecie root z zaleznym child -> odmowa (spojnosc)")
	# Cofnij child, potem root -> staty wracaja do bazy, punkty zwrocone.
	_check(tree.deallocate(&"child"), "cofniecie child OK")
	_check(tree.deallocate(&"root"), "cofniecie root OK po usunieciu child")
	var after := stats.get_stat(&"damage")
	_check(absf(after - base_dmg) < EPS, "po cofnieciu staty wracaja: %.2f (baza %.2f)" % [after, base_dmg])
	_check(level.available_points() == pts_after_alloc + 1, "zwrot punktu po cofnieciu root")
	print("[E3] dealokacja: damage wraca do %.2f, punkty zwrocone" % after)
	_free_stack(stack)


# ---------------------------------------------------------------------------
#  (7) Respec — zwrot punktow za walute
# ---------------------------------------------------------------------------
func _test_respec() -> void:
	var stack := _make_stack(_make_test_tree())
	var stats: StatsComponent = stack[0]
	var level: LevelComponent = stack[1]
	var tree: SkillTreeComponent = stack[2]
	level.grant_xp(LevelComponent.total_xp_for_level(5))
	var base_dmg := stats.get_stat(&"damage")
	tree.allocate(&"root")
	tree.allocate(&"child")
	var allocated := tree.allocated_ids().size()
	_check(allocated == 2, "2 wezly zaalokowane przed respec (jest %d)" % allocated)

	# Portfel testowy (Orby). Koszt pierwszego respecu = 500 (schodek 0).
	var wallet := {"orbs": 1000}
	var pool := func() -> int: return wallet["orbs"]
	var spend := func(amount: int) -> void: wallet["orbs"] -= amount
	var cost := SkillTreeComponent.orb_cost_for(0)
	_check(cost == 500, "koszt respec #0 = 500 Orb (jest %d)" % cost)

	var refunded := tree.respec(cost, pool, spend)
	_check(refunded == 2, "respec zwrocil 2 punkty (jest %d)" % refunded)
	_check(wallet["orbs"] == 500, "respec pobral 500 Orb (zostalo %d)" % wallet["orbs"])
	_check(tree.allocated_ids().is_empty(), "po respec brak alokacji")
	_check(absf(stats.get_stat(&"damage") - base_dmg) < EPS, "po respec staty = baza")
	_check(level.available_points() == level.total_points(), "po respec wszystkie punkty wolne")

	# Za malo waluty -> brak respecu (reszta nietkniety stan).
	tree.allocate(&"root")
	var poor := {"orbs": 10}
	var ppool := func() -> int: return poor["orbs"]
	var pspend := func(amount: int) -> void: poor["orbs"] -= amount
	var ref2 := tree.respec(SkillTreeComponent.orb_cost_for(1), ppool, pspend)
	_check(ref2 == 0, "respec za malo waluty -> 0 zwroconych (jest %d)" % ref2)
	_check(tree.is_allocated(&"root"), "po nieudanym respec alokacja nietknieta")
	print("[E3] respec: zwrot 2 pkt za 500 Orb; za malo waluty -> brak respecu")
	_free_stack(stack)


# ---------------------------------------------------------------------------
#  (8) Zasob klasy FURIA (Wojownik)
# ---------------------------------------------------------------------------
func _test_rage_resource() -> void:
	var cr := ClassResourceComponent.new()
	cr.build_for(&"warrior")
	add_child(cr)
	_check(cr.kind == ClassResourceComponent.Kind.RAGE, "Wojownik -> tryb FURIA")
	_check(cr.rage == 0.0, "Furia startuje od 0")

	cr.on_hit_dealt(true)         # +6
	_check(absf(cr.rage - 6.0) < EPS, "zadany cios +6 Furii (jest %.1f)" % cr.rage)
	cr.on_hit_taken()             # +4
	_check(absf(cr.rage - 10.0) < EPS, "otrzymany cios +4 Furii -> 10 (jest %.1f)" % cr.rage)

	# Cap 100: nasyc i sprawdz clamp.
	for i in range(30):
		cr.on_hit_dealt(true)
	_check(cr.rage <= 100.0 + EPS, "Furia cap 100 (jest %.1f)" % cr.rage)
	_check(absf(cr.rage - 100.0) < EPS, "Furia dochodzi do 100 (jest %.1f)" % cr.rage)

	# Wydatek (finisher) 30 Furii.
	cr.spend(&"rage", 30.0)
	_check(absf(cr.rage - 70.0) < EPS, "finisher -30 Furii -> 70 (jest %.1f)" % cr.rage)

	# Zanik: po RAGE_DECAY_DELAY (3 s) ciszy zanika 5/s. Symulujemy _process manualnie.
	var before := cr.rage
	# 3 s ciszy -> zanik nie ruszyl jeszcze (graniczy z delay).
	cr._process(2.9)
	_check(absf(cr.rage - before) < EPS, "przed 3 s ciszy Furia nie zanika (jest %.1f)" % cr.rage)
	# Kolejne 2 s (lacznie >3 s) -> zanik 5/s przez ~1.9 s realnego zaniku.
	cr._process(2.0)
	_check(cr.rage < before, "po 3 s ciszy Furia zanika (przed %.1f, po %.1f)" % [before, cr.rage])
	print("[E3] FURIA: +6 zadany / +4 obrywany / cap 100 / -30 finisher / zanik po 3 s OK")
	cr.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
#  (9) MANA (Mag) regen + COMBO (Ranger)
# ---------------------------------------------------------------------------
func _test_mana_and_combo() -> void:
	var mage := ClassResourceComponent.new()
	mage.build_for(&"mage")
	add_child(mage)
	_check(mage.kind == ClassResourceComponent.Kind.MANA, "Mag -> tryb MANA")
	_check(absf(mage.mana - mage.mana_max) < EPS, "Mag startuje z pelna mana")
	mage.spend(&"mana", 40.0)
	var after_spend := mage.mana
	mage._process(1.0)            # regen ~5/s
	_check(mage.mana > after_spend, "Mana regeneruje w czasie (%.1f -> %.1f)" % [after_spend, mage.mana])
	mage.queue_free()

	var ranger := ClassResourceComponent.new()
	ranger.build_for(&"ranger")
	add_child(ranger)
	_check(ranger.kind == ClassResourceComponent.Kind.COMBO_FOCUS, "Ranger -> tryb COMBO+FOCUS")
	for i in range(7):
		ranger.on_hit_dealt(true)  # builder +1 (cap 5)
	_check(ranger.combo == 5, "Combo builder +1 cap 5 (jest %d)" % ranger.combo)
	ranger.spend(&"combo", 5)
	_check(ranger.combo == 0, "finisher wydaje Combo -> 0 (jest %d)" % ranger.combo)
	print("[E3] MANA regen OK; COMBO builder/cap/finisher OK")
	ranger.queue_free()


# ---------------------------------------------------------------------------
#  (10) Starter Wojownik/Berserker — drzewko z SkillDB (8 wezlow + keystone lvl 25)
# ---------------------------------------------------------------------------
func _test_starter_tree() -> void:
	var tree_res: SkillTreeResource = null
	if typeof(SkillDB) != TYPE_NIL and SkillDB != null and SkillDB.has_method("tree"):
		tree_res = SkillDB.tree(&"warrior")
	_check(tree_res != null, "SkillDB ma drzewko warrior (.tres na dysku)")
	if tree_res == null:
		return
	_check(tree_res.nodes.size() == 8, "drzewko Wojownika ma 8 wezlow (jest %d)" % tree_res.nodes.size())
	var has_keystone := false
	var keystone_min := 0
	var ids: Array[StringName] = []
	for n in tree_res.nodes:
		ids.append(n.id)
		if n.is_keystone:
			has_keystone = true
			keystone_min = n.min_level
	_check(has_keystone, "drzewko ma keystone")
	_check(keystone_min == 25, "keystone gated lvl 25 (jest %d)" % keystone_min)
	_check(ids.has(&"war_battle_fury"), "ma wezel Furia Bitwy (root)")
	# Funkcjonalny smoke: alokuj root Furia Bitwy -> rage_gen rosnie przez get_stat.
	var stats := StatsComponent.new()
	stats.base = StatBlock.new()
	add_child(stats)
	var level := LevelComponent.new()
	add_child(level)
	level.load_from(30, 0)        # dosc punktow + powyzej keystone gate
	var tc := SkillTreeComponent.new()
	add_child(tc)
	tc.setup(tree_res, level)
	stats.register_provider(tc)
	var base_rg := stats.get_stat(&"rage_gen")    # baza 1.0
	# FUNKCJONALNY test petli zwrotnej (review major): zasob klasy WPIETY do StatsComponentu — przed
	# alokacja Furia za cios = 6.0; po alokacji Furia Bitwy (+25% rage_gen) musi byc 7.5, a nie wciaz 6.0.
	var cr := ClassResourceComponent.new()
	cr.build_for(&"warrior")
	add_child(cr)
	cr.set_stats(stats)
	cr.on_hit_dealt(true)
	_check(absf(cr.rage - 6.0) < EPS, "przed alokacja: cios buduje 6 Furii (jest %.2f)" % cr.rage)
	cr.spend(&"rage", cr.rage)                     # wyzeruj przed pomiarem po alokacji
	tc.allocate(&"war_battle_fury")
	var after_rg := stats.get_stat(&"rage_gen")
	_check(after_rg > base_rg, "Furia Bitwy +25%% rage_gen: %.2f -> %.2f" % [base_rg, after_rg])
	cr.on_hit_dealt(true)
	_check(absf(cr.rage - 7.5) < EPS, "po alokacji Furia Bitwy: cios buduje 6*1.25=7.5 Furii (jest %.2f)" % cr.rage)
	print("[E3] starter Wojownik: 8 wezlow, keystone lvl 25, Furia Bitwy rage_gen %.2f->%.2f, cios->%.1f Furii" % [base_rg, after_rg, cr.rage])
	cr.queue_free(); stats.queue_free(); level.queue_free(); tc.queue_free()


# ---------------------------------------------------------------------------
#  (11) Save round-trip progresji
# ---------------------------------------------------------------------------
func _test_save_roundtrip() -> void:
	var sd := SaveData.new()
	sd.class_id = &"warrior"
	sd.level = 27
	sd.xp = 1234
	sd.orbs = 750
	sd.allocated_passives = [&"war_battle_fury", &"war_damage_1", &"war_reckless"]
	var d := sd.to_dict()
	var rt := SaveData.from_dict(d)
	_check(rt.level == 27, "save level round-trip (jest %d)" % rt.level)
	_check(rt.xp == 1234, "save xp round-trip (jest %d)" % rt.xp)
	_check(rt.orbs == 750, "save orbs round-trip (jest %d)" % rt.orbs)
	_check(rt.allocated_passives.size() == 3, "save allocated_passives round-trip (jest %d)" % rt.allocated_passives.size())
	_check(rt.allocated_passives.has(&"war_reckless"), "alokacja keystone zachowana w save")
	# Odtworzenie do LevelComponent: poziom -> punkty deterministyczne.
	var lc := LevelComponent.new()
	add_child(lc)
	lc.load_from(rt.level, rt.xp)
	_check(lc.total_points() >= 26, "lvl 27 -> >=26 punktow lacznie (jest %d)" % lc.total_points())
	print("[E3] save round-trip: lvl=%d xp=%d orbs=%d alloc=%d" % [rt.level, rt.xp, rt.orbs, rt.allocated_passives.size()])
	lc.queue_free()


# ---------------------------------------------------------------------------
#  (12) Save round-trip przez PRAWDZIWY PLIK (SaveManager) — sciezka zapisu w grze (review major)
# ---------------------------------------------------------------------------
## DoD 'poziom/xp/punkty/waluta/alokacja w save': wczesniej testowany tylko in-memory (to_dict/from_dict).
## Tu zapisujemy do pliku tymczasowego przez SaveManager.save_character i odczytujemy z powrotem —
## tak jak robi to gra przez Player.save_progression() na zamknieciu/awansie/respec.
func _test_save_file_roundtrip() -> void:
	if typeof(SaveManager) == TYPE_NIL or SaveManager == null:
		_check(false, "SaveManager autoload dostepny")
		return
	var path := "user://saves/_e3_test_char.json"
	var sd := SaveData.new()
	sd.class_id = &"warrior"
	sd.level = 14
	sd.xp = 321
	sd.orbs = 640
	sd.gold = 99
	sd.allocated_passives = [&"war_battle_fury", &"war_damage_1"]
	var wrote := SaveManager.save_character(sd, path)
	_check(wrote, "SaveManager.save_character zapisal plik")
	var rt := SaveManager.load_character(path)
	_check(rt != null, "SaveManager.load_character odczytal plik")
	if rt != null:
		_check(rt.level == 14, "plik: level round-trip (jest %d)" % rt.level)
		_check(rt.xp == 321, "plik: xp round-trip (jest %d)" % rt.xp)
		_check(rt.orbs == 640, "plik: orbs round-trip (jest %d)" % rt.orbs)
		_check(rt.gold == 99, "plik: gold round-trip (jest %d)" % rt.gold)
		_check(rt.allocated_passives.size() == 2, "plik: alokacja round-trip (jest %d)" % rt.allocated_passives.size())
		_check(rt.allocated_passives.has(&"war_battle_fury"), "plik: zachowany war_battle_fury")
	# Sprzatanie pliku tymczasowego.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("[E3] save FILE round-trip (SaveManager): lvl/xp/orby/zloto/alokacja OK")


# ---------------------------------------------------------------------------
#  (13) mana_max sledzi StatsComponent (loot +max many) — review minor (jednorazowy odczyt)
# ---------------------------------------------------------------------------
## Po wpieciu StatsComponentu zmiana mana_max (np. afiks z lootu) musi podniesc pule, a nie zostac
## odczytana raz przy buildzie. Zachowanie ulamka wypelnienia: pelny mag -> pelny po wzroscie max.
func _test_mana_max_rescale() -> void:
	var stats := StatsComponent.new()
	stats.base = StatBlock.new()           # mana_max baza 100
	add_child(stats)
	var cr := ClassResourceComponent.new()
	cr.build_for(&"mage")
	add_child(cr)
	cr.set_stats(stats)
	_check(absf(cr.mana_max - 100.0) < EPS, "mana_max baza 100 po set_stats (jest %.1f)" % cr.mana_max)
	_check(absf(cr.mana - 100.0) < EPS, "pelny mag po set_stats (jest %.1f)" % cr.mana)
	# Loot +50 many: dolozenie modyfikatora -> stats_changed -> mana_max rosnie, pelny zostaje pelny.
	var loot_mods: Array[StatModifier] = [StatModifier.make(&"mana_max", StatModifier.Op.FLAT, 50.0, [], &"test_loot", &"ring")]
	stats.add_modifiers(loot_mods)
	_check(absf(cr.mana_max - 150.0) < EPS, "mana_max sledzi loot (+50 -> 150, jest %.1f)" % cr.mana_max)
	_check(absf(cr.mana - 150.0) < EPS, "pelny mag skaluje do nowego max (jest %.1f)" % cr.mana)
	print("[E3] mana_max sledzi StatsComponent (loot +50 -> %.0f) OK" % cr.mana_max)
	stats.queue_free(); cr.queue_free()


# ---------------------------------------------------------------------------
#  (14) HUD Ranger — widget pipsow COMBO (setup_combo + on_class_combo_changed)
# ---------------------------------------------------------------------------
## Smoke: HUD buduje N pipsow COMBO i zapala dokladnie `count`. To OSOBNY widget od melee "Combo xN"
## (set_combo) — pokazuje zasob builder/finisher Rangera (GDD 4.3). Lustro spiecia w Main._setup_hud.
func _test_ranger_hud_combo_pips() -> void:
	var hud = HUDScript.new()
	add_child(hud)   # _ready -> _build_bars (kontener pipsow pusty/ukryty do setup_combo)
	_check(hud.has_method("setup_combo"), "HUD ma setup_combo")
	_check(hud.has_method("on_class_combo_changed"), "HUD ma on_class_combo_changed")

	# combo_max Rangera (0..5) buduje 5 pipsow; widget staje sie widoczny.
	hud.setup_combo(5)
	_check(hud._combo_pips.size() == 5, "setup_combo(5) tworzy 5 pipsow (jest %d)" % hud._combo_pips.size())
	_check(hud._combo_root.visible, "widget pipsow COMBO widoczny po setup_combo")

	# Builder: 3 combo -> dokladnie 3 zapalone pipsy, reszta pusta.
	hud.on_class_combo_changed(3, 5)
	var lit := 0
	for pip in hud._combo_pips:
		if pip.color == HUDScript.COMBO_PIP_ON:
			lit += 1
	_check(lit == 3, "on_class_combo_changed(3,5) zapala 3 pipsy (jest %d)" % lit)

	# Finisher: wydanie combo -> 0 zapalonych.
	hud.on_class_combo_changed(0, 5)
	var lit0 := 0
	for pip in hud._combo_pips:
		if pip.color == HUDScript.COMBO_PIP_ON:
			lit0 += 1
	_check(lit0 == 0, "po finisherze 0 zapalonych pipsow (jest %d)" % lit0)

	# Melee "Combo xN" (set_combo) to INNY widget — nie rusza pipsow zasobu klasy.
	_check(hud.has_method("set_combo"), "HUD nadal ma osobne melee set_combo (nie scalone z pipsami)")
	print("[E3] HUD Ranger: 5 pipsow COMBO, zapala count, finisher gasi; melee set_combo osobno OK")
	hud.queue_free()


func _free_stack(stack: Array) -> void:
	for n in stack:
		if is_instance_valid(n):
			n.queue_free()
