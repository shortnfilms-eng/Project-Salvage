extends CharacterBody2D
class_name Player

# ============================================================
# Components (assign .tres resources in inspector)
# ============================================================

@export var propulsor_data: PropulsorData
@export var frame_data: FrameData
@export var weapon_right: WeaponData
@export var weapon_left: WeaponData
@export var weapon_scene: PackedScene

# Hook rope texture (will fix later)
@export var rope_texture: Texture2D

# ============================================================
# Hook system exports
# ============================================================

@export var hook_max_distance: float = 500.0
@export var tow_leash_length: float = 600.0
@export var rope_slack_length: float = 200.0
@export_range(4, 30) var rope_vertices: int = 15

# ============================================================
# Towed object deceleration (drag)
# ============================================================
@export_range(0.0, 10.0, 0.1) var towed_deceleration: float = 0.0

# ============================================================
# Other exports (tuning)
# ============================================================

@export var sprite_rotation_offset_degrees: float = 90.0
@export var look_ahead_max: float = 150.0
@export var look_ahead_smooth: float = 5.0
@export var shake_duration: float = 0.15
@export var shake_intensity_default: float = 3.0
@export var knockback_speed: float = 350.0
@export var knockback_duration: float = 0.15
@export var flash_duration: float = 0.1
@export var light_energy: float = 1.0
@export var light_texture_radius: int = 256
@export var hook_scene: PackedScene
@export var hook_cooldown: float = 0.8
@export var hook_recoil_distance: float = 10.0
@export var hook_recoil_return_speed: float = 10.0
@export var spotlight_radius_x: float = 1080.0
@export var spotlight_radius_y: float = 1080.0
@export var spotlight_edge_softness: float = 0.4

# ============================================================
# Node references (set at runtime)
# ============================================================

var propulsor_root: Node2D
var body_sprite: Sprite2D
var frame_root: Node2D
var turret_sprite: Sprite2D
var hook_frame: Sprite2D
var current_weapon: Node2D = null   # right weapon
var left_weapon: Node2D = null
var hook_muzzle: Marker2D
var camera: Camera2D
var darkness_overlay: ColorRect
var _engine_sprites: Array[Sprite2D] = []

var hook: Node2D = null
var is_hooked: bool = false
var attached_body: Node2D = null
var hook_attachment_offset: Vector2 = Vector2.ZERO
var hook_timer: float = 0.0
var rope: Line2D = null

var rope_points: Array[Vector2] = []
var rope_old: Array[Vector2] = []
var rope_base_seg_len: float = 0.0

var aim_direction: Vector2 = Vector2.RIGHT
var last_direction: Vector2 = Vector2.RIGHT

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector2 = Vector2.RIGHT
var current_leash_multiplier: float = 1.0

var shake_timer: float = 0.0
var current_shake_intensity: float = 0.0
var camera_look_offset: Vector2 = Vector2.ZERO

var knockback_velocity: Vector2 = Vector2.ZERO
var knockback_timer: float = 0.0

var original_body_modulate: Color
var original_turret_modulate: Color
var original_hook_frame_modulate: Color

var light: PointLight2D

var hook_recoil_offset: Vector2 = Vector2.ZERO

# Hook frame animation
var hook_frame_look_target: Vector2
var hook_frame_transitioning: bool = false
var hook_frame_transition_start: Vector2
var hook_frame_transition_timer: float = 0.0
var hook_frame_transition_duration: float = 0.2

# Flash helpers
var _original_modulates: Dictionary = {}
var _flash_tween: Tween = null

