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


func test_illegal_actions_rejected() -> void:
	var game := _make_game(4)
	game.start_hand()
	# First actor faces the big blind: a free check is illegal.
	var la := game.get_legal_actions()
	assert_gt(la["to_call"], 0)
	var before := game.to_act
	assert_true(game.apply("check").is_empty(), "Cannot check while facing a bet")
	assert_eq(game.to_act, before, "A rejected action does not advance play")
	assert_true(game.apply("bogus").is_empty(), "Unknown actions are rejected")
	assert_eq(game.to_act, before)
	# Reach the flop on checks/calls; the first actor can check, not call.
	var guard := 0
	while game.street == PokerGame.Street.PREFLOP and not game.hand_over and guard < 50:
		guard += 1
		var l := game.get_legal_actions()
		if l.get("can_check", false):
			game.apply("check")
		else:
			game.apply("call")
	assert_eq(game.street, PokerGame.Street.FLOP)
	var flop_la := game.get_legal_actions()
	assert_true(flop_la["can_check"])
	assert_false(flop_la["can_call"])
	var flop_before := game.to_act
	assert_true(game.apply("call").is_empty(), "Cannot call when nothing is bet")
	assert_eq(game.to_act, flop_before)
	# Once the hand is over, no action is accepted.
	while not game.hand_over:
		game.apply("fold")
	assert_true(game.apply("raise", 100).is_empty(), "No actions once the hand is over")


func test_raise_to_current_bet_clamps_to_minimum() -> void:
	var game := _make_game(4)
	game.start_hand()
	var actor := game.current_player()
	game.apply("raise", game.current_bet)
	assert_eq(actor.bet, BB + BB, "A raise at/below the current bet clamps up to the minimum")


func test_blinds_increase_progression() -> void:
	var game := _make_game(4)
	assert_eq(game.small_blind, 10)
	assert_eq(game.big_blind, 20)
	game._increase_blinds()
	assert_eq(game.small_blind, 15)
	assert_eq(game.big_blind, 30)
	game._increase_blinds()
	assert_eq(game.small_blind, 25)
	assert_eq(game.big_blind, 50)
	game._increase_blinds()
	assert_eq(game.small_blind, 40)
	assert_eq(game.big_blind, 80)


func test_flop_bet_and_full_raise_grows_minimum() -> void:
	var game := _make_game(3, 42)
	game.start_hand()
	var guard := 0
	while game.street == PokerGame.Street.PREFLOP and not game.hand_over and guard < 50:
		guard += 1
		var l := game.get_legal_actions()
		if l.get("can_check", false):
			game.apply("check")
		else:
			game.apply("call")
	assert_eq(game.street, PokerGame.Street.FLOP, "Reached the flop on checks/calls")
	assert_eq(game.current_bet, 0)
	assert_eq(game.min_raise, BB, "Minimum raise resets each street")
	# The opener bets the minimum.
	var opener := game.current_player()
	var la0 := game.get_legal_actions()
	assert_true(la0["can_check"])
	assert_eq(la0["min_raise_to"], BB)
	game.apply("raise", la0["min_raise_to"])
	assert_eq(opener.bet, BB)
	assert_eq(game.current_bet, BB)
	# A full raise grows the minimum increment and reopens the action.
	var raiser := game.current_player()
	game.apply("raise", game.current_bet + 2 * BB)
	assert_eq(raiser.bet, 3 * BB)
	assert_eq(game.min_raise, 2 * BB, "A full raise updates the minimum increment")
	var la2 := game.get_legal_actions()
	assert_true(la2["can_raise"])
	assert_eq(la2["min_raise_to"], game.current_bet + 2 * BB)
	# Everyone calls; the street completes onto the turn with clean resets.
	guard = 0
	while game.street == PokerGame.Street.FLOP and not game.hand_over and guard < 50:
		guard += 1
		var l2 := game.get_legal_actions()
		if l2.get("can_check", false):
			game.apply("check")
		elif l2.get("can_call", false):
			game.apply("call")
		else:
			game.apply("fold")
	assert_eq(game.street, PokerGame.Street.TURN)
	assert_eq(game.current_bet, 0)


