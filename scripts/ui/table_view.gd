class_name TableView
extends Control

## Renders the poker table, seats, cards, chips, and the action bar.
## Presentation only: it reads a PokerGame and emits the human's chosen action.

signal action_chosen(data: Dictionary)
signal menu_pressed
signal mute_toggled

const DESIGN := Vector2(1280, 720)

# Normalised seat anchors for the four fixed seats.
const SEAT_ANCHORS := [
	Vector2(0.50, 0.730),   # seat 0: human, bottom centre
	Vector2(0.125, 0.400),  # seat 1: left
	Vector2(0.50, 0.075),   # seat 2: top centre
	Vector2(0.875, 0.400),  # seat 3: right
]
const HOLE_ANCHORS := [
	Vector2(0.50, 0.578),
	Vector2(0.265, 0.400),
	Vector2(0.50, 0.212),
	Vector2(0.735, 0.400),
]
const COMMUNITY_CENTER := Vector2(0.50, 0.405)
const POT_CENTER := Vector2(0.50, 0.315)
const DECK_ORIGIN := Vector2(0.50, 0.325)

const SEAT_SIZE := Vector2(228, 96)
const COMMUNITY_SIZE := Vector2(78, 108)
const HUMAN_CARD_SIZE := Vector2(92, 128)
const AI_CARD_SIZE := Vector2(68, 94)

const FELT_DARK := Color("#14512f")
const FELT_LIGHT := Color("#2f9159")
const RAIL := Color("#4a3323")
const RAIL_HI := Color("#6d4b32")
const GOLD := Color("#e8b64c")
const BUTTON_FOLD := Color("#c0453b")
const BUTTON_CALL := Color("#2f7bd6")
const BUTTON_RAISE := Color("#d9a83a")
const BUTTON_NEUTRAL := Color("#3b4750")

const SUIT_SYMBOLS := ["\u2663", "\u2666", "\u2665", "\u2660"]

## How far winning / losing showdown cards lift off the felt to mark the
## 5-card scoring hand.
const SPOTLIGHT_WIN_LIFT := 14.0
const SPOTLIGHT_LOSE_LIFT := 8.0

# Every animation dwell lives here so the whole table can be tuned in one
# place. Bigger, rarer events hold longer than routine ones.
const PACE := {
	"blind": 0.10,
	"deal_hole": 0.08,
	"action_fold": 0.24,
	"action_check": 0.22,
	"action_call": 0.32,
	"action_raise": 0.48,
	"all_in_bonus": 0.30,
	"street_settle": 0.40,
	"refund": 0.32,
	"reveal_stagger": 0.45,
	"spotlight_hold": 0.90,
	"showdown_reveal": 0.65,
	"win": 0.70,
	"hand_end": 0.30,
}

var game: PokerGame = null

var _seat_views: Array = []
var _hole_views: Dictionary = {}      # player id -> Array[CardView]
var _community_views: Array = []       # Array[CardView]
var _fx_layer: Control
var _card_layer: Control
var _hud_label: Label
var _mute_button: Button
var _menu_button: Button
var _action_panel: Panel
var _status_label: Label
var _history_label: Label
var _history: Array = []
var _last_recorded: String = ""
var _raise_label: Label
var _raise_slider: HSlider
var _quick_buttons: Array = []
var _fold_button: Button
var _call_button: Button
var _raise_button: Button
var _banner_panel: Panel
var _banner_label: Label
var _result_panel: Panel
var _result_title: Label
var _result_board: Label
var _result_rows: VBoxContainer

## True while an end-of-hand summary is on screen waiting to advance.
var awaiting_result: bool = false
var _result_skipped: bool = false

## Multiplier applied to every PACE dwell (1.0 = default tempo).
var pace_scale: float = 1.0

var _hole_slots: Dictionary = {}       # player id -> Array[Vector2]
var _community_slots: Array = []
var _spotlight: Array = []               # CardViews currently lifted for showdown
var _pot_value: int = 0
var _human_can_raise: bool = false
var _build_done: bool = false
var _community_dealt: int = 0

## When true, events are applied without animation (used by autoplay tests).
var instant: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	if _build_done:
		return
	_build_done = true

	# Seats first so cards and effects draw on top of the name plates.
	for i in range(4):
		var seat := SeatView.new()
		seat.size = SEAT_SIZE
		_seat_views.append(seat)
		add_child(seat)
		_hole_views[i] = []

	_card_layer = Control.new()
	_card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_card_layer)

	_fx_layer = Control.new()
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fx_layer)

	for i in range(4):
		for k in range(2):
			var cv := CardView.new()
			cv.size = HUMAN_CARD_SIZE if i == 0 else AI_CARD_SIZE
			cv.visible = false
			_card_layer.add_child(cv)
			_hole_views[i].append(cv)

	for i in range(5):
		var cv := CardView.new()
		cv.size = COMMUNITY_SIZE
		cv.visible = false
		_card_layer.add_child(cv)
		_community_views.append(cv)

	_build_hud()
	_build_action_bar()
	_build_banner()
	_build_hand_result()

	_notification(NOTIFICATION_RESIZED)


