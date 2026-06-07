shader_type spatial;

// Scrolling belt surface — the texture moves along the belt's local Z (length
// axis) at scroll_speed metres-per-second-ish so the operator can SEE that the
// belt is running. scroll_speed = 0.0 freezes it, which is exactly what a
// stopped belt should look like.
//
// All three maps are sampled at the same tiled+scrolled UV: an albedo image
// (the rubber slat pattern), a roughness map that picks out the slats vs the
// flat web between them, and an optional normal map for subtle relief.

uniform sampler2D belt_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D belt_roughness : hint_roughness_r, repeat_enable;
uniform sampler2D belt_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal_map = true;

uniform float scroll_speed : hint_range(-5.0, 5.0) = 1.0;
uniform vec2 uv_tile = vec2(1.0, 5.0);   // x = across belt; y = along belt
uniform vec2 uv_offset = vec2(0.0, 0.0);

void fragment() {
	vec2 uv = UV * uv_tile + uv_offset + vec2(0.0, TIME * scroll_speed);
	ALBEDO = texture(belt_albedo, uv).rgb;
	ROUGHNESS = texture(belt_roughness, uv).r;
	METALLIC = 0.0;
	if (has_normal_map) {
		NORMAL_MAP = texture(belt_normal, uv).rgb;
	}
}
