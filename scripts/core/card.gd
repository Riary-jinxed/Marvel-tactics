extends RefCounted
## Une carte jouable, décrite dans data/game_data.json.

enum Type { ATTACK, SKILL, HEROIC }

const TYPE_NAMES := {"attack": Type.ATTACK, "skill": Type.SKILL, "heroic": Type.HEROIC}

var id := ""
var name := ""
var hero_id := ""
var type := Type.ATTACK
## Coût en Héroïsme (cartes Héroïques uniquement).
var cost := 0
## "enemy", "ally", "self", "tile" ou "tile_empty".
var target := "enemy"
## Portée en cases (distance de Manhattan depuis le héros).
var reach := 0
var effects: Array = []
var text := ""
