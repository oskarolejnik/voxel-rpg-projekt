class_name ContentLint
extends RefCounted
## ContentLint.gd — LOOT Faza 7: walidator TREŚCI (items/affixy/sety/gemy) przeciw rejestrom.
## Literówka w `stat`/`payload`/`set_id` IMPORTUJE SIĘ POPRAWNIE, ale jest CICHO MARTWA (modyfikator
## nic nie robi, set nie istnieje). Ten lint łapie to jednym przebiegiem. Uruchamiany przez test
## (LootExpansionTest) i dostępny ręcznie: `print(ContentLint.format_report())`.
##
## NIE jest autoloadem — statyczny; czyta autoloady ItemDB/ContentDB w czasie lintu. Zwraca listę
## stringów-problemów (pusta = czysto). Whitelisty trzymane TU (jedno źródło prawdy walidacji).

# Klasy broni (GDD §7 taksonomia). weapon_class itemu MUSI być z tej listy (puste = nie-broń, OK).
const WEAPON_CLASSES: Array[StringName] = [
	&"sword", &"greatsword", &"dagger", &"axe", &"axe2h", &"mace", &"hammer2h", &"spear",
	&"bow", &"crossbow", &"staff", &"wand", &"shield", &"tome",
]
# Payloady, które EffectComponent FAKTYCZNIE wykonuje (_dispatch + _apply_aura). Inny = martwy proc.
const EFFECT_PAYLOADS: Array[StringName] = [
	&"burn", &"poison", &"bleed", &"chill", &"frost", &"heal", &"shield",
	&"frost_nova", &"fire_nova", &"earthquake",
]
const SLOT_MIN: int = 0
const SLOT_MAX: int = 12      # ItemResource.Slot.AMULET
const RARITY_MAX: int = 7     # ItemResource.Rarity.ANCIENT


## Pełny lint. Zwraca Array[String] problemów (pusta = czysto). Wymaga ItemDB (autoload).
static func lint_all() -> Array:
	var issues: Array = []
	if ItemDB == null:
		issues.append("ContentLint: brak ItemDB (autoload) — nie można lintować")
		return issues
	_lint_items(issues)
	_lint_affixes(issues)
	_lint_sets(issues)
	_lint_gems(issues)
	return issues


static func _valid_stat(stat: StringName) -> bool:
	return StatBlock.STAT_KEYS.has(stat)


static func _valid_class(cid: StringName) -> bool:
	# ContentDB może nie być w teście — wtedy nie blokujemy (zwracamy true).
	if ContentDB == null or not ContentDB.has_method("has_class"):
		return true
	return ContentDB.has_class(cid)


static func _lint_items(issues: Array) -> void:
	for id in ItemDB.items:
		var ir: ItemResource = ItemDB.items[id]
		if ir == null:
			continue
		var who := "ITEM %s" % id
		if int(ir.slot) < SLOT_MIN or int(ir.slot) > SLOT_MAX:
			issues.append("%s: slot %d poza zakresem 0..%d" % [who, int(ir.slot), SLOT_MAX])
		if ir.weapon_class != &"" and not WEAPON_CLASSES.has(ir.weapon_class):
			issues.append("%s: weapon_class '%s' spoza whitelisty" % [who, ir.weapon_class])
		if ir.set_id != &"" and not ItemDB.sets.has(ir.set_id):
			issues.append("%s: set_id '%s' nie istnieje (dangling)" % [who, ir.set_id])
		if ir.req_level < 1:
			issues.append("%s: req_level %d < 1" % [who, ir.req_level])
		for bm in ir.base_modifiers:
			if bm is StatModifier and not _valid_stat((bm as StatModifier).stat):
				issues.append("%s: base_modifier stat '%s' spoza STAT_KEYS (martwy)" % [who, (bm as StatModifier).stat])
		for ef in ir.equip_effects:
			if ef is EffectResource and not EFFECT_PAYLOADS.has((ef as EffectResource).payload):
				issues.append("%s: equip_effect payload '%s' nieobsługiwany (martwy proc)" % [who, (ef as EffectResource).payload])
		for cid in ir.allowed_classes:
			if not _valid_class(cid):
				issues.append("%s: allowed_classes '%s' nie jest klasą" % [who, cid])


static func _lint_affixes(issues: Array) -> void:
	for id in ItemDB.affixes:
		var af: AffixResource = ItemDB.affixes[id]
		if af == null:
			continue
		var who := "AFFIX %s" % id
		if not _valid_stat(af.stat):
			issues.append("%s: stat '%s' spoza STAT_KEYS (martwy)" % [who, af.stat])
		if af.value_min > af.value_max:
			issues.append("%s: value_min %.2f > value_max %.2f" % [who, af.value_min, af.value_max])
		for s in af.allowed_slots:
			if int(s) < SLOT_MIN or int(s) > SLOT_MAX:
				issues.append("%s: allowed_slot %d poza zakresem" % [who, int(s)])


static func _lint_sets(issues: Array) -> void:
	for id in ItemDB.sets:
		var sd: SetResource = ItemDB.sets[id]
		if sd == null:
			continue
		var who := "SET %s" % id
		for fm in sd.fixed_modifiers:
			if fm is StatModifier and not _valid_stat((fm as StatModifier).stat):
				issues.append("%s: fixed_modifier stat '%s' spoza STAT_KEYS (martwy)" % [who, (fm as StatModifier).stat])
		for thr in sd.bonuses:
			for m in sd.bonuses[thr]:
				if m is StatModifier and not _valid_stat((m as StatModifier).stat):
					issues.append("%s: %dpc stat '%s' spoza STAT_KEYS (martwy)" % [who, int(thr), (m as StatModifier).stat])
		for thr in sd.procs:
			for pe in sd.procs[thr]:
				if pe is EffectResource and not EFFECT_PAYLOADS.has((pe as EffectResource).payload):
					issues.append("%s: %dpc proc payload '%s' nieobsługiwany" % [who, int(thr), (pe as EffectResource).payload])


static func _lint_gems(issues: Array) -> void:
	for id in ItemDB.gems:
		var g: GemResource = ItemDB.gems[id]
		if g == null:
			continue
		var who := "GEM %s" % id
		for m in g.modifiers:
			if m is StatModifier and not _valid_stat((m as StatModifier).stat):
				issues.append("%s: modifier stat '%s' spoza STAT_KEYS (martwy)" % [who, (m as StatModifier).stat])


## Czytelny raport (do ręcznego wywołania / logu). "OK" gdy czysto.
static func format_report() -> String:
	var issues := lint_all()
	if issues.is_empty():
		return "[ContentLint] OK — %d itemów, %d afiksów, %d setów, %d gemów czyste" % [
			ItemDB.items.size(), ItemDB.affixes.size(), ItemDB.sets.size(), ItemDB.gems.size()]
	var s := "[ContentLint] %d PROBLEMÓW:\n" % issues.size()
	for i in issues:
		s += "  - %s\n" % i
	return s
