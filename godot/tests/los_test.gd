# =============================================================================
# DUSTFALL — LINE OF SIGHT TEST (Session #3, 2026-10-08)
# Tim's pick: fix the Bresenham asymmetry AND build the two July rules
# (cover-degraded LOS, high ground sees over cover).
#   1) SYMMETRY: on the canonical mesa board, for every pair of flat passable
#      tiles has_los(a, b) == has_los(b, a). The old single-direction line had
#      336 one-way pairs.
#   2) walls still block; open lanes still clear (regression vs positioning_test)
#   3) INTERVENING COVER: a shot through a cover tile adds that cover to the
#      defender's band; capped at LOS_COVER_CAP; a shooter on h1 sees over it;
#      point-blank has nothing between; ignore-cover weapons bypass it
#      (hit_chance with ignore_cover); hunker still stacks under the 0.6 cap.
# Run: godot --headless --path godot --script res://tests/los_test.gd
# =============================================================================
extends SceneTree

const CombatCoreScript = preload("res://scripts/combat_core.gd")

var fails := 0
var passes := 0

func _check(name: String, cond: bool, detail := "") -> void:
	if cond:
		passes += 1
		print("  PASS  " + name)
	else:
		fails += 1
		print("  FAIL  " + name + ("  (" + detail + ")" if detail != "" else ""))

func _u(q: int, r: int, extra := {}) -> Dictionary:
	var u := {"q": q, "r": r, "alive": true, "side": "p", "aim": 70, "rng": 6, "str": 4,
		"status": {"burn": 0, "bleed": 0, "hex": 0, "marked": 0, "hunker": 0, "stun": 0, "conf": 0}}
	u.merge(extra, true)
	return u

func _init() -> void:
	var core = CombatCoreScript.new()
	var grid: Array = core.build_grid()

	print("== 1) symmetry on the mesa board ==")
	var flats: Array = []
	for r in core.ROWS:
		for q in core.COLS:
			if int(grid[r][q]["h"]) < 2:
				flats.append([q, r])
	var one_way := 0
	var pairs := 0
	var blocked := 0
	for i in flats.size():
		for j in range(i + 1, flats.size()):
			var a := _u(flats[i][0], flats[i][1])
			var b := _u(flats[j][0], flats[j][1])
			var ab: bool = core.has_los(grid, a, b)
			var ba: bool = core.has_los(grid, b, a)
			pairs += 1
			if ab != ba:
				one_way += 1
			if not ab:
				blocked += 1
	_check("every flat pair is symmetric (%d pairs, %d blocked)" % [pairs, blocked], one_way == 0, "%d one-way pairs" % one_way)
	_check("walls still block some lanes", blocked > 0)

	print("== 2) wall / lane regressions ==")
	# wall at (4,4) h2 — shooting across it from (2,4) to (6,4) must be blocked
	_check("LOS blocked by full-height wall", not core.has_los(grid, _u(2, 4), _u(6, 4)))
	_check("...and the reverse is blocked too", not core.has_los(grid, _u(6, 4), _u(2, 4)))
	_check("open lane clear (0,0)->(0,9)", core.has_los(grid, _u(0, 0), _u(0, 9)))
	# the two-tile diagonal seam h2 (4,4)+(5,5): a straight diagonal shot across it
	_check("diagonal seam across (4,4)/(5,5) is blocked both ways",
		not core.has_los(grid, _u(3, 3), _u(6, 6)) and not core.has_los(grid, _u(6, 6), _u(3, 3)))

	print("== 3) intervening cover ==")
	var g2: Array = []
	for r in core.ROWS:
		var row: Array = []
		for q in core.COLS:
			row.append({"h": 0, "cover": 0.0, "cover0": 0.0, "chp": 0, "heavy": false, "rough": false})
		g2.append(row)
	# heavy rock at (5,2) between a shooter at (2,2) and a target at (8,2) on bare ground
	g2[2][5]["cover"] = 0.4; g2[2][5]["cover0"] = 0.4; g2[2][5]["chp"] = -1; g2[2][5]["heavy"] = true
	var att := _u(2, 2)
	var def := _u(8, 2)
	_check("shot through heavy cover still has LOS", core.has_los(g2, att, def))
	_check("intervening heavy = 0.4", is_equal_approx(core.intervening_cover(g2, att, def), 0.4), str(core.intervening_cover(g2, att, def)))
	_check("cover_bonus on a bare target through a rock = 0.4", is_equal_approx(core.cover_bonus(g2, att, def), 0.4))
	var hc_through: int = core.hit_chance(g2, att, def, false)
	var hc_clear: int = core.hit_chance(g2, _u(2, 3), _u(8, 3), false)
	_check("hit chance drops by 40 through the rock (%d vs %d)" % [hc_through, hc_clear], hc_clear - hc_through == 40)
	_check("ignore-cover weapon bypasses intervening cover", core.hit_chance(g2, att, def, true) == hc_clear)
	# symmetric: the target shooting back through the same rock pays the same
	_check("intervening cover is symmetric", is_equal_approx(core.intervening_cover(g2, def, att), 0.4))
	# cap: two heavy rocks on the line still cap at LOS_COVER_CAP
	g2[2][6]["cover"] = 0.4; g2[2][6]["cover0"] = 0.4; g2[2][6]["chp"] = -1; g2[2][6]["heavy"] = true
	_check("two rocks cap at LOS_COVER_CAP", is_equal_approx(core.intervening_cover(g2, att, def), core.LOS_COVER_CAP))
	# own-tile cover + intervening + hunker still capped at 0.6
	g2[2][8]["cover"] = 0.4; g2[2][8]["cover0"] = 0.4; g2[2][8]["chp"] = -1; g2[2][8]["heavy"] = true
	def["status"]["hunker"] = 2
	_check("own cover + intervening + hunker caps at 0.6", is_equal_approx(core.cover_bonus(g2, att, def), 0.6))
	def["status"]["hunker"] = 0
	g2[2][8]["cover"] = 0.0; g2[2][8]["cover0"] = 0.0; g2[2][8]["chp"] = 0; g2[2][8]["heavy"] = false
	# high ground sees over: shooter on an h1 tile ignores the rocks
	g2[2][2]["h"] = 1
	_check("shooter on high ground sees over intervening cover", is_equal_approx(core.intervening_cover(g2, att, def), 0.0))
	_check("...but the low target shooting up still pays it", is_equal_approx(core.intervening_cover(g2, def, att), core.LOS_COVER_CAP))
	g2[2][2]["h"] = 0
	# point-blank: nothing between adjacent tiles
	_check("point-blank has no intervening cover", is_equal_approx(core.intervening_cover(g2, _u(4, 2), _u(5, 2)), 0.0))
	# beacon target on h1: own cover 0 but intervening still applies from a low shooter
	g2[2][8]["h"] = 1
	_check("beacon target still shielded by the rocks between", is_equal_approx(core.cover_bonus(g2, att, def), core.LOS_COVER_CAP))
	g2[2][8]["h"] = 0
	# light cover decays: a degraded wagon contributes its CURRENT cover
	g2[2][5]["cover"] = 0.2 * (2.0 / 3.0); g2[2][5]["cover0"] = 0.2; g2[2][5]["chp"] = 2; g2[2][5]["heavy"] = false
	g2[2][6]["cover"] = 0.0; g2[2][6]["cover0"] = 0.0; g2[2][6]["chp"] = 0; g2[2][6]["heavy"] = false
	_check("degraded light cover contributes its current value", is_equal_approx(core.intervening_cover(g2, att, def), 0.2 * (2.0 / 3.0)))

	print("")
	print("los_test: %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)
