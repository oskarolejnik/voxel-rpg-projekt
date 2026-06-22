class_name Blocks
extends RefCounted
## Blocks.gd — definicje typów bloków: enum, kolory (vertex colors) i pomocnicze.
##
## Trzymamy to w osobnym pliku z `class_name`, żeby z każdego miejsca w projekcie
## odwoływać się przez `Blocks.Type.GRASS` / `Blocks.COLORS` / `Blocks.is_solid(...)`.
## To czysta klasa danych (RefCounted) — nie tworzymy jej instancji w drzewie sceny.

# Typy bloków. 0 = AIR (powietrze). Mieszczą się w bajcie (PackedByteArray) bez problemu.
# WOOD i LEAVES dodane wcześniej NA KOŃCU enuma — wartości bajtowe nie zmieniły się.
# Styl Cube World: dokładamy NA SAMYM KOŃCU warianty liści/skały, by zachować
# zgodność bajtów wstecz (AIR=0..LEAVES=8 bez zmian; nowe = 9,10).
#   LEAVES_AUTUMN — jesienne, ciepłe drzewa (~10% lasu)
#   ROCK_MOSSY    — głazy z porostem (~20% kamieni)
enum Type { AIR, WATER, SAND, GRASS, DIRT, ROCK, SNOW, WOOD, LEAVES, LEAVES_AUTUMN, ROCK_MOSSY }

# Bazowe kolory bloków. Albedo bierzemy z koloru wierzchołka (vertex_color_use_as_albedo),
# więc tu definiujemy „bazę”, a drobne wariacje (mikro-szum, pseudo-AO) dokładamy przy meshowaniu.
# UWAGA: materiał ma vertex_color_is_srgb=true, więc kolory dobieramy jak sRGB.
#
# Paleta „Cube World”: barwy bardziej nasycone i czyste niż Minecraft, mocniejsze
# rozróżnienie biomów, ale złamane pod nasz pipeline (ACES exposure 0.8 + white 6.0,
# glow 0.2/bloom 0.05, mikro-tint ±0.055, AO ×0.6). Biele/żółcie celowo zbite,
# żeby glow ich nie wypalił. DIRT/ROCK celowo stonowane (odpoczynek dla oka).
# Typ Dictionary jawnie (review #minor: spójność z resztą typowanych const w pliku).
const COLORS: Dictionary = {
	Type.WATER:  Color(0.10, 0.46, 0.62),  # głębszy turkus-lazur, tropikalny zamiast szarego stawu
	Type.SAND:   Color(0.85, 0.77, 0.54),  # cieplejszy, lekko bardziej żółty piasek
	Type.GRASS:  Color(0.36, 0.62, 0.26),  # soczysta, żółto-zielona trawa (Cube World vibe)
	Type.DIRT:   Color(0.45, 0.31, 0.19),  # cieplejsza, bardziej czerwona ziemia (kontrast z trawą)
	Type.ROCK:   Color(0.46, 0.46, 0.50),  # chłodny szary z nutą błękitu (nie martwy neutral)
	Type.SNOW:   Color(0.90, 0.93, 0.99),  # zbity z 0.92, by glow nie wypalił bieli do flara
	Type.WOOD:   Color(0.40, 0.27, 0.16),  # pień: ciepły orzech, czerwieńszy/jaśniejszy niż ROCK
	Type.LEAVES: Color(0.22, 0.46, 0.20),  # liście: nasycona, chłodniejsza zieleń (ciemniejsza od GRASS)
	# --- Warianty propów (Cube World) ---
	Type.LEAVES_AUTUMN: Color(0.62, 0.36, 0.12),  # jesienne liście — ciepły bursztyn/miedź
	Type.ROCK_MOSSY:    Color(0.36, 0.42, 0.34),  # głaz z porostem — szarozielony
}

# --- Kolory kotwiczne gradientu trawy (nizina -> wyżyna). Cube World mocno różnicuje
# trawę z wysokością. Interpolacja w Chunk._solid_color między BEACH_MAX_Y a ROCK_MIN_Y.
const GRASS_LOW:  Color = Color(0.42, 0.64, 0.24)   # nizina: cieplejsza, jaśniejsza łąka
const GRASS_HIGH: Color = Color(0.30, 0.52, 0.30)   # wyżyna: chłodniejsza, ciemniejsza zieleń górska
# Regionalne warianty łąki (Faza 2C) — biom koloru ze szumu, by świat nie był „jedną zielenią".
const GRASS_DRY:  Color = Color(0.60, 0.58, 0.26)   # region ciepły/suchy: żółto-zielona łąka
const GRASS_COOL: Color = Color(0.22, 0.54, 0.34)   # region wilgotny: bujna, chłodniejsza zieleń

# --- Akcenty kolorystyczne drobnych propów (trawa/kwiaty/grzyby — osobny mesh, nie _voxels).
# Nasycone, ale nie neonowe — pod ACES+glow małe voxele i tak „świecą”.
# Const-tablice MUSZĄ być typowane (inaczej „Cannot infer type”).
const PROP_GRASS_TUFT: Color = Color(0.30, 0.52, 0.22)  # zieleń runa (źdźbła)
const PROP_FLOWER_STEM: Color = Color(0.28, 0.45, 0.20)  # łodyga kwiatka
const FLOWER_COLORS: Array[Color] = [
	Color(0.82, 0.20, 0.20),  # mak / czerwony
	Color(0.86, 0.74, 0.22),  # mlecz / żółty — przygaszony (review #minor: anty-bloom-flicker na mini-quadach)
	Color(0.86, 0.86, 0.80),  # stokrotka — kremowa, zbita poniżej progu glow
	Color(0.55, 0.34, 0.72),  # lawenda / fiolet — chłodny kontrapunkt dla zieleni
	Color(0.28, 0.45, 0.80),  # chaber / błękit
]
const MUSHROOM_STEM: Color = Color(0.86, 0.82, 0.72)   # trzonek grzyba — kremowy
const MUSHROOM_RED:  Color = Color(0.75, 0.18, 0.16)   # czerwony kapelusz (muchomor)
const MUSHROOM_BROWN: Color = Color(0.52, 0.38, 0.24)  # brązowy grzyb — cieplejszy niż DIRT

## Czy blok jest „stały” (pełny) z punktu widzenia face cullingu i kolizji.
## WATER traktujemy jak przezroczysty/niestały — nie zasłania ścian i nie ma kolizji.
## Nowe warianty (LEAVES_AUTUMN, ROCK_MOSSY) automatycznie zwracają true.
static func is_solid(t: int) -> bool:
	return t != Type.AIR and t != Type.WATER

## Kolor bazowy danego typu (z bezpiecznym fallbackiem na biel, gdyby ktoś podał AIR).
static func color_of(t: int) -> Color:
	return COLORS.get(t, Color(1.0, 1.0, 1.0))
