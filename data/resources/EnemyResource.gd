class_name EnemyResource
extends Resource
## EnemyResource.gd — definicja wroga (TDD 2.5). Etap 0: tylko schemat.
## stats: StatBlock skalowany per wariant (Brute/Slinger to te same eksporty).

@export var id: StringName = &""
@export var display_name: String = ""
@export var scene: PackedScene
@export var stats: StatBlock
@export var loot_table: LootTableResource
@export var xp_reward: int = 10
@export var ai_profile: StringName = &"melee"        # &"melee"/&"ranged"/&"caster"
@export var threat_tier: StringName = &"trash"       # &"trash"/&"elite"/&"boss" (telegraf — GDD 5.4)
## LOOT Faza 6 — WORLD-BOSS: niepuste => to świat-boss o tym id. Pierwszy kill (raz na save) daje
## gwarantowany ANCIENT; kolejne kille podłogę MYTHIC. LootService.drop_for + GameState.cleared_world_bosses.
@export var world_boss_id: StringName = &""
## EKOSYSTEM (GDD Świat §4): 0=Hostile (agresja na widok), 1=Neutral (kontratak po prowokacji),
## 2=Passive (nigdy nie atakuje, ucieka). Czytane przez Enemy.configure_from_resource -> AIComponent.
@export_enum("Hostile", "Neutral", "Passive") var disposition: int = 0
## COMBAT (reaktywność): pula POISE — odporność na przerwanie ataku. 0 = trash (każdy cios przerywa
## windup i staggeruje); >0 = elity/bossy (przerywają się dopiero po złamaniu poise — nie da się ich
## permastunować trashem). Regeneruje się między ciosami. Czytane przez Enemy.configure_from_resource.
@export var poise: float = 0.0
@export var tameable: bool = false                   # pet od lvl 5
@export var tame_difficulty_mult: float = 1.0
@export var biomes: Array[StringName] = []
## ETAP 4: parametry wariantu spoza StatBlock (windup/zasięg/pocisk/skala/reskin/element).
## Czytane przez Enemy._apply_variant_meta. Klucze (wszystkie opcjonalne):
##   attack_windup, attack_range, attack_entry_delay, aggro_radius, leash_radius (float)
##   projectile_speed, projectile_gravity (float), projectile_pierce (int)
##   body_scale (float), element (StringName), skin_tint/eye_tint (Color)
@export var variant_meta: Dictionary = {}
