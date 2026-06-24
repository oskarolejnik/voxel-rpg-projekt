## Redesign skill progression (Core + Advanced, statusy, synergy)

> Rozdział GDD świata — warstwa progresji umiejętności. Reużywa istniejącego silnika:
> `SkillResource` / `SkillTreeResource` / `PassiveNodeResource` / `SkillTreeComponent` /
> `LevelComponent` / `AbilityComponent` / `StatsComponent` / `StatModifier` / `DamageService` /
> `SkillDB` / `ContentDB`. **Zero przepisywania rdzenia** — rozszerzamy o nowe pola danych i nowy
> komponent statusów. Wszystkie liczby gotowe do wpisania w `.tres`.

---

### 1. Cel i pętla mocy

Leveling ma dawać **odczuwalne skoki mocy** (real power spikes), a nie liniowy +1% co poziom.
Pętla: `kill -> XP -> level up -> punkt -> węzeł CORE -> nowy skill/spec -> nowy combo -> mocniejszy
build -> dalszy biom`. Spójność ze światem (rozdz. 02): biomy w pierścieniach dystansu dostarczają
przeciwników z konkretnymi typami obrażeń/odpornościami — buildy statusowe (freeze w Snow, burn w
Volcanic, poison w Swamp) mają tam mieć sens lub karę.

Każda z **11 klas** (kanon `ContentDB._seed`: wojownik, paladyn, berserker, lucznik, lotrzyk,
zabojca, mag, nekromanta, kaplan, druid, mnich) dostaje **jedną** `SkillTreeResource` o tej samej
strukturze szkieletowej:

- **CORE TREE** — 4 gałęzie: **Offense / Defense / Utility / Mobility**. Dostępne od lvl 1.
- **ADVANCED TREE** — 2 gałęzie specjalizacji: **Spec A / Spec B**. Odblokowywane od lvl 25
  (keystone wyboru spec), pełnia od lvl 60 (capstone/ultimate).

---

### 2. Taksonomia węzłów i skilli

Mapowanie na istniejące typy zasobów:

| Kategoria | Nośnik danych | Pole/typ | Uwagi |
|---|---|---|---|
| **Pasyw** | `PassiveNodeResource.modifiers` | `Array[StatModifier]` (FLAT/INCREASED/MORE) | wpina się przez provider `SkillTreeComponent.collect_modifiers()` |
| **Notable** | `PassiveNodeResource` + `is_keystone=false`, `min_level` próg | mocniejszy pasyw, 1 punkt | "węzeł smaku" gałęzi |
| **Keystone** | `PassiveNodeResource.is_keystone=true`, `min_level=25` | zmienia regułę gry, często trade-off | brama do Spec A/B |
| **Aktywny skill** | `PassiveNodeResource.grants_skill` -> `SkillResource` | węzeł nadaje skill na pasek | spawn/hitbox wg `SkillResource.scene` + timeline |
| **ULTIMATE** | `SkillResource` z `tags=[&"ultimate"]`, `min_level` capstone=60 | **1 per spec** (2 na klasę) | długi CD, duży `damage_mult`, własna aura |
| **Movement skill** | `SkillResource` z `tags=[&"movement"]` | dash/skok/teleport | cancel-into z `AbilityComponent.cancel()` |
| **Defensive skill** | `SkillResource` z `tags=[&"defensive"]` | block/bariera/unik-i-frame | i-frames z timeline `anticipation`/`active` |
| **Utility skill** | `SkillResource` z `tags=[&"utility"]` | pułapka/aura/totem/oil | często enabler combo |

**Każda klasa dostaje** (minimum): 1 movement, 1 defensive, 1 utility w CORE + 2 ultimate w ADVANCED
(po jednym na spec).

---

### 3. Rozszerzenia techniczne istniejących zasobów

Wszystko jako **nowe `@export` z bezpiecznym defaultem** (stare `.tres` działają bez zmian).

#### 3.1 `PassiveNodeResource.gd` (dodać pola)

```gdscript
@export var layer: StringName = &"core"        # &"core" | &"advanced"
@export var branch: StringName = &""           # &"offense"|&"defense"|&"utility"|&"mobility"|&"spec_a"|&"spec_b"
@export var rank_max: int = 1                   # ile razy można dobrać (skalowalne pasywy 1..N)
@export var grants_status_apply: Array[StatusApplyResource] = []  # węzeł nadaje on-hit status (sek.5)
@export var spec_lock: StringName = &""         # jeśli != "" -> wziąć tylko gdy aktywna ta spec (A/B)
```

