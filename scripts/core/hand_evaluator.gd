class_name HandEvaluator
extends RefCounted

## Evaluates poker hands. A result is a Dictionary:
##   score:    int, higher is better, safe to compare directly
##   category: int, 0..8
##   name:     String, human readable
##   ranks:    Array[int], tiebreak ranks in significance order
##   cards:    Array[Card], the five cards that make the hand

const CAT_HIGH_CARD := 0
const CAT_PAIR := 1
const CAT_TWO_PAIR := 2
const CAT_TRIPS := 3
const CAT_STRAIGHT := 4
const CAT_FLUSH := 5
const CAT_FULL_HOUSE := 6
const CAT_QUADS := 7
const CAT_STRAIGHT_FLUSH := 8

const CATEGORY_NAMES := [
	"High Card", "One Pair", "Two Pair", "Three of a Kind",
	"Straight", "Flush", "Full House", "Four of a Kind", "Straight Flush",
]

const _POWERS := [50625, 3375, 225, 15, 1]  # 15^4 .. 15^0

const RANK_PLURALS := {
	2: "2s", 3: "3s", 4: "4s", 5: "5s", 6: "6s", 7: "7s", 8: "8s",
	9: "9s", 10: "10s", 11: "Jacks", 12: "Queens", 13: "Kings", 14: "Aces",
}


static func category_name(category: int) -> String:
	return CATEGORY_NAMES[category] if category >= 0 and category < CATEGORY_NAMES.size() else "?"


const RANK_FACE_NAMES := {11: "Jack", 12: "Queen", 13: "King", 14: "Ace"}


static func _rank_full(rank: int) -> String:
	if RANK_FACE_NAMES.has(rank):
		return RANK_FACE_NAMES[rank]
	return Card.RANK_NAMES.get(rank, "?")


static func _rank_plural(rank: int) -> String:
	return RANK_PLURALS.get(rank, "?")


static func _kicker_suffix(ranks: Array) -> String:
	if ranks.is_empty():
		return ""
	var parts := PackedStringArray()
	for r in ranks:
		parts.append(_rank_full(r))
	var word := "kicker" if parts.size() == 1 else "kickers"
	return ", %s %s" % ["-".join(parts), word]


## A one-line, TV-style description of an evaluated hand, e.g.
## "Pair of 9s, A-Q-5 kickers" or "Ace-high". Falls back to the plain
## category name when the result is malformed.
static func detail(result: Dictionary) -> String:
	var category: int = result.get("category", -1)
	var ranks: Array = result.get("ranks", [])
	if ranks.is_empty():
		return result.get("name", "?")
	match category:
		CAT_HIGH_CARD:
			return "%s-high" % _rank_full(ranks[0])
		CAT_PAIR:
			return "Pair of %s%s" % [_rank_plural(ranks[0]), _kicker_suffix(ranks.slice(1))]
		CAT_TWO_PAIR:
			return "%s and %s%s" % [_rank_plural(ranks[0]), _rank_plural(ranks[1]), _kicker_suffix(ranks.slice(2))]
		CAT_TRIPS:
			return "Three %s%s" % [_rank_plural(ranks[0]), _kicker_suffix(ranks.slice(1))]
		CAT_STRAIGHT:
			return "%s-high Straight" % _rank_full(ranks[0])
		CAT_FLUSH:
			return "%s-high Flush" % _rank_full(ranks[0])
		CAT_FULL_HOUSE:
			return "%s over %s" % [_rank_plural(ranks[0]), _rank_plural(ranks[1])]
		CAT_QUADS:
			return "Four %s%s" % [_rank_plural(ranks[0]), _kicker_suffix(ranks.slice(1))]
		CAT_STRAIGHT_FLUSH:
			if ranks[0] == 14:
				return "Royal Flush"
			return "%s-high Straight Flush" % _rank_full(ranks[0])
	return result.get("name", "?")


