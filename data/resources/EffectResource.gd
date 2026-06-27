class_name EffectResource
extends Resource
## EffectResource.gd — LOOT Faza 4: EFEKT WYPOSAŻENIA (proc). Wyzwalany w walce, NIE jest StatModifierem
## (StatModifier nie zna triggerów). Definicyjny (referowany przez id z ItemResource.equip_effects /
## SetResource.procs) => ZERO bajtów zapisu, ZERO ryzyka determinizmu. Wykonuje host-only EffectComponent.
##
## Determinizm/co-op: szansa losowana na RNGService.combat WYŁĄCZNIE u hosta (has_state_authority);
## cooldowny żyją w pamięci (nigdy w SaveData). Klient widzi skutek przez replikację HP/statusów.

enum Trigger { ON_HIT, ON_CRIT, ON_KILL, ON_HURT, ON_DASH, ON_EQUIP_AURA }

@export var id: StringName = &""
@export var trigger: Trigger = Trigger.ON_HIT
@export var chance: float = 1.0                      # 0..1 (szansa wyzwolenia na zdarzenie)
@export var cooldown: float = 0.0                    # sekundy między wyzwoleniami (anti-spam)
@export var magnitude: float = 0.0                   # siła (obrażenia/leczenie/DoT per tick)
@export var duration: float = 0.0                    # czas trwania DoT/buffa
@export var radius: float = 0.0                      # promień AoE (frost_nova/earthquake)
# payload: &"burn"/&"poison"/&"bleed"/&"chill"/&"frost"/&"heal"/&"frost_nova"/&"earthquake"/
#          &"multishot"/&"dash_charge"/&"aura_crit"/&"shield"
@export var payload: StringName = &""
@export var tags: Array[StringName] = []


func to_dict() -> Dictionary:
	return {
		"id": String(id), "trigger": int(trigger), "chance": chance, "cooldown": cooldown,
		"magnitude": magnitude, "duration": duration, "radius": radius, "payload": String(payload),
	}


static func from_dict(d: Dictionary) -> EffectResource:
	var e := EffectResource.new()
	e.id = StringName(d.get("id", ""))
	e.trigger = int(d.get("trigger", Trigger.ON_HIT))
	e.chance = float(d.get("chance", 1.0))
	e.cooldown = float(d.get("cooldown", 0.0))
	e.magnitude = float(d.get("magnitude", 0.0))
	e.duration = float(d.get("duration", 0.0))
	e.radius = float(d.get("radius", 0.0))
	e.payload = StringName(d.get("payload", ""))
	return e