`rank_max>1`: `SkillTreeComponent.allocate()` zezwala na wielokrotną alokację, `collect_modifiers()`
mnoży `value*rank`. Wymaga drobnej zmiany `_allocated: Dictionary` z `bool` na `int` (liczba ranków).

#### 3.2 `SkillTreeResource.gd` (dodać metadane warstw)

```gdscript
@export var core_branches: Array[StringName] = [&"offense", &"defense", &"utility", &"mobility"]
@export var advanced_branches: Array[StringName] = [&"spec_a", &"spec_b"]
@export var advanced_unlock_level: int = 25     # próg odblokowania ADVANCED
@export var spec_choice_exclusive: bool = false # true -> wybór A LUB B (hard spec); false -> oba dostępne wolniej
@export var resource_kind: StringName = &""     # &"rage"/&"mana"/&"combo"/&"focus"... (z ClassResource.resource_kind)
```

#### 3.3 `SkillResource.gd` (dodać)

```gdscript
@export var category: StringName = &"active"    # active|ultimate|movement|defensive|utility
@export var status_on_hit: Array[StatusApplyResource] = []  # statusy nakładane przy trafieniu
@export var combo_consumes: StringName = &""    # np. &"oil"/&"freeze" — zużywa status celu na bonus
@export var combo_bonus_mult: float = 1.0       # mnożnik dmg gdy combo_consumes spełnione
@export var iframe_window: float = 0.0          # s nietykalności w fazie active (defensive/dash)
```

#### 3.4 `SkillTreeComponent.gd` (rozszerzyć walidację)

- `cannot_allocate_reason()` dokłada: `layer==&"advanced"` wymaga `lvl >= tree.advanced_unlock_level`;
  jeśli `spec_choice_exclusive` i wzięto już węzeł z `spec_a`, blokuj `spec_b` (i odwrotnie) — chyba że
  pełny respec.
- `grants_skill` -> przy alokacji woła `entity.grant_skill(node.grants_skill)` (encja podpina na pasek;
  `AbilityComponent.try_use` reszta bez zmian).
- `grants_status_apply` -> rejestruje on-hit u `StatusComponent` (sek. 5) po `source_id=node.id`.

#### 3.5 `LevelComponent.gd` (power-spike granty)

Obecnie: +1 punkt/level, +1 power-point co 5 lvl. **Dokładamy bramki progowe** (bez zmiany krzywej XP):

| Próg | Co dostaje gracz |
|---|---|
| lvl 1 | 1. aktywny CORE skill (z `ClassResource.skill_hints[0]`), movement skill |
| lvl 5 | +1 power-point; odblokowanie **defensive skill** |
| lvl 10 | utility skill; pierwszy notable osiągalny |
| lvl 15 | drugi aktywny CORE; +1 power-point |
| lvl 20 | trzeci aktywny CORE (`skill_hints[2]`) |
| **lvl 25** | **WYBÓR SPECJALIZACJI** (keystone spec_a/spec_b) — duży skok |
| lvl 30/35/40 | notable w wybranej spec, +power-pointy co 5 |
| **lvl 60** | **ULTIMATE** danej spec (capstone) — drugi duży skok |
| lvl 75/90 | drugi keystone spec / cross-spec notable |
| lvl 99 | cap; pełna alokacja ~98 pkt + ~19 power-point |

Implementacja: `_grant_points_for_level(lvl)` emituje dodatkowy sygnał `milestone_reached(lvl, kind)`
przy lvl ∈ {1,5,10,15,20,25,60}, encja wtedy `grant_skill`/otwiera UI spec. Krzywa XP i cap 99
**bez zmian**.

---

### 4. Pipeline statów a skille (spójność z TDD 3.1)

Węzły piszą wyłącznie `StatModifier` w kanonie `FLAT / INCREASED / MORE`:

```
final = (base + Σ FLAT) * (1 + Σ INCREASED) * Π(1 + MORE)
```

Reguły projektowe (by uniknąć inflacji):
- **FLAT** — tylko wczesne CORE (np. `+8 damage`, `+40 max_hp`).
- **INCREASED %** — większość węzłów skalowalnych (`+12% increased fire_damage`), sumują się — tanie,
  liniowe, podstawa buildu.
- **MORE %** — rzadkie, **tylko keystone/ultimate/spec capstone** (`x1.30 more damage gdy cel pali`).
  Multiplikatywne = źródło prawdziwych power-spike’ów. Max 2-3 źródła MORE na build.

