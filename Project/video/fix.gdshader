shader_type canvas_item;

// The text layer: 40x32 tiles of 8x8 pixels drawn over everything else.

// 120x32: tile lo, tile hi nibble, palette, and the screen line from which the
// cell applies; above that line the cell 40 to the right (the text before a
// change during the frame) shows, by the same rule
uniform sampler2D cells_tex : filter_nearest, repeat_disable;
uniform sampler2D fix_tex : filter_nearest, repeat_disable;   // 512x512, 64 tiles per row
uniform sampler2D pal_tex : filter_nearest, repeat_disable;   // 16 x 256
uniform vec2 screen_size = vec2(320.0, 224.0);

// The first two tile rows are above the visible picture.
const int FIRST_ROW = 2;

void fragment() {
	ivec2 pixel = ivec2(floor(UV * screen_size));
	ivec2 cell_pos = ivec2(pixel.x >> 3, (pixel.y >> 3) + FIRST_ROW);
	ivec4 cell = ivec4(round(texelFetch(cells_tex, cell_pos, 0) * 255.0));
	if (pixel.y < cell.a) {
		cell = ivec4(round(texelFetch(cells_tex, cell_pos + ivec2(40, 0), 0) * 255.0));
		if (pixel.y < cell.a) {
			cell = ivec4(round(texelFetch(cells_tex, cell_pos + ivec2(80, 0), 0) * 255.0));
		}
	}
	int tile = cell.r | (cell.g << 8);
	ivec2 atlas = ivec2(tile & 63, tile >> 6) * 8 + (pixel & ivec2(7));
	int index = int(round(texelFetch(fix_tex, atlas, 0).r * 255.0));
	if (index == 0) {
		discard;
	}
	COLOR = vec4(texelFetch(pal_tex, ivec2(index, cell.b), 0).rgb, 1.0);
}
