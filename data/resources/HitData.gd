class_name HitData
extends RefCounted
## HitData.gd — lekki kontener pojedynczego trafienia (TDD 2.2). Tworzony per cios,
## NIE zapisywany. RefCounted (nie Resource) — zero kosztu serializacji/inspektora.
## W Etapie 0 tylko definicja + (de)serializacja pod przyszle RPC (Etap 1/7).

var source: Node = null                              # kto bije (gracz/wrog/pet)
var base_damage: float = 0.0
var tags: Array[StringName] = []                     # [&"fire",&"aoe",&"spell"]...
var crit_chance: float = 0.05
var crit_mult: float = 1.5
var armor_pierce: float = 0.0                         # combo gracza wlicza tu (0..1)
var lifesteal: float = 0.0
var knockback: float = 6.0                            # sila (zastepuje hardkod 6.0 w take_damage)
var on_hit_effects: Array = []                        # statusy z afiksow/setow
var hit_position: Vector3 = Vector3.ZERO


## Do RPC klient->host (Etap 7). source idzie jako NodePath (Node nieserializowalny).
func to_dict() -> Dictionary:
	return {
		"source": source.get_path() if is_instance_valid(source) else NodePath(),
		"base_damage": base_damage,
		"tags": tags.map(func(t: StringName) -> String: return String(t)),
		"crit_chance": crit_chance,
		"crit_mult": crit_mult,
		"armor_pierce": armor_pierce,
		"lifesteal": lifesteal,
		"knockback": knockback,
		"hit_position": hit_position,
	}


## from_dict NIE rozwiazuje source (Node) — robi to DamageService po stronie odbiorcy
## (get_node(path)), bo HitData nie ma kontekstu drzewa. Tu odtwarzamy tylko dane skalarne.
static func from_dict(d: Dictionary) -> HitData:
	var h := HitData.new()
	h.base_damage = float(d.get("base_damage", 0.0))
	var tg: Array[StringName] = []
	for t in d.get("tags", []):
		tg.append(StringName(t))
	h.tags = tg
	h.crit_chance = float(d.get("crit_chance", 0.05))
	h.crit_mult = float(d.get("crit_mult", 1.5))
	h.armor_pierce = float(d.get("armor_pierce", 0.0))
	h.lifesteal = float(d.get("lifesteal", 0.0))
	h.knockback = float(d.get("knockback", 6.0))
	h.hit_position = d.get("hit_position", Vector3.ZERO)
	return h
