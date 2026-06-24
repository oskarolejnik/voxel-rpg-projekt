extends Node
## GameState.gd (autoload) — globalny stan SESJI (TDD 1.3). NIE trzyma stanu encji (to komponenty).
## Trzyma: tryb gry (lustro NetManager.mode dla wygody), pauze, ref do lokalnego gracza,
## biezacy biom/run. Etap 0: szkielet + ref gracza + pauza.

enum Mode { SINGLE, HOST, CLIENT }

var mode: Mode = Mode.SINGLE
var paused: bool = false

## "Nowa gra" przeładowuje scenę dla czystego startu (świat+postać są budowane raz w Main._ready i
## nie są resetowane). Ta flaga PRZEŻYWA reload (GameState to autoload), więc po przeładowaniu Main
## wie, że ma od razu wejść do świeżej gry (pominąć menu). Konsumowana w Main._setup_menus.
var pending_new_game: bool = false

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

## ETAP 5 — biezaca RUNA dungeonu (instancja efemeryczna). null = gracz w otwartym swiecie.
## Trzyma kontekst aktywnego DungeonRun (seed/tier/biome) + zapamietana pozycje gracza w SWIECIE
## (powrot po pokonaniu bossa/wyjsciu). Instancja jest EFEMERYCZNA — tu trzymamy tylko lekkie dane
## sesji (NIE wezel), zgodnie z zasada "GameState nie trzyma stanu encji" (TDD 1.3). Zapis hybrydowy:
## swiat trwaly zostaje (SaveManager.save_world), runa NIE jest zapisywana (efemeryczna, GDD 8).
##   current_run = {} gdy brak runy; inaczej { seed:int, tier:int, biome:StringName }.
var current_run: Dictionary = {}
## Pozycja gracza w SWIECIE zapamietana przy wejsciu do dungeonu (powrot po wyjsciu).
var world_return_position: Vector3 = Vector3.ZERO
signal run_changed(in_dungeon: bool)


## ETAP 5 — wejscie do runy: zapamietaj kontekst + pozycje powrotu w swiecie. in_dungeon -> true.
func enter_run(seed: int, tier: int, biome: StringName, return_pos: Vector3) -> void:
	current_run = { "seed": seed, "tier": tier, "biome": biome }
	current_run_seed = seed
	world_return_position = return_pos
	run_changed.emit(true)


## ETAP 5 — wyjscie z runy (boss pokonany / wyjscie). Czysci kontekst; in_dungeon -> false.
## Pozycja powrotu zostaje w world_return_position (Main stawia tam gracza). Loot/postep sa juz na
## postaci (SaveManager) — runa efemeryczna znika bez zapisu.
func exit_run() -> void:
	current_run = {}
	run_changed.emit(false)


func in_dungeon() -> bool:
	return not current_run.is_empty()

## Zloto sesji (Etap 2: drop zlota z wrogow trafia tutaj; pelna ekonomia w SaveData/Etap 3).
var gold: int = 0
signal gold_changed(amount: int)

## ETAP 3 — klasa wybranej postaci (Mag/Wojownik/Ranger). Zrodlo dla ClassResourceComponent
## (jaki zasob: Mana/Furia/Combo+Focus) oraz dla SkillDB.tree(class_id) (ktore drzewko). Domyslnie
## Wojownik (klasa startowa vertical slice — GDD 4.2). Kreator postaci (GDD 12) ustawi to docelowo.
var class_id: StringName = &"warrior"

## ETAP 3 — Orby Przemiany (waluta respecu drzewka, GDD 10.1). Zloto powyzej (tani respec).
var orbs: int = 0
signal orbs_changed(amount: int)


func set_local_player(p: Node) -> void:
	local_player = p


## Dodaje zloto (drop z LootDrop). Emituje gold_changed (HUD/UI). Etap 3 podlaczy pelna ekonomie.
func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(0, gold + amount)
	gold_changed.emit(gold)


## ETAP 3 — wydatek/dodanie Orb (respec). spend_orbs zwraca true jesli starczylo.
func add_orbs(amount: int) -> void:
	if amount == 0:
		return
	orbs = maxi(0, orbs + amount)
	orbs_changed.emit(orbs)


func spend_orbs(amount: int) -> bool:
	if amount <= 0:
		return true
	if orbs < amount:
		return false
	orbs -= amount
	orbs_changed.emit(orbs)
	return true


func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func is_paused() -> bool:
	return paused


func set_paused(value: bool) -> void:
	paused = value
	get_tree().paused = value
