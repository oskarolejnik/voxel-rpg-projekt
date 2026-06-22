class_name NetIdentity
extends Node
## NetIdentity.gd (komponent) — tozsamosc sieciowa encji (TDD 1.2 / 6.5).
## Niesie net_id + owner_peer; helpery autorytetu deleguja do NetManager. W SP wszystko
## nalezy do peer 1 (NetManager.HOST_PEER_ID). Etap 0: szkielet gotowy pod Etap 7.

@export var net_id: int = 0                            # unikalny id encji w sesji (0 = niezarejestrowana)
@export var owner_peer: int = 1                        # peer-wlasciciel (SP: 1 = host)


## Czy LOKALNY peer ma autorytet nad TA encja (delegacja do NetManager). SP: zawsze true.
func has_authority() -> bool:
	return NetManager.has_authority(get_parent())


## Czy ta encja nalezy do lokalnego peera (predykcja ruchu wlasnej postaci w Etapie 7).
func is_owned_locally() -> bool:
	return owner_peer == NetManager.local_peer_id()
