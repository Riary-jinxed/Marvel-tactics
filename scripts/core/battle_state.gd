extends RefCounted
## État d'un combat, indépendant de l'affichage pour pouvoir le tester en headless.

const Unit = preload("res://scripts/core/unit.gd")
const Card = preload("res://scripts/core/card.gd")

const WIDTH := 6
const HEIGHT := 7
const HAND_SIZE := 5
const PLAYS_PER_TURN := 3
const REDRAWS_PER_TURN := 2
const FROST_TO_FREEZE := 3
const COLLISION_DAMAGE := 2
const BARREL_DAMAGE := 3
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

enum Phase { PLAYER, ENEMY, WON, LOST }

var units: Array = []
var crates := {}
var barrels := {}
var ice := {}
var draw_pile: Array = []
var discard_pile: Array = []
var hand: Array = []
var heroism := 0
var plays_left := 0
var redraws_left := 0
var turn := 0
var phase := Phase.PLAYER
var events: Array[String] = []
## Événements visuels (dégâts, KO, explosions...) que l'affichage consomme pour animer.
var fx: Array = []
var rng := RandomNumberGenerator.new()

# Objectif et renforts de la mission
var bomb_turns := 0
var spawn_tiles: Array[Vector2i] = []
var spawn_enemy_id := ""
var spawns_per_turn := 0
var max_enemies := 8
var planned_spawns: Array[Vector2i] = []
var _library
var _spawned := 0


func setup(library, mission: Dictionary, rng_seed: int = -1) -> void:
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	for entry in mission.heroes:
		var hero = library.make_hero(entry.id)
		hero.pos = _vec(entry.pos)
		units.append(hero)
		draw_pile.append_array(library.make_deck(entry.id))
	var count := 0
	for entry in mission.enemies:
		count += 1
		var enemy = library.make_enemy(entry.id, count)
		enemy.pos = _vec(entry.pos)
		units.append(enemy)
	for p in mission.get("crates", []):
		crates[_vec(p)] = true
	for p in mission.get("barrels", []):
		barrels[_vec(p)] = true
	_library = library
	_spawned = count
	bomb_turns = int(mission.get("bomb_turns", 0))
	var reinforcements: Dictionary = mission.get("reinforcements", {})
	if not reinforcements.is_empty():
		spawn_enemy_id = reinforcements.id
		spawns_per_turn = int(reinforcements.per_turn)
		max_enemies = int(reinforcements.get("max_enemies", 8))
		for p in reinforcements.tiles:
			spawn_tiles.append(_vec(p))
	_shuffle(draw_pile)
	start_player_turn()


# --- Requêtes -------------------------------------------------------------

func heroes() -> Array:
	return units.filter(func(u): return u.is_alive() and u.is_hero())


func enemies() -> Array:
	return units.filter(func(u): return u.is_alive() and not u.is_hero())


func bomb():
	for u in units:
		if u.kind == "device":
			return u
	return null


## Tours restants avant l'explosion de la bombe (0 si la mission n'en a pas).
func bomb_turns_left() -> int:
	return bomb_turns - turn + 1 if bomb_turns > 0 else 0


func hero_by_id(hero_id: String):
	for u in units:
		if u.id == hero_id:
			return u
	return null


func card_owner(card):
	return hero_by_id(card.hero_id)


func unit_at(p: Vector2i):
	for u in units:
		if u.is_alive() and u.pos == p:
			return u
	return null


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < WIDTH and p.y < HEIGHT


func is_blocked(p: Vector2i) -> bool:
	return not in_bounds(p) or crates.has(p) or barrels.has(p) or unit_at(p) != null


static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Cases atteignables en marchant, avec le nombre de pas (la case de départ comprise).
func reachable(start: Vector2i, max_steps: int) -> Dictionary:
	var steps := {start: 0}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var p: Vector2i = frontier.pop_front()
		if steps[p] >= max_steps:
			continue
		for d in DIRECTIONS:
			var n := p + d
			if steps.has(n) or is_blocked(n):
				continue
			steps[n] = steps[p] + 1
			frontier.append(n)
	return steps


# --- Tour du joueur -------------------------------------------------------

func start_player_turn() -> void:
	turn += 1
	phase = Phase.PLAYER
	plays_left = PLAYS_PER_TURN
	redraws_left = REDRAWS_PER_TURN
	for hero in heroes():
		hero.has_moved = false
		hero.burrowed = false
	while hand.size() < HAND_SIZE and _draw_card():
		pass
	_plan_enemy_intents()
	_plan_spawns()
	_event("Tour %d" % turn)