# Health
var max_health: float = 100.0
var health: float = 100.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 14

	camera = $Camera2D
	darkness_overlay = get_tree().get_first_node_in_group("darkness_overlay")
	hook_muzzle = $HookMuzzle
	hook_frame = $HookFrame

	_assemble_ship()
	_make_unshaded(propulsor_root)
	_setup_light()
	_setup_rope()
	_setup_hook()

	# Health initialisation
	if frame_data:
		max_health = frame_data.max_health
	else:
		max_health = 100.0
	health = max_health
	EventBus.player_health_changed.emit(health, max_health)

	# Record original modulates for hit flash
	_record_original_modulates(propulsor_root)
	_record_original_modulates(frame_root)
	if hook_frame:
		_record_original_modulates(hook_frame)

	# Rope texture (will fix later)
	if rope_texture and rope:
		rope.texture = rope_texture
		rope.texture_mode = Line2D.LINE_TEXTURE_TILE

	set_process(true)


func _assemble_ship():
	# 1. Propulsor (body + flames)
	var prop_mount = $PropulsorMount
	if propulsor_data and propulsor_data.scene:
		propulsor_root = propulsor_data.scene.instantiate()
		prop_mount.add_child(propulsor_root)

		body_sprite = propulsor_root.get_node("BodySprite") as Sprite2D
		if not body_sprite:
			push_warning("Propulsor scene missing 'BodySprite'. Creating default.")
			body_sprite = Sprite2D.new()
			body_sprite.name = "BodySprite"
			propulsor_root.add_child(body_sprite)

		_engine_sprites.clear()
		for child in propulsor_root.get_children():
			if child is Sprite2D and "Flame" in child.name:
				_engine_sprites.append(child)
	else:
		propulsor_root = Node2D.new()
		propulsor_root.name = "Propulsor"
		prop_mount.add_child(propulsor_root)
		body_sprite = Sprite2D.new()
		body_sprite.name = "BodySprite"
		propulsor_root.add_child(body_sprite)

	original_body_modulate = body_sprite.modulate

	# 2. Frame (turret + weapon mounts)
	var frame_mount = $FrameMount
	var weapon_mount: Marker2D

	if frame_data and frame_data.scene:
		frame_root = frame_data.scene.instantiate()
		frame_mount.add_child(frame_root)
		turret_sprite = frame_root.get_node("TurretSprite") as Sprite2D
		weapon_mount = frame_root.get_node("RightWeaponMount") as Marker2D
	else:
		frame_root = Node2D.new()
		frame_root.name = "Frame"
		frame_mount.add_child(frame_root)
		turret_sprite = Sprite2D.new()
		turret_sprite.name = "TurretSprite"
		frame_root.add_child(turret_sprite)
		weapon_mount = Marker2D.new()
		weapon_mount.name = "RightWeaponMount"
		frame_root.add_child(weapon_mount)

	original_turret_modulate = turret_sprite.modulate

	# 3. Right weapon
	if weapon_scene and weapon_right:
		current_weapon = weapon_scene.instantiate()
		weapon_mount.add_child(current_weapon)
		current_weapon.position = Vector2.ZERO
		current_weapon.weapon_data = weapon_right
		current_weapon.is_player_weapon = true

	# 4. Left weapon
	var left_mount = frame_root.get_node_or_null("LeftWeaponMount") as Marker2D
	if left_mount and weapon_scene:
		var left_data = weapon_left if weapon_left else weapon_right
		if left_data:
			left_weapon = weapon_scene.instantiate()
			left_mount.add_child(left_weapon)
			left_weapon.position = Vector2.ZERO
			left_weapon.weapon_data = left_data
			left_weapon.is_player_weapon = true
			left_weapon.scale.x = -1

	original_hook_frame_modulate = hook_frame.modulate


# ============================================================
# Light, Rope, Hook
# ============================================================

func _setup_light():
	light = PointLight2D.new()
	light.name = "Light2D"
	light.texture = _generate_radial_texture(light_texture_radius)
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.energy = light_energy
	light.z_index = -1
	add_child(light)