Tagi `StatModifier.tags` (np. `&"fire"`, `&"melee"`, `&"bleed"`, `&"crit"`) pozwalają węzłom celować
w konkretny typ — synergia z lootem (afiksy o tych samych tagach się sumują w INCREASED).

Zasoby klas (`ClassResource.resource_kind`): rage/faith/combo/focus/mana/essence/nature/chi —
węzły mogą modyfikować staty zasobu kluczami `&"<res>_max"`, `&"<res>_regen"`, `&"<res>_on_hit"`.

---

### 5. STATUS EFFECTS — nowy `StatusComponent` (komponent) + `StatusApplyResource` (dane)

`DamageService._resolve()` ma już hook **pkt 6** (`on_hit_effects` — obecnie no-op). Aktywujemy go:
po `hit_resolved` wołamy `StatusComponent.apply()` na celu. Status = data (`StatusApplyResource`) +
runtime stack na celu. Tick co 0.5 s w `_process` (zgodnie z budżetem RTX 3050 — pooling, brak
per-frame).

#### 5.1 Tabela statusów (mechanika liczbowo)

| Status | Typ | Czas | Tick | Obrażenia/efekt na tick | Stack | Max stack | Interakcje |
|---|---|---|---|---|---|---|---|
| **bleed** (krwawienie) | DoT fizyczny | 6 s | 0.5 s | 4% atk dmg / tick | dodaje czas + intensywność | 5 | nasila się przy ruchu celu (+50% tick gdy się porusza); `execute` poniżej 20% HP |
| **poison** (trucizna) | DoT chaos, ignoruje pancerz | 8 s | 0.5 s | 3% atk dmg / tick | osobne instancje (każda swój timer) | 8 | nie redukowany przez `armor`; synergia z `weaken` (x1.25 tick) |
| **burn** (ogień) | DoT ognisty | 4 s | 0.5 s | 5% atk dmg / tick | odświeża czas, intensywność max 3 | 3 | `+oil` -> x2 dmg i +czas; podpala olej/gaz w jaskini |
| **freeze** (zamrożenie) | hard CC | 2 s | — | brak ruchu i akcji | nie stackuje (odświeża) | 1 | po wyjściu **shatter**: dmg = 15% max_hp celu jeśli rozbity bronią; chill (slow 30%) jako stan przejściowy |
| **stun** (ogłuszenie) | hard CC | 1.2 s | — | brak akcji (może spaść) | DR: każdy kolejny stun w 6 s -50% czasu | 1 | przerywa cast wroga; immunity 4 s po pełnym stunie (anty-permastun) |
| **weaken** (osłabienie) | debuff | 5 s | — | cel zadaje -20% dmg, otrzymuje +15% dmg | odświeża, intensywność max 2 (-30%/+25%) | 2 | mnoży dmg wszystkich źródeł — enabler dla DoT i burst |

Liczby skalują się od `atk dmg` źródła w momencie nałożenia (snapshot), żeby DoT nie był zależny od
późniejszych buffów (determinizm host-authoritative, brak desyncu — zgodnie z DamageService).

#### 5.2 `StatusApplyResource.gd` (nowy zasób danych)

```gdscript
class_name StatusApplyResource
extends Resource
@export var status: StringName = &""        # &"bleed"|&"poison"|&"burn"|&"freeze"|&"stun"|&"weaken"
@export var chance: float = 1.0             # 0..1 szansa nałożenia
@export var duration: float = 6.0
@export var tick: float = 0.5
@export var magnitude: float = 0.04         # % atk dmg / tick LUB % efektu
@export var max_stacks: int = 1
@export var tags: Array[StringName] = []
```

#### 5.3 `StatusComponent.gd` (nowy komponent)

- `apply(src_dmg: float, def: StatusApplyResource)` — rzut na `chance`, dodaj/odśwież stack.
- `_process(delta)` — akumuluj do `tick`; per tick: DoT -> `DamageService.request_hit(src=null,
  self, HitData(base_damage=snapshot*magnitude, tags=[status]))` (centralne liczenie odporności).
- hard CC (`freeze`/`stun`) -> ustawia flagę w `AIComponent`/Player input (blokada akcji), emituje
  `status_changed` (HUD/FX).
