shader_type canvas_item;

uniform vec2 camera_position;
uniform vec2 viewport_size;
uniform vec2 spotlight_center;       // player world position
uniform float spotlight_radius_x = 200.0;
uniform float spotlight_radius_y = 150.0;
uniform float edge_softness = 0.1;

void fragment() {
	// Calculate the world position of this pixel on the screen
	vec2 world_pos = camera_position - viewport_size * 0.5 + UV * viewport_size;

	vec2 offset = (world_pos - spotlight_center) / vec2(spotlight_radius_x, spotlight_radius_y);
	float dist = length(offset);
	float mask = 1.0 - smoothstep(1.0 - edge_softness, 1.0 + edge_softness, dist);

	// Black overlay where no light, transparent where light
	COLOR = vec4(vec3(0.0), 1.0 - mask);
}