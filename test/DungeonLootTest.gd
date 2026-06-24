extends Node
## DungeonLootTest.gd — weryfikuje naprawę: pokoje TREASURE/SECRET dają loot (audyt rank #4).
## Uruchomienie: godot --headless res://test/DungeonLootTest.tscn
##
## Wcześniej TREASURE i SECRET były puste. Teraz _spawn_treasure_loot losuje nagrodę i emituje ją
## przez loot_dropped (ten sam pipeline co drop wroga -> Main -> LootDrop). Testujemy bezpośrednio
## (bez budowy geometrii): bare DungeonRun, ustawiamy seed/tier/biome, wołamy _spawn_treasure_loot.
##
##  (1) TREASURE -> ≥1 item, rzadkość ≥ RARE.
##  (2) SECRET   -> ≥1 item, rzadkość ≥ EPIC (lepsza niż treasure).
##  (3) Determinizm: ten sam seed/room -> ta sama liczba i te same rzadkości.
##  (4) Jest też złoto w dropie.
## Kod wyjścia: 0 = ALL OK, 1 = FAIL.

const DungeonRunScript := preload("res://src/world/DungeonRun.gd")

var _failures := 0
var _last_drops: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[DL] FAIL: %s" % msg)


func _on_loot(_wp: Vector3, drops: Array) -> void:
	_last_drops = drops


func _make_run() -> Object:
	var run = DungeonRunScript.new()
	run._seed = 123456
	run._tier = 2
	run._biome = &"verdant"
	run.loot_dropped.connect(_on_loot)
	return run


func _items(drops: Array) -> Array:
	var out: Array = []
	for d in drops:
		if d is Dictionary and d.get("kind", "") == "item" and d.get("instance", null) != null:
			out.append(d["instance"])
	return out


func _ready() -> void:
	print("[DL] === Dungeon treasure/secret loot test ===")
	if ItemDB != null:
		ItemDB.reload()

	# (1) TREASURE
	var run := _make_run()
	_last_drops = []
	run._spawn_treasure_loot({ "id": 5, "depth": 3, "type": run.RoomType_TREASURE(), "center": Vector3.ZERO })
	var t_items := _items(_last_drops)
	_check(t_items.size() > 0, "TREASURE nie dał żadnego itemu (pokój pusty)")
	for inst in t_items:
		_check(inst.rarity >= ItemResource.Rarity.RARE, "item skarbca poniżej RARE (rarity=%d)" % inst.rarity)
	# (4) złoto
	var has_gold := false
	for d in _last_drops:
		if d is Dictionary and d.get("kind", "") == "gold" and int(d.get("amount", 0)) > 0:
			has_gold = true
	_check(has_gold, "skarbiec nie dał złota")
	print("[DL] (1)(4) TREASURE: %d itemów + złoto OK" % t_items.size())

	# (2) SECRET (wyższa rzadkość)
	var run2 := _make_run()
	_last_drops = []
	run2._spawn_treasure_loot({ "id": 9, "depth": 4, "type": run2.RoomType_SECRET(), "center": Vector3.ZERO })
	var s_items := _items(_last_drops)
	_check(s_items.size() > 0, "SECRET nie dał żadnego itemu")
	for inst in s_items:
		_check(inst.rarity >= ItemResource.Rarity.EPIC, "item sekretu poniżej EPIC (rarity=%d)" % inst.rarity)
	print("[DL] (2) SECRET: %d itemów, rzadkość ≥ EPIC OK" % s_items.size())

	# (3) Determinizm: dwa identyczne runy -> identyczny wynik (liczba + rzadkości).
	var rA := _make_run(); _last_drops = []
	rA._spawn_treasure_loot({ "id": 7, "depth": 3, "type": rA.RoomType_TREASURE(), "center": Vector3.ZERO })
	var a := _items(_last_drops)
	var rB := _make_run(); _last_drops = []
	rB._spawn_treasure_loot({ "id": 7, "depth": 3, "type": rB.RoomType_TREASURE(), "center": Vector3.ZERO })
	var b := _items(_last_drops)
	_check(a.size() == b.size(), "determinizm: różna liczba itemów (%d vs %d)" % [a.size(), b.size()])
	var same := a.size() == b.size()
	if same:
		for i in a.size():
			if a[i].rarity != b[i].rarity:
				same = false
	_check(same, "determinizm: rozjazd rzadkości między identycznymi runami")
	print("[DL] (3) determinizm (ten sam seed -> ten sam loot) OK")

	run.free(); run2.free(); rA.free(); rB.free()
	if _failures == 0:
		print("[DL] ALL OK")
	else:
		printerr("[DL] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
