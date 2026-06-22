extends Node
## GameState.gd (autoload) — globalny stan SESJI (TDD 1.3). NIE trzyma stanu encji (to komponenty).
## Trzyma: tryb gry (lustro NetManager.mode dla wygody), pauze, ref do lokalnego gracza,
## biezacy biom/run. Etap 0: szkielet + ref gracza + pauza.

enum Mode { SINGLE, HOST, CLIENT }

var mode: Mode = Mode.SINGLE
var paused: bool = false

## TRUE gdy modalne UI (np. ekwipunek) lapie input — gracz NIE chodzi/skacze/sprintuje wtedy.
## Ustawiane przez InventoryUI._set_open(). Player.gd zeruje lokomocje, gdy to jest true. Jedno
## zrodlo prawdy "czy UI ma fokus", zeby ruch i kursor nie walczyly o input (Etap 2 review #4/#5).
var ui_capturing_input: bool = false

## Referencja do lokalnej encji gracza (ustawia Main.gd po spawnie — opcjonalnie w pozniejszych
## etapach). Trzymana jako Node, by nie wiazac GameState z konkretna klasa Player.
var local_player: Node = null

## Biezacy run/biom (Etap 4+). Etap 0: tylko pola.
var current_biome: StringName = &""
var current_run_seed: int = 0

## Zloto sesji (Etap 2: drop zlota z wrogow trafia tutaj; pelna ekonomia w SaveData/Etap 3).
var gold: int = 0
signal gold_changed(amount: int)


func set_local_player(p: Node) -> void:
	local_player = p


## Dodaje zloto (drop z LootDrop). Emituje gold_changed (HUD/UI). Etap 3 podlaczy pelna ekonomie.
func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(0, gold + amount)
	gold_changed.emit(gold)


func is_paused() -> bool:
	return paused


func set_paused(value: bool) -> void:
	paused = value
	get_tree().paused = value
