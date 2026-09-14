extends GutTest

## Rules-correctness tests for the PokerGame state machine.

const SB := 10
const BB := 20
const STACK := 1000


func _make_game(count: int = 4, seed_value: int = 12345, stack: int = STACK) -> PokerGame:
	var defs: Array = []
	for i in range(count):
		defs.append({
			"id": i,
			"name": "P%d" % i,
			"chips": stack,
			"human": i == 0,
			"personality": "balanced",
		})
	var game := PokerGame.new()
	game.setup(defs, SB, BB, seed_value)
	return game


func _total_chips(game: PokerGame) -> int:
	var total := 0
	for p in game.players:
		total += p.chips
	return total


func _chips_in_play(game: PokerGame) -> int:
	var total := 0
	for p in game.players:
		total += p.chips + p.committed
	return total


func _random_action(game: PokerGame, rng: RandomNumberGenerator) -> void:
	var la := game.get_legal_actions()
	var choices: Array = []
	if la.get("can_fold", false):
		choices.append("fold")
	if la.get("can_check", false):
		choices.append("check")
	if la.get("can_call", false):
		choices.append("call")
	if la.get("can_raise", false):
		choices.append("raise")
	if choices.is_empty():
		return
	var action: String = choices[rng.randi_range(0, choices.size() - 1)]
	if action == "raise":
		var lo: int = la["min_raise_to"]
		var hi: int = la["max_raise_to"]
		var cap: int = mini(hi, lo * 3)
		var amt := cap
		if cap > lo:
			amt = rng.randi_range(lo, cap)
		game.apply(action, amt)
	else:
		game.apply(action)


func test_blinds_posted() -> void:
	var game := _make_game(4)
	game.start_hand()
	var total_bets := 0
	for p in game.players:
		total_bets += p.bet
	assert_eq(total_bets, SB + BB, "Both blinds are in the middle")
	assert_eq(game.total_pot(), SB + BB)


func test_button_rotates() -> void:
	var game := _make_game(4)
	var buttons: Array = []
	for _i in range(5):
		if game.game_over:
			break
		game.start_hand()
		buttons.append(game.button)
		# Fold the hand out so the next one can start cleanly.
		while not game.hand_over:
			game.apply("fold")
	assert_eq(buttons, [0, 1, 2, 3, 0], "Button moves one seat per hand")


func test_heads_up_small_blind_acts_first() -> void:
	var game := _make_game(2)
	game.start_hand()
	assert_eq(game.button, 0)
	assert_eq(game.to_act, game.button, "Heads-up, the button/small blind acts first pre-flop")
	assert_true(game.players[game.button].bet == SB)


func test_fold_to_big_blind() -> void:
	var game := _make_game(4)
	game.start_hand()
	var bb_index := game._big_blind_index()
	var bb_player = game.players[bb_index]
	while not game.hand_over:
		game.apply("fold")
	assert_true(bb_player.is_winner, "Big blind wins when everyone folds")
	assert_eq(bb_player.chips, STACK + SB, "Big blind profits exactly the small blind")


func test_side_pots() -> void:
	var game := _make_game(3)
	game.start_hand()
	# White-box: three players commit 100 / 300 / 300 with the 100 all-in.
	for p in game.players:
		p.committed = 0
		p.folded = false
	game.players[0].committed = 100
	game.players[1].committed = 300
	game.players[2].committed = 300
	var pots: Array = game._build_side_pots()
	assert_eq(pots.size(), 2, "An all-in creates a main and a side pot")
	assert_eq(pots[0]["amount"], 300, "Main pot: 100 x 3")
	assert_eq(pots[1]["amount"], 400, "Side pot: 200 x 2")


func test_uncalled_bet_refunded() -> void:
	var game := _make_game(2)
	game.start_hand()
	for p in game.players:
		p.committed = 0
	game.players[0].committed = 100
	game.players[1].committed = 300
	game.players[1].chips = 0
	game._refund_uncalled()
	assert_eq(game.players[1].chips, 200, "Excess over the call is returned")


func test_exact_tie_splits_pot() -> void:
	# Craft a board that plays the same for both players.
	var game := _make_game(2)
	game.start_hand()
	game.community = [
		Card.new(14, 0), Card.new(13, 1), Card.new(12, 2), Card.new(11, 3), Card.new(10, 0),
	]
	game.players[0].hole = [Card.new(2, 0), Card.new(3, 1)]
	game.players[1].hole = [Card.new(2, 1), Card.new(3, 2)]
	game.players[0].committed = 100
	game.players[1].committed = 100
	game.players[0].chips = 0
	game.players[1].chips = 0
	game._do_showdown()
	assert_eq(game.players[0].chips, 100, "Split pot: half each")
	assert_eq(game.players[1].chips, 100, "Split pot: half each")


func test_min_raise_enforced() -> void:
	var game := _make_game(4)
	game.start_hand()
	var actor = game.current_player()
	var la := game.get_legal_actions()
	assert_eq(la["to_call"], BB)
	assert_eq(la["min_raise_to"], BB + BB, "A raise must at least double the big blind")
	game.apply("raise", 30)  # Below the minimum; engine should clamp up.
	assert_eq(actor.bet, BB + BB, "Raise is clamped to the legal minimum")