func _build_hud() -> void:
	_hud_label = Label.new()
	_hud_label.add_theme_font_size_override("font_size", 20)
	_hud_label.add_theme_color_override("font_color", Color("#dfe8ea"))
	_hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_hud_label.add_theme_constant_override("shadow_offset_x", 1)
	_hud_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_hud_label)

	_menu_button = _make_button("Menu", BUTTON_NEUTRAL, 18)
	_menu_button.pressed.connect(func(): menu_pressed.emit())
	add_child(_menu_button)

	_mute_button = _make_button("Sound", BUTTON_NEUTRAL, 18)
	_mute_button.pressed.connect(func(): mute_toggled.emit())
	add_child(_mute_button)


func _build_action_bar() -> void:
	_action_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0a0f12", 0.92)
	sb.corner_radius_top_left = 20
	sb.corner_radius_top_right = 20
	sb.border_color = Color("#1f2b31")
	sb.border_width_top = 2
	_action_panel.add_theme_stylebox_override("panel", sb)
	add_child(_action_panel)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 19)
	_status_label.add_theme_color_override("font_color", Color("#c9d6da"))
	_action_panel.add_child(_status_label)

	_history_label = Label.new()
	_history_label.add_theme_font_size_override("font_size", 15)
	_history_label.add_theme_color_override("font_color", Color("#7d8f97"))
	_history_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_action_panel.add_child(_history_label)

	_raise_label = Label.new()
	_raise_label.add_theme_font_size_override("font_size", 20)
	_raise_label.add_theme_color_override("font_color", GOLD)
	_action_panel.add_child(_raise_label)

	_raise_slider = HSlider.new()
	_raise_slider.min_value = 0
	_raise_slider.max_value = 100
	_raise_slider.step = 5
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#31414c")
	track.set_corner_radius_all(8)
	track.content_margin_top = 10
	track.content_margin_bottom = 10
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(8)
	fill.content_margin_top = 10
	fill.content_margin_bottom = 10
	_raise_slider.add_theme_stylebox_override("slider", track)
	_raise_slider.add_theme_stylebox_override("grabber_area", fill)
	_raise_slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	_raise_slider.value_changed.connect(_on_raise_slider_changed)
	_action_panel.add_child(_raise_slider)

	var quick_defs := [
		["Min", 0.0], ["\u00bd Pot", 0.5], ["Pot", 1.0], ["Max", -1.0],
	]
	for q in quick_defs:
		var b := _make_button(q[0], BUTTON_NEUTRAL, 16)
		b.pressed.connect(func(): _on_quick_press(q[1]))
		_quick_buttons.append(b)
		_action_panel.add_child(b)

	_fold_button = _make_button("Fold", BUTTON_FOLD, 22)
	_fold_button.pressed.connect(_on_fold)
	_action_panel.add_child(_fold_button)

	_call_button = _make_button("Check", BUTTON_CALL, 22)
	_call_button.pressed.connect(_on_call)
	_action_panel.add_child(_call_button)

	_raise_button = _make_button("Bet", BUTTON_RAISE, 22)
	_raise_button.pressed.connect(_on_raise)
	_action_panel.add_child(_raise_button)

	_raise_slider.visible = false
	_raise_label.visible = false
	for b in _quick_buttons:
		b.visible = false


func _build_banner() -> void:
	_banner_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0a0f12", 0.82)
	sb.set_corner_radius_all(16)
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	_banner_panel.add_theme_stylebox_override("panel", sb)
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_panel.visible = false
	add_child(_banner_panel)

	_banner_label = Label.new()
	_banner_label.add_theme_font_size_override("font_size", 25)
	_banner_label.add_theme_color_override("font_color", Color("#ffe9b0"))
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_panel.add_child(_banner_label)


func _build_hand_result() -> void:
	_result_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0a0f12", 0.97)
	sb.set_corner_radius_all(18)
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	_result_panel.add_theme_stylebox_override("panel", sb)
	_result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.visible = false
	add_child(_result_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_result_title = Label.new()
	_result_title.add_theme_font_size_override("font_size", 27)
	_result_title.add_theme_color_override("font_color", GOLD)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_result_title)

	_result_board = Label.new()
	_result_board.add_theme_font_size_override("font_size", 18)
	_result_board.add_theme_color_override("font_color", Color("#c9d6da"))
	_result_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_result_board)

	box.add_child(HSeparator.new())

	_result_rows = VBoxContainer.new()
	_result_rows.add_theme_constant_override("separation", 4)
	_result_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_result_rows)


