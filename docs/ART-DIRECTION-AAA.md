# Dossier: Kierunek artystyczny i rendering AAA
## Voxel RPG (Godot 4.7, dostrojone pod RTX 3050 4 GB)

> Wygenerowane przez zespol tech-art (10 agentow). Kazda rekomendacja: cel wizualny / implementacja (Godot 4.7, pseudokod) / koszt (CPU-build vs GPU) / priorytet.

# DOSSIER NADRZĘDNE — kierunek artystyczny i rendering dla voxel action-RPG (Godot 4.7, RTX 3050 4 GB)

## 1. Executive summary

Twój prototyp ma poprawne fundamenty (ACES, SSAO, glow, volumetric fog, cykl dobowy), ale wygląda jak prototyp z trzech konkretnych powodów: świat jest **płaski świetlnie** (AO napisane, lecz wyłączone; ambient to jeden bezkierunkowy fill z nieba; zero bounce), **martwy w ruchu** (zero wiatru, cząsteczek, animacji wody, game-feel kamery) i **surowy kolorystycznie** (brak color grade, brak AA — voxele migoczą na każdej krawędzi). Najmocniej jakość podniesie przeniesienie tożsamości wizualnej z geometrii (drogi CPU-build, Twoje wąskie gardło) do **shaderów i światła (tani GPU-render, gdzie masz ~6 ms zapasu na klatkę)**: hemisferyczny ambient w shaderze terenu jako tani zamiennik GI, custom shader terenu z curvature-AO i rim, wiatr na trawie/liściach, oraz autorski color grade per pora doby. Drugą osią jest **game feel** — odpięcie kamery od gracza, smoothing, shake i hitstop to czysto CPU-owe zmiany, które natychmiast zamieniają „ikonę na planszy" w „postać w świecie". Krytyczna decyzja architektoniczna: przeniesienie budowy chunków na `WorkerThreadPool`, co odblokowuje LOD dali i usuwa stuttery bez dotykania budżetu VRAM. Cała mapa drogowa jest sortowana wg stosunku efekt/koszt **dla tego konkretnego GPU** — większość Fazy 0 to godziny pracy i zero nowego VRAM. SDFGI słusznie zostaje wyłączone; jego zamiennikiem jest hemisfera + fill light + aerial perspective.

## 2. Zunifikowana mapa drogowa wdrożenia (sortowanie: efekt/koszt dla RTX 3050 4 GB)

### FAZA 0 — Quick wins (godziny pracy, duży efekt, zero/Low GPU, zero nowego VRAM)

Kolejność celowo zaczyna od pozycji bez kodu strukturalnego (czyste property), potem tanie shadery i game-feel CPU.

**0A. Property na Environment / Viewport / DirectionalLight (jeden wieczór, zero kodu):**
- **Tonemap ACES → AGX**, `exposure 0.8 → 0.85` — żywsze kolory bez wypalania śniegu/wody. Jeśli wyjdzie wyprane, wróć na ACES + saturacja w adjustment. [postproc §6]
- **`adjustment_enabled = true`**: `contrast 1.05`, `saturation 1.12` — autorski look za darmo. [lighting §6a, postproc §7]
- **MSAA 2x** (`msaa_3d`), `use_taa = false`, FXAA off — koniec migotania krawędzi voxeli. **NIE TAA** (ghosting na ostrych krawędziach). [postproc §12] — to jedyna pozycja Fazy 0 z realnym kosztem VRAM (~30-40 MB render target).
- **`directional_shadow_max_distance 120 → 80`** + `blend_splits`, split offsety 0.06/0.15/0.35, `fade_start 0.9`, `shadow_blur 1.5 → 1.0` — ostrzejszy cień ZA DARMO (render_distance to 64 m, cień na 120 m marnował teksele). [lighting §5, postproc §9]
- **SSAO re-tune**: `radius 0.5 → 0.8` (VOXEL_SIZE 0.5 m), `intensity 2.0 → 1.4`, `power 1.5`, `horizon 0.06`, quality Medium. [postproc §1]
- **Glow HDR threshold**: `threshold 1.0`, levels 2-4 only, softlight, `bloom 0.05 → 0.1` — selektywna poświata zamiast mleka. [postproc §3]
- **`fog_aerial_perspective = 1.0`** + `fog_sky_affect = 1.0` — dal wtapia się w kolor horyzontu, maskuje krawędź świata. Najtańszy efekt głębi w całym dossier. [dystans §1A]
- **Depth fog dostrojony do krawędzi**: `fog_depth_begin 38`, `fog_depth_end 66`, curve 2.0 — chunki wyłaniają się z mgły zamiast wyskakiwać (obecna density 0.002 daje 88% widoczności na krawędzi = popping widoczny). [dystans §2A]
- **Ground-color skybox proxy**: `ProceduralSkyMaterial.ground_bottom/horizon_color` w barwie biomu — iluzja terenu za 64 m, zero geometrii. [dystans §6A]
- **Volumetric fog**: `length = 64` (nie licz froxeli do horyzontu), `anisotropy 0.4` (włącza tanie god rays ze słońca), `ambient_inject 0.2`. [postproc §4, §11]

**0B. Tanie shadery (GPU-render, zero CPU-build):**
- **Shader terenu** (StandardMaterial3D → ShaderMaterial): zachowuje vertex colors + twarde normalne, DODAJE **hemisferyczny ambient** (góra/dół wg world-normal.y — fake GI), **curvature-AO z `fwidth`** (głębia w narożnikach bez per-vertex AO w buildzie), **rim/fresnel** (czytelność krawędzi), **triplanar detail-noise** (mikro-ziarno łamiące płaskość). To fundament — odblokowuje resztę. [shadery §1, lighting §1A]
- **Fill DirectionalLight** (bez cienia, energy 0.15-0.22, barwa dopełniająca słońce) — wypełnia cienie kierunkowo zamiast płaskiego ambientu. [lighting §1B]
- **Wiatr trawy** (vertex sway w shaderze propów) — WYMAGA migracji propów na MultiMesh (i tak wygrana na draw-callach). [shadery §2, environment §1]
- **Rim + hit-flash na postaciach/wrogach** (flash = realny feedback walki, nadbiel `Color(2,2,2)` by przebić ACES). [shadery §5, gamefeel §6]
- **Vignette** (canvas_item shader na istniejącym HUD CanvasLayer). [postproc §8]

**0C. Game feel (czysto CPU/RAM, zero GPU, zero VRAM):**
- **Movement feel**: `move_toward` z accel/decel, coyote time, jump buffer, jump-cut, cięższe opadanie. [gamefeel §1]
- **Kamera odpięta od gracza** (`top_level`, smoothing `1-exp(-k·dt)`) — fundament pod shake/lag. [gamefeel §2]
- **Hitstop** (`Engine.time_scale 0.05` na 60-100 ms, timer z `ignore_time_scale`) — najsilniejszy juice walki. [gamefeel §5]
- **Camera shake** trauma-based (trauma², FastNoiseLite, roll najmocniejszy). [gamefeel §4]
- **Audio od zera** (Autoload + pula 8× AudioStreamPlayer3D, kroki per biom, whoosh/thud, ambient dobowy) — największa pojedyncza luka, zero VRAM. [gamefeel §8]
- **Blob shadow** pod postacią (Decal/quad) — osadza model w świecie. [polish50 §8]

### FAZA 1 — Średnie (custom shadery treściowe, particles, atmosfera)

- **Shader wody** (osobny surface): gradient głębi, fresnel, foam na brzegu (depth-based), animowane normale, falowanie vertex (amp 0.04 — voxel zostaje płaski). Wariant LITE bez SCREEN_TEXTURE jako pierwszy. Największy skok pojedynczego typu bloku. [shadery §4, environment §10]
- **Wiatr drzew/liści** (osobny surface foliage) + **fake subsurface/translucency** (prześwit liści pod niskie słońce — mocny o świcie/zachodzie). Dotyka CPU-build (wyodrębnienie liści), więc po trawie. [shadery §3, environment §2]
- **Particles ambient**: świetliki (noc, emisja additive, ZERO real-lights), kurz w słońcu (god-dust), spadające liście, kurz spod stóp, impact-particles walki (voxelowe kostki 0.08 m). Wszystkie pulowane, `amount × fx_scale`, podążające za graczem, dzień/noc gating przez DayNight. [environment §3,6,7,9; gamefeel §7]
- **Camera lag** (yaw/pitch rozdzielnie), **FOV-kick** sprint/atak, **anticipation + lunge** ataku, **impact squash** wroga. [gamefeel §3,5,6]
- **Color grade per doba**: `adjustment_*` interpolowane w DayNight + opcjonalny LUT 16³ (wariant tani: jeden neutralny LUT + saturacja/kontrast per keyframe). [lighting §6, postproc §7]
- **God rays** o złotej godzinie: `volumetric_fog_density → 0.0035` i `anisotropy → 0.6` w keyframach świtu/zachodu (zero kosztu ponad istniejący fog + cienie). [postproc §11]
- **HUD polish**: płynne paski HP/stamina z damage-chip, floating damage numbers, low-HP vignette, screen-flash obrażeń. [polish50 §42-46]
- **Atmospheric perspective + desaturacja dali** wbudowane w shader terenu (jeśli idziesz ścieżką shaderowego tintu zamiast samego fog). [dystans §1B,4]

### FAZA 2 — Duże / ryzykowne (architektura, LOD, decyzje)