- `has_status(s)`, `consume_status(s)` — używane przez combo (`SkillResource.combo_consumes`).
- Provider `StatsComponent`: `weaken` wpina `StatModifier` (`damage` INCREASED -20%, `taken` +15%)
  po `source=&"status"`, `source_id=&"weaken"` — auto-zdejmowane po wygaśnięciu (`remove_modifiers_by_source`).

---

### 6. COMBO / SYNERGY — konkretne przykłady

**Combo (status -> finisher), liczbowo:**

| Combo | Setup | Finisher | Efekt |
|---|---|---|---|
| **freeze -> shatter** | freeze celu (Lodowy grot/keystone) | dowolny cios bronią | `shatter`: +15% max_hp celu jako dmg, AoE 3 m do sąsiadów |
| **burn + oil** | utility `Olej` (status `oil`) na cel/teren | burn (Ognista kula) | burn tick **x2** i +2 s; podpala kałużę oleju (strefa 4 m) |
| **bleed + execute** | 3+ stacki bleed | skill z tagiem `&"execute"` poniżej 25% HP | natychmiastowa egzekucja (dmg = pozostałe HP), zwrot zasobu |
| **poison + weaken** | poison na cel | weaken | tick poison x1.25, ignoruje pancerz — anty-tank/anty-elite |
| **stun -> burst** | stun (Roztrzaskanie/Fala chi) | nuke w oknie stunu | crit guaranteed w pierwszych 0.4 s stunu |

**Synergia między węzłami (pasywy mnożą się przez tagi/MORE):**

- *"Każdy stack bleed na celu: +6% increased damage Twoich ataków przeciw niemu"* (notable Offense) +
  *"Bleed nakłada się o 1 stack więcej (max 6)"* (notable) -> skaluje DoT-build liniowo, a keystone
  *"Cele krwawiące: x1.25 more damage"* daje power-spike multiplikatywny.
- *"Freeze trwa +0.5 s"* + *"Shatter zadaje +50%"* + keystone *"Twoje obrażenia ognia ROZBIJAJĄ
  zamrożenie zamiast je zdejmować"* -> cross-element fire+ice burst.
- *"Weaken aplikuje się przy każdym ulti"* + *"Cele osłabione: x1.3 more crit damage"* -> burst-spec.

---

### 7. Wzorcowa pełna klasa: **Berserker** (`class_id = &"berserker"`, zasób `rage`)

Baza (z `ContentDB`): `hp 120, dmg 20, armor 0.1`, broń: topór dwuręczny, hinty: Szał / Wir Ostrzy /
Rozłup. Spec A = **Krwawy Szał** (bleed/lifesteal/sustained), Spec B = **Burza Ostrzy** (AoE/freeze-shatter/burst).

#### 7.1 CORE — Offense (`branch=&"offense"`, layer=&"core"`)

| id | display | min_lvl | rank_max | koszt | modifiers (op) | grants_skill / status |
|---|---|---|---|---|---|---|
| `brsk_off_1` | Ostrze Furii | 1 | 3 | 1 | `damage` INCREASED +10% (tag melee) | — |
| `brsk_off_2` | Głęboka Rana | 5 | 3 | 1 | `bleed_magnitude` INCREASED +15% | nadaje on-hit bleed 1 stack (`StatusApplyResource` chance 0.4) |
| `brsk_off_3` | Krwiożerczość (notable) | 10 | 1 | 1 | `crit_chance` FLAT +8% (tag bleed) | — |
| `brsk_off_4` | Topór Spustoszenia | 15 | 1 | 1 | — | grants_skill `&"rozlup"` (AoE cleave) |
| `brsk_off_5` | Furia Rośnie (notable) | 20 | 1 | 1 | `damage` INCREASED +6% per 25 rage (warunkowe) | — |

#### 7.2 CORE — Defense

| id | display | min_lvl | rank_max | koszt | modifiers |
|---|---|---|---|---|---|
| `brsk_def_1` | Twarda Skóra | 1 | 3 | 1 | `max_hp` FLAT +40 |
| `brsk_def_2` | Zacietość | 5 | 1 | 1 | grants_skill `&"krzyk_bojowy"` (defensive: -20% taken 4 s) |
| `brsk_def_3` | Drugi Oddech (notable) | 10 | 1 | 1 | `lifesteal` FLAT +5% (tag bleed) |
| `brsk_def_4` | Niezłomny (notable) | 20 | 1 | 1 | `max_hp` INCREASED +15% |

#### 7.3 CORE — Utility