func _generate_radial_texture(radius: int) -> ImageTexture:
	var image = Image.create(radius * 2, radius * 2, false, Image.FORMAT_RGBA8)
	var center = Vector2(radius, radius)
	for y in range(radius * 2):
		for x in range(radius * 2):
			var dist = Vector2(x, y).distance_to(center) / radius
			var alpha = clamp(1.0 - dist, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(image)

func _setup_rope():
	rope = Line2D.new()
	rope.name = "Rope"
	rope.width = 8.0
	rope.default_color = Color(1, 1, 1, 1)   # white so texture appears
	rope.z_index = 3
	rope.joint_mode = Line2D.LINE_JOINT_ROUND
	rope.begin_cap_mode = Line2D.LINE_CAP_ROUND
	rope.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(rope)
	rope.show()
	_init_stored_rope()

func _init_stored_rope():
	rope_points.clear()
	rope_old.clear()
	var start = hook_muzzle.global_position
	var end = start + aim_direction * 10.0
	var total = start.distance_to(end)
	rope_base_seg_len = total / float(rope_vertices)
	for i in range(rope_vertices + 1):
		var t = float(i) / float(rope_vertices)
		rope_points.append(start.lerp(end, t))
		rope_old.append(rope_points[i])

func _init_rope() -> void:
	rope_points.clear()
	rope_old.clear()
	var start = hook_muzzle.global_position
	var end = hook.global_position
	var total_dist = start.distance_to(end)
	rope_base_seg_len = total_dist / float(rope_vertices)
	for i in range(rope_vertices + 1):
		var t = float(i) / float(rope_vertices)
		var pt = start.lerp(end, t)
		rope_points.append(pt)
		rope_old.append(pt)

func _setup_hook():
	if not hook_scene: return
	var hook_instance = hook_scene.instantiate()
	add_child(hook_instance)
	hook = hook_instance
	hook.position = hook_muzzle.position
	hook.is_stored = true
	hook.sprite.hide()

	if hook.has_signal("anchored"):
		hook.anchored.connect(_on_hook_anchored)
	if hook.has_signal("returned_to_player"):
		hook.returned_to_player.connect(_on_hook_returned)


# ============================================================
# Physics loop
# ============================================================

func _physics_process(delta: float) -> void:
	var input = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)

	hook_timer = max(0.0, hook_timer - delta)
	dash_cooldown_timer = max(0.0, dash_cooldown_timer - delta)

	var intended_velocity = Vector2.ZERO

	if knockback_timer > 0.0:
		knockback_timer -= delta
		velocity = knockback_velocity
	else:
		var max_speed = 300.0
		if Input.is_action_just_pressed("dash") and not is_dashing and dash_cooldown_timer <= 0.0:
			var dash_input = input.normalized() if input.length() > 0 else last_direction
			if dash_input.length() > 0:
				dash_direction = dash_input.normalized()
				is_dashing = true
				dash_timer = 0.2
				dash_cooldown_timer = 1.5
				current_leash_multiplier = 1.5
				apply_shake(shake_intensity_default * 2.0)

		current_leash_multiplier = lerp(current_leash_multiplier, 1.0, 2.0 * delta)

		if is_dashing:
			dash_timer -= delta
			if dash_timer <= 0.0: is_dashing = false
			velocity = dash_direction * 900.0
			intended_velocity = velocity
		else:
			velocity = input.normalized() * max_speed
			intended_velocity = velocity

	if velocity.length() > 10:
		last_direction = velocity.normalized()

	move_and_slide()

	if intended_velocity.length() > 10:
		propulsor_root.rotation = lerp_angle(propulsor_root.rotation,
			intended_velocity.angle() + deg_to_rad(sprite_rotation_offset_degrees), 8.0 * delta)

	if frame_root:
		var mouse_pos = get_global_mouse_position()
		var to_mouse = mouse_pos - frame_root.global_position
		if to_mouse.length() > 10.0:
			var target_angle = to_mouse.angle() + deg_to_rad(sprite_rotation_offset_degrees)
			frame_root.global_rotation = lerp_angle(frame_root.global_rotation, target_angle, 15.0 * delta)

	_update_engine_flames(delta, intended_velocity)
	_update_rope()
	_apply_towing(delta)
	_update_camera(delta)
	_update_turret_and_hook(delta)


