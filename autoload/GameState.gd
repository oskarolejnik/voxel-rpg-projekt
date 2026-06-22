extends Node
## GameState.gd (autoload) — globalny stan SESJI (TDD 1.3). NIE trzyma stanu encji (to komponenty).
## Trzyma: tryb gry (lustro NetManager.mode dla wygody), pauze, ref do lokalnego gracza,
## biezacy biom/run. Etap 0: szkielet + ref gracza + pauza.

enum Mode { SINGLE, HOST, CLIENT }

var mode: Mode = Mode.SINGLE
var paused: bool = false

## Referencja do lokalnej encji gracza (ustawia Main.gd po spawnie — opcjonalnie w pozniejszych
## etapach). Trzymana jako Node, by nie wiazac GameState z konkretna klasa Player.
var local_player: Node = null

## Biezacy run/biom (Etap 4+). Etap 0: tylko pola.
var current_biome: StringName = &""
var current_run_seed: int = 0


func set_local_player(p: Node) -> void:
	local_player = p


func is_paused() -> bool:
	return paused


func set_paused(value: bool) -> void:
	paused = value
	get_tree().paused = value
