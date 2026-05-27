shader_type canvas_item;

uniform float strength = 0.03;
uniform bool swap_axes = true;   // true = distort each axis by its own coordinate

void fragment() {
	vec2 uv = UV;
	float t = TIME * 20.8;

	if (swap_axes) {
		uv.x += sin(uv.x * 14.0 + t) * strength;
		uv.y += cos(uv.y * 12.0 + t * 0.7) * strength;
	} else {
		uv.x += sin(uv.y * 12.0 + t) * strength;
		uv.y += cos(uv.x * 14.0 + t * 0.7) * strength;
	}

	COLOR = texture(TEXTURE, uv);
}