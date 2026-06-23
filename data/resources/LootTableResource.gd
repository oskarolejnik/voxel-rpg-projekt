class_name LootTableResource
extends Resource
## LootTableResource.gd — tablica lootu (TDD 2.4). Etap 0: tylko schemat (LootService w Etapie 2).

@export var entries: Array[Dictionary] = []          # {item_id, weight, min_qty, max_qty}
@export var rarity_weights: Dictionary = {}          # Rarity -> waga (per biom/dungeon-tier)
@export var affix_count_by_rarity: Dictionary = {}   # Rarity -> Vector2i(min_pre+suf)
@export var gold_min: int = 0
@export var gold_max: int = 0
## ETAP 6: dodatkowe dropy KONKRETNYCH itemow (poza losowanym z rarity), np. tame_charm dla
## oswajalnych bestii. Kazdy wpis: {item_id: StringName, chance: float 0..1}. Item bierzemy WPROST
## z ItemDB po item_id (zwykle CONSUMABLE/MATERIAL), bez losowania afiksow. Szansa rozstrzygana
## per-wpis ze strumienia RNGService.loot (HOST-ONLY przez LootService.drop_for). Pusta -> brak.
@export var item_drops: Array[Dictionary] = []
