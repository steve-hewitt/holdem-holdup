extends GutTest

## UI-side tests for the casino all-in exposure: exposed hands flip face-up
## and stay up through the runout, and runout community cards arrive face-up.


func _make_table() -> TableView:
	var table := TableView.new()
	add_child_autofree(table)
	table.set_anchors_preset(Control.PRESET_TOP_LEFT)
	table.size = Vector2(1280, 720)
	table.pace_scale = 0.05
	return table


func _make_exposed_game() -> PokerGame:
	var defs: Array = []
	for i in range(4):
		defs.append({"id": i, "name": "P%d" % i, "chips": 0, "human": false})
	var game := PokerGame.new()
	game.setup(defs, 10, 20, 42)
	game.start_hand()
	# start_hand ends immediately (everyone broke); repair into a live
	# all-in spot for seats 0 and 1, with 2 and 3 already folded.
	for p in game.players:
		p.out = false
		p.chips = 0
		p.all_in = true
		p.committed = 100
		p.folded = p.id >= 2
	game.players[0].hole = [Card.new(14, 0), Card.new(13, 0)]
	game.players[1].hole = [Card.new(2, 1), Card.new(7, 2)]
	game.community = [Card.new(5, 0), Card.new(9, 1), Card.new(12, 2)]
	game.street = PokerGame.Street.FLOP
	game.hand_over = false
	return game


func test_exposed_hands_read_revealed() -> void:
	var table := _make_table()
	var game := _make_exposed_game()
	table.set_game(game)
	table._exposed = [0, 1]
	assert_true(table._revealed(game.players[0]))
	assert_true(table._revealed(game.players[1]))
	game.players[1].folded = true
	assert_false(table._revealed(game.players[1]), "folded stays down")


func test_expose_flips_hole_cards_face_up() -> void:
	var table := _make_table()
	var game := _make_exposed_game()
	table.set_game(game)
	table.refresh_all()
	var before: CardView = table._hole_views[0][0]
	assert_false(before.face_up, "AI hole starts face-down")
	await table._expose_hole_cards([0, 1])
	assert_eq(table._exposed, [0, 1])
	for pid in [0, 1]:
		for k in range(2):
			var cv: CardView = table._hole_views[pid][k]
			assert_true(cv.visible)
			assert_true(cv.face_up, "exposed hole %d:%d is face-up" % [pid, k])
	table.refresh_all()
	for pid in [0, 1]:
		for k in range(2):
			assert_true((table._hole_views[pid][k] as CardView).face_up,
				"refresh keeps exposed hands up")


func test_runout_community_arrives_face_up() -> void:
	var table := _make_table()
	var game := _make_exposed_game()
	table.set_game(game)
	table.refresh_all()
	var dealt := [Card.new(4, 3)]
	await table._deal_community(dealt, true, PokerGame.Street.RIVER)
	var cv: CardView = table._community_views[3]
	assert_true(cv.visible)
	assert_true(cv.face_up, "runout river arrives face-up")
