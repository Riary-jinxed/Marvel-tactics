extends SceneTree
## Tests de la logique de combat.
## Lancer : godot --headless --path . -s tests/run_tests.gd

const BattleState = preload("res://scripts/core/battle_state.gd")
const CardLibrary = preload("res://scripts/core/card_library.gd")

var library
var checks := 0
var failures := 0


func _init() -> void:
	library = CardLibrary.new()
	var tests := [
		"test_default_mission",
		"test_attack_gives_heroism",
		"test_last_enemy_wins",
		"test_knockback_into_crate",
		"test_ice_slide",
		"test_frost_freezes",
		"test_swallow",
		"test_burrow_avoids_damage",
		"test_heroic_cost",
		"test_enemy_moves_and_attacks",
		"test_ko_removes_cards",
		"test_redraw",
		"test_barrel_explodes",
		"test_hero_move",
	]
	for test in tests:
		call(test)
	print("%d vérifications, %d échec(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("ÉCHEC : " + label)


func make_state(heroes: Array, enemies: Array, crates := [], barrels := []):
	var mission := {"heroes": [], "enemies": [], "crates": crates, "barrels": barrels}
	for h in heroes:
		mission.heroes.append({"id": h[0], "pos": h[1]})
	for e in enemies:
		mission.enemies.append({"id": e[0], "pos": e[1]})
	var state = BattleState.new()
	state.setup(library, mission, 42)
	return state


## Ajoute une carte précise à la main et renvoie son index.
func give(state, card_id: String, hero_id: String) -> int:
	state.hand.append(library.make_card(card_id, hero_id))
	return state.hand.size() - 1


func test_default_mission() -> void:
	var state = BattleState.new()
	state.setup(library, library.data.mission, 1)
	check(state.hand.size() == 5, "main de 5 cartes")
	check(state.hand.size() + state.draw_pile.size() == 24, "24 cartes au total")
	check(state.heroes().size() == 3, "3 héros")
	check(state.enemies().size() == 6, "6 ennemis")
	check(state.plays_left == 3 and state.redraws_left == 2, "budget du tour")
	for e in state.enemies():
		check(e.intent_target != null, "intention de %s" % e.name)


func test_attack_gives_heroism() -> void:
	var s = make_state([["magik", [2, 5]]], [["hydra_brute", [2, 4]], ["hydra_minion", [5, 0]]])
	var i := give(s, "magik_soulsword", "magik")
	check(s.play_card(i, Vector2i(2, 4)), "Épée d'âme jouable")
	check(s.unit_at(Vector2i(2, 4)).hp == 7, "brute à 7 PV")
	check(s.heroism == 1, "1 Héroïsme gagné")
	check(s.plays_left == 2, "2 cartes restantes")
	i = give(s, "magik_soulsword", "magik")
	check(not s.play_card(i, Vector2i(5, 0)), "hors de portée refusé")


func test_last_enemy_wins() -> void:
	var s = make_state([["magik", [2, 5]]], [["hydra_minion", [2, 4]]])
	s.play_card(give(s, "magik_soulsword", "magik"), Vector2i(2, 4))
	check(s.phase == BattleState.Phase.WON, "victoire quand le dernier ennemi tombe")


func test_knockback_into_crate() -> void:
	var s = make_state([["magik", [2, 5]]], [["hydra_brute", [2, 4]]], [[2, 3]])
	s.play_card(give(s, "magik_limbo_strike", "magik"), Vector2i(2, 4))
	var brute = s.enemies()[0]
	check(brute.pos == Vector2i(2, 4), "la brute reste contre la caisse")
	check(brute.hp == 6, "2 dégâts + 2 de collision (hp=%d)" % brute.hp)


func test_ice_slide() -> void:
	var s = make_state([["magik", [2, 5]]], [["hydra_brute", [2, 4]]])
	for p in [Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0)]:
		s.ice[p] = true
	s.play_card(give(s, "magik_limbo_strike", "magik"), Vector2i(2, 4))
	var brute = s.enemies()[0]
	check(brute.pos == Vector2i(2, 0), "glisse jusqu'au bord (pos=%s)" % brute.pos)
	check(brute.hp == 6, "collision contre le bord (hp=%d)" % brute.hp)


func test_frost_freezes() -> void:
	var s = make_state([["luna_snow", [1, 6]]], [["hydra_gunner", [1, 3]]])
	for n in 3:
		check(s.play_card(give(s, "luna_shard", "luna_snow"), Vector2i(1, 3)), "éclat %d" % n)
	var gunner = s.enemies()[0]
	check(gunner.frozen, "gelé après 3 givres")
	check(gunner.hp == 1, "tireur à 1 PV")
	s.end_turn()
	check(s.hero_by_id("luna_snow").hp == 10, "l'ennemi gelé n'attaque pas")
	check(not gunner.frozen, "dégel après un tour")


