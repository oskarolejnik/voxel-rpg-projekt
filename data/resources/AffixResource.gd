class_name AffixResource
extends Resource
## AffixResource.gd — pula afiksow (prefix/suffix) do losowania (TDD 2.4). Etap 0: tylko schemat.

enum Kind { PREFIX, SUFFIX }

@export var id: StringName = &""
@export var kind: Kind = Kind.PREFIX
@export var stat: StringName = &""
@export var op: StatModifier.Op = StatModifier.Op.FLAT
@export var value_min: float = 0.0
@export var value_max: float = 0.0
@export var tags: Array[StringName] = []             # &"fire"/&"defense"/&"crit"...
@export var ilvl_min: int = 1
@export var allowed_slots: Array[int] = []           # ItemResource.Slot
@export var biomes: Array[StringName] = []           # biom dosypujacy ten afiks (pusty = wszedzie)
@export var weight: float = 1.0