- **`WorkerThreadPool` dla budowy chunków** — ENABLER wszystkiego dalej. Buduj ArrayMesh w wątku (czyste dane), `mesh_instance.mesh =` i dodanie do drzewa na main thread. Usuwa stuttery, pozwala podnieść `chunks_per_frame`, odblokowuje LOD. Najważniejsza pojedyncza zmiana dla Twojego realnego limitu (CPU-build single-thread). [dystans §6C, teren-art puenta]
- **LOD dali**: half-res ring (voxel 1.0 m, bez tint/AO/propów, 4-8× tańszy build) + skirts na szwy LOD0↔LOD1; opcjonalnie ultra-LOD2 (2.0 m) jako sylwetki w mgle. NETTO oszczędza CPU-build. **Imposters — odrzuć** (atlas w 4 GB, RTT — ślepa uliczka). [dystans §3,6B]
- **Wariacja terenu** (źródłowa naprawa „falowania"): warstwy szumu (continent/mountain ridged/hills), domain warp, kompozycja multiplikatywna `cont*mnt`, slope→skała, klimat (temp/humid ortogonalny do wysokości), tarasowanie klifów, landmarki na gridzie. Wszystko CPU-build — rób PO threadingu, z próbkowaniem makro-map per-chunk (4 narożniki). [teren-art §1-6]
- **Subtle DoF far** (amount 0.06, quality Low, tylko far) — miniaturkowy klimat. [postproc §10]
- **Per-chunk dither fade-in** (discard, nie alpha-blend) — anty-popping nawet poza mgłą. [dystans §2B]
- **ReflectionProbe** (UPDATE_ONCE, tylko jeśli woda z odbiciami). [lighting §1D]
- **Pogoda** (deszcz/śnieg particles + WeatherManager lerpujący fog/glow/ambient), weather/biome LUT. [polish50 §27-29]

## 3. Budżet wydajności 4 GB

**WŁĄCZYĆ na pewno:** AGX + adjustment (0 VRAM), SSAO Medium re-tune (0), glow levels 2-4 (mały), shadow atlas **4096** (NIE 8192 — to ~256 MB; 4096 ~64-128 MB), volumetric fog froxele **64³** (~8 MB, NIE 128³), MSAA 2x (~30-40 MB render target — największy pojedynczy konsument z listy, dlatego 2x nie 4x), shadery terenu/wody/foliage (~128 KB tekstur noise łącznie). Łączny narzut wszystkich custom shaderów: **~1.0-1.4 ms/klatkę** przy budżecie 10.4 ms — gigantyczny zapas po stronie GPU-render.

**ODPUŚCIĆ:** SDFGI (słusznie off), SSIL (drugi screen-space pass + bufor), **TAA** (ghosting na voxelach — krytyczne), CompositorEffect god rays (volumetric robi to taniej), MSAA 4x, volume_size 128, LightmapGI (niewykonalne dla proceduralnych chunków), imposters dali (atlas w 4 GB), DoF near, OmniLight per firefly/particle.

**PILNOWAĆ:**
- **CPU-build chunku to JEDYNE realne wąskie gardło**, nie VRAM ani fillrate. Każda rekomendacja terenowa z sekcji teren-art dokłada do niego — stąd próbkowanie makro-map per-chunk i bezwzględny priorytet `WorkerThreadPool` przed wariacją terenu.
- **Particles**: łączny budżet transparentnych/additive quadów w kadrze **< ~150** (dust+pollen+fireflies+leaves), `amount × fx_scale` (spada do 0.5 gdy FPS < 55 przez 2 s), wszystko podąża za graczem z ręcznym `visibility_aabb` ~30-40 m, dzień/noc gating (oszczędza ~50% kosztu FX uśrednionego po dobie).
- **Czerwona linia VRAM**: jeśli zabraknie po włączeniu MSAA — najpierw `scaling_3d/scale = 0.85` (FSR-like), dopiero potem rezygnacja z MSAA. Trzymaj natywne 1080p tak długo, jak się da.
- **Fill light i particles BEZ cieni** (drugi shadow atlas / per-particle light = zabójcze dla 4 GB).

## 4. Ryzyka i pułapki specyficzne dla Godot/GDScript

- **TAA + voxele = ghosting na każdej krawędzi.** Twoje ostre, wysokokontrastowe krawędzie + mikro-tint (szum) + przyszłe animowane propy to najgorszy możliwy materiał dla TAA. Bezwarunkowo MSAA, nie TAA.
- **Greedy meshing vs vertex-AO/tint**: słusznie odrzucone dla LOD0 (per-voxel detale blokują łączenie). Furtka: dla DALEKICH chunków te detale są niewidoczne — LOD ring half-res bez tint/AO MOŻE łączyć ściany. Nie próbuj greedy na bliskim terenie.
- **Szwy/cracki na granicy LOD0↔LOD1**: stitching geometrii w GDScript to koszmar — użyj **skirts** (pionowy kołnierz w dół o `vsize` na krawędziach chunku), tanie i wystarczające.
- **Popping chunków**: obecna density 0.002 daje 88% transmittance na krawędzi — popping BĘDZIE widać. Najpierw depth fog dostrojony do krawędzi (begin/end), dopiero potem dither dissolve. **Dither `discard`, NIE alpha-blend** (alpha zabija depth-prepass i psuje SSAO).
- **`Engine.time_scale` przy hitstop zamraża timery** — timer hitstopu MUSI mieć `ignore_time_scale = true`, inaczej deadlock.
- **`vertex_color_is_srgb` przy przejściu na ShaderMaterial**: StandardMaterial robił konwersję automatycznie; w shaderze ręcznie `pow(COLOR.rgb, 2.2)` w fragmencie ORAZ `.srgb_to_linear()` na kolorach uniformów ustawianych z DayNight.gd. Łatwo o podwójną/brakującą konwersję = wyblakłe lub przepalone kolory.
- **`NORMAL` w fragmencie to view-space** — hemisferę/aerial licz z world-normal (`MODEL_MATRIX * NORMAL` w vertex, varying), nie z surowego `NORMAL`.
- **Custom `light()` przejmuje cały model oświetlenia** — dla translucency liści tańszy/bezpieczniejszy wariant to `EMISSION` z jawnym `sun_dir` uniformem z DayNight, zamiast nadpisywać `DIFFUSE_LIGHT`.
- **Soft shadows (`soft_shadow_filter_quality 3` + `angular_distance 1.5`)** to realny narzut PCSS na 3050 — akceptowalny TYLKO przy jednym directional i atlas 4096; nie dawaj drugiemu światłu cienia.
- **MultiMesh dla propów to warunek wiatru** — bez migracji animacja zadziała, ale setki-tysiące osobnych MeshInstance3D zatkają CPU (draw calls) zanim VRAM drgnie. Migracja to wygrana niezależnie od wiatru.
- **Faktura wersji Godot**: część specjalistów zaznaczyła, że publiczny stable to 4.3/4.4, nie 4.7 — wszystkie property/shadery powyżej działają na 4.3+; jeśli to custom build 4.7, API jest identyczne. Zweryfikuj jedynie ekspozycję `CameraAttributesPractical` (DoF) i screen-space contact shadows w Twoim buildzie przed wpięciem.

Pliki integracyjne (absolutne): `C:\Users\oskar\Downloads\voxel-rpg\src\Main.gd` (Environment/viewport/particle-pool), `C:\Users\oskar\Downloads\voxel-rpg\src\DayNight.gd` (spięcie słońce/ambient/hemisfera/fog/grading/god-rays/gating particles), `C:\Users\oskar\Downloads\voxel-rpg\src\world\VoxelWorld.gd` (materiały→shadery, noise/klimat/landmarki, WorkerThreadPool), `C:\Users\oskar\Downloads\voxel-rpg\src\world\Chunk.gd` (shader terenu, LOD/skirts, foliage surface, woda surface), `C:\Users\oskar\Downloads\voxel-rpg\src\Player.gd` (movement/kamera/shake/hitstop/audio), `C:\Users\oskar\Downloads\voxel-rpg\src\Enemy.gd` (squash/nadbiel/flash), nowy `C:\Users\oskar\Downloads\voxel-rpg\src\Audio.gd` (Autoload), `C:\Users\oskar\Downloads\voxel-rpg\project.godot` (sekcja `[rendering]`, autoload Audio).

---

# Sekcje szczegolowe (specjalisci)

## [diagnoza] diagnoza prototypu

I have everything I need. The brief is fully confirmed against the code, plus I found three concrete additional facts: (1) per-vertex AO is implemented but called with `with_ao=false` (dead code), (2) no viewport config exists at all (default MSAA off, TAA off, default project — no `[rendering]` block), (3) water renders only its top face with no shader. Now I'll write the analysis.

---

# DLACZEGO TO WYGLĄDA JAK PROTOTYP

Bezlitosna diagnoza Twojego konkretnego renderingu (`voxel-rpg/`, Godot 4.7, RTX 3050 4 GB). Każdy punkt = co dokładnie zdradza prototyp + jednozdaniowy kierunek naprawy. Pełne rekomendacje z kosztami i priorytetami w sekcji końcowej.

### 1. Voxele są PŁASKIE — AO jest wyłączone, a SSAO tego nie nadrabia
To jest grzech główny. W `Chunk.gd` masz w pełni zaimplementowane per-vertex AO (`_ao_color`, klasyczny ramp 1.0/0.85/0.72/0.6, `_face_tangents`, `_corner_sign`) — i wołasz `_emit_face(..., false)` w obu miejscach (linie 531 i 540). **AO jest martwym kodem.** Skutek: każda ściana voxela ma jeden, idealnie jednolity kolor od krawędzi do krawędzi. Styki bloków, wnęki pod drzewami, narożniki — wszystko świeci tak samo. SSAO (`intensity 2.0, radius 0.5`) działa w screen-space, więc łapie tylko duże wklęsłości widziane pod kątem; przy ostrych krawędziach voxela 0.5 m i tak nie wejdzie w każdy styk i znika przy ruchu kamery (typowy SSAO flicker). To, co czyta mózg jako "render z silnika", a nie "prototyp", to właśnie ten ciemny ząbek w każdym wewnętrznym narożniku siatki — a Ty go masz napisanego i wyłączonego. *Kierunek: włączyć istniejące `with_ao=true` (bake do vertex color), zaakceptować droższy build chunku, SSAO zostawić jako warstwę uzupełniającą.*

### 2. Oświetlenie jest "flat" — bo całe wypełnienie cienia to jeden płaski ambient z nieba
Masz dokładnie dwa źródła światła: kierunkowe słońce (`energy 1.0`) i ambient (`AMBIENT_SOURCE_SKY, energy 0.25, sky_contribution 0.6`). Ambient ze SKY przy proceduralnym niebie to niemal jednolity, bezkierunkowy fill — każdy piksel w cieniu dostaje praktycznie ten sam kolor niezależnie od orientacji ściany. Ściana północna domu i podłoga w cieniu mają ten sam ton. Brak jakiejkolwiek wariacji świetlnej w zacienieniu = "plastikowa" płaskość, którą oko natychmiast czyta jako niegotowe. Dochodzi do tego, że SDFGI (jedyne GI, jakie miałeś) słusznie wyłączyłeś — więc nie ma ŻADNEGO odbicia/bounce. *Kierunek: dodać tani, kierunkowy ambient przez gradient w shaderze terenu (góra jaśniejsza/cieplejsza, dół ciemniejszy/chłodniejszy wg NORMAL.y), co imituje hemisferyczne GI bez kosztu SDFGI.*

### 3. Kolory są jednolitymi "płachtami" — mikro-tint ±0.055 jest za słaby i działa tylko per-blok
`tint_at` daje ±0.055 wariacji i `gboost` na zieleni. To brzmi rozsądnie, ale efekt jest znikomy: 0.055 na kanale to ~5% jasności, poniżej progu, na którym oko widzi "teksturę". Większy problem strukturalny: wariacja jest **per-voxel jednolita na całej ścianie** (jeden `_solid_color` na face), więc nadal masz pola jednego koloru — tylko sąsiednie pola minimalnie się różnią. Brak jakiegokolwiek wzoru wewnątrz ściany (grain, plamki, gradient), brak makro-wariacji biomowej większej niż gradient trawy. W Cube World trawa "mieni się" — u Ciebie jest matową, jednolitą zieloną płytą. *Kierunek: dodać proceduralny grain w shaderze fragmentu (hash z `world_vertex_coords`) nakładany na albedo — wariacja WEWNĄTRZ ściany, nie tylko między blokami.*

### 4. Świat jest martwy — zero ruchu, zero cząsteczek
W briefie i kodzie potwierdzone: BRAK wiatru, BRAK animacji roślinności, BRAK GPUParticles. Trawa (`_build_grass_tuft`), liście koron, kwiaty — wszystko stoi nieruchomo jak odlew. Nic na świecie się nie porusza poza graczem i wrogami. To jest największy "tell" prototypu w ruchu: gracz idzie przez las, a las jest zamrożony. Żadnego kołysania źdźbeł, żadnego pyłku/iskier/spadających liści, żadnego marszczenia wody (woda renderuje tylko górną ścianę, `water_material` bez shadera — to płaska, lekko przezroczysta tafla). Statyczność = śmierć game feel. *Kierunek: shader wiatru na propach/liściach (przesunięcie VERTEX wg `TIME` + `world_vertex_coords`) i jeden GPUParticles3D na pyłek pod słońce — oba czysto GPU, niemal darmowe na 3050.*

### 5. Brak game feel kamery — obraz jest "sztywny"
Brak camera shake, lag, bob, FOV-kick przy biegu, brak DoF. Kamera jest przyklejona sztywno. Gdy gracz biegnie (`shift`), atakuje (`LMB`), dostaje obrażenia — kamera nie reaguje niczym. To sprawia, że nawet poprawna walka (masz HP/stamina/combo) czuje się jak poruszanie ikoną po planszy, a nie sterowanie postacią w świecie. *Kierunek: lekki position-lag + bob kamery w `Player.gd` i krótki shake na trafienie/atak — czysto CPU transformacja, zero kosztu GPU.*

### 6. Brak color grade i vignette — surowy, "domyślny" obraz
Masz ACES (`exposure 0.8, white 6.0`) i glow (`0.2/0.05`) — to dobry start, ale ZERO `adjustment_*` (brightness/contrast/saturation/LUT) i ZERO winiety. Obraz nie ma "podpisu" kolorystycznego: brak jednolitego pchnięcia w stronę ciepłej/zielonej palety, brak przyciemnienia rogów, które prowadzi wzrok do centrum. ACES bez grade'u daje neutralny, lekko wyblakły look — poprawny technicznie, ale "nie-autorski". Każda gra AAA ma rozpoznawalny grade; Ty masz domyślne tonemapowanie. *Kierunek: włączyć `adjustment_enabled` z lekkim podbiciem saturacji/kontrastu + winieta przez prosty CompositorEffect lub fullscreen quad — kopia kosztowo darmowa.*

### 7. Brak anty-aliasingu — krawędzie voxeli migoczą
`project.godot` NIE MA sekcji `[rendering]`, `Main.tscn` to goły `Node3D` bez konfiguracji viewportu. Czyli: **MSAA off, TAA off, domyślny viewport.** Przy świecie zbudowanym wyłącznie z ostrych krawędzi voxeli (twoja tożsamość wizualna!) to katastrofa estetyczna w ruchu — każda krawędź dachu, każdy róg drzewa "schodkuje" i migocze (edge crawling) podczas chodzenia. To absolutnie krzyczy "prototyp" w sekundę po starcie ruchu. *Kierunek: włączyć MSAA 4x na viewport (`msaa_3d`) — geometria voxelowa to czyste krawędzie, MSAA je wygładza idealnie i jest tańsze/ostrzejsze niż TAA dla tego stylu.*

### 8. Sylwetki postaci/wrogów są generyczne — BoxMesh bez wykończenia
Humanoid z `BoxMesh` + StandardMaterial albedo, animacja chodu przez pivoty. To czytelna sylwetka (dobrze), ale bez AO, bez rim-light, bez cienia kontaktowego pod stopami — postać "unosi się" nad terenem i nie jest osadzona w świecie. *Kierunek: dodać prosty fake contact shadow (ciemny, półprzezroczysty quad pod postacią) i rim-light w shaderze postaci — osadza modele w scenie.*

### 9. Mgła robi za atmosferę, ale jest jednowarstwowa i pozbawiona "głębi"
Volumetric fog (`density 0.002`) ładnie chowa doładowywane chunki, ale jest jednolicie cienka. Brak gęstniejącej mgły w dolinach/przy wodzie (height fog), brak god rays (volumetric light shafts), brak żadnego efektu "powietrza" przy słońcu. Daleki teren po prostu zanika w jednolitą barwę zamiast budować plany głębi. *Kierunek: dodać height-based density do mgły (gęstsza nisko nad wodą) i włączyć volumetric fog interakcję ze słońcem dla tanich god rays.*

---

# NORTH STAR — docelowy look

Stylizowany AAA voxel, "Cube World++": świat zbudowany z **ostrych, czytelnych sześcianów o żywej, nasyconej palecie**, ale każdy voxel jest **osadzony w przekonującym świetle** — głębokie, miękkie AO w każdym styku i wnęce, kierunkowy hemisferyczny ambient malujący ściany różnymi tonami zależnie od orientacji, i jeden autorski color grade (ciepłe światła, lekko chłodne cienie, podbita zieleń), który spina kadr w rozpoznawalną całość. **Świat oddycha**: trawa i liście falują na wietrze, pyłek tańczy w smugach słońca, woda się marszczy, jesienne liście opadają — ruch jest wszędzie, nawet gdy gracz stoi. **Kamera żyje z postacią**: lekki bob i lag w ruchu, krótki shake i FOV-kick w walce, sprawiające że każdy cios ma ciężar. Głębia kadru budowana jest **planami atmosfery** — height fog gęstniejący w dolinach, miękkie god rays przy słońcu, winieta prowadząca wzrok — tak że odległe szczyty śniegu majaczą za warstwami powietrza zamiast po prostu zanikać. Całość renderuje się płynnie na laptopowym 3050 4 GB, bo **tożsamość wizualna leży w shaderach i świetle (tani GPU-render), a nie w gęstości geometrii (drogi CPU-build)** — ostre sześciany zostają ostre, sylwetki czytelne, kolory soczyste, ale obraz przestaje być surowym zrzutem z silnika i staje się kadrem z gry, którą chce się oglądać w ruchu.

---

Pliki źródłowe (wszystkie ścieżki bezwzględne):
- `C:\Users\oskar\Downloads\voxel-rpg\src\Main.gd` — `_setup_environment()` (linie 49-123): Environment, słońce, SSAO/glow/fog/ACES. Tu brak `adjustment_*` i konfiguracji viewportu.
- `C:\Users\oskar\Downloads\voxel-rpg\src\world\Chunk.gd` — `_build_mesh()` (522-542) woła `_emit_face(..., false)` → **AO wyłączone**; `_ao_color()` (671-706) gotowe, nieużywane; `_solid_color()` (640-662) mikro-tint per-face.
- `C:\Users\oskar\Downloads\voxel-rpg\src\world\VoxelWorld.gd` — `_setup_materials()` (100-129): trzy `StandardMaterial3D`, zero custom shaderów; `tint_at()` (158-160) amplituda 0.055.
- `C:\Users\oskar\Downloads\voxel-rpg\src\DayNight.gd` — keyframe'y doby (36-82); to tu wepną się height/color zmiany mgły i god rays.
- `C:\Users\oskar\Downloads\voxel-rpg\src\world\Blocks.gd` — paleta kolorów (26-59).
- `C:\Users\oskar\Downloads\voxel-rpg\project.godot` — **brak sekcji `[rendering]`** (MSAA/TAA off); `C:\Users\oskar\Downloads\voxel-rpg\Main.tscn` — goły `Node3D`, brak konfiguracji viewportu.

(Uwaga: katalog roboczy `C:\Users\oskar\Downloads\Cube World Alpha` zawiera retailowy Cube World z 2013, nie Twój projekt — projekt Godot jest w `C:\Users\oskar\Downloads\voxel-rpg\`.)

---

## [lighting] lighting + color grade

I'll base everything on your actual setup (Godot 4.7, RTX 3050 4 GB, voxel chunks in GDScript, SDFGI off). Here is the LIGHTING section.

---

# SEKCJA: LIGHTING (Senior Lighting Artist/Engineer)

Założenia bazowe, do których odnoszę koszty: VRAM 4 GB to twardy sufit (DirectionalLight shadow atlas + volumetric fog froxele + glow buffery już zajmują budżet). Każda technika oparta o duże bufory ekranowe lub wolumetryczne 3D jest dla Ciebie "High". Color grading i parametry świateł to praktycznie zero VRAM — "Low". Poniżej 6 podsekcji + gotowy refaktor DayNight.gd na końcu.

---

## 1. "Uczucie GI" BEZ SDFGI

### 1A. Hemispheric ambient (niebo vs ziemia) — fundament

**Cel wizualny:** Wrażenie odbitego światła z ziemi — cienie i spody bloków nie są martwo-szare/niebieskie, lecz lekko podbarwione kolorem biomu (trawa → zielonkawy fill od dołu). To największy "fake GI" zysk za zero VRAM.

**Implementacja (Godot 4.7):** Godot nie ma natywnego ground-color w Environment ambient, więc robisz to w materiale terenu — masz już `vertex_color_use_as_albedo`, więc dodaj cienki custom shader na bazie StandardMaterial (przejście z `StandardMaterial3D` na `ShaderMaterial`, ten sam koszt renderu). Hemisphere term liczony z normalnej:

```glsl
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform vec3 sky_ambient : source_color = vec3(0.55, 0.62, 0.78);   // sterowane z DayNight
uniform vec3 ground_ambient : source_color = vec3(0.20, 0.17, 0.12);
uniform float ground_bounce_strength = 0.35;

void fragment() {
    ALBEDO = COLOR.rgb;          // vertex color (masz vertex_color_is_srgb=true -> srgb_to_linear w GDScript przy ustawianiu uniformów!)
    ROUGHNESS = 1.0;
    METALLIC = 0.0;
    // hemispheric fill: world-up dot
    float up = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);  // NORMAL jest w view-space; patrz uwaga niżej
    vec3 hemi = mix(ground_ambient, sky_ambient, up) * ground_bounce_strength;
    EMISSION = COLOR.rgb * hemi; // tani fill bez dodatkowego światła
}
```

Uwaga techniczna: w `fragment()` `NORMAL` jest w view-space. Aby dostać prawdziwe world-up, użyj `(INV_VIEW_MATRIX * vec4(NORMAL,0.0)).y` albo policz hemisferę w `vertex()` z world normal i przekaż varying. Masz TWARDE normalne per ściana, więc to per-face stałe — policz w `vertex()`, taniej:

```glsl
varying float v_up;
void vertex() {
    vec3 wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
    v_up = clamp(wn.y * 0.5 + 0.5, 0.0, 1.0);
}
```

**Koszt:** Low (GPU-render). Zero dodatkowego VRAM, ~kilka instrukcji ALU per fragment. NIE dotyka kosztu CPU-build chunku (shader, nie geometria). To kluczowe — odzyskujesz "AO/GI feel" bez per-vertex AO w buildzie.
**Priorytet:** High. To najlepszy stosunek efektu do kosztu w całej sekcji.

### 1B. Sky ambient + jeden "bounce/fill" DirectionalLight

**Cel wizualny:** Miękkie doświetlenie stron odwróconych od słońca, symulujące bounce z terenu/nieba — zamiast czarnych cieni masz wypełnienie w barwie dopełniającej do słońca (słońce ciepłe → fill chłodny).

**Implementacja:** Drugi `DirectionalLight3D` ("FillLight"):
- `light_energy = 0.15–0.25`
- kierunek: z grubsza przeciwny do słońca w azymucie, ale od góry-tyłu (np. -sun_dir odbite w X/Z, podniesione: rotacja ok. (-50°, sun_yaw+150°, 0))
- `light_color`: dopełnienie słońca (dzień: lekko niebieski 0.7,0.8,1.0)
- `shadow_enabled = false` (KLUCZOWE — drugi shadow atlas = drugie ~kilkaset MB VRAM, nie stać Cię)
- `light_specular = 0.0` (fill ma tylko dyfuzyjnie dokładać)

```gdscript
# DayNight.gd – fill jako chłodne dopełnienie słońca
fill_light.light_color = sun_color.inverted().lerp(Color(0.7,0.8,1.0), 0.6)
fill_light.light_energy = lerp(0.05, 0.22, day_factor)  # nocą prawie zero
```

**Koszt:** Low (GPU-render, bez cienia = bardzo tanio; tylko dodatkowy lighting pass term). VRAM ~0.
**Priorytet:** High. Razem z 1A daje 80% "wrażenia GI".

### 1C. LightmapGI — ocena dla Twoich proceduralnych chunków

**Werdykt: NIE. Odrzuć.** LightmapGI wymaga statycznej geometrii z UV2 i bake'u offline. Twój teren jest generowany proceduralnie w runtime (SurfaceTool→ArrayMesh, render_distance 4, chunks strumieniowane), więc:
- brak UV2 (musiałbyś je generować w buildzie chunku = dodatkowy CPU-build koszt, którego unikasz),
- bake jest niemożliwy dla terenu tworzonego po starcie,
- lightmapy zżerają VRAM (atlasy tekstur) — na 4 GB to zła inwestycja.

**Koszt:** N/A (niewykonalne dla proceduralnego streamingu).
**Priorytet:** Low (= nie robić). Hemispheric ambient (1A) to Twój zamiennik GI dla terenu.

### 1D. ReflectionProbe

**Cel wizualny:** Poprawne odbicia nieba w wodzie i delikatny spójny ambient specular. Przy `roughness 1.0` terenu odbicia są nieistotne — ale woda i ewentualne mokre/śliskie materiały skorzystają.

**Implementacja:** JEDEN `ReflectionProbe` w trybie `UPDATE_ONCE`, podążający za graczem skokowo (re-render tylko gdy gracz przejdzie próg, np. co 16 m), nie `UPDATE_ALWAYS`:
- `box_projection = false` (świat otwarty, projekcja pudełkowa nie ma sensu)
- `intensity = 0.6`
- `max_distance = 80`
- rozmiar ~ 80×40×80, ambient_mode = `AMBIENT_DISABLED` (ambient bierzesz z nieba/hemisfery, probe tylko do odbić wody)
- `mesh_lod_threshold` wysoki, by w bake'u probe rysować mniej

```gdscript
# re-bake tylko po przesunięciu, NIE co klatkę
if player.global_position.distance_to(probe.global_position) > 16.0:
    probe.global_position = player.global_position
    probe.update_mode = ReflectionProbe.UPDATE_ONCE  # wymusza jednorazowy refresh
```

**Koszt:** Med (GPU-render, okresowy re-render sceny do cubemapy = spike przy bake'u; cubemapa ~kilkanaście MB VRAM). UPDATE_ALWAYS byłby High — nie używaj.
**Priorytet:** Medium (tylko jeśli wprowadzisz wodę z odbiciami; inaczej Low). Dla `roughness 1.0` lądu pomijalne.

---

## 2. Ambient (energy / sky_contribution / per pora doby)

**Cel wizualny:** Ambient śledzi porę doby — w południe jasny i lekko chłodny od nieba, o zachodzie cieplejszy i słabszy, nocą ciemny niebieski. `sky_contribution` decyduje ile ambientu pochodzi z koloru nieba vs ze stałego `ambient_light_color`.

**Implementacja (Environment, sterowane z DayNight.gd):** Zostań przy `AMBIENT_SOURCE_SKY`. Per-keyframe wartości:

| Pora | `ambient_light_energy` | `ambient_light_sky_contribution` |
|---|---|---|
| Noc | 0.08 | 0.85 (niebo nocne ciemnoniebieskie dominuje) |
| Świt | 0.18 | 0.7 |
| Dzień | 0.30 | 0.6 (Twoja obecna 0.25 → podbij lekko, hemisfera 1A i tak dokłada) |
| Zachód | 0.20 | 0.55 (więcej stałego ciepłego koloru) |

```gdscript
# DayNight.gd – interpolacja ambientu razem z resztą keyframe'ów
env.ambient_light_energy = lerp(kf_a.ambient_energy, kf_b.ambient_energy, t)
env.ambient_light_sky_contribution = lerp(kf_a.sky_contrib, kf_b.sky_contrib, t)
```

**Koszt:** Low (GPU-render; zmiana uniformów Environment, zero VRAM, zero CPU-build).
**Priorytet:** High (już to robisz częściowo — rozszerz o sky_contribution per keyframe).

---

## 3. Słońce kierunkowe (energy / barwa / angular_distance / kąt)

**Cel wizualny:** Czytelny, kierunkowy klucz świetlny z miękką krawędzią cienia i barwą zależną od pory. Cube World ma żywe, lekko przesycone słońce — nie neutralne.

**Implementacja (DirectionalLight3D, per keyframe z DayNight.gd):**

| Pora | `light_energy` | `light_color` (RGB) | wysokość słońca (pitch) |
|---|---|---|---|
| Noc (księżyc) | 0.15 | (0.55, 0.62, 0.85) | -10° (pod horyzontem/nisko) |
| Świt | 0.7 | (1.0, 0.75, 0.55) | 8° |
| Dzień | 1.1 | (1.0, 0.96, 0.88) | 60° |
| Zachód | 0.8 | (1.0, 0.62, 0.40) | 6° |

Miękkość krawędzi cienia (penumbra fizyczna): `light_angular_distance = 1.5` (stopnie; realne słońce ~0.5°, ale 1.0–2.0 daje ładny stylizowany miękki brzeg). UWAGA: większy `angular_distance` wymaga `soft_shadow_filter_quality` ≥ Medium, inaczej widać schodki.

```gdscript
sun.light_energy = lerp(kf_a.sun_energy, kf_b.sun_energy, t)
sun.light_color  = kf_a.sun_color.lerp(kf_b.sun_color, t)
sun.light_angular_distance = 1.5
# kąt: pitch z keyframe'a, yaw obracaj liniowo z czasem doby dla ruchu słońca po niebie
var pitch = lerp(kf_a.sun_pitch, kf_b.sun_pitch, t)
var yaw   = day_progress * 360.0 - 90.0
sun.rotation_degrees = Vector3(pitch, yaw, 0.0)
```

**Koszt:** Low (GPU-render; sam light_angular_distance jest darmowy, ale wymusza filtr — patrz pkt 4). Zero VRAM/CPU-build.
**Priorytet:** High.

---

## 4. Miękkie cienie (shadow_blur / soft_shadow_filter_quality / params)

**Cel wizualny:** Cienie z delikatnym, stylizowanym rozmyciem brzegu — nie ostre piksele, nie rozmyta papka. Spójne z voxelową estetyką (kontur czytelny, brzeg miękki).

**Implementacja:**
- Per-light: `sun.shadow_blur = 1.0` (masz 1.5 — zmniejsz lekko; 1.5 przy 4 splitach potrafi rozmywać kontakt cienia pod nogami). 
- Per-light bias: `shadow_normal_bias = 1.0`, `shadow_bias = 0.03` — przy VOXEL_SIZE 0.5 m i ostrych ścianach łatwo o peter-panning/acne; dostrój `shadow_bias` w zakresie 0.02–0.05.
- Projektowo (ProjectSettings, globalne):
  - `rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality = 3` (High) — potrzebne, bo dałeś `angular_distance 1.5`. Na RTX 3050 to GPU-render Med, ale akceptowalny przy jednym directional.
  - `rendering/lights_and_shadows/directional_shadow/size = 4096` (NIE 8192 — 8192 to ~256+ MB na atlas, za dużo na 4 GB). 4096 to dobry kompromis ostrość/VRAM.
  - `rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality` możesz zostawić niżej (Med) — i tak nie masz punktowych z cieniem.

```gdscript
# DayNight.gd – opcjonalnie: nocą zmiękcz i osłab cień (księżyc)
sun.shadow_blur = lerp(1.0, 1.6, night_factor)
sun.shadow_enabled = sun.light_energy > 0.2  # wyłącz cień gdy słońce/księżyc bardzo słabe (oszczędność)
```

**Koszt:** Med (GPU-render). `soft_shadow_filter_quality 3` + `angular_distance 1.5` to realny narzut samplowania PCSS na 3050, ale przy JEDNYM directional i atlas 4096 mieści się w budżecie. Atlas 4096 ~64–128 MB VRAM (zależnie od formatu) — OK.
**Priorytet:** High (cienie to czytelność scen voxelowych).

---

## 5. Kaskady cieni (splits / offsets / blend_splits / max_distance / fade)

**Cel wizualny:** Ostre cienie blisko gracza (kontakt pod postacią/blokami), płynne przejścia między kaskadami bez widocznego "skoku" rozdzielczości, zanik na dystansie zamiast twardego cięcia.

**Implementacja (DirectionalLight3D):**
- `directional_shadow_mode = SHADOW_PARALLEL_4_SPLITS` (masz — zostaw).
- `directional_shadow_max_distance = 80` (masz 120 — ZMNIEJSZ). Twój `render_distance 4` = 64 m widoczności. Cień rzucany na 120 m, gdy świat kończy się ~64 m, marnuje rozdzielczość atlasu na pustkę. 80 m daje margines i ZAGĘSZCZA teksele cienia tam, gdzie je widać → ostrzejszy cień bez zwiększania atlasu. To darmowy zysk jakości.
- Split offsets (ProjectSettings `rendering/lights_and_shadows/directional_shadow/`):
  - `split_1 = 0.06`
  - `split_2 = 0.15`
  - `split_3 = 0.35`
  (reszta do 1.0 = kaskada 4). Przesunięcie pierwszych splitów blisko zagęszcza teksele w strefie kontaktu pod graczem.
- `blend_splits = true` — KLUCZOWE dla braku widocznych granic kaskad; kosztuje trochę GPU (sampluje dwie kaskady na styku), ale przy jednym świetle OK.
- `directional_shadow_fade_start = 0.9` — zanik cienia na 90% max_distance zamiast twardego końca.
- Pamiętaj: `shadow_max_distance` liczone od kamery; przy szybkim ruchu rozważ `directional_shadow_pancake_size` domyślne.

```gdscript
sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
sun.directional_shadow_max_distance = 80.0
sun.directional_shadow_blend_splits = true
sun.directional_shadow_fade_start = 0.9
```

**Koszt:** Low→Med (GPU-render). `blend_splits` to niewielki narzut samplowania na styku kaskad; redukcja max_distance ze 120→80 wręcz ODDAJE wydajność i podnosi jakość. Net: prawdopodobnie zysk.
**Priorytet:** High (max_distance 120→80 zrób natychmiast — to czysty zysk).

---

## 6. Color grading wg biomu i pory doby (adjustment_* + LUT)

**Cel wizualny:** Każda pora doby ma własny "look" (poranek pastelowy, południe nasycone, zachód ciepło-pomarańczowy, noc chłodno-niebieska z podbitym kontrastem), a wejście w biom (np. mroczny las vs słoneczna łąka) płynnie przesuwa barwę. To, co najbardziej "sprzedaje" klimat Cube World.

**Implementacja — dwa poziomy:**

**(a) Adjustment (tani, zawsze włącz):** `Environment.adjustment_enabled = true`, sterowane z DayNight + biom:
- `adjustment_brightness`, `adjustment_contrast`, `adjustment_saturation` — interpolowane per keyframe doby ORAZ przesuwane przez biom (mnożnik/offset).

| Pora | brightness | contrast | saturation |
|---|---|---|---|
| Noc | 0.95 | 1.10 | 0.85 |
| Świt | 1.0 | 1.0 | 1.05 |
| Dzień | 1.0 | 1.05 | 1.15 |
| Zachód | 1.02 | 1.08 | 1.20 |

**(b) LUT (`adjustment_color_correction`):** przypisz `GradientTexture` 1D lub teksturę 3D LUT (256×16 strip lub Texture3D). Per BIOM osobny LUT (las = zielono-chłodny, pustynia = ciepło-żółty, śnieg = niebiesko-jasny). Godot 4.7 obsługuje Texture3D w `adjustment_color_correction`.

Płynny blend LUT per-biom (Godot nie ma natywnego cross-fade dwóch LUT w Environment) — dwa podejścia:
1. **Tanio:** trzymaj JEDEN neutralny LUT, a "biom feel" rób przez `adjustment_saturation/contrast` + lekki tint na `volumetric_fog_albedo` i `ambient_light_color` (te już blendujesz). Wystarczająco dobre, zero VRAM ekstra.
2. **Dokładnie:** wygeneruj w runtime pośredni Texture3D = lerp(lut_A, lut_B, biome_t) na CPU (małe LUT 16³ = 4096 px, tanio) i podmień co przekroczenie progu strefy. To realne przy małym 16³ LUT.

```gdscript
# DayNight.gd – grading per doba, modulowany przez biom
func apply_grading(env, kf_a, kf_b, t, biome):
    env.adjustment_enabled = true
    env.adjustment_brightness = lerp(kf_a.bright, kf_b.bright, t) * biome.bright_mul
    env.adjustment_contrast   = lerp(kf_a.contrast, kf_b.contrast, t) * biome.contrast_mul
    env.adjustment_saturation = lerp(kf_a.sat, kf_b.sat, t) * biome.sat_mul
    # LUT blend (wariant dokładny, 16^3):
    if biome.changed:
        _blend_lut3d(env, current_lut, biome.target_lut, biome.blend_t)  # CPU lerp na 4096 px

# płynny blend biomu po wejściu w strefę (np. 3 s)
biome.blend_t = clamp(biome.blend_t + delta / 3.0, 0.0, 1.0)
```

**Koszt:** 
- Adjustment brightness/contrast/saturation: Low (GPU-render, kilka instrukcji w tonemap passie, zero VRAM).
- LUT 3D 16³: Low VRAM (4096 px ≈ kilkadziesiąt KB). Runtime lerp dwóch LUT: Low CPU (4096 elementów, robione tylko przy zmianie biomu, nie co klatkę).
**Priorytet:** High dla (a) adjustment per doba (ogromny zysk klimatu za grosze). Medium dla (b) LUT per-biom (zrób wariant 1 "tanio" najpierw; wariant 2 gdy będziesz mieć więcej biomów).

---

## SPIĘCIE: zrefaktoryzowany rdzeń DayNight.gd

Jeden zestaw keyframe'ów steruje WSZYSTKIM powyżej spójnie (słońce, ambient, hemisfera shadera, fog, grading):

```gdscript
# Keyframe doby
class_name DayKeyframe
var sun_energy: float
var sun_color: Color
var sun_pitch: float
var ambient_energy: float
var sky_contrib: float
var sky_top: Color
var sky_horizon: Color
var fog_albedo: Color
var hemi_sky: Color      # uniform shadera terenu (1A)
var hemi_ground: Color   # uniform shadera terenu (1A)
var bright: float
var contrast: float
var sat: float

func _process(delta):
    day_progress = fmod(day_progress + delta / DAY_LENGTH, 1.0)  # DAY_LENGTH=240
    var seg = _segment(day_progress)      # noc/świt/dzień/zachód
    var a = keyframes[seg.a]; var b = keyframes[seg.b]; var t = seg.t

    # --- SŁOŃCE (3,4,5) ---
    sun.light_energy = lerp(a.sun_energy, b.sun_energy, t)
    sun.light_color  = a.sun_color.lerp(b.sun_color, t)
    sun.rotation_degrees = Vector3(lerp(a.sun_pitch, b.sun_pitch, t), day_progress*360.0-90.0, 0)
    sun.shadow_enabled = sun.light_energy > 0.2
    sun.shadow_blur = lerp(1.0, 1.6, _night_factor())

    # --- FILL LIGHT (1B) ---
    fill.light_color = sun.light_color.inverted().lerp(Color(0.7,0.8,1.0), 0.6)
    fill.light_energy = lerp(0.05, 0.22, _day_factor())

    # --- AMBIENT (2) ---
    env.ambient_light_energy = lerp(a.ambient_energy, b.ambient_energy, t)
    env.ambient_light_sky_contribution = lerp(a.sky_contrib, b.sky_contrib, t)

    # --- NIEBO + FOG ---
    sky_mat.sky_top_color = a.sky_top.lerp(b.sky_top, t)
    sky_mat.sky_horizon_color = a.sky_horizon.lerp(b.sky_horizon, t)
    env.volumetric_fog_albedo = a.fog_albedo.lerp(b.fog_albedo, t)

    # --- HEMISPHERIC AMBIENT shadera terenu (1A) ---
    # UWAGA srgb: vertex_color_is_srgb=true => konwertuj kolory do linear przy ustawianiu uniformu
    terrain_mat.set_shader_parameter("sky_ambient", a.hemi_sky.lerp(b.hemi_sky, t).srgb_to_linear())
    terrain_mat.set_shader_parameter("ground_ambient", a.hemi_ground.lerp(b.hemi_ground, t).srgb_to_linear())

    # --- COLOR GRADING (6) ---
    env.adjustment_enabled = true
    env.adjustment_brightness = lerp(a.bright, b.bright, t) * biome.bright_mul
    env.adjustment_contrast   = lerp(a.contrast, b.contrast, t) * biome.contrast_mul
    env.adjustment_saturation = lerp(a.sat, b.sat, t) * biome.sat_mul
```

---

## PODSUMOWANIE PRIORYTETÓW (kolejność wdrożenia)

| # | Rekomendacja | Koszt | Typ | Priorytet |
|---|---|---|---|---|
| 5 | `directional_shadow_max_distance` 120→80 + split offsets + blend_splits + fade | Low (zysk) | GPU-render | **High — zrób pierwsze** |
| 1A | Hemispheric ambient w shaderze terenu (fake GI) | Low | GPU-render | **High** |
| 2 | Ambient per doba + sky_contribution | Low | GPU-render | **High** |
| 3 | Słońce: energy/color/angular_distance/kąt per keyframe | Low | GPU-render | **High** |
| 6a | Color grading adjustment_* per doba | Low | GPU-render | **High** |
| 1B | Fill DirectionalLight (bez cienia) | Low | GPU-render | **High** |
| 4 | Soft shadows: filter_quality 3, atlas 4096, blur 1.0, bias tuning | Med | GPU-render | **High** |
| 6b | LUT 3D per-biom (wariant tani najpierw) | Low | GPU-render + mały CPU | **Medium** |
| 1D | ReflectionProbe (UPDATE_ONCE) — tylko dla wody | Med | GPU-render | **Medium** |
| 1C | LightmapGI | — | — | **Low (odrzuć — proceduralne chunki)** |

Trzy rzeczy, które dają najwięcej za najmniej na Twoim 3050 4 GB: (1) **hemispheric ambient w shaderze terenu** — odzyskuje "GI/AO feel" bez kosztu CPU-build, (2) **redukcja shadow max_distance 120→80** — ostrzejszy cień ZA DARMO, (3) **color grading per doba** — największy skok klimatu za zero VRAM. SDFGI słusznie zostaje wyłączone; powyższy zestaw to jego najtańszy zamiennik dla 4 GB.

---

## [shadery] shadery

I'll deliver the SHADERS section. This is a design task based on the project facts provided — no file exploration needed, as you've given me the complete rendering state. Let me write the shader specifications.

# SEKCJA: SHADERS — Senior Technical Artist

Założenia bazowe dla RTX 3050 4 GB / Forward+: koszt RENDER (GPU fragment/vertex) ma zapas — przy 64 m render_distance i ~96 FPS steady-state GPU nie jest wąskim gardłem (CPU-build chunku jest). Dlatego **prawie cały budżet shaderowy płacimy w GPU, a NIE w CPU-build** — to dobra wiadomość. Krytyczna zasada przewija się wszędzie: jeśli efekt wymaga dodatkowego atrybutu wierzchołka liczonego w GDScript podczas budowy chunku, to jest CPU-build i drogie. Jeśli liczy się w shaderze z `VERTEX`/`world_vertex_coords`/`COLOR` — to GPU i tanie.

---

## (1) TEREN VOXELOWY — StandardMaterial3D → ShaderMaterial

**Cel wizualny:** Zachować obecny wygląd (vertex colors jako albedo, twarde normalne, ostre sześciany) i DODAĆ za darmo: tani AO/curvature dla głębi w zakamarkach, rim/edge highlight dla czytelności krawędzi voxela, triplanar detail-noise dla mikro-ziarna bez tekstur, gradient trawy z wysokości. To podnosi "stylizowaną głębię" bez SSAO-only.

**Implementacja (Godot 4.7 Shading Language):**

Najpierw decyzja o AO. Masz dwie ścieżki:
- **Ścieżka A (ZERO kosztu CPU-build):** AO/curvature liczone w `FRAGMENT` z gradientu normalnej i mikro-noise — całkowicie GPU. To rekomendowana ścieżka, bo per-vertex AO już raz wyłączyłeś jako za drogie w budowie.
- **Ścieżka B (mały koszt CPU-build):** zapisać AO do `COLOR.a` podczas SurfaceTool (alpha kanał wolny — używasz tylko RGB na tint). To daje "prawdziwe" AO w narożnikach, ale dokłada do budowy chunku 4 sample sąsiedztwa/vertex. Trzymaj jako opcję na później.

Poniżej Ścieżka A:

```glsl
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;
// specular_disabled: teren roughness=1, metallic=0 — spec i tak zerowy, oszczędza GPU

uniform float detail_strength    = 0.06;   // siła triplanar noise
uniform float detail_scale       = 3.0;    // m^-1, gęstość ziarna
uniform float rim_strength       = 0.10;   // jasność krawędzi
uniform float curvature_strength = 0.35;   // siła pseudo-AO z curvature
uniform float grass_blend_height = 2.0;    // m, szerokość gradientu trawy
uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
    v_world_pos    = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    // COLOR przychodzi jak dotąd jako vertex color (już z mikro-tintem z GDScript)
}

