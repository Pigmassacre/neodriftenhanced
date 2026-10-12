shader_type canvas_item;

// Shows the game's picture as a picture tube would: each line of the picture
// as a band of light with dark between, pixels running into each other
// across, and a mask of red, green and blue stripes. Meant for a picture
// enlarged three times or more.

uniform vec2 picture_size = vec2(320.0, 224.0); // in game pixels
uniform float scanlines : hint_range(0.0, 1.0) = 0.55;
uniform float mask : hint_range(0.0, 1.0) = 0.25;
uniform float blur : hint_range(0.0, 1.0) = 0.6;
uniform float glow : hint_range(0.0, 1.0) = 0.12;

// The colour of a game pixel, as light.
#define PIXEL(at) pow(texture(TEXTURE, ((at) + 0.5) / picture_size).rgb, vec3(2.2))

void fragment() {
	vec2 at = UV * picture_size;
	float line = floor(at.y);
	float within = at.y - line - 0.5;
	// across, neighbours run together
	float left = floor(at.x - 0.5);
	float sharp = smoothstep(0.0, 1.0, clamp((at.x - left - 1.0) / max(blur, 0.001) + 0.5, 0.0, 1.0));
	vec3 colour = vec3(0.0);
	// the line itself and the ones above and below, each a beam that is
	// wider the brighter it is
	for (int offset = -1; offset <= 1; offset++) {
		float beam_line = line + float(offset);
		vec3 beam = mix(PIXEL(vec2(left, beam_line)), PIXEL(vec2(left + 1.0, beam_line)), sharp);
		float away = within - float(offset);
		vec3 width = mix(0.5, 0.2, scanlines) * (0.7 + 0.6 * beam);
		colour += beam * exp(-(away * away) / (2.0 * width * width));
	}
	// what the beams leave dark is made up for
	colour *= mix(0.8, 1.35, scanlines);
	// a little light from around
	vec2 middle = floor(at);
	vec3 around = (PIXEL(middle - vec2(1.0, 0.0)) + PIXEL(middle + vec2(1.0, 0.0))
			+ PIXEL(middle - vec2(0.0, 1.0)) + PIXEL(middle + vec2(0.0, 1.0))) * 0.25;
	colour += around * glow;
	// stripes of the three colours, one screen pixel each
	int stripe = int(mod(floor(FRAGCOORD.x), 3.0));
	vec3 stripes = vec3(stripe == 0 ? 1.0 : 0.0, stripe == 1 ? 1.0 : 0.0, stripe == 2 ? 1.0 : 0.0);
	colour *= mix(vec3(1.0), stripes * 1.6 + 0.47, mask);
	COLOR = vec4(pow(clamp(colour, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0);
}
