class_name AugmentResource
extends Resource
## AugmentResource.gd — wstawka modyfikujaca KONKRETNY skill (loot). TDD 2.3.
## Augmenty dzialaja lokalnie na skill (przed pipeline'em obrazen), NIE wchodza do
## globalnej puli StatsComponent (TDD 3.2). Etap 0: tylko schemat.

@export var id: StringName = &""
@export var display_name: String = ""
@export var modifiers: Array[StatModifier] = []      # modyfikatory tego skilla
@export var added_tags: Array[StringName] = []       # moze dodac tag (np. &"zone")
@export var effect_id: StringName = &""              # specjalny efekt (rozszczepienie, kaluza...)
