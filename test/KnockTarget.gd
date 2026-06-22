extends CharacterBody3D
## KnockTarget.gd — atrapa celu na potrzeby Etap1Test (test przekazania HitData.knockback).
## Ma HealthComponent (HP liczy komponent), a take_damage służy TYLKO do odebrania siły odrzutu,
## którą DamageService przekazuje z HitData (FX-only call: take_damage(0, from, knockback)).

var armor: float = 0.0
var last_knockback: float = -999.0

func take_damage(_amount: float, _from: Node = null, knockback: float = -1.0) -> void:
	last_knockback = knockback
