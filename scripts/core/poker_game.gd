class_name PokerGame
extends RefCounted

## Turn-based no-limit Texas Hold'em engine. Pure state and rules: no UI.
##
## Public flow:
##   setup(...)      -> build the table
##   start_hand()    -> returns Array of events
##   get_legal_actions() / apply(action, amount) -> returns Array of events
##   hand_over / game_over -> check for completion
##
## Events are Dictionaries the UI consumes for animation and messaging.

enum Street { PREFLOP, FLOP, TURN, RIVER, SHOWDOWN, COMPLETE }

const ACTION_FOLD := "fold"
const ACTION_CHECK := "check"
const ACTION_CALL := "call"
const ACTION_RAISE := "raise"

const STREET_NAMES := ["Pre-Flop", "Flop", "Turn", "River", "Showdown", "Complete"]

## Showdown reveal policy. "show_all" flips every contender; "muck_losers"
## keeps beaten hands face-down. Configurable without a code change via the
## `holdem_holdup/showdown_reveal` project setting (see project.godot) or the
## `--showdown=` CLI flag, which main.gd forwards to `showdown_reveal_mode`.
const REVEAL_SHOW_ALL := "show_all"
const REVEAL_MUCK_LOSERS := "muck_losers"
const REVEAL_SETTING := "holdem_holdup/showdown_reveal"

var players: Array = []
var deck: Deck
var community: Array = []
var street: int = Street.COMPLETE
var current_bet: int = 0
var min_raise: int = 20
var to_act: int = -1
var button: int = -1
var hand_number: int = 0
var small_blind: int = 10
var big_blind: int = 20
var blinds_increase_every: int = 8
var hand_over: bool = true
var game_over: bool = false
var game_winner: int = -1
var showdown_results: Array = []
var last_pots: Array = []
var events: Array = []
## Last player to bet/raise on the current street (-1 when nobody did).
var last_aggressor: int = -1
## Showdown reveal order (player ids) and the subset actually flipped face-up.
var reveal_order: Array = []
var revealed_ids: Array = []
## Contenders exposed early by an all-in runout (subset of revealed_ids).
var exposed_ids: Array = []
## Reveal policy override; defaults to the project setting in setup().
var showdown_reveal_mode: String = REVEAL_SHOW_ALL

var _rng := RandomNumberGenerator.new()


