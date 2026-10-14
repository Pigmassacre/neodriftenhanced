shader_type canvas_item;

// Draws hardware sprites from the machine's video RAM. Every sprite is one
// 16-pixel-wide strip of up to 32 tiles; the quad for a strip covers the
// whole screen height and this shader works out, per pixel, which tile row
// and pixel the hardware would show there, including its shrink tables.

uniform sampler2D strips_tex : filter_nearest, repeat_disable; // per sprite: 32 tiles (code lo, code mid, code hi | attr, palette)
uniform sampler2D tiles_tex : filter_nearest, repeat_disable;  // 4096x4096, 256 tiles per row
uniform sampler2D pal_tex : filter_nearest, repeat_disable;    // 16 x 256
uniform sampler2D zoom_y_tex : filter_nearest, repeat_disable; // 256x256 vertical shrink table
uniform int auto_anim = 0;
uniform bool auto_anim_enabled = true;

#include "res://video/replaced.gdshaderinc"

// Which of a tile's 16 pixel columns survive at each horizontal shrink level (bit 0 = leftmost).
const int SHRINK_X[16] = int[](
	0x0100, 0x0110, 0x1110, 0x1114, 0x5114, 0x5154, 0x5554, 0x5555,
	0x5755, 0x575d, 0xd75d, 0xd7dd, 0xf7dd, 0xf7df, 0xffdf, 0xffff);

varying flat vec4 params;

void vertex() {
	params = COLOR;
}

void fragment() {
	// params: sprite index, top line, vertical shrink, rows + 64 * horizontal shrink
	// + 1024 if it is to be seen through + 2048 if it is drawn the other way
	// round (all / 1024)
	int sprite = int(round(params.r * 1024.0));
	int top = int(round(params.g * 1024.0));
	int shrink_y = int(round(params.b * 1024.0));
	int packed = int(round(params.a * 1024.0));
	int rows = packed & 63;
	int shrink_x = (packed >> 6) & 15;
	bool seen_through = (packed & 1024) != 0;
	int offset = int(floor(UV.x));
	vec2 fine = fract(UV);
	if (packed >= 2048) {
		offset = shrink_x - offset;
		fine.x = 1.0 - fine.x;
	}
	int line = int(floor(UV.y));

	int sprite_line = (line - top) & 0x1ff;
	if (rows < 0x21 && sprite_line >= rows * 16) {
		discard;
	}
	int zoom_line = sprite_line & 0xff;
	bool invert = (sprite_line & 0x100) != 0;
	if (invert) {
		zoom_line ^= 0xff;
	}
	if (rows > 0x20) {
		int period = (shrink_y + 1) << 1;
		zoom_line %= period;
		if (zoom_line >= shrink_y + 1) {
			zoom_line = period - 1 - zoom_line;
			invert = !invert;
		}
	}
	int entry = int(round(texelFetch(zoom_y_tex, ivec2(zoom_line, shrink_y), 0).r * 255.0));
	int tile_row = entry >> 4;
	int y = entry & 15;
	if (invert) {
		tile_row ^= 0x1f;
		y ^= 0xf;
	}

	int mask = SHRINK_X[shrink_x];
	int x = -1;
	int seen = 0;
	for (int k = 0; k < 16; k++) {
		if ((mask & (1 << k)) != 0) {
			if (seen == offset) {
				x = k;
			}
			seen++;
		}
	}
	if (x < 0) {
		discard;
	}

	ivec4 cell = ivec4(round(texelFetch(strips_tex, ivec2(tile_row, sprite), 0) * 255.0));
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
		COLOR = vec4(colour.rgb, colour.a * (seen_through ? 0.5 : 1.0));
	} else {
		if (index == 0) {
			discard;
		}
		COLOR = vec4(texelFetch(pal_tex, ivec2(index, cell.a), 0).rgb, seen_through ? 0.5 : 1.0);
	}
}
