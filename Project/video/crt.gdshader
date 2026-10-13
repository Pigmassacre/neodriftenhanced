shader_type canvas_item;

// Shows what is on screen under it as a picture tube would: the glass
// curved, the game's lines as bands of light with dark between, a mask of
// red, green and blue stripes, the colours a little apart towards the
// corners, and the corners darker. It is drawn over the game's picture and
// everything on it, as large as that picture.

uniform sampler2D screen : hint_screen_texture, filter_linear;
// How much the glass curves: 0 is flat.
uniform float curve = 0.0;
// The picture's lines: how many there are, and screen pixels to each (at
// least 3, or a line has no room for its dark part).
uniform float lines = 224.0;
uniform float pitch = 3.0;
// Where the picture is on screen, in pixels: its top left and its size.
uniform vec2 place = vec2(0.0);
uniform vec2 size = vec2(1280.0, 896.0);

void fragment() {
	vec2 bent = UV * 2.0 - 1.0;
	bent *= 1.0 + curve * bent.yx * bent.yx;
	vec2 uv = bent * 0.5 + 0.5;
	// from the picture to the screen
	vec2 at = (place + uv * size) * SCREEN_PIXEL_SIZE;
	vec2 centred = uv - 0.5;
	float shift = SCREEN_PIXEL_SIZE.x * (1.0 + 3.0 * dot(centred, centred));
	vec3 colour = vec3(texture(screen, at + vec2(shift, 0.0)).r, texture(screen, at).g,
			texture(screen, at - vec2(shift, 0.0)).b);
	float luma = dot(colour, vec3(0.299, 0.587, 0.114));
	// brightest in the middle of a line; a bright line is wider
	float scan = 0.5 - 0.5 * cos(uv.y * lines * TAU);
	colour *= 1.0 - mix(0.4, 0.12, luma) * (1.0 - scan);
	vec3 mask = vec3(0.82);
	mask[int(mod(floor(FRAGCOORD.x * 3.0 / pitch), 3.0))] = 1.0;
	colour *= mask * 1.18;
	vec2 edge = uv * (1.0 - uv);
	colour *= pow(max(edge.x * edge.y * 16.0, 0.0), 0.12);
	// nothing beyond the glass
	vec2 inside = min(uv, 1.0 - uv) * size;
	colour *= clamp(min(inside.x, inside.y), 0.0, 1.0);
	COLOR = vec4(colour, 1.0);
}
