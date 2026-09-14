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
const SUIT_SYMBOLS := ["\u2663", "\u2666", "\u2665", "\u2660"]
const SUIT_NAMES := ["Clubs", "Diamonds", "Hearts", "Spades"]

var rank: int
var suit: int


func _init(p_rank: int = 2, p_suit: int = 0) -> void:
	rank = p_rank
	suit = p_suit


func rank_label() -> String:
	return RANK_NAMES.get(rank, "?")


func suit_symbol() -> String:
	return SUIT_SYMBOLS[suit] if suit >= 0 and suit < SUIT_SYMBOLS.size() else "?"


func suit_name() -> String:
	return SUIT_NAMES[suit] if suit >= 0 and suit < SUIT_NAMES.size() else "?"


func is_red() -> bool:
	return suit == SUIT_DIAMONDS or suit == SUIT_HEARTS


func color() -> Color:
	return Color("#d23b3b") if is_red() else Color("#20242b")


func short_name() -> String:
	var s := "?"
	match suit:
		SUIT_CLUBS: s = "c"
		SUIT_DIAMONDS: s = "d"
		SUIT_HEARTS: s = "h"
		SUIT_SPADES: s = "s"
	return rank_label() + s


func long_name() -> String:
	return "%s of %s" % [rank_label(), suit_name()]


func duplicate_card() -> Card:
	return Card.new(rank, suit)


func equals(other: Card) -> bool:
	return other != null and other.rank == rank and other.suit == suit