| id | display | min_lvl | koszt | modifiers / grants |
|---|---|---|---|---|
| `brsk_uti_1` | Zew Krwi | 5 | 1 | `rage_on_hit` FLAT +4 |
| `brsk_uti_2` | Prowokacja | 10 | 1 | grants_skill `&"prowokacja"` (utility: taunt + weaken AoE) |
| `brsk_uti_3` | Niegasnąca Furia (notable) | 15 | 1 | `rage_decay` INCREASED -30% |

#### 7.4 CORE — Mobility

| id | display | min_lvl | koszt | grants / modifiers |
|---|---|---|---|---|
| `brsk_mob_1` | Szarża | 1 | 1 | grants_skill `&"szarza"` (movement: dash 6 m, `iframe_window 0.2`) |
| `brsk_mob_2` | Pęd Bitewny (notable) | 10 | 1 | `move_speed` INCREASED +12% po zabiciu (5 s) |
| `brsk_mob_3` | Szarża+ | 15 | 1 | `szarza` cooldown INCREASED -25%; szarża nakłada stun 0.6 s |

#### 7.5 ADVANCED — Spec A: Krwawy Szał (`branch=&"spec_a"`, advanced, unlock 25)

| id | display | min_lvl | is_keystone | koszt | efekt |
|---|---|---|---|---|---|
| `brsk_a_key` | **Pakt Krwi** (keystone) | 25 | true | 1 | Twoje ataki zawsze nakładają bleed; cele krwawiące: **x1.25 MORE damage**; tracisz 2% HP/s |
| `brsk_a_1` | Żniwo | 30 | false | 1 | `bleed` może mieć 6 stacków; każdy stack +4% lifesteal |
| `brsk_a_2` | Egzekucja (notable) | 40 | false | 1 | skill `rozlup` zyskuje tag `&"execute"` (combo bleed+execute <25% HP) |
| `brsk_a_ult` | **ULTIMATE: Krwawa Łaźnia** | 60 | true | 1 | grants_skill `&"krwawa_laznia"`: AoE, zużywa wszystkie stacki bleed wrogów w 6 m -> dmg = Σ pozostałego bleed x2, leczy 40% zadanego (CD 60 s, `tags=[&"ultimate"]`) |

#### 7.6 ADVANCED — Spec B: Burza Ostrzy (`branch=&"spec_b"`)

| id | display | min_lvl | is_keystone | koszt | efekt |
|---|---|---|---|---|---|
| `brsk_b_key` | **Wir Nieustający** (keystone) | 25 | true | 1 | grants_skill `&"wir_ostrzy"` (kanałowane AoE); podczas wiru: x1.2 MORE AoE dmg, brak regenu rage |
| `brsk_b_1` | Mroźne Ostrze | 30 | false | 1 | ataki AoE nakładają chill; krytyk na schłodzonym -> freeze 1.5 s |
| `brsk_b_2` | Roztrzaskanie (notable) | 40 | false | 1 | combo freeze->shatter +50% (synergia z Mroźnym Ostrzem) |
| `brsk_b_ult` | **ULTIMATE: Tornado Stali** | 60 | true | 1 | grants_skill `&"tornado_stali"`: wir 8 m, wciąga wrogów, shatteruje wszystkie zamrożone (CD 75 s, `tags=[&"ultimate"]`) |

#### 7.7 Powiązane `SkillResource` (timeline — wzorzec dla `rozlup`)

```
id=&"rozlup", category=&"active", cost_resource=&"rage", cost_amount=25, cooldown=4.0,
damage_mult=1.6, anticipation=0.25, active=0.15, recovery=0.35, cancel_window=0.2,
tags=[&"melee",&"aoe"], aura_kind=&"slam", status_on_hit=[StatusApply(bleed,0.5,...)]
```

---

### 8. Build diversity — przykładowe buildy (Berserker + Mag)

**Berserker / Build A — "Krwawy Młyn" (sustained DoT bruiser):**
CORE Offense pełne (Ostrze Furii ×3, Głęboka Rana ×3, Krwiożerczość) + Defense lifesteal (Drugi
Oddech) -> Spec A keystone **Pakt Krwi** + Żniwo + ULTIMATE Krwawa Łaźnia. Loot: afiksy `+bleed`,
`+lifesteal`. Power-spike: keystone (x1.25 MORE) na lvl 25, drugi na ulti lvl 60. Gra: utrzymuj
bleed, egzekucje, sustain HP z lifesteal — anty-elite, słaby przeciw rojom.

