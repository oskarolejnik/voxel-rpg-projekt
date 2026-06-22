class_name ItemResource
extends Resource
## ItemResource.gd — DEFINICJA itemu (read-only z ItemDB). TDD 2.4.
## To, co lezy w plecaku, to ItemInstance (lekka, z seed) — patrz ItemInstance.gd.
## Etap 0: tylko schemat danych.

enum Slot { WEAPON, HELM, CHEST, LEGS, BOOTS, TRINKET, CONSUMABLE, MATERIAL }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, SET }   # KANON tierow (GDD 6.2)

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D
@export var mesh: PackedScene                         # voxelowy model broni/itemu
@export var slot: Slot = Slot.WEAPON
@export var weapon_class: StringName = &""            # &"axe2h"/&"wand"/&"bow"... -> nadpisuje bron
@export var base_modifiers: Array[StatModifier] = []  # implicit
@export var max_sockets: int = 0
@export var set_id: StringName = &""
@export var req_level: int = 1
@export var stack_size: int = 1
