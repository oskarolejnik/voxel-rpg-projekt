class_name GemResource
extends Resource
## GemResource.gd — klejnot do socketa (TDD 2.4). Etap 0: tylko schemat.

@export var id: StringName = &""
@export var display_name: String = ""
@export var quality: int = 1                          # 1..5 (Skaza..Doskonaly)
@export var modifiers: Array[StatModifier] = []