**Berserker / Build B — "Lodowa Burza" (AoE freeze-shatter):**
CORE Offense crit + Mobility (Szarcha+ stun) -> Spec B **Wir Nieustający** + Mroźne Ostrze +
Roztrzaskanie + ULTIMATE Tornado Stali. Loot: `+cold/ice`, `+crit`. Combo: chill -> krytyk freeze ->
ulti shatteruje całą grupę. Power-spike: AoE clear pod Snow/jaskinie z rojami. Słaby 1v1 vs
freeze-immune (Volcanic).

**Berserker / Build C — "Tank-Provokator" (co-op frontline):**
Defense pełne (Niezłomny, Twarda Skóra ×3) + Utility (Prowokacja+weaken) + Spec A do Pakt Krwi dla
sustainu, bez ulti-burst. Rola: trzyma aggro, weaken na bossie -> reszta party bije mocniej (synergia
party-wide). Power-spike: lvl 20 Niezłomny (+15% HP MORE-like) + weaken aura.

**Mag (`&"mag"`, zasób mana) / Build A — "Piromanta" (burn + oil):**
CORE Offense fire (INCREASED fire_damage) + Utility **Olej** -> Spec fire keystone *"burn x1.3
MORE"*. Combo burn+oil (x2 tick), podpala kałuże w jaskiniach. Loot: `+fire`, `+burn duration`.
Świetny w Volcanic-ready vs grupy, kara: cele fire-immune.

**Mag / Build B — "Kriomanta" (freeze control):**
CORE Lodowy grot + freeze-duration notable -> Spec ice keystone *"krytyk zawsze freeze"* + shatter.
Kontrola CC, burst z shatter (15% max_hp). Synergia party: zamraża dla meleé do shatteru. Słaby DPS
solo na bossach freeze-resistant -> wtedy respec.

---

### 9. RESPEC (rozbudowa istniejącego `SkillTreeComponent.respec`)

Silnik już ma: koszt schodkowy w **Orbach Przemiany** (`ORB_COST_STEPS = [500,1500,4000]`, dalej
+4000 cap) i tani respec za **Złoto** (`level*50`). Rozszerzenia projektowe:

| Tryb | Koszt | Zakres | Hook |
|---|---|---|---|
| **Pojedynczy węzeł** (Orb Drobny) | 1 Orb Drobny | cofnij 1 liść (jeśli nic od niego nie zależy) | `deallocate()` — już istnieje, strukturalnie darmowy + opłata waluty w warstwie wyżej |
| **Respec gałęzi** | `gold_cost_for(level)` ×0.5 | reset jednej gałęzi CORE | nowy wariant `respec_branch(branch)` filtrujący `_allocated` po `node.branch` |
| **Pełny respec** | `orb_cost_for(respec_index)` LUB `gold_cost_for(level)` | wszystko + zmiana spec A/B | istniejący `respec()` |
| **Zmiana specjalizacji** | pełny respec (zwalnia `spec_lock`) | przełączenie hard-spec A<->B | walidacja `spec_choice_exclusive` w `cannot_allocate_reason` |

`respec_done(refunded, cost)` / `respec_failed(reason)` — bez zmian; UI (`SkillTreeUI.gd`) pokazuje
podgląd przed potwierdzeniem. Pierwszy respec do lvl 20 darmowy (onboarding eksperymentowania).

---

### 10. Pliki danych do wyprodukowania (rozwiązuje BLOKER #1 — pusty świat)

`SkillDB` skanuje `res://data/db/{skills,trees,passives,augments}`. Potrzebne `.tres`:

- `data/db/trees/` — **11×** `SkillTreeResource` (1 per `class_id`), każde z `core_branches`/`advanced_branches`.
- `data/db/passives/` — **~22 węzły/klasa** (CORE ~16 + ADVANCED ~6) -> ~240 plików, lub jedno
  `SkillTreeResource.nodes` inline per klasa (preferowane: mniej plików, szybszy skan, budżet pamięci).
- `data/db/skills/` — `SkillResource` dla każdego `grants_skill` + 2 ultimate/klasa (~6-8/klasa).
- Nowe: `StatusApplyResource` (inline w skillach/węzłach), `StatusComponent.gd` dodać do prefabu encji
  jako sibling `StatsComponent` (auto-rejestruje provider, jak `SkillTreeComponent`).

Kolejność wdrożenia (pod vertical slice): Berserker + Mag pełne -> reszta klas wg wzorca z sek. 7.