# ============================================================
# Camera, shake, flash
# ============================================================

func _update_camera(delta: float) -> void:
	if not camera: return
	var mouse_pos = get_global_mouse_position()
	var to_mouse = mouse_pos - global_position
	var target_look_offset = Vector2.ZERO
	if to_mouse.length() > 1.0:
		target_look_offset = to_mouse.normalized() * min(to_mouse.length(), look_ahead_max)
	camera_look_offset = camera_look_offset.lerp(target_look_offset, look_ahead_smooth * delta)
	var shake_offset = Vector2.ZERO
	if shake_timer > 0:
		shake_timer = max(shake_timer - delta, 0.0)
		shake_offset = Vector2(randf_range(-1,1), randf_range(-1,1)) * current_shake_intensity
	camera.offset = camera_look_offset + shake_offset
	camera.rotation = 0.0

func apply_shake(intensity: float) -> void:
	shake_timer = shake_duration
	current_shake_intensity = intensity

func take_damage(amount: float, damage_source: Vector2):
	health -= amount
	if health < 0: health = 0
	EventBus.player_health_changed.emit(health, max_health)

	var dir = (global_position - damage_source).normalized()
	knockback_velocity = dir * knockback_speed
	knockback_timer = knockback_duration
	apply_shake(6.0)
	flash_hit()
	# Screen flash via EventBus
	EventBus.player_damaged.emit(Color(1, 1, 1, 1))   # white flash

	if health <= 0:
		# TODO: player death
		pass


# ---------- FLASH (recursive) ----------
func flash_hit():
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)

	_flash_with_original(propulsor_root)
	_flash_with_original(frame_root)
	if hook_frame:
		_flash_with_original(hook_frame)

	_flash_tween.finished.connect(func(): _flash_tween = null)


func _flash_with_original(node: Node) -> void:
	if node is Sprite2D and _original_modulates.has(node):
		var orig = _original_modulates[node]
		node.modulate = Color(4, 4, 4, 1)
		_flash_tween.tween_property(node, "modulate", orig, flash_duration)
	for child in node.get_children():
		_flash_with_original(child)


func _record_original_modulates(node: Node) -> void:
	if node is Sprite2D:
		_original_modulates[node] = node.modulate
	for child in node.get_children():
		_record_original_modulates(child)


func _make_unshaded(node: Node) -> void:
	if node is Sprite2D:
		if node.material == null:
			var mat = CanvasItemMaterial.new()
			mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			node.material = mat
	for child in node.get_children():
		_make_unshaded(child)


# ============================================================
# Towing, rope, engine flames (unchanged)
# ============================================================

func _apply_towing(delta: float) -> void:
	if not is_hooked or not attached_body is RigidBody2D: return
	var effective_leash = tow_leash_length * current_leash_multiplier
	var offset = attached_body.global_position - global_position
	var dist = offset.length()
	if dist > effective_leash:
		var direction = offset.normalized()
		attached_body.global_position = global_position + direction * effective_leash
		var radial_vel = (attached_body.linear_velocity - velocity).dot(direction) * direction
		attached_body.linear_velocity -= radial_vel
		if hook_attachment_offset.length() > 0.01:
			var to_player = (global_position - attached_body.global_position).normalized()
			var attach_local_angle = hook_attachment_offset.angle()
			var desired_angle = to_player.angle() - attach_local_angle
			var current_angle = attached_body.global_rotation
			var angle_diff = fmod(desired_angle - current_angle + PI, TAU) - PI
			var max_turn = deg_to_rad(180.0) * delta
			attached_body.angular_velocity = clamp(angle_diff, -max_turn, max_turn) / delta
		else:
			attached_body.angular_velocity = 0.0
	else:
		attached_body.angular_velocity *= 0.95

	if towed_deceleration > 0.0:
		attached_body.apply_central_force(-attached_body.linear_velocity * towed_deceleration)


