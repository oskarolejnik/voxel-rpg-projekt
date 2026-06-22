class_name HurtboxComponent
extends Area3D
## HurtboxComponent.gd (komponent, Area3D) — przyjmuje trafienie i kieruje je do DamageService
## /HealthComponent encji-wlasciciela (TDD 1.2 / 5). Etap 1 krok 2.
##
## To "cel" hitboxow przeciwnika. Hitbox wykrywa ten Area3D (po warstwie), pobiera z niego
## wlasciciela (owner_entity) i HitData, po czym wola DamageService.request_hit(source, owner, hit).
## Sam hurtbox nic nie liczy — JEDYNE zrodlo obrazen to DamageService (host-authoritative).
##
## Warstwy (TDD 5): hurtbox wroga zyje na bicie enemy_hurtbox; ciala (bit0-2) nietkniete.
## Owner_entity to root encji (CharacterBody3D) — tam siedzi HealthComponent + kontrakt take_damage.

## Bity warstw walki (TDD 5). Bit0-2 (teren/gracz/wrog) ZAREZERWOWANE dla cial — nie ruszamy.
const LAYER_PLAYER_HITBOX: int = 1 << 3   # bit3: ataki gracza/peta
const LAYER_ENEMY_HURTBOX: int = 1 << 4   # bit4: precyzyjny hurtbox wroga
const LAYER_ENEMY_HITBOX: int = 1 << 5    # bit5: ataki/telegrafy wrogow
const LAYER_PLAYER_BODY: int = 1 << 1     # bit1: cialo gracza (= warstwa 2)
const LAYER_ENEMY_BODY: int = 1 << 2      # bit2: cialo wroga (= warstwa 3)

## Root encji, ktora ten hurtbox reprezentuje. Pusta -> get_parent() (komponent jest dzieckiem encji).
@export var owner_path: NodePath

var _owner_entity: Node = null


func _ready() -> void:
	_owner_entity = _resolve_owner()
	monitoring = false        # hurtbox jest PASYWNY — to hitbox monitoruje jego; my tylko istniejemy
	monitorable = true        # ...ale musimy byc wykrywalni przez hitboxy


func _resolve_owner() -> Node:
	if owner_path != NodePath() and has_node(owner_path):
		return get_node(owner_path)
	return get_parent()


## Zwraca root encji (do podania jako 'target' w DamageService). Hitbox tego uzywa.
func get_owner_entity() -> Node:
	if _owner_entity == null or not is_instance_valid(_owner_entity):
		_owner_entity = _resolve_owner()
	return _owner_entity


## Konfiguruje warstwy hurtboxa po stronie wroga (wykrywalny przez hitbox gracza).
func setup_as_enemy() -> void:
	collision_layer = LAYER_ENEMY_HURTBOX | LAYER_ENEMY_BODY
	collision_mask = 0


## Konfiguruje warstwy hurtboxa po stronie gracza (wykrywalny przez hitbox wroga).
func setup_as_player() -> void:
	collision_layer = LAYER_PLAYER_BODY
	collision_mask = 0
