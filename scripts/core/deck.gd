class_name Deck
extends RefCounted

## A standard 52-card deck with deterministic, seedable shuffling.

var cards: Array = []
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	reset()


func reset() -> void:
	cards.clear()
	for suit in range(4):
		for rank in range(2, 15):
			cards.append(Card.new(rank, suit))


func shuffle() -> void:
	# Fisher-Yates using our seeded RNG so tests are reproducible.
	for i in range(cards.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp


func draw() -> Card:
	return cards.pop_back() if not cards.is_empty() else null


func remaining() -> int:
	return cards.size()