func _update_rope() -> void:
	if is_hooked and attached_body is RigidBody2D:
		_update_slack_rope_physics()
	elif is_instance_valid(hook) and not hook.is_stored and not is_hooked:
		_update_rope_physics()
	else:
		_update_rope_physics()


func _update_slack_rope_physics() -> void:
	if not attached_body or not hook: return
	var start = hook_muzzle.global_position
	var end = hook.global_position
	if rope_points.size() != rope_vertices + 1:
		rope_points.clear(); rope_old.clear()
		for i in range(rope_vertices + 1):
			var t = float(i) / float(rope_vertices)
			rope_points.append(start.lerp(end, t))
			rope_old.append(rope_points[i])
	rope_points[0] = start; rope_points[rope_vertices] = end
	var damp = 0.995
	for i in range(1, rope_vertices):
		var vel = (rope_points[i] - rope_old[i]) * damp
		rope_old[i] = rope_points[i]
		rope_points[i] += vel
	var effective_max = rope_base_seg_len
	for _iter in range(5):
		for i in range(rope_vertices):
			var p1 = rope_points[i]; var p2 = rope_points[i+1]
			var d = p2 - p1; var dist = d.length()
			if dist < 0.001: continue
			if dist > effective_max:
				var correction = d * (dist - effective_max) / dist * 0.5
				if i > 0: rope_points[i] += correction
				if i < rope_vertices - 1: rope_points[i+1] -= correction


func _update_rope_physics() -> void:
	if rope_points.size() != rope_vertices + 1: return
	rope_points[0] = hook_muzzle.global_position
	if hook.is_stored:
		rope_points[rope_vertices] = hook_muzzle.global_position + aim_direction * 10.0
	else:
		rope_points[rope_vertices] = hook.global_position
	var damp = 0.995
	for i in range(1, rope_vertices):
		var vel = (rope_points[i] - rope_old[i]) * damp
		rope_old[i] = rope_points[i]
		rope_points[i] += vel
	var total_dist = rope_points[0].distance_to(rope_points[rope_vertices])
	var max_dist = rope_vertices * rope_base_seg_len
	var stiffness = int(lerp(4.0, 16.0, clamp(total_dist / max_dist, 0.0, 1.0)))
	for _iter in range(stiffness):
		for i in range(rope_vertices):
			var p1 = rope_points[i]; var p2 = rope_points[i+1]
			var d = p2 - p1; var dist = d.length()
			if dist < 0.001: continue
			var correction = d * (dist - rope_base_seg_len) / dist * 0.5
			if i > 0: rope_points[i] += correction
			if i < rope_vertices - 1: rope_points[i+1] -= correction


func _update_engine_flames(delta: float, move_velocity: Vector2) -> void:
	var target_scale = propulsor_data.engine_min_scale if propulsor_data else 0.3
	if is_dashing: target_scale = (propulsor_data.engine_max_scale if propulsor_data else 2.5) * 2.0
	elif move_velocity.length() > 10: target_scale = propulsor_data.engine_max_scale if propulsor_data else 2.5
	for sprite in _engine_sprites:
		var current = sprite.scale.x
		sprite.scale = Vector2.ONE * lerp(current, target_scale, (propulsor_data.engine_scale_speed if propulsor_data else 8.0) * delta)


# ============================================================
# Turret & Hook Frame (unchanged)
# ============================================================

