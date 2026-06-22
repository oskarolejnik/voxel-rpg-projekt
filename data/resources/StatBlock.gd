class_name StatBlock
extends Resource
## StatBlock.gd — bazowe staty encji (DEFINICJA, nie stan dynamiczny). TDD 2.1.
##
## To wartosci "base" wchodzace do pipeline'u StatsComponent. Domyslne liczby = gracz lvl 1
## z GDD/ROADMAP 6 (HP 100, damage 18, attack_speed 2.2, krytyk 5%/x1.5, move_speed 6...).
## damage == dawne Player.attack_damage; area_radius == dawne Player.attack_range;
## attack_speed == 1/attack_cooldown. Klucze statow czytane przez StringName w StatsComponent.

@export var max_hp: float = 100.0
@export var hp_regen: float = 0.0
@export var max_stamina: float = 100.0
@export var stamina_regen: float = 22.0
@export var damage: float = 18.0                    # == Player.attack_damage
@export var attack_speed: float = 2.2               # == 1/attack_cooldown
@export var crit_chance: float = 0.05
@export var crit_mult: float = 1.5
@export var armor: float = 0.0                      # 0..1 (% redukcji, jak u Enemy)
@export var armor_pierce: float = 0.0
@export var move_speed: float = 6.0
@export var dodge_iframes: float = 0.30
@export var lifesteal: float = 0.0
@export var area_radius: float = 2.2                # == Player.attack_range
@export var cdr: float = 0.0
@export var magic_find: float = 0.0
@export var resistances: Dictionary = {}            # StringName(element) -> float(%)
@export var elemental: Dictionary = {}              # &"fire"/&"frost"/&"poison"/&"lightning"/&"dark" -> float
@export var pet_damage: float = 0.0
@export var pet_hp: float = 0.0
@export var primary: Dictionary = {}                # &"str"/&"dex"/&"int" -> int (skalowanie klas)


## Odczyt bazowej wartosci statu po kluczu StringName. Uzywane przez StatsComponent._base_value().
## Dla statow skalarnych zwraca pole; dla nieznanych zwraca 0.0 (modyfikatory i tak moga je dosypac).
func get_base(stat: StringName) -> float:
	match stat:
		&"max_hp": return max_hp
		&"hp_regen": return hp_regen
		&"max_stamina": return max_stamina
		&"stamina_regen": return stamina_regen
		&"damage": return damage
		&"attack_speed": return attack_speed
		&"crit_chance": return crit_chance
		&"crit_mult": return crit_mult
		&"armor": return armor
		&"armor_pierce": return armor_pierce
		&"move_speed": return move_speed
		&"dodge_iframes": return dodge_iframes
		&"lifesteal": return lifesteal
		&"area_radius": return area_radius
		&"cdr": return cdr
		&"magic_find": return magic_find
		&"pet_damage": return pet_damage
		&"pet_hp": return pet_hp
		_:
			# Staty zlozone (elemental/resistances/primary) nie sa skalarem -> sprawdz slowniki.
			if elemental.has(stat):
				return float(elemental[stat])
			if resistances.has(stat):
				return float(resistances[stat])
			if primary.has(stat):
				return float(primary[stat])
			return 0.0


## Plytka kopia (do nadawania instancji encji wlasnego StatBlock bez mutowania definicji z DB).
func duplicate_block() -> StatBlock:
	return duplicate(true) as StatBlock