// Tani triplanar bez tekstur: 3 sample 2D-noise rzutowane po osiach, ważone normalą.
float triplanar_noise(vec3 p, vec3 n) {
    vec3 w = abs(n);
    w /= (w.x + w.y + w.z);
    float nx = texture(detail_noise, p.zy * detail_scale).r;
    float ny = texture(detail_noise, p.xz * detail_scale).r;
    float nz = texture(detail_noise, p.xy * detail_scale).r;
    return nx * w.x + ny * w.y + nz * w.z; // 0..1
}

void fragment() {
    // vertex color -> albedo. vertex_color_is_srgb robił to w StandardMaterial;
    // w ShaderMaterial konwertujemy ręcznie sRGB->linear:
    vec3 base = pow(COLOR.rgb, vec3(2.2));

    // --- Triplanar detail noise (mikro-ziarno, łamie płaskość ściany) ---
    float d = triplanar_noise(v_world_pos, v_world_normal);
    base *= mix(1.0 - detail_strength, 1.0 + detail_strength, d);

    // --- Pseudo-curvature / cheap AO z pochodnych normalnej ekranowej ---
    // fwidth na world-normal: rośnie na krawędziach geometrii -> ciemnimy zagłębienia
    vec3 dN = fwidth(v_world_normal);
    float curv = clamp((dN.x + dN.y + dN.z) * 2.0, 0.0, 1.0);
    base *= 1.0 - curv * curvature_strength;

    // --- Rim / edge highlight dla czytelności sylwetki voxela ---
    float fres = pow(1.0 - clamp(dot(v_world_normal, VIEW), 0.0, 1.0), 4.0);
    base += fres * rim_strength;

    // --- Gradient trawy z wysokości (opcjonalny, jeśli enkodujesz typ w COLOR
    //     albo chcesz globalny lekki rozjaśnianie szczytów) ---
    // float h = smoothstep(0.0, grass_blend_height, fract(v_world_pos.y));
    // base = mix(base, base * vec3(1.05,1.10,0.95), h * 0.3);

    ALBEDO     = base;
    ROUGHNESS  = 1.0;
    METALLIC   = 0.0;
    // Twarde normalne: NIE dotykamy NORMAL/NORMAL_MAP — zostają per-face z geometrii.
}
```

Detail noise: jedna mała tekstura 256×256 R8 FastNoiseLite zapisana raz do PNG (lub `NoiseTexture2D` w edytorze). VRAM: ~64 KB z mipmapami. Możesz też wygenerować noise proceduralnie w shaderze (hash), ale tekstura jest tańsza per-pixel.

**Koszt:** **Med (GPU-render), ZERO CPU-build.** Na RTX 3050: 3 sample tekstury (triplanar) + `fwidth` + fresnel na fragment. Przy 64 m i kilkuset tys. fragmentów terenu to ~0.2–0.4 ms. `fwidth` na varying jest darmowe (HW pochodne). Brak dodatkowego VRAM poza 64 KB noise. Najważniejsze: NIE rusza budowy chunku — Twoje wąskie gardło CPU nietknięte.

**Priorytet: High.** To fundament — ShaderMaterial odblokowuje wszystko inne, a sam w sobie daje głębię (curvature+rim) której SSAO-only nie złapie na krawędziach voxeli, i mikro-detal łamiący "plastikową" płaskość dużych ścian.

> Uwaga wydajnościowa: `triplanar_noise` to 3 sample. Jeśli zobaczysz spadek na dużych polach trawy, zredukuj do 1 sample po osi dominującej (`if (w.y > w.x && w.y > w.z) use p.xz`) — branch na GPU jest tani, bo koherentny per-face (twarde normalne = cała ściana ten sam branch).

---

## (2) TRAWA / DROBNE PROPY — wiatr w VERTEX

**Cel wizualny:** Drobne propy (trawa/kwiaty ~0.25 m, obecnie BoxMesh bez animacji) kołyszą się na wietrze; pochylenie od nasady (dół statyczny, góra się rusza). Życie w scenie bez kosztu CPU.

**Implementacja:** To powinno jechać na **MultiMeshInstance3D**, nie osobne MeshInstance3D per prop — obecnie masz osobne MeshInstance parentowane do chunku, co jest drogie w draw-callach i CPU. Migracja na MultiMesh to osobny temat (sekcja propów), ale shader działa identycznie. Pochylenie od nasady wymaga, by VERTEX.y=0 był u podstawy mesha (BoxMesh wycentrowany — przesuń pivot albo użyj `(VERTEX.y - aabb_min)`).

```glsl
shader_type spatial;
render_mode cull_disabled; // trawa widoczna z obu stron

uniform float wind_strength = 0.12;  // m wychylenia na szczycie
uniform float wind_speed    = 1.5;
uniform vec2  wind_dir      = vec2(1.0, 0.3);
uniform float stiffness_exp = 2.0;   // krzywa pochylenia od nasady

void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    // Waga: 0 u nasady (VERTEX.y=0), 1 na szczycie. Krzywa wykładnicza = naturalny łuk.
    float h = clamp(VERTEX.y / 0.25, 0.0, 1.0);   // 0.25 = wysokość propa
    float bend = pow(h, stiffness_exp);

    // Faza per-instancja z pozycji świata -> każdy prop kołysze inaczej (brak "fali zborowej")
    float phase = world.x * 0.7 + world.z * 0.7;
    float sway  = sin(TIME * wind_speed + phase) * wind_strength * bend;

    vec3 dir = normalize(vec3(wind_dir.x, 0.0, wind_dir.y));
    VERTEX.xz += dir.xz * sway;
    // drugi, szybszy oktaw dla "trzepotu" liścia (opcjonalnie):
    VERTEX.xz += dir.xz * sin(TIME * wind_speed * 2.7 + phase * 1.3) * wind_strength * 0.25 * bend;
}

void fragment() {
    ALBEDO    = pow(COLOR.rgb, vec3(2.2));
    ROUGHNESS = 1.0;
}
```

**Koszt:** **Low (GPU-vertex), ZERO CPU-build.** Kilka `sin` na wierzchołek. Trawa to mesh o małej liczbie vertów; nawet z MultiMesh × tysiące instancji to vertex-bound trivia dla 3050 — ~0.1 ms. Brak VRAM. Brak dotykania budowy chunku (animacja czysto w shaderze, statyczny mesh w buforze).

**Priorytet: High.** Największy "wow" za najmniejszą cenę — statyczna trawa w Cube World wygląda martwo, kołysanie ożywia całą scenę. Warunek: przejście propów na MultiMesh (inaczej animacja jest, ale draw-calle Cię zabiją po stronie CPU).

> Bez wzrostu CPU-build: TAK, w 100%. Faza z `world.x/z` eliminuje potrzebę per-instance custom data. Jeśli przejdziesz na MultiMesh, możesz wpisać losowy seed do `INSTANCE_CUSTOM.x` dla jeszcze lepszej dekorelacji — to też zero CPU-build (ustawiane raz przy spawnie instancji).

---

## (3) FOLIAGE / LIŚCIE — sway + fake subsurface (translucency)

**Cel wizualny:** Liście drzew/krzaków kołyszą się (mocniejszy, wolniejszy sway niż trawa) ORAZ prześwitują pod słońce — efekt "podświetlonego liścia od tyłu" (back-translucency), kluczowy dla soczystej zieleni Cube World.

**Implementacja:** Liście masz wpisane w voxele chunku — tu jest haczyk. Sway liści wpisanych w mesh chunku jest problematyczny (ten sam ShaderMaterial co teren, a nie chcesz kołysać ziemią). Rekomendacja: **liście drzew jako osobny materiał/surface**. Jeśli budujesz koronę jako część chunku, użyj osobnego SurfaceTool surface dla bloków typu "liść" z tym shaderem — to NIE dokłada budowy (i tak iterujesz voxele), tylko routuje do innego materiału. Translucency fake liczymy w `fragment` z `LIGHT()` lub przez dodanie do emisji proporcjonalnie do `dot(-light_dir, view)`.

```glsl
shader_type spatial;
render_mode cull_disabled;

uniform float leaf_wind     = 0.06;
uniform float leaf_speed    = 0.9;
uniform vec3  translucency_color : source_color = vec3(0.35, 0.6, 0.18);
uniform float translucency_amt = 0.6;

varying vec3 v_world_pos;

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float phase = v_world_pos.x * 0.5 + v_world_pos.y * 0.3 + v_world_pos.z * 0.5;
    // cała korona kołysze się spójnie (liście wpisane w voxele — brak nasady per-liść),
    // więc lekkie przesunięcie XYZ, nie bend od podstawy:
    vec3 off = vec3(
        sin(TIME * leaf_speed + phase),
        sin(TIME * leaf_speed * 1.3 + phase) * 0.4,
        cos(TIME * leaf_speed + phase * 1.1)
    ) * leaf_wind;
    VERTEX += off;
}

void fragment() {
    ALBEDO    = pow(COLOR.rgb, vec3(2.2));
    ROUGHNESS = 1.0;
}

// Fake subsurface: dokładamy światło "przechodzące przez liść" do diffuse.
void light() {
    float NdotL = max(dot(NORMAL, LIGHT), 0.0);
    DIFFUSE_LIGHT += ALBEDO * NdotL * LIGHT_COLOR * ATTENUATION;

    // back-translucency: gdy światło jest ZA liściem względem kamery
    float back = max(dot(-LIGHT, VIEW), 0.0);
    back = pow(back, 3.0);
    DIFFUSE_LIGHT += translucency_color * back * translucency_amt
                     * LIGHT_COLOR * ATTENUATION;
}
```

**Koszt:** **Med (GPU). CPU-build: znikomy** (tylko routing bloków-liści do osobnego surface, co i tak robisz iterując voxele). Custom `light()` wyłącza domyślny model i liczysz sam — kilka operacji/fragment/światło. Masz 1 directional + ambient sky, więc `light()` woła się rzadko. ~0.15 ms. Brak VRAM.

**Priorytet: Medium.** Sway liści (vertex) jest High-value/Low-cost — zrób na pewno. Translucency (`light()`) to polish; daje dużo dla atmosfery o świcie/zachodzie (Twój DayNight ma niskie słońce → mocny efekt prześwitu), ale nie blokuje niczego. Jeśli chcesz uniknąć custom `light()` (przejmuje cały lighting), tańszy wariant: dorzuć translucency do `EMISSION` w `fragment` używając jawnego uniformu kierunku słońca z DayNight.gd:

```glsl
// wariant bez custom light() — tańszy, mniej fizyczny:
uniform vec3 sun_dir;  // ustawiany z DayNight.gd co klatkę
void fragment() {
    ALBEDO = pow(COLOR.rgb, vec3(2.2));
    float back = pow(max(dot(-sun_dir, normalize(-VIEW)), 0.0), 3.0);
    EMISSION = translucency_color * back * translucency_amt * 0.5;
    ROUGHNESS = 1.0;
}
```

---

## (4) WODA — stylizowana voxelowa tafla

**Cel wizualny:** Woda nie jako płaski niebieski voxel, lecz: animowane fałdy (przesuwane normale), fresnel (ciemniej w pionie, jaśniej pod kątem), pianka na brzegu (depth-based, gdzie woda styka się z terenem), refrakcja przez SCREEN_TEXTURE, gradient głębi (płycizna jaśniejsza). Zachować voxelową, płaską taflę — żadnych wysokich fal.

**Implementacja:** Woda jako osobny surface/mesh (blok typu woda → osobny ShaderMaterial, transparent). Refrakcja i depth-foam wymagają `DEPTH_TEXTURE` + `SCREEN_TEXTURE` (w Godot 4.x `hint_screen_texture`/`hint_depth_texture`). To jest najdroższy shader z zestawu, ale wciąż GPU-only.

```glsl
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex  : hint_depth_texture, filter_nearest;
uniform sampler2D normal_noise : repeat_enable, filter_linear; // mała tekstura normal/noise

uniform vec3  shallow_color : source_color = vec3(0.25, 0.6, 0.7);
uniform vec3  deep_color    : source_color = vec3(0.05, 0.2, 0.35);
uniform float depth_fade    = 3.0;    // m, na jakiej głębi -> deep_color
uniform float foam_dist     = 0.4;    // m od brzegu
uniform float wave_speed    = 0.04;
uniform float refraction    = 0.03;
uniform float fresnel_pow   = 4.0;

varying vec3 v_world_pos;

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    // --- animowane "normale" z 2 warstw noise przesuwanych w przeciwne strony ---
    vec2 uv1 = v_world_pos.xz * 0.15 + vec2(TIME * wave_speed, 0.0);
    vec2 uv2 = v_world_pos.xz * 0.20 - vec2(0.0, TIME * wave_speed * 0.8);
    vec3 n1 = texture(normal_noise, uv1).xyz * 2.0 - 1.0;
    vec3 n2 = texture(normal_noise, uv2).xyz * 2.0 - 1.0;
    vec3 wave_n = normalize(vec3(n1.x + n2.x, 4.0, n1.z + n2.z)); // płaska tafla -> mocne Y
    NORMAL = normalize((VIEW_MATRIX * vec4(wave_n, 0.0)).xyz);

    // --- głębokość sceny pod taflą (depth-based) ---
    float scene_depth = texture(depth_tex, SCREEN_UV).r;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
    vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view_pos.xyz /= view_pos.w;
    float water_to_floor = -view_pos.z - (-VERTEX.z); // przybliżenie różnicy głębi (linear depth)
    float depth_amt = clamp(water_to_floor / depth_fade, 0.0, 1.0);

    // --- gradient głębi: płycizna -> głębia ---
    vec3 water_col = mix(shallow_color, deep_color, depth_amt);

    // --- pianka na brzegu: gdzie różnica głębi jest mała (woda płytka przy terenie) ---
    float foam = 1.0 - smoothstep(0.0, foam_dist, water_to_floor);
    foam *= 0.5 + 0.5 * sin(TIME * 2.0 + v_world_pos.x * 4.0); // migotanie pianki
    water_col = mix(water_col, vec3(0.9, 0.95, 1.0), clamp(foam, 0.0, 1.0));

    // --- refrakcja: próbkuj scenę z offsetem od fałd ---
    vec2 refr_uv = SCREEN_UV + wave_n.xz * refraction;
    vec3 refracted = texture(screen_tex, refr_uv).rgb;
    water_col = mix(refracted, water_col, clamp(depth_amt + 0.3, 0.0, 1.0));

    // --- fresnel: pod kątem jaśniej/odbicie nieba ---
    float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_pow);

    ALBEDO    = water_col;
    EMISSION  = water_col * fres * 0.3;   // tani fake odbicia nieba
    ROUGHNESS = 0.1;
    METALLIC  = 0.0;
    SPECULAR  = 0.5;
    ALPHA     = mix(0.75, 0.95, depth_amt); // płycizna bardziej przezroczysta
}
```

Uwagi implementacyjne: linearyzacja depth zależy od near/far Twojej kamery — pseudokod używa `INV_PROJECTION_MATRIX`; zweryfikuj znak Z (Godot view space Z ujemny). Płaskie odbicie (planar reflection) świadomie POMINĄŁEM — w Godot 4.7 wymaga drugiego viewportu renderującego scenę = duplikat kosztu, zabójcze dla 4 GB. Zamiast tego fresnel→EMISSION daje "tani połysk", a refleks nieba i tak dostajesz z reflection probe/ambient sky jeśli dodasz mały ReflectionProbe.

**Koszt:** **High (GPU-render). ZERO CPU-build.** To najdroższy shader: `SCREEN_TEXTURE` wymusza kopię bufora ekranu (Godot robi to raz, gdy jakikolwiek materiał go używa — koszt stały ~0.3 ms na 3050), `DEPTH_TEXTURE` sample, 2 noise sample, fresnel. Transparent = brak Z-prepass dla wody, overdraw. ALE: woda zajmuje mały % ekranu (jeziorka), więc realny narzut ~0.4–0.6 ms. VRAM: kopia screen buffer (już alokowana jeśli używasz glow — glow MASZ ON, więc bufor istnieje) + mała noise tekstura 64 KB.

**Priorytet: Medium.** Woda to duży wizualny skok, ale jest najdroższa i najbardziej finicky (depth linearization). Zrób PO terenie/trawie. Jeśli budżet ciasny, **wersja LITE bez SCREEN_TEXTURE/refrakcji** (tylko gradient głębi z depth + fresnel + animowany kolor) jest Low-Med koszt i wygląda 80% tak dobrze:

```glsl
// WODA LITE — bez screen copy, bez refrakcji. Koszt Low-Med.
// Usuń screen_tex i refrakcję; zostaw depth_tex (foam+gradient), noise normale, fresnel.
```

---

## (5) POSTACIE / WROGOWIE — rim light + flash trafienia + outline opcjonalnie

**Cel wizualny:** Czytelne sylwetki postaci (BoxMesh humanoid) odcięte od tła rim-lightem; biały/czerwony błysk przy trafieniu (feedback walki — masz HP/atak/unik); opcjonalny outline dla "toon" charakteru i czytelności wroga z dystansu.

**Implementacja:** ShaderMaterial na postaci. Flash sterowany uniformem z kodu walki (ustawiasz `hit_flash = 1.0` przy trafieniu, zanikasz w `_process`). Outline jako druga technika — w Godot 4.7 najtaniej: `cull_front` + `grow` w osobnym przebiegu (next_pass material) albo `inverted_hull`.

```glsl
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform vec3  rim_color : source_color = vec3(1.0, 0.95, 0.8);
uniform float rim_power = 3.0;
uniform float rim_strength = 0.4;
uniform float hit_flash = 0.0;                 // 0..1 z kodu walki
uniform vec3  flash_color : source_color = vec3(1.0, 0.3, 0.3);

void fragment() {
    vec3 base = pow(COLOR.rgb, vec3(2.2)); // lub albedo z uniformu, jeśli nie vertex color

    // rim light — niezależny od słońca, czysta czytelność sylwetki
    float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
    base += rim_color * rim * rim_strength;

    ALBEDO    = base;
    ROUGHNESS = 0.8;
    // flash trafienia: miesza do koloru + emisja, żeby błysnęło nawet w cieniu
    EMISSION  = flash_color * hit_flash;
    ALBEDO    = mix(ALBEDO, flash_color, hit_flash * 0.6);
}
```

Outline (osobny `next_pass` ShaderMaterial, inverted hull):

```glsl
shader_type spatial;
render_mode cull_front, unshaded; // renderuj tył, "spuchnięty"
uniform float outline_width = 0.02;        // m
uniform vec3  outline_color : source_color = vec3(0.05, 0.05, 0.08);
void vertex() {
    VERTEX += NORMAL * outline_width;       // rozdmuchanie po normalnej
}
void fragment() { ALBEDO = outline_color; }
```

Flash z GDScript:
```gdscript
# przy trafieniu:
mat.set_shader_parameter("hit_flash", 1.0)
# w _process(delta): zanikanie
flash = max(0.0, flash - delta * 5.0)
mat.set_shader_parameter("hit_flash", flash)
```

**Koszt:** **Low (GPU). ZERO CPU-build.** Postaci to garstka na ekranie, kilka boxów. Rim+flash = trywialne. Outline DODAJE drugi draw per postać (inverted hull) — przy kilku-kilkunastu wrogach to nic dla 3050 (~0.1 ms łącznie). VRAM: zero.

**Priorytet: High dla rim+flash** (flash to realny feedback gameplayowy walki, nie tylko estetyka — wysokowartościowy). **Low dla outline** — ładny, ale czysto estetyczny; dodaj jeśli chcesz mocniejszy toon look. Inverted-hull outline na BoxMesh humanoid może dać artefakty na ostrych narożnikach (rozjazd normalnych) — jeśli wystąpią, przejdź na outline w post (CompositorEffect z detekcją krawędzi depth/normal), ale to droższe.

---

## (6) DISTANT TERRAIN — uproszczony shader + atmospheric tint

**Cel wizualny:** Odległe chunki (przy 64 m render_distance granica jest blisko) zlewają się z mgłą/niebem zamiast urywać ostro; uproszczony shader bez detail-noise/curvature/rim, z tintem atmosferycznym ku kolorowi horyzontu/mgły. Maskuje krótki render_distance i taniej renderuje dalekie fragmenty.

**Implementacja:** Masz już volumetric fog ON — on robi większość roboty atmosferycznie. Ten shader to DODATEK: wariant materiału terenu (LOD-owy lub ten sam shader z `if (dist > threshold)`) który wyłącza drogie sample i miesza do koloru horyzontu z DayNight. Najprościej: w shaderze terenu (sekcja 1) dodaj wczesne wyjście dystansowe — branch koherentny przestrzennie, więc tani.

```glsl
// dodatek do shadera TERENU (sekcja 1):
uniform vec3  horizon_color : source_color = vec3(0.7, 0.78, 0.9); // sync z DayNight sky_horizon
uniform float fade_start = 45.0;   // m
uniform float fade_end   = 64.0;   // m = render_distance

