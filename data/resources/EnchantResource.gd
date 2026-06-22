class_name EnchantResource
extends Resource
## EnchantResource.gd — enchant slotu z rangami (TDD 2.4). Etap 0: tylko schemat.

@export var id: StringName = &""
@export var display_name: String = ""
@export var allowed_slots: Array[int] = []
@export var ranks: Array[Dictionary] = []            # [{rank, effect_id, magnitude, modifiers}]
