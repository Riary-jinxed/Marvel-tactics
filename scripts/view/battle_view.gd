extends Control
## Écran de combat en placeholder : formes simples dessinées dans _draw(),
## en attendant le pixel art. Toute la logique est dans BattleState.

const BattleState = preload("res://scripts/core/battle_state.gd")
const CardLibrary = preload("res://scripts/core/card_library.gd")
const Card = preload("res://scripts/core/card.gd")

const TILE := 52.0
const GRID_ORIGIN := Vector2(24, 60)
const DETAIL_RECT := Rect2(8, 428, 344, 38)
const HAND_Y := 476.0
const CARD_SIZE := Vector2(64, 96)
const CARD_GAP := 6.0
const REDRAW_RECT := Rect2(8, 588, 112, 44)
const END_TURN_RECT := Rect2(240, 588, 112, 44)
const ENEMY_STEP_DELAY := 0.35

const BG := Color("#1b1d2a")
const INK := Color("#f2efe6")
const MUTED := Color("#9a9fb5")
const TARGET_COLOR := Color("#ffd166")
const MOVE_COLOR := Color("#5ee0c9")
const ICE_COLOR := Color("#9fd3ea")

var library
var state
var font: Font
var selected_card := -1
var selected_hero = null
var inspected = null
var highlights: Array = []
var busy := false
var sprites := {}
var sprite_feet := {}


func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	library = CardLibrary.new()
	_new_battle()


func _new_battle() -> void:
	state = BattleState.new()
	state.setup(library, library.data.mission)
	_clear_selection()
	queue_redraw()


# --- Entrées --------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	if state.phase == BattleState.Phase.WON or state.phase == BattleState.Phase.LOST:
		_new_battle()
		return
	if busy:
		return
	_on_tap(event.position)
	_refresh_highlights()
	queue_redraw()


func _on_tap(pos: Vector2) -> void:
	for i in state.hand.size():
		if _card_rect(i).has_point(pos):
			selected_hero = null
			inspected = null
			selected_card = -1 if selected_card == i else i
			return
	if REDRAW_RECT.has_point(pos):
		if selected_card >= 0 and state.redraw(selected_card):
			selected_card = -1
		return
	if END_TURN_RECT.has_point(pos):
		_end_turn()
		return
	var tile = _tile_at(pos)
	if tile == null:
		_clear_selection()
		return
	if selected_card >= 0 and state.play_card(selected_card, tile):
		selected_card = -1
		return
	if selected_hero != null and state.move_hero(selected_hero, tile):
		selected_hero = null
		return
	var unit = state.unit_at(tile)
	_clear_selection()
	if unit != null and unit.is_hero():
		selected_hero = unit
	else:
		inspected = unit


func _end_turn() -> void:
	busy = true
	_clear_selection()
	for enemy in state.begin_enemy_phase():
		state.enemy_act(enemy)
		queue_redraw()
		await get_tree().create_timer(ENEMY_STEP_DELAY).timeout
	state.finish_enemy_phase()
	busy = false
	queue_redraw()


func _clear_selection() -> void:
	selected_card = -1
	selected_hero = null
	inspected = null
	highlights = []


func _refresh_highlights() -> void:
	if selected_card >= 0:
		highlights = state.valid_targets(selected_card)
	elif selected_hero != null:
		highlights = state.move_targets(selected_hero)
	else:
		highlights = []


# --- Géométrie ------------------------------------------------------------

func _tile_rect(p: Vector2i) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(p) * TILE, Vector2(TILE, TILE))


func _tile_at(pos: Vector2):
	var local := (pos - GRID_ORIGIN) / TILE
	var p := Vector2i(floori(local.x), floori(local.y))
	return p if state.in_bounds(p) else null


func _card_rect(i: int) -> Rect2:
	var r := Rect2(Vector2(8 + i * (CARD_SIZE.x + CARD_GAP), HAND_Y), CARD_SIZE)
	if i == selected_card:
		r.position.y -= 10
	return r


# --- Dessin ---------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	_draw_header()
	_draw_grid()
	_draw_units()
	_draw_detail()
	_draw_hand()
	_draw_buttons()
	_draw_end_overlay()