void fragment() {
    float dist = length(v_world_pos - CAMERA_POSITION_WORLD);
    float far = smoothstep(fade_start, fade_end, dist);

    vec3 base = pow(COLOR.rgb, vec3(2.2));

    // dalekie fragmenty: pomiń detail-noise, curvature, rim (oszczędność GPU + spójność)
    if (far < 0.99) {
        // ... pełna ścieżka z sekcji 1 (noise + curvature + rim) ...
    }
    // atmospheric tint ku horyzontowi (DayNight ustawia horizon_color co klatkę)
    base = mix(base, horizon_color, far * 0.6);

    ALBEDO = base;
    ROUGHNESS = 1.0;
}
```

Kluczowe: `horizon_color` ustawiaj z DayNight.gd tym samym keyframe co `sky_horizon`/`volumetric_fog_albedo`, żeby teren topił się dokładnie w kolor nieba/mgły na granicy — to ukrywa pop-in nowych chunków.

**Koszt:** **Low (GPU-render), ZERO CPU-build.** Branch dystansowy OSZCZĘDZA GPU (pomija sample na dalekich fragmentach). Tint to jeden `mix`. `CAMERA_POSITION_WORLD` darmowe. Brak VRAM, brak budowy chunku.

**Priorytet: Medium.** Volumetric fog już maskuje sporo, więc to polish + drobna optymalizacja. Wartość rośnie, jeśli zwiększysz render_distance (wtedy tint na granicy ważniejszy). Synchronizacja `horizon_color` z DayNight to mała robota w GDScript za duży efekt spójności.

---

## Podsumowanie — kolejność wdrożenia i koszt całkowity

| # | Shader | Koszt GPU | CPU-build | Priorytet | Bez wzrostu budowy chunku? |
|---|--------|-----------|-----------|-----------|----------------------------|
| 1 | Teren (vertex color + curvature AO + rim + triplanar noise) | Med (~0.2-0.4ms) | **ZERO** | **High** | TAK (ścieżka A, all-GPU) |
| 2 | Trawa wiatr (vertex sway) | Low (~0.1ms) | ZERO | **High** | TAK (wymaga MultiMesh) |
| 3 | Liście sway + translucency | Med (~0.15ms) | znikomy (routing surface) | Medium | TAK |
| 4 | Woda stylizowana | High (~0.4-0.6ms) | ZERO | Medium | TAK |
| 5 | Postaci rim+flash (+outline) | Low (~0.1ms) | ZERO | **High** (flash) | TAK |
| 6 | Distant terrain tint | Low (oszczędza) | ZERO | Medium | TAK |

**Łączny narzut GPU przy wszystkim ON: ~1.0–1.4 ms/klatkę.** Przy steady-state 96 FPS (10.4 ms budżet) zostaje gigantyczny zapas — masz ~6 ms wolne. **Żaden z tych shaderów nie dotyka wąskiego gardła (CPU-build chunku) poza znikomym routingiem surface dla liści/wody.** VRAM total: ~128 KB (dwie małe tekstury noise) — pomijalne wobec 4 GB.

**Sekwencja wdrożenia:** (1) Teren → fundament i odblokowanie ShaderMaterial → (5) rim+flash postaci (gameplay feedback) → (2) trawa wiatr (wymaga migracji na MultiMesh — równolegle) → (3) liście sway → (6) distant tint → (4) woda (ostatnia, najdroższa i najbardziej finicky przez depth linearization).

**Jedna decyzja architektoniczna do podjęcia teraz:** czy AO terenu zostaje all-GPU (ścieżka A, `fwidth` curvature — zero CPU, rekomendowane) czy przejdziesz na `COLOR.a` AO (ścieżka B — lepsze narożniki, ale +4 sample/vertex w budowie chunku, czyli atak na Twoje wąskie gardło). Rekomendacja: zostań przy ścieżce A, dopóki CPU-build chunku jest bottleneckiem.

---

## [postproc] post-processing

Sekcja POST PROCESSING. Wszystkie wartości pod RTX 3050 4 GB / Forward+ / Godot 4.7, pod istniejący stan z CTX. Kolejność włączania na końcu.

---

## 1. SSAO (masz ON: intensity 2.0, radius 0.5 — do korekty)

**Cel wizualny:** Kontaktowe zacienienie w szczelinach między voxelami, pod liśćmi, u podstawy drzew/kamieni. Pogłębia tożsamość voxelową bez per-vertex AO (które słusznie wyłączyłeś — to koszt CPU-build). SSAO przenosi ten koszt na GPU, gdzie masz zapas.

**Implementacja (Godot 4.7 Environment):**
```
ssao_enabled = true
ssao_radius = 0.8           # 0.5 za ciasne dla VOXEL_SIZE 0.5 — kontakt łapie 1.5–2 voxele
ssao_intensity = 1.4        # 2.0 brudzi płaskie ściany; ostre normalne i tak dają twardy AO
ssao_power = 1.5            # gamma krzywej — 1.5 trzyma cień w szczelinie, nie wylewa na ścianę
ssao_detail = 0.5           # default; nie podbijać — łapie szum z mikro-tint
ssao_horizon = 0.06        # odcina self-occlusion na płaskich ścianach (twoje twarde normalne)
ssao_sharpness = 0.98      # ostre krawędzie blura = trzyma voxelowy charakter
ssao_ao_channel_affect = 0.0
```
Globalnie: `RenderingServer` quality przez Project Settings → `rendering/environment/ssao/quality = Medium` (Ultra to overkill i kradnie fillrate na 3050), `adaptive_target = 0.5`, `blur_passes = 2`.

**Koszt:** Low-Med, GPU-render. SSAO na 3050 przy 1080p to ~0.4–0.7 ms na Medium. Bufor depth/normal już masz. Zero kosztu CPU-build. Zapas fillrate jest — steady-state 96 FPS.
**Priorytet:** High (już działa; tylko przestrojenie radius/intensity).

---

## 2. SSIL — ODPUŚĆ

**Cel wizualny:** Kolorowe odbicie światła (zielony refleks od trawy na pień itd.).

**Decyzja:** NIE. SSIL to drugi pełny screen-space pass (osobny od SSAO), ~0.8–1.3 ms na 3050 + dodatkowy bufor (VRAM przy 4 GB to wróg). Stylizacja Cube World nie potrzebuje GI-refleksów; ambient_light_sky_contribution 0.6 + glow już dają „odbite" wrażenie. Koszt/efekt nie broni się na tym GPU.
**Koszt:** Med-High GPU + VRAM. **Priorytet:** Low (świadomie pomijamy).

---

## 3. Bloom / Glow (masz ON: intensity 0.2, bloom 0.05 — podbić selektywnie)

**Cel wizualny:** Miękka poświata na słońcu, refleksach wody, jasnym śniegu — „bajkowy" kontrast Cube World. NIE ma rozmywać całej sceny (twój intensity 0.2 jest bezpieczny, ale bloom 0.05 prawie nic nie robi).

**Implementacja (Godot 4.7 Environment) — tryb HDR threshold (selektywny, nie globalny):**
```
glow_enabled = true
glow_intensity = 0.8
glow_strength = 1.0
glow_bloom = 0.1                       # 0.05→0.1: lekki bloom bazowy, wciąż nie mleko
glow_blend_mode = GLOW_BLEND_MODE_SOFTLIGHT   # softlight = nie wypala bieli, trzyma kolor
glow_hdr_threshold = 1.0               # KLUCZ: tylko >1.0 (HDR, słońce/woda/śnieg) świeci
glow_hdr_scale = 2.0
glow_hdr_luminance_cap = 12.0
glow_levels/1 = false
glow_levels/2 = true                   # średnie poziomy = ciasna poświata
glow_levels/3 = true
glow_levels/4 = true
glow_levels/5 = false                  # wyłącz najszersze — to one robią „mgłę z glow" i kosztują
glow_levels/6 = false
glow_levels/7 = false
```
Threshold 1.0 wymaga, by jasne elementy realnie przekraczały 1.0 w HDR — przy exposure 0.8 słońce/śnieg muszą mieć emission lub wysoki albedo*światło. Jeśli nic nie świeci, zejdź threshold do 0.9.

**Koszt:** Low, GPU-render. Glow to downsample pyramid; ograniczone do poziomów 2-4 = mały koszt (~0.3 ms). Wyłączone poziomy 5-7 oszczędzają i fillrate, i VRAM (mniej mip buforów).
**Priorytet:** High (tani, mocno robi klimat Cube World).

---

## 4. Volumetric Fog (masz ON: density 0.002, albedo ~bluish — dostroić pod stylizację, nie mleko)

**Cel wizualny:** Głębia powietrzna, lekka mgła w dolinach o świcie, nośnik god rays. Ma być SUBTELNA i barwiona przez DayNight, nie biały całun.

**Implementacja (Godot 4.7 Environment):**
```
volumetric_fog_enabled = true
volumetric_fog_density = 0.0025         # 0.002 ok; 0.0025 nieco więcej głębi
volumetric_fog_albedo = Color(0.82,0.87,0.95)   # zostaw, DayNight i tak interpoluje
volumetric_fog_emission = Color(0,0,0)
volumetric_fog_emission_energy = 0.0
volumetric_fog_gi_inject = 0.0          # bez SDFGI i tak 0
volumetric_fog_anisotropy = 0.4         # 0.4 = forward-scatter → god rays od słońca działają
volumetric_fog_length = 64.0            # = render_distance (64 m); nie marnuj froxeli dalej
volumetric_fog_detail_spread = 2.0
volumetric_fog_ambient_inject = 0.2     # 0.2 trzyma mgłę barwioną ambientem, nie szarą
volumetric_fog_sky_affect = 0.5         # mgła nie zjada nieba w 100% — trzyma czytelność
volumetric_fog_temporal_reprojection_enabled = true
volumetric_fog_temporal_reprojection_amount = 0.9
```
Project Settings → `rendering/environment/volumetric_fog/volume_size = 64` i `volume_depth = 64` (default 64×64×64 froxele — NIE podbijać do 128, to skok VRAM i czas).

**Koszt:** Med, GPU-render + stały VRAM (froxel grid 64³ RGBA16F ≈ 8 MB — akceptowalne). Temporal reprojection trzyma koszt per-frame nisko (~0.5–0.8 ms). `length=64` kluczowe — bez tego liczy froxele do horyzontu za darmo.
**Priorytet:** Medium (masz, działa; głównie ograniczyć length i ustawić anisotropy pod god rays).

---

## 5. Atmospheric / Depth Fog (depth fog — NIE włączać razem z dużym volumetric)

**Cel wizualny:** Tani aerial perspective (dystans blednie w kolor nieba). Tańszy niż volumetric, ale mniej „obecny".

**Decyzja:** Masz volumetric ON, więc depth fog trzymaj jako CIENKĄ warstwę uzupełniającą tylko dla aerial perspective na horyzoncie, albo pomiń. Jeśli włączasz:
```
fog_enabled = true
fog_mode = FOG_MODE_DEPTH
fog_density = 0.0008                    # bardzo cienko — volumetric robi główną robotę
fog_sun_scatter = 0.2                   # lekki rozblask wokół słońca (tani fake god ray)
fog_aerial_perspective = 0.6           # KLUCZ: 0.6 wpina kolor nieba w dystans = głębia za grosze
fog_sky_affect = 0.0                   # niebo zostaw czyste
fog_height_enabled = false
```
`fog_aerial_perspective` to najtańszy zysk głębi w całej liście — działa na bazie depth, zero dodatkowych buforów.

**Koszt:** Low, GPU-render (część głównego shadera, brak osobnego passa). aerial_perspective praktycznie darmowy.
**Priorytet:** Medium (aerial_perspective High-value, reszta opcjonalna).

---

## 6. Tone Mapping — AGX zamiast ACES (rekomendacja: zmień)

**Cel wizualny:** Żywe, nasycone kolory Cube World bez wypalania jasnych obszarów (śnieg, słońce na wodzie). ACES (masz) ładnie roluje highlighty, ALE desaturuje i przyciemnia saturację w jasnych partiach — walczy ze stylizacją „żywych kolorów".

**Implementacja (Godot 4.7 Environment):**
```
tonemap_mode = TONE_MAPPER_AGX         # AGX trzyma saturację lepiej w highlightach niż ACES
tonemap_exposure = 0.85                 # 0.8→0.85 lekko jaśniej (AGX ciemniejsze od ACES)
tonemap_white = 6.0                     # zostaw
```
Uwaga: AGX ma charakterystyczny „filmowy" roll-off — jeśli wyjdzie zbyt wyprany/pastelowy względem żywego Cube World, **wróć na ACES** (`TONE_MAPPER_ACES`) i podbij saturację w color grade (sekcja 7, `adjustment_saturation = 1.15`). Obie ścieżki tanie. Dla Cube World stawiam na AGX + lekki saturation boost w adjustment.

**Koszt:** Low/Zero, GPU-render. Tonemap to operacja per-pixel w tym samym passie. Zmiana mappera = 0 dodatkowego kosztu.
**Priorytet:** High (darmowe, duży wpływ na „look").

---

## 7. Color Grading / LUT (Environment.adjustment_* — WŁĄCZ, najtańszy „identity art direction")

**Cel wizualny:** Spójny art-direction look (cieplejsze dnie, chłodniejsze noce/świty), boost saturacji pod Cube World, kontrola kontrastu. Najlepszy stosunek look/koszt po tonemapie.

**Implementacja — wariant A (bez LUT, darmowy, zacznij TUTAJ):**
```
adjustment_enabled = true
adjustment_brightness = 1.0
adjustment_contrast = 1.05             # leciutki kontrast = mniej „płasko"
adjustment_saturation = 1.12          # żywe kolory Cube World; z AGX trzymaj 1.12–1.18
```
**Wariant B (LUT, gdy chcesz pełny grade per pora dnia):**
```
adjustment_color_correction = <GradientTexture/Texture3D LUT>
```
Jak zrobić LUT: wyrenderuj klatkę gry → w GIMP/Photoshop nałóż neutralny LUT strip (np. 16×16×16 unwrap, plik „neutral-lut.png") → pokoloruj (curves/HSL) → zapisz → w Godot zaimportuj jako **Texture3D** (import type: 3D, tile size 16) LUB jako poziomy strip do GradientTexture. Podłącz pod `adjustment_color_correction`.

**Blend per biom/pora:** Godot nie miksuje dwóch LUT natywnie w Environment. Opcje:
- **Tania:** DayNight.gd przełącza `adjustment_color_correction` na inny Texture3D w keyframach pory dnia (twardy swap; przy 240 s dobie niewidoczny).
- **Płynna:** trzymaj jeden LUT, a porę dnia rób przez `adjustment_saturation`/`adjustment_contrast` interpolowane w DayNight.gd (już interpolujesz inne property — dopisz te dwa). Tańsze i wystarcza.

**Koszt:** Wariant A: Zero (część tonemapy). Wariant B: Low GPU + ~mały VRAM (Texture3D 16³ RGBA8 ≈ 16 KB — pomijalne). LUT to jedno texture fetch per pixel.
**Priorytet:** High (wariant A od razu; wariant B gdy ustabilizujesz paletę).

---

## 8. Vignette (Godot 4.7 nie ma w Environment — przez CompositorEffect lub quad)

**Cel wizualny:** Subtelne ściemnienie rogów — skupia wzrok na postaci, pogłębia klimat. MUSI być ledwo widoczna.

**Implementacja — wariant tani (zalecany): ColorRect + shader na CanvasLayer (masz już HUD CanvasLayer):**
```glsl
shader_type canvas_item;
uniform float vignette_intensity = 0.35;
uniform float vignette_radius = 0.75;
uniform vec4 vignette_color : source_color = vec4(0.0,0.0,0.0,1.0);
void fragment() {
    vec2 uv = SCREEN_UV - 0.5;
    float d = length(uv) * 1.41421;          // 0 w centrum, ~1 w rogach
    float v = smoothstep(vignette_radius, 1.0, d) * vignette_intensity;
    COLOR = vec4(vignette_color.rgb, v);
}
```
ColorRect full-rect, `mouse_filter = IGNORE`, na wierzchu świata, pod HUD-em. Zero dodatkowego render targetu.

**Wariant CompositorEffect:** możliwy (compositor RD pass), ale dla zwykłej winiety to przerost — quad/canvas_item jest tańszy i prostszy. CompositorEffect zostaw na efekty wymagające depth/screen tekstury (sekcja 11).

**Koszt:** Low, GPU-render (jeden full-screen quad, prosty fragment). Zero VRAM dodatkowego.
**Priorytet:** Medium (tani klimat; nie krytyczny).

---

## 9. Screen Space Shadows (light contact shadows — WŁĄCZ, tanio)

**Cel wizualny:** Kontaktowy cień tam, gdzie shadow map gubi szczegół — styk nóg postaci z ziemią, drobne propy (trawa/grzyby 0.25 m), liście. Łata brak rozdzielczości cienia kierunkowego.

**Implementacja (Godot 4.7 — to property DirectionalLight3D, NIE compositor):**
```
# na DirectionalLight3D (słońce):
shadow_enabled = true
# Project Settings → rendering/lights_and_shadows/positional_shadow/...  oraz:
light_shadow_caster_mask              # bez zmian
# Screen Space Shadows:
Project Settings → rendering/2d? NIE. To:
DirectionalLight3D ma w 4.x: brak bezpośredniego SSS toggle w inspektorze starych wersji,
ale Godot 4.7 udostępnia kontaktowe cienie przez:
```
W Godot 4.7 screen-space contact shadows konfigurujesz przez Project Settings:
```
rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality = Medium
```
i na samym świetle parametr **`shadow_blur`** masz (1.5). Jeśli build ma SSS jako property światła (`light_shadow_*`/contact), ustaw długość kontaktu na ~0.05–0.1 m. Jeśli Twoja wersja nie eksponuje SSS na DirectionalLight — **pomiń, nie kombinuj z compositorem dla tego** (koszt/zysk słaby).

**Realna rekomendacja zamiast niepewnego SSS:** zamiast SSS dobierz shadow:
```
directional_shadow_max_distance = 80     # 120→80: gęstsze teksele cienia BLIŻEJ = ostrzejszy kontakt przy postaci
shadow_blur = 1.0                        # 1.5→1.0 ostrzej, mniej „wycieku"
DirectionalLight3D.shadow_normal_bias = 1.0
DirectionalLight3D.shadow_bias = 0.03
blend_splits = true
```
Zmniejszenie max_distance z 120 na 80 da Ci więcej rozdzielczości cienia w strefie gry (render_distance i tak 64 m) — to lepszy zysk niż SSS na tym GPU.

**Koszt:** SSS (jeśli jest): Low-Med GPU (screen-space trace). Strojenie shadow distance: Zero (przesuwa teksele, nie dokłada kosztu).
**Priorytet:** Medium — najpierw zjedź `max_distance=80` (darmowe, pewny zysk), SSS tylko jeśli wersja eksponuje property.

---

## 10. Subtle DoF (depth of field — bardzo subtelnie, tylko far)

**Cel wizualny:** Leciutkie rozmycie dalekiego tła → głębia, „miniaturkowy" klimat Cube World. NIE near blur (rozmyłby postać/akcję).

**Implementacja (Godot 4.7 — Camera3D attributes / Environment w zależności od setupu; w 4.7 przez `CameraAttributesPractical`):**
```
# CameraAttributesPractical na Camera3D:
dof_blur_far_enabled = true
dof_blur_far_distance = 55.0           # zaczyna się tuż przed końcem render_distance (64 m)
dof_blur_far_transition = 20.0         # łagodne wejście
dof_blur_amount = 0.06                  # BARDZO mało; >0.1 wygląda jak wada wzroku
dof_blur_near_enabled = false           # NIGDY near — postać/akcja na pierwszym planie
```
Project Settings → `rendering/camera/depth_of_field/depth_of_field_bokeh_shape = Circle`, `depth_of_field_bokeh_quality = Low` (Med/High kradną fillrate; przy amount 0.06 i tak nie widać różnicy).

**Koszt:** Low-Med, GPU-render. DoF to blur pass; quality Low + tylko far = ~0.3–0.5 ms. Przy 4 GB Low quality trzyma VRAM/fillrate w ryzach.
**Priorytet:** Low (miły akcent, najmniej krytyczny; włącz na końcu, łatwo wyłączyć jeśli zżera FPS).

---

## 11. God Rays / Light Shafts (przez volumetric fog — masz już 90% za darmo)

**Cel wizualny:** Promienie słońca przez korony drzew, smugi o świcie/zachodzie. Sygnaturowy efekt Cube World o złotej godzinie.

**Implementacja — droga TANIA (zalecana, używa volumetric z sekcji 4):**
God rays w Godot 4.7 wychodzą NATURALNIE z volumetric fog gdy:
```
volumetric_fog_anisotropy = 0.4        # (już ustawione w sekcji 4) forward-scatter robi smugi do kamery
# słońce: DirectionalLight3D
light_energy = 1.0                      # mocne światło = wyraźniejsze smugi w mgle
# o świcie/zachodzie w DayNight.gd podbij chwilowo:
volumetric_fog_density → 0.0035 w keyframie świtu/zachodu (interpolujesz już density? dodaj)
volumetric_fog_anisotropy → 0.6 w keyframie złotej godziny (ostrzejsze smugi)
```
Cienie kierunkowe MUSZĄ być ON (są) — to one wycinają smugi między liśćmi/koronami (volumetric fog respektuje shadow map słońca). To jest cały sekret: shadow map + anisotropy + density.

**Droga DROGA (NIE zalecana na 3050):** osobny radial-blur god ray pass przez CompositorEffect (sample od pozycji słońca). Drugi full-screen pass = ~0.6–1.0 ms + screen texture. Volumetric już to robi taniej i fizyczniej. **Pomiń compositor god rays.**

**Koszt:** Zero dodatkowego (jedzie na volumetric z sekcji 4 + istniejących cieniach). Tylko 2 wartości interpolowane w DayNight.gd.
**Priorytet:** Medium (duży „wow" o złotej godzinie, koszt zerowy ponad volumetric).

---

## 12. Temporal AA vs MSAA — dla 4 GB i VOXELI: MSAA 2x, NIE TAA

**Cel wizualny:** Wygładzić schodki na ostrych krawędziach voxeli/sylwetkach BEZ rozmycia tożsamości voxelowej i BEZ ghostingu.

**Decyzja i uzasadnienie (kluczowe dla TWOJEGO projektu):**
- **TAA (`viewport.use_taa = true`):** rozmywa w ruchu i daje GHOSTING — a Ty masz ostre, wysokokontrastowe krawędzie voxeli + mikro-tint (szum) + przyszłe animowane propy. To najgorszy możliwy materiał dla TAA: ghosting na każdej krawędzi sześcianu, „smużenie" przy ruchu kamery. **NIE używaj TAA.**
- **MSAA 2x (`viewport.msaa_3d = MSAA_2X`):** wygładza GEOMETRYCZNE krawędzie (a Twój look to właśnie twarde krawędzie geometrii) bez dotykania wnętrza ścian, bez rozmycia, bez ghostingu. Idealne pod voxele.

**Implementacja (Godot 4.7 Viewport / Project Settings):**
```
rendering/anti_aliasing/quality/msaa_3d = MSAA_2X      # 2x wystarcza; 4x kosztuje ~2× MSAA na 3050
rendering/anti_aliasing/quality/use_taa = false
rendering/anti_aliasing/quality/screen_space_aa = SCREEN_SPACE_AA_DISABLED   # FXAA rozmydla, nie trzeba
rendering/scaling_3d/mode = bilinear
rendering/scaling_3d/scale = 1.0                        # NIE schodź; przy 4 GB raczej trzymaj natywne 1080p
```
Jeśli FPS spadnie po włączeniu reszty efektów: zanim ruszysz MSAA, zejdź `scaling_3d/scale = 0.85` (FSR-like upscale) — taniej niż utrata AA. MSAA 2x na 3050 przy 1080p to ~0.5–0.9 ms + ~bufor MSAA (2× sample = wzrost VRAM render targetu o ~30-40 MB przy 1080p; akceptowalne w 4 GB jeśli trzymasz froxele/glow w ryzach jak wyżej).

**Koszt:** MSAA 2x: Med, GPU-render + VRAM render-target (2 sample). Na 4 GB to największy pojedynczy konsument VRAM z tej listy po volumetric — dlatego 2x, nie 4x.
**Priorytet:** High (AA jest konieczne dla czytelności sylwetek; MSAA 2x to właściwy wybór, nie TAA).

---

## KOLEJNOŚĆ WŁĄCZANIA dla 4 GB (od pewnego zysku do opcjonalnych)

| # | Krok | Koszt | VRAM | Priorytet |
|---|------|-------|------|-----------|
| 1 | Tonemap AGX + exposure 0.85 | Zero | 0 | High |
| 2 | adjustment_enabled (sat 1.12, contrast 1.05) | Zero | 0 | High |
| 3 | SSAO re-tune (radius 0.8, intensity 1.4, power 1.5, horizon 0.06) | Low | 0 | High |
| 4 | Glow HDR threshold 1.0, levels 2-4, softlight | Low | mały | High |
| 5 | shadow max_distance 120→80, blur 1.0 | Zero | 0 | High |
| 6 | fog_aerial_perspective 0.6 (depth fog cienki) | Low | 0 | Medium |
| 7 | Volumetric: length=64, anisotropy 0.4, ambient_inject 0.2 | Med | ~8 MB | Medium |
| 8 | God rays = anisotropy/density w DayNight keyframach | Zero | 0 | Medium |
| 9 | MSAA 2x (use_taa=false, FXAA off) | Med | ~30-40 MB | High |
| 10 | Vignette (canvas_item shader) | Low | 0 | Medium |
| 11 | LUT Texture3D (gdy paleta ustabilizowana) | Low | ~16 KB | High* |
| 12 | Subtle DoF far (amount 0.06, quality Low) | Low-Med | mały | Low |

**Co WŁĄCZYĆ na pewno (4 GB):** 1-5 (zero/low koszt, duży look), 9 (MSAA 2x — czytelność), 4 (glow), 7 (volumetric ograniczony length=64).
**Co ODPUŚCIĆ:** SSIL (sekcja 2), TAA (sekcja 12), CompositorEffect god rays (sekcja 11), DoF near, MSAA 4x, volume_size 128.
**Czerwona linia VRAM:** największy łączny pobór to MSAA 2x render target (~30-40 MB) + volumetric froxele (~8 MB) + glow mipy. Przy 1080p natywnym i powyższych ograniczeniach mieścisz się; jeśli zabraknie — najpierw `scaling_3d/scale = 0.85`, dopiero potem rezygnacja z MSAA.

---

**Jeden sanity-check do zweryfikowania w Twoim repo (nie zgaduję):** czy DoF/DirectionalLight SSS w sekcjach 9-10 to property eksponowane w Twojej wersji buildu. Mogę sprawdzić pliki sceny/skryptów w `C:\Users\oskar\Downloads\Cube World Alpha` — wskaż `.tscn` z WorldEnvironment i `DayNight.gd`, zweryfikuję nazwy property 1:1 i dopiszę gotowe linie do wklejenia.

---

## [environment] environment alive

That directory is the actual retail Cube World Alpha game (binaries), not your Godot project — no source to anchor to there. The brief in the prompt is the source of truth for node structure (`DayNight.gd`, voxel chunks, `WorldEnvironment`). I'll write everything against that, with concrete node paths you can wire in. No further file reads needed.

Here is the full ENVIRONMENT POLISH section — "żywy świat" — designed for Godot 4.7, Forward+, RTX 3050 4 GB.

---

# ENVIRONMENT POLISH — "Żywy świat"

## Założenia kosztowe (dla TEGO GPU)

Twoje wąskie gardło to **CPU single-thread build chunków**, nie GPU fill. To kluczowe rozróżnienie dla tej sekcji: **prawie wszystkie efekty tu są GPU-render i NIE dotykają budowy chunku** — masz na nie zapas. Wyjątek to wiatr trawy/drzew, który chcę wpiąć w istniejący mesh BEZ przebudowy (czysto w shaderze, koszt = vertex shader na GPU, zero CPU-build).

Twardy limit 4 GB VRAM oznacza: particle pools małe (setki, nie tysiące), kulling do promienia gracza (masz `render_distance 4` = 64 m — używam tego jako budżetu), wiązanie nocnych/dziennych efektów z `DayNight.gd` żeby nie płacić za wyłączone.

Globalny strażnik budżetu (jeden AutoLoad albo metoda w istniejącym managerze):

```gdscript
# FXBudget.gd — globalny mnożnik jakości, czytany przez wszystkie emittery
@export var fx_scale: float = 1.0   # 1.0 desktop / 0.5 gdy FPS < 60
# w _process: jeśli Engine.get_frames_per_second() < 55 przez 2 s -> fx_scale = 0.5
```

---

## 1. Wiatr trawy (vertex wind na propach trawy/kwiatów)

**Cel wizualny:** drobne propy trawy/kwiatów (~0.25 m BoxMesh) kołyszą się falą wiatru — góra meshu wychylana, dół przyklejony do ziemi. Tożsamość voxelowa zachowana (sześcian się pochyla, nie deformuje w "glut").

**Implementacja (Godot 4.7, konkretnie):**
Twoje propy to osobne `MeshInstance3D` (BoxMesh) parentowane do chunku. **Przerzuć je na jeden `MultiMeshInstance3D` per chunk** (krytyczne — patrz koszt) i nadaj wspólny `ShaderMaterial`. Wiatr w world-space, więc fala jest spójna między chunkami.

```glsl
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
// vertex_color jak w terenie:
// w materiale: vertex_color_use_as_albedo via ALBEDO = COLOR.rgb (poniżej)

