extends Node
## LootDummyEnemy.gd — atrapa wroga dla Etap2Test. Niesie pola kontekstu lootu, które czyta
## LootService.drop_for (loot_table/loot_ilvl/loot_biome). Bez fizyki/AI — czysty nośnik danych.

@export var loot_table: LootTableResource
@export var loot_ilvl: int = 1
@export var loot_biome: StringName = &"verdant"
# ETAP 4: premia rzadkosci z loot_tier biomu (czytana przez LootService._enemy_loot_tier_bonus).
@export var loot_tier_bonus: int = 0
