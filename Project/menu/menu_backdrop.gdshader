shader_type canvas_item;

// What the menus are drawn on, over the game's picture: the picture dimmed,
// a dark slanted panel at the left that the rows are on, lines along its
// edge, a bar along the bottom, and streaks going by as if at speed.

// The size of the rectangle, in pixels.
uniform vec2 size = vec2(1280.0, 720.0);
// Where the panel's edge is halfway down, in pixels, and how far across it
// goes for each pixel up.
uniform float panel = 600.0;
uniform float slant = 0.18;
// From 0 to 1 as the menu comes on: the panel sweeps in.
uniform float appear = 1.0;
// 1 when nothing of the picture is to show.
uniform float cover = 0.0;
// The height of the bar at the bottom, in pixels.
uniform float footer = 60.0;
uniform vec4 ink : source_color = vec4(0.02, 0.03, 0.07, 1.0);
uniform vec4 panel_colour : source_color = vec4(0.03, 0.05, 0.11, 1.0);
uniform vec4 accent : source_color = vec4(1.0, 0.42, 0.08, 1.0);
uniform vec4 second : source_color = vec4(0.16, 0.89, 1.0, 1.0);

float hash(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// `top` (not premultiplied) over `under`.
vec4 over(vec4 under, vec3 colour, float alpha) {
	float out_alpha = alpha + under.a * (1.0 - alpha);
	if (out_alpha <= 0.0) {
		return vec4(0.0);
	}
	return vec4((colour * alpha + under.rgb * under.a * (1.0 - alpha)) / out_alpha, out_alpha);
}

// 1 on a line `width` wide at `at` along `d`, smoothed over a pixel.
float line(float d, float at, float width) {
	return 1.0 - smoothstep(width * 0.5 - 0.5, width * 0.5 + 0.5, abs(d - at));
}

void fragment() {
	vec2 p = UV * size;
	float unit = size.y / 100.0;
	float sweep = 1.0 - pow(1.0 - clamp(appear, 0.0, 1.0), 3.0);
	float edge = mix(-size.y * 0.6, panel, sweep) + (size.y * 0.5 - p.y) * slant;

	// the picture behind: dimmed, the more so nearer the panel and the edges
	vec2 centred = UV - vec2(0.62, 0.5);
	float dim = mix(0.5, 0.75, smoothstep(size.x * 0.9, 0.0, p.x)) + 0.3 * smoothstep(0.3, 0.8, length(centred));
	vec4 result = vec4(ink.rgb, mix(clamp(dim, 0.0, 1.0) * sweep, 1.0, cover));

	// the panel, lighter towards its edge, with a faint hatching
	float inside = 1.0 - smoothstep(edge - 0.75, edge + 0.75, p.x);
	vec3 shade = mix(panel_colour.rgb * 0.7, panel_colour.rgb * 1.5, clamp(p.x / max(edge, 1.0), 0.0, 1.0));
	float hatch = smoothstep(0.82, 1.0, fract((p.x + p.y * slant) / (unit * 1.1)));
	shade += vec3(0.05, 0.07, 0.1) * hatch * 0.35;
	result = over(result, shade, inside * 0.9);

	// streaks going by, right to left
	float row_height = max(unit * 0.9, 3.0);
	float row = floor(p.y / row_height);
	if (hash(row) > 0.74) {
		float speed = mix(0.7, 2.2, hash(row + 7.0)) * size.x;
		float streak = mix(0.06, 0.28, hash(row + 3.0)) * size.x;
		float span = size.x + streak * 2.0;
		float head = span - mod(TIME * speed + hash(row + 11.0) * span, span) - streak;
		float along = (p.x - head) / streak;
		float across = abs(fract(p.y / row_height) - 0.5) * row_height;
		float strength = step(0.0, along) * step(along, 1.0) * pow(1.0 - along, 2.0)
				* (1.0 - smoothstep(0.2, 0.9, across));
		vec3 colour = hash(row + 5.0) > 0.55 ? second.rgb : vec3(1.0);
		result = over(result, colour, strength * mix(0.5, 0.2, inside) * sweep);
	}

	// lines along the panel's edge
	float d = p.x - edge;
	result = over(result, accent.rgb, line(d, unit * 0.45, unit * 0.55));
	result = over(result, second.rgb, line(d, unit * 1.6, max(unit * 0.16, 1.0)) * 0.8);
	result = over(result, vec3(1.0), line(d, unit * 2.6, max(unit * 0.1, 1.0)) * 0.25);

	// the bar along the bottom
	float bar = smoothstep(size.y - footer - 0.5, size.y - footer + 0.5, p.y);
	result = over(result, ink.rgb, bar * 0.93 * sweep);
	result = over(result, second.rgb, line(p.y, size.y - footer, max(unit * 0.12, 1.0)) * 0.55 * sweep);
	float block = step(p.x, unit * 14.0) * line(p.y, size.y - footer + unit * 0.25, unit * 0.5);
	result = over(result, accent.rgb, block * sweep);

	COLOR = result;
}