func _update_turret_and_hook(delta: float) -> void:
	var base_pos = hook_muzzle.global_position
	hook_recoil_offset = hook_recoil_offset.lerp(Vector2.ZERO, hook_recoil_return_speed * delta)
	hook_frame.global_position = base_pos + hook_recoil_offset

	if hook_frame_transitioning:
		hook_frame_transition_timer += delta
		var factor = clamp(hook_frame_transition_timer / hook_frame_transition_duration, 0.0, 1.0)
		hook_frame_look_target = hook_frame_transition_start.lerp(get_global_mouse_position(), factor)
		if factor >= 1.0:
			hook_frame_transitioning = false
			hook_frame_look_target = get_global_mouse_position()
	else:
		if is_hooked and attached_body:
			hook_frame_look_target = hook.global_position
		else:
			hook_frame_look_target = get_global_mouse_position()

	hook_frame.look_at(hook_frame_look_target)
	hook_frame.rotate(deg_to_rad(sprite_rotation_offset_degrees))

	if Input.is_action_pressed("shoot_right") and current_weapon:
		current_weapon.shoot()
		apply_shake(shake_intensity_default * 0.3)

	if Input.is_action_pressed("shoot_left") and left_weapon:
		left_weapon.shoot()
		apply_shake(shake_intensity_default * 0.3)

	if Input.is_action_just_pressed("hook"):
		if is_hooked: release_hook()
		elif hook and hook.is_stored and hook_timer <= 0.0: shoot_hook()


# ============================================================
# Hook actions (unchanged)
# ============================================================

func shoot_hook() -> void:
	if not hook: return
	if hook.is_stored:
		remove_child(hook)
		get_parent().add_child(hook)
		hook.global_position = hook_muzzle.global_position
	hook.sprite.show()
	var dir = (get_global_mouse_position() - global_position).normalized()
	hook.launch(dir, hook_max_distance)
	hook_timer = hook_cooldown
	_init_rope()
	hook_recoil_offset = -dir * hook_recoil_distance
	apply_shake(shake_intensity_default * 1.5)


func _on_hook_anchored(global_pos: Vector2, body: Node2D):
	hook_frame_transitioning = false
	is_hooked = true; attached_body = body
	if body is RigidBody2D:
		hook_attachment_offset = hook.position
		rope_base_seg_len = rope_slack_length / float(rope_vertices)
		var start = hook_muzzle.global_position; var end = hook.global_position
		rope_points.clear(); rope_old.clear()
		for i in range(rope_vertices + 1):
			var t = float(i) / float(rope_vertices)
			rope_points.append(start.lerp(end, t))
			rope_old.append(rope_points[i])


func _on_hook_returned():
	if hook:
		hook.get_parent().remove_child(hook)
		add_child(hook)
		hook.position = hook_muzzle.position
		hook.is_stored = true
		hook.sprite.hide()
		_init_stored_rope()


func release_hook():
	if not hook: return
	if hook.get_parent() != get_parent():
		var world_pos = hook.global_position
		hook.get_parent().remove_child(hook)
		get_parent().add_child(hook)
		hook.global_position = world_pos

	hook_frame_transition_start = hook.global_position
	hook_frame_transitioning = true
	hook_frame_transition_timer = 0.0

	hook.start_returning()
	is_hooked = false; attached_body = null


# ============================================================
# Rope drawing & darkness overlay (unchanged)
# ============================================================

func _process(_delta: float) -> void:
	if is_hooked and attached_body is RigidBody2D:
		_draw_rope()
	elif hook and not hook.is_stored:
		_draw_rope()
	else:
		_update_rope_physics()
		_draw_rope()
	_update_darkness_overlay()


func _draw_rope():
	rope.clear_points()
	for pt in rope_points: rope.add_point(to_local(pt))


func _update_darkness_overlay():
	if not darkness_overlay: return
	var mat: ShaderMaterial = darkness_overlay.material
	var cam = get_viewport().get_camera_2d()
	if cam:
		mat.set_shader_parameter("camera_position", cam.global_position)
		mat.set_shader_parameter("viewport_size", get_viewport().get_visible_rect().size)
		mat.set_shader_parameter("spotlight_center", global_position)
		mat.set_shader_parameter("spotlight_radius_x", spotlight_radius_x)
		mat.set_shader_parameter("spotlight_radius_y", spotlight_radius_y)
		mat.set_shader_parameter("edge_softness", spotlight_edge_softness)
