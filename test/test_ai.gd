extends GutTest

## AI sanity: legal decisions, meaningful equity, and complete games.


func _make_game(count: int = 4, seed_value: int = 3) -> PokerGame:
	var defs: Array = []
	var personalities := ["rock", "aggressive", "loose", "balanced"]
	for i in range(count):
		defs.append({
			"id": i,
			"name": "AI%d" % i,
			"chips": 1000,
			"human": false,
			"personality": personalities[i % personalities.size()],
		})
	var game := PokerGame.new()
	game.setup(defs, 10, 20, seed_value)
	return game


func test_decisions_are_legal() -> void:
	var game := _make_game(4, 11)
	game.start_hand()
	var ai := PokerAI.new(7)
	for _i in range(200):
		var p = game.current_player()
		if p == null:
			break
		var decision := ai.decide(game, p)
		var la := game.get_legal_actions()
		match decision["action"]:
			"fold":
				assert_true(la["can_fold"])
			"check":
				assert_true(la["can_check"])
			"call":
				assert_true(la["can_call"])
			"raise":
				assert_true(la["can_raise"])
				var amt: int = decision["amount"]
				assert_between(amt, la["min_raise_to"], la["max_raise_to"],
					"Raise amount is within legal bounds")
		game.apply(decision["action"], decision.get("amount", 0))
		if game.hand_over:
			break


func test_equity_reasonableness() -> void:
	var game := _make_game(2, 2)
	game.start_hand()
	game.community.clear()
	var ai := PokerAI.new(99)
	var hero = game.players[0]
	hero.hole = [Card.new(14, 0), Card.new(14, 1)]
	var aces := ai.estimate_equity(game, hero, 200)
	hero.hole = [Card.new(7, 0), Card.new(2, 1)]
	var junk := ai.estimate_equity(game, hero, 200)
	assert_gt(aces, 0.6, "Pocket aces are a big favourite")
	assert_lt(junk, 0.5, "Seven-deuce is a dog")
	assert_gt(aces, junk)


func test_ai_decisions_legal_across_many_deals() -> void:
	for seed_value in range(1, 9):
		var game := _make_game(4, seed_value)
		var ai := PokerAI.new(seed_value * 3 + 1)
		game.start_hand()
		var guard := 0
		while not game.hand_over and guard < 400:
			guard += 1
			var p = game.current_player()
			if p == null:
				break
			var la := game.get_legal_actions()
			var decision := ai.decide(game, p)
			match decision["action"]:
				"fold":
					assert_true(la["can_fold"], "seed %d" % seed_value)
				"check":
					assert_true(la["can_check"], "seed %d" % seed_value)
				"call":
					assert_true(la["can_call"], "seed %d" % seed_value)
				"raise":
					assert_true(la["can_raise"], "seed %d" % seed_value)
					assert_between(decision["amount"], la["min_raise_to"], la["max_raise_to"],
						"seed %d raise in bounds" % seed_value)
			game.apply(decision["action"], decision.get("amount", 0))
		assert_true(game.hand_over, "seed %d hand resolved" % seed_value)


func test_ai_games_complete_and_conserve_chips() -> void:
	var game := _make_game(4, 21)
	var ai := PokerAI.new(5)
	var expected := 4000
	var hands := 0
	var start_time := Time.get_ticks_msec()
	while hands < 60 and not game.game_over:
		game.start_hand()
		var guard := 0
		while not game.hand_over and guard < 1000:
			guard += 1
			var p = game.current_player()
			if p == null:
				break
			var decision := ai.decide(game, p)
			game.apply(decision["action"], decision.get("amount", 0))
		assert_lt(guard, 1000, "Hand terminated")
		var total := 0
		for p in game.players:
			total += p.chips
			assert_gte(p.chips, 0)
		assert_eq(total, expected, "Chips conserved after AI hand %d" % hands)
		hands += 1
	var elapsed := Time.get_ticks_msec() - start_time
	assert_gt(hands, 10, "AI played a real session")
	assert_lt(elapsed, 30000, "AI decisions are fast enough (%d ms)" % elapsed)
