class_name LootTableResource
extends Resource
## LootTableResource.gd — tablica lootu (TDD 2.4). Etap 0: tylko schemat (LootService w Etapie 2).

@export var entries: Array[Dictionary] = []          # {item_id, weight, min_qty, max_qty}
@export var rarity_weights: Dictionary = {}          # Rarity -> waga (per biom/dungeon-tier)
@export var affix_count_by_rarity: Dictionary = {}   # Rarity -> Vector2i(min_pre+suf)
@export var gold_min: int = 0
@export var gold_max: int = 0
