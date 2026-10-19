extends RefCounted
## Une unité sur la grille de combat : héros ou ennemi.

enum Team { HERO, ENEMY }

var id := ""
var name := ""
## Lettre affichée tant qu'il n'y a pas de sprite.
var short := ""
var team := Team.HERO
## "hero", "minion" ou "elite".
var kind := "hero"
var color := Color.WHITE
var max_hp := 1
var hp := 1
var shield := 0
var pos := Vector2i.ZERO
var move_range := 2
var attack_range := 1
var attack_damage := 0
var frost := 0
var frozen := false
var burrowed := false
var has_moved := false
## Héros que l'ennemi attaquera à son prochain tour (intention affichée).
var intent_target = null


func is_alive() -> bool:
	return hp > 0


func is_hero() -> bool:
	return team == Team.HERO


## Applique des dégâts après le bouclier ; renvoie les PV réellement perdus.
func take_damage(amount: int) -> int:
	if burrowed or amount <= 0 or not is_alive():
		return 0
	var absorbed: int = mini(shield, amount)
	shield -= absorbed
	var lost: int = mini(hp, amount - absorbed)
	hp -= lost
	return lost


func heal(amount: int) -> int:
	var gained: int = mini(max_hp - hp, amount)
	hp += gained
	return gained