## Score a set of 5 cards. Asserts are stripped from release exports, so an
## invalid input returns a below-zero "Invalid" result instead of crashing.
static func evaluate_5(cards: Array) -> Dictionary:
	if cards.size() != 5:
		push_warning("HandEvaluator.evaluate_5 needs exactly 5 cards, got %d" % cards.size())
		return {"score": -1, "category": -1, "name": "Invalid", "ranks": [], "cards": []}
	var ranks: Array = []
	var suits: Array = []
	for c in cards:
		ranks.append(c.rank)
		suits.append(c.suit)
	ranks.sort()
	ranks.reverse()

	var is_flush := true
	for s in suits:
		if s != suits[0]:
			is_flush = false
			break

	var straight_high := _straight_high(ranks)

	# Count ranks.
	var counts := {}
	for r in ranks:
		counts[r] = counts.get(r, 0) + 1
	# Groups: list of [count, rank], sorted by count desc then rank desc.
	var groups: Array = []
	for r in counts:
		groups.append([counts[r], r])
	groups.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] > b[0]
		return a[1] > b[1])

	var category := CAT_HIGH_CARD
	var tiebreak: Array = []

	if is_flush and straight_high > 0:
		category = CAT_STRAIGHT_FLUSH
		tiebreak = [straight_high]
	elif groups[0][0] == 4:
		category = CAT_QUADS
		tiebreak = [groups[0][1], groups[1][1]]
	elif groups[0][0] == 3 and groups[1][0] == 2:
		category = CAT_FULL_HOUSE
		tiebreak = [groups[0][1], groups[1][1]]
	elif is_flush:
		category = CAT_FLUSH
		tiebreak = ranks.duplicate()
	elif straight_high > 0:
		category = CAT_STRAIGHT
		tiebreak = [straight_high]
	elif groups[0][0] == 3:
		category = CAT_TRIPS
		tiebreak = [groups[0][1], groups[1][1], groups[2][1]]
	elif groups[0][0] == 2 and groups[1][0] == 2:
		category = CAT_TWO_PAIR
		tiebreak = [groups[0][1], groups[1][1], groups[2][1]]
	elif groups[0][0] == 2:
		category = CAT_PAIR
		tiebreak = [groups[0][1], groups[1][1], groups[2][1], groups[3][1]]
	else:
		category = CAT_HIGH_CARD
		tiebreak = ranks.duplicate()

	var name := category_name(category)
	if category == CAT_STRAIGHT_FLUSH and tiebreak[0] == 14:
		name = "Royal Flush"

	return {
		"score": _encode(category, tiebreak),
		"category": category,
		"name": name,
		"ranks": tiebreak,
		"cards": cards.duplicate(),
	}


## Evaluate the best 5-card hand from 5 to 7 cards.
static func evaluate_best(cards: Array) -> Dictionary:
	if cards.size() < 5:
		push_warning("HandEvaluator.evaluate_best needs at least 5 cards, got %d" % cards.size())
		return {"score": -1, "category": -1, "name": "Invalid", "ranks": [], "cards": []}
	if cards.size() == 5:
		return evaluate_5(cards)
	var best: Dictionary = {}
	for combo in _five_card_combos(cards.size()):
		var hand: Array = []
		for idx in combo:
			hand.append(cards[idx])
		var result := evaluate_5(hand)
		if best.is_empty() or result["score"] > best["score"]:
			best = result
	return best


## Convenience: total score for hole + community.
static func score(hole: Array, community: Array) -> int:
	var all: Array = []
	all.append_array(hole)
	all.append_array(community)
	return evaluate_best(all)["score"]


static func _encode(category: int, tiebreak: Array) -> int:
	var total := category * 1000000
	for i in range(5):
		var value: int = tiebreak[i] if i < tiebreak.size() else 0
		total += value * _POWERS[i]
	return total


## Returns the high card of a straight found in the given descending rank list,
## or 0 if there is no straight. Handles the A-2-3-4-5 wheel (returns 5).
static func _straight_high(desc_ranks: Array) -> int:
	var unique: Array = []
	for r in desc_ranks:
		if not unique.has(r):
			unique.append(r)
	if unique.size() < 5:
		return 0
	for i in range(unique.size() - 4):
		if unique[i] - unique[i + 4] == 4:
			return unique[i]
	# Wheel: A,5,4,3,2
	if unique.has(14) and unique.has(5) and unique.has(4) and unique.has(3) and unique.has(2):
		return 5
	return 0


static func _five_card_combos(n: int) -> Array:
	var combos: Array = []
	for a in range(n - 4):
		for b in range(a + 1, n - 3):
			for c in range(b + 1, n - 2):
				for d in range(c + 1, n - 1):
					for e in range(d + 1, n):
						combos.append([a, b, c, d, e])
	return combos
