class_name PokerPlayer
extends RefCounted

## Runtime state for one seat at the table.

var id: int = 0
var display_name: String = "Player"
var is_human: bool = false
var personality: String = "balanced"
var avatar_color: Color = Color("#4a90d9")

var chips: int = 0
var hole: Array = []
var bet: int = 0          # chips wagered on the current street
var committed: int = 0    # chips wagered across the whole hand
var folded: bool = false
var all_in: bool = false
var has_acted: bool = false
var can_raise: bool = true
var out: bool = false     # eliminated from the game (no chips at hand start)

var last_action: String = ""
var last_hand_name: String = ""
var last_hand_cards: Array = []
var won_last: int = 0
var is_winner: bool = false


func _init(p_id: int = 0, p_name: String = "Player", p_chips: int = 0, p_human: bool = false) -> void:
	id = p_id
	display_name = p_name
	chips = p_chips
	is_human = p_human


func reset_for_hand() -> void:
	hole.clear()
	bet = 0
	committed = 0
	folded = false
	all_in = false
	has_acted = false
	can_raise = true
	last_action = ""
	last_hand_name = ""
	last_hand_cards.clear()
	is_winner = false
	if chips <= 0:
		out = true


func reset_for_street() -> void:
	bet = 0
	has_acted = false
	can_raise = true


## A player is still contesting the pot: not folded and not eliminated.
func in_hand() -> bool:
	return not out and not folded


## A player who can still put chips in this hand.
func can_contribute() -> bool:
	return in_hand() and not all_in and chips > 0


func add_chips(amount: int) -> void:
	chips += amount


func remove_chips(amount: int) -> int:
	var taken := mini(amount, chips)
	chips -= taken
	if chips <= 0:
		chips = 0
	return taken


func status_text() -> String:
	if out:
		return "Out"
	if folded:
		return "Folded"
	if all_in:
		return "All in"
	return ""
