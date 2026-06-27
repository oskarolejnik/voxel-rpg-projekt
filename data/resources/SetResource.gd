class_name SetResource
extends Resource
## SetResource.gd — zestaw (set) z bonusami za liczbe czesci (TDD 2.4). Etap 0: tylko schemat.

@export var id: StringName = &""
@export var display_name: String = ""
@export var fixed_modifiers: Array[StatModifier] = []   # stale afiksy sztuk (rozpoznawalnosc)
@export var bonuses: Dictionary = {}                    # int(liczba_czesci) -> Array[StatModifier]
# LOOT Faza 5 — PROCY setu (zwykle 6-cz capstone). int(liczba_czesci) -> Array[EffectResource].
# Bliźniak `bonuses`, ale kanał EFEKTÓW (triggery), nie statów. Zbierane przez InventoryComponent
# .collect_effects() przy osiągniętym progu, wykonywane host-only przez EffectComponent. Definicyjne
# (referowane) => ZERO bajtów zapisu; set odtwarza się z liczby założonych części (NIE z SaveData).
@export var procs: Dictionary = {}                      # int(liczba_czesci) -> Array[EffectResource]
