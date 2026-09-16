class_name SeatView
extends Control

## The name plate, stack, and status for one player. Cards live in CardLayer.

const PLATE_BG := Color("#10171b", 0.86)
const PLATE_BORDER := Color("#2b3a42")
const TURN_BORDER := Color("#f2c14e")
const OUT_BG := Color("#10171b", 0.45)

var player: PokerPlayer = null
var is_turn: bool = false
var is_dealer: bool = false
var emphasized: bool = false

var _plate: StyleBoxFlat
var _glow: StyleBoxFlat
var _last_size := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate = StyleBoxFlat.new()
	_plate.bg_color = PLATE_BG
	_plate.border_color = PLATE_BORDER
	_plate.set_border_width_all(2)

	_glow = StyleBoxFlat.new()
	_glow.bg_color = Color(0, 0, 0, 0)
	_glow.border_color = TURN_BORDER
	_glow.set_border_width_all(3)
	_glow.shadow_color = Color(TURN_BORDER.r, TURN_BORDER.g, TURN_BORDER.b, 0.45)
	_glow.shadow_size = 10


func bind(p: PokerPlayer) -> void:
	player = p
	queue_redraw()


func set_turn(value: bool) -> void:
	if is_turn != value:
		is_turn = value
		queue_redraw()


func set_dealer(value: bool) -> void:
	if is_dealer != value:
		is_dealer = value
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if player == null or size.x < 4.0:
		return
	_sync_styles()
	var rect := Rect2(Vector2.ZERO, size)
	var style := _plate
	if player.out:
		style.bg_color = OUT_BG
	else:
		style.bg_color = PLATE_BG
	draw_style_box(style, rect)
	if is_turn:
		draw_style_box(_glow, rect.grow(2))

	var font := get_theme_default_font()
	var avatar_r := size.y * 0.30
	var avatar_c := Vector2(avatar_r + 12, size.y * 0.5)
	var avatar_color := player.avatar_color
	if player.out:
		avatar_color = Color(avatar_color, 0.35)
	draw_circle(avatar_c, avatar_r, avatar_color)
	draw_arc(avatar_c, avatar_r, 0, TAU, 32, Color(1, 1, 1, 0.25), 2.0)
	var initial := player.display_name.substr(0, 1).to_upper()
	var initial_size := int(avatar_r * 1.1)
	var iw := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, initial_size).x
	draw_string(font, avatar_c + Vector2(-iw * 0.5, initial_size * 0.35), initial,
		HORIZONTAL_ALIGNMENT_LEFT, -1, initial_size, Color("#0e1114"))

	var text_x := avatar_c.x + avatar_r + 12
	var name_color := Color("#f5f7f8") if not player.out else Color(1, 1, 1, 0.4)
	var name_size := int(size.y * 0.20)
	draw_string(font, Vector2(text_x, size.y * 0.32), player.display_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, name_color)

	var chips_size := int(size.y * 0.23)
	var chips_color := Color("#ffd873") if not player.out else Color(1, 1, 1, 0.35)
	_chip_icon(Vector2(text_x + chips_size * 0.34, size.y * 0.72), chips_size * 0.32)
	draw_string(font, Vector2(text_x + chips_size * 0.78, size.y * 0.80), _format(player.chips),
		HORIZONTAL_ALIGNMENT_LEFT, -1, chips_size, chips_color)

	if player.last_hand_name != "":
		var hn_size := int(size.y * 0.19)
		var hn := player.last_hand_name
		var hw := font.get_string_size(hn, HORIZONTAL_ALIGNMENT_LEFT, -1, hn_size).x
		draw_string(font, Vector2(size.x - hw - 12, size.y * 0.56), hn,
			HORIZONTAL_ALIGNMENT_LEFT, -1, hn_size, Color("#f2c14e"))

	var status := ""
	var status_color := Color("#9fb3bd")
	if player.out:
		status = "Out"
		status_color = Color(1, 1, 1, 0.35)
	elif player.folded:
		status = "Folded"
		status_color = Color("#a7b0b6")
	elif player.all_in:
		status = "All in"
		status_color = Color("#ff9d6b")
	elif player.last_action == "Small blind":
		status = "SB %s" % _format(player.bet)
		status_color = Color("#8fd694")
	elif player.last_action == "Big blind":
		status = "BB %s" % _format(player.bet)
		status_color = Color("#8fd694")
	elif player.bet > 0:
		status = "Bet %s" % _format(player.bet)
		status_color = Color("#8fd694")
	if status != "":
		var status_size := int(size.y * 0.165)
		var sw := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, status_size).x
		draw_string(font, Vector2(size.x - sw - 12, size.y * 0.84), status,
			HORIZONTAL_ALIGNMENT_LEFT, -1, status_size, status_color)

	if is_dealer:
		var d_r := size.y * 0.175
		var d_c := Vector2(size.x - d_r - 8, d_r + 4)
		draw_circle(d_c, d_r + 2.0, Color(0, 0, 0, 0.45))
		draw_circle(d_c, d_r, Color("#f4f4f4"))
		draw_arc(d_c, d_r, 0, TAU, 24, Color("#b8a45a"), 2.0)
		var ds := int(d_r * 1.2)
		var dw := font.get_string_size("D", HORIZONTAL_ALIGNMENT_LEFT, -1, ds).x
		draw_string(font, d_c + Vector2(-dw * 0.5, ds * 0.35), "D",
			HORIZONTAL_ALIGNMENT_LEFT, -1, ds, Color("#333018"))


func _chip_icon(center: Vector2, r: float) -> void:
	draw_circle(center, r, Color("#e8b64c"))
	draw_circle(center, r * 0.72, Color("#c9922f"))
	draw_arc(center, r * 0.86, 0, TAU, 20, Color(1, 1, 1, 0.5), 1.5)


func _format(amount: int) -> String:
	var s := str(amount)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


func _sync_styles() -> void:
	if size == _last_size:
		return
	_last_size = size
	var radius := int(size.y * 0.22)
	_plate.set_corner_radius_all(radius)
	_glow.set_corner_radius_all(radius + 2)