func _draw_header() -> void:
	var header := "Tour %d   Héroïsme %d   Cartes %d/%d" % [state.turn, state.heroism, state.plays_left, BattleState.PLAYS_PER_TURN]
	draw_string(font, Vector2(8, 18), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
	var recent: Array = state.events.slice(-2)
	for i in recent.size():
		draw_string(font, Vector2(8, 36 + i * 14), recent[i], HORIZONTAL_ALIGNMENT_LEFT, 344, 11, MUTED)


func _draw_grid() -> void:
	var hl_color := TARGET_COLOR if selected_card >= 0 else MOVE_COLOR
	for y in BattleState.HEIGHT:
		for x in BattleState.WIDTH:
			var p := Vector2i(x, y)
			var r := _tile_rect(p).grow(-1)
			var c := Color("#2c3040") if (x + y) % 2 == 0 else Color("#333749")
			if state.ice.has(p):
				c = ICE_COLOR.darkened(0.35)
			draw_rect(r, c)
			if highlights.has(p):
				draw_rect(r, Color(hl_color, 0.3))
				draw_rect(r, hl_color, false, 2)
			if state.crates.has(p):
				var cr := r.grow(-9)
				draw_rect(cr, Color("#8b5a2b"))
				draw_line(cr.position, cr.end, Color("#5c3b1c"), 2)
				draw_line(Vector2(cr.end.x, cr.position.y), Vector2(cr.position.x, cr.end.y), Color("#5c3b1c"), 2)
			if state.barrels.has(p):
				draw_circle(r.get_center(), 13, Color("#c0392b"))
				_centered("!", r.get_center() + Vector2(0, 6), 16, INK)


func _draw_units() -> void:
	var alive: Array = state.units.filter(func(u): return u.is_alive())
	# Les unités du bas passent devant : un sprite plus haut qu'une case déborde sur celle du dessus.
	alive.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	for u in alive:
		_draw_unit_body(u)
	for u in alive:
		_draw_unit_overlay(u)


func _draw_unit_body(u) -> void:
	var r := _tile_rect(u.pos)
	var feet := Vector2(r.get_center().x, r.end.y - 6)
	var tex: Texture2D = _sprite(u)
	if tex != null:
		var ring := INK if u == selected_hero else Color(0, 0, 0, 0.35)
		draw_set_transform(feet, 0, Vector2(1, 0.35))
		draw_circle(Vector2.ZERO, 17, ring)
		draw_set_transform(Vector2.ZERO)
		var offset: Vector2 = sprite_feet[u.id]
		var tint := Color(1, 1, 1, 0.35) if u.burrowed else Color.WHITE
		draw_texture(tex, (feet - offset).round(), tint)
		return
	var center := r.get_center() - Vector2(0, 3)
	var col: Color = u.color
	if u.burrowed:
		col.a = 0.35
	if u.is_hero():
		draw_circle(center, 17, col)
	else:
		draw_rect(Rect2(center - Vector2(16, 16), Vector2(32, 32)), col)
	if u == selected_hero or u == inspected:
		draw_arc(center, 22, 0, TAU, 32, INK, 2)
	_centered(u.short, center + Vector2(0, 6), 17, INK)


func _draw_unit_overlay(u) -> void:
	var r := _tile_rect(u.pos)
	var hp_text := "%d" % u.hp
	if u.shield > 0:
		hp_text += " +%d" % u.shield
	if _sprite(u) != null:
		var w := font.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 6
		var badge := Rect2(r.end.x - w - 1, r.end.y - 13, w, 12)
		draw_rect(badge, Color(0, 0, 0, 0.6))
		_centered(hp_text, Vector2(badge.get_center().x, badge.end.y - 2), 10, INK)
	else:
		_centered(hp_text, Vector2(r.get_center().x, r.end.y - 1), 10, INK)
	for i in u.frost:
		draw_circle(r.position + Vector2(6 + i * 6, 6), 2.5, ICE_COLOR)
	if u.frozen:
		draw_rect(r.grow(-3), ICE_COLOR, false, 2)
	if u.is_hero() and u.has_moved:
		draw_circle(r.position + Vector2(6, r.size.y - 7), 3, MUTED)
	if not u.is_hero() and u.intent_target != null and u.intent_target.is_alive():
		var intent := "%s %d" % [u.intent_target.short, u.attack_damage] if not u.frozen else "gelé"
		_centered(intent, Vector2(r.get_center().x, r.position.y + 10), 10, TARGET_COLOR)


## Texture du héros si un sprite est défini, sinon null (forme placeholder).
func _sprite(u) -> Texture2D:
	if u.sprite_path == "":
		return null
	if not sprites.has(u.id):
		var tex: Texture2D = load(u.sprite_path)
		sprites[u.id] = tex
		# Ancre aux pieds : bas des pixels opaques, centré horizontalement.
		var used := tex.get_image().get_used_rect()
		sprite_feet[u.id] = Vector2(tex.get_width() / 2.0, used.end.y)
	return sprites[u.id]


func _draw_detail() -> void:
	var text := "Touche une carte puis sa cible, ou un héros pour le déplacer."
	if selected_card >= 0:
		var card = state.hand[selected_card]
		text = "%s (%s) : %s" % [card.name, state.card_owner(card).name, card.text]
		if not state.can_play(selected_card):
			text += " Injouable maintenant."
		elif state.valid_targets(selected_card).is_empty():
			text += " Aucune cible à portée."
	elif selected_hero != null:
		if selected_hero.has_moved:
			text = "%s s'est déjà déplacé ce tour." % selected_hero.name
		else:
			text = "%s : touche une case en surbrillance pour se déplacer." % selected_hero.name
	elif inspected != null:
		var target_name: String = inspected.intent_target.name if inspected.intent_target != null else "personne"
		text = "%s : %d PV, %d dégâts à portée %d. Vise %s." % [inspected.name, inspected.hp, inspected.attack_damage, inspected.attack_range, target_name]
	draw_multiline_string(font, DETAIL_RECT.position + Vector2(0, 13), text, HORIZONTAL_ALIGNMENT_LEFT, DETAIL_RECT.size.x, 12, 3, INK)


func _draw_hand() -> void:
	for i in state.hand.size():
		var card = state.hand[i]
		var owner = state.card_owner(card)
		var r := _card_rect(i)
		var playable: bool = state.can_play(i)
		draw_rect(r, Color("#ece6d6") if playable else Color("#7d7a70"))
		var band := Rect2(r.position, Vector2(r.size.x, 16))
		draw_rect(band, _type_color(card.type))
		_centered(_type_label(card), band.get_center() + Vector2(0, 4), 10, INK)
		draw_multiline_string(font, r.position + Vector2(3, 32), card.name, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 6, 11, 4, BG)
		var foot := Rect2(r.position + Vector2(0, r.size.y - 16), Vector2(r.size.x, 16))
		draw_rect(foot, owner.color)
		_centered(owner.name, foot.get_center() + Vector2(0, 4), 10, BG)
		if i == selected_card:
			draw_rect(r, INK, false, 2)
	draw_string(font, Vector2(8, HAND_Y + CARD_SIZE.y + 12), "Pioche %d · Défausse %d" % [state.draw_pile.size(), state.discard_pile.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, MUTED)


func _draw_buttons() -> void:
	var can_redraw: bool = selected_card >= 0 and state.redraws_left > 0
	_button(REDRAW_RECT, "Repiocher (%d)" % state.redraws_left, can_redraw)
	_button(END_TURN_RECT, "Fin de tour", not busy and state.phase == BattleState.Phase.PLAYER)


func _draw_end_overlay() -> void:
	if state.phase != BattleState.Phase.WON and state.phase != BattleState.Phase.LOST:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7))
	var title := "Victoire !" if state.phase == BattleState.Phase.WON else "Défaite"
	_centered(title, Vector2(180, 300), 32, INK)
	_centered("Touche l'écran pour rejouer", Vector2(180, 336), 13, MUTED)


func _button(r: Rect2, label: String, enabled: bool) -> void:
	draw_rect(r, Color("#3d4a7a") if enabled else Color("#2a2e3d"))
	draw_rect(r, INK if enabled else MUTED, false, 1)
	_centered(label, r.get_center() + Vector2(0, 5), 13, INK if enabled else MUTED)


func _centered(text: String, baseline_center: Vector2, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(baseline_center.x - w / 2, baseline_center.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _type_color(type: int) -> Color:
	match type:
		Card.Type.ATTACK:
			return Color("#c0392b")
		Card.Type.SKILL:
			return Color("#2e86c1")
	return Color("#c9a227")


func _type_label(card) -> String:
	match card.type:
		Card.Type.ATTACK:
			return "ATTAQUE"
		Card.Type.SKILL:
			return "COMPÉT."
	return "HÉROÏQUE %d" % card.cost
