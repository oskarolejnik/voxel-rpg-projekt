class_name SkillTreeResource
extends Resource
## SkillTreeResource.gd — drzewko pasywow per klasa (TDD 2.3). Etap 0: tylko schemat.

@export var class_id: StringName = &""
@export var nodes: Array[PassiveNodeResource] = []
@export var layout: Dictionary = {}                  # id -> Vector2 (pozycja w UI)