func test_three_way_all_in_does_not_skip_pending_call() -> void:
	# P0 and P1 shove for 100; the big blind (P2) still owes 80 and must get a
	# turn instead of being swept into an immediate run-out.
	var game := _make_game(3)
	game.players[0].chips = 100
	game.players[1].chips = 100
	game.players[2].chips = 1000
	game.start_hand()
	assert_eq(game.current_player().id, 0)
	game.apply("raise", 100)
	assert_eq(game.current_player().id, 1)
	game.apply("call")
	assert_eq(game.current_player().id, 2, "A lone caller who owes chips is not skipped")
	var la := game.get_legal_actions()
	assert_true(la["can_call"], "The big blind can call the all-in")
	assert_false(la["can_check"], "The big blind still faces a bet")
	game.apply("call")
	assert_true(game.hand_over)
	assert_eq(game.community.size(), 5, "Board runs out once betting is truly closed")


func test_no_raise_into_dry_side_pot() -> void:
	# Heads-up: P0 (short) shoves all-in. P1 has chips but no opponent can
	# call, so raising is illegal -- only call or fold.
	var game := _make_game(2)
	game.players[0].chips = 100
	game.start_hand()
	assert_eq(game.current_player().id, 0)
	game.apply("raise", 100)
	assert_eq(game.current_player().id, 1)
	var la := game.get_legal_actions()
	assert_true(la["can_call"])
	assert_false(la["can_raise"], "No raising when every opponent is all-in")


func test_fold_out_refunds_uncalled_chips() -> void:
	var game := _make_game(2)
	game.start_hand()
	assert_eq(game.current_player().id, 0)
	game.apply("raise", 500)
	assert_eq(game.current_player().id, 1)
	game.apply("fold")
	assert_true(game.hand_over)
	# SB put in 500, but only the big blind's 20 was actually at stake.
	assert_eq(game.players[0].won_last, 40, "Pot excludes the returned 480")
	assert_eq(game.players[0].net_last, 20, "Net win is the folded big blind")
	assert_eq(game.players[0].chips, 1020, "Own uncalled chips come back")


func test_showdown_results_one_row_per_player() -> void:
	# Board plays for everyone: a three-way tie with a side pot. Each player
	# must appear exactly once in showdown_results, never once per pot.
	var game := _make_game(3, 17)
	game.start_hand()
	game.community = [
		Card.new(14, 0), Card.new(13, 1), Card.new(12, 2), Card.new(11, 3), Card.new(10, 0),
	]
	game.players[0].hole = [Card.new(2, 0), Card.new(3, 1)]
	game.players[1].hole = [Card.new(2, 1), Card.new(3, 2)]
	game.players[2].hole = [Card.new(4, 0), Card.new(5, 1)]
	for i in range(3):
		game.players[i].folded = false
		game.players[i].chips = 0
	game.players[0].committed = 100
	game.players[1].committed = 300
	game.players[2].committed = 300
	game._do_showdown()
	assert_eq(game.showdown_results.size(), 3, "One row per non-folded player")
	var ids: Array = []
	for r in game.showdown_results:
		ids.append(r["player"])
		assert_eq(r["amount"], game.players[r["player"]].won_last)
		assert_eq(r["net"], game.players[r["player"]].net_last)
	for i in range(3):
		assert_eq(ids.count(i), 1, "Player %d appears exactly once" % i)


func test_short_small_blind_all_in_closes_betting_at_deal() -> void:
	# Heads-up: the small blind is all-in for less than the big blind, so the
	# big blind has no call to make and no opponent to bet into -- the board
	# must run out instead of offering a meaningless action.
	var game := _make_game(2)
	game.players[0].chips = 10
	game.start_hand()
	assert_true(game.players[0].all_in)
	assert_eq(game.current_bet, 20)
	assert_true(game.hand_over, "Betting is closed once the only opponent is all-in")
	assert_eq(game.community.size(), 5, "The board runs out to a showdown")