uniform float wind_strength = 0.12;   // metry wychylenia na szczycie
uniform float wind_speed    = 1.3;
uniform vec2  wind_dir      = vec2(0.8, 0.6); // znormalizuj w kodzie
uniform float sway_freq     = 0.35;   // przestrzenna częstotliwość fali

void vertex() {
    // maska: tylko górne wierzchołki się ruszają (dół przyklejony)
    // BoxMesh 0.25 m -> lokalne Y w [-0.125, 0.125]; mapujemy na 0..1
    float h = clamp((VERTEX.y + 0.125) / 0.25, 0.0, 1.0);
    float mask = h * h; // kwadratowo: korzeń sztywny, czubek miękki

    vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float phase = dot(wpos.xz, normalize(wind_dir)) * sway_freq
                + TIME * wind_speed;
    // dwie składowe = mniej "metronomu"
    float wave = sin(phase) * 0.7 + sin(phase * 2.3 + 1.7) * 0.3;

    vec3 offset = vec3(normalize(wind_dir).x, 0.0, normalize(wind_dir).y)
                  * wave * wind_strength * mask;
    VERTEX += (inverse(mat3(MODEL_MATRIX)) * offset); // offset world->local
}

void fragment() {
    ALBEDO = COLOR.rgb;          // vertex color jak teren
    ROUGHNESS = 1.0;
    METALLIC  = 0.0;
}
```

Jeden globalny `TIME` i jednolite uniformy = ta sama fala wszędzie. `wind_dir` możesz powoli obracać z `DayNight.gd` (porywy) — ale to opcja, nie wymóg.

**Koszt:** **Low — GPU-render**, ale **TYLKO po konsolidacji w MultiMesh**. Uzasadnienie 4 GB: dziś każdy prop to osobny `MeshInstance3D` = osobny draw call; przy gęstej trawie w 64 m to setki–tysiące draw calls (CPU-bound, dławi się zanim VRAM puchnie). MultiMesh per chunk redukuje to do ~1 draw call/chunk. Vertex shader na BoxMesh (8 wierzchołków) jest pomijalny dla 3050. VRAM: jeden buffer instancji per chunk, kilkadziesiąt KB.

**Priorytet: High.** Najmocniejszy "ożywiacz" świata na jednostkę kosztu, a konsolidacja w MultiMesh i tak jest wygraną wydajnościową niezależnie od wiatru.

---

## 2. Kołysanie drzew (vertex wind na koronach/liściach)

**Cel wizualny:** korony drzew kołyszą się wolniej i z większą amplitudą niż trawa; pień nieruchomy. Sześcienne liście pochylają się grupowo, nie rozjeżdżają.

**Implementacja:** Problem — drzewa masz **wpisane w voxele chunku**, więc nie da się ich animować bez wyodrębnienia. Dwie drogi:

- **Tania (zalecana):** liście/korony NIE są częścią mesha terenu — wypiekane jako osobny `ArrayMesh` "foliage" per chunk (i tak warto, bo liście mają inny materiał). Nadajesz mu shader poniżej. Pień zostaje w terenie.
- Jeśli liście muszą zostać w mesh terenu: rozróżnij je w shaderze terenu przez próg koloru (zielony liścia) — brzydkie i ryzykowne, **odradzam**.

```glsl
shader_type spatial;
render_mode cull_back;

uniform float tree_wind_strength = 0.18;
uniform float tree_wind_speed    = 0.7;   // wolniej niż trawa
uniform vec2  wind_dir           = vec2(0.8, 0.6);
uniform float trunk_y;                     // world-Y podstawy korony, ustaw per drzewo/chunk

void vertex() {
    vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // maska wysokości: im wyżej nad podstawą korony, tym większy ruch
    float hmask = clamp((wpos.y - trunk_y) / 4.0, 0.0, 1.0);
    float phase = dot(wpos.xz, normalize(wind_dir)) * 0.15 + TIME * tree_wind_speed;
    float sway  = sin(phase) + 0.3 * sin(phase * 2.7);
    vec3 dir = vec3(normalize(wind_dir).x, 0.0, normalize(wind_dir).y);
    VERTEX += inverse(mat3(MODEL_MATRIX)) * dir * sway * tree_wind_strength * hmask;
}
```

**Koszt:** **Low–Med — GPU-render.** Vertex shader na meshu foliage (mało wierzchołków per drzewo). Koszt "Med" pojawia się tylko jeśli wyodrębnienie foliage zwiększa **CPU-build chunku** — a to Twój wróg. Mitygacja: foliage buduj raz przy generacji chunku, bez per-vertex AO, jeden surface. VRAM: znikomy.

**Priorytet: Medium.** Świetny efekt, ale wymaga refaktoru wypiekania (wyodrębnienie liści) — to dotyka CPU-build, więc rób po trawie.

---

## 3. Spadające liście (GPUParticles3D)

**Cel wizualny:** kilka liści leniwie opada i wiruje w okolicy gracza, gęściej pod drzewami. Stylizacja: sześcienne/płaskie quady w kolorach liści.

**Implementacja:** jeden `GPUParticles3D` podążający za graczem (parentuj do gracza albo przesuwaj `global_position` co klatkę), `local_coords = false`.

```
GPUParticles3D:
  amount = 40            # * fx_scale
  lifetime = 6.0
  preprocess = 3.0
  visibility_aabb = ręczny AABB ~ Vector3(40,20,40) wokół gracza
  draw_pass_1 = QuadMesh 0.25x0.25 (lub mały BoxMesh dla voxel look)
ParticleProcessMaterial:
  emission_shape = BOX, extents (20, 10, 20)   # nad/wokół gracza
  direction = (0,-1,0), spread = 30
  gravity = (0.3, -0.8, 0.2)    # lekki dryf wiatru w X/Z, zgodny z wind_dir
  initial_velocity 0.4..1.0
  angular_velocity 40..90 deg/s  # wirowanie
  damping 0.2
  color_ramp: warianty zieleni/żółci/brązu
```

Materiał liścia: `billboard = PARTICLES` (faceuje kamerę) lub off dla pełnego voxel-look. Wiąż `amount` z `DayNight` tylko opcjonalnie (jesień = więcej).

**Koszt:** **Low — GPU.** 40 cząstek to nic dla 3050 (GPU sim). 1 draw pass = 1 draw call. Uzasadnienie 4 GB: jeden mały atlas/quad, VRAM pomijalny. Ryzyko zerowe dopóki `amount` < ~200.

**Priorytet: Medium.**

---

## 4. Motyle (GPUParticles3D, dzień)

**Cel wizualny:** kilka motyli trzepocze nisko nad trawą/kwiatami w dzień. Kolorowe, nieregularny lot.

**Implementacja:** `GPUParticles3D` podążający za graczem, **włączany tylko w dzień** przez `DayNight.gd`.

```
GPUParticles3D (butterflies):
  amount = 12 * fx_scale
  lifetime = 8.0
  one_shot = false, local_coords = false
ParticleProcessMaterial:
  emission_shape = BOX extents (25, 2, 25)  # nisko, przy ziemi
  gravity = (0,0,0)
  initial_velocity 0.5..1.2
  # trzepot/zygzak: turbulence
  turbulence_enabled = true
  turbulence_noise_strength = 1.5
  turbulence_noise_scale = 2.0
  turbulence_influence = (0.8,0.8,0.8)
  draw_pass_1 = mały QuadMesh, billboard = PARTICLES
  color_ramp = żywe kolory (pomarańcz/błękit/biały)
```

Wpięcie w DayNight:
```gdscript
# w DayNight.gd, tam gdzie liczysz fazę doby (0..1):
$Butterflies.emitting = is_day            # np. faza in [0.25, 0.75]
$Fireflies.emitting   = is_night          # faza in [0.85..0.15]
```

**Koszt:** **Low — GPU.** 12 cząstek + turbulence (tani noise GPU). Draw call: 1. VRAM pomijalny. Wyłączane w nocy = zero kosztu połowę doby.

**Priorytet: Low–Medium.** Czysty urok, niski koszt — dobry "tani win".

---

## 5. Ptaki (proste, daleki plan)

**Cel wizualny:** 2–4 ptaki krążą wysoko, sporadycznie. Sylwetki, nie detal.

**Implementacja:** **NIE particles** (chcesz spójny tor lotu). Najtaniej: `MultiMeshInstance3D` z 3–4 instancjami + skrypt przesuwający je po okręgu/`Curve3D` wokół gracza, z prostym "flapem" przez vertex shader (sinus na skrzydłach) albo dwuklatkową animacją skali Y.

```gdscript
# Birds.gd — 4 ptaki po okręgu r=30 m, wysokość 25 m, wolny obrót
func _process(dt):
    t += dt * 0.1
    for i in birds.size():
        var a = t + i * TAU / birds.size()
        var p = player.global_position + Vector3(cos(a)*30, 25, sin(a)*30)
        multimesh.set_instance_transform(i, Transform3D(basis_facing(a), p))
```

Flap w shaderze ptaka: `VERTEX.y += sin(TIME*8.0 + INSTANCE_CUSTOM.x) * abs(VERTEX.x) * 0.3` (skrzydła = duży |x|, korpus = mały).

**Koszt:** **Low — GPU-render + znikomy CPU** (4 transformy/klatkę). 1 draw call (MultiMesh). VRAM pomijalny.

**Priorytet: Low.** Miły akcent tła, ale najmniejszy wpływ na "życie" sceny w zasięgu gracza.

---

## 6. Cząsteczki ambient — kurz w słońcu (god-dust)

**Cel wizualny:** delikatne drobinki kurzu unoszące się i lśniące w świetle dnia — natychmiast dodaje "atmosfery" voxelowemu lasowi.

**Implementacja:** `GPUParticles3D` wokół gracza, bardzo wolne, emisyjny materiał (łapią glow który masz ON).

```
GPUParticles3D (dust):
  amount = 60 * fx_scale
  lifetime = 12.0
  visibility_aabb ~ 30 m wokół gracza
ParticleProcessMaterial:
  emission_shape = BOX extents (15, 8, 15)
  gravity = (0, -0.02, 0)      # prawie zawieszone
  initial_velocity 0.02..0.08
  turbulence_enabled = true, noise_strength 0.3, scale 1.0
  draw_pass_1 = QuadMesh 0.04x0.04, billboard = PARTICLES
material (StandardMaterial3D na quadzie):
  emission_enabled = true, emission_energy ~1.5 (łapie Twój glow intensity 0.2)
  transparency = ALPHA, alpha ~0.3
```

Intensywność wiąż z `DayNight`: `emission_energy` i `amount` w dzień, ścisz do zera nocą.

**Koszt:** **Low–Med — GPU.** 60 transparentnych quadów = overdraw, ale przy 0.04 m i alpha 0.3 fill jest minimalny; 3050 to udźwignie. Uwaga: transparency + glow = lekki koszt blendu. Trzymaj `amount` < 100. VRAM pomijalny.

**Priorytet: Medium.** Bardzo wysoki zwrot atmosferyczny, zwłaszcza w lesie przy promieniach słońca.

---

## 7. Świetliki nocą (emisyjne particles, TYLKO noc)

**Cel wizualny:** migoczące punkty światła nisko nad ziemią po zmroku. Najsilniejszy efekt "magii" nocy.

**Implementacja:** `GPUParticles3D` przy ziemi, emisyjne, **pulsujące alpha**, włączane wyłącznie nocą przez `DayNight.gd`.

```
GPUParticles3D (fireflies):
  amount = 30 * fx_scale
  lifetime = 5.0
  emitting = (sterowane z DayNight: tylko noc)
ParticleProcessMaterial:
  emission_shape = BOX extents (18, 1.5, 18)   # nisko
  gravity = (0,0,0)
  initial_velocity 0.1..0.3
  turbulence_enabled = true, noise_strength 0.6
  draw_pass_1 = QuadMesh 0.06x0.06, billboard = PARTICLES
```
Migotanie — shader na quadzie (lub emission ramp po HUE):
```glsl
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled;
void fragment() {
    float flick = 0.5 + 0.5 * sin(TIME * 3.0 + INSTANCE_CUSTOM.x * 30.0);
    EMISSION = vec3(0.9, 1.0, 0.4) * flick * 3.0;
    ALPHA = flick;
}
```
`blend_add` + glow ON = mocny bloom punktów. Brak światła rzeczywistego (OmniLight per firefly zabiłby GPU) — symulacja emisją wystarczy.

**Koszt:** **Low — GPU.** 30 additive quadów, zero real-lights. Krytyczne dla 4 GB: **NIE dawaj OmniLight3D na świetliki** (każde światło = koszt cieni/forward+ clustera). Wyłączane w dzień = zero kosztu połowę doby. VRAM pomijalny.

**Priorytet: High.** Najwyższy zwrot wizualny dla scen nocnych, a koszt znikomy dzięki czystej emisji.

---

## 8. Pyłek / pollen unoszący się (dzień, łąki)

**Cel wizualny:** drobny złoty pyłek dryfuje nad trawą/kwiatami w dzień — odróżnia łąki od lasu.

**Implementacja:** wariant kurzu (#6) ale złoty, niżej i wolniej. Można współdzielić jeden node z dust, sterując `color_ramp`/wysokością przez tryb biomu, albo osobny:

```
GPUParticles3D (pollen):
  amount = 35 * fx_scale, lifetime 10.0
  emission BOX extents (12, 3, 12), nisko nad trawą
  gravity (0, 0.01, 0)  # leciutko w górę
  initial_velocity 0.05..0.15, turbulence noise_strength 0.4
  draw_pass quad 0.03, emission żółto-złota, alpha 0.25
```

**Koszt:** **Low — GPU.** Jak dust. Jeśli aktywny RAZEM z dust i pollen → sumuj amount, trzymaj łączny budżet transparentnych quadów < ~150 w kadrze.

**Priorytet: Low.** Ładny detal biomu, ale efekt nakłada się z dust (#6) — rób tylko jeśli masz wyraźne łąki.

---

## 9. Kurz spod stóp / przy ruchu (one-shot, gracz)

**Cel wizualny:** obłoczek kurzu gdy gracz biegnie/ląduje na piasku/ziemi. Sprzężenie ruchu ze światem.

**Implementacja:** `GPUParticles3D` na graczu, `one_shot = false`, ale `emitting` sterowane prędkością i typem bloku pod stopami (masz typy: piasek/ziemia/trawa).

```gdscript
# w kontrolerze gracza:
var grounded_block = get_block_below()   # już masz dane voxeli
$FootDust.emitting = is_moving and grounded_block in [SAND, DIRT]
$FootDust.process_material.color = dust_color_for(grounded_block)
```
```
GPUParticles3D (footdust):
  amount = 8, lifetime 0.6, local_coords = false
  emission SPHERE radius 0.2 przy stopach
  initial_velocity 0.3..0.8, gravity (0,-1,0), spread wide
  scale_curve: rośnie potem znika
```

**Koszt:** **Low — GPU.** 8 cząstek burst, emituje tylko podczas ruchu na sypkim podłożu. VRAM pomijalny.

**Priorytet: Medium.** Tani, mocno zwiększa "weight"/feedback ruchu — dobre uzupełnienie braku camera bob/shake.

---

## 10. Zmarszczki na wodzie (vertex + normal shader)

**Cel wizualny:** powierzchnia wody faluje i lśni — dziś woda to płaski voxel z vertex color. Najmocniejszy upgrade pojedynczego typu bloku.

**Implementacja:** wyodrębnij górne ściany wody do osobnego mesha z dedykowanym `ShaderMaterial` (woda i tak chce innego materiału — przezroczystość/odbicie). Falowanie = vertex Gerstner-lite, lśnienie = animowana normalna.

```glsl
shader_type spatial;
render_mode cull_back, diffuse_lambert;
uniform vec4 water_color : source_color = vec4(0.2,0.45,0.6,0.75);
uniform float wave_amp = 0.04;   // małe, voxel zostaje płaski-ish
uniform float wave_speed = 1.0;

void vertex() {
    vec3 w = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    float h = sin(w.x*1.5 + TIME*wave_speed)*0.5
            + sin(w.z*1.9 + TIME*wave_speed*1.3)*0.5;
    VERTEX.y += h * wave_amp;
}
void fragment() {
    // animowana normalna -> migotanie specular pod słońcem (god-rays-lite)
    float nx = cos(VERTEX.x*2.0 + TIME)*0.15;
    float nz = cos(VERTEX.z*2.0 + TIME*1.2)*0.15;
    NORMAL = normalize(NORMAL + vec3(nx,0.0,nz));
    ALBEDO = water_color.rgb;
    ALPHA  = water_color.a;
    ROUGHNESS = 0.1;   // lśni
    METALLIC  = 0.0;
    SPECULAR  = 0.5;
}
```
Trzymaj `wave_amp` małe (0.04 m), żeby woda nie straciła voxelowej płaskości. Przezroczystość pokaże dno — ładnie z Twoim volumetric fog.

**Koszt:** **Med — GPU-render** (transparency = sortowanie + ewentualny depth-prepass; vertex sin tani). Drobny CPU-build przy wyodrębnieniu wody — minimalny, woda to mało ścian. Na 3050 OK dopóki tafle wody nie są ogromne (overdraw z alpha). VRAM pomijalny.

**Priorytet: High.** Statyczna woda to teraz najsłabszy element "żywego świata"; ten jeden shader daje nieproporcjonalnie duży skok jakości.

---

## Plan wdrożenia wg ROI (priorytety zbiorczo)

| # | Efekt | Koszt | Typ | Priorytet | Warunek doby |
|---|-------|-------|-----|-----------|--------------|
| 1 | Wiatr trawy (+MultiMesh) | Low | GPU (po refaktorze draw calls) | **High** | — |
| 7 | Świetliki | Low | GPU | **High** | tylko noc |
| 10 | Woda falująca | Med | GPU | **High** | — |
| 6 | Kurz w słońcu | Low–Med | GPU | Medium | dzień |
| 2 | Kołysanie drzew | Low–Med | GPU (+CPU-build foliage) | Medium | — |
| 3 | Spadające liście | Low | GPU | Medium | — |
| 9 | Kurz spod stóp | Low | GPU | Medium | — |
| 4 | Motyle | Low | GPU | Low–Med | dzień |
| 8 | Pyłek/pollen | Low | GPU | Low | dzień |
| 5 | Ptaki | Low | GPU | Low | dzień |

**Kolejność robienia:** 1 → 10 → 7 → 6 → 2 → reszta.
Uzasadnienie: #1 zmusza do konsolidacji propów w MultiMesh (wygrana wydajnościowa + odblokowuje wiatr), #10 i #7 to największe pojedyncze skoki jakości za GPU-only koszt, dopiero potem #2 który dotyka Twojego wrażliwego CPU-build.

**Globalne zabezpieczenia 4 GB (obowiązkowe):**
- Wszystkie `amount` mnożone przez `fx_scale` (spada do 0.5 gdy FPS < 55).
- Wszystkie particle emittery podążają za graczem (`local_coords=false`, ręczny `visibility_aabb` ~30–40 m) — nigdy nie emituj w całym świecie.
- Łączny budżet transparentnych/additive quadów w kadrze: trzymaj **< ~150** (dust+pollen+fireflies+leaves razem).
- ZERO real-lights na particles (świetliki = emisja, nie OmniLight).
- Dzień/noc gating przez `DayNight.gd`: świetliki tylko noc; motyle/pyłek/dust tylko dzień — to oszczędza ~50% kosztu FX uśrednionego po dobie.

---

Relevant path: brief node `DayNight.gd` is the integration point for all day/night gating (sekcje #4, #6, #7, #8). Note: `C:\Users\oskar\Downloads\Cube World Alpha` contains only the retail game binaries, not your Godot project — none of this could be anchored to actual source files; everything above is written against the architecture described in your brief. If you point me at the real Godot project folder I can wire these to exact node paths and your existing `DayNight.gd` keyframe structure.

---

## [teren-art] terrain art direction

I now have the full picture: single `FastNoiseLite` Perlin FBM (freq 0.007, 4 octaves) mapped linearly to height, hard biome thresholds by Y only, no temperature/humidity, features placed by `feature_hash`. Everything is CPU-build. My recommendations target exactly this pipeline.

---

# TERRAIN ART DIRECTION — Cube World voxel RPG (Godot 4.7, voxel 0.5 m, RTX 3050 4 GB)

Baza faktyczna (z `VoxelWorld.gd` / `Chunk.gd`): jeden `_noise` Perlin FBM `frequency=0.007, octaves=4, lacunarity=2.0, gain=0.5`, mapowany LINIOWO: `surface_y = round(24 + n*64)`, n∈[0,1]. Biomy są wybierane WYŁĄCZNIE po Y (`_block_for`: BEACH≤26, ROCK≥56, SNOW≥68). Brak mapy temperatury/wilgotności, brak ridged/erozji, brak domain warpingu, brak landmarków. To powoduje dokładnie ten „falujący jednostajny teren”, o który pytasz: pojedynczy FBM Perlina = miękkie, izotropowe, samopodobne wzgórza bez grani i klifów.

UWAGA o koszcie: praktycznie WSZYSTKO tutaj to CPU-build (generacja w `surface_height` / `_generate_data` / `_place_features`). Twoje wąskie gardło to czas budowy chunku na jednym wątku, nie GPU. Dlatego przy każdej rekomendacji podaję ile DODATKOWYCH próbek szumu na kolumnę dokładam (1 kolumna = 1024 wywołań/chunk × octaves) i jak to ograniczyć.

Mikro-benchmark do kalibracji: obecnie 1 `surface_height` = 1 `get_noise_2d` z 4 oktawami = ~4 próbki Perlina, ×1024 kolumn = ~4096 próbek/chunk. To Twój punkt odniesienia „1×”.

---

## 1) WARIACJA TERENU — warstwy szumu, ridged, domain warping

**Cel wizualny**: zlikwidować jednostajne „faliste” wzgórza. Chcemy: rozległe niziny i płaskowyże (kontynentalność), ostre grzbiety górskie (ridged), poszarpane doliny (erozja), oraz zerwanie regularności siatki szumu (domain warp).

**Implementacja (Godot 4.7, konkretnie)** — zamień jeden `_noise` na 4 wyspecjalizowane `FastNoiseLite` + warp. W `_setup_noise()`:

```gdscript
# A) KONTYNENTALNOŚĆ — bardzo niska częstotliwość, decyduje ląd/nizina/góry.
_continent = FastNoiseLite.new()
_continent.noise_type = FastNoiseLite.TYPE_OPEN_SIMPLEX_2  # mniej kierunkowych artefaktów niż Perlin
_continent.seed = 1337
_continent.frequency = 0.0012          # ~830 m perioda — duże masy lądu
_continent.fractal_type = FastNoiseLite.FRACTAL_FBM
_continent.fractal_octaves = 3

# B) GÓRY — RIDGED, daje ostre granie zamiast kopuł.
_mountain = FastNoiseLite.new()
_mountain.noise_type = FastNoiseLite.TYPE_OPEN_SIMPLEX_2
_mountain.seed = 2207
_mountain.frequency = 0.006
_mountain.fractal_type = FastNoiseLite.FRACTAL_RIDGED   # KLUCZ dla grani/klifów
_mountain.fractal_octaves = 4
_mountain.fractal_gain = 0.45
_mountain.fractal_lacunarity = 2.1

# C) WZGÓRZA — zwykły FBM, detal średniej skali (Twój obecny szum, podbity).
_hills = FastNoiseLite.new()
_hills.noise_type = FastNoiseLite.TYPE_PERLIN
_hills.seed = 1337
_hills.frequency = 0.010
_hills.fractal_octaves = 3

