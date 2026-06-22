extends Node
## RNGService.gd (autoload) — deterministyczny RNG (TDD 1.3 + nota integracyjna).
##
## Strumienie: `world` / `loot` / `combat` wyprowadzone z JEDNEGO seeda sesji.
## KRYTYCZNA INTEGRACJA: swiat MA juz wlasny deterministyczny seed w VoxelWorld
## (FEATURE_SEED + feature_hash + _noise.seed=1337). RNGService NIE duplikuje generacji
## terenu — `world` dostarcza TYLKO wspolny seed/strumien, a VoxelWorld dalej generuje teren
## swoim feature_hash. Domyslny seed sesji bazuje na VoxelWorld.FEATURE_SEED, by oba zrodla
## startowaly z tej samej "prawdy" (jedno zrodlo seeda). loot/combat sa NIEZALEZNE od terenu.
##
## UWAGA DETERMINIZM (kontrakt Etap 7): combat/loot to GLOBALNE, sekwencyjne strumienie — ten sam
## seed daje te sama sekwencje TYLKO przy identycznej kolejnosci i liczbie pobran. W co-opie
## pobierane WYLACZNIE po stronie autorytetu (NetManager.is_host / has_authority), nigdy w sciezce
## predykcji/FX klienta. Seedy trzymac < 2^53 (JSON double) — Etap 0 i tak uzywa <= 32-bit.

## Stale przesuniecia strumieni (rozdzielenie sekwencji jak `salt` w feature_hash).
const STREAM_WORLD: int = 0x1111
const STREAM_LOOT: int = 0x2222
const STREAM_COMBAT: int = 0x3333

var session_seed: int = 0

var world: RandomNumberGenerator = RandomNumberGenerator.new()
var loot: RandomNumberGenerator = RandomNumberGenerator.new()
var combat: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	# Domyslny seed sesji = VoxelWorld.FEATURE_SEED (jedno zrodlo prawdy z istniejacym swiatem).
	# class_name VoxelWorld jest globalnie dostepny (skrypt z class_name), wiec stala czytamy wprost.
	seed_session(VoxelWorld.FEATURE_SEED)


## Ustawia seed CALEJ sesji i wyprowadza z niego trzy niezalezne strumienie.
## Determinizm: ten sam session_seed -> identyczne sekwencje loot/combat na hoscie i kliencie
## (TDD 6.2: brak desyncu lootu). `world`-seed oddajemy do VoxelWorld przez world_seed().
func seed_session(p_seed: int) -> void:
	session_seed = p_seed
	world.seed = p_seed ^ STREAM_WORLD
	loot.seed = p_seed ^ STREAM_LOOT
	combat.seed = p_seed ^ STREAM_COMBAT


## Seed do przekazania VoxelWorld/DungeonGen (jedno zrodlo seeda, NIE duplikat generacji).
## VoxelWorld nadal liczy teren swoim feature_hash — to tylko wspolny punkt startowy.
func world_seed() -> int:
	return session_seed


## Reset wszystkich strumieni do biezacego session_seed (np. nowa runa dungeonu z entrance_seed
## w Etapie 5: seed_session(entrance_seed); reszta kodu bez zmian).
func reset_streams() -> void:
	seed_session(session_seed)
