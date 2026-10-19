extends Control
## Écran de combat dessiné dans _draw() : sprites quand ils existent, formes
## simples sinon. Toute la logique est dans BattleState ; cette vue anime les
## événements visuels (state.fx) qu'elle produit.

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
const ENEMY_STEP_DELAY := 0.45
const DRAG_THRESHOLD := 12.0
const DAMAGE_COLOR := Color("#ff5a5a")
const HEAL_COLOR := Color("#6ee07a")
const ZONE_COLOR := Color("#ff4d4d")

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

# Animation
var display_pos := {}
var flash := {}
var floaters: Array = []
var bursts: Array = []
var tile_flashes: Array = []
var screen_tint := Color(0, 0, 0, 0)
var shake := 0.0

# Glisser une carte
var drag_card := -1
var drag_pos := Vector2.ZERO
var press_pos := Vector2.ZERO
var dragging := false
var was_selected := false


func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	library = CardLibrary.new()
	_new_battle()


func _new_battle() -> void:
	state = BattleState.new()
	state.setup(library, library.data.mission)
	display_pos.clear()
	state.fx.clear()
	_clear_selection()
	queue_redraw()


# --- Entrées --------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if drag_card >= 0:
			drag_pos = event.position
			dragging = dragging or drag_pos.distance_to(press_pos) > DRAG_THRESHOLD
			queue_redraw()
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	if event.pressed:
		_on_press(event.position)
	else:
		_on_release(event.position)
	_consume_fx()
	_refresh_highlights()
	queue_redraw()


func _on_press(pos: Vector2) -> void:
	if state.phase == BattleState.Phase.WON or state.phase == BattleState.Phase.LOST:
		_new_battle()
		return
	if busy:
		return
	for i in state.hand.size():
		if _card_rect(i).has_point(pos):
			was_selected = selected_card == i
			selected_card = i
			selected_hero = null
			inspected = null
			drag_card = i
			press_pos = pos
			drag_pos = pos
			dragging = false
			return
	_on_tap(pos)


## Relâcher une carte glissée sur une cible la joue ; un simple toucher la
## sélectionne ou la désélectionne.
func _on_release(pos: Vector2) -> void:
	if drag_card < 0:
		return
	if dragging:
		var tile = _tile_at(pos)
		if tile != null and state.play_card(drag_card, tile):
			selected_card = -1
	elif was_selected:
		selected_card = -1
	drag_card = -1
	dragging = false


func _on_tap(pos: Vector2) -> void:
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
		if _consume_fx():
			await get_tree().create_timer(ENEMY_STEP_DELAY).timeout
	state.finish_enemy_phase()
	_consume_fx()
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


# --- Animation ------------------------------------------------------------

func _process(delta: float) -> void:
	var active := false
	for u in state.units:
		if not u.is_alive():
			continue
		var target := _tile_rect(u.pos).position
		var current: Vector2 = display_pos.get(u, target)
		if current.distance_to(target) > 0.5:
			current = current.lerp(target, 1.0 - exp(-delta * 14.0))
			active = true
		else:
			current = target
		display_pos[u] = current
	for u in flash.keys():
		flash[u] -= delta
		if flash[u] <= 0:
			flash.erase(u)
	for list in [floaters, bursts, tile_flashes]:
		for f in list:
			f.age += delta
	floaters = floaters.filter(func(f): return f.age < 0.9)
	bursts = bursts.filter(func(b): return b.age < b.dur)
	tile_flashes = tile_flashes.filter(func(t): return t.age < 0.5)
	screen_tint.a = move_toward(screen_tint.a, 0.0, delta * 1.5)
	if shake > 0:
		shake = maxf(0.0, shake - delta * 30.0)
		position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	elif position != Vector2.ZERO:
		position = Vector2.ZERO
	active = active or not flash.is_empty() or not floaters.is_empty() or not bursts.is_empty()
	active = active or not tile_flashes.is_empty() or screen_tint.a > 0 or shake > 0
	if active:
		queue_redraw()