# D) DOMAIN WARP — przesuwa wsp. próbkowania => kręte, organiczne kształty.
_warp = FastNoiseLite.new()
_warp.seed = 5150
_warp.domain_warp_enabled = true
_warp.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
_warp.domain_warp_amplitude = 28.0     # do ~14 m przesunięcia (28 voxeli)
_warp.domain_warp_frequency = 0.005
```

Nowy `surface_height` — kompozycja z maskami, NIE prosta suma (suma daje znów jednostajność):

```gdscript
func surface_height(world_x: int, world_z: int) -> int:
    var p := Vector2(float(world_x), float(world_z))
    _warp.domain_warp_position(p)              # in-place warp wsp. (Godot 4.x)
    var wx := p.x; var wz := p.y

    # kontynent: [-1,1] -> [0,1], przesunięty by ~45% świata było niziną
    var cont := (_continent.get_noise_2d(wx, wz) * 0.5) + 0.5
    cont = smoothstep(0.30, 0.85, cont)        # płaskie niziny + szybkie wybicie w góry

    # ridged góry: FastNoiseLite RIDGED zwraca ~[-1,1]; bierzemy dodatnią część
    var mnt := maxf(0.0, _mountain.get_noise_2d(wx, wz))
    mnt = mnt * mnt                            # ^2 = wyostrza granie, doliny szersze

    var hill := (_hills.get_noise_2d(wx, wz) * 0.5) + 0.5

    # KOMPOZYCJA: bazowa nizina + góry bramkowane kontynentem + drobne wzgórza
    var h := BASE_HEIGHT \
        + cont * 10.0 \
        + cont * mnt * 52.0 \
        + hill * 8.0
    return clampi(int(round(h)), 1, WORLD_HEIGHT - 1)
```

Kluczowe: `cont * mnt` (góry pojawiają się TYLKO tam, gdzie kontynent wysoki) eliminuje „góry wszędzie”. `smoothstep` na kontynencie daje płaskie niziny + płaskowyże, a nie ciągłą falę. `mnt²` daje wąskie ostre granie zamiast okrągłych pagórków.

**Koszt**: Medium, CPU-build. Z ~4 próbek/kolumnę robi się ~3+4+3 octaves = ~10 próbek + 1 warp ≈ 11–12 próbek/kolumnę = ~3× obecny koszt budowy. Przy ~1024 kolumn/chunk i `chunks_per_frame=2` to zauważalny wzrost czasu budowy (Twoje realne wąskie gardło). Mitygacja: kontynent i warp są bardzo niskoczęstotliwościowe — próbkuj je co 4 voxele i interpoluj biliniowo w obrębie kafla 4×4 (redukuje koszt continent+warp ~16×, wizualnie nieodróżnialne bo perioda >800 m). To sprowadza koszt do ~1.5–2×.

**Priorytet**: **High**. To jest źródłowa przyczyna „nudnego” terenu; bez tego wszystkie pozostałe punkty malują na płaskim tle.

---

## 2) MIKRO-DETALE — głazy, odsłonięcia skał, łaty deterministycznie

**Cel wizualny**: zerwać gładkość zboczy — odsłonięte żyły skalne na stromiznach, rozproszone otoczaki, łaty ziemi/żwiru w trawie. Dziś masz głazy (`_place_rock`), ale TYLKO jako wystające elipsoidy; brak skały WIDOCZNEJ w samym terenie i brak zależności od nachylenia.

**Implementacja (Godot 4.7, konkretnie)** — dodaj regułę nachylenia (slope) w `_block_for`. Slope liczysz z gotowej heightmapy (zero dodatkowego szumu), porównując sąsiednie kolumny w `_generate_data`:

```gdscript
# w _generate_data, po wypełnieniu _heightmap, PRZED kolumnami bloków:
func _slope_at(x: int, z: int, world: VoxelWorld) -> int:
    var h := _heightmap[x + CHUNK_SIZE * z]
    var hx := world.surface_height(_coord.x*CHUNK_SIZE + x+1, _coord.y*CHUNK_SIZE + z)
    var hz := world.surface_height(_coord.x*CHUNK_SIZE + x, _coord.y*CHUNK_SIZE + z+1)
    return maxi(absi(hx - h), absi(hz - h))   # w voxelach
```

W `_block_for` (przekaż slope): strome zbocze = odsłonięta skała niezależnie od wysokości:

```gdscript
if world_y == surface_y:
    if slope >= 5: return Blocks.Type.ROCK        # stromizna >5 voxeli/voxel => goła skała
    if surface_y <= BEACH_MAX_Y: return Blocks.Type.SAND
    ...
# pod powierzchnią na stromiznie też skała zamiast grubej gleby:
if slope >= 5 and world_y >= surface_y - 2: return Blocks.Type.ROCK
```

Łaty ziemi/żwiru w trawie — bez nowego szumu, użyj `feature_hash` z progiem przestrzennym albo `_tint_noise` (już masz) jako maskę:

```gdscript
# w _block_for dla GRASS na powierzchni:
if _tint_noise.get_noise_2d(wx*0.3, wz*0.3) > 0.55:
    return Blocks.Type.DIRT   # ~10% powierzchni: wydeptana łata ziemi
```

Plus podbij gęstość `_place_rock` na stromiznach (ROCK_PROB ×3 gdy slope≥4) — kamienie tam, gdzie naturalnie się osypują.

**Koszt**: Low–Medium, CPU-build. Slope dokłada 2 `surface_height` na graniczne kolumny (wewnątrz chunku liczysz z cache `_heightmap` za darmo — przesuń `_slope_at` by czytał `_heightmap` dla x+1,z+1 w obrębie chunku, tylko brzeg woła szum). Łata ziemi to 1 tania próbka 2D dla kafli trawy. Zero kosztu GPU (te same vertex colors, te same typy bloków).

**Priorytet**: **High**. Slope→skała to pojedynczo największy skok „naturalności” voxelowego terenu, a kosztuje grosze.

---

## 3) PRZEJŚCIA BIOMÓW — mapy temperatura/wilgotność, blend kolorów

**Cel wizualny**: biom ma wynikać z KLIMATU (gdzie jesteś na mapie), nie tylko z wysokości. Pustynia/sawanna/las/tundra. Granice rozmyte, nie twarde progi Y — żeby trawa nie „przeskakiwała” w piasek jedną linią.

**Implementacja (Godot 4.7, konkretnie)** — dwie nowe, NISKOczęstotliwościowe mapy klimatu, niezależne od wysokości:

```gdscript
_temp = FastNoiseLite.new()
_temp.seed = 4242
_temp.noise_type = FastNoiseLite.TYPE_OPEN_SIMPLEX_2
_temp.frequency = 0.0018        # ~550 m perioda — duże strefy klimatyczne
_temp.fractal_octaves = 2

_humid = FastNoiseLite.new()
_humid.seed = 8484
_humid.noise_type = FastNoiseLite.TYPE_OPEN_SIMPLEX_2
_humid.frequency = 0.0021
_humid.fractal_octaves = 2
```

Funkcja klimatu z korekcją wysokości (wysoko = zimniej — naturalny śnieg na szczytach):

```gdscript
func climate_at(wx: int, wz: int, surface_y: int) -> Vector2:
    var t := (_temp.get_noise_2d(wx, wz) * 0.5) + 0.5
    t -= clampf(float(surface_y - 40) / 60.0, 0.0, 0.4)   # lapse rate: szczyty zimne
    var hmd := (_humid.get_noise_2d(wx, wz) * 0.5) + 0.5
    return Vector2(clampf(t,0,1), hmd)
```

Mapowanie biomu (zastąp wybór po Y w `_block_for` powierzchni):
- t<0.30 → SNOW/tundra
- t<0.55 & humid<0.35 → ROCK/żwir (step skalny)
- t>0.70 & humid<0.30 → SAND (pustynia, też wysoko nad morzem!)
- reszta → GRASS

**Blendowanie na granicy** (klucz — bez twardych progów): zamiast wybierać typ bloku skokowo, interpoluj KOLOR w `_solid_color` w pasie przejściowym. Bloki nadal są dyskretne (tożsamość voxelowa), ale ich vertex color płynnie przechodzi:

```gdscript
# w _solid_color dla powierzchni trawiastej:
var clim := world.climate_at(wx, wz, y)
var dryness := smoothstep(0.55, 0.78, clim.x) * (1.0 - smoothstep(0.40, 0.20, clim.y))
base = base.lerp(SAVANNA_GRASS, dryness)   # trawa -> sucha sawanna płynnie
var cold := smoothstep(0.40, 0.20, clim.x)
base = base.lerp(TUNDRA_GRASS, cold)       # -> wyblakła tundra płynnie
```

To daje gradient barwy szeroki na dziesiątki metrów zamiast linii. Dithering na samym przełączeniu TYPU bloku (np. piasek↔trawa): użyj `feature_hash` jako progu losowego w pasie ±0.05 wokół granicy klimatu — ziarniste, naturalne wymieszanie pojedynczych voxeli zamiast prostej linii.

**Koszt**: Medium, CPU-build. +2 mapy ×2 octaves = ~4 próbki/kolumnę. Ale temperatura/wilgotność mają periodę >500 m — próbkuj je RAZ na chunk w 4 narożnikach i interpoluj biliniowo per kolumna (koszt spada do 4 próbek/chunk zamiast /kolumnę, ~256× taniej). Wizualnie identyczne. To czyni ten punkt praktycznie darmowym w CPU.

**Priorytet**: **High**. Bez klimatu cały świat to „jeden biom z piaskiem na dole i śniegiem na górze”. To daje POWÓD do eksploracji.

---

## 4) PALETA KOLORÓW — spójna, żywa, per-biom (konkretne wartości)

**Cel wizualny**: rozszerzyć obecną (dobrą) paletę o brakujące biomy, zachowując spójność pod Twój pipeline (ACES exposure 0.8, white 6.0, glow 0.2/bloom 0.05). Każdy biom musi mieć rozpoznawalną „temperaturę barwy”.

**Implementacja (Godot 4.7)** — dodaj do `Blocks.gd` kotwice trawy per-klimat (sRGB, dobrane jak Twoje istniejące, zbite poniżej progu glow):

```gdscript
const GRASS_LOW:     Color = Color(0.42, 0.64, 0.24)  # (istniejąca) łąka nizinna
const GRASS_HIGH:    Color = Color(0.30, 0.52, 0.30)  # (istniejąca) hala górska
const SAVANNA_GRASS: Color = Color(0.72, 0.66, 0.30)  # sucha, żółto-oliwkowa
const TUNDRA_GRASS:  Color = Color(0.55, 0.62, 0.52)  # wyblakła szarozielona
const JUNGLE_GRASS:  Color = Color(0.24, 0.58, 0.22)  # ciemna, nasycona (humid wysoki)
# piaski/skały per klimat:
const SAND_DESERT:   Color = Color(0.86, 0.74, 0.46)  # cieplejszy niż plażowy
const ROCK_VOLCANIC: Color = Color(0.30, 0.27, 0.28)  # ciemny bazalt (akcent landmarków)
const ROCK_DESERT:   Color = Color(0.62, 0.46, 0.34)  # czerwonawy piaskowiec/mesa
```

Zasada spójności pod glow: trzymaj max kanału ≤0.90 dla bieli/żółci (śnieg masz już 0.90/0.93/0.99 — granica), nasycenie wysokie ale luminancja umiarkowana, bo ACES exposure 0.8 + glow 0.2 podbija jasne barwy. Akcenty (kwiaty, jesienne liście) mogą iść wyżej w saturacji bo to małe powierzchnie — duże płachty trawy/piasku trzymaj stonowane, by glow ich nie wypalił (już to robisz w komentarzach — kontynuuj tę dyscyplinę dla nowych biomów).

Mesa/kanion: warstwowy piaskowiec — koloruj ROCK_DESERT pasami wg `world_y % 8` (jaśniej/ciemniej co 4 m), daje stratygrafię jak w kanionie:

```gdscript
if t == Blocks.Type.ROCK and clim.dry:
    var band := 0.92 + 0.08 * float((y / 4) % 2)
    base = ROCK_DESERT * band
```

**Koszt**: Low, CPU-build (to tylko stałe + lerpy w `_solid_color`, które już wykonujesz). Zero GPU.

**Priorytet**: **Medium** (High dla samej paszy biomów, ale to dopełnienie punktu 3 — bez klimatu nie ma gdzie ich użyć).

---

## 5) SYLWETKI TERENU — klify, nawisy, łuki

**Cel wizualny**: Twój teren to czysta heightmapa (1 kolumna = 1 wysokość) — fizycznie NIE MOŻE mieć nawisów ani łuków, tylko zbocza. To największe ograniczenie sylwetki. Cel: dodać formy 3D (nawisy, łuki, iglice), zachowując tani heightmap-base wszędzie indziej.

**Implementacja (Godot 4.7)** — dwie ścieżki:

**5a. Klify (tanio, w heightmapie)**: ridged góry z `mnt²` z punktu 1 + slope→skała z punktu 2 JUŻ dają pionowe ściany skalne. Wzmocnij: gdy `slope >= 8`, wymuś dosłownie pionową ścianę przez kwantyzację wysokości do tarasów:

```gdscript
if slope >= 8:
    h = float(int(h / 4) * 4)   # tarasowanie co 4 voxele => płaskie półki + pionowe ściany (mesa/klif)
```

To daje czytelne klify Cube World bez wychodzenia poza heightmapę. Koszt zerowy.

**5b. Nawisy/łuki/iglice (prawdziwe 3D, RZADKO)**: heightmapa tego nie zrobi — potrzebujesz drugiej maski szumu 3D, ale TYLKO lokalnie (globalnie 3D byłoby zabójcze: 96 warstw × 1024 kolumn = wywołanie szumu 3D na ~100k voxeli/chunk). Zamiast tego — wytnij łuk PROCEDURALNIE jako feature (jak drzewo), w wąskim oknie, tylko gdy `feature_hash` trafi rzadki próg:

```gdscript
# w _place_features, bardzo rzadko (~1 na kilka chunków):
if world.feature_hash(wx, wz, SALT_ARCH) < 0.0004 and surface_t == ROCK:
    _carve_arch(x, sy, z)   # rzeźbi tunel: usuwa AIR w łuku, zostawia ROCK nad i po bokach
```

`_carve_arch` ustawia ROCK w kształcie podkowy (parametryczny: dwa filary + łuk z `sin`) i AIR w środku — kilkadziesiąt `_try_set_feature` na sztukę. Identycznie iglice (kolumna ROCK r=1–2, wysokość 8–16) i grzybowe skały (cienka szyja + szeroki kapelusz ROCK).

**Koszt**: 5a Low (zerowy — arytmetyka). 5b Medium-tylko-lokalnie, CPU-build: szum 3D NIE jest stosowany globalnie, łuki to rzadkie features (~kilkadziesiąt voxeli każdy, raz na kilka chunków) — pomijalne w sumie budowy. Krytyczne: nie próbuj globalnego carvingu 3D szumem — to rozsadzi czas budowy.

**Priorytet**: 5a **Medium**, 5b **Low**. Łuki/iglice to „wow”, ale rzadkie; klify (5a) dają więcej za mniej.

---

## 6) LANDMARKI — rzadkie, wyróżniające punkty (wielkie drzewo, ruiny, krater)

**Cel wizualny**: punkty orientacyjne widoczne z daleka, nadające światu kierunek („idę do tej wielkiej wieży skalnej”). Muszą być RZADKIE (1 na setki metrów) i deterministyczne.

**Implementacja (Godot 4.7)** — problem: landmark jest większy niż chunk (16 m), więc nie może być wybierany per-kafel jak drzewo. Rozwiązanie: GRID LANDMARKÓW. Dziel świat na komórki np. 8×8 chunków (128 m); każda komórka MA co najwyżej jeden landmark, którego pozycję i typ wyznacza `feature_hash` komórki:

```gdscript
const LANDMARK_CELL: int = 8   # 8 chunków = 128 m
func _landmark_for_cell(cx: int, cz: int) -> Dictionary:
    var roll := world.feature_hash(cx, cz, SALT_LANDMARK)
    if roll > 0.45: return {}                    # ~55% komórek pustych => rzadkość
    # pozycja landmarku w komórce (deterministyczna):
    var lx := cx*LANDMARK_CELL*CHUNK_SIZE + int(world.feature_hash(cx,cz,SALT_LM_X)*LANDMARK_CELL*CHUNK_SIZE)
    var lz := cz*LANDMARK_CELL*CHUNK_SIZE + int(world.feature_hash(cx,cz,SALT_LM_Z)*LANDMARK_CELL*CHUNK_SIZE)
    var kind := int(world.feature_hash(cx,cz,SALT_LM_KIND)*4)  # 0 drzewo,1 ruiny,2 krater,3 iglica
    return {"x":lx, "z":lz, "kind":kind}
```

Każdy budowany chunk pyta SWOJĄ komórkę (i 8 sąsiednich komórek — landmark może wystawać poza komórkę) czy landmark wpada w jego obręb, i renderuje swoją część. Typy:
- **Wielkie drzewo**: jak `_place_tree` ×4 skali (trunk_h 30, r=12), pień fat 4×4, korona wielowarstwowa. Widoczne ponad render_distance.
- **Ruiny**: siatka kolumn ROCK r=2 wysokości 6–14 z `feature_hash` (część zawalona = niższa), opcjonalnie podstawa z DIRT. Determinizm per kolumna.
- **Krater**: odejmij od heightmapy paraboloidę w `surface_height` (landmark MUSI być w heightmapie, nie tylko features, by teren się dopasował): `h -= max(0, R² - dist²)/k`, dno z ROCK/woda.
- **Iglica/wieża**: pionowa kolumna ROCK r=2–3, wysokość 20–40, tarasowana.

KLUCZ dla krateru/góry-landmarku: musi wpłynąć przez `surface_height`, nie przez `_place_features` — inaczej teren pod nim będzie płaski i landmark „zawiśnie”. Dlatego krater i mega-góra to modyfikacja heightmapy (sprawdź najbliższy landmark w `surface_height`), a wielkie drzewo/ruiny/iglica to features na wierzchu.

**Koszt**: Medium, CPU-build. Dla heightmapowych landmarków (krater): +1 lookup gridu landmarków na kolumnę (tanie — to hash, nie szum, i tylko gdy komórka ma landmark blisko). Dla feature-landmarków: koszt tylko w ~kilku chunkach na komórkę, które faktycznie zawierają landmark. Większość chunków: +1 hash/chunk (sprawdzenie „czy mój chunk dotyka landmarku”), pomijalne. Uwaga VRAM: wielkie drzewo dokłada geometrię do paru chunków — przy 4 GB to nieistotne (to wciąż vertex-color mesh w istniejącym batchu materiału).

**Priorytet**: **Medium**. Po punktach 1–3 (które robią teren ciekawym w skali makro), landmarki dają warstwę nawigacyjną/narracyjną.

---

## JAK UNIKAĆ POWTARZALNOŚCI PROCEDURALNEJ (przekrojowo)

1. **Nieparzyste, niewspółmierne częstotliwości i różne ziarna** dla każdej warstwy (continent 0.0012, mountain 0.006, hills 0.010, temp 0.0018, humid 0.0021) — wartości nie będące wielokrotnościami siebie nie tworzą widocznej interferencji/„kratki”.
2. **Domain warp na heightmapie** (punkt 1) — najsilniejszy pojedynczy środek anty-regularności: łamie izotropię Perlina, której efekt „wszystko wygląda tak samo” najmocniej widać.
3. **Kompozycja multiplikatywna, nie addytywna** (`cont*mnt`) — sumowanie szumów zawsze dąży do jednostajnej „średniej”; bramkowanie maskami tworzy wyraźnie różne strefy.
4. **OpenSimplex2 zamiast Perlina** dla warstw makro — Perlin ma osiowe artefakty (widoczne grzbiety pod 45°), które przy dużych skalach robią „kratę”.
5. **Deterministyczna rzadkość przez progi `feature_hash`** zamiast okresowego rozmieszczania — landmarki/łuki nigdy nie wpadają w regularny raster.
6. **Klimat ortogonalny do wysokości** (punkt 3) — ten sam poziom wysokości w różnych miejscach mapy wygląda inaczej (raz las, raz pustynia), co najbardziej zabija wrażenie „już to widziałem”.

---

## KOLEJNOŚĆ WDROŻENIA (wg stosunku efekt/koszt dla Twojego CPU-build budżetu)

1. **Punkt 2 (slope→skała)** — najtańszy, natychmiastowa naturalność. High.
2. **Punkt 1 (warstwy szumu + ridged + warp)** — źródłowa naprawa „falowania”. High. Zastosuj próbkowanie continent/warp co 4 voxele, by trzymać CPU-build w ryzach.
3. **Punkt 3 + 4 (klimat + paleta)** — z próbkowaniem temp/humid per-chunk (4 narożniki) prawie darmowe, a dają biomy. High/Medium.
4. **Punkt 5a (tarasowanie klifów)** — zerowy koszt, mocny efekt sylwetki. Medium.
5. **Punkt 6 (landmarki)** — warstwa nawigacyjna. Medium.
6. **Punkt 5b (łuki/iglice)** — rzadki „wow”. Low.

Pliki do zmian (absolutne): `C:\Users\oskar\Downloads\voxel-rpg\src\world\VoxelWorld.gd` (`_setup_noise`, `surface_height`, `climate_at`, grid landmarków, `feature_hash` salty), `C:\Users\oskar\Downloads\voxel-rpg\src\world\Chunk.gd` (`_block_for` z slope/klimatem, `_solid_color` blend biomów, `_place_features` landmarki/łuki, tarasowanie), `C:\Users\oskar\Downloads\voxel-rpg\src\world\Blocks.gd` (nowe kotwice kolorów + typy ROCK_DESERT/SAVANNA itd. jeśli chcesz osobne bloki).

Jedno ostrzeżenie pod Twój profiler: każdy z tych punktów dokłada do CPU-build (Twoje udokumentowane wąskie gardło — „koszt budowy chunku, single-thread”). Zanim dodasz wszystkie naraz, rozważ przeniesienie `_generate_data`+`_build_mesh` na `WorkerThreadPool` (Godot 4.7) — wtedy budżet CPU-build przestaje być wąskim gardłem i możesz pozwolić sobie na pełną wariację bez kompromisów próbkowania. To pojedyncza zmiana architektury o największym wpływie na Twój realny limit.

---

## [dystans] distance rendering

I'll base everything on your actual setup. Note one factual correction up front so the recommendations land right: **Godot's latest stable is 4.4/4.5-dev — there is no 4.7.** I'll target the Godot 4.x API as it exists; every property/shader below works on 4.3+. If you're genuinely on a custom 4.7 build, the API is identical here.

Let me confirm the most critical constraint for distance work — `aerial_perspective` exists on `Environment` only when volumetric fog is on, which you have. Good, that unlocks the cheapest win.

---

# DISTANCE RENDERING — pierścień dali przy render_distance 4 (64 m)

**Brutalnie szczerze o punkcie wyjścia:** 64 m to nie "mało", to *bardzo* mało dla action-RPG — gracz widzi krawędź świata. Twój prawdziwy wróg to **CPU-build w single-thread GDScript** (8× voxeli przy 0.5 m). Dlatego cała strategia poniżej jest: **render-side maskowanie krawędzi (tanie, GPU) + jeden tani pierścień geometrii LOD (CPU, ale 4-16× tańszy per chunk), NIE zwiększanie render_distance.** Zwiększenie do 6 to ~2.25× chunków buildowanych tym samym wąskim gardłem — odpada.

---

## 1. Atmospheric perspective (tint dali kolorem horyzontu)

**Cel wizualny:** Dalsze voxele "wtapiają się" w kolor nieba/horyzontu — natychmiastowo daje wrażenie głębi i ukrywa twardą krawędź render_distance. To pojedynczy najmocniejszy efekt głębi za najmniejszą cenę.

**Implementacja (Godot 4.x, konkretnie):** Masz dwie drogi — wybierz **A** (zero kosztu CPU, zero kodu).

**A) Wbudowany aerial perspective fog (ZALECANE):**
```gdscript
# Environment — masz już volumetric fog ON, więc to działa
env.volumetric_fog_enabled = true
env.volumetric_fog_density = 0.002          # zostaw jak jest
env.fog_aerial_perspective = 1.0            # 0→1: ile fog miesza kolor NIEBA per-piksel wg głębi
env.fog_sky_affect = 1.0                     # fog widoczny też na tle nieba (spójny horyzont)
```
`fog_aerial_perspective = 1.0` sprawia, że mgła zamiast jednolitego koloru sampluje **kolor nieba w kierunku patrzenia** — czyli dal automatycznie dostaje kolor horyzontu, który DayNight.gd już animuje. To dokładnie efekt z Cube World. Zero kodu, zero CPU.

**B) Per-vertex/fragment tint w shaderze terenu** (jeśli chcesz pełną kontrolę i niezależność od fog) — wymaga przejścia ze StandardMaterial3D na ShaderMaterial dla terenu:
```glsl
shader_type spatial;
render_mode cull_back, diffuse_burley;
uniform vec3 horizon_color : source_color = vec3(0.78, 0.84, 0.93);
uniform float aerial_start = 30.0;   // m — gdzie zaczyna się tint
uniform float aerial_end   = 64.0;   // m — render_distance edge
uniform float aerial_max   = 0.85;   // max siła (nie 1.0 — sylwetki nie znikają całkiem)

