class_name RaceResource
extends Resource
## RaceResource.gd — rasa grywalna (GDD sek.3, data-driven). Dane czytane przez ContentDB + kreator.
## Premie rasowe trzymamy jako prosty słownik {stat: wartość} (builder postaci tłumaczy na StatModifier).

@export var id: StringName = &""
@export var display_name: String = ""
@export var lore: String = ""                       # krótki opis (pełne lore w docs/GDD)
@export var biome: StringName = &""                 # &"verdant"/&"emberwaste"/&"frosthelm"/&"" (uniwersalna)
@export var stat_bonus: Dictionary = {}             # np. {"dex": 2, "armor": 0.05}
@export var passive: String = ""                    # opis pasywki rasowej
@export var preferred_roles: PackedStringArray = [] # np. ["ranged_dps","support"]
@export var name_prefix: PackedStringArray = []     # sylaby początkowe (generator imion, GDD sek.5)
@export var name_suffix: PackedStringArray = []     # sylaby końcowe