func can_play(index: int) -> bool:
	if phase != Phase.PLAYER or plays_left <= 0 or index < 0 or index >= hand.size():
		return false
	var card = hand[index]
	var user = card_owner(card)
	if not _alive(user):
		return false
	return card.type != Card.Type.HEROIC or heroism >= card.cost


func valid_targets(index: int) -> Array:
	if not can_play(index):
		return []
	var card = hand[index]
	var user = card_owner(card)
	var out := []
	match card.target:
		"self":
			out.append(user.pos)
		"enemy":
			for e in enemies():
				if distance(user.pos, e.pos) <= card.reach:
					out.append(e.pos)
		"ally":
			for h in heroes():
				if distance(user.pos, h.pos) <= card.reach:
					out.append(h.pos)
		"tile", "tile_empty":
			for y in HEIGHT:
				for x in WIDTH:
					var p := Vector2i(x, y)
					if distance(user.pos, p) > card.reach:
						continue
					if card.target == "tile_empty" and is_blocked(p):
						continue
					out.append(p)
	return out


func play_card(index: int, target: Vector2i) -> bool:
	if not valid_targets(index).has(target):
		return false
	var card = hand[index]
	var user = card_owner(card)
	hand.remove_at(index)
	plays_left -= 1
	if card.type == Card.Type.HEROIC:
		heroism -= card.cost
		fx.append({"type": "heroic", "unit": user})
	else:
		heroism += 1
	_event("%s : %s" % [user.name, card.name])
	var target_unit = unit_at(target)
	for effect in card.effects:
		_apply_effect(effect, user, target_unit, target)
	if user.is_alive():
		discard_pile.append(card)
	_check_end()
	return true


## Défausse une carte de la main et la remplace (2 fois par tour).
func redraw(index: int) -> bool:
	if phase != Phase.PLAYER or redraws_left <= 0 or index < 0 or index >= hand.size():
		return false
	discard_pile.append(hand[index])
	hand.remove_at(index)
	redraws_left -= 1
	_draw_card(index)
	return true


func move_targets(hero) -> Array:
	if phase != Phase.PLAYER or not _alive(hero) or not hero.is_hero() or hero.has_moved:
		return []
	var tiles := reachable(hero.pos, hero.move_range).keys()
	tiles.erase(hero.pos)
	return tiles


func move_hero(hero, tile: Vector2i) -> bool:
	if not move_targets(hero).has(tile):
		return false
	hero.pos = tile
	hero.has_moved = true
	return true


# --- Tour ennemi ----------------------------------------------------------

## Passe en phase ennemie et renvoie les ennemis à faire agir dans l'ordre.
func begin_enemy_phase() -> Array:
	if phase != Phase.PLAYER:
		return []
	phase = Phase.ENEMY
	return enemies()


func enemy_act(enemy) -> void:
	if phase != Phase.ENEMY or not _alive(enemy) or enemy.attack == "none":
		return
	if enemy.frozen:
		enemy.frozen = false
		_event("%s est gelé et passe son tour" % enemy.name)
		return
	if enemy.attack == "barrage":
		_barrage(enemy)
	else:
		_melee(enemy)
	_check_end()


func _melee(enemy) -> void:
	var target = enemy.intent_target
	if not _alive(target):
		target = _nearest_hero(enemy.pos)
	if target == null:
		return
	if distance(enemy.pos, target.pos) > enemy.attack_range:
		enemy.pos = _approach(enemy, target)
	if distance(enemy.pos, target.pos) <= enemy.attack_range:
		_event("%s attaque %s" % [enemy.name, target.name])
		_damage(target, enemy.attack_damage)
		if enemy.attack_push > 0 and _alive(target):
			_push(enemy.pos, target, enemy.attack_push)


## Tir de zone : touche tout ce qui se trouve encore sur les cases annoncées,
## alliés de l'ennemi compris.
func _barrage(enemy) -> void:
	if enemy.intent_tiles.is_empty():
		return
	_event("%s : tir de barrage" % enemy.name)
	fx.append({"type": "barrage", "tiles": enemy.intent_tiles.duplicate()})
	for p in enemy.intent_tiles:
		var hit = unit_at(p)
		if hit != null and hit != enemy:
			_damage(hit, enemy.attack_damage)
	enemy.intent_tiles.clear()


