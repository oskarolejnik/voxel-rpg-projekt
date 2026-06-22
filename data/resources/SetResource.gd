class_name SetResource
extends Resource
## SetResource.gd — zestaw (set) z bonusami za liczbe czesci (TDD 2.4). Etap 0: tylko schemat.

@export var id: StringName = &""
@export var display_name: String = ""
@export var fixed_modifiers: Array[StatModifier] = []   # stale afiksy sztuk (rozpoznawalnosc)
@export var bonuses: Dictionary = {}                    # int(liczba_czesci) -> Array[StatModifier]