func _make_button(text: String, base: Color, font_size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color("#ffffff"))
	b.add_theme_color_override("font_hover_color", Color("#ffffff"))
	b.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	b.add_theme_stylebox_override("normal", _button_style(base))
	b.add_theme_stylebox_override("hover", _button_style(base.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _button_style(base.darkened(0.15)))
	b.add_theme_stylebox_override("disabled", _button_style(Color(base.r, base.g, base.b, 0.28)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _button_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	return sb


## Seconds for a named event, scaled by the table's tempo.
func _pace(key: String, fallback: float = 0.2) -> float:
	return float(PACE.get(key, fallback)) * pace_scale


# ---------------------------------------------------------------------------
# Game binding
# ---------------------------------------------------------------------------

func set_game(p_game: PokerGame) -> void:
	game = p_game
	for i in range(_seat_views.size()):
		_seat_views[i].bind(game.players[i])
	refresh_all()


func refresh_all() -> void:
	if game == null:
		return
	for i in range(_seat_views.size()):
		var p: PokerPlayer = game.players[i]
		_seat_views[i].bind(p)
		_seat_views[i].set_turn(i == game.to_act and not game.hand_over)
		_seat_views[i].set_dealer(i == game.button)
		# Hole cards
		for k in range(_hole_views[i].size()):
			var cv: CardView = _hole_views[i][k]
			if k < p.hole.size() and not p.out:
				cv.visible = true
				cv.set_card(p.hole[k], p.is_human or _revealed(p))
				cv.position = _hole_slots[i][k] - cv.size * 0.5
				cv.modulate = Color(1, 1, 1, 0.45) if p.folded else Color(1, 1, 1, 1)
			else:
				cv.visible = false
	# Community
	for k in range(_community_views.size()):
		var cv: CardView = _community_views[k]
		if k < game.community.size():
			cv.visible = true
			cv.set_card(game.community[k], true)
			cv.position = _community_slots[k] - cv.size * 0.5
		else:
			cv.visible = false
	_community_dealt = game.community.size()
	_pot_value = game.total_pot()
	queue_redraw()
	_update_hud()


func _revealed(p: PokerPlayer) -> bool:
	if game == null:
		return false
	if p.folded:
		return false
	if not game.revealed_ids.is_empty() and not game.revealed_ids.has(p.id):
		return false
	return p.last_hand_name != "" or game.street == PokerGame.Street.SHOWDOWN


func reveal_showdown() -> void:
	if game == null:
		return
	for i in range(_seat_views.size()):
		var p: PokerPlayer = game.players[i]
		if p.folded or p.out:
			continue
		if not _revealed(p):
			continue
		for k in range(_hole_views[i].size()):
			if k < p.hole.size():
				var cv: CardView = _hole_views[i][k]
				cv.visible = true
				cv.set_card(p.hole[k], true)


## Flip each revealed hand face-up in real-poker reveal order, announcing the
## made hand as it shows. Mucked hands stay face-down.
func _reveal_in_order(order: Array, revealed: Array) -> void:
	if game == null:
		return
	for pid in order:
		if not revealed.has(pid):
			continue
		var p: PokerPlayer = game.players[pid]
		for k in range(_hole_views[pid].size()):
			if k < p.hole.size():
				var cv: CardView = _hole_views[pid][k]
				cv.visible = true
				cv.set_card(p.hole[k], false)
		_sync_seats()
		SoundBank.play("deal", 1.0, -12.0)
		for k in range(_hole_views[pid].size()):
			if k < p.hole.size():
				var cv2: CardView = _hole_views[pid][k]
				await animate_flip(cv2, p.hole[k])
		var made := p.last_hand_detail if p.last_hand_detail != "" else p.last_hand_name
		if made != "":
			set_status("%s shows %s" % [p.display_name, made])
		else:
			set_status("%s shows" % p.display_name)
		await get_tree().create_timer(_pace("reveal_stagger", 0.45), false).timeout


## Lift the 5-card scoring hand off the felt: winners get the full gold lift,
## beaten-but-shown hands a smaller lift so the viewer can compare.
func _apply_spotlight() -> void:
	_clear_spotlight()
	if game == null:
		return
	for r in game.showdown_results:
		if not r.get("revealed", true):
			continue
		var pid: int = r["player"]
		var p: PokerPlayer = game.players[pid]
		var best5: Array = r.get("best5", [])
		if best5.is_empty():
			continue
		var lift := SPOTLIGHT_WIN_LIFT if p.is_winner else SPOTLIGHT_LOSE_LIFT
		for k in range(_hole_views[pid].size()):
			if k < p.hole.size() and _card_in(p.hole[k], best5):
				_lift_card(_hole_views[pid][k], lift, p.is_winner)
		for k in range(_community_views.size()):
			if k < game.community.size() and _card_in(game.community[k], best5):
				_lift_card(_community_views[k], lift, p.is_winner)


func _card_in(card: Card, best5: Array) -> bool:
	for b in best5:
		if PokerGame.card_matches(card, b):
			return true
	return false


func _lift_card(cv: CardView, lift: float, winner: bool) -> void:
	if _spotlight.has(cv):
		if winner:
			cv.set_highlight(true)
		return
	cv.set_meta("base_pos", cv.position)
	_spotlight.append(cv)
	cv.position = cv.position + Vector2(0, -lift)
	if winner:
		cv.set_highlight(true)


func _clear_spotlight() -> void:
	for cv in _spotlight:
		if is_instance_valid(cv):
			if cv.has_meta("base_pos"):
				cv.position = cv.get_meta("base_pos")
			cv.set_highlight(false)
	_spotlight.clear()


func clear_hand_visuals() -> void:
	for i in range(_seat_views.size()):
		for cv in _hole_views[i]:
			cv.visible = false
			cv.set_highlight(false)
	for cv in _community_views:
		cv.visible = false
		cv.set_highlight(false)
	_banner_panel.visible = false
	_result_panel.visible = false
	awaiting_result = false
	_history.clear()
	_last_recorded = ""
	_history_label.text = ""
	_clear_spotlight()
	_community_dealt = 0


func reset_for_new_hand() -> void:
	clear_hand_visuals()
	_sync_seats()


func _sync_seats() -> void:
	if game == null:
		return
	for i in range(_seat_views.size()):
		var p: PokerPlayer = game.players[i]
		_seat_views[i].bind(p)
		_seat_views[i].set_turn(i == game.to_act and not game.hand_over)
		_seat_views[i].set_dealer(i == game.button)
	if game.hand_over:
		_call_button.text = "—"
		_raise_button.text = "Raise"
	_pot_value = game.total_pot()
	_update_hud()
	queue_redraw()


## Play a batch of engine events with animation. Coroutine: await it.
func play_events(events: Array) -> void:
	if game == null:
		return
	if instant:
		refresh_all()
		return
	var hole_index := {}
	for ev in events:
		var type: String = ev.get("type", "")
		match type:
			"blinds_up":
				_update_hud()
				await show_banner("Blinds up: %d / %d" % [ev["small"], ev["big"]], GOLD, 1.3)
			"blind":
				var pid: int = ev["player"]
				_sync_seats()
				SoundBank.play("chip", randf_range(0.95, 1.05), -10.0)
				animate_chip_flight(seat_center(pid), POT_CENTER * size, GOLD, 2, 0.3)
				await get_tree().create_timer(_pace("blind", 0.10), false).timeout
			"deal_hole":
				var pid2: int = ev["player"]
				var idx: int = hole_index.get(pid2, 0)
				hole_index[pid2] = idx + 1
				animate_deal_hole(pid2, ev["card"], idx)
				await get_tree().create_timer(_pace("deal_hole", 0.08), false).timeout
			"action":
				var act: String = ev.get("action", "")
				var dwell := _pace("action_check", 0.22)
				if act == "fold":
					SoundBank.play("fold", randf_range(0.95, 1.05), -9.0)
					dwell = _pace("action_fold", 0.24)
				elif act == "check":
					SoundBank.play("check", randf_range(0.95, 1.05), -10.0)
					dwell = _pace("action_check", 0.22)
				elif act == "call":
					SoundBank.play("chip", randf_range(0.92, 1.0), -8.0)
					animate_chip_flight(seat_center(ev["player"]), POT_CENTER * size, Color("#5da84c"), 2, 0.3)
					dwell = _pace("action_call", 0.32)
				elif act == "raise":
					SoundBank.play("raise", randf_range(0.97, 1.05), -8.0)
					animate_chip_flight(seat_center(ev["player"]), POT_CENTER * size,
						BUTTON_RAISE, 4, 0.35)
					dwell = _pace("action_raise", 0.48)
				if ev.get("all_in", false):
					dwell += _pace("all_in_bonus", 0.30)
				_sync_seats()
				set_status(_action_message(ev))
				await get_tree().create_timer(dwell, false).timeout
			"street":
				await _deal_community(ev["cards"])
				_sync_seats()
				set_status(ev.get("name", "") + " \u2014 " + _turn_status())
				await get_tree().create_timer(_pace("street_settle", 0.40), false).timeout
			"refund":
				animate_chip_flight(POT_CENTER * size, seat_center(ev["player"]), Color("#9ad06a"), 2, 0.3)
				set_status(ev.get("message", ""))
				_sync_seats()
				await get_tree().create_timer(_pace("refund", 0.32), false).timeout
			"showdown":
				var order: Array = ev.get("reveal_order", [])
				if order.is_empty():
					for pl in game.players:
						if not pl.folded and not pl.out:
							order.append(pl.id)
				var revealed: Array = ev.get("revealed", order)
				await _reveal_in_order(order, revealed)
				_apply_spotlight()
				await get_tree().create_timer(_pace("spotlight_hold", 0.90), false).timeout
			"win":
				var wpid: int = ev["player"]
				_highlight_winner(wpid)
				animate_chip_flight(POT_CENTER * size, seat_center(wpid), GOLD, 5, 0.45)
				SoundBank.play("win", randf_range(0.98, 1.04), -6.0)
				set_status("%s wins %d" % [game.players[wpid].display_name, ev["amount"]])
				_sync_seats()
				await get_tree().create_timer(_pace("win", 0.70), false).timeout
			"hand_end":
				var wpid2: int = ev["winner"]
				_highlight_winner(wpid2)
				animate_chip_flight(POT_CENTER * size, seat_center(wpid2), GOLD, 5, 0.45)
				SoundBank.play("win", 1.0, -6.0)
				set_status(ev.get("message", ""))
				_sync_seats()
				await get_tree().create_timer(_pace("hand_end", 0.30), false).timeout
			"game_over":
				pass
	refresh_all()


func _action_message(ev: Dictionary) -> String:
	return ev.get("message", "")


func _turn_status() -> String:
	if game.hand_over:
		return ""
	var p := game.current_player()
	if p == null:
		return ""
	return "Your turn" if p.is_human else "%s to act" % p.display_name


func _highlight_winner(pid: int) -> void:
	for k in range(_hole_views[pid].size()):
		var cv: CardView = _hole_views[pid][k]
		if cv.visible:
			cv.set_highlight(true)
	_seat_views[pid].set_turn(true)


func _deal_community(cards: Array) -> void:
	for card in cards:
		if _community_dealt >= _community_views.size():
			break
		var cv: CardView = _community_views[_community_dealt]
		var target: Vector2 = _community_slots[_community_dealt] - cv.size * 0.5
		_community_dealt += 1
		cv.visible = true
		cv.scale = Vector2.ONE
		cv.position = DECK_ORIGIN * size - cv.size * 0.5
		cv.set_card(card, false)
		SoundBank.play("deal", randf_range(0.9, 1.05))
		var t := create_tween()
		t.tween_property(cv, "position", target, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await t.finished
		await animate_flip(cv, card)


func _update_hud() -> void:
	if game == null:
		return
	_hud_label.text = "Hand %d    Blinds %d / %d" % [game.hand_number, game.small_blind, game.big_blind]


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _build_done:
			_layout()


func _layout() -> void:
	var s := size
	if s.x < 1.0:
		return
	_hole_slots.clear()
	_community_slots.clear()

	for i in range(4):
		var center: Vector2 = SEAT_ANCHORS[i] * s
		var seat: SeatView = _seat_views[i]
		seat.size = SEAT_SIZE
		seat.position = center - seat.size * 0.5
		var hole_center: Vector2 = HOLE_ANCHORS[i] * s
		var card_size := HUMAN_CARD_SIZE if i == 0 else AI_CARD_SIZE
		var spread := card_size.x * 0.54
		var slots: Array = [
			hole_center + Vector2(-spread, 0),
			hole_center + Vector2(spread, 0),
		]
		_hole_slots[i] = slots
		for k in range(2):
			var cv: CardView = _hole_views[i][k]
			cv.size = card_size
			cv.pivot_offset = card_size * 0.5
			cv.position = slots[k] - card_size * 0.5

	var comm_center := COMMUNITY_CENTER * s
	var gap := COMMUNITY_SIZE.x + 12.0
	var total := gap * 5.0 - 12.0
	for k in range(5):
		var pos := comm_center + Vector2(-total * 0.5 + COMMUNITY_SIZE.x * 0.5 + k * gap, 0)
		_community_slots.append(pos)
		var cv: CardView = _community_views[k]
		cv.size = COMMUNITY_SIZE
		cv.pivot_offset = COMMUNITY_SIZE * 0.5
		cv.position = pos - COMMUNITY_SIZE * 0.5

	# HUD
	_hud_label.position = Vector2(20, 14)
	_hud_label.size = Vector2(420, 30)
	_mute_button.size = Vector2(110, 40)
	_mute_button.position = Vector2(s.x - 240, 12)
	_menu_button.size = Vector2(110, 40)
	_menu_button.position = Vector2(s.x - 120, 12)

	# Action bar
	var bar_h := 146.0
	_action_panel.position = Vector2(0, s.y - bar_h)
	_action_panel.size = Vector2(s.x, bar_h)
	var cx := s.x * 0.5
	_status_label.position = Vector2(28, 6)
	_status_label.size = Vector2(s.x - 56, 30)
	_history_label.position = Vector2(s.x - 488, 8)
	_history_label.size = Vector2(460, 24)
	_raise_label.position = Vector2(cx - 440, 38)
	_raise_label.size = Vector2(230, 34)
	_raise_slider.position = Vector2(cx - 210, 40)
	_raise_slider.size = Vector2(380, 34)
	for k in range(_quick_buttons.size()):
		var b: Button = _quick_buttons[k]
		b.size = Vector2(74, 34)
		b.position = Vector2(cx + 190 + k * 82, 39)
	var btn_w := 190.0
	var btn_h := 58.0
	var gap_b := 18.0
	var row_w := btn_w * 3 + gap_b * 2
	_fold_button.size = Vector2(btn_w, btn_h)
	_fold_button.position = Vector2(cx - row_w * 0.5, 88)
	_call_button.size = Vector2(btn_w, btn_h)
	_call_button.position = Vector2(cx - row_w * 0.5 + btn_w + gap_b, 88)
	_raise_button.size = Vector2(btn_w, btn_h)
	_raise_button.position = Vector2(cx - row_w * 0.5 + (btn_w + gap_b) * 2, 88)

	# Banner (top-left toast so it never covers the cards).
	var banner_w := minf(480.0, s.x * 0.42)
	_banner_panel.size = Vector2(banner_w, 58)
	_banner_panel.position = Vector2(20, 52)

	# End-of-hand summary, centred over the felt above the action bar.
	var result_w := minf(660.0, s.x * 0.72)
	_result_panel.size = Vector2(result_w, 300)
	_result_panel.position = Vector2((s.x - result_w) * 0.5, s.y * 0.10)


# ---------------------------------------------------------------------------
# Drawing: felt, rail, pot
# ---------------------------------------------------------------------------

func _draw() -> void:
	var s := size
	if s.x < 1.0:
		return
	draw_rect(Rect2(Vector2.ZERO, s), Color("#0a1210"))

	var center := Vector2(s.x * 0.5, s.y * 0.46)
	var rx := s.x * 0.465
	var ry := s.y * 0.43

	# Table shadow.
	draw_colored_polygon(_ellipse(center + Vector2(0, 14), rx * 1.02, ry * 1.02), Color(0, 0, 0, 0.45))
	# Rail.
	draw_colored_polygon(_ellipse(center, rx * 1.06, ry * 1.06), RAIL)
	draw_colored_polygon(_ellipse(center, rx * 1.01, ry * 1.01), RAIL_HI)
	# Felt with a soft inner highlight.
	draw_colored_polygon(_ellipse(center, rx, ry), FELT_DARK)
	draw_colored_polygon(_ellipse(center, rx * 0.82, ry * 0.82), FELT_DARK.lerp(FELT_LIGHT, 0.35))
	draw_colored_polygon(_ellipse(center, rx * 0.55, ry * 0.55), FELT_DARK.lerp(FELT_LIGHT, 0.6))
	# Gold inner ring.
	draw_polyline(_ellipse_outline(center, rx * 0.9, ry * 0.9), Color(GOLD.r, GOLD.g, GOLD.b, 0.25), 2.0)

	_draw_pot()


func _draw_pot() -> void:
	if _pot_value <= 0:
		return
	var center := POT_CENTER * size
	var font := get_theme_default_font()
	var text := "POT  %s" % _fmt(_pot_value)
	if game != null:
		var street := game.street_name()
		if street != "" and street != "Showdown" and street != "Complete":
			text += "  •  " + street.to_upper()
	var fs := 24
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad := 18.0
	var rect := Rect2(center - Vector2(tw * 0.5 + pad, 22), Vector2(tw + pad * 2, 44))
	draw_rect(rect, Color(0, 0, 0, 0.35), true)
	# chip icon
	draw_circle(center - Vector2(tw * 0.5 + 4, 0), 10, GOLD)
	draw_circle(center - Vector2(tw * 0.5 + 4, 0), 7, Color("#c9922f"))
	draw_string(font, center + Vector2(-tw * 0.5 + 20, 9), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#ffe9b0"))


func _ellipse(center: Vector2, rx: float, ry: float, segments: int = 64) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _ellipse_outline(center: Vector2, rx: float, ry: float, segments: int = 64) -> PackedVector2Array:
	var pts := _ellipse(center, rx, ry, segments)
	pts.append(pts[0])
	return pts


# ---------------------------------------------------------------------------
# Action bar state
# ---------------------------------------------------------------------------

func set_status(text: String, record: bool = true) -> void:
	if record:
		if _last_recorded != "" and _last_recorded != text:
			_history.push_front(_last_recorded)
			while _history.size() > 2:
				_history.pop_back()
			_history_label.text = "  •  ".join(PackedStringArray(_history))
		_last_recorded = text
	_status_label.text = text


func show_actions(legal: Dictionary) -> void:
	_human_can_raise = legal.get("can_raise", false)
	var to_call: int = legal.get("to_call", 0)
	var pot := game.total_pot() if game != null else 0
	if to_call > 0:
		set_status("Your turn — call %s to win %s" % [_fmt(legal.get("call_amount", to_call)), _fmt(pot)])
	elif _human_can_raise:
		set_status("Your turn — check or bet")
	else:
		set_status("Your turn — check")
	_fold_button.disabled = false
	_call_button.disabled = not (legal.get("can_check", false) or legal.get("can_call", false))
	if legal.get("can_check", false):
		_call_button.text = "Check"
	elif legal.get("can_call", false):
		var amt: int = legal.get("call_amount", 0)
		if legal.get("is_all_in_call", false):
			_call_button.text = "Call All-In %d" % amt
		else:
			_call_button.text = "Call %d" % amt
	else:
		_call_button.text = "\u2014"

	_raise_button.disabled = not _human_can_raise
	_raise_button.text = "Bet" if legal.get("to_call", 0) <= 0 else "Raise"

	_raise_slider.visible = _human_can_raise
	_raise_label.visible = _human_can_raise
	for b in _quick_buttons:
		b.visible = _human_can_raise
	if _human_can_raise:
		var lo: int = legal.get("min_raise_to", 0)
		var hi: int = legal.get("max_raise_to", lo)
		_raise_slider.min_value = lo
		_raise_slider.max_value = maxi(hi, lo)
		_raise_slider.step = _slider_step(lo, hi)
		_raise_slider.value = lo
		_update_raise_label()


func _slider_step(lo: int, hi: int) -> float:
	if hi < 200:
		return 5.0
	if hi < 2000:
		return 10.0
	return 25.0


func set_waiting(text: String) -> void:
	_fold_button.disabled = true
	_call_button.disabled = true
	_raise_button.disabled = true
	_call_button.text = "—"
	_raise_slider.visible = false
	_raise_label.visible = false
	for b in _quick_buttons:
		b.visible = false
	set_status(text, false)


func _on_raise_slider_changed(_value: float) -> void:
	_update_raise_label()


func _update_raise_label() -> void:
	var to := int(_raise_slider.value)
	var verb := "Raise to" if game != null and game.current_bet > 0 else "Bet"
	_raise_label.text = "%s %s" % [verb, _fmt(to)]
	if _human_can_raise:
		_raise_button.text = "%s %s" % [verb, _fmt(to)]


func _on_quick_press(kind: float) -> void:
	if game == null or not _human_can_raise:
		return
	var target := 0
	if kind < 0.0:
		target = int(_raise_slider.max_value)
	elif kind == 0.0:
		target = int(_raise_slider.min_value)
	else:
		# Standard pot-sized raise: match the bet first, then raise by the
		# pot after your call. total_pot() already holds every committed
		# chip (including live bets), so only the pending call is added.
		var hero := game.current_player()
		var to_call: int = game.current_bet - (hero.bet if hero != null else 0)
		target = PokerGame.pot_raise_target(game.current_bet, game.total_pot(),
			to_call, kind, int(_raise_slider.min_value), int(_raise_slider.max_value))
	target = clampi(target, int(_raise_slider.min_value), int(_raise_slider.max_value))
	_raise_slider.value = target
	_update_raise_label()


func _on_fold() -> void:
	SoundBank.play("click")
	_lock_actions()
	action_chosen.emit({"action": "fold", "amount": 0})


func _on_call() -> void:
	SoundBank.play("click")
	_lock_actions()
	var legal := game.get_legal_actions()
	action_chosen.emit({"action": "check" if legal.get("can_check", false) else "call", "amount": 0})


func _on_raise() -> void:
	SoundBank.play("click")
	_lock_actions()
	action_chosen.emit({"action": "raise", "amount": int(_raise_slider.value)})


## Programmatic equivalent of pressing the action buttons (used by autoplay).
## The slider must already be configured by show_actions().
func press_action(action: String, amount: int = 0) -> void:
	match action:
		"fold":
			_on_fold()
		"raise":
			_raise_slider.value = clampi(amount,
				int(_raise_slider.min_value), int(_raise_slider.max_value))
			_on_raise()
		_:
			_on_call()


func _lock_actions() -> void:
	_fold_button.disabled = true
	_call_button.disabled = true
	_raise_button.disabled = true
	_raise_slider.visible = false
	_raise_label.visible = false
	for b in _quick_buttons:
		b.visible = false


# ---------------------------------------------------------------------------
# Animations
# ---------------------------------------------------------------------------

func seat_center(index: int) -> Vector2:
	return SEAT_ANCHORS[index] * size


func animate_deal_hole(pid: int, card: Card, index: int) -> void:
	if not _hole_slots.has(pid) or index >= _hole_views[pid].size():
		return
	var cv: CardView = _hole_views[pid][index]
	var target: Vector2 = _hole_slots[pid][index] - cv.size * 0.5
	cv.visible = true
	cv.position = DECK_ORIGIN * size - cv.size * 0.5
	cv.scale = Vector2(0.3, 0.3)
	cv.modulate = Color.WHITE
	cv.set_card(card, game.players[pid].is_human)
	SoundBank.play("deal", randf_range(0.92, 1.08))
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(cv, "position", target, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(cv, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func animate_chip_flight(from: Vector2, to: Vector2, color: Color, count: int = 3, dur: float = 0.35) -> void:
	for i in range(count):
		var chip := _make_chip(color)
		chip.size = Vector2(22, 22)
		chip.position = from - chip.size * 0.5 + Vector2(randf_range(-6, 6), randf_range(-6, 6))
		_fx_layer.add_child(chip)
		var t := create_tween()
		var mid := (from + to) * 0.5 + Vector2(randf_range(-40, 40), -60 - randf_range(0, 40))
		t.tween_property(chip, "position", mid, dur * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(chip, "position", to - chip.size * 0.5, dur * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(chip.queue_free)


func _make_chip(color: Color) -> Panel:
	var chip := Panel.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(11)
	sb.border_color = Color(1, 1, 1, 0.6)
	sb.set_border_width_all(2)
	chip.add_theme_stylebox_override("panel", sb)
	return chip


func animate_flip(cv: CardView, card: Card) -> void:
	var t := create_tween()
	t.tween_property(cv, "scale:x", 0.05, 0.09)
	await t.finished
	cv.set_card(card, true)
	var t2 := create_tween()
	t2.tween_property(cv, "scale:x", 1.0, 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t2.finished


func show_banner(text: String, color: Color, duration: float = 1.6) -> void:
	_banner_label.text = text
	_banner_label.add_theme_color_override("font_color", color)
	var sb: StyleBoxFlat = _banner_panel.get_theme_stylebox("panel")
	sb.border_color = color
	_banner_panel.visible = true
	_banner_panel.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_banner_panel, "modulate:a", 1.0, 0.15)
	await get_tree().create_timer(duration, false).timeout
	var t2 := create_tween()
	t2.tween_property(_banner_panel, "modulate:a", 0.0, 0.25)
	await t2.finished
	_banner_panel.visible = false


# ---------------------------------------------------------------------------
# End-of-hand summary
# ---------------------------------------------------------------------------

## Reveal the board and every contender's holding, then hold for `seconds` or
## until the player taps/clicks/presses a key. No-op when running instantly.
func show_hand_result(seconds: float) -> void:
	if instant or game == null:
		return
	_refresh_result_panel()
	set_status(_result_title.text, false)
	_result_panel.visible = true
	_result_panel.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_result_panel, "modulate:a", 1.0, 0.15)
	await t.finished
	awaiting_result = true
	_result_skipped = false
	var elapsed := 0.0
	while elapsed < seconds and not _result_skipped:
		await get_tree().create_timer(0.05, false).timeout
		elapsed += 0.05
	awaiting_result = false
	var t2 := create_tween()
	t2.tween_property(_result_panel, "modulate:a", 0.0, 0.2)
	await t2.finished
	_result_panel.visible = false


## Let the player cut the summary short and move on to the next hand.
func skip_result() -> void:
	if awaiting_result:
		_result_skipped = true


func _unhandled_input(event: InputEvent) -> void:
	if not awaiting_result:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		pressed = event.pressed
	elif event is InputEventScreenTouch:
		pressed = event.pressed
	if pressed:
		skip_result()
		get_viewport().set_input_as_handled()


func _refresh_result_panel() -> void:
	for child in _result_rows.get_children():
		child.queue_free()
	_result_board.text = _board_text()
	if game.showdown_results.is_empty():
		_refresh_uncontested_result()
		return
	var winners: Array = []
	for r in game.showdown_results:
		if r.get("won", false):
			winners.append(r)
	if winners.size() == 1:
		var w: Dictionary = winners[0]
		var wp: PokerPlayer = game.players[int(w["player"])]
		_result_title.text = "%s %s %s" % [wp.display_name, _win_verb(wp), _fmt(int(w.get("gross", w.get("amount", 0))))]
	elif winners.size() > 1:
		var shares: Array = []
		for wr in winners:
			shares.append(_fmt(int(wr.get("gross", wr.get("amount", 0)))))
		_result_title.text = "Split pot — %s each" % " / ".join(PackedStringArray(shares))
	else:
		_result_title.text = "Showdown"
	for r in game.showdown_results:
		_add_result_row(r)
	_add_pot_lines()


func _refresh_uncontested_result() -> void:
	for p in game.players:
		if p.is_winner:
			_result_title.text = "%s %s %s" % [p.display_name, _win_verb(p), _fmt(p.won_last)]
			return
	_result_title.text = "Hand complete"


func _win_verb(p: PokerPlayer) -> String:
	return "win" if p.is_human else "wins"


func _add_result_row(r: Dictionary) -> void:
	var p: PokerPlayer = game.players[int(r["player"])]
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not r.get("revealed", true):
		name_label.text = "%s  —  mucks" % p.display_name
		name_label.add_theme_color_override("font_color", Color("#9fb3bd"))
	else:
		var detail: String = r.get("detail", r.get("name", ""))
		var hole: Array = r.get("hole", [])
		if not hole.is_empty():
			name_label.text = "%s  %s  —  %s" % [p.display_name, _hole_text(hole), detail]
		elif detail != "":
			name_label.text = "%s  —  %s" % [p.display_name, detail]
		else:
			name_label.text = p.display_name
		name_label.add_theme_color_override("font_color",
			Color("#ffe9b0") if r.get("won", false) else Color("#9fb3bd"))
	var amount_label := Label.new()
	amount_label.add_theme_font_size_override("font_size", 18)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Gross chip movement only: winners show what the pot paid them, losers
	# show what they put in.
	var gross: int = int(r.get("gross", r.get("amount", 0)))
	var lost: int = int(r.get("committed", 0))
	if r.get("won", false):
		amount_label.text = "+%s" % _fmt(gross)
		amount_label.add_theme_color_override("font_color", Color("#8fd694"))
	elif lost > 0:
		amount_label.text = "-%s" % _fmt(lost)
		amount_label.add_theme_color_override("font_color", Color("#e07060"))
	else:
		amount_label.text = "—"
		amount_label.add_theme_color_override("font_color", Color("#9fb3bd"))
	row.add_child(name_label)
	row.add_child(amount_label)
	_result_rows.add_child(row)


## One small line per side pot so split/odd-chip awards are not a mystery.
func _add_pot_lines() -> void:
	if game == null or game.last_pots.size() <= 1:
		return
	var idx := 1
	for pot in game.last_pots:
		var names := PackedStringArray()
		for pid in pot.get("eligible", []):
			names.append(game.players[pid].display_name)
		var line := Label.new()
		line.add_theme_font_size_override("font_size", 15)
		line.add_theme_color_override("font_color", Color("#7d8f97"))
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.text = "Pot %d: %s (%s)" % [idx, _fmt(int(pot.get("amount", 0))), ", ".join(names)]
		_result_rows.add_child(line)
		idx += 1


func _board_text() -> String:
	if game == null or game.community.is_empty():
		return ""
	var parts: Array = []
	for c in game.community:
		parts.append(c.rank_label() + _suit_symbol(c.suit))
	return "Board:  " + "  ".join(PackedStringArray(parts))


func _suit_symbol(suit: int) -> String:
	return SUIT_SYMBOLS[suit] if suit >= 0 and suit < SUIT_SYMBOLS.size() else ""


func _fmt(amount: int) -> String:
	var s := str(absi(amount))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if amount < 0 else "") + out


func _hole_text(hole: Array) -> String:
	var parts := PackedStringArray()
	for c in hole:
		parts.append(c.rank_label() + _suit_symbol(c.suit))
	return "  ".join(parts)
