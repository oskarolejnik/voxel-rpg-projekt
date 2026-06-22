class_name SkillResource
extends Resource
## SkillResource.gd — definicja skilla (TDD 2.3). Etap 0: tylko schemat danych.

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D
@export var class_path: StringName = &""             # do ktorej sciezki (podklasy) nalezy
@export var cost_resource: StringName = &""          # &"mana"/&"rage"/&"combo"/&"focus"/&"stamina"
@export var cost_amount: float = 0.0
@export var cooldown: float = 0.0
@export var cast_time: float = 0.0
@export var damage_mult: float = 1.0
@export var tags: Array[StringName] = []             # tagi skilla (synergia z lootem)
@export var max_augments: int = 3                    # gniazda augmentow (0..3)
@export var scene: PackedScene                       # pocisk/AoE/strefa do zespawnowania
@export var passive_modifiers: Array[StatModifier] = []   # gdy skill wpiety
