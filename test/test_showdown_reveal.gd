extends GutTest

## Tests for the showdown reveal pipeline: reveal ordering, best-5 mapping,
## gross-vs-net accounting, hand detail strings, and the show-all/muck setting.

const SB := 10
const BB := 20
const STACK := 1000


func _make_game(count: int = 4, seed_value: int = 777, stack: int = STACK) -> PokerGame:
	var defs: Array = []
	for i in range(count):
		defs.append({
			"id": i,
			"name": "P%d" % i,
			"chips": stack,
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


func _all_in_types(events: Array) -> Array:
	var types: Array = []
	for ev in events:
		types.append(ev.get("type", ""))
	return types


func test_all_in_runout_exposes_hands() -> void:
	var game := _make_game(2, 99, 60)
	game.start_hand()
	assert_eq(game.current_player().id, 0, "heads-up small blind opens")
	game.apply("raise", 60)
	var last: Array = game.apply("call")
	assert_true(game.hand_over)
	var types := _all_in_types(last)
	assert_true(types.has("all_in_showdown"), "exposure opens the runout")
	var exposure: Dictionary = last[types.find("all_in_showdown")]
	assert_eq(exposure["players"], [0, 1])
	assert_eq(game.exposed_ids, [0, 1])
	for ev in last:
		if ev.get("type", "") == "street":
			assert_true(bool(ev.get("runout", false)), "runout streets are flagged")
	assert_true(types.find("all_in_showdown") < types.find("showdown"))
	assert_true(types.find("showdown") < types.find("win"))


func test_no_exposure_when_board_complete() -> void:
	var game := _make_game(2, 5, 60)
	game.start_hand()
	game.events.clear()
	game.street = PokerGame.Street.RIVER
	game.community = [
		Card.new(14, 0), Card.new(13, 1), Card.new(9, 2),
		Card.new(5, 3), Card.new(3, 0)]
	for i in range(2):
		game.players[i].hole = [Card.new(2 + i, 0), Card.new(7 + i, 1)]
		game.players[i].chips = 0
		game.players[i].all_in = true
		game.players[i].committed = 60
	game.button = 0
	game._run_out_and_showdown()
	assert_false(_all_in_types(game.events).has("all_in_showdown"),
		"river all-ins go straight to the ordered reveal")


func test_no_exposure_when_one_player_live() -> void:
	var game := _make_game(2, 6, 500)
	game.start_hand()
	game.events.clear()
	game.street = PokerGame.Street.PREFLOP
	game.community = []
	game.deck = Deck.new(6)
	game.players[0].chips = 0
	game.players[0].all_in = true
	game.players[0].committed = 100
	game.players[0].hole = [Card.new(14, 0), Card.new(14, 1)]
	game.players[1].chips = 400
	game.players[1].all_in = false
	game.players[1].committed = 100
	game.players[1].hole = [Card.new(2, 0), Card.new(7, 1)]
	game.button = 0
	game._run_out_and_showdown()
	assert_true(game.exposed_ids.is_empty(), "a live player keeps cards covered")
	for ev in game.events:
		if ev.get("type", "") == "street":
			assert_false(bool(ev.get("runout", false)))


func test_exposed_hands_stay_revealed_in_muck_mode() -> void:
	var game := _make_game(2, 99, 60)
	game.showdown_reveal_mode = "muck_losers"
	game.start_hand()
	game.apply("raise", 60)
	game.apply("call")
	assert_true(game.hand_over)
	assert_eq(game.revealed_ids.size(), 2, "exposed losers stay face-up")
	for r in game.showdown_results:
		assert_true(r.get("revealed", false))


func test_human_win_message_uses_base_verb() -> void:
	var defs: Array = []
	for i in range(2):
		defs.append({"id": i, "name": "P%d" % i, "chips": 0, "human": i == 0})
	var game := PokerGame.new()
	game.setup(defs, SB, BB, 5)
	game.events.clear()
	game.street = PokerGame.Street.RIVER
	game.community = [
		Card.new(14, 0), Card.new(13, 1), Card.new(9, 2),
		Card.new(5, 3), Card.new(3, 0)]
	game.players[0].hole = [Card.new(14, 1), Card.new(2, 0)]
	game.players[1].hole = [Card.new(4, 0), Card.new(7, 1)]
	for i in range(2):
		game.players[i].out = false
		game.players[i].chips = 0
		game.players[i].all_in = true
		game.players[i].committed = 60
		game.players[i].folded = false
	game.button = 0
	game._do_showdown()
	var won := false
	for ev in game.events:
		if ev.get("type", "") == "win" and int(ev.get("player", -1)) == 0:
			won = true
			assert_true(str(ev.get("message", "")).contains("win 120"),
				"human win message was: %s" % ev.get("message", ""))
	assert_true(won, "human takes the pot")
