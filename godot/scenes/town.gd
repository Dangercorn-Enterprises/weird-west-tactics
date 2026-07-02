# =============================================================================
# DUSTFALL — TOWN (Godot port)
# Full service hub ported from src/scene_town.js, with the v1.3 art pass:
# the backdrop swaps to each service's interior painting (assets/scenes/
# saloon.png, outfitter.png, shrine.png, forge.png, stable.png, marshal.png,
# doc.png) and the town street when arriving. Services: rest/recruit/rumors,
# buy + equip gear, shrine pray/swear/donate, forge mods, stables mounts,
# marshal bounties, doc healing.
# =============================================================================
extends Control

var GS
var node_data: Dictionary = {}
var cur_service := ""
var recruit: Dictionary = {}

@onready var backdrop: TextureRect = $Backdrop
@onready var tabs: HBoxContainer = $Layout/Tabs
@onready var rows: VBoxContainer = $Layout/Scroll/Rows
@onready var header: Label = $Layout/Header
@onready var flash_label: Label = $Layout/Flash

const LABELS := {
	"saloon": "Saloon", "outfitter": "Outfitter", "shrine": "Shrine",
	"forge": "Forge", "stable": "Stables", "marshal": "Marshal", "doc": "Doc",
}
const NAMES := ["Eli Mourne", "Dolores Vane", "Quint Ashby", "Rosa Quintero",
	"Jeb Hollis", "Lottie Graves", "Amos Pike", "Inez Calder",
	"Wade Sumner", "Pearl Dukes", "Cyrus Flint", "Mae Renner"]
const RUMORS := [
	"\"Forgeworks men been buyin' up every claim east of here. Pay in brass, threaten in iron.\"",
	"\"Folks say the dead don't stay buried out past the Boneyard. Don't camp there.\"",
	"\"There's a witch rides the dust storms. Gets in your head before her coyotes get your throat.\"",
	"\"The army hauled somethin' out of Roswell in crates. Whatever it was, it wasn't empty.\"",
	"\"High ground wins fights out here. Cover keeps you breathin'. Remember it.\"",
]

func _ready() -> void:
	GS = get_node("/root/GameState")
	GS.apply_theme(self)
	GS.headline(header, 24)
	node_data = GS.node_by_id(str(GS.state["location"]))
	if node_data.is_empty():
		node_data = {"name": "Rustwater", "region": "Neutral ground",
			"svc": ["saloon", "outfitter", "shrine"], "god": "coyote", "tier": 1}
	var svc: Array = node_data.get("svc", ["saloon"])
	cur_service = svc[0]
	for s in svc:
		var b := Button.new()
		b.text = LABELS.get(s, s)
		b.pressed.connect(func():
			cur_service = s
			_flash("")
			_render())
		tabs.add_child(b)
	var depart := Button.new()
	depart.text = "Depart → Map"
	depart.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/worldmap.tscn"))
	tabs.add_child(depart)
	_render()

func _set_backdrop(key: String) -> void:
	var path := "res://assets/scenes/%s.png" % key
	if not ResourceLoader.exists(path):
		path = "res://assets/scenes/town_street.png"
	if ResourceLoader.exists(path):
		backdrop.texture = load(path)

func _flash(msg: String) -> void:
	flash_label.text = msg

func _clear_rows() -> void:
	for c in rows.get_children():
		c.queue_free()

func _row(label: String, btn_text: String, cb: Callable, disabled := false) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var b := Button.new()
	b.text = btn_text
	b.disabled = disabled
	b.custom_minimum_size.x = 140
	b.pressed.connect(cb)
	h.add_child(b)
	rows.add_child(h)

func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color("#9a8a6a")
	rows.add_child(l)

func _render() -> void:
	_clear_rows()
	_set_backdrop("town_street" if cur_service == "" else cur_service)
	var g: Dictionary = GS.god_by_id(node_data.get("god"))
	header.text = "%s — %s   ·   Gold %d · Day %d%s" % [
		node_data["name"], node_data.get("region", ""),
		int(GS.state["gold"]), int(GS.state["day"]),
		("  ·  " + str(g["faction"])) if not g.is_empty() else ""]
	match cur_service:
		"saloon": _saloon()
		"outfitter": _outfitter()
		"shrine": _shrine()
		"forge": _forge()
		"stable": _stable()
		"marshal": _marshal()
		"doc": _doc()