func test_swallow() -> void:
	var s = make_state([["jeff", [2, 5]]], [["hydra_minion", [2, 4]], ["hydra_brute", [3, 5]]])
	s.play_card(give(s, "jeff_swallow", "jeff"), Vector2i(2, 4))
	check(s.unit_at(Vector2i(2, 4)) == null, "sbire avalé")
	s.play_card(give(s, "jeff_swallow", "jeff"), Vector2i(3, 5))
	var brute = s.enemies()[0]
	check(brute.hp == 8 and brute.pos == Vector2i(5, 5), "élite blessée et repoussée (hp=%d pos=%s)" % [brute.hp, brute.pos])


func test_burrow_avoids_damage() -> void:
	var s = make_state([["jeff", [2, 6]]], [["hydra_brute", [2, 3]]])
	check(s.play_card(give(s, "jeff_dive", "jeff"), Vector2i(2, 4)), "plongée jouable")
	s.end_turn()
	var jeff = s.hero_by_id("jeff")
	check(jeff.hp == 14, "aucun dégât sous terre (hp=%d)" % jeff.hp)
	check(not jeff.burrowed, "Jeff ressort au tour suivant")


func test_heroic_cost() -> void:
	var s = make_state([["magik", [2, 5]]], [["hydra_brute", [2, 4]], ["hydra_minion", [3, 6]], ["hydra_minion", [0, 0]]])
	var i := give(s, "magik_darkchylde", "magik")
	check(not s.can_play(i), "Héroïque injouable sans Héroïsme")
	s.heroism = 3
	check(s.play_card(i, Vector2i(2, 5)), "Darkchylde jouable avec 3 Héroïsme")
	check(s.heroism == 0, "Héroïsme dépensé")
	check(s.enemies().size() == 2, "le sbire adjacent tombe, le lointain reste")
	check(s.unit_at(Vector2i(2, 4)).hp == 5, "brute à 5 PV")


func test_enemy_moves_and_attacks() -> void:
	var s = make_state([["magik", [0, 6]]], [["hydra_minion", [0, 3]]])
	s.end_turn()
	check(s.enemies()[0].pos == Vector2i(0, 5), "le sbire avance de 2 cases")
	check(s.hero_by_id("magik").hp == 10, "puis attaque")
	check(s.turn == 2 and s.plays_left == 3, "nouveau tour")


func test_ko_removes_cards() -> void:
	var s = make_state([["magik", [0, 6]], ["jeff", [5, 6]]], [["hydra_brute", [0, 5]]])
	s.hero_by_id("magik").hp = 1
	s.end_turn()
	var all_cards: Array = s.hand + s.draw_pile + s.discard_pile
	check(not s.hero_by_id("magik").is_alive(), "Magik KO")
	check(all_cards.all(func(c): return c.hero_id == "jeff"), "les cartes de Magik disparaissent")
	check(s.phase == BattleState.Phase.PLAYER, "le combat continue avec Jeff")


func test_redraw() -> void:
	var s = make_state([["magik", [2, 5]], ["jeff", [3, 5]]], [["hydra_brute", [0, 0]]])
	var first = s.hand[0]
	check(s.redraw(0), "repioche autorisée")
	check(s.hand.size() == 5 and s.hand[0] != first, "carte remplacée à la même place")
	check(s.discard_pile.has(first), "carte défaussée")
	s.redraw(0)
	check(not s.redraw(0), "2 repioches maximum")


func test_barrel_explodes() -> void:
	var s = make_state([["magik", [2, 5]]], [["hydra_brute", [2, 4]], ["hydra_minion", [3, 2]]], [], [[2, 3]])
	s.play_card(give(s, "magik_limbo_strike", "magik"), Vector2i(2, 4))
	var brute = s.unit_at(Vector2i(2, 4))
	check(s.barrels.is_empty(), "baril détruit")
	check(brute != null and brute.hp == 3, "2 + 2 collision + 3 explosion")
	check(s.unit_at(Vector2i(3, 2)) == null, "sbire pris dans l'explosion")
	check(s.hero_by_id("magik").hp == 12, "Magik hors de l'explosion")


func test_hero_move() -> void:
	var s = make_state([["magik", [0, 6]]], [["hydra_brute", [5, 0]]], [[0, 5]])
	var magik = s.hero_by_id("magik")
	check(not s.move_targets(magik).has(Vector2i(0, 4)), "pas de passage à travers une caisse")
	check(s.move_hero(magik, Vector2i(2, 6)), "déplacement de 2 cases")
	check(not s.move_hero(magik, Vector2i(3, 6)), "un seul déplacement par tour")