func finish_enemy_phase() -> void:
	if phase != Phase.ENEMY:
		return
	if bomb_turns > 0 and _alive(bomb()) and bomb_turns_left() <= 1:
		phase = Phase.LOST
		fx.append({"type": "explode", "pos": bomb().pos, "big": true})
		_event("La bombe explose... Défaite")
		return
	_spawn_reinforcements()
	start_player_turn()


## Tour ennemi complet, sans pause entre les actions (utilisé par les tests).
func end_turn() -> void:
	for enemy in begin_enemy_phase():
		enemy_act(enemy)
	finish_enemy_phase()


# --- Effets ---------------------------------------------------------------

func _apply_effect(effect: Dictionary, user, target_unit, tile: Vector2i) -> void:
	var amount := int(effect.get("amount", 0))
	match effect.type:
		"damage":
			if _alive(target_unit):
				_damage(target_unit, amount)
		"knockback":
			if _alive(target_unit):
				_push(user.pos, target_unit, amount)
		"frost":
			if _alive(target_unit):
				_add_frost(target_unit, amount)
		"heal":
			if _alive(target_unit):
				_heal(target_unit, amount)
		"shield":
			if _alive(target_unit):
				target_unit.shield += amount
				_event("%s gagne %d de bouclier" % [target_unit.name, amount])
		"teleport_self":
			fx.append({"type": "teleport", "unit": user, "from": user.pos})
			user.pos = tile
		"burrow":
			user.burrowed = true
			_event("%s plonge sous terre" % user.name)
		"ice_area":
			for p in [tile, tile + Vector2i.UP, tile + Vector2i.DOWN, tile + Vector2i.LEFT, tile + Vector2i.RIGHT]:
				if in_bounds(p) and not crates.has(p) and not barrels.has(p):
					ice[p] = true
		"swallow":
			if not _alive(target_unit):
				return
			if target_unit.kind == "minion":
				target_unit.hp = 0
				fx.append({"type": "ko", "unit": target_unit})
				_event("%s avale %s" % [user.name, target_unit.name])
			else:
				_damage(target_unit, amount)
				_push(user.pos, target_unit, int(effect.get("distance", 2)))
		"area_damage":
			for e in enemies():
				if _chebyshev(user.pos, e.pos) <= 1:
					_damage(e, amount)
		"heal_allies":
			for h in heroes():
				_heal(h, amount)
		"frost_all":
			for e in enemies():
				_add_frost(e, amount)
		"taunt":
			for e in enemies():
				e.intent_target = user
			_event("Tous les ennemis ciblent %s" % user.name)
		"draw":
			for i in amount:
				_draw_card()


func _damage(unit, amount: int) -> void:
	if unit.burrowed:
		_event("%s est sous terre, aucun dégât" % unit.name)
		return
	var lost: int = unit.take_damage(amount)
	fx.append({"type": "damage", "unit": unit, "amount": lost, "blocked": amount - lost})
	_event("%s perd %d PV" % [unit.name, lost])
	if not unit.is_alive():
		_on_ko(unit)


func _heal(unit, amount: int) -> void:
	var gained: int = unit.heal(amount)
	if gained > 0:
		fx.append({"type": "heal", "unit": unit, "amount": gained})
		_event("%s récupère %d PV" % [unit.name, gained])


func _add_frost(unit, stacks: int) -> void:
	unit.frost += stacks
	if unit.frost >= FROST_TO_FREEZE:
		unit.frost = 0
		unit.frozen = true
		_event("%s est gelé" % unit.name)


## Repousse la cible dans l'axe source -> cible. Sur la glace, elle glisse
## jusqu'au prochain obstacle. Heurter un obstacle inflige des dégâts.
func _push(source: Vector2i, unit, distance_left: int) -> void:
	if unit.immovable or unit.burrowed:
		return
	var dir := _direction(source, unit.pos)
	var moved := false
	while distance_left > 0 or (moved and ice.has(unit.pos)):
		var next: Vector2i = unit.pos + dir
		if is_blocked(next):
			_collide(unit, next)
			return
		unit.pos = next
		moved = true
		distance_left = maxi(0, distance_left - 1)


