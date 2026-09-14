class_name Card
extends RefCounted

## A single playing card. Rank is 2..14 (14 = Ace), suit is 0..3.

const SUIT_CLUBS := 0
const SUIT_DIAMONDS := 1
const SUIT_HEARTS := 2
const SUIT_SPADES := 3

const RANK_NAMES := {
	2: "2", 3: "3", 4: "4", 5: "5", 6: "6", 7: "7", 8: "8",
	9: "9", 10: "10", 11: "J", 12: "Q", 13: "K", 14: "A",
}

var rank: int
var suit: int


func _init(p_rank: int = 2, p_suit: int = 0) -> void:
	rank = p_rank
	suit = p_suit


func rank_label() -> String:
	return RANK_NAMES.get(rank, "?")


func is_red() -> bool:
	return suit == SUIT_DIAMONDS or suit == SUIT_HEARTS


func color() -> Color:
	return Color("#d23b3b") if is_red() else Color("#20242b")