# ---- services ----------------------------------------------------------------------
func _saloon() -> void:
	_note("Piano music, crowd noise, wanted posters. The barkeep knows everything and charges for it.")
	_row("Rest — heal the whole crew (costs 1 day)", "Rest", func():
		for p in GS.state["party"]:
			p["hpDamage"] = 0
		GS.state["day"] = int(GS.state["day"]) + 1
		GS.save_game()
		_flash("The crew patches up and sleeps it off. Day %d." % int(GS.state["day"]))
		_render())
	if recruit.is_empty():
		var archs: Array = GS.design["archetypes"]
		var arch: Dictionary = archs[randi() % archs.size()]
		recruit = {"arch": arch, "name": NAMES[randi() % NAMES.size()],
			"cost": 90 + (randi() % 8) * 10}
	var full: bool = GS.state["party"].size() >= 6
	var broke: bool = int(GS.state["gold"]) < int(recruit["cost"])
	_row("Recruit — %s, the %s (%dg)" % [recruit["name"], recruit["arch"]["name"], int(recruit["cost"])],
		"Roster Full" if full else "Hire", func():
			GS.state["gold"] = int(GS.state["gold"]) - int(recruit["cost"])
			var m: Dictionary = GS._mk_member(recruit["arch"]["id"], "r%d" % (Time.get_ticks_msec() % 100000), recruit["name"])
			GS.state["party"].append(m)
			recruit = {}
			GS.save_game()
			_flash("They throw in with you. Crew: %d." % GS.state["party"].size())
			_render(), full or broke)
	_row("Rumors — lean in close", "Listen", func(): _flash(RUMORS[randi() % RUMORS.size()]))

func _gear_label(p: Dictionary, kind: String) -> String:
	var id = p["gear"].get(kind)
	if id == null:
		return {"weapon": "default weapon", "armor": "no armor", "mod": "no mod"}[kind]
	var catalog: Array = GS.design[{"weapon": "weapons", "armor": "armor", "mod": "weapon_mods"}[kind]]
	for it in catalog:
		if it["id"] == id:
			if kind == "weapon":
				return "%s (%d-%d, rng %d)" % [it["name"], it["dmg"][0], it["dmg"][1], it["range"]]
			if kind == "armor":
				return "%s (def %d)" % [it["name"], it["def"]]
			return "%s (%s)" % [it["name"], it["note"]]
	return str(id)

func _cycle_gear(p: Dictionary, kind: String) -> void:
	var catalog: Array = GS.design[{"weapon": "weapons", "armor": "armor", "mod": "weapon_mods"}[kind]]
	var inv: Dictionary = GS.state["inventory"]
	var opts: Array = [null]
	for it in catalog:
		if int(inv.get(it["id"], 0)) > 0:
			if kind == "weapon" and it.has("archetype") and it["archetype"] != p["archetype"]:
				continue
			if kind == "armor" and it.has("faction") and p.get("god") != it["faction"]:
				continue
			opts.append(it["id"])
	var cur = p["gear"].get(kind)
	var idx := opts.find(cur)
	var next = opts[(idx + 1) % opts.size()]
	if next == cur:
		_flash("Nothing else they can use — buy gear first.")
		return
	if cur != null:
		inv[cur] = int(inv.get(cur, 0)) + 1
	if next != null:
		inv[next] = maxi(0, int(inv.get(next, 0)) - 1)
	p["gear"][kind] = next
	GS.save_game()
	_render()

func _outfitter() -> void:
	_note("Guns, armor, and Ashfall charges, frontier-style.")
	var goods: Array = []
	goods.append_array(GS.design["weapons"].slice(0, 4))
	goods.append_array(GS.design["armor"].slice(0, 3))
	goods.append_array(GS.design["consumables"].slice(0, 3))
	for it in goods:
		var own := int(GS.state["inventory"].get(it["id"], 0))
		_row("%s%s%s  [%dg]" % [it["name"],
			(" — " + str(it["note"])) if it.has("note") else "",
			("  (owned %d)" % own) if own > 0 else "", int(it["cost"])],
			"Buy", func():
				GS.state["gold"] = int(GS.state["gold"]) - int(it["cost"])
				GS.state["inventory"][it["id"]] = int(GS.state["inventory"].get(it["id"], 0)) + 1
				GS.save_game()
				_flash("Bought %s." % it["name"])
				_render(), int(GS.state["gold"]) < int(it["cost"]))
	_note("— OUTFIT THE POSSE —")
	for p in GS.state["party"]:
		_row("%s · %s" % [p["name"], _gear_label(p, "weapon")], "Swap Gun", _cycle_gear.bind(p, "weapon"))
		_row("%s · %s" % [p["name"], _gear_label(p, "armor")], "Swap Armor", _cycle_gear.bind(p, "armor"))

