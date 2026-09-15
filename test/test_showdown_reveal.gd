extends GutTest

## Tests for the showdown reveal pipeline: reveal ordering, best-5 mapping,
## gross-vs-net accounting, hand detail strings, and the show-all/muck setting.

const SB := 10
const BB := 20
const STACK := 1000


func _make_game(count: int = 4, seed_value: int = 777) -> PokerGame:
	var defs: Array = []
	for i in range(count):
		defs.append({
			"id": i,
			"name": "P%d" % i,
			"chips": STACK,
			"human": false,
			"personality": "balanced",
		})
	var game := PokerGame.new()
	game.setup(defs, SB, BB, seed_value)
	return game


## Check (or call when checked into) every decision: no new aggression.
func _play_checkdown(game: PokerGame) -> void:
	var guard := 0
	while not game.hand_over and guard < 200:
		guard += 1
		var la := game.get_legal_actions()
		if la.get("can_check", false):
			game.apply("check")
		elif la.get("can_call", false):
			game.apply("call")
		else:
			game.apply("fold")
	assert_eq(game.street, PokerGame.Street.SHOWDOWN, "checkdown reaches showdown")


func _card(rank: int, suit: int) -> Card:
	return Card.new(rank, suit)


func test_detail_strings() -> void:
	var pair := HandEvaluator.evaluate_5([
		_card(9, 0), _card(9, 1), _card(14, 2), _card(12, 3), _card(5, 1)])
	assert_eq(HandEvaluator.detail(pair), "Pair of 9s, Ace-Queen-5 kickers")
	var high := HandEvaluator.evaluate_5([
		_card(14, 0), _card(9, 1), _card(7, 2), _card(5, 3), _card(3, 1)])
	assert_eq(HandEvaluator.detail(high), "Ace-high")
	var flush := HandEvaluator.evaluate_5([
		_card(14, 2), _card(11, 2), _card(9, 2), _card(6, 2), _card(3, 2)])
	assert_eq(HandEvaluator.detail(flush), "Ace-high Flush")
	var boat := HandEvaluator.evaluate_5([
		_card(13, 0), _card(13, 1), _card(13, 2), _card(4, 3), _card(4, 0)])
	assert_eq(HandEvaluator.detail(boat), "Kings over 4s")
	var wheel := HandEvaluator.evaluate_5([
		_card(14, 0), _card(5, 1), _card(4, 2), _card(3, 3), _card(2, 0)])
	assert_eq(HandEvaluator.detail(wheel), "5-high Straight")
	var quads := HandEvaluator.evaluate_5([
		_card(12, 0), _card(12, 1), _card(12, 2), _card(12, 3), _card(9, 0)])
	assert_eq(HandEvaluator.detail(quads), "Four Queens, 9 kicker")
	var two := HandEvaluator.evaluate_5([
		_card(11, 0), _card(11, 1), _card(4, 2), _card(4, 3), _card(14, 0)])
	assert_eq(HandEvaluator.detail(two), "Jacks and 4s, Ace kicker")


func test_reveal_defaults_to_show_all() -> void:
	var game := _make_game()
	assert_eq(game.showdown_reveal_mode, "show_all")


func test_checkdown_reveal_is_button_left_order() -> void:
	var game := _make_game()
	game.start_hand()
	_play_checkdown(game)
	assert_eq(game.last_aggressor, -1, "no aggression on a pure checkdown")
	var contenders: Array = []
	for p in game.players:
		if not p.folded and not p.out:
			contenders.append(p.id)
	assert_eq(game.reveal_order.size(), contenders.size())
	assert_eq(game.revealed_ids, game.reveal_order, "show-all reveals everyone")
	var first_from_button := (game.button + 1) % game.players.size()
	assert_eq(game.reveal_order[0], first_from_button)


func test_river_aggressor_shows_first() -> void:
	var game := _make_game()
	game.start_hand()
	var guard := 0
	while not game.hand_over and guard < 200:
		guard += 1
		if game.street == PokerGame.Street.RIVER and game.last_aggressor < 0:
			var raiser := game.current_player()
			var la := game.get_legal_actions()
			assert_true(la.get("can_raise", false), "river raiser can bet")
			game.apply("raise", int(la["min_raise_to"]) + 20)
			assert_eq(game.last_aggressor, raiser.id)
			continue
		var la2 := game.get_legal_actions()
		if la2.get("can_check", false):
			game.apply("check")
		elif la2.get("can_call", false):
			game.apply("call")
		else:
			game.apply("fold")
	assert_eq(game.street, PokerGame.Street.SHOWDOWN)
	assert_gt(game.last_aggressor, -1)
	assert_eq(game.reveal_order[0], game.last_aggressor, "aggressor shows first")


func test_showdown_rows_carry_hole_best5_and_gross_net() -> void:
	var game := _make_game()
	game.start_hand()
	_play_checkdown(game)
	assert_false(game.showdown_results.is_empty())
	var pot := game.total_pot()
	var paid := 0
	for r in game.showdown_results:
		var p: PokerPlayer = game.players[int(r["player"])]
		assert_eq(int(r["gross"]), p.won_last)
		assert_eq(int(r["amount"]), p.won_last, "amount stays gross for compat")
		assert_eq(int(r["net"]), p.won_last - p.committed)
		assert_true(r.get("revealed", false))
		assert_eq((r["hole"] as Array).size(), 2)
		var best5: Array = r.get("best5", [])
		assert_eq(best5.size(), 5, "best-5 has five cards")
		var all: Array = []
		all.append_array(p.hole)
		all.append_array(game.community)
		for b in best5:
			var found := false
			for c in all:
				if PokerGame.card_matches(c, b):
					found = true
					break
			assert_true(found, "every best-5 card comes from hole+board")
		assert_true(str(r.get("detail", "")).length() > 0, "detail string present")
		if r.get("won", false):
			paid += int(r["gross"])
	assert_eq(paid, pot, "all pot chips are paid out")


func test_muck_losers_hides_beaten_hands() -> void:
	var game := _make_game()
	game.showdown_reveal_mode = "muck_losers"
	game.start_hand()
	_play_checkdown(game)
	var winners: Array = []
	for r in game.showdown_results:
		if r.get("won", false):
			winners.append(int(r["player"]))
	assert_false(winners.is_empty())
	assert_eq(game.revealed_ids.size(), winners.size())
	for r in game.showdown_results:
		if r.get("won", false):
			assert_true(r.get("revealed", false))
		else:
			assert_false(r.get("revealed", true), "losers stay face-down in muck mode")


func test_card_match_helpers() -> void:
	var a := _card(14, 3)
	var same := a
	var twin := _card(14, 3)
	var other := _card(13, 3)
	assert_true(PokerGame.card_matches(a, same))
	assert_true(PokerGame.card_matches(a, twin), "rank+suit fallback matches")
	assert_false(PokerGame.card_matches(a, other))
	assert_false(PokerGame.card_matches(a, null))
	assert_eq(PokerGame.card_indices([other, a, twin], a), [1, 2])
