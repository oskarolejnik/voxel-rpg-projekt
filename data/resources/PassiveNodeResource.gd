class_name PassiveNodeResource
extends Resource
## PassiveNodeResource.gd — wezel drzewka pasywow (TDD 2.3). Etap 0: tylko schemat.

@export var id: StringName = &""
@export var display_name: String = ""
@export var modifiers: Array[StatModifier] = []
@export var cost_points: int = 1
@export var requires: Array[StringName] = []         # prerekwizyty (id innych wezlow)
@export var min_level: int = 1                        # keystone=25, capstone=60
@export var is_keystone: bool = false
@export var grants_skill: StringName = &""
