extends Control

## Application controller: title screen, table, turn loop, pause, and results.

const DESIGN := Vector2(1280, 720)

var table: TableView
var game: PokerGame
var ai: PokerAI

var _stage: Control
var _title_screen: Control
var _pause_screen: Control
var _result_screen: Control
var _result_title: Label
var _result_body: Label
var _bold_font: FontVariation

var _session: int = 0
var _running: bool = false
var _screenshot_path: String = ""
var _shot_frames: int = 0
var _autoplay: bool = false
var _turbo: bool = false
var _hands_target: int = -1
var _shot_screen: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bold_font = FontVariation.new()
	_bold_font.base_font = ThemeDB.fallback_font
	_bold_font.variation_embolden = 0.6

	var bg := ColorRect.new()
	bg.color = Color("#070d0c")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_stage = Control.new()
	_stage.size = DESIGN
	_stage.pivot_offset = DESIGN * 0.5
	add_child(_stage)

	table = TableView.new()
	table.size = DESIGN
	table.process_mode = Node.PROCESS_MODE_PAUSABLE
	table.menu_pressed.connect(_open_pause)
	table.mute_toggled.connect(_toggle_mute)
	_stage.add_child(table)

	_build_title()
	_build_pause()
	_build_result()

	get_viewport().size_changed.connect(_layout_stage)
	_layout_stage()
	_show_title()
	_parse_cmdline()


func _layout_stage() -> void:
	var s := get_viewport_rect().size
	var scale := minf(s.x / DESIGN.x, s.y / DESIGN.y)
	_stage.scale = Vector2(scale, scale)
	_stage.position = (s - DESIGN * scale) * 0.5


# ---------------------------------------------------------------------------
# Screens
# ---------------------------------------------------------------------------

func _build_title() -> void:
	_title_screen = _make_overlay(Color("#050b09"), Color("#123c27"))
	var title := _make_label("HOLD'EM", 84, Color("#f2c14e"), true)
	title.position = Vector2(0, 96)
	title.size = Vector2(DESIGN.x, 100)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_screen.add_child(title)

	var sub := _make_label("HOLDUP", 60, Color("#e9f0f2"), true)
	sub.position = Vector2(0, 182)
	sub.size = Vector2(DESIGN.x, 80)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_screen.add_child(sub)

	var tag := _make_label("Texas Hold'em against three rivals", 24, Color("#9fb3bd"))
	tag.position = Vector2(0, 280)
	tag.size = Vector2(DESIGN.x, 40)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_screen.add_child(tag)

	var play := _make_button("DEAL ME IN", Color("#d9a83a"), 28)
	play.size = Vector2(300, 76)
	play.position = Vector2(DESIGN.x * 0.5 - 150, 360)
	play.pressed.connect(_on_play_pressed)
	_title_screen.add_child(play)

	var info := _make_label("1,000 chips \u00b7 Blinds 10/20 \u00b7 Blinds rise every 8 hands", 20, Color("#7d8f97"))
	info.position = Vector2(0, 460)
	info.size = Vector2(DESIGN.x, 30)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_screen.add_child(info)

	var keys := _make_label("Mouse or touch to play   \u00b7   F fold   \u00b7   C check / call   \u00b7   R raise   \u00b7   Esc menu", 18, Color("#5f7079"))
	keys.position = Vector2(0, 640)
	keys.size = Vector2(DESIGN.x, 30)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_screen.add_child(keys)
	_stage.add_child(_title_screen)


