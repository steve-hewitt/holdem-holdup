extends GutTest

## Hand evaluator correctness: categories, ordering, tiebreakers, wheels.

const RANKS := {"2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8,
	"9": 9, "T": 10, "J": 11, "Q": 12, "K": 13, "A": 14}
const SUITS := {"c": 0, "d": 1, "h": 2, "s": 3}


func _card(code: String) -> Card:
	var rank: int = RANKS[code.substr(0, 1)]
	var suit: int = SUITS[code.substr(1, 1)]
	return Card.new(rank, suit)


func _hand(codes: Array) -> Array:
	var result: Array = []
	for code in codes:
		result.append(_card(code))
	return result


func _eval(codes: Array) -> Dictionary:
	return HandEvaluator.evaluate_best(_hand(codes))


func test_royal_flush_is_best() -> void:
	var royal := _eval(["As", "Ks", "Qs", "Js", "Ts", "2c", "3d"])
	assert_eq(royal["name"], "Royal Flush")
	assert_eq(royal["category"], HandEvaluator.CAT_STRAIGHT_FLUSH)


func test_category_ordering() -> void:
	var hands := {
		"sf": ["9s", "8s", "7s", "6s", "5s", "2c", "3d"],
		"quads": ["9s", "9h", "9d", "9c", "5s", "2c", "3d"],
		"full": ["9s", "9h", "9d", "5c", "5s", "2c", "3d"],
		"flush": ["As", "Js", "9s", "6s", "3s", "2c", "3d"],
		"straight": ["9s", "8h", "7d", "6c", "5s", "2c", "3d"],
		"trips": ["9s", "9h", "9d", "Ac", "5s", "2c", "3d"],
		"two_pair": ["9s", "9h", "5d", "5c", "As", "2c", "3d"],
		"pair": ["9s", "9h", "Ad", "8c", "5s", "2c", "3d"],
		"high": ["As", "Jh", "9d", "7c", "5s", "2c", "3d"],
	}
	var order := ["sf", "quads", "full", "flush", "straight", "trips", "two_pair", "pair", "high"]
	for i in range(order.size() - 1):
		var better: int = _eval(hands[order[i]])["score"]
		var worse: int = _eval(hands[order[i + 1]])["score"]
		assert_gt(better, worse, "%s should beat %s" % [order[i], order[i + 1]])


func test_wheel_straight() -> void:
	var wheel := _eval(["As", "2h", "3d", "4c", "5s", "Kc", "Qd"])
	assert_eq(wheel["category"], HandEvaluator.CAT_STRAIGHT)
	assert_eq(wheel["ranks"][0], 5, "Wheel counts as a five-high straight")


func test_wheel_beats_nothing_below() -> void:
	var six_high := _eval(["2s", "3h", "4d", "5c", "6s", "Kc", "Qd"])
	var wheel := _eval(["As", "2h", "3d", "4c", "5s", "Kc", "Qd"])
	assert_gt(six_high["score"], wheel["score"])


func test_steel_wheel_straight_flush() -> void:
	var steel := _eval(["As", "2s", "3s", "4s", "5s", "Kc", "Qd"])
	assert_eq(steel["category"], HandEvaluator.CAT_STRAIGHT_FLUSH)
	assert_eq(steel["ranks"][0], 5)


func test_pair_kicker_matters() -> void:
	var aces_king := _eval(["As", "Ah", "Kd", "8c", "5s", "2c", "3d"])
	var aces_queen := _eval(["Ac", "Ad", "Qd", "8h", "5s", "2h", "3s"])
	assert_gt(aces_king["score"], aces_queen["score"])


func test_two_pair_kicker_matters() -> void:
	var a := _eval(["As", "Ah", "Kd", "Kc", "Qs", "2c", "3d"])
	var b := _eval(["Ac", "Ad", "Kh", "Ks", "Js", "2h", "3s"])
	assert_gt(a["score"], b["score"])


func test_flush_ranks_compare() -> void:
	var a := _eval(["As", "Qs", "9s", "6s", "3s", "2c", "3d"])
	var b := _eval(["As", "Js", "9s", "6s", "3s", "2h", "3c"])
	assert_gt(a["score"], b["score"])


func test_exact_tie() -> void:
	var a := _eval(["As", "Kh", "Qd", "Jc", "Ts", "2c", "3d"])
	var b := _eval(["Ah", "Ks", "Qc", "Jd", "Th", "4c", "5d"])
	assert_eq(a["score"], b["score"])
	assert_true(_same_ranks(a, b))


func _same_ranks(a: Dictionary, b: Dictionary) -> bool:
	return a["ranks"] == b["ranks"]


func test_best_five_of_seven() -> void:
	# Board pairs the board twice; the player has the only ace for trips.
	var result := _eval(["As", "Ad", "Kc", "Kh", "Kd", "2s", "3c"])
	assert_eq(result["category"], HandEvaluator.CAT_FULL_HOUSE)
	assert_eq(result["cards"].size(), 5)


func test_full_house_tiebreak() -> void:
	var nines_full := _eval(["9s", "9h", "9d", "5c", "5s", "2c", "3d"])
	var fives_full := _eval(["5s", "5h", "5d", "9c", "9s", "2c", "3d"])
	assert_gt(nines_full["score"], fives_full["score"])


func test_undersized_input_returns_invalid() -> void:
	var result := HandEvaluator.evaluate_best(_hand(["As", "Ks", "Qs"]))
	assert_eq(result["score"], -1)
	assert_eq(result["name"], "Invalid")