func test_all_in_call_does_not_exceed_stack() -> void:
	var game := _make_game(2, 7, 15)
	game.start_hand()
	var player = game.players[game.to_act]
	var la := game.get_legal_actions()
	assert_true(la["is_all_in_call"], "Short stack must call all-in")
	assert_eq(la["call_amount"], 5, "Call is capped at the remaining stack")
	game.apply("call")
	assert_gte(player.chips, 0, "Chips never go negative")
	assert_true(player.all_in)


func test_chip_conservation_over_many_hands() -> void:
	var game := _make_game(4, 99, 100000)
	game.blinds_increase_every = 100000
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var expected := _total_chips(game)
	var hands := 0
	while hands < 300 and not game.game_over:
		if game.active_player_count() <= 1:
			break
		game.start_hand()
		var guard := 0
		while not game.hand_over and guard < 2000:
			guard += 1
			if game.current_player() == null:
				break
			assert_eq(_chips_in_play(game), expected,
				"Chips are conserved during hand %d" % hands)
			_random_action(game, rng)
		assert_lt(guard, 2000, "Hand %d terminated" % hands)
		assert_eq(_total_chips(game), expected,
			"Chips are conserved after hand %d" % hands)
		for p in game.players:
			assert_gte(p.chips, 0, "No negative stacks")
		hands += 1
	assert_gt(hands, 50, "Played a meaningful number of hands")


func test_apply_returns_only_new_events() -> void:
	var game := _make_game(4)
	var dealt := game.start_hand()
	assert_true(dealt.size() > 0)
	var ev := game.apply("fold")
	assert_eq(ev.size(), 1, "A fold that does not end the street emits one event")
	assert_eq(ev[0]["type"], "action")
	var ev2 := game.apply("fold")
	assert_eq(ev2.size(), 1, "Subsequent actions do not replay earlier events")
	assert_ne(ev2[0]["player"], ev[0]["player"], "Each event belongs to the acting player")


func test_short_all_in_does_not_reopen_action() -> void:
	# P0 (button) shoves for less than a full raise after P3 has already called.
	var game := _make_game(4, 31)
	game.players[0].chips = 25
	game.start_hand()
	assert_eq(game.players[0].chips, 25)
	assert_eq(game.current_player().id, 3)
	game.apply("call")
	assert_eq(game.current_player().id, 0)
	assert_true(game.get_legal_actions()["can_raise"])
	game.apply("raise", 25)
	var p0 = game.players[0]
	assert_true(p0.all_in)
	assert_eq(p0.bet, 25)
	# The blinds had not acted yet, so they may still raise.
	assert_eq(game.current_player().id, 1)
	assert_true(game.get_legal_actions()["can_raise"])
	game.apply("call")
	assert_eq(game.current_player().id, 2)
	assert_true(game.get_legal_actions()["can_raise"])
	game.apply("call")
	# P3 already acted, so the short all-in must not reopen raising for them.
	assert_eq(game.current_player().id, 3)
	var la3 := game.get_legal_actions()
	assert_false(la3["can_raise"], "Short all-in must not reopen betting for a player who acted")
	assert_true(la3["can_call"])


func test_odd_chip_goes_left_of_button() -> void:
	var game := _make_game(3, 17)
	game.start_hand()
	game.community = [
		Card.new(14, 0), Card.new(13, 1), Card.new(12, 2), Card.new(11, 3), Card.new(10, 0),
	]
	game.players[0].hole = [Card.new(2, 0), Card.new(3, 1)]
	game.players[1].hole = [Card.new(2, 1), Card.new(3, 2)]
	game.players[2].hole = [Card.new(4, 0), Card.new(5, 1)]
	game.players[2].folded = true
	for i in range(3):
		game.players[i].chips = 0
	game.players[0].committed = 34
	game.players[1].committed = 34
	game.players[2].committed = 33
	game.button = 0
	game._do_showdown()
	assert_eq(game.players[1].chips, 51)
	assert_eq(game.players[0].chips, 50)


func test_all_in_runout_deals_full_board() -> void:
	var game := _make_game(2, 8, 60)
	game.start_hand()
	var guard := 0
	while not game.hand_over and guard < 50:
		guard += 1
		var la := game.get_legal_actions()
		if la.get("can_raise", false):
			game.apply("raise", la["max_raise_to"])
		elif la.get("can_call", false):
			game.apply("call")
		else:
			game.apply("check")
	assert_true(game.hand_over)
	assert_eq(game.community.size(), 5, "Board is run out when everyone is all-in")


func test_short_big_blind_posts_all_in() -> void:
	var game := _make_game(3, 12, 1000)
	game.players[2].chips = 15
	game.start_hand()
	assert_true(game.players[2].all_in)
	assert_eq(game.players[2].bet, 15, "Short big blind posts everything")
	assert_eq(game.current_bet, 15)
	assert_eq(_chips_in_play(game), 1000 + 1000 + 15)


func test_elimination_and_game_over() -> void:
	var game := _make_game(3, 5, 100)
	var guard := 0
	while not game.game_over and guard < 400:
		guard += 1
		game.start_hand()
		var inner := 0
		while not game.hand_over and inner < 500:
			inner += 1
			var la := game.get_legal_actions()
			if la.get("can_raise", false):
				game.apply("raise", la["max_raise_to"])
			elif la.get("can_call", false):
				game.apply("call")
			else:
				game.apply("check")
	assert_true(game.game_over, "Game ends when one player holds all the chips")
	assert_eq(_total_chips(game), 300)