func setup(defs: Array, p_small_blind: int = 10, p_big_blind: int = 20, seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	players.clear()
	for d in defs:
		var p := PokerPlayer.new(
			d.get("id", players.size()),
			d.get("name", "Player"),
			d.get("chips", 1000),
			d.get("human", false)
		)
		p.personality = d.get("personality", "balanced")
		p.avatar_color = d.get("color", Color("#4a90d9"))
		players.append(p)
	small_blind = p_small_blind
	big_blind = p_big_blind
	showdown_reveal_mode = str(ProjectSettings.get_setting(REVEAL_SETTING, REVEAL_SHOW_ALL))
	last_aggressor = -1
	reveal_order.clear()
	revealed_ids.clear()
	exposed_ids.clear()
	deck = Deck.new(seed_value)
	button = -1
	hand_number = 0
	game_over = false
	game_winner = -1
	hand_over = true
	street = Street.COMPLETE
	community.clear()
	events.clear()


# ---------------------------------------------------------------------------
# Hand lifecycle
# ---------------------------------------------------------------------------

func start_hand() -> Array:
	events.clear()
	showdown_results.clear()
	last_pots.clear()
	reveal_order.clear()
	revealed_ids.clear()
	exposed_ids.clear()
	last_aggressor = -1
	hand_over = false

	for p in players:
		if p.chips <= 0:
			p.out = true
		p.won_last = 0
		p.reset_for_hand()

	var active := _active_players()
	if active.size() <= 1:
		game_over = true
		hand_over = true
		game_winner = active[0].id if active.size() == 1 else -1
		_event({"type": "game_over", "winner": game_winner})
		return events.duplicate()

	if hand_number > 0 and hand_number % blinds_increase_every == 0:
		_increase_blinds()

	hand_number += 1
	deck.reset()
	deck.shuffle()
	community.clear()
	to_act = -1
	street = Street.PREFLOP

	button = _next_active_index(button)
	var sb_i := _small_blind_index()
	var bb_i := _big_blind_index()

	_deal_hole_cards(sb_i)

	_post_blind(players[sb_i], small_blind, "Small blind")
	_post_blind(players[bb_i], big_blind, "Big blind")

	current_bet = maxi(players[sb_i].bet, players[bb_i].bet)
	min_raise = big_blind
	for p in players:
		p.has_acted = false
		p.can_raise = true

	var first := _first_preflop_actor(sb_i, bb_i)
	# Blinds alone can close the betting (e.g. heads-up, small blind all-in for
	# less than the big blind). Do not hand out an action nobody can use.
	if _betting_closed():
		_run_out_and_showdown()
	else:
		var nxt := _find_actor(first)
		if nxt == -1:
			_run_out_and_showdown()
		else:
			to_act = nxt

	return events.duplicate()


func current_player() -> PokerPlayer:
	if to_act >= 0 and to_act < players.size():
		return players[to_act]
	return null


func active_player_count() -> int:
	return _active_players().size()


func human_player() -> PokerPlayer:
	for p in players:
		if p.is_human:
			return p
	return null


func total_pot() -> int:
	var total := 0
	for p in players:
		total += p.committed
	return total


func street_name() -> String:
	return STREET_NAMES[street] if street >= 0 and street < STREET_NAMES.size() else ""


# ---------------------------------------------------------------------------
# Legal actions + action application
# ---------------------------------------------------------------------------

func get_legal_actions() -> Dictionary:
	var p := current_player()
	if p == null:
		return {}
	var to_call := current_bet - p.bet
	var max_to := p.bet + p.chips
	var result := {
		"to_call": to_call,
		"call_amount": mini(to_call, p.chips),
		# Folding is always offered, even when a free check is available.
		# This matches standard online clients (fold is never disabled) and
		# keeps the engine total: every turn has at least one legal exit.
		"can_fold": true,
		"can_check": to_call <= 0,
		"can_call": to_call > 0 and p.chips > 0,
		"can_raise": false,
		"min_raise_to": 0,
		"max_raise_to": max_to,
		"is_all_in_call": to_call >= p.chips,
	}
	# A raise needs someone who can still call it. Betting into a dry side pot
	# (every other contender is all-in) is disallowed, matching real rules.
	if p.can_raise and max_to > current_bet and _opponent_can_call(p):
		var min_to := current_bet + min_raise
		if min_to > max_to:
			min_to = max_to
		result["can_raise"] = true
		result["min_raise_to"] = min_to
	return result


func apply(action: String, amount: int = 0) -> Array:
	if hand_over or game_over:
		return []
	var p := current_player()
	if p == null:
		return []
	events.clear()
	var la := get_legal_actions()

	match action:
		ACTION_FOLD:
			if not la.get("can_fold", false):
				return []
			p.folded = true
			p.has_acted = true
			p.last_action = "Fold"
			_event({"type": "action", "player": p.id, "action": "fold",
				"message": "%s %s" % [p.display_name, _pv(p, "fold")]})
		ACTION_CHECK:
			if not la.get("can_check", false):
				return []
			p.has_acted = true
			p.last_action = "Check"
			_event({"type": "action", "player": p.id, "action": "check",
				"message": "%s %s" % [p.display_name, _pv(p, "check")]})
		ACTION_CALL:
			if not la.get("can_call", false):
				return []
			var pay: int = mini(la.get("to_call", 0), p.chips)
			_take_chips(p, pay)
			p.has_acted = true
			p.last_action = "Call"
			var msg := "%s %s %d" % [p.display_name, _pv(p, "call"), pay]
			if p.all_in:
				msg = "%s %s all-in for %d" % [p.display_name, _be(p), p.bet]
			_event({"type": "action", "player": p.id, "action": "call",
				"amount": pay, "all_in": p.all_in, "message": msg})
		ACTION_RAISE:
			if not la.get("can_raise", false):
				return []
			_apply_raise(p, amount, la)
		_:
			return []

	_advance()
	return events.duplicate()


func _apply_raise(p: PokerPlayer, amount: int, la: Dictionary) -> void:
	var old_bet := current_bet
	var max_to: int = p.bet + p.chips
	var target: int = mini(amount, max_to)
	var min_to: int = la.get("min_raise_to", current_bet + min_raise)
	if target < min_to and max_to >= min_to:
		target = min_to
	if target > max_to:
		target = max_to
	# A raise amount at/below the current bet is not a shove by default: the
	# clamp above already lifted it to the minimum raise whenever the stack
	# allows one. Reaching here with target <= current_bet means the player
	# cannot even make a minimum raise, so the only legal raise is a short
	# all-in for everything they have left.
	if target <= current_bet:
		target = max_to

	var add: int = target - p.bet
	_take_chips(p, add)
	var raise_size: int = p.bet - old_bet
	var full_raise: bool = raise_size >= min_raise
	if full_raise and raise_size > 0:
		min_raise = raise_size
	current_bet = maxi(current_bet, p.bet)

	if full_raise and raise_size > 0:
		for other in players:
			if other.id != p.id and other.can_contribute():
				other.can_raise = true
	else:
		# A short all-in does not reopen the betting for players who already acted.
		for other in players:
			if other.id != p.id and other.can_contribute() and other.has_acted:
				other.can_raise = false

	p.has_acted = true
	p.can_raise = false
	last_aggressor = p.id
	var verb := "raise to"
	if p.all_in:
		verb = "all-in for"
	elif old_bet <= 0:
		verb = "bet"
	p.last_action = "All in" if p.all_in else ("Bet" if verb == "bet" else "Raise")
	if p.all_in:
		_event({"type": "action", "player": p.id, "action": "raise", "amount": p.bet,
			"to": p.bet, "all_in": true,
			"message": "%s %s all-in for %d" % [p.display_name, _be(p), p.bet]})
	else:
		_event({"type": "action", "player": p.id, "action": "raise", "amount": p.bet,
			"to": p.bet, "all_in": false,
			"message": "%s %s %d" % [p.display_name, _pv(p, verb), p.bet]})


func _take_chips(p: PokerPlayer, amount: int) -> void:
	if amount <= 0:
		return
	var taken := p.remove_chips(amount)
	p.bet += taken
	p.committed += taken
	if p.chips <= 0:
		p.all_in = true


# ---------------------------------------------------------------------------
# Flow
# ---------------------------------------------------------------------------

func _advance() -> void:
	if _contenders().size() <= 1:
		_end_hand_by_fold()
		return
	if _betting_closed():
		_run_out_and_showdown()
		return
	var nxt := _find_actor((to_act + 1) % players.size())
	if nxt == -1:
		_complete_street()
	else:
		to_act = nxt


func _complete_street() -> void:
	_collect_bets()
	if street == Street.RIVER:
		_do_showdown()
		return
	street += 1
	_deal_street_cards()
	current_bet = 0
	min_raise = big_blind
	last_aggressor = -1
	for p in players:
		if not p.out:
			p.reset_for_street()
	var nxt := _find_actor(_next_active_index(button))
	if nxt == -1:
		_run_out_and_showdown()
	else:
		to_act = nxt


func _run_out_and_showdown() -> void:
	# Casino rule: when every remaining contender is all-in with board still
	# to come, hands are exposed before the runout so the table can sweat it.
	var exposed := _exposed_all_in_ids()
	exposed_ids = exposed.duplicate()
	if not exposed.is_empty():
		_event({"type": "all_in_showdown", "players": exposed})
	while street < Street.RIVER:
		street += 1
		_deal_street_cards(not exposed.is_empty())
	_do_showdown()


## Player ids whose hole cards must be flipped now: every contender is
## all-in and the board is incomplete. Empty when normal covering applies
## (someone can still bet, or the board is already out).
func _exposed_all_in_ids() -> Array:
	if community.size() >= 5:
		return []
	var ids: Array = []
	for p in _contenders():
		if not p.all_in:
			return []
		ids.append(p.id)
	return ids if ids.size() > 1 else []


func _do_showdown() -> void:
	_collect_bets()
	_refund_uncalled()
	var pots := _build_side_pots()
	last_pots = pots

	# Award the pots now for accounting, but hold the win events until after
	# the showdown reveal so chips visually stay in the pot while hands show.
	var wins_from := events.size()
	for pot in pots:
		_award_pot(pot)
	var wins := events.slice(wins_from)
	events.resize(wins_from)

	for p in players:
		p.has_acted = true
		p.net_last = p.won_last - p.committed
	reveal_order = _compute_reveal_order()
	# Hands exposed mid-runout stay up no matter the muck policy.
	revealed_ids = exposed_ids.duplicate()
	if showdown_reveal_mode == REVEAL_MUCK_LOSERS:
		revealed_ids.clear()
		for pid in reveal_order:
			if players[pid].is_winner:
				revealed_ids.append(pid)
	else:
		revealed_ids = reveal_order.duplicate()
	for pid in exposed_ids:
		if not revealed_ids.has(pid):
			revealed_ids.append(pid)
	_build_showdown_results()
	hand_over = true
	street = Street.SHOWDOWN
	to_act = -1
	_event({"type": "showdown", "results": showdown_results.duplicate(),
		"pots": pots, "reveal_order": reveal_order.duplicate(),
		"revealed": revealed_ids.duplicate()})
	for w in wins:
		events.append(w)


## Real-poker reveal order: the last aggressor on the final betting round
## shows first; everyone else follows clockwise from the button. When nobody
## bet the last round, the first contender left of the button leads.
func _compute_reveal_order() -> Array:
	var ids: Array = []
	for p in _contenders():
		ids.append(p.id)
	var ordered := _order_from_button(ids)
	if last_aggressor >= 0 and ordered.has(last_aggressor):
		ordered.erase(last_aggressor)
		ordered.push_front(last_aggressor)
	return ordered


func _end_hand_by_fold() -> void:
	_collect_bets()
	# Return the winner's own uncalled chips before awarding the pot, so
	# won_last / net_last reflect chips actually won from opponents.
	_refund_uncalled()
	var contenders := _contenders()
	if contenders.is_empty():
		push_error("PokerGame._end_hand_by_fold: no contenders left; %d committed chips have no winner" % total_pot())
		hand_over = true
		to_act = -1
		return
	var winner: PokerPlayer = contenders[0]
	var amount := total_pot()
	winner.chips += amount
	winner.won_last += amount
	winner.is_winner = true
	for p in players:
		p.net_last = p.won_last - p.committed
	hand_over = true
	street = Street.COMPLETE
	to_act = -1
	_event({"type": "hand_end", "winner": winner.id, "amount": amount,
		"message": "%s %s %d" % [winner.display_name, _pv(winner, "win"), amount]})


# ---------------------------------------------------------------------------
# Pot handling
# ---------------------------------------------------------------------------

func _collect_bets() -> void:
	for p in players:
		p.bet = 0


func _refund_uncalled() -> void:
	var max1 := -1
	var max2 := -1
	for p in players:
		var c: int = p.committed
		if c > max1:
			max2 = max1
			max1 = c
		elif c > max2:
			max2 = c
	if max1 > max2 and max2 >= 0 and max1 > 0:
		var excess := max1 - max2
		for p in players:
			if p.committed == max1:
				p.chips += excess
				p.committed -= excess
				_event({"type": "refund", "player": p.id, "amount": excess,
					"message": "Uncalled %d returned to %s" % [excess, p.display_name]})
				break


func _build_side_pots() -> Array:
	var rem: Array = []
	var folded_arr: Array = []
	for p in players:
		rem.append(p.committed)
		folded_arr.append(p.folded)
	var pots: Array = []
	while true:
		var m := -1
		for c in rem:
			if c > 0 and (m < 0 or c < m):
				m = c
		if m < 0:
			break
		var amount := 0
		var eligible: Array = []
		for i in range(players.size()):
			if rem[i] > 0:
				amount += m
				rem[i] -= m
				if not folded_arr[i]:
					eligible.append(i)
		pots.append({"amount": amount, "eligible": eligible})
	return pots


func _award_pot(pot: Dictionary) -> void:
	var eligible: Array = pot["eligible"]
	if eligible.is_empty():
		push_error("PokerGame._award_pot: pot of %d has no eligible winners" % int(pot.get("amount", 0)))
		return
	var best_score := -1
	var winners: Array = []
	var results: Dictionary = {}
	for i in eligible:
		var p: PokerPlayer = players[i]
		var result := HandEvaluator.evaluate_best(_all_cards(p.hole, community))
		results[i] = result
		if int(result["score"]) > best_score:
			best_score = int(result["score"])
			winners = [i]
		elif int(result["score"]) == best_score:
			winners.append(i)

	var share: int = int(pot["amount"]) / winners.size()
	var remainder: int = int(pot["amount"]) % winners.size()
	var ordered := _order_from_button(winners)
	for w in ordered:
		var amt := share
		if remainder > 0:
			amt += 1
			remainder -= 1
		var p: PokerPlayer = players[w]
		p.chips += amt
		p.won_last += amt
		p.is_winner = true
		_event({"type": "win", "player": p.id, "amount": amt,
			"message": "%s %s %d" % [p.display_name, _pv(p, "win"), amt]})

	for i in eligible:
		var p: PokerPlayer = players[i]
		var res: Dictionary = results[i]
		p.last_hand_name = res["name"]
		p.last_hand_detail = HandEvaluator.detail(res)
		p.last_hand_cards = res["cards"]


## One summary row per player who reached showdown, listed in reveal order.
## A player eligible for several pots is listed once, with combined winnings.
## `gross` is chips actually paid out; `net` subtracts what they put in.
func _build_showdown_results() -> void:
	showdown_results.clear()
	for pid in reveal_order:
		var p: PokerPlayer = players[pid]
		if p.folded or p.out:
			continue
		if p.last_hand_cards.is_empty() and p.hole.size() + community.size() >= 5:
			var res := HandEvaluator.evaluate_best(_all_cards(p.hole, community))
			p.last_hand_name = res["name"]
			p.last_hand_detail = HandEvaluator.detail(res)
			p.last_hand_cards = res["cards"]
		showdown_results.append({
			"player": p.id,
			"name": p.last_hand_name,
			"detail": p.last_hand_detail,
			"score": HandEvaluator.score(p.hole, community),
			"hole": p.hole.duplicate(),
			"cards": p.last_hand_cards,
			"best5": p.last_hand_cards.duplicate(),
			"won": p.is_winner,
			"revealed": revealed_ids.has(p.id),
			"amount": p.won_last,
			"gross": p.won_last,
			"committed": p.committed,
			"net": p.net_last,
		})


# ---------------------------------------------------------------------------
# Dealer / blinds / dealing
# ---------------------------------------------------------------------------

func _deal_hole_cards(sb_i: int) -> void:
	var count := _active_players().size()
	for _round in range(2):
		var i := sb_i
		for _k in range(count):
			var p: PokerPlayer = players[i]
			var card: Card = deck.draw()
			p.hole.append(card)
			_event({"type": "deal_hole", "player": p.id, "card": card})
			i = _next_active_index(i)


func _post_blind(p: PokerPlayer, amount: int, label: String) -> void:
	var posted := p.remove_chips(amount)
	p.bet += posted
	p.committed += posted
	if p.chips <= 0:
		p.all_in = true
	p.last_action = label
	_event({"type": "blind", "player": p.id, "amount": posted, "label": label})


func _deal_street_cards(runout: bool = false) -> void:
	var count := 3 if street == Street.FLOP else 1
	var dealt: Array = []
	for _i in range(count):
		var card: Card = deck.draw()
		community.append(card)
		dealt.append(card)
	_event({"type": "street", "street": street, "cards": dealt,
		"name": street_name(), "runout": runout})


func _increase_blinds() -> void:
	small_blind = int(ceil(small_blind * 1.5 / 5.0)) * 5
	big_blind = small_blind * 2
	_event({"type": "blinds_up", "small": small_blind, "big": big_blind})


# ---------------------------------------------------------------------------
# Index helpers
# ---------------------------------------------------------------------------

func _active_players() -> Array:
	var result: Array = []
	for p in players:
		if not p.out:
			result.append(p)
	return result


func _contenders() -> Array:
	var result: Array = []
	for p in players:
		if p.in_hand():
			result.append(p)
	return result


## True when at least one other contender still has chips to call a raise.
func _opponent_can_call(p: PokerPlayer) -> bool:
	for other in players:
		if other.id != p.id and other.can_contribute():
			return true
	return false


## Standard pot-sized raise target: call the current bet first, then raise
## the resulting pot. kind 1.0 = full pot, 0.5 = half pot. The result is a
## raise-TO amount, truncated to whole chips and clamped to [lo, hi].
static func pot_raise_target(current_bet: int, total_pot: int, to_call: int, kind: float, lo: int, hi: int) -> int:
	var target := current_bet + int((total_pot + to_call) * kind)
	return clampi(target, lo, hi)


## True when betting is finished: every contender is all-in, or at most one
## can still act and nobody has an outstanding call. A lone player who still
## owes chips is *not* closed out -- they must be given the chance to call or
## fold before the board runs out.
func _betting_closed() -> bool:
	var actors := 0
	for p in _contenders():
		if not p.can_contribute():
			continue
		if p.bet < current_bet:
			return false
		actors += 1
	return actors <= 1


func _next_active_index(from_index: int) -> int:
	var n := players.size()
	for offset in range(1, n + 1):
		var i := (from_index + offset) % n
		if not players[i].out:
			return i
	return from_index


func _small_blind_index() -> int:
	if _active_players().size() == 2:
		return button
	return _next_active_index(button)


func _big_blind_index() -> int:
	return _next_active_index(_small_blind_index())


func _first_preflop_actor(sb_i: int, bb_i: int) -> int:
	if _active_players().size() == 2:
		return sb_i
	return _next_active_index(bb_i)


func _find_actor(start_index: int) -> int:
	var n := players.size()
	for offset in range(n):
		var i := (start_index + offset) % n
		var p: PokerPlayer = players[i]
		if p.out or p.folded or p.all_in or p.chips <= 0:
			continue
		if not p.has_acted or p.bet < current_bet:
			return i
	return -1


func _order_from_button(indices: Array) -> Array:
	var n := players.size()
	var result := indices.duplicate()
	result.sort_custom(func(a, b):
		return posmod(a - (button + 1), n) < posmod(b - (button + 1), n))
	return result


func _all_cards(hole: Array, board: Array) -> Array:
	var all: Array = []
	all.append_array(hole)
	all.append_array(board)
	return all


## True when two Card handles are the same physical card (same instance, or
## — as a fallback — same rank and suit, which is unique within one deck).
static func card_matches(a: Card, b: Card) -> bool:
	if a == null or b == null:
		return false
	if is_same(a, b):
		return true
	return a.rank == b.rank and a.suit == b.suit


## Indices into `cards` whose entries match `target`. Empty when absent.
static func card_indices(cards: Array, target: Card) -> Array:
	var out: Array = []
	for i in range(cards.size()):
		if card_matches(cards[i], target):
			out.append(i)
	return out


func _pv(p: PokerPlayer, verb: String) -> String:
	if p.is_human:
		return verb
	# Multi-word verbs agree on their head word: "raise to" -> "raises to".
	if verb.ends_with(" to"):
		return verb.substr(0, verb.length() - 3) + "s to"
	return verb + "s"


func _be(p: PokerPlayer) -> String:
	return "are" if p.is_human else "is"


func _event(data: Dictionary) -> void:
	events.append(data)
