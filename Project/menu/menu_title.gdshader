shader_type canvas_item;

// A menu's title: the letters shade from white at the top to the colour at
// the bottom, with a shine going across them now and then. What is drawn
// dark (the letters' shadow) is left as it is.

// The size of the title, in pixels.
uniform vec2 box = vec2(400.0, 80.0);
uniform vec4 top : source_color = vec4(1.0);
uniform vec4 bottom : source_color = vec4(1.0, 0.68, 0.38, 1.0);
// How far across the shine leans for each pixel down.
uniform float slant = 0.25;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec4 colour = COLOR;
	if (max(colour.r, max(colour.g, colour.b)) > 0.5) {
		float down = clamp(local.y / box.y, 0.0, 1.0);
		vec3 shaded = mix(top.rgb, bottom.rgb, smoothstep(0.3, 0.95, down));
		float at = mix(-0.5, 2.5, fract(TIME * 0.18)) * box.x;
		float from_shine = abs(local.x + (box.y - local.y) * slant - at);
		shaded = mix(shaded, vec3(1.0), (1.0 - smoothstep(0.0, box.y * 0.6, from_shine)) * 0.85);
		colour.rgb = shaded;
	}
	COLOR = colour;
}
