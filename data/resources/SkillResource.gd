class_name SkillResource
extends Resource
## SkillResource.gd — definicja skilla (TDD 2.3). Etap 0: tylko schemat danych.

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D
@export var class_path: StringName = &""             # do ktorej sciezki (podklasy) nalezy
@export var cost_resource: StringName = &""          # &"mana"/&"rage"/&"combo"/&"focus"/&"stamina"
@export var cost_amount: float = 0.0
@export var cooldown: float = 0.0
@export var cast_time: float = 0.0
@export var damage_mult: float = 1.0

# --- FAZA 1 (FEEL): ATTACK TIMELINE (anticipation -> active -> recovery) ---
# Czasy faz ataku (s). Hitbox otwiera sie DOPIERO po `anticipation` (NIE w klatce 0), zyje przez
# `active`, potem `recovery` jest CANCELABLE (w unik zawsze, w nastepny cios w oknie combo). Encja
# (Player/AbilityComponent) czyta te wartosci, by sterowac oknem hitboxa i cancelami. 0/0/0 =
# zachowanie sprzed Fazy 1 (otwarcie natychmiast, brak faz) — bezpieczny default dla starych skilli.
@export var anticipation: float = 0.0                # wind-up: hitbox JESZCZE zamkniety (model cofa rece)
@export var active: float = 0.0                      # okno aktywnych klatek (hitbox otwarty)
@export var recovery: float = 0.0                    # po active: cancelable (unik / nastepny cios)
@export var cancel_window: float = 0.0               # s w recovery, w ktorych mozna wejsc w nastepny cios
@export var tags: Array[StringName] = []             # tagi skilla (synergia z lootem)
@export var max_augments: int = 3                    # gniazda augmentow (0..3)
@export var scene: PackedScene                       # pocisk/AoE/strefa do zespawnowania
@export var passive_modifiers: Array[StatModifier] = []   # gdy skill wpiety

# --- FAZA 4 (3) ABILITY AURY: wizual kastowania/uzycia skilla (czysto kosmetyczny) ---
# aura_kind sterowane danymi: &"" = brak aury (stare skille bez zmian), &"ring" = rosnacy pierscien
# (np. Wir Ostrzy), &"slam" = uderzenie w ziemie (iskra+puls+fala, np. Roztrzaskanie), &"cast" = puls
# u stop. Encja (Player) czyta te pola i wola FeelFX.spawn_ability_aura w fazie ACTIVE skilla.
@export var aura_kind: StringName = &""
@export var aura_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var aura_radius: float = 2.0


## Czy skill ma zdefiniowany timeline (jakakolwiek faza > 0). Gdy false -> stara sciezka:
## skill wykonuje sie natychmiast (perform_skill od razu), bez maszyny faz w AbilityComponent.
func has_timeline() -> bool:
	return anticipation > 0.0 or active > 0.0 or recovery > 0.0
