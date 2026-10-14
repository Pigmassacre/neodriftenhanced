shader_type canvas_item;

// The ground of a course, straight from the course's map. Which tile and
// which of its pixels is at a pixel of the picture is worked out for every
// column and every line of the picture beforehand (NeoGeoVideo), since the
// two do not depend on each other.

// Row 0, by pixel across: the map's column of tiles (two bytes), the pixel
// within the tile, and 255 where there is ground. Row 1 likewise by line.
uniform sampler2D lookup_tex : filter_nearest, repeat_disable;
// The block number at each place of the map (two bytes).
uniform sampler2D places_tex : filter_nearest, repeat_disable;
// 16 blocks to a row; a block is 16 columns of 16 tiles, each tile number
// (two bytes), flips and palette.
uniform sampler2D blocks_tex : filter_nearest, repeat_disable;
uniform sampler2D tiles_tex : filter_nearest, repeat_disable;  // 4096x4096, 256 tiles per row
uniform sampler2D pal_tex : filter_nearest, repeat_disable;    // 16 x 256
uniform vec2 view_size = vec2(320.0, 224.0);
uniform int auto_anim = 0;
uniform bool auto_anim_enabled = true;

#include "res://video/replaced.gdshaderinc"

void fragment() {
	ivec2 pixel = ivec2(floor(UV * view_size));
	vec2 fine = fract(UV * view_size);
	ivec4 across = ivec4(round(texelFetch(lookup_tex, ivec2(pixel.x, 0), 0) * 255.0));
	ivec4 down = ivec4(round(texelFetch(lookup_tex, ivec2(pixel.y, 1), 0) * 255.0));
	if (across.a == 0 || down.a == 0) {
		discard;
	}
	int column = across.r | (across.g << 8);
	int row = down.r | (down.g << 8);
	ivec4 place = ivec4(round(texelFetch(places_tex, ivec2(column >> 4, row >> 4), 0) * 255.0));
	int block = place.r | (place.g << 8);
	ivec2 in_blocks = ivec2((block & 15) * 256 + (column & 15) * 16 + (row & 15), block >> 4);
	ivec4 cell = ivec4(round(texelFetch(blocks_tex, in_blocks, 0) * 255.0));
	int code = cell.r | (cell.g << 8);
	int attr = cell.b;
	int high = attr >> 4;
	if (auto_anim_enabled) {
		if ((attr & 8) != 0) {
			code = (code & ~7) | (auto_anim & 7);
		} else if ((attr & 4) != 0) {
			code = (code & ~3) | (auto_anim & 3);
		}
	}
	int x = across.b;
	int y = down.b;
	if ((attr & 1) != 0) {
		x = 15 - x;
		fine.x = 1.0 - fine.x;
	}
	if ((attr & 2) != 0) {
		y = 15 - y;
		fine.y = 1.0 - fine.y;
	}
	ivec2 atlas = ivec2(code & 255, code >> 8) * 16 + ivec2(x, y);
	int index = int(round(texelFetch(tiles_tex, atlas, 0).r * 255.0));
	int replaced_at = replacement_of(code | (high << 16));
	if (replaced_at > 0) {
		vec4 colour = replaced_colour(replaced_at, ivec2(x, y), fine, index, pal_tex, cell.a);
		if (colour.a == 0.0) {
			discard;
		}
		COLOR = colour;
	} else {
		if (index == 0) {
			discard;
		}
		COLOR = vec4(texelFetch(pal_tex, ivec2(index, cell.a), 0).rgb, 1.0);
	}
}
