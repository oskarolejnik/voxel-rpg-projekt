shader_type canvas_item;
// Winieta — delikatne przyciemnienie krawędzi ekranu (Faza 0B). Pełnoekranowy ColorRect.
uniform float strength : hint_range(0.0, 1.0) = 0.32;
uniform float inner : hint_range(0.0, 1.0) = 0.32;
uniform float outer : hint_range(0.0, 1.2) = 0.78;

void fragment() {
	float d = distance(UV, vec2(0.5));
	float vig = smoothstep(inner, outer, d);
	COLOR = vec4(0.0, 0.0, 0.0, vig * strength);
}
