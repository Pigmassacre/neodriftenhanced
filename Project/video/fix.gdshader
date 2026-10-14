shader_type canvas_item;

// The text layer: 40x32 tiles of 8x8 pixels drawn over everything else.
// In a picture wider than the hardware's it is in the middle, and can be
// drawn in three parts with the outer two moved to the picture's edges.

// 122x32: tile lo, tile hi nibble, palette, and the screen line from which the
// cell applies; above that line the cell 40 to the right (the text before a
// change during the frame) shows, by the same rule. The next two columns are
// the tiles that cover the picture left and right of the layer, row by row
// (nothing where the fourth byte is 0). The last column's fourth byte is 0
// for a row that is not to be drawn in parts.
uniform sampler2D cells_tex : filter_nearest, repeat_disable;
uniform sampler2D fix_tex : filter_nearest, repeat_disable;   // 512x512, 64 tiles per row
uniform sampler2D pal_tex : filter_nearest, repeat_disable;   // 16 x 256
uniform vec2 view_size = vec2(320.0, 224.0);
// How far the layer's left edge is from the picture's.
uniform int margin = 0;
// How many pixels of the layer are left out at its left and at its right:
// the columns the game fills with black to hide the ragged edges of its
// scrolling ground.
uniform ivec2 open_sides = ivec2(0);
// Covers the picture beyond the layer (and the columns left out) with the
// tiles cells_tex has for it.
uniform bool cover_sides = false;
// How far the game's curtain is closed, from 0 to 1, or less than 0 when it
// is not moving. It is then drawn in wipe_colour from two corners of the
// picture towards the line between the other two, and the cells the game
// draws it with (wipe_cells: tile numbers, all of palette wipe_palette) are
// left out.
uniform float wipe = -1.0;
uniform vec3 wipe_colour = vec3(0.0);
uniform ivec3 wipe_cells = ivec3(0x020, 0x37F, 0x37B);
uniform int wipe_palette = 4;
// How far the columns left of the HUD's left end are moved left and those
// from HUD_RIGHT_START on are moved right.
uniform int spread = 0;

// The first two tile rows are above the visible picture.
const int FIRST_ROW = 2;
const int WIDTH = 320;
const int SIDE_CELLS = 120;
const int WHOLE_ROWS = 122;
// What a race shows at the left ends before these columns (the time taken
// in the upper half of the picture, the speed in the lower), and what it
// shows at the right (the time left, the stage) starts at the other.
const int HUD_LEFT_END_ABOVE = 15;
const int HUD_LEFT_END_BELOW = 13;
const int HUD_RIGHT_START = 26;

#include "res://video/replaced.gdshaderinc"

// Mods replace the text layer's tiles as tile numbers from this on
// (mods/mod_graphics.gd).
const int REPLACED_FIX = 0xFF000;

// The colour number and the palette of a cell's tile at a pixel of it, the
// tile's number plus one (0 for none) and the pixel within the tile.
ivec4 tile_pixel(ivec4 cell, ivec2 pixel) {
	int tile = cell.r | (cell.g << 8);
	if (wipe >= 0.0 && cell.b == wipe_palette
			&& (tile == wipe_cells.x || tile == wipe_cells.y || tile == wipe_cells.z)) {
		return ivec4(0);
	}
	ivec2 within = pixel & ivec2(7);
	ivec2 atlas = ivec2(tile & 63, tile >> 6) * 8 + within;
	return ivec4(int(round(texelFetch(fix_tex, atlas, 0).r * 255.0)), cell.b, tile + 1, within.x | (within.y << 3));
}

// The same for the text at `x` across the layer, on the picture's line `y`.
ivec4 text_pixel(int x, int y) {
	ivec2 cell_pos = ivec2(x >> 3, (y >> 3) + FIRST_ROW);
	ivec4 cell = ivec4(round(texelFetch(cells_tex, cell_pos, 0) * 255.0));
	if (y < cell.a) {
		cell = ivec4(round(texelFetch(cells_tex, cell_pos + ivec2(40, 0), 0) * 255.0));
		if (y < cell.a) {
			cell = ivec4(round(texelFetch(cells_tex, cell_pos + ivec2(80, 0), 0) * 255.0));
		}
	}
	return tile_pixel(cell, ivec2(x, y));
}

void fragment() {
	ivec2 pixel = ivec2(floor(UV * view_size));
	vec2 across = (vec2(pixel) + 0.5) / view_size;
	bool curtain = wipe >= 0.0 && min(across.x + across.y, 2.0 - across.x - across.y) < wipe;
	int x = pixel.x - margin;
	int row = (pixel.y >> 3) + FIRST_ROW;
	int first = open_sides.x;
	int last = WIDTH - open_sides.y;
	int parted = spread;
	if (parted > 0 && texelFetch(cells_tex, ivec2(WHOLE_ROWS, row), 0).a == 0.0) {
		parted = 0;
	}
	int left_end = (pixel.y < 112 ? HUD_LEFT_END_ABOVE : HUD_LEFT_END_BELOW) * 8;
	ivec4 found = ivec4(0);
	if (parted > 0 && x + parted >= first && x + parted < left_end) {
		found = text_pixel(x + parted, pixel.y);
	} else if (parted > 0 && x - parted >= HUD_RIGHT_START * 8 && x - parted < last) {
		found = text_pixel(x - parted, pixel.y);
	} else if (x >= first && x < last) {
		if (parted == 0 || (x >= left_end && x < HUD_RIGHT_START * 8)) {
			found = text_pixel(x, pixel.y);
		}
	} else if (cover_sides) {
		ivec4 cell = ivec4(round(texelFetch(cells_tex, ivec2(SIDE_CELLS + (x < first ? 0 : 1), row), 0) * 255.0));
		if (cell.a != 0) {
			found = tile_pixel(cell, ivec2(0));
		}
	}
	int replaced_at = found.z > 0 ? replacement_of(REPLACED_FIX + found.z - 1) : 0;
	if (curtain) {
		COLOR = vec4(wipe_colour, 1.0);
	} else if (replaced_at > 0) {
		vec4 colour = replaced_colour(replaced_at, ivec2(found.w & 7, found.w >> 3),
				fract(UV * view_size), found.x, pal_tex, found.y);
		if (colour.a == 0.0) {
			discard;
		}
		COLOR = colour;
	} else if (found.x == 0) {
		discard;
	} else {
		COLOR = vec4(texelFetch(pal_tex, ivec2(found.x, found.y), 0).rgb, 1.0);
	}
}
