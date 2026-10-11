shader_type canvas_item;

// Draws the course background exactly as the game composes it on the
// hardware: 32 one-tile-wide sprite columns forming a 512x512 wrap-around
// window onto the course tilemap, each column shrunk horizontally and
// vertically according to the camera zoom.
//
// Every 4-bit tile pixel indexes one of 256 sixteen-colour palettes; index 0
// is transparent and shows the backdrop colour.

uniform sampler2D map_tex : filter_nearest, repeat_disable;    // tile lo, tile hi, flips, palette
uniform sampler2D tiles_tex : filter_nearest, repeat_disable;  // 4096x4096, 256 tiles per row
uniform sampler2D pal_tex : filter_nearest, repeat_disable;    // 16 x 256
uniform sampler2D zoom_y_tex : filter_nearest, repeat_disable; // 256x256 vertical shrink table
uniform ivec2 map_size;          // in tiles
uniform ivec2 camera;            // the game's scroll position
uniform ivec2 zoom;              // 8.8 fixed point, 0x100 = 1:1
uniform int shrink_steps[32];    // per-column change of the shrink control word
uniform int x_steps[32];         // per-column extra X step (1/128 px)
uniform ivec4 raster;            // line offset, timing offset, first and last visible line
uniform vec2 screen_size = vec2(320.0, 224.0);

// The first visible raster line.
const int FIRST_LINE = 16;
// Which of a tile's 16 pixel columns survive at each horizontal shrink level (bit 0 = leftmost).
const int SHRINK_X[16] = int[](
	0x0100, 0x0110, 0x1110, 0x1114, 0x5114, 0x5154, 0x5554, 0x5555,
	0x5755, 0x575d, 0xd75d, 0xd7dd, 0xf7dd, 0xf7df, 0xffdf, 0xffff);

void fragment() {
	ivec2 pixel = ivec2(floor(UV * screen_size));
	int line = pixel.y + FIRST_LINE;

	// Vertical: the 512-pixel ring is placed twice, one below the other;
	// part-way down the screen the game switches from the first placement
	// to the second.
	int top = zoom.y - (((camera.y & 0x1ff) * zoom.y) >> 8);
	int split = top + zoom.y;
	if (split < raster.z || (split <= raster.w && line >= split - raster.x)) {
		top = split + zoom.y;
	}
	int shrink_y = (zoom.y - 1) & 0xff;
	int sprite_line = (line - top) & 0x1ff;
	int zoom_line = sprite_line & 0xff;
	bool invert = (sprite_line & 0x100) != 0;
	if (invert) {
		zoom_line ^= 0xff;
	}
	int period = (shrink_y + 1) << 1;
	zoom_line %= period;
	if (zoom_line >= shrink_y + 1) {
		zoom_line = period - 1 - zoom_line;
		invert = !invert;
	}
	int entry_y = int(round(texelFetch(zoom_y_tex, ivec2(zoom_line, shrink_y), 0).r * 255.0));
	int ring_row = entry_y >> 4;
	int tile_y = entry_y & 15;
	if (invert) {
		ring_row ^= 0x1f;
		tile_y ^= 0xf;
	}
	int first_row = (camera.y >> 4) - 2;
	int row = first_row + ((ring_row + 16 - first_row) & 31);

	// Horizontal: walk the 32 columns left to right; where columns overlap
	// the one in the higher-numbered sprite slot is drawn on top.
	int x = (-(((camera.x & 15) * zoom.x) >> 1)) & 0xff80;
	int x_step = (zoom.x & 0xfff0) << 3;
	int control = (((zoom.x - 0x10) & 0xf0) << 4) + zoom.y - 1;
	int first_column = camera.x >> 4;
	int best_slot = -1;
	int column = 0;
	int tile_x = 0;
	for (int i = 0; i < 32; i++) {
		control = (control + shrink_steps[i]) & 0xffff;
		int mask = SHRINK_X[(control >> 8) & 15];
		int offset = (pixel.x - (x >> 7)) & 0x1ff;
		int slot = (first_column + i) & 31;
		if (offset < 16 && slot > best_slot) {
			int seen = 0;
			for (int k = 0; k < 16; k++) {
				if ((mask & (1 << k)) != 0) {
					if (seen == offset) {
						best_slot = slot;
						column = first_column - 2 + ((i + 2) & 31);
						tile_x = k;
					}
					seen++;
				}
			}
		}
		x = (x + x_step + x_steps[i]) & 0xffff;
	}

	vec3 colour = texelFetch(pal_tex, ivec2(15, 255), 0).rgb;
	if (best_slot >= 0) {
		ivec2 cell = ivec2(column, row);
		cell = ((cell % map_size) + map_size) % map_size;
		ivec4 entry = ivec4(round(texelFetch(map_tex, cell, 0) * 255.0));
		if ((entry.b & 1) != 0) {
			tile_x = 15 - tile_x;
		}
		if ((entry.b & 2) != 0) {
			tile_y = 15 - tile_y;
		}
		ivec2 atlas = ivec2(entry.r, entry.g) * 16 + ivec2(tile_x, tile_y);
		int index = int(round(texelFetch(tiles_tex, atlas, 0).r * 255.0));
		if (index != 0) {
			colour = texelFetch(pal_tex, ivec2(index, entry.a), 0).rgb;
		}
	}
	COLOR = vec4(colour, 1.0);
}
