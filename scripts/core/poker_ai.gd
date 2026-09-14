class_name PokerAI
extends RefCounted

## Heuristic opponents. Each one estimates its equity with a small Monte Carlo
## simulation, then decides using pot odds modulated by a personality.

const PERSONALITIES := {
	"rock": {"tightness": 0.08, "aggression": 0.30, "bluff": 0.04, "noise": 0.03},
	"aggressive": {"tightness": 0.00, "aggression": 0.78, "bluff": 0.14, "noise": 0.04},
	"loose": {"tightness": -0.04, "aggression": 0.46, "bluff": 0.24, "noise": 0.05},
	"balanced": {"tightness": 0.03, "aggression": 0.55, "bluff": 0.10, "noise": 0.04},
}

const SIMULATIONS := 90

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## Returns {"action": String, "amount": int}. `amount` is the raise "to" total.
func decide(game: PokerGame, player: PokerPlayer) -> Dictionary:
	var la := game.get_legal_actions()
	if la.is_empty():
		return {"action": "check", "amount": 0}
	var params: Dictionary = PERSONALITIES.get(player.personality, PERSONALITIES["balanced"])
	var equity := estimate_equity(game, player, SIMULATIONS)
	equity += _rng.randf_range(-params["noise"], params["noise"])
	equity = clampf(equity, 0.0, 1.0)

	var to_call: int = la["to_call"]
	var pot: int = game.total_pot()

	if la["can_check"]:
		return _decide_when_unbet(la, equity, pot, params)

	# Facing a bet: compare equity to the price of calling.
	var pot_odds := float(to_call) / float(pot + to_call)
	var threshold: float = pot_odds + params["tightness"] - 0.01
	if equity >= threshold:
		var raise_chance: float = 0.30 + params["aggression"] * 0.45
		if la["can_raise"] and equity > 0.68 - params["aggression"] * 0.16 \
				and _rng.randf() < raise_chance:
			return _raise_decision(la, pot, params, equity)
		return {"action": "call", "amount": 0}

	# Bluff-raise occasionally when the price is not outrageous.
	if la["can_raise"] and to_call < pot * 0.6 and _rng.randf() < params["bluff"] * 0.5:
		return _raise_decision(la, pot, params, equity)
	return {"action": "fold", "amount": 0}


func _decide_when_unbet(la: Dictionary, equity: float, pot: int, params: Dictionary) -> Dictionary:
	if la["can_raise"]:
		var value_bet: float = 0.52 + (1.0 - params["aggression"]) * 0.12
		if equity > value_bet or _rng.randf() < params["bluff"] * 0.35:
			return _raise_decision(la, pot, params, equity)
	return {"action": "check", "amount": 0}


func _raise_decision(la: Dictionary, pot: int, params: Dictionary, equity: float) -> Dictionary:
	var min_to: int = la["min_raise_to"]
	var max_to: int = la["max_raise_to"]
	var scale: float = 0.5 + params["aggression"] * 0.6
	if equity > 0.82:
		scale = 0.9 + params["aggression"] * 0.6
	var base: int = la["to_call"] + int(pot * scale)
	base = _round_chips(maxi(base, min_to))
	var target: int = clampi(base, min_to, max_to)
	if target >= max_to - 5 or target > max_to:
		target = max_to
	return {"action": "raise", "amount": target}


func _round_chips(amount: int) -> int:
	if amount <= 0:
		return 0
	if amount < 100:
		return int(round(amount / 5.0)) * 5
	if amount < 1000:
		return int(round(amount / 10.0)) * 10
	return int(round(amount / 25.0)) * 25


## Win probability against the other players still in the hand, sampled from
## random unknown holdings and runouts.
func estimate_equity(game: PokerGame, hero: PokerPlayer, iterations: int = SIMULATIONS) -> float:
	var opponents := 0
	for p in game.players:
		if p.id != hero.id and p.in_hand():
			opponents += 1
	if opponents <= 0:
		return 1.0

	var known := {}
	for c in hero.hole:
		known[c.rank * 4 + c.suit] = true
	for c in game.community:
		known[c.rank * 4 + c.suit] = true

	var unknown: Array = []
	for suit in range(4):
		for rank in range(2, 15):
			if not known.has(rank * 4 + suit):
				unknown.append(Card.new(rank, suit))

	var board_needed := 5 - game.community.size()
	var base_board := game.community.duplicate()
	var score_total := 0.0

	for _it in range(iterations):
		var pool := unknown.duplicate()
		for i in range(pool.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp

		var idx := 0
		var board := base_board.duplicate()
		for _k in range(board_needed):
			board.append(pool[idx])
			idx += 1

		var hero_cards: Array = hero.hole.duplicate()
		hero_cards.append_array(board)
		var hero_score: int = HandEvaluator.evaluate_best(hero_cards)["score"]

		var best_opp := -1
		for _o in range(opponents):
			var opp_cards: Array = [pool[idx], pool[idx + 1]]
			idx += 2
			opp_cards.append_array(board)
			var opp_score: int = HandEvaluator.evaluate_best(opp_cards)["score"]
			if opp_score > best_opp:
				best_opp = opp_score

		if hero_score > best_opp:
			score_total += 1.0
		elif hero_score == best_opp:
			score_total += 0.5

	return score_total / float(iterations)
