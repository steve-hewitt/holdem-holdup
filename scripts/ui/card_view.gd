class_name CardView
extends Control

## A playing-card Control drawn entirely in code (no textures).

var card: Card = null
var face_up: bool = false
var highlighted: bool = false
var accent: Color = Color("#e8b64c")

var _face_style: StyleBoxFlat
var _back_style: StyleBoxFlat
var _back_inner: StyleBoxFlat
var _hl_style: StyleBoxFlat
var _last_size := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face_style = StyleBoxFlat.new()
	_face_style.bg_color = Color("#fcfbf6")
	_face_style.border_color = Color("#d9d4c6")
	_face_style.set_border_width_all(2)
	_face_style.shadow_color = Color(0, 0, 0, 0.35)
	_face_style.shadow_size = 6
	_face_style.shadow_offset = Vector2(0, 3)

	_back_style = StyleBoxFlat.new()
	_back_style.bg_color = Color("#2b3f78")
	_back_style.border_color = Color("#e9edff")
	_back_style.set_border_width_all(3)
	_back_style.shadow_color = Color(0, 0, 0, 0.35)
	_back_style.shadow_size = 6
	_back_style.shadow_offset = Vector2(0, 3)

	_back_inner = StyleBoxFlat.new()
	_back_inner.bg_color = Color("#3a53a0")
	_back_inner.border_color = Color(1, 1, 1, 0.35)
	_back_inner.set_border_width_all(2)

	_hl_style = StyleBoxFlat.new()
	_hl_style.bg_color = Color(0, 0, 0, 0)
	_hl_style.border_color = accent
	_hl_style.set_border_width_all(4)


func set_card(new_card: Card, up: bool = true) -> void:
	card = new_card
	face_up = up
	queue_redraw()


func set_highlight(value: bool) -> void:
	highlighted = value
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if size.x < 4.0 or size.y < 4.0:
		return
	_sync_styles()
	var rect := Rect2(Vector2.ZERO, size)
	if face_up and card != null:
		draw_style_box(_face_style, rect)
		_draw_face(rect)
	else:
		draw_style_box(_back_style, rect)
		_draw_back(rect)
	if highlighted:
		_hl_style.border_color = accent
		draw_style_box(_hl_style, rect)


func _sync_styles() -> void:
	if size == _last_size:
		return
	_last_size = size
	var radius := int(minf(size.x, size.y) * 0.12)
	_face_style.set_corner_radius_all(radius)
	_back_style.set_corner_radius_all(radius)
	_back_inner.set_corner_radius_all(maxi(radius - 3, 2))
	_hl_style.set_corner_radius_all(radius + 1)


func _draw_face(rect: Rect2) -> void:
	var color := card.color()
	var font := get_theme_default_font()
	var rank_size := int(size.y * 0.26)
	var corner_suit_r := size.y * 0.075
	var pad := size.x * 0.10

	var top_rank := card.rank_label()
	draw_string(font, Vector2(pad, size.y * 0.28), top_rank,
		HORIZONTAL_ALIGNMENT_LEFT, -1, rank_size, color)

	var suit_center := Vector2(pad + rank_size * 0.28, size.y * 0.40)
	_draw_suit(suit_center, corner_suit_r, card.suit, color)

	# Large central pip.
	_draw_suit(Vector2(size.x * 0.5, size.y * 0.63), size.y * 0.17, card.suit, color)

	# Mirror the rank in the bottom-right (right-aligned, no rotation).
	var bottom_size := int(size.y * 0.20)
	draw_string(font, Vector2(0, size.y - pad * 0.5), top_rank,
		HORIZONTAL_ALIGNMENT_RIGHT, size.x - pad, bottom_size, color)


func _draw_back(rect: Rect2) -> void:
	var inset := rect.grow(-size.x * 0.13)
	draw_style_box(_back_inner, inset)
	_draw_suit(rect.get_center(), size.y * 0.20, Card.SUIT_SPADES, Color(1, 1, 1, 0.22))


func _draw_suit(center: Vector2, r: float, suit: int, color: Color) -> void:
	match suit:
		Card.SUIT_DIAMONDS:
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -r),
				center + Vector2(r * 0.74, 0),
				center + Vector2(0, r),
				center + Vector2(-r * 0.74, 0),
			]), color)
		Card.SUIT_HEARTS:
			_draw_heart(center, r, color, false)
		Card.SUIT_SPADES:
			_draw_heart(center, r, color, true)
		_:
			_draw_club(center, r, color)


func _draw_heart(center: Vector2, r: float, color: Color, flip: bool) -> void:
	if not flip:
		draw_circle(center + Vector2(-r * 0.45, -r * 0.30), r * 0.53, color)
		draw_circle(center + Vector2(r * 0.45, -r * 0.30), r * 0.53, color)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-r * 1.0, -r * 0.05),
			center + Vector2(r * 1.0, -r * 0.05),
			center + Vector2(0, r * 1.05),
		]), color)
	else:
		# Spade: inverted heart plus a stem.
		draw_circle(center + Vector2(-r * 0.45, r * 0.30), r * 0.53, color)
		draw_circle(center + Vector2(r * 0.45, r * 0.30), r * 0.53, color)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-r * 1.0, r * 0.05),
			center + Vector2(r * 1.0, r * 0.05),
			center + Vector2(0, -r * 1.05),
		]), color)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(0, r * 0.15),
			center + Vector2(r * 0.32, r * 1.0),
			center + Vector2(-r * 0.32, r * 1.0),
		]), color)


func _draw_club(center: Vector2, r: float, color: Color) -> void:
	draw_circle(center + Vector2(0, -r * 0.52), r * 0.50, color)
	draw_circle(center + Vector2(-r * 0.52, r * 0.34), r * 0.50, color)
	draw_circle(center + Vector2(r * 0.52, r * 0.34), r * 0.50, color)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, r * 0.15),
		center + Vector2(r * 0.30, r * 0.98),
		center + Vector2(-r * 0.30, r * 0.98),
	]), color)