func _build_pause() -> void:
	_pause_screen = _make_overlay(Color(0, 0, 0, 0.65))
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#101a1e")
	sb.set_corner_radius_all(18)
	sb.border_color = Color("#2b3a42")
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	panel.size = Vector2(420, 300)
	panel.position = Vector2(DESIGN.x * 0.5 - 210, DESIGN.y * 0.5 - 150)
	_pause_screen.add_child(panel)

	var title := _make_label("PAUSED", 40, Color("#f2c14e"), true)
	title.position = Vector2(0, 30)
	title.size = Vector2(420, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var resume := _make_button("Resume", Color("#2f7bd6"), 24)
	resume.size = Vector2(240, 60)
	resume.position = Vector2(90, 110)
	resume.pressed.connect(_close_pause)
	panel.add_child(resume)

	var quit := _make_button("Quit to Title", Color("#c0453b"), 24)
	quit.size = Vector2(240, 60)
	quit.position = Vector2(90, 190)
	quit.pressed.connect(_quit_to_title)
	panel.add_child(quit)
	_stage.add_child(_pause_screen)


func _build_result() -> void:
	_result_screen = _make_overlay(Color("#0a0d0c"), Color("#1c3a2c"))
	_result_title = _make_label("", 64, Color("#f2c14e"), true)
	_result_title.position = Vector2(0, 150)
	_result_title.size = Vector2(DESIGN.x, 90)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_screen.add_child(_result_title)

	_result_body = _make_label("", 24, Color("#c9d6da"))
	_result_body.position = Vector2(0, 260)
	_result_body.size = Vector2(DESIGN.x, 120)
	_result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_screen.add_child(_result_body)

	var again := _make_button("PLAY AGAIN", Color("#d9a83a"), 28)
	again.size = Vector2(300, 76)
	again.position = Vector2(DESIGN.x * 0.5 - 150, 430)
	again.pressed.connect(_on_play_pressed)
	_result_screen.add_child(again)
	_stage.add_child(_result_screen)


func _make_overlay(bg: Color, gradient_top: Color = Color(0, 0, 0, 0)) -> Control:
	var overlay := Control.new()
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	if gradient_top.a > 0.0:
		var grad := Gradient.new()
		grad.set_color(0, gradient_top)
		grad.set_color(1, bg)
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 8
		tex.height = 256
		tex.fill_from = Vector2(0.5, 0.0)
		tex.fill_to = Vector2(0.5, 1.0)
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.add_child(tr)
	else:
		var rect := ColorRect.new()
		rect.color = bg
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.add_child(rect)
	return overlay


func _make_label(text: String, font_size: int, color: Color, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_font_override("font", _bold_font)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _make_button(text: String, color: Color, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_font_override("font", _bold_font)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(16)
	var hover := StyleBoxFlat.new()
	hover.bg_color = color.lightened(0.12)
	hover.set_corner_radius_all(16)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = color.darkened(0.15)
	pressed.set_corner_radius_all(16)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _show_title() -> void:
	_session += 1
	_running = false
	get_tree().paused = false
	table.visible = false
	_title_screen.visible = true
	_pause_screen.visible = false
	_result_screen.visible = false


func _on_play_pressed() -> void:
	SoundBank.play("click")
	_start_game()


# ---------------------------------------------------------------------------
# Game loop
# ---------------------------------------------------------------------------

func _start_game() -> void:
	_session += 1
	var my_session := _session
	_running = true
	get_tree().paused = false
	table.visible = true
	_title_screen.visible = false
	_pause_screen.visible = false
	_result_screen.visible = false

	var defs := [
		{"id": 0, "name": "You", "chips": 1000, "human": true, "color": Color("#3f8ee0")},
		{"id": 1, "name": "Rusty", "chips": 1000, "human": false, "personality": "rock", "color": Color("#b5651d")},
		{"id": 2, "name": "Mona", "chips": 1000, "human": false, "personality": "aggressive", "color": Color("#a1447a")},
		{"id": 3, "name": "Duke", "chips": 1000, "human": false, "personality": "loose", "color": Color("#4b8f5a")},
	]
	game = PokerGame.new()
	game.setup(defs, 10, 20)
	ai = PokerAI.new()
	table.set_game(game)
	table.reset_for_new_hand()
	await get_tree().process_frame
	if my_session != _session:
		return
	if _shot_screen == "pause":
		_open_pause()
		return
	if _shot_screen == "result":
		_show_result(true)
		return
	_next_hand(my_session)


func _next_hand(my_session: int) -> void:
	if my_session != _session:
		return
	if _check_game_end(my_session):
		return
	table.reset_for_new_hand()
	table.set_waiting("Dealing\u2026")
	var events := game.start_hand()
	await table.play_events(events)
	if my_session != _session:
		return
	if _check_game_end(my_session):
		return
	_run_hand(my_session)


func _check_game_end(my_session: int) -> bool:
	if my_session != _session:
		return true
	if not game.hand_over and not game.game_over:
		return false
	var human := game.human_player()
	if human.chips <= 0:
		_show_result(false)
		return true
	if game.active_player_count() <= 1:
		_show_result(true)
		return true
	return false


func _run_hand(my_session: int) -> void:
	while not game.hand_over:
		if my_session != _session:
			return
		var p := game.current_player()
		if p == null:
			break
		if p.is_human:
			await _human_turn(my_session)
		else:
			table.set_waiting("%s is thinking\u2026" % p.display_name)
			var delay := 0.0 if _turbo else randf_range(0.30, 0.60)
			await get_tree().create_timer(delay, false).timeout
			if my_session != _session:
				return
			var decision := ai.decide(game, p)
			var events := game.apply(decision["action"], decision.get("amount", 0))
			await table.play_events(events)
	if my_session != _session:
		return
	await _finish_hand(my_session)


func _human_turn(my_session: int) -> void:
	if my_session != _session:
		return
	if _autoplay:
		# Exercise the real UI path: show the buttons, then auto-press them.
		table.show_actions(game.get_legal_actions())
		var timer := get_tree().create_timer(0.0 if _turbo else randf_range(0.30, 0.55), false)
		timer.timeout.connect(_auto_press_human.bind(my_session))
		var data: Dictionary = await table.action_chosen
		if my_session != _session:
			return
		var events := game.apply(data.get("action", "check"), data.get("amount", 0))
		await table.play_events(events)
		return
	var legal := game.get_legal_actions()
	table.show_actions(legal)
	var data: Dictionary = await table.action_chosen
	if my_session != _session:
		return
	var events := game.apply(data.get("action", "check"), data.get("amount", 0))
	await table.play_events(events)


func _auto_press_human(my_session: int) -> void:
	if my_session != _session or game == null or game.hand_over:
		return
	var p := game.current_player()
	if p == null or not p.is_human:
		return
	var decision := ai.decide(game, p)
	# Drive the real buttons so the whole UI wiring is exercised.
	table.press_action(decision.get("action", "check"), decision.get("amount", 0))


func _finish_hand(my_session: int) -> void:
	if my_session != _session:
		return
	var human := game.human_player()
	if human.is_winner:
		table.set_status("You win %d!" % human.won_last)
		if not table.instant:
			table.show_banner("You win %d" % human.won_last, TableView.GOLD, 1.8)
		if human.won_last >= game.big_blind * 12:
			SoundBank.play("jackpot", 1.0, -5.0)
	else:
		table.set_status("Hand complete")
	# Reveal opponent hands briefly via their seats is handled by showdown.
	var wait := 0.0 if _turbo else 2.0
	await get_tree().create_timer(wait, false).timeout
	if my_session != _session:
		return
	if _hands_target > 0 and game.hand_number >= _hands_target:
		print("[autoplay] completed %d hands; chips=%d" % [game.hand_number, _total_chips()])
		SoundBank.stop_all()
		get_tree().quit()
		return
	_next_hand(my_session)


func _total_chips() -> int:
	var total := 0
	for p in game.players:
		total += p.chips
	return total


func _show_result(won: bool) -> void:
	_running = false
	get_tree().paused = false
	table.visible = false
	_result_screen.visible = true
	if won:
		_result_title.text = "YOU WIN!"
		_result_title.add_theme_color_override("font_color", Color("#f2c14e"))
		_result_body.text = "You took every chip on the table.\nA clean sweep \u2014 nicely played."
		SoundBank.play("jackpot", 1.0, -4.0)
	else:
		_result_title.text = "YOU'RE OUT"
		_result_title.add_theme_color_override("font_color", Color("#e07060"))
		_result_body.text = "You ran out of chips on hand %d.\nThe table wins this time \u2014 try again?" % game.hand_number
		SoundBank.play("lose", 1.0, -6.0)
	if _autoplay or _turbo:
		print("[autoplay] game over: won=%s hands=%d chips=%d" % [str(won), game.hand_number, _total_chips()])
		SoundBank.stop_all()
		get_tree().quit()


# ---------------------------------------------------------------------------
# Pause / menu
# ---------------------------------------------------------------------------

func _open_pause() -> void:
	SoundBank.play("click")
	get_tree().paused = true
	_pause_screen.visible = true


func _close_pause() -> void:
	SoundBank.play("click")
	get_tree().paused = false
	_pause_screen.visible = false


func _quit_to_title() -> void:
	SoundBank.play("click")
	get_tree().paused = false
	_running = false
	_show_title()


func _toggle_mute() -> void:
	var muted := SoundBank.toggle_mute()
	table._mute_button.text = "Muted" if muted else "Sound"


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	if _result_screen.visible:
		if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
			_on_play_pressed()
		return
	if _title_screen.visible:
		if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
			_on_play_pressed()
		return
	if _pause_screen.visible:
		if key == KEY_ESCAPE:
			_close_pause()
		return
	if key == KEY_ESCAPE:
		_open_pause()
		return
	if game == null or game.hand_over or game.current_player() == null:
		return
	if not game.current_player().is_human:
		return
	match key:
		KEY_F:
			if not table._fold_button.disabled:
				table._on_fold()
		KEY_C, KEY_SPACE:
			if not table._call_button.disabled:
				table._on_call()
		KEY_R:
			if not table._raise_button.disabled:
				table._on_raise()
		KEY_UP:
			table._raise_slider.value = minf(table._raise_slider.value + table._raise_slider.step,
				table._raise_slider.max_value)
		KEY_DOWN:
			table._raise_slider.value = maxf(table._raise_slider.value - table._raise_slider.step,
				table._raise_slider.min_value)


# ---------------------------------------------------------------------------
# Screenshot tool (developer convenience)
# ---------------------------------------------------------------------------

func _parse_cmdline() -> void:
	var autostart := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-title="):
			_screenshot_path = arg.substr(13)
			_shot_frames = 60
		elif arg.begins_with("--shot="):
			_screenshot_path = arg.substr(7)
			autostart = true
		elif arg.begins_with("--frames="):
			_shot_frames = int(arg.substr(9))
		elif arg.begins_with("--shot-screen="):
			_shot_screen = arg.substr(14)
			autostart = true
		elif arg == "--autoplay":
			_autoplay = true
		elif arg == "--turbo":
			_turbo = true
			_autoplay = true
		elif arg.begins_with("--hands="):
			_hands_target = int(arg.substr(8))
	if _screenshot_path != "" and _shot_frames <= 0:
		_shot_frames = 150
	if table != null:
		table.instant = _turbo
	if autostart or _autoplay:
		_on_play_pressed()


func _process(_delta: float) -> void:
	if _shot_frames > 0:
		_shot_frames -= 1
		if _shot_frames == 0:
			var image: Image = get_viewport().get_texture().get_image()
			if image != null:
				image.save_png(_screenshot_path)
			else:
				push_warning("Screenshot capture returned no image; skipping " + _screenshot_path)
			SoundBank.stop_all()
			get_tree().quit()