void vertex() {
    COLOR = COLOR; // vertex colors as albedo (zachowaj swój pipeline)
}
void fragment() {
    float d = length((INV_VIEW_MATRIX * vec4(VERTEX,1.0)).xyz - CAMERA_POSITION_WORLD);
    float t = clamp((d - aerial_start)/(aerial_end - aerial_start), 0.0, 1.0);
    t = t*t*(3.0-2.0*t);                          // smoothstep — miękko
    ALBEDO = mix(COLOR.rgb, horizon_color, t * aerial_max);
}
```
DayNight.gd pushuje `horizon_color` co keyframe: `terrain_mat.set_shader_parameter("horizon_color", current_horizon)`.

**Koszt:** **A: Low (GPU-render, praktycznie zero)** — to przełącznik na już-aktywnej mgle, brak dodatkowych passów. **B: Low-Med (GPU-render)** — fragment-side `length` + `mix` per piksel terenu; na RTX 3050 nieistotne przy 64 m zasięgu. Oba zero CPU-build. Uwaga 4GB: żaden nie dokłada VRAM.

**Priorytet: HIGH.** Zacznij od **A** — jeden wieczór, największy zwrot.

---

## 2. Fog blending doczytywanych chunków (anty-popping)

**Cel wizualny:** Chunk, który właśnie się dobudował, **wyłania się z mgły** zamiast wyskakiwać. Kluczowe przy Twoim CPU-build — chunki pojawiają się z opóźnieniem, więc MUSZĄ być zamaskowane mgłą na granicy.

**Implementacja:** Dwie warstwy.

**(a) Dostrojenie istniejącej mgły, by krawędź była W mgle.** Twoja `density 0.002` jest za rzadka — przy 64 m daje znikome wytłumienie. Policz: transmittance ≈ `exp(-density·dist)` = `exp(-0.002·64)` = **0.88** — chunk na krawędzi jest wciąż w 88% widoczny, czyli popping BĘDZIE widać. Chcesz ~0.35-0.45 transmittance na krawędzi:
```gdscript
env.volumetric_fog_density = 0.013   # exp(-0.013·64)=0.43 → krawędź solidnie w mgle
# jeśli to za "ciężkie" w dzień, użyj fog_depth_* (klasyczny depth fog) zamiast wolumetrycznej gęstości:
env.fog_enabled = true
env.fog_mode = Environment.FOG_MODE_DEPTH
env.fog_depth_begin = 38.0           # czysto do 38 m
env.fog_depth_end   = 66.0           # pełna mgła tuż ZA krawędzią render_distance
env.fog_depth_curve = 2.0            # wykładniczo — gęstnieje przy końcu
```
**Depth fog (FOG_MODE_DEPTH) jest tu lepszy niż volumetric** do maskowania krawędzi: dokładna kontrola begin/end zsynchronizowana z render_distance, i jest **tańszy** (brak froxel grid). Volumetric zostaw tylko jeśli chcesz god-rays/lokalne FogVolume; do samego maskowania dali depth fog wystarcza i zwalnia GPU.

**(b) Per-chunk fade-in (dissolve) przy dobudowaniu** — eliminuje popping NAWET gdy chunk jest bliżej niż mgła:
```gdscript
# W skrypcie chunku, po zbudowaniu mesha:
func _on_built():
    var m: ShaderMaterial = mesh_instance.material_override
    var t := create_tween()
    m.set_shader_parameter("spawn_fade", 0.0)
    t.tween_method(func(v): m.set_shader_parameter("spawn_fade", v), 0.0, 1.0, 0.45)
```
```glsl
// w shaderze terenu — dithered dissolve (tani, bez alpha-blend/sortowania):
uniform float spawn_fade = 1.0;
void fragment() {
    // bayer-ish dither z ekranowych UV:
    float dith = fract(sin(dot(SCREEN_UV*vec2(1920,1080), vec2(12.9898,78.233)))*43758.5453);
    if (dith > spawn_fade) discard;   // alpha-tested fade, zero kosztu sortowania
}
```
Dither dissolve > alpha blend: nie wymaga `transparent` (który zabija depth-prepass i jest drogi przy nakładających się chunkach), nie psuje SSAO.

**Koszt:** (a) **Low (GPU-render)** — depth fog tańszy niż obecna volumetric; możesz nawet odzyskać klatki. (b) **Low (GPU-render)** — `discard` + jeden tween na chunk, koszt CPU pomijalny (jeden tween, nie per-vertex). Zero VRAM.

**Priorytet: HIGH** dla (a) — to bezpośrednio leczy Twój najbardziej widoczny artefakt (opóźnione chunki). **Medium** dla (b).

---

## 3. LOD terenu — tańsze dalsze chunki w GDScript

**Tu jest cała trudność i tu muszę być szczery.**

**Greedy meshing masz słusznie odrzucony** (per-voxel tint+AO blokują łączenie). Ale dla DALEKICH chunków te detale są niewidoczne — i to jest furtka.

**Realna opcja: half-res / quarter-res mesh dla pierścienia dali (LOD1).**

**Cel wizualny:** Chunki w pierścieniu 2-4 (32-64 m) renderowane z voxelem **1.0 m zamiast 0.5 m** → 8× mniej voxeli do zmeshowania → 8× tańszy CPU-build. Z 64 m i atmospheric perspective (pkt 1) gracz NIE rozróżni 0.5 vs 1.0 m na krawędzi.

**Implementacja (GDScript, konkretnie):**
```gdscript
# Parametryzuj builder rozmiarem voxela LOD:
func build_chunk_mesh(chunk_data, lod: int):
    var step := 1 << lod          # lod0→1, lod1→2 (próbkuj co 2. voxel)
    var vsize := VOXEL_SIZE * float(step)   # 0.5 → 1.0
    for x in range(0, CHUNK_SIZE, step):
        for z in range(0, CHUNK_SIZE, step):
            for y in range(0, WORLD_HEIGHT, step):
                # próbkuj reprezentatywny voxel bloku (np. dominujący typ w 2×2×2)
                var block = sample_dominant(chunk_data, x, y, z, step)
                if block == AIR: continue
                # buduj ścianę o rozmiarze vsize, kolor = średnia/dominanta, BEZ mikro-tintu i BEZ AO
                ...
    # LOD1: POMIŃ mikro-tint (FastNoiseLite) i drobne propy całkowicie
```
**LOD przydział wg pierścienia (Chebyshev distance w chunkach):**
```gdscript
func lod_for(chunk_coord: Vector2i, player_chunk: Vector2i) -> int:
    var ring = max(abs(chunk_coord.x-player_chunk.x), abs(chunk_coord.y-player_chunk.y))
    return 0 if ring <= 1 else 1     # ring 0-1 pełne (24 m), ring 2-3 half-res
```
**Twardy problem: cracki/szwy na granicy LOD0↔LOD1** (sąsiednie chunki różnej rozdzielczości → dziury w pionowych ścianach). Rozwiązanie najtańsze w GDScript: **"skirts"** — na krawędziach każdego chunku dociągnij ściany 1-2 voxele w dół (pionowy kołnierz), który zakrywa szczeliny. Tanie (kilka quadów per krawędź), nie wymaga stitchingu geometrii (który w GDScript byłby koszmarem).
```gdscript
# po zbudowaniu, na 4 krawędziach chunku dodaj pionowy pas w dół o vsize:
add_skirt(edge_vertices, down = vsize)   # ~CHUNK_SIZE/step * 4 dodatkowych quadów
```

**Koszt:** **Med (CPU-build, ale OSZCZĘDZA CPU netto).** LOD1 chunk: ~8× mniej voxeli + brak mikro-tintu + brak propów + brak AO → realnie **4-8× szybszy build** niż LOD0. Pierścień 2-3 to większość buildowanych chunków, więc to **bezpośrednio atakuje Twoje wąskie gardło**. Skirts dokładają ~5% wierzchołków — pomijalne. VRAM: **mniej** mesha = mniej VRAM (plus dla 4GB). GPU-render: mniej trójkątów = taniej.

**Priorytet: HIGH** — to jedyna pozycja, która jednocześnie poprawia dal I leczy główne wąskie gardło CPU. Ale to też najwięcej pracy (skirts, sample_dominant, zarządzanie przejściami LOD).

**Imposter ring / billboard — ODRADZAM dla Twojego przypadku.** Imposters (rendered-to-texture kafle terenu) wymagają render-to-texture passa, atlasu i regeneracji przy ruchu — koszt CPU/VRAM (atlas textures w 4GB!) i komplikacja przewyższają zysk przy zaledwie 64 m. Half-res mesh daje 80% efektu za 20% pracy. Pomiń.

---

## 4. Desaturacja w dali

**Cel wizualny:** Dal lekko traci nasycenie (realna optyka atmosfery) — wzmacnia głębię, współgra z tintem horyzontu z pkt 1.

**Implementacja:** Najlepiej **wbudować w shader terenu z pkt 1B** (jeśli go masz), za darmo razem z tintem:
```glsl
void fragment() {
    // ... t = smoothstep depth jak w pkt 1 ...
    vec3 col = COLOR.rgb;
    float lum = dot(col, vec3(0.299,0.587,0.114));
    col = mix(col, vec3(lum), t * 0.35);          // desaturacja do 35% w dali
    ALBEDO = mix(col, horizon_color, t * aerial_max);  // potem tint horyzontu
}
```
Jeśli zostajesz na fog aerial perspective (1A) bez własnego shadera — desaturacja przyjdzie **częściowo za darmo**, bo kolor nieba/horyzontu jest mniej nasycony niż trawa, więc `mix` ku niemu już desaturuje. Wtedy nie rób nic osobno.

**Koszt:** **Low (GPU-render)** — dwa `mix` i `dot` per piksel; zero przy 64 m na RTX 3050. Zero CPU, zero VRAM.

**Priorytet: Medium** — miły dodatek, ale tylko jeśli i tak robisz shader terenu (1B). Jako samodzielna pozycja: Low priorytet.

---

## 5. Horizon haze

**Cel wizualny:** Pas zamglenia tam, gdzie teren spotyka niebo — ukrywa "ścianę" krawędzi świata i zlewa pierścień LOD z niebem.

**Implementacja:** Połączenie dwóch przełączników, które już masz/dodajesz:
```gdscript
env.fog_sky_affect = 1.0          # mgła wpływa na piksele nieba → niebo blisko horyzontu się zamgla
env.fog_aerial_perspective = 1.0  # (z pkt 1A) dal=kolor nieba → bezszwowe zlanie
# ProceduralSkyMaterial — podbij jasność pasa horyzontu, by haze był widoczny:
sky_mat.sky_horizon_color = Color(0.80, 0.86, 0.93)   # jaśniejszy niż top
sky_mat.ground_horizon_color = sky_mat.sky_horizon_color  # spójność
sky_mat.sky_curve = 0.15          # szerszy, miękki gradient horyzontu (niżej=ostrzej)
```
DayNight.gd już animuje sky_top/horizon — upewnij się tylko, że `fog_sky_affect=1.0` jest ustawione raz na starcie.

**Koszt:** **Low (GPU-render)** — same przełączniki na istniejącym Environment/Sky. Zero CPU, zero VRAM.

**Priorytet: Medium.** Wymaga, by mgła była dostrojona (pkt 2a) — wtedy to dosłownie 2 linijki.

---

## 6. Zwiększenie WRAŻENIA zasięgu bez 8× kosztu

**To jest serce Twojego pytania. Cube World ma malutki render distance — sztuczka jest w warstwach.** Trzy techniki, od najtańszej:

**(6a) Distant terrain skybox-proxy / "false horizon" — NAJTAŃSZE, ZALECANE.**
**Cel:** Za pierścieniem LOD1 widać niski, miękki gradient sugerujący teren ciągnący się w dal — gracz "czuje" świat dalej niż 64 m, choć to malowane.
**Implementacja:** Dodaj do ProceduralSkyMaterial drugą warstwę koloru u dołu (ground), zsynchronizowaną z dominującym kolorem biomu:
```gdscript
sky_mat.ground_bottom_color = Color(0.35, 0.45, 0.30)   # przygaszona zieleń biomu
sky_mat.ground_horizon_color = Color(0.72, 0.80, 0.78)  # ku haze
sky_mat.ground_curve = 0.25
# DayNight.gd: ground_* też interpoluj (noc=ciemniejsze)
```
Gdy mgła (pkt 2) chowa krawędź LOD, gracz widzi ten "ground" jako ciągnący się teren. **Iluzja za zero geometrii.** Koszt: **Low (GPU), zero CPU, zero VRAM.** **Priorytet: HIGH** — najlepszy stosunek wrażenie/koszt w całej sekcji.

**(6b) Drugi pierścień ULTRA-LOD (LOD2, voxel 2.0 m) tylko jako sylwetka.**
**Cel:** Jeden dodatkowy pierścień (ring 4-6, 64-96 m) zbudowany z voxelem 2.0 m (16× mniej voxeli niż LOD0, ~16× tańszy build), renderowany **mocno w mgle** — daje rzeczywiste wzgórza/sylwetki w dali za grosze.
**Implementacja:** ta sama `build_chunk_mesh(..., lod=2)` z `step=4`; buduj te chunki z `chunks_per_frame` osobno/rzadziej (niższy priorytet kolejki), bo i tak są ledwo widoczne:
```gdscript
return 0 if ring<=1 else (1 if ring<=3 else 2)   # 3-poziomowy LOD
# render_distance efektywnie 6 (96 m) dla SYLWETEK, ale koszt buildu pierścienia 2 ≈ 1/16 LOD0
```
**Koszt:** **Med (CPU-build), ale per-chunk 16× taniej** — realny dla 4GB/RTX 3050, bo to mało trójkątów i mało VRAM. Daje +50% postrzeganego zasięgu. **Priorytet: Medium** — rób PO tym, jak LOD1 (pkt 3) działa stabilnie.

**(6c) Threading buildu chunków (WorkerThreadPool) — nie "dal", ale odblokowuje wszystko powyżej.**
Skoro CPU-build single-thread to wąskie gardło, a chcesz więcej (LOD1+LOD2) pierścieni — **przenieś meshowanie na `WorkerThreadPool`**:
```gdscript
var task := WorkerThreadPool.add_task(build_chunk_mesh.bind(data, lod))
# w _process sprawdzaj WorkerThreadPool.is_task_completed(task), potem dodaj ArrayMesh na main thread
```
SurfaceTool/ArrayMesh budujesz w wątku (czyste dane), a tylko `mesh_instance.mesh = arr_mesh` i dodanie do drzewa robisz na main thread. To zamienia "stuttery przy doczytywaniu" w płynne tło i pozwala podnieść `chunks_per_frame`.
**Koszt:** **Med (refactor CPU), zero GPU/VRAM.** RTX 3050 + laptop CPU mają zwykle 6-8 rdzeni — marnujesz je teraz w 100%. **Priorytet: HIGH jako enabler** — bez tego LOD2 i jakiekolwiek zwiększenie zasięgu będzie stutterować.

---

## Kolejność wdrożenia (od ROI)

| # | Pozycja | Koszt | Typ | Priorytet |
|---|---------|-------|-----|-----------|
| 1 | `fog_aerial_perspective=1.0` + `fog_sky_affect=1.0` (1A) | Low | GPU | **HIGH** |
| 2 | Depth fog dostrojony do krawędzi (2a) | Low | GPU | **HIGH** |
| 3 | Ground-color skybox proxy (6a) | Low | GPU | **HIGH** |
| 4 | WorkerThreadPool dla buildu (6c) | Med | CPU | **HIGH** (enabler) |
| 5 | Half-res LOD1 ring + skirts (3) | Med | CPU(-) | **HIGH** |
| 6 | Per-chunk dither fade-in (2b) | Low | GPU | Medium |
| 7 | Horizon haze tuning (5) | Low | GPU | Medium |
| 8 | Ultra-LOD2 silhouette ring (6b) | Med | CPU | Medium |
| 9 | Desaturacja dali w shaderze (4) | Low | GPU | Medium/Low |

**Szczera puenta dla 4 GB / RTX 3050 / GDScript:** Pozycje 1-3 (jeden wieczór, zero kodu strukturalnego, czyste property na Environment/Sky) dadzą Ci **70% wrażenia głębi** i ukryją krawędź — zrób je najpierw i oceń, czy w ogóle potrzebujesz reszty. Prawdziwa praca inżynierska to **4+5+8** (threading + LOD ring), które atakują Twoje jedyne realne wąskie gardło — single-thread CPU-build. Nie dotykaj imposterów ani nie zwiększaj render_distance — to ślepe uliczki dla tego sprzętu.

---

## [gamefeel] game feel

I now have the full picture of the actual code. I have everything I need: `Player.gd` (movement in `_physics_process`, camera in `_build_camera`/`_unhandled_input`, attack in `_try_attack`, hit in `take_damage`, flash in `_flash_hit`), `Enemy.gd`, `Main.gd` wiring, `HUD.gd`. SpringArm3D + CameraPivot confirmed. No sound, no particles, no shake, instant velocity (no accel/decel), no coyote time, no hitstop. Now I can write the game feel section grounded in these exact files and line numbers.

---

# SEKCJA GAME FEEL — Voxel RPG (Godot 4.7, RTX 3050 4 GB)

Wszystko poniżej jest oparte o realny kod: `C:/Users/oskar/Downloads/voxel-rpg/src/Player.gd`, `Enemy.gd`, `Main.gd`, `HUD.gd`. Diagnoza stanu wyjściowego, którą potwierdziłem w plikach:

- **Ruch:** `velocity.x/z = direction * speed` (Player.gd:362-363) — prędkość ZERO→MAX w jednej klatce. Brak akceleracji/wyhamowania, brak coyote time, skok tylko `is_on_floor()` (Player.gd:334).
- **Kamera:** `_pivot.rotate_y` i `_spring.rotate_x` zapisywane WPROST z myszy (Player.gd:221-222). Pivot przyklejony sztywno (dziecko gracza, Player.gd:206). Brak wygładzania pozycji, brak lagu, brak shake.
- **Atak:** ustawia flagę + zadaje dmg w tej samej klatce (Player.gd:397-437). Brak hitstop, anticipation, lunge.
- **Trafienie wroga:** `_flash_hit()` (Player.gd:555) — błysk emisji jest. Knockback jest (Player.gd:514). Brak particles, brak impact frame, brak SFX.
- **Dźwięk: kompletny BRAK** (zero AudioStreamPlayer w projekcie).

Architektura wzorcowa: kamera dostaje **własny węzeł świata** (odpięty od gracza), żeby móc ją wygładzać i trząść NIEZALEŻNIE od fizyki gracza. To fundament pod (2)(3)(4).

---

## (1) MOVEMENT FEEL — akceleracja / wyhamowanie / coyote / lepszy skok

**Cel wizualny:** Postać "ma masę" — rusza z lekkim rozpędem i dojeżdża zamiast zatrzymywać się jak wmurowana. Skok wybaczający (coyote + bufor), z wyższym wyskokiem przy przytrzymaniu i szybszym opadaniem (mniej "księżycowo").

**Implementacja (Player.gd, sekcja prędkości poziomej 358-363):** Zamień natychmiastowe przypisanie na `move_toward` z osobnym przyspieszeniem dla startu i hamowania.

```gdscript
# NOWE eksporty (przy speed/sprint_speed, Player.gd:15-17)
@export var ground_accel: float = 60.0     # m/s² rozpęd na ziemi (do max w ~0.10-0.16 s)
@export var ground_decel: float = 80.0     # m/s² wyhamowanie (ostrzejsze niż start = responsywne)
@export var air_accel: float = 18.0        # m/s² słabsza kontrola w powietrzu
@export var jump_buffer_time: float = 0.12 # s — skok "zapamiętany" przed lądowaniem
@export var coyote_time: float = 0.10      # s — można skoczyć tuż po zejściu z krawędzi
@export var jump_cut_multiplier: float = 0.45  # puszczenie spacji = ścięcie wyskoku
@export var fall_gravity_mult: float = 1.6 # cięższe opadanie (mniej "floaty")
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _was_on_floor: bool = false

# W _physics_process — ZASTĄP blok 358-363:
var moving := input_dir != Vector2.ZERO
var can_sprint := Input.is_physical_key_pressed(KEY_SHIFT) and stamina > 0.0
var current_speed: float = sprint_speed if can_sprint else speed
var target_h := Vector2(direction.x, direction.z) * current_speed
var rate: float = (ground_accel if moving else ground_decel)
if not is_on_floor():
    rate = air_accel
var cur_h := Vector2(velocity.x, velocity.z)
cur_h = cur_h.move_toward(target_h, rate * delta)
velocity.x = cur_h.x + _knockback.x
velocity.z = cur_h.z + _knockback.z
```

**Coyote + bufor skoku — ZASTĄP grawitację (330-331) i skok (334-335):**
```gdscript
# liczniki na górze _physics_process (przy _attack_cd itd.)
_coyote = maxf(0.0, _coyote - delta)
_jump_buffer = maxf(0.0, _jump_buffer - delta)
if Input.is_physical_key_pressed(KEY_SPACE):
    _jump_buffer = jump_buffer_time
if is_on_floor():
    _coyote = coyote_time

# grawitacja z cięższym opadaniem:
if not is_on_floor():
    var g := _gravity * (fall_gravity_mult if velocity.y < 0.0 else 1.0)
    velocity.y -= g * delta

# skok z coyote + bufor + jump-cut:
if not is_dead and _jump_buffer > 0.0 and _coyote > 0.0:
    velocity.y = jump_velocity
    _jump_buffer = 0.0
    _coyote = 0.0
    add_trauma(0.15)               # patrz (4) — mikro-szarpnięcie kamery przy skoku
if not Input.is_physical_key_pressed(KEY_SPACE) and velocity.y > 0.0:
    velocity.y *= jump_cut_multiplier   # puszczenie = niższy skok (kontrola wysokości)
```
Uwaga: auto-podskok (Player.gd:351) zostaje bez zmian — to osobny mechanizm dla 1-blokowych stopni.

**Koszt:** **Low, CPU (logika fizyki, kilka float-ów/klatkę).** Zero kosztu GPU/VRAM. Bez znaczenia dla 4 GB.
**Priorytet:** **High.** Największy zwrot z najmniejszej zmiany — to jest 60% odczucia "gra reaguje dobrze".

---

## (2) RUCH KAMERY — wygładzenie pozycji i celu

**Cel wizualny:** Kamera nie jest przyspawana do biodra gracza — podąża miękko, eliminuje mikro-drgania z auto-podskoku i fizyki voxelowej (te `velocity.y = 6.5` na stopniach robią teraz widoczne szarpnięcia).

**Implementacja:** Odepnij CameraPivot od gracza. W `_build_camera()` (Player.gd:200-216) NIE rób `add_child(_pivot)` do gracza — dodaj pivot do roota sceny i dosuwaj go interpolacją w `_process`.

```gdscript
# _build_camera(): zamiast add_child(_pivot) →
get_tree().current_scene.add_child.call_deferred(_pivot)
_pivot.top_level = true   # ignoruj transform rodzica, jedziemy global_position ręcznie
@export var cam_follow_speed: float = 12.0   # wyższe = ciaśniej podąża

# NOWA funkcja, wołana z _process (kamera = wizual, więc _process nie _physics_process):
func _update_camera(delta: float) -> void:
    var target := global_position + Vector3(0.0, 1.6, 0.0)
    # exp smoothing niezależny od FPS:
    var t := 1.0 - exp(-cam_follow_speed * delta)
    _pivot.global_position = _pivot.global_position.lerp(target, t)
```
Wołaj `_update_camera(delta)` na początku `_process` (Player.gd:244). Wzór `1 - exp(-k*delta)` zamiast surowego `lerp(...,k*delta)` daje stałe odczucie przy 60 i 96 FPS.

**Koszt:** **Low, CPU (jeden lerp wektora/klatkę).** Zero GPU.
**Priorytet:** **High.** Bez tego shake i lag (4)(3) nie mają gdzie żyć, a voxelowe szarpnięcia psują całą resztę.

---

## (3) CAMERA LAG — interpolacja podążania, osobno yaw/pitch

**Cel wizualny:** Lekki "ciężar" obrotu kamery — input myszy nie skacze 1:1, tylko dogania. Pitch celowo szybszy niż yaw (pion ma być responsywny, poziom może płynąć), co daje filmowy charakter bez utraty celności.

**Implementacja:** Rozdziel "pożądany" kąt od "aktualnego". Mysz pisze do `_yaw_target/_pitch_target` (Player.gd:221-222), a `_process` dogania.

```gdscript
@export var yaw_lag_speed: float = 18.0     # wolniejszy = większy lag poziomy
@export var pitch_lag_speed: float = 28.0   # szybszy pion = celność
var _yaw_target: float = 0.0
var _pitch_target: float = 0.0

# _unhandled_input — ZASTĄP 221-224:
_yaw_target -= event.relative.x * mouse_sensitivity
_pitch_target -= event.relative.y * mouse_sensitivity
_pitch_target = clampf(_pitch_target, deg_to_rad(-70.0), deg_to_rad(30.0))

# w _update_camera (po lerpie pozycji):
var ty := 1.0 - exp(-yaw_lag_speed * delta)
var tp := 1.0 - exp(-pitch_lag_speed * delta)
_pivot.rotation.y = lerp_angle(_pivot.rotation.y, _yaw_target, ty)
_spring.rotation.x = lerp(_spring.rotation.x, _pitch_target, tp)
```
WAŻNE: kierunek ruchu (Player.gd:355) czyta `_pivot.rotation.y` — teraz to wartość wygładzona, więc ruch i kamera są spójne, a "przód" nie przeskakuje. Celowanie ataku (Player.gd:413) też zostaje spójne.

**Koszt:** **Low, CPU.** Zero GPU/VRAM.
**Priorytet:** **Medium.** Wyraźnie podnosi klasę odczucia, ale po (1)(2). Trzymaj `yaw_lag_speed` ≥16 — za niski robi "pływającą" kamerę, która szkodzi celności w walce.

---

## (4) CAMERA SHAKE — trauma-based, Perlin

**Cel wizualny:** Uderzenia, skok, oberwanie i zabicie wroga dają krótki, organiczny wstrząs kamery. Trauma² (kwadrat) sprawia, że małe trzęsienia są subtelne, a mocne — naprawdę mocne.

**Implementacja:** Pole `_trauma` 0..1 gaśnie liniowo; offset = `trauma²` × Perlin(TIME). Aplikowane na `_spring`/`_camera` PO wygładzeniu rotacji, żeby nie psuło celowania (shake to czysty wizual offsetu).

```gdscript
@export var trauma_decay: float = 1.4        # /s — pełny wstrząs gaśnie w ~0.7 s
@export var shake_max_yaw: float = 0.06       # rad (~3.4°) przy trauma=1
@export var shake_max_pitch: float = 0.05
@export var shake_max_roll: float = 0.08      # roll najmocniejszy = "uderzenie"
var _trauma: float = 0.0
var _noise := FastNoiseLite.new()   # w _ready: _noise.frequency = 2.0
var _shake_t: float = 0.0

