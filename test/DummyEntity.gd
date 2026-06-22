extends CharacterBody3D
## DummyEntity.gd — atrapa celu na potrzeby Etap1Test (HEADLESS). NIE używana w grze.
## Niesie pole `armor` (kontrakt DamageService: czyta "armor" 0..1). Obrażenia rozwiązuje
## HealthComponent (sibling), więc nie potrzebuje własnego take_damage.

var armor: float = 0.0
