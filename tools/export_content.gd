extends Node
## export_content.gd — NARZĘDZIE: zapisuje zaseedowane (w kodzie) zasoby ContentDB do plików .tres
## w res://data/content/{races,classes,origins}/. ContentDB i tak SKANUJE ten katalog i nadpisuje seed
## po `id` — więc pliki == seed (scan==seed, brak dubli; klucz to id). Po eksporcie treść jest
## edytowalna w inspektorze (data-driven), a seed zostaje jako fallback. Uruchom:
##   godot --headless --path . res://tools/export_content.tscn

const BASE := "res://data/content"


func _ready() -> void:
	var groups := {
		"races": ContentDB.races(),
		"classes": ContentDB.classes(),
		"origins": ContentDB.origins(),
	}
	var total := 0
	var failed := 0
	for sub in groups:
		DirAccess.make_dir_recursive_absolute(BASE + "/" + sub)
		for r in groups[sub]:
			var path := "%s/%s/%s.tres" % [BASE, sub, String(r.id)]
			var err := ResourceSaver.save(r, path)
			if err == OK:
				total += 1
			else:
				failed += 1
				printerr("[EXPORT] błąd %d -> %s" % [err, path])
	print("[EXPORT] zapisano %d .tres (races=%d, classes=%d, origins=%d), błędów=%d" % [
		total, ContentDB.races().size(), ContentDB.classes().size(), ContentDB.origins().size(), failed])
	get_tree().quit(1 if failed > 0 or total == 0 else 0)