## Transforme les événements du combat en effets à l'écran. Renvoie true s'il y en avait.
func _consume_fx() -> bool:
	var had: bool = not state.fx.is_empty()
	for e in state.fx:
		match e.type:
			"damage":
				if e.amount > 0:
					_float("-%d" % e.amount, e.unit, DAMAGE_COLOR)
					flash[e.unit] = 0.2
					shake = maxf(shake, minf(2.0 + e.amount, 7.0))
				elif e.blocked > 0:
					_float("bloqué", e.unit, MUTED)
			"heal":
				_float("+%d" % e.amount, e.unit, HEAL_COLOR)
			"ko":
				_burst(_unit_center(e.unit), INK, 26.0, 0.35)
				_float("KO", e.unit, INK)
			"explode":
				var big: bool = e.get("big", false)
				_burst(_tile_rect(e.pos).get_center(), Color("#ff9f43"), 90.0 if big else 46.0, 0.5)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						tile_flashes.append({"tile": e.pos + Vector2i(dx, dy), "age": 0.0, "color": Color("#ff9f43")})
				shake = maxf(shake, 12.0 if big else 8.0)
			"barrage":
				for p in e.tiles:
					tile_flashes.append({"tile": p, "age": 0.0, "color": ZONE_COLOR})
				shake = maxf(shake, 4.0)
			"teleport":
				_burst(_tile_rect(e.from).get_center(), e.unit.color, 30.0, 0.35)
				_burst(_tile_rect(e.unit.pos).get_center(), e.unit.color, 30.0, 0.35)
				display_pos[e.unit] = _tile_rect(e.unit.pos).position
			"heroic":
				screen_tint = Color(e.unit.color, 0.45)
				shake = maxf(shake, 6.0)
			"bump":
				var r: Rect2 = _tile_rect(e.unit.pos)
				_burst(r.get_center().lerp(_tile_rect(e.pos).get_center(), 0.5), INK, 16.0, 0.25)
			"spawn":
				display_pos[e.unit] = _tile_rect(e.unit.pos).position - Vector2(0, 40)
				_burst(_tile_rect(e.unit.pos).get_center(), e.unit.color, 30.0, 0.4)
	state.fx.clear()
	if had:
		queue_redraw()
	return had


func _float(text: String, unit, color: Color) -> void:
	floaters.append({"text": text, "pos": _unit_center(unit) - Vector2(0, 14), "age": 0.0, "color": color})


func _burst(pos: Vector2, color: Color, radius: float, duration: float) -> void:
	bursts.append({"pos": pos, "color": color, "radius": radius, "age": 0.0, "dur": duration})


# --- Géométrie ------------------------------------------------------------

func _tile_rect(p: Vector2i) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(p) * TILE, Vector2(TILE, TILE))


func _tile_at(pos: Vector2):
	var local := (pos - GRID_ORIGIN) / TILE
	var p := Vector2i(floori(local.x), floori(local.y))
	return p if state.in_bounds(p) else null


## Case où l'unité est affichée (suit sa position logique avec un léger retard animé).
func _unit_rect(u) -> Rect2:
	return Rect2(display_pos.get(u, _tile_rect(u.pos).position), Vector2(TILE, TILE))


func _unit_center(u) -> Vector2:
	return _unit_rect(u).get_center()


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
	_draw_effects()
	_draw_detail()
	_draw_hand()
	_draw_buttons()
	_draw_dragged_card()
	if screen_tint.a > 0:
		draw_rect(Rect2(Vector2.ZERO, size), screen_tint)
	_draw_end_overlay()


