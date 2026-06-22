extends Node3D
## AIHost.gd — atrapa "ciała" dla testu AIComponent (Etap1Test). Implementuje kontrakt ai_*,
## którego AIComponent używa w tick(). Pozwala sprawdzić wybór stanu (IDLE->CHASE) i sterowanie
## ciałem (ai_move_towards) bez uruchamiania całego Enemy.

var ai_target: Node3D = null
var move_called: bool = false
var last_move_point: Vector3 = Vector3.ZERO
var facing: Vector3 = Vector3.ZERO
var attacked: bool = false

func ai_get_position() -> Vector3:
	return global_position

func ai_get_target() -> Node3D:
	return ai_target if (ai_target != null and is_instance_valid(ai_target)) else null

func ai_move_towards(point: Vector3, _spd: float) -> void:
	move_called = true
	last_move_point = point

func ai_stop() -> void:
	pass

func ai_face(dir: Vector3) -> void:
	facing = dir

func ai_can_attack() -> bool:
	return true

func ai_attack(_target: Node3D) -> void:
	attacked = true
