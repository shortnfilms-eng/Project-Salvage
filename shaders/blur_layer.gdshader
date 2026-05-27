shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 5.0) = 2.0;

// Overlay controls
uniform vec4 overlay_color : source_color = vec4(0.001, 0.019, 0.09, 1.0);   // pick any color
uniform float overlay_amount : hint_range(0.0, 1.0) = 0.4;               // 0 = no overlay, 1 = full color

void fragment() {
    // Sample the blurred screen
    vec4 screen = textureLod(screen_texture, SCREEN_UV, blur_amount);

    // Blend between the screen and the overlay color
    vec4 final_color = mix(screen, overlay_color, overlay_amount);

    COLOR = final_color;
}