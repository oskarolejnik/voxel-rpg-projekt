class_name BiomeResource
extends Resource
## BiomeResource.gd — definicja biomu (TDD 2.5). Etap 0: tylko schemat.
## noise_params NADPISUJE konfiguracje VoxelWorld dla danego biomu (NIE duplikuje generacji).

@export var id: StringName = &""                      # &"verdant"/&"emberwaste"/&"frosthelm"
@export var display_name: String = ""
@export var loot_tier: int = 1
@export var noise_params: Dictionary = {}            # FastNoiseLite config (nadpisanie VoxelWorld)
@export var enemy_spawn_table: Array[Dictionary] = []  # {enemy_id, weight, max_alive}
@export var affix_themes: Array[StringName] = []     # tagi afiksow dosypywanych (GDD 6.4)
@export var entrance_chance: float = 0.01            # szansa wejscia dungeonu na chunk
@export var fog_color: Color = Color.BLACK
@export var ambient_light: Color = Color.BLACK