func add_trauma(amount: float) -> void:
    _trauma = clampf(_trauma + amount, 0.0, 1.0)

# w _update_camera (na końcu):
if _trauma > 0.0:
    _trauma = maxf(0.0, _trauma - trauma_decay * delta)
    _shake_t += delta
    var s := _trauma * _trauma         # kwadrat — kluczowe dla feel
    var n1 := _noise.get_noise_2d(_shake_t * 40.0, 0.0)
    var n2 := _noise.get_noise_2d(0.0, _shake_t * 40.0)
    var n3 := _noise.get_noise_2d(_shake_t * 40.0, 100.0)
    _camera.rotation.x = n1 * shake_max_pitch * s
    _camera.rotation.y = n2 * shake_max_yaw * s
    _camera.rotation.z = n3 * shake_max_roll * s   # roll = camera, nie spring
else:
    _camera.rotation = Vector3.ZERO
```
**Wyzwalacze (konkretne dawki):**
- Skok: `add_trauma(0.15)` (już w (1)).
- Trafienie wroga moim atakiem: `add_trauma(0.25)` w `_deal_damage_to` (Player.gd:448).
- Oberwanie (take_damage): `add_trauma(0.5)` w Player.gd:503 obok `_flash_hit()`.
- Śmierć wroga: `add_trauma(0.35)`.

**Koszt:** **Low, CPU (3× sample FastNoiseLite/klatkę).** Zero GPU/VRAM. FastNoiseLite jest trywialny.
**Priorytet:** **High** dla feel walki, **ale** twardo wymaga (2) (kamera odpięta). Bez (2) shake walczyłby z transformem gracza.

---

## (5) ATTACK FEEDBACK — hitstop, anticipation, lunge

**Cel wizualny:** Cios ma "ciężar": mikro-zatrzymanie czasu w momencie trafienia (mózg czyta to jako siłę), krótkie cofnięcie ręki przed zamachem (anticipation) i lekki wyrzut postaci do przodu (lunge) — agresja zamiast machania w miejscu.

**Implementacja — HITSTOP (globalny dip time_scale):** Najtańszy, najmocniejszy trik. W `_deal_damage_to` (po zadaniu dmg, Player.gd:449) odpal hitstop. UWAGA: użyj realnego czasu, bo `time_scale` zamraża też timery.

```gdscript
@export var hitstop_normal: float = 0.06   # s (60 ms) — zwykły cios
@export var hitstop_combo: float = 0.10    # s (100 ms) — od 3. combo, cięższe
var _hitstop_busy: bool = false

func _apply_hitstop(duration: float) -> void:
    if _hitstop_busy: return
    _hitstop_busy = true
    Engine.time_scale = 0.05               # niemal stop (nie 0 — fizyka lubi >0)
    await get_tree().create_timer(duration, true, false, true).timeout  # ignore_time_scale=true
    Engine.time_scale = 1.0
    _hitstop_busy = false

# w _try_attack po pętli, jeśli hit_any:
if hit_any:
    _apply_hitstop(hitstop_combo if _combo_count >= 3 else hitstop_normal)
```

**ANTICIPATION + LUNGE:** Rozbij animację (Player.gd:257-266) na fazę cofnięcia i wyrzutu. Przy starcie ataku dodaj impuls do przodu.

```gdscript
@export var lunge_speed: float = 5.0   # m/s krótki zryw do przodu w stronę celu
# w _try_attack (Player.gd:401), po ustaleniu forward:
_knockback.x += forward.x * lunge_speed   # reużywamy gasnący _knockback (już wygasza się 18/s)
_knockback.z += forward.z * lunge_speed

# w _process, blok is_attacking (259-261) — dodaj anticipation w pierwszych 25%:
var t := 1.0 - (_attack_anim_t / attack_anim_time)
var swing: float
if t < 0.25:
    swing = lerpf(0.0, -0.5, t / 0.25)   # cofnięcie ręki (ujemny = w tył)
else:
    swing = sin(((t - 0.25) / 0.75) * PI) * 2.4   # wyrzut do przodu
_arm_r.rotation.x = -swing
```

**Koszt:** **Low.** Hitstop = zmiana jednego floata (`Engine.time_scale`), zero GPU. Lunge reużywa istniejący `_knockback`. Bez wpływu na VRAM.
**Priorytet:** **High.** Hitstop to pojedynczo najsilniejszy element "game juice" w walce.

---

## (6) HIT EFFECTS — błysk, knockback, particles, impact frame

**Cel wizualny:** Trafiony wróg "reaguje całym ciałem": błysk (jest), knockback (jest), do tego krótki **squash** (spłaszczenie modelu = impact frame) i rozbryzg cząstek w punkcie trafienia.

**Implementacja — IMPACT FRAME (squash modelu wroga):** W `Enemy.take_damage` (Enemy.gd:398), obok `_flash_timer`, ustaw scale-punch na `_model`.

```gdscript
# Enemy.gd, w take_damage:
var tw := create_tween()
_model.scale = Vector3(1.25, 0.75, 1.25)   # spłaszcz w pionie, rozszerz w bok
tw.tween_property(_model, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
```
**Wzmocnienie błysku:** Twój flash interpoluje do `Color.WHITE` (Enemy.gd:378) — podbij do nadbieli `Color(2,2,2)` na pierwsze 2 klatki, żeby przebił tonemap ACES (exposure 0.8 zjada zwykłą biel).

**PARTICLES uderzenia (przekierowanie do (7)):** spawn 1× GPUParticles3D one-shot w punkcie kontaktu — szczegóły niżej.

**Koszt:** **Low, CPU.** Tween scale jest darmowy. Squash nie dotyka mesha (tylko transform). Zero VRAM.
**Priorytet:** **Medium.** Błysk+knockback już niosą czytelność; squash to wisienka — tani, więc warto.

---

## (7) PARTICLES — GPUParticles3D, pulowane

**Cel wizualny:** Voxelowy rozbryzg przy trafieniu (kilka małych sześcianów odlatuje), kurz przy lądowaniu, iskry przy śmierci wroga. Styl: **kostki, nie miękkie sprite'y** — trzyma tożsamość voxelową.

**Implementacja:** GPUParticles3D z `QuadMesh`→ lepiej `BoxMesh` 0.08 m jako draw_pass (voxelowy look), one-shot, **pulowane** (jedna scena, `restart()` zamiast instancjonowania). Krytyczne dla 4 GB: NIE twórz nowego ParticleProcessMaterial per trafienie.

```gdscript
# Autoload/Main: jeden zbudowany w kodzie GPUParticles3D, parametry:
var p := GPUParticles3D.new()
p.amount = 12
p.one_shot = true
p.explosiveness = 0.9
p.lifetime = 0.4
var pm := ParticleProcessMaterial.new()
pm.direction = Vector3(0,1,0)
pm.spread = 60.0
pm.initial_velocity_min = 3.0
pm.initial_velocity_max = 6.0
pm.gravity = Vector3(0,-14,0)
pm.scale_min = 0.5; pm.scale_max = 1.0
p.process_material = pm
var bm := BoxMesh.new(); bm.size = Vector3(0.08,0.08,0.08)
p.draw_pass_1 = bm
# trafienie: ustaw p.global_position = punkt, pm.color = kolor wroga, p.restart()
```
Vertex color cząstek = `_base_colors` wroga (rozbryzg "z jego ciała").

**Koszt:** **Low-Med, GPU-render.** 12 cząstek × kostka = ~144 tris/efekt, jednorazowo. To po stronie RENDER (gdzie masz zapas — sam piszesz, że post-proces ma luz), NIE po stronie CPU-build chunku. VRAM: jeden ParticleProcessMaterial + jeden BoxMesh = pomijalne. Limit: trzymaj ≤3 aktywne emittery naraz (pula), żeby fillrate RTX 3050 się nie dławił.
**Priorytet:** **Medium.** Po hitstop/shake. Trzymaj kostki małe (0.08) i krótkie (0.4 s) — kostki przezroczyste/duże biją we fillrate na 4 GB.

---

## (8) SPRZĘŻENIE DŹWIĘKOWE — architektura + dobór

**Cel wizualny (audio):** Kroki zależne od biomu (trawa/piasek/skała/śnieg), świst ataku, mięsiste trafienie, ambient dnia/nocy. Dziś dźwięku NIE MA wcale — to największa pojedyncza luka w "feel".

**Architektura:** Lekki **Autoload `Audio.gd`** + **pula AudioStreamPlayer3D** (8 sztuk) recyklowanych po dystansie. 3D player podążający za graczem dla kroków, osobny 2D/bezpozycyjny dla UI/ambient. Biom czytasz z `Blocks.gd` przez typ bloku pod stopami (masz już `height_at`/typy w VoxelWorld).

```gdscript
# Audio.gd (Autoload)
var _pool: Array[AudioStreamPlayer3D] = []   # 8 sztuk, prealokowane w _ready
func play_3d(stream: AudioStream, pos: Vector3, pitch_var := 0.08, vol_db := 0.0) -> void:
    var pl := _free_player()                 # pierwszy nie-playing z puli
    pl.stream = stream
    pl.global_position = pos
    pl.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)  # rozstrojenie = brak "karabinu"
    pl.volume_db = vol_db
    pl.play()

# Kroki: w Player._physics_process licz dystans przebyty; co ~2.2 m → krok
# biom = _world.block_type_at(global_position - Vector3.UP) → wybór banku sampli
# Atak: Audio.play_3d(SWING, global_position) w _try_attack
# Trafienie: Audio.play_3d(HIT_FLESH, enemy.global_position) w _deal_damage_to
# Oberwanie: Audio.play_3d(HURT, global_position) w take_damage
```
**Dobór (charakter):** kroki = krótkie, stłumione, 3-4 warianty/biom z pitch ±8% (anty-powtarzalność). Atak = whoosh ~120 ms. Trafienie = "thud" z niskim uderzeniem. Ambient = pętla wiatru przez bezpozycyjny player, głośność modulowana przez `DayNight` (cichszy dzień, owady/wiatr nocą — podłącz pod fazę doby, masz już interpolację w DayNight.gd).
**Bus layout:** Master → Music / SFX / Ambient (3 busy, regulacja głośności). Format: **OGG Vorbis** (mniejsze niż WAV, ważne dla pakietu; dekod tani).

**Koszt:** **Low, CPU + RAM (nie VRAM).** Audio nie dotyka GPU ani 4 GB VRAM w ogóle. 8 streamów OGG = parę MB RAM. Pula = zero alokacji w runtime.
**Priorytet:** **High.** Brak dźwięku to teraz najbardziej "martwy" aspekt gry; relatywnie dużo feel za mało roboty, zero kosztu GPU.

---

## KOLEJNOŚĆ WDROŻENIA (wg zwrot/koszt, wszystko CPU — zero zagrożenia dla 4 GB)

1. **(1) Movement feel** — High, Low, natychmiastowa różnica.
2. **(2) Kamera odpięta + smoothing** — High, Low, fundament pod (3)(4).
3. **(5) Hitstop** — High, Low, najmocniejszy juice walki.
4. **(4) Camera shake** — High, Low (wymaga 2).
5. **(8) Audio** — High, Low (CPU/RAM), największa luka.
6. **(3) Camera lag** — Medium.
7. **(6) Impact squash + nadbiel** — Medium.
8. **(7) Particles** — Medium, jedyny element z kosztem GPU-render (ale w obszarze zapasu, nie w CPU-build chunku).

Cały pakiet (1)-(6),(8) to **wyłącznie koszt CPU/RAM** — fizyka, tweeny, time_scale, audio. **Nie dokłada NIC do budowy chunku** (twoje wąskie gardło z notatki) ani do VRAM. Jedynie (7) dotyka GPU-render, gdzie masz zapas. Voxelowa tożsamość zachowana: cząstki to kostki, squash to transform (ostre sześciany bez zmian).

Pliki do edycji (absolutne): `C:/Users/oskar/Downloads/voxel-rpg/src/Player.gd` (1,2,3,4,5,6-lunge,8-kroki/atak), `C:/Users/oskar/Downloads/voxel-rpg/src/Enemy.gd` (6-squash/nadbiel, 8-trafienie/śmierć), nowy `C:/Users/oskar/Downloads/voxel-rpg/src/Audio.gd` (8, jako Autoload w `project.godot`), `C:/Users/oskar/Downloads/voxel-rpg/src/Main.gd` (7-pula particles, podpięcie ambientu do DayNight).

---

## [polish50] 50x polish

Rola: Senior Producer / Tech Art Lead. Poniżej 50 "polish" feature'ów dopasowanych do waszego voxel RPG (Godot 4.7, RTX 3050 4 GB, teren meshowany w GDScript). Koszt: L/M/H z dopiskiem (CPU-build vs GPU-render gdzie istotne). Priorytet: H/M/L.

## KAMERA (1-7)
1. **Cel:** subtelny bob kroku — *Jak:* w `_process` dodaj `camera.position.y += sin(walk_phase)*0.03` skalowane prędkością. *Koszt:* L (CPU, znikomy). *Pri:* H
2. **Cel:** smooth follow / lag kamery — *Jak:* `cam_pivot.global_position = cam_pivot.global_position.lerp(target, 1.0-exp(-12*delta))`. *Koszt:* L (CPU). *Pri:* H
3. **Cel:** camera shake na trafieniu/skoku — *Jak:* offset z `FastNoiseLite` lub malejący `randf_range` dodawany do rotacji cam przez `trauma*trauma`. *Koszt:* L (CPU). *Pri:* H
4. **Cel:** lekki FOV kick przy sprincie/ataku — *Jak:* `camera.fov = lerp(fov, base+8, delta*8)` w sprincie, powrót w idle. *Koszt:* L (GPU znikomo). *Pri:* M
5. **Cel:** mikro-recoil/punch przy uderzeniu — *Jak:* impuls do `cam_pivot.rotation.x` z tween 0.05s w górę, 0.15s powrót. *Koszt:* L (CPU). *Pri:* M
6. **Cel:** dynamiczne dosunięcie kamery przy ścianie (spring-arm) — *Jak:* `SpringArm3D` jako pivot, ustaw `spring_length`/collision mask na chunki. *Koszt:* L (GPU raycast). *Pri:* H
7. **Cel:** delikatny tilt kamery w skręcie — *Jak:* `cam.rotation.z = lerp(z, -input_x*0.04, delta*6)`. *Koszt:* L (CPU). *Pri:* L

## POSTAĆ (8-16)
8. **Cel:** miękki blob-cień pod postacią — *Jak:* `Decal` z gradientową teksturą koła (lub quad z `billboard`+alpha), podążający za stopami, raycast na grunt. *Koszt:* L (GPU 1 decal). *Pri:* H
9. **Cel:** kurz przy lądowaniu — *Jak:* `GPUParticles3D` one-shot, 12-16 cząstek BoxMesh, emit w `_on_landed()`. *Koszt:* L-M (GPU, krótkie bursty). *Pri:* H
10. **Cel:** pyłki przy kroku (foot dust) — *Jak:* mały one-shot GPUParticles emitowany na footstep event, 4-6 cząstek, krótki lifetime 0.4s. *Koszt:* L (GPU). *Pri:* M
11. **Cel:** squash & stretch przy skoku/lądowaniu — *Jak:* tween `mesh_root.scale` (1,1.15,1)→(1,0.85,1)→(1,1,1) po 0.12s. *Koszt:* L (CPU). *Pri:* M
12. **Cel:** sprężyste przechylenie ciała w ruchu — *Jak:* `body.rotation.z = lerp(z, -velocity_local.x*0.06, delta*8)`. *Koszt:* L (CPU). *Pri:* M
13. **Cel:** obrót głowy ku celowi/kamerze — *Jak:* `head.look_at` z clampem kąta ±40°, lerp. *Koszt:* L (CPU). *Pri:* L
14. **Cel:** ślady stóp znikające na piasku/śniegu — *Jak:* pulla `Decal` (ring buffer ~16), spawn na footstep, fade `albedo_mix` tweenem. *Koszt:* M (GPU, limit decali). *Pri:* L
15. **Cel:** mrugnięcie / mikro-idle (przestępowanie) — *Jak:* addytywny offset pivotów co losowe 3-6s w idle. *Koszt:* L (CPU). *Pri:* L
16. **Cel:** edge highlight / rim na postaci — *Jak:* custom spatial shader: `fresnel = pow(1.0-dot(NORMAL,VIEW),3.0); EMISSION += rim_col*fresnel`. *Koszt:* L (GPU, tylko mesh postaci). *Pri:* M

## ŚWIAT (17-26)
17. **Cel:** wiatr/kołysanie traw i liści — *Jak:* shader na propach: `VERTEX.x += sin(TIME*1.5 + world_pos.z)*0.05*COLOR.a` (maska siły w vertex alpha/wys.). *Koszt:* L (GPU vertex). *Pri:* H
18. **Cel:** trawa/propy na MultiMesh zamiast osobnych MeshInstance — *Jak:* `MultiMeshInstance3D`, instancje per chunk, transformy ustawiane przy budowie. *Koszt:* M CPU-build (raz), oszczędza draw calls. *Pri:* H
19. **Cel:** odległościowe blaknięcie/scale-in chunków (pop-in mask) — *Jak:* przy aktywacji chunku tween `material.albedo.a` lub scale.y 0→1 0.3s. *Koszt:* L (CPU/GPU). *Pri:* M
20. **Cel:** animowana woda (fala + przezroczystość) — *Jak:* shader na blokach wody: `VERTEX.y += sin(TIME+world_x)*0.03`, `ALPHA=0.7`, lekki fresnel. *Koszt:* M (GPU, osobny surface wody). *Pri:* H
21. **Cel:** edge highlight krawędzi voxeli (toon outline) — *Jak:* AO/tint już macie; dodaj jaśniejszy top-face tint w mesherze (`color*1.08` dla normal.y>0.5). *Koszt:* L (CPU-build, 1 mnożenie). *Pri:* M
22. **Cel:** falujące światło pod wodą (caustics) — *Jak:* na podwodnym terenie animowana tekstura w `EMISSION` przez TIME, tani scroll. *Koszt:* L-M (GPU). *Pri:* L
23. **Cel:** kołyszące się/spadające liście (ambient particle biomu) — *Jak:* `GPUParticles3D` lokalny, kilka cząstek liści w lesie, attractor wiatru. *Koszt:* M (GPU). *Pri:* L
24. **Cel:** interaktywne kołysanie traw przy przejściu postaci — *Jak:* przekaż pozycję gracza jako `global uniform`, shader odgina trawę: `bend = clamp(radius-dist,0)*dir`. *Koszt:* M (GPU). *Pri:* M
25. **Cel:** chmurki cienia przesuwające się po terenie (cloud shadows) — *Jak:* sampling animowanej noise tekstury w shaderze terenu mnożący albedo, scroll TIME. *Koszt:* M (GPU, +tekstura). *Pri:* M
26. **Cel:** drobny parallax/sticker-detail na skale — *Jak:* mikro-tint już jest; dodaj `roughness` variance per typ bloku dla zróżnicowania odbić. *Koszt:* L (CPU-build). *Pri:* L

## ATMOSFERA / POGODA (27-34)
27. **Cel:** deszcz — *Jak:* `GPUParticles3D` box emitter nad graczem, podążający, BoxMesh streaki, ~400 cząstek. *Koszt:* M (GPU). *Pri:* M
28. **Cel:** śnieg w biomie zimowym — *Jak:* jak deszcz, wolniejsze, drift sinusem, attractor. *Koszt:* M (GPU). *Pri:* M
29. **Cel:** płynne przejścia pogody (clear→rain) — *Jak:* `WeatherManager` lerpujący `volumetric_fog_density`, glow, particle amount, ambient. *Koszt:* L (CPU sterowanie). *Pri:* M
30. **Cel:** god rays / light shafts o świcie i zachodzie — *Jak:* już macie volumetric fog; podbij `volumetric_fog_density` 0.006 + sun energy w keyframach DayNight przy niskim słońcu. *Koszt:* L (GPU, fog już on). *Pri:* H
31. **Cel:** gwiazdy nocą — *Jak:* w `ProceduralSkyMaterial`/sky shader dodaj noise-threshold punkty w `sky_top` przy nocnym keyframe, fade z energią. *Koszt:* L (GPU). *Pri:* M
32. **Cel:** księżyc — *Jak:* drugi `DirectionalLight3D` (zimny, energy 0.1) aktywny nocą, lub billboard quad na niebie. *Koszt:* L (GPU). *Pri:* L
33. **Cel:** mgła poranna w dolinach (height fog) — *Jak:* podbij `fog_height`/`fog_height_density` w Environment w keyframe świtu DayNight. *Koszt:* L (GPU). *Pri:* M
34. **Cel:** color grading wg pory dnia (LUT/adjustment) — *Jak:* `Environment.adjustment_enabled=true`, tween `adjustment_color_correction` (LUT) + `adjustment_saturation` w DayNight. *Koszt:* L (GPU). *Pri:* M

## AUDIO (35-41)
35. **Cel:** kroki zależne od podłoża — *Jak:* raycast/typ bloku pod stopą → `AudioStreamPlayer3D` losowy sample z banku (trawa/piasek/skała). *Koszt:* L (CPU). *Pri:* H
36. **Cel:** ambient biomu (las/jaskinia/woda) — *Jak:* `AudioStreamPlayer` z pętlą, crossfade volume_db między biomami wg pozycji. *Koszt:* L. *Pri:* H
37. **Cel:** wind ambient skalowany pogodą — *Jak:* loop wiatru, `volume_db` lerp wg WeatherManager. *Koszt:* L. *Pri:* M
38. **Cel:** dzień/noc soundscape (ptaki vs świerszcze) — *Jak:* dwa loopy, crossfade sterowany czasem doby z DayNight. *Koszt:* L. *Pri:* M
39. **Cel:** SFX walki (whoosh/impact/unik) — *Jak:* `AudioStreamPlayer3D` na atak/trafienie/unik, lekki random pitch ±0.1. *Koszt:* L. *Pri:* H
40. **Cel:** reverb w jaskiniach/wnętrzach — *Jak:* `Area3D` przełączający `AudioServer` bus na Reverb effect przy wejściu. *Koszt:* L. *Pri:* L
41. **Cel:** muzyka adaptacyjna (eksploracja↔walka) — *Jak:* dwa stemy, crossfade `volume_db` gdy wróg w aggro. *Koszt:* L. *Pri:* M

## UI / HUD (42-46)
42. **Cel:** płynne paski HP/staminy (lerp + damage chip) — *Jak:* dwa progresy: szybki front + wolny czerwony "chip" lerp 0.5s. *Koszt:* L. *Pri:* H
43. **Cel:** floating damage numbers — *Jak:* `Label3D` lub Control pool, spawn nad celem, tween pozycja↑ + alpha→0 0.8s. *Koszt:* L (CPU). *Pri:* H
44. **Cel:** hit flash na wrogu/postaci — *Jak:* tween `material.albedo`/`emission` na biało 0.08s i powrót przy trafieniu. *Koszt:* L (GPU). *Pri:* H
45. **Cel:** vignette przy niskim HP — *Jak:* `ColorRect` z radialnym shaderem na CanvasLayer, alpha rośnie poniżej 25% HP, lekki puls. *Koszt:* L (GPU full-screen, prosty). *Pri:* M
46. **Cel:** screen flash / czerwony tint przy obrażeniach — *Jak:* `ColorRect` alpha 0.3→0 tween 0.25s na otrzymanie ciosu. *Koszt:* L (GPU). *Pri:* M

## WALKA (47-50)
47. **Cel:** hit-stop / freeze-frame na trafieniu — *Jak:* `Engine.time_scale=0.05` na 0.05s przez timer/await, potem 1.0. *Koszt:* L (CPU). *Pri:* H
48. **Cel:** trail broni przy zamachu — *Jak:* `GPUParticles3D` trail lub proceduralny `ImmediateMesh`/ribbon wzdłuż łuku ataku, fade 0.2s. *Koszt:* M (GPU). *Pri:* M
49. **Cel:** knockback + impact particles na trafieniu — *Jak:* impuls do velocity celu + one-shot GPUParticles iskier/voxel-chunków w punkcie kontaktu. *Koszt:* L-M (GPU). *Pri:* H
50. **Cel:** telegraph ataku wroga (wind-up flash) — *Jak:* przed atakiem tween `emission` wroga + skala 1.1 przez 0.3s jako czytelny sygnał. *Koszt:* L (GPU/CPU). *Pri:* H

Uwagi wdrożeniowe (4 GB / RTX 3050):
- Najwyższy ROI względem kosztu: 8 (blob shadow), 17 (wiatr trawy), 35/36 (audio kroki+ambient), 42-44/47 (game-feel walki). Wszystko L i mocno podnosi "produkcyjność".
- GPUParticles trzymaj jako krótkie one-shoty z małym `amount` i poolinguj/limit jednoczesnych emiterów — VRAM na bufory cząstek jest tani, ale wiele ciągłych emiterów + deszcz potrafią zjeść fillrate.
- Wszystkie custom shadery (16, 17, 20, 24, 25) to koszt GPU-render — macie tam zapas; unikaj dokładania czegokolwiek do CPU-build chunku (stąd 21/26 jako tanie mnożenia w mesherze, nie nowe przebiegi).
- Decale (8, 14) i full-screen ColorRecty (45, 46) są tanie na tym GPU; pilnuj tylko liczby aktywnych decali (limit ~16).

---
