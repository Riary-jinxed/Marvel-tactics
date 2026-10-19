extends RefCounted
## Charge les héros, ennemis, cartes et la mission depuis le fichier de données.

const Unit = preload("res://scripts/core/unit.gd")
const Card = preload("res://scripts/core/card.gd")

const DATA_PATH := "res://data/game_data.json"

var data: Dictionary = {}


func _init(path: String = DATA_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "Données introuvables : %s" % path)
	data = JSON.parse_string(file.get_as_text())


func make_card(card_id: String, hero_id: String) -> Card:
	var d: Dictionary = data.cards[card_id]
	var card := Card.new()
	card.id = card_id
	card.hero_id = hero_id
	card.name = d.name
	card.type = Card.TYPE_NAMES[d.type]
	card.cost = int(d.get("cost", 0))
	card.target = d.target
	card.reach = int(d.get("reach", 0))
	card.effects = d.effects
	card.text = d.text
	return card


## Le deck de mission d'un héros (8 cartes, doublons compris).
func make_deck(hero_id: String) -> Array:
	var deck := []
	for entry in data.heroes[hero_id].deck:
		for i in int(entry[1]):
			deck.append(make_card(entry[0], hero_id))
	return deck


func make_hero(hero_id: String) -> Unit:
	var d: Dictionary = data.heroes[hero_id]
	var unit := _make_unit(d)
	unit.id = hero_id
	unit.team = Unit.Team.HERO
	unit.kind = "hero"
	return unit


func make_enemy(enemy_id: String, number: int) -> Unit:
	var d: Dictionary = data.enemies[enemy_id]
	var unit := _make_unit(d)
	unit.id = "%s_%d" % [enemy_id, number]
	unit.team = Unit.Team.ENEMY
	unit.kind = d.kind
	unit.attack_range = int(d.get("attack_range", 0))
	unit.attack_damage = int(d.get("attack_damage", 0))
	unit.attack = d.get("attack", "melee")
	unit.attack_push = int(d.get("attack_push", 0))
	unit.immovable = unit.kind == "device"
	return unit


func _make_unit(d: Dictionary) -> Unit:
	var unit := Unit.new()
	unit.name = d.name
	unit.short = d.short
	unit.color = Color(d.color)
	unit.max_hp = int(d.hp)
	unit.hp = unit.max_hp
	unit.move_range = int(d.get("move", 2))
	unit.sprite_path = d.get("sprite", "")
	return unit