func test_ai_raise_message_agrees() -> void:
	var game := _make_game(4)
	game.start_hand()
	# Seat 3 opens preflop and is AI; a raise must read "raises to", not "raise tos".
	assert_eq(game.current_player().id, 3)
	var events := game.apply("raise", 60)
	assert_false(events.is_empty())
	assert_true(str(events[0].get("message", "")).contains("raises to 60"),
		"AI raise message was: %s" % events[0].get("message", ""))


func test_blind_labels_clear_on_new_street() -> void:
	var game := _make_game(4)
	game.start_hand()
	var sb_seen := false
	for p in game.players:
		if p.last_action == "Small blind":
			sb_seen = true
	assert_true(sb_seen, "blinds tag the opener preflop")
	var guard := 0
	while not game.hand_over and game.street == PokerGame.Street.PREFLOP and guard < 50:
		guard += 1
		var la := game.get_legal_actions()
		if la.get("can_check", false):
			game.apply("check")
		elif la.get("can_call", false):
			game.apply("call")
		else:
			game.apply("fold")
	if game.street != PokerGame.Street.PREFLOP and not game.hand_over:
		for p in game.players:
			assert_false(p.last_action == "Small blind" or p.last_action == "Big blind",
				"blind tags do not leak past preflop")


func test_pot_raise_targets() -> void:
	# Preflop, blinds 10/20: pot 30, facing 20. Call (pot 50), raise 50 -> 70.
	assert_eq(PokerGame.pot_raise_target(20, 30, 20, 1.0, 40, 1000), 70)
	assert_eq(PokerGame.pot_raise_target(20, 30, 20, 0.5, 40, 1000), 45)
	# Flop, pot 100, bet 40: call (pot 140), raise 140 -> 180; half -> 110.
	assert_eq(PokerGame.pot_raise_target(40, 100, 40, 1.0, 80, 1000), 180)
	assert_eq(PokerGame.pot_raise_target(40, 100, 40, 0.5, 80, 1000), 110)
	# Opening into an empty street: pot bet, half pot.
	assert_eq(PokerGame.pot_raise_target(0, 60, 0, 1.0, 20, 1000), 60)
	assert_eq(PokerGame.pot_raise_target(0, 60, 0, 0.5, 20, 1000), 30)
	# Clamped to the legal window.
	assert_eq(PokerGame.pot_raise_target(20, 30, 20, 1.0, 100, 1000), 100)
	assert_eq(PokerGame.pot_raise_target(40, 100, 40, 1.0, 80, 150), 150)


func test_showdown_event_comes_before_win_events() -> void:
	var game := _make_game(4)
	game.start_hand()
	var last: Array = []
	var guard := 0
	while not game.hand_over and guard < 200:
		guard += 1
		var la := game.get_legal_actions()
		if la.get("can_check", false):
			last = game.apply("check")
		elif la.get("can_call", false):
			last = game.apply("call")
		else:
			last = game.apply("fold")
	assert_eq(game.street, PokerGame.Street.SHOWDOWN)
	var types: Array = []
	for ev in last:
		types.append(ev.get("type", ""))
	var showdown_idx := types.find("showdown")
	assert_gt(showdown_idx, -1, "final batch contains the showdown event")
	assert_true(types.has("win"), "final batch pays the winners")
	for i in range(types.size()):
		if types[i] == "win":
			assert_gt(i, showdown_idx, "chips move only after the reveal")


func test_showdown_rows_carry_gross_and_committed() -> void:
	var game := _make_game(4)
	game.start_hand()
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
	assert_eq(game.street, PokerGame.Street.SHOWDOWN)
	for r in game.showdown_results:
		var p: PokerPlayer = game.players[int(r["player"])]
		assert_eq(int(r["gross"]), p.won_last, "gross is what the pot paid")
		assert_eq(int(r["committed"]), p.committed, "row carries chips put in")
		if r.get("won", false):
			assert_gt(int(r["gross"]), 0)
		else:
			assert_eq(int(r["gross"]), 0, "losers are paid nothing")
			assert_gt(int(r["committed"]), 0, "losers still show their buy-in")
