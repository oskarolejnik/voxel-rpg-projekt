class_name ItemResource
extends Resource
## ItemResource.gd — DEFINICJA itemu (read-only z ItemDB). TDD 2.4.
## To, co lezy w plecaku, to ItemInstance (lekka, z seed) — patrz ItemInstance.gd.
## Etap 0: tylko schemat danych.

# UWAGA (zapis): Slot i Rarity to SUROWE INTY w zapisie (ItemInstance.rarity, equipment_to_save).
# WOLNO TYLKO DOPISYWAĆ NA KOŃCU — przestawienie/wstawienie cicho przemapuje każdy zapisany przedmiot.
# Sloty 8-12 (rękawice/naramienniki/pas/peleryna/amulet) i tiery 6-7 (mityczny/prastary) dopisane.
enum Slot { WEAPON, HELM, CHEST, LEGS, BOOTS, TRINKET, CONSUMABLE, MATERIAL, GLOVES, SHOULDERS, BELT, CLOAK, AMULET }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, SET, MYTHIC, ANCIENT }   # KANON tierow (GDD 6.2 + rozszerzenie)

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D
@export var mesh: PackedScene                         # (legacy/nieużywane) — patrz visual_kind
# LOOT Faza 3 — WIDOCZNY MODEL ekwipunku. visual_kind wybiera proceduralną rzeźbę (_sculpt_gear_<kind>
# w Player), NIE renderujemy PackedScene (perf przy 100+). visual_tint: a==0 => dziedzicz paletę klasy.
# visual_glow: a==0 => energia emisji z rzadkości. Definicyjne => save-free.
@export var visual_kind: StringName = &""             # &"sword"/&"helm"/&"pauldron"/&"cloak"... (puste => domyślny wg slotu)
@export var visual_tint: Color = Color(0, 0, 0, 0)
@export var visual_glow: Color = Color(0, 0, 0, 0)
@export var slot: Slot = Slot.WEAPON
@export var weapon_class: StringName = &""            # &"axe2h"/&"wand"/&"bow"... -> nadpisuje bron
@export var base_modifiers: Array[StatModifier] = []  # implicit
@export var max_sockets: int = 0
@export var set_id: StringName = &""
@export var req_level: int = 1
# LOOT Faza 2 — restrykcja klasowa (puste = każda klasa). Filtr w LootService._roll_base_id z fallbackiem
# do nieograniczonych, gdy pula klasowa pusta (grupa co-op nadal dostaje dropy). Definicyjne => save-free.
@export var allowed_classes: Array[StringName] = []
# LOOT Faza 4 — EFEKTY WYPOSAŻENIA (procy: poison-on-hit, frost-nova, heal-on-kill...). Implicit (legendy/
# mythic). Referowane => save-free. Wykonuje host-only EffectComponent. Patrz EffectResource.
@export var equip_effects: Array[EffectResource] = []
@export var stack_size: int = 1
# Konsumpcyjne (slot CONSUMABLE): efekt użycia (mikstury). 0/&"" = brak danego efektu.
@export var heal_amount: float = 0.0            # ile HP leczy po użyciu
@export var restore_stat: StringName = &""      # zasób do uzupełnienia (np. &"stamina")
@export var restore_amount: float = 0.0         # ile zasobu uzupełnia
