extends Node
## LootDummyEnemy.gd — atrapa wroga dla Etap2Test. Niesie pola kontekstu lootu, które czyta
## LootService.drop_for (loot_table/loot_ilvl/loot_biome). Bez fizyki/AI — czysty nośnik danych.

@export var loot_table: LootTableResource
@export var loot_ilvl: int = 1
@export var loot_biome: StringName = &"verdant"
