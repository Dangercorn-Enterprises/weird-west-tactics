# =============================================================================
# DUSTFALL — Positioning v1 mechanics test (LOS, banded cover, high ground)
# Run:  godot --headless --path godot --script res://tests/positioning_test.gd
# Asserts the new tactical rules directly (deterministic — no win-rate RNG).
# =============================================================================
extends SceneTree

var core: CombatCore
var passed := 0
var failed := 0

func ok(name: String, cond: bool) -> void:
	if cond:
		passed += 1
		print("  PASS  ", name)
	else:
		failed += 1
		print("  FAIL  ", name)

func _u(q: int, r: int, extra := {}) -> Dictionary:
	var u := {"q": q, "r": r, "aim": 75, "rng": 8, "str": 6, "wmin": 4, "wmax": 8,
		"status": {"hex": 0, "hunker": 0, "marked": 0, "bleed": 0, "burn": 0,
			"stun": 0, "conf": 0}}
	u.merge(extra, true)
	return u

func _initialize() -> void:
	core = CombatCore.new()
	var g := core.build_grid()

	# --- LOS -----------------------------------------------------------------
	# walls sit at [4,4] and [5,5]. Shoot across [4,4] from [4,2] to [4,6].
	ok("LOS blocked by full-height wall",
		not core.has_los(g, _u(4, 2), _u(4, 6)))
	ok("LOS clear along an open lane",
		core.has_los(g, _u(0, 0), _u(0, 9)))
	# high ground sees over a wall of equal/lower height
	g[4][4]["h"] = 2  # ensure wall
	var hi := _u(4, 2); var lo := _u(4, 6)
	# put the shooter up on a h2 perch so att_h(2) > def_h(0)
	g[2][4]["h"] = 2
	ok("high ground sees over a wall",
		core.has_los(g, _u(4, 2), _u(4, 6)))
	g[2][4]["h"] = 0  # reset perch

	# --- cover bonus ---------------------------------------------------------
	g = core.build_grid()
	# a known heavy tile [2,3]=0.4, light tile [3,5]=0.2
	var att := _u(0, 3)  # far, low ground, not point-blank
	ok("heavy cover gives 0.4 bonus",
		is_equal_approx(core.cover_bonus(g, att, _u(2, 3)), 0.4))
	ok("light cover gives 0.2 bonus",
		is_equal_approx(core.cover_bonus(g, att, _u(3, 5)), 0.2))
	ok("no cover on bare tile is 0",
		is_equal_approx(core.cover_bonus(g, att, _u(0, 5)), 0.0))
	# point-blank flank negates cover
	ok("point-blank negates cover",
		is_equal_approx(core.cover_bonus(g, _u(2, 2), _u(2, 3)), 0.0))
	# high ground halves the defender's cover (shooting down over it)
	var hi_att := _u(0, 3); g[hi_att["r"]][hi_att["q"]]["h"] = 2
	ok("high-ground attacker halves target cover",
		is_equal_approx(core.cover_bonus(g, hi_att, _u(2, 3)), 0.2))
	g[hi_att["r"]][hi_att["q"]]["h"] = 0
	# beacon: a defender ON high ground gets no cover even if the tile has some
	g = core.build_grid()
	g[3][2]["h"] = 1  # [2,3] heavy cover tile, now also elevated
	ok("defender on high ground is a beacon (no cover)",
		is_equal_approx(core.cover_bonus(g, att, _u(2, 3)), 0.0))
	# hunker adds to cover (and a hunkered beacon still gets the hunker floor)
	g = core.build_grid()
	var hunk_def := _u(2, 3, {"status": {"hunker": 1, "hex": 0, "marked": 0,
		"bleed": 0, "burn": 0, "stun": 0, "conf": 0}})
	ok("hunker adds to cover bonus (0.4 -> 0.6)",
		is_equal_approx(core.cover_bonus(g, att, hunk_def), 0.6))
	# cap: hunker can never push cover past the 0.6 ceiling
	ok("cover bonus caps at 0.6",
		core.cover_bonus(g, att, hunk_def) <= 0.6 + 0.0001)

	# --- destructible cover --------------------------------------------------
	g = core.build_grid()
	var b := {"grid": g}
	# heavy tile [2,3]: bullets never crack it
	var heavy_before: float = g[3][2]["cover"]
	core.strike_cover(b, 2, 3)
	ok("small arms never degrade heavy cover",
		is_equal_approx(g[3][2]["cover"], heavy_before))
	# light tile [3,5]: degrades over LIGHT_COVER_HP strikes, bonus decays
	ok("light cover starts at 0.2", is_equal_approx(g[5][3]["cover"], 0.2))
	core.strike_cover(b, 3, 5)
	ok("light cover bonus decays after a strike", g[5][3]["cover"] < 0.2)
	core.strike_cover(b, 3, 5)
	core.strike_cover(b, 3, 5)
	ok("light cover is GONE after LIGHT_COVER_HP strikes",
		is_equal_approx(g[5][3]["cover"], 0.0))
	# explosives: delete light, crack heavy
	g = core.build_grid()
	b = {"grid": g, "units": []}
	core.do_blast(b, {"q": 3, "r": 5})  # centered on a light-cover tile
	ok("explosive deletes light cover", is_equal_approx(g[5][3]["cover"], 0.0))
	g = core.build_grid()
	b = {"grid": g, "units": []}
	var heavy0: float = g[3][2]["cover"]
	core.do_blast(b, {"q": 2, "r": 3})  # centered on a heavy-cover tile
	ok("explosive cracks heavy cover (reduced, not immune)",
		g[3][2]["cover"] < heavy0)

	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
