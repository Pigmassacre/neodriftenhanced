shader_type canvas_item;

// A row of a menu: a slanted bar with a stripe of colour at its left end.
// When the row is chosen it fills with the colour, with a shine going along
// it and a hatching at its right end.

// The size of the row, in pixels.
uniform vec2 size = vec2(400.0, 40.0);
// How far across the bar leans for each pixel up.
uniform float slant = 0.3;
// From 0 to 1 as the row is chosen.
uniform float chosen = 0.0;
// 1 just after the row is pressed, going to 0.
uniform float flash = 0.0;
uniform vec4 accent : source_color = vec4(1.0, 0.42, 0.08, 1.0);
uniform vec4 base : source_color = vec4(0.05, 0.07, 0.13, 0.62);
// The stripe at the left end, in pixels.
uniform float stripe = 4.0;

void fragment() {
	vec2 p = UV * size;
	float left = (size.y - p.y) * slant;
	float right = size.x - p.y * slant;
	float inside = smoothstep(left - 0.75, left + 0.75, p.x) * (1.0 - smoothstep(right - 0.75, right + 0.75, p.x));
	float along = clamp((p.x - left) / max(right - left, 1.0), 0.0, 1.0);

	// as it is when not chosen: fading towards its right end
	vec4 colour = vec4(base.rgb, base.a * mix(1.0, 0.45, along));
	float on_stripe = 1.0 - smoothstep(stripe - 0.75, stripe + 0.75, p.x - left);
	colour = mix(colour, vec4(accent.rgb, 0.9), on_stripe * (1.0 - chosen));

	// chosen: the colour, lighter at the top, a hatching and a shine
	vec3 fill = accent.rgb * mix(1.12, 0.88, UV.y);
	float hatch = smoothstep(0.45, 0.55, fract((p.x + p.y * slant) / (size.y * 0.32)));
	fill = mix(fill, fill * 0.8, hatch * smoothstep(0.72, 0.95, along));
	float at = mix(-0.3, 1.6, fract(TIME * 0.45)) * size.x;
	float from_shine = abs(p.x + p.y * slant - at);
	fill = mix(fill, vec3(1.0), (1.0 - smoothstep(0.0, size.y * 1.2, from_shine)) * 0.35);
	fill = mix(fill, vec3(1.0), flash * 0.7);
	colour = mix(colour, vec4(fill, 1.0), chosen);

	COLOR = vec4(colour.rgb, colour.a * inside);
}
