shader_type canvas_item;

// Shows the game's picture enlarged by any amount, a whole number of times
// or not, with every game pixel as a sharp square: only the screen pixels
// that lie across two game pixels are a mix of the two. The texture must
// be filtered.

uniform vec2 picture_size = vec2(320.0, 224.0); // in game pixels
uniform float scale = 4.0;                      // screen pixels to a game pixel

void fragment() {
	// between the middles of game pixels `first` and the next
	vec2 at = UV * picture_size - 0.5;
	vec2 first = floor(at);
	vec2 mixed = clamp((at - first - 0.5) * scale + 0.5, 0.0, 1.0);
	COLOR = vec4(texture(TEXTURE, (first + 0.5 + mixed) / picture_size).rgb, 1.0);
}
