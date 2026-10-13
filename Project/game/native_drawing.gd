extends GameRoutines
## Two routines of the original's drawing code as a machine without the
## translated program needs them: what they do to the game's own records,
## without what they do to the video hardware. (The picture is drawn from
## the records, see video/game_scene.gd.) Not checked against the original,
## which does both.

const Sprite := preload("res://game/sprite_object.gd")

## The order the sprite objects are drawn in: its ends and how many.
const DRAW_ORDER_FIRST := 0x102226
const DRAW_ORDER_LAST := 0x10222A
const DRAW_ORDER_COUNT := 0x102224
const NO_ORDER := [0x29292, 0x2929A]
const SPRITES_BUILT := 0x1020A0
## The ground: 1 while it is drawn, the table for the screen's height, the
## two lists of where its strips are, and a count of what is to be sent.
const GROUND_ON := 0x102530
const GROUND_PENDING := 0x102532
const GROUND_HEIGHTS := 0x1025CE
const HEIGHTS := 0x296E2
const GROUND_POSITIONS := [0x1025D2, 0x1025D6]
const POSITIONS := [0x1025DA, 0x1026DC]
const POSITIONS_SIZE := 0x102


func routines() -> Dictionary:
	return {
		0x120E0: clear_sprites,
		0x133FA: ground_off,
	}


## $120E0: no sprite object is in use.
func clear_sprites() -> void:
	set32(DRAW_ORDER_FIRST, NO_ORDER[0])
	set32(DRAW_ORDER_LAST, NO_ORDER[1])
	set16(DRAW_ORDER_COUNT, 0)
	for index in Sprite.record_count(m):
		Sprite.free_record(m, Sprite.record(index))
	set16(SPRITES_BUILT, 0)


## $133FA: no ground is drawn.
func ground_off() -> void:
	set16(GROUND_ON, 0)
	set32(GROUND_HEIGHTS, HEIGHTS)
	for list in 2:
		set32(GROUND_POSITIONS[list], POSITIONS[list])
		for index in POSITIONS_SIZE:
			set8(POSITIONS[list] + index, 0)
	set16(GROUND_PENDING, 0)
