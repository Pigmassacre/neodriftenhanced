// Tiles replaced by mods (mods/mod_graphics.gd): a tile number may have a
// picture of its own, in full colour and up to four times as fine, that is
// drawn instead of the tile's colour numbers.

// For each tile number (1024 to a row) the replacement's place in
// replaced_tex, plus one; 0 for a tile that is not replaced.
uniform sampler2D replaced_index_tex : filter_nearest, repeat_disable;
// The replacements side by side, each 16 * replaced_scale pixels square.
uniform sampler2D replaced_tex : filter_nearest, repeat_disable;
// For each replacement the 16 colours it was painted against (alpha 0 where
// it is not known): the game's colours change (fades, other cars in other
// colours), and the replacement follows them.
uniform sampler2D replaced_colours_tex : filter_nearest, repeat_disable;
uniform bool replacing = false;
uniform int replaced_scale = 1;

// The place of `code`'s replacement, plus one, or 0.
int replacement_of(int code) {
	if (!replacing) {
		return 0;
	}
	ivec4 entry = ivec4(round(texelFetch(replaced_index_tex, ivec2(code & 1023, code >> 10), 0) * 255.0));
	return entry.r | (entry.g << 8);
}

// The replacement's colour at `pixel` of the tile (0 to 15, flips done) and
// `fine` within that pixel (0 to 1). `index` is the original's colour
// number there, and `palette` the colours the tile is drawn with now, row
// `palette_row` of `palettes`.
vec4 replaced_colour(int place, ivec2 pixel, vec2 fine, int index, sampler2D palettes, int palette_row) {
	int slot = place - 1;
	int size = 16 * replaced_scale;
	int across = textureSize(replaced_tex, 0).x / size;
	ivec2 at = ivec2(slot % across, slot / across) * size + pixel * replaced_scale
			+ ivec2(clamp(floor(fine * float(replaced_scale)), 0.0, float(replaced_scale - 1)));
	vec4 colour = texelFetch(replaced_tex, at, 0);
	if (texelFetch(replaced_colours_tex, ivec2(0, slot), 0).a == 0.0) {
		return colour;
	}
	// how the colours have changed since: by the original's colour here, or
	// by all of the tile's colours where the original shows nothing
	vec3 now = vec3(0.0);
	vec3 then = vec3(0.0);
	if (index > 0) {
		now = texelFetch(palettes, ivec2(index, palette_row), 0).rgb;
		then = texelFetch(replaced_colours_tex, ivec2(index, slot), 0).rgb;
	} else {
		for (int number = 1; number < 16; number++) {
			now += texelFetch(palettes, ivec2(number, palette_row), 0).rgb;
			then += texelFetch(replaced_colours_tex, ivec2(number, slot), 0).rgb;
		}
		now /= 15.0;
		then /= 15.0;
	}
	// the replacement's difference from the colour it was painted over,
	// on the colour there now, as much brighter or darker as that is
	const vec3 LUMA = vec3(0.299, 0.587, 0.114);
	float brightness = (dot(now, LUMA) + 0.02) / (dot(then, LUMA) + 0.02);
	return vec4(clamp(now + (colour.rgb - then) * brightness, 0.0, 1.0), colour.a);
}