func _collide(unit, obstacle: Vector2i) -> void:
	var other = unit_at(obstacle)
	fx.append({"type": "bump", "unit": unit, "pos": obstacle})
	_event("%s percute un obstacle" % unit.name)
	_damage(unit, COLLISION_DAMAGE)
	if other != null:
		_damage(other, 1)
	elif barrels.has(obstacle):
		_explode(obstacle)


func _explode(barrel: Vector2i) -> void:
	barrels.erase(barrel)
	fx.append({"type": "explode", "pos": barrel})
	_event("Le baril explose !")
	for u in units:
		if u.is_alive() and _chebyshev(u.pos, barrel) <= 1:
			_damage(u, BARREL_DAMAGE)


func _on_ko(unit) -> void:
	fx.append({"type": "ko", "unit": unit})
	_event("%s est KO" % unit.name)
	if unit.is_hero():
		var keep := func(card): return card.hero_id != unit.id
		hand = hand.filter(keep)
		draw_pile = draw_pile.filter(keep)
		discard_pile = discard_pile.filter(keep)


# --- Interne --------------------------------------------------------------

func _draw_card(at: int = -1) -> bool:
	if draw_pile.is_empty():
		if discard_pile.is_empty():
			return false
		draw_pile = discard_pile
		discard_pile = []
		_shuffle(draw_pile)
	var card = draw_pile.pop_back()
	if at < 0 or at > hand.size():
		hand.append(card)
	else:
		hand.insert(at, card)
	return true


func _plan_enemy_intents() -> void:
	for e in enemies():
		e.intent_tiles.clear()
		if e.attack == "none":
			e.intent_target = null
			continue
		e.intent_target = _nearest_hero(e.pos)
		if e.attack == "barrage" and e.intent_target != null:
			var center: Vector2i = e.intent_target.pos
			for p in [center, center + Vector2i.UP, center + Vector2i.DOWN, center + Vector2i.LEFT, center + Vector2i.RIGHT]:
				if in_bounds(p):
					e.intent_tiles.append(p)


## Choisit les cases où des renforts arriveront à la fin du prochain tour ennemi.
func _plan_spawns() -> void:
	planned_spawns.clear()
	var room := max_enemies - enemies().size()
	var free := spawn_tiles.filter(func(p): return not is_blocked(p))
	_shuffle(free)
	for i in mini(mini(spawns_per_turn, room), free.size()):
		planned_spawns.append(free[i])


## Un héros posté sur une case de renfort empêche l'arrivée.
func _spawn_reinforcements() -> void:
	for p in planned_spawns:
		if is_blocked(p):
			continue
		_spawned += 1
		var enemy = _library.make_enemy(spawn_enemy_id, _spawned)
		enemy.pos = p
		units.append(enemy)
		fx.append({"type": "spawn", "unit": enemy})
		_event("Renfort : %s" % enemy.name)
	planned_spawns.clear()


func _nearest_hero(from: Vector2i):
	var best = null
	for h in heroes():
		if best == null:
			best = h
			continue
		var d := distance(from, h.pos)
		var best_d := distance(from, best.pos)
		if d < best_d or (d == best_d and h.hp < best.hp):
			best = h
	return best


## Case où l'ennemi s'arrête : à portée d'attaque avec le moins de pas possible,
## sinon la plus proche de sa cible.
func _approach(enemy, target) -> Vector2i:
	var options := reachable(enemy.pos, enemy.move_range)
	var best: Vector2i = enemy.pos
	var best_score := INF
	for p in options:
		var d := distance(p, target.pos)
		var score: float
		if d <= enemy.attack_range:
			score = options[p]
		else:
			score = 100 + d * 10 + options[p]
		if score < best_score:
			best_score = score
			best = p
	return best


func _check_end() -> void:
	if phase == Phase.WON or phase == Phase.LOST:
		return
	var won: bool = not _alive(bomb()) if bomb_turns > 0 else enemies().is_empty()
	if won:
		phase = Phase.WON
		_event("Victoire !")
	elif heroes().is_empty():
		phase = Phase.LOST
		_event("Défaite...")


func _shuffle(cards: Array) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp


func _event(text: String) -> void:
	events.append(text)


func _alive(unit) -> bool:
	return unit != null and unit.is_alive()


static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func _direction(from: Vector2i, to: Vector2i) -> Vector2i:
	var d := to - from
	if d == Vector2i.ZERO:
		return Vector2i.UP
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0)
	return Vector2i(0, signi(d.y))


static func _vec(a) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))
