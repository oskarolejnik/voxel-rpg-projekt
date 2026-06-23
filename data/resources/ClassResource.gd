class_name ClassResource
extends Resource
## ClassResource.gd — klasa postaci (GDD sek.4, data-driven). DANE klasy (NIE mylić z
## ClassResourceComponent, który w runtime trzyma pulę Furia/Mana/Focus). Czytane przez ContentDB+kreator.

@export var id: StringName = &""
@export var display_name: String = ""
@export var role: StringName = &""                  # &"tank"/&"melee_dps"/&"ranged_dps"/&"healer"/&"support"
@export var lore: String = ""
@export var resource_kind: StringName = &""         # zasób klasy: &"rage"/&"mana"/&"focus"/&"combo"/&"faith"/&"essence"/&"chi"/&"nature"
@export var primary_stat: StringName = &""          # główny atrybut skalujący (&"str"/&"dex"/&"int"/&"wis")
@export var armor_weight: StringName = &""          # &"light"/&"medium"/&"heavy"
@export var weapons: PackedStringArray = []         # dozwolone bronie
@export var base_stats: Dictionary = {}             # bazowe staty {hp,dmg,armor,...}
@export var skill_hints: PackedStringArray = []     # przykładowe skille (nazwy; pełne def w SkillDB później)