func _draw_header() -> void:
	var header := "Tour %d   Héroïsme %d   Cartes %d/%d" % [state.turn, state.heroism, state.plays_left, BattleState.PLAYS_PER_TURN]
	draw_string(font, Vector2(8, 18), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
	if state.bomb_turns > 0:
		var left: int = state.bomb_turns_left()
		var objective := "Détruis la bombe : %d tour%s restant%s" % [left, "s" if left > 1 else "", "s" if left > 1 else ""]
		draw_string(font, Vector2(8, 35), objective, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ZONE_COLOR if left <= 2 else TARGET_COLOR)
	if not state.events.is_empty():
		draw_string(font, Vector2(8, 51), state.events[-1], HORIZONTAL_ALIGNMENT_LEFT, 344, 11, MUTED)


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
	# Tirs de zone annoncés : sortir des cases rouges pour esquiver.
	for e in state.enemies():
		if e.frozen:
			continue
		for p in e.intent_tiles:
			var r := _tile_rect(p).grow(-1)
			draw_rect(r, Color(ZONE_COLOR, 0.22))
			draw_rect(r, Color(ZONE_COLOR, 0.8), false, 1.5)
			draw_string(font, r.position + Vector2(3, 12), "%d" % e.attack_damage, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ZONE_COLOR)
	for p in state.planned_spawns:
		var c := _tile_rect(p).get_center()
		draw_arc(c, 18, 0, TAU, 24, Color("#7bd389"), 1.5)
		_centered("renfort", c + Vector2(0, 4), 9, Color("#7bd389"))
	if dragging:
		var under = _tile_at(drag_pos)
		if under != null and highlights.has(under):
			draw_rect(_tile_rect(under).grow(-2), INK, false, 3)


func _draw_units() -> void:
	var alive: Array = state.units.filter(func(u): return u.is_alive())
	# Les unités du bas passent devant : un sprite plus haut qu'une case déborde sur celle du dessus.
	alive.sort_custom(func(a, b): return _unit_rect(a).position.y < _unit_rect(b).position.y)
	for u in alive:
		_draw_unit_body(u)
	for u in alive:
		_draw_unit_overlay(u)


func _draw_unit_body(u) -> void:
	var r := _unit_rect(u)
	var hit: bool = flash.has(u)
	var feet := Vector2(r.get_center().x, r.end.y - 6)
	var tex: Texture2D = _sprite(u)
	if tex != null:
		var ring := INK if u == selected_hero else Color(0, 0, 0, 0.35)
		draw_set_transform(feet, 0, Vector2(1, 0.35))
		draw_circle(Vector2.ZERO, 17, ring)
		draw_set_transform(Vector2.ZERO)
		var offset: Vector2 = sprite_feet[u.id]
		var tint := Color(1, 1, 1, 0.35) if u.burrowed else Color.WHITE
		if hit:
			tint = Color(1, 0.3, 0.3)
		draw_texture(tex, (feet - offset).round(), tint)
		return
	var center := r.get_center() - Vector2(0, 3)
	var col: Color = u.color
	if u.burrowed:
		col.a = 0.35
	if hit:
		col = col.lerp(Color.WHITE, 0.7)
	var label: String = u.short
	if u.kind == "device":
		draw_rect(Rect2(center - Vector2(18, 18), Vector2(36, 36)), col)
		draw_rect(Rect2(center - Vector2(18, 18), Vector2(36, 36)), ZONE_COLOR, false, 2)
		label = "%d" % state.bomb_turns_left() if state.bomb_turns > 0 else u.short
	elif u.is_hero():
		draw_circle(center, 17, col)
	else:
		draw_rect(Rect2(center - Vector2(16, 16), Vector2(32, 32)), col)
	if u == selected_hero or u == inspected:
		draw_arc(center, 22, 0, TAU, 32, INK, 2)
	_centered(label, center + Vector2(0, 6), 17, INK)


func _draw_unit_overlay(u) -> void:
	var r := _unit_rect(u)
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
	var intent := ""
	if u.frozen:
		intent = "gelé"
	elif u.attack == "barrage" and not u.intent_tiles.is_empty():
		intent = "zone %d" % u.attack_damage
	elif u.kind == "device":
		intent = "BOMBE"
	elif not u.is_hero() and u.intent_target != null and u.intent_target.is_alive():
		intent = "%s %d" % [u.intent_target.short, u.attack_damage]
	if intent != "":
		_centered(intent, Vector2(r.get_center().x, r.position.y + 10), 10, ZONE_COLOR if u.kind == "device" else TARGET_COLOR)


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


func _draw_effects() -> void:
	for t in tile_flashes:
		var a: float = 1.0 - t.age / 0.5
		if state.in_bounds(t.tile):
			draw_rect(_tile_rect(t.tile).grow(-1), Color(t.color, 0.55 * a))
	for b in bursts:
		var k: float = b.age / b.dur
		draw_arc(b.pos, b.radius * (0.3 + 0.7 * k), 0, TAU, 32, Color(b.color, 1.0 - k), 4.0 * (1.0 - k) + 1.0)
	for f in floaters:
		var k: float = f.age / 0.9
		var p: Vector2 = f.pos - Vector2(0, 26 * k)
		_centered(f.text, p + Vector2(1, 1), 15, Color(0, 0, 0, 1.0 - k))
		_centered(f.text, p, 15, Color(f.color, 1.0 - k))


func _draw_dragged_card() -> void:
	if not dragging or drag_card < 0 or drag_card >= state.hand.size():
		return
	var r := Rect2(drag_pos - CARD_SIZE / 2 - Vector2(0, 40), CARD_SIZE)
	_draw_card(state.hand[drag_card], r, drag_card)
	draw_rect(r, INK, false, 2)


func _draw_detail() -> void:
	var text := "Glisse une carte sur sa cible, ou touche un héros pour le déplacer. Touche un ennemi pour voir son attaque."
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
		if inspected.kind == "device":
			text = "%s : %d PV. Explose dans %d tour(s) : détruis-la pour gagner. Elle ne peut pas être repoussée." % [inspected.name, inspected.hp, state.bomb_turns_left()]
		elif inspected.attack == "barrage":
			text = "%s : %d PV. Tir de zone de %d dégâts sur les cases rouges, ennemis compris. Sors de la zone pour esquiver." % [inspected.name, inspected.hp, inspected.attack_damage]
		else:
			var target_name: String = inspected.intent_target.name if inspected.intent_target != null else "personne"
			text = "%s : %d PV, %d dégâts au contact. Vise %s." % [inspected.name, inspected.hp, inspected.attack_damage, target_name]
			if inspected.attack_push > 0:
				text += " Repousse d'une case."
	draw_multiline_string(font, DETAIL_RECT.position + Vector2(0, 13), text, HORIZONTAL_ALIGNMENT_LEFT, DETAIL_RECT.size.x, 12, 3, INK)


func _draw_hand() -> void:
	for i in state.hand.size():
		if dragging and i == drag_card:
			draw_rect(_card_rect(i), Color(INK, 0.15))
			continue
		_draw_card(state.hand[i], _card_rect(i), i)
		if i == selected_card:
			draw_rect(_card_rect(i), INK, false, 2)
	draw_string(font, Vector2(8, HAND_Y + CARD_SIZE.y + 12), "Pioche %d · Défausse %d" % [state.draw_pile.size(), state.discard_pile.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, MUTED)


func _draw_card(card, r: Rect2, index: int) -> void:
	var owner = state.card_owner(card)
	var playable: bool = state.can_play(index)
	draw_rect(r, Color("#ece6d6") if playable else Color("#7d7a70"))
	var band := Rect2(r.position, Vector2(r.size.x, 16))
	draw_rect(band, _type_color(card.type))
	_centered(_type_label(card), band.get_center() + Vector2(0, 4), 10, INK)
	var name_size := 11 if card.name.length() <= 9 else 10
	draw_multiline_string(font, r.position + Vector2(3, 32), card.name, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 6, name_size, 4, BG)
	var foot := Rect2(r.position + Vector2(0, r.size.y - 16), Vector2(r.size.x, 16))
	draw_rect(foot, owner.color)
	_centered(owner.name, foot.get_center() + Vector2(0, 4), 10, BG)


func _draw_buttons() -> void:
	var can_redraw: bool = selected_card >= 0 and state.redraws_left > 0
	_button(REDRAW_RECT, "Repiocher (%d)" % state.redraws_left, can_redraw)
	_button(END_TURN_RECT, "Fin de tour", not busy and state.phase == BattleState.Phase.PLAYER)


func _draw_end_overlay() -> void:
	if state.phase != BattleState.Phase.WON and state.phase != BattleState.Phase.LOST:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7))
	var title := "Victoire !" if state.phase == BattleState.Phase.WON else "Défaite"
	var reason := ""
	if state.bomb_turns > 0:
		reason = "Bombe détruite" if state.phase == BattleState.Phase.WON else "La bombe a explosé"
		if state.phase == BattleState.Phase.LOST and state.heroes().is_empty():
			reason = "Toute l'équipe est KO"
	_centered(title, Vector2(180, 290), 32, INK)
	_centered(reason, Vector2(180, 316), 14, TARGET_COLOR)
	_centered("Touche l'écran pour rejouer", Vector2(180, 344), 13, MUTED)


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
