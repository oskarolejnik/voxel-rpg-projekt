extends Node
## AllClassTreesTest.gd — po unifikacji namespace (#namespace) + autorstwie drzewek (#12):
## KAŻDA klasa ContentDB ma niepuste drzewko (SkillDB.tree(id) != null, nodes > 0) keyed kanonicznym
## (polskim) id. Łapie regresję „klasa bez drzewka -> punkty niewydawalne".
## Uruchomienie: godot --headless res://test/AllClassTreesTest.tscn

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[CLASSES] FAIL: %s" % msg)


func _ready() -> void:
	print("[CLASSES] === all-class skill trees test ===")
	if ContentDB != null:
		ContentDB.reload()
	if SkillDB != null:
		SkillDB.reload()
	_check(ContentDB != null and SkillDB != null, "brak ContentDB/SkillDB")
	if ContentDB == null or SkillDB == null:
		get_tree().quit(1)
		return

	var ids: Array = ContentDB.class_ids()
	_check(ids.size() >= 11, "ContentDB ma %d klas (oczekiwane >= 11)" % ids.size())
	var with_tree := 0
	for id in ids:
		var t: SkillTreeResource = SkillDB.tree(id)
		_check(t != null, "klasa &\"%s\" -> brak drzewka (SkillDB.tree == null)" % id)
		if t != null:
			_check(t.nodes.size() > 0, "klasa &\"%s\" -> drzewko PUSTE (0 nodow)" % id)
			if t.nodes.size() > 0:
				with_tree += 1
	_check(with_tree == ids.size(), "tylko %d/%d klas ma niepuste drzewko" % [with_tree, ids.size()])
	print("[CLASSES] %d/%d klas ma niepuste drzewko" % [with_tree, ids.size()])

	if _failures == 0:
		print("[CLASSES] ALL OK")
	else:
		printerr("[CLASSES] FAILURES: %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
