extends Node
## NetManager.gd (autoload) — abstrakcja autorytetu sieci (TDD 6.5 / 7). ETAP 0 = STUB SP.
##
## Cala mutacja stanu (HP, loot, smierc, postep) przechodzi przez uslugi bramkowane
## has_authority(). W SP zwraca ZAWSZE true — jestesmy autorytetem. W Etapie 7 ten SAM kod
## dziala na HOSCIE, a klient wysyla intencje (RPC) i odbiera stan (Synchronizer). Co-op to
## DOLOZENIE transportu, NIE przepisanie logiki. API ponizej jest juz gotowe pod retrofit.

## Tryby sesji (gotowe pod Etap 7; w Etapie 0 zawsze SINGLE).
enum Mode { SINGLE, HOST, CLIENT }

const HOST_PEER_ID: int = 1                           # listen-server: host = peer 1

var mode: Mode = Mode.SINGLE


## Czy LOKALNY peer ma autorytet nad encja `_n`. SP: zawsze true.
## Etap 7: true gdy jestesmy hostem LUB jestesmy wlascicielem encji (NetIdentity.owner_peer).
## Argument celowo opcjonalny — wiele wywolan w SP nie ma jeszcze konkretnej encji.
func has_authority(_n: Node = null) -> bool:
	if mode == Mode.SINGLE:
		return true
	# Etap 7 (szkic kontraktu): host ma autorytet nad wszystkim; klient tylko nad swoja encja.
	# W Etapie 0 ta galaz jest nieosiagalna (mode==SINGLE), ale trzyma docelowy ksztalt API.
	if is_host():
		return true
	# Szukamy komponentu po TYPIE (NetIdentity), nie po nazwie wezla — nazwa w scenie moze byc
	# dowolna, a kontrakt ma trzymac sie typu (TDD 1.2). W Etapie 0 ta galaz jest nieosiagalna.
	if _n != null:
		for c in _n.get_children():
			if c is NetIdentity:
				return int(c.owner_peer) == local_peer_id()
	return false


## Czy jestesmy hostem (lub SP — SP to "sesja z jednym peerem-hostem", TDD 6.5).
func is_host() -> bool:
	return mode == Mode.SINGLE or mode == Mode.HOST


## ID lokalnego peera. SP: 1 (wszystko nalezy do peer 1).
func local_peer_id() -> int:
	if mode == Mode.SINGLE:
		return HOST_PEER_ID
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return HOST_PEER_ID


## Czy faktycznie dziala transport sieciowy (Etap 7). W SP zawsze false -> hitstop/time_scale
## globalny dozwolony (TDD 6.4). Trzymane tu, by reszta kodu nie dotykala multiplayer wprost.
func has_network() -> bool:
	return mode != Mode.SINGLE and multiplayer != null and multiplayer.has_multiplayer_peer()
