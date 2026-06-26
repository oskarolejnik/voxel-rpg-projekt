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
#   ORE_COPPER/IRON/GOLD — rudy w skale jaskiń (dosypane NA KOŃCU: bajty 11,12,13; saved
#   PackedByteArray AIR..ROCK_MOSSY bez zmian). Renderowane jak skała z odcieniem minerału.
enum Type { AIR, WATER, SAND, GRASS, DIRT, ROCK, SNOW, WOOD, LEAVES, LEAVES_AUTUMN, ROCK_MOSSY, ORE_COPPER, ORE_IRON, ORE_GOLD }

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
	# --- Rudy jaskiniowe (mineralne plamki w szarej skale ROCK 0.46/0.46/0.50; przygaszone < glow knee) ---
	Type.ORE_COPPER:    Color(0.55, 0.42, 0.30),  # rdzawo-miedziany akcent w skale
	Type.ORE_IRON:      Color(0.52, 0.50, 0.47),  # blady stalowo-szary, ledwie cieplejszy od ROCK (częsty, subtelny)
	Type.ORE_GOLD:      Color(0.74, 0.62, 0.30),  # przygaszone antyczne złoto, zdesaturowane (rzadkie, głębokie)
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
const MUSHROOM_SPOT: Color = Color(0.94, 0.92, 0.86)   # białe kropki muchomora (zbite < glow)
# --- Detaliczne mikro-voxelowe propy (Cube World) ---
const FLOWER_CORE: Color = Color(0.90, 0.78, 0.20)     # żółty środek kwiatu (przygaszony anty-bloom)

# ============================================================================
#  FEEL 3 — PER-BIOM PALETA (Verdant / Emberwaste / Frosthelm jako MIEJSCA)
# ============================================================================
# Problem: get_biome rozróżnia 3 biomy, ale _solid_color malował teren niemal identycznie wszędzie
# (tylko gradient trawy z biome_factor). Biom NIE czytał się z daleka jako inne MIEJSCE.
#
# Rozwiązanie (tanie, deterministyczne, spójne z generacją 2C/Etap4): modulacja KOŻDEGO koloru
# terenu mnożnikiem RGB + przesunięciem nasycenia per biom. Wołane z _solid_color (NEAR: raz na
# widoczny voxel — kolor hoistowany poza pętlę 6 ścian; FAR: per komórka skirta). ID biomu czytane
# z cache kolumny (_biomemap), nie z ponownego próbkowania szumu. Trzymane UMIARKOWANIE — pod
# AGX+glow mocne tinty zlewają się w monochrom; chcemy CZYTELNĄ tożsamość, nie filtr instagramowy.
#
#   Verdant   — neutral/lekko soczysty (baza). Mnożnik ~1, nasycenie +.
#   Emberwaste— ciepły rdzawo-pomarańczowy przesyp + WYSOKI kontrast (sucha, spalona ziemia).
#   Frosthelm — chłodny błękitny przesyp + DESATURACJA (zimna, wyblakła mrozem skała/śnieg).
#
# tint_mul    : mnożnik RGB albedo (barwi cały teren w temat biomu).
# saturate    : >1 podbija nasycenie (Verdant/Ember soczyste), <1 wypłukuje (Frosthelm wyblakły).
const BIOME_VERDANT_TINT: Color = Color(1.00, 1.02, 0.96)   # neutral, ciut cieplejsza zieleń
const BIOME_VERDANT_SAT: float = 1.06
const BIOME_EMBER_TINT: Color = Color(1.16, 0.92, 0.70)     # rdzawo-pomarańczowy przesyp
const BIOME_EMBER_SAT: float = 1.18                          # wysoki kontrast/nasycenie (spiek)
const BIOME_FROST_TINT: Color = Color(0.88, 0.94, 1.05)     # chłodny błękitny przesyp (B zbity 1.10->1.05: review #minor — SNOW.b 0.99 ze starym 1.10 przebijał próg glow w południe na płaskich szczytach śniegu, gdzie biome-tint + value_peak + key light się sumują; 1.05 wciąż czyta zimno, B>R zachowane, margines pod AGX+glow)
const BIOME_FROST_SAT: float = 0.78                          # desaturacja (wyblakły mróz)

## Moduluje kolor terenu wg ID biomu (StringName z VoxelWorld.get_biome). Zwraca NOWY Color.
## Tint = mnożnik RGB; nasycenie liniowo wokół luminancji (sat>1 podbija, <1 wypłukuje). Mnożniki
## clampowane do [0,1] (vertex color sRGB). Nieznany biom -> Verdant (bezpieczny default).
static func biome_modulate(c: Color, biome: StringName) -> Color:
	var tint: Color = BIOME_VERDANT_TINT
	var sat: float = BIOME_VERDANT_SAT
	if biome == &"emberwaste":
		tint = BIOME_EMBER_TINT; sat = BIOME_EMBER_SAT
	elif biome == &"frosthelm":
		tint = BIOME_FROST_TINT; sat = BIOME_FROST_SAT
	var r := c.r * tint.r
	var g := c.g * tint.g
	var b := c.b * tint.b
	# Nasycenie wokół luminancji Rec.601 (sat>1 oddala od szarości, <1 zbliża).
	var luma := r * 0.299 + g * 0.587 + b * 0.114
	r = luma + (r - luma) * sat
	g = luma + (g - luma) * sat
	b = luma + (b - luma) * sat
	return Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0), c.a)


## Czy blok jest „stały” (pełny) z punktu widzenia face cullingu i kolizji.
## WATER traktujemy jak przezroczysty/niestały — nie zasłania ścian i nie ma kolizji.
## Nowe warianty (LEAVES_AUTUMN, ROCK_MOSSY) automatycznie zwracają true.
static func is_solid(t: int) -> bool:
	return t != Type.AIR and t != Type.WATER

## Czy typ to ruda jaskiniowa (renderowana własnym kolorem minerału, BEZ modulacji biomu/trawy).
static func is_ore(t: int) -> bool:
	return t == Type.ORE_COPPER or t == Type.ORE_IRON or t == Type.ORE_GOLD

## Kolor bazowy danego typu (z bezpiecznym fallbackiem na biel, gdyby ktoś podał AIR).
static func color_of(t: int) -> Color:
	return COLORS.get(t, Color(1.0, 1.0, 1.0))
