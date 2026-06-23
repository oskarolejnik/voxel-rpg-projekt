class_name OriginResource
extends Resource
## OriginResource.gd — pochodzenie/tło postaci (GDD sek.1, data-driven). Drobne bonusy + punkt startu.

@export var id: StringName = &""
@export var display_name: String = ""
@export var lore: String = ""
@export var stat_bonus: Dictionary = {}             # drobny bonus {stat: wartość}
@export var start_biome: StringName = &""           # biom startowy (powiązanie ze światem)
@export var start_items: PackedStringArray = []     # startowy ekwipunek (id itemów)
