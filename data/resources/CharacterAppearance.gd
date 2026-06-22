class_name CharacterAppearance
extends Resource
## CharacterAppearance.gd — parametry wygladu postaci voxelowej (TDD 2.5).
## limb_proportions: P_* z Player.gd (np. P_SHOULDER_W...). Etap 0: schemat + (de)serializacja
## uzywana przez SaveData/SaveManager (round-trip postaci).

@export var class_id: StringName = &""
@export var body_color: Color = Color(0.8, 0.7, 0.6, 1.0)
@export var height_scale: float = 1.0
@export var limb_proportions: Dictionary = {}        # P_* z Player.gd


func to_dict() -> Dictionary:
	return {
		"class_id": String(class_id),
		"body_color": [body_color.r, body_color.g, body_color.b, body_color.a],
		"height_scale": height_scale,
		"limb_proportions": limb_proportions,
	}


static func from_dict(d: Dictionary) -> CharacterAppearance:
	var a := CharacterAppearance.new()
	a.class_id = StringName(d.get("class_id", ""))
	var c: Array = d.get("body_color", [0.8, 0.7, 0.6, 1.0])
	if c.size() >= 4:
		a.body_color = Color(c[0], c[1], c[2], c[3])
	a.height_scale = float(d.get("height_scale", 1.0))
	a.limb_proportions = d.get("limb_proportions", {})
	return a