func _shrine() -> void:
	var g: Dictionary = GS.god_by_id(node_data.get("god"))
	if g.is_empty():
		_note("No shrine stands here.")
		return
	_note("%s — %s. Corruption: %s" % [g["title"], g["domain"], g["corruption"]])
	_note("Favor with %s: %d  (fuels divine ultimates — 1 per use, empowered at 3+)" % [
		g["name"], int(GS.state["favor"].get(g["id"], 0))])
	_row("Pray — a blessing for your next battle", "Pray (free)", func():
		GS.state["flags"]["blessing"] = g["id"]
		GS.save_game()
		_flash("%s's favor settles over the crew." % g["name"]))
	for p in GS.state["party"]:
		var aligned: bool = p.get("god") == g["id"]
		var sworn = GS.god_by_id(p.get("god"))
		_row("%s — %s" % [p["name"],
			("sworn to " + str(sworn["name"])) if not sworn.is_empty() else "unsworn"],
			"Aligned" if aligned else "Swear to " + str(g["name"]), func():
				p["god"] = g["id"]
				GS.save_game()
				_flash("%s swears to %s. %s granted." % [p["name"], g["name"], g["divine"]["name"]])
				_render(), aligned)
	_row("Donate 50g — raise favor with " + str(g["name"]), "Donate", func():
		GS.state["gold"] = int(GS.state["gold"]) - 50
		GS.state["favor"][g["id"]] = int(GS.state["favor"].get(g["id"], 0)) + 1
		GS.save_game()
		_flash("Favor with %s: %d." % [g["name"], int(GS.state["favor"][g["id"]])])
		_render(), int(GS.state["gold"]) < 50)

func _forge() -> void:
	_note("Hammered brass, Ashfall fire, hot iron. The smith tunes a gun like a fiddle — one mod per rider.")
	for m in GS.design["weapon_mods"]:
		var own := int(GS.state["inventory"].get(m["id"], 0))
		_row("%s — %s%s  [%dg]" % [m["name"], m["note"],
			("  (owned %d)" % own) if own > 0 else "", int(m["cost"])],
			"Buy", func():
				GS.state["gold"] = int(GS.state["gold"]) - int(m["cost"])
				GS.state["inventory"][m["id"]] = int(GS.state["inventory"].get(m["id"], 0)) + 1
				GS.save_game()
				_flash("The smith wraps up a %s." % m["name"])
				_render(), int(GS.state["gold"]) < int(m["cost"]))
	_note("— FIT THE IRONS —")
	for p in GS.state["party"]:
		_row("%s · %s" % [p["name"], _gear_label(p, "mod")], "Swap Mod", _cycle_gear.bind(p, "mod"))

func _stable() -> void:
	var cur = GS.state.get("mount")
	_note("Horses, camels, and one clockwork steed that hisses steam." +
		(" Your team waits at the rail." if cur != null else " The posse walks — for now."))
	for m in GS.design["mounts"]:
		var owned: bool = cur == m["id"]
		_row("%s — %s  (travel ×%s, ambush %d%%)  [%dg]" % [m["name"], m["note"],
			str(m["travelF"]), roundi(float(m["ambushMod"]) * 100), int(m["cost"])],
			"Hitched" if owned else "Buy", func():
				GS.state["gold"] = int(GS.state["gold"]) - int(m["cost"])
				GS.state["mount"] = m["id"]
				GS.save_game()
				_flash("The %s is yours. The frontier just shrank." % m["name"])
				_render(), owned or int(GS.state["gold"]) < int(m["cost"]))

func _marshal() -> void:
	_note("Bounty board, reputation, the occasional posse. Law work pays in gold and grief.")
	var reward := 60 + int(node_data.get("tier", 1)) * 40
	_row("Bounty — clear a nest of trouble (%dg on success)" % reward, "Ride Out", func():
		var pool: Array = GS.design["enemies"].filter(
			func(e): return int(e.get("tier", 1)) <= maxi(1, int(node_data.get("tier", 1))) and not e.get("boss", false))
		var count := 2 + int(node_data.get("tier", 1))
		var enemies: Array = []
		for i in count:
			enemies.append(pool[randi() % pool.size()])
		GS.go_battle({"title": "Bounty: " + str(node_data["name"]),
			"biome": GS.biome_for(node_data.get("god")),
			"enemies": enemies, "context": {"bounty": reward}}))

func _doc() -> void:
	_note("Medicine beyond battlefield bandages — for a price.")
	_row("Full heal + tend wounds (40g)", "Treat", func():
		GS.state["gold"] = int(GS.state["gold"]) - 40
		for p in GS.state["party"]:
			p["hpDamage"] = 0
		GS.save_game()
		_flash("The crew is mended, good as the frontier allows.")
		_render(), int(GS.state["gold"]) < 40)
