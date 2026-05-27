extends CharacterBody2D
class_name Enemy

@export var enemy_data: EnemyData
@export var weapon_scene: PackedScene
@export var weapon_left: WeaponData

# Fallback exports
@export var fallback_wander_speed: float = 80.0
@export var fallback_combat_speed: float = 150.0
@export var fallback_fire_rate: float = 2.0
@export var fallback_patrol_radius: float = 250.0
@export var fallback_combat_min_range: float = 200.0
@export var fallback_combat_max_range: float = 350.0
@export var fallback_sight_range: float = 500.0
@export var fallback_knockback_speed: float = 250.0
@export var fallback_knockback_duration: float = 0.15
@export var flash_duration: float = 0.1

var body_sprite: Sprite2D
var turret: Node2D
var turret_sprite: Sprite2D
var weapon_mount: Marker2D
var current_weapon: Node2D = null
var left_weapon: Node2D = null
var player: Node2D = null
var time_since_last_shot: float = 0.0

var patrol_center: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var waiting: bool = false
var wait_timer: float = 0.0

enum State { PATROL, CHASE, ATTACK }
var state: State = State.PATROL
var state_timer: float = 0.0
var _lost_sight_timer: float = 0.0

var generator: Node2D
var _cell_size: int = 60

var _separation_push: Vector2 = Vector2.ZERO

var knockback_velocity: Vector2 = Vector2.ZERO
var knockback_timer: float = 0.0

var original_body_modulate: Color
var original_turret_modulate: Color

@export var avoidance_lookahead: float = 200.0
@export var avoidance_angle_range: float = 90.0
@export var avoidance_steps: int = 12
@export var separation_radius: float = 100.0
@export var separation_strength: float = 250.0
@export var arrive_slowing_radius: float = 150.0

var scan_dir: int = 1
var scan_timer: float = 0.0

var propulsor_root: Node2D
var _engine_sprites: Array[Sprite2D] = []

# Flash state
var _original_modulates: Dictionary = {}
var _flash_tween: Tween = null

# Health
var health: float = 30.0
var max_health: float = 30.0


func _ready():
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | 16

	_assemble_ship()
	_make_unshaded(propulsor_root)
	_find_player()
	generator = get_tree().get_first_node_in_group("world_generator")
	if generator: _cell_size = generator.cell_size

	original_body_modulate = body_sprite.modulate
	original_turret_modulate = turret_sprite.modulate

	time_since_last_shot = 1.0 / get_fire_rate()

	_engine_sprites.clear()
	if propulsor_root:
		for child in propulsor_root.get_children():
			if child is Sprite2D and "Flame" in child.name:
				_engine_sprites.append(child)

	_record_original_modulates(propulsor_root)
	_record_original_modulates(turret)

	if enemy_data and enemy_data.frame:
		max_health = enemy_data.frame.max_health
	else:
		max_health = 30.0
	health = max_health


func _assemble_ship():
	var prop_mount = $PropulsorMount
	if enemy_data and enemy_data.propulsor and enemy_data.propulsor.scene:
		propulsor_root = enemy_data.propulsor.scene.instantiate()
		prop_mount.add_child(propulsor_root)
		body_sprite = propulsor_root.get_node("BodySprite") as Sprite2D
	else:
		propulsor_root = Node2D.new(); propulsor_root.name = "Propulsor"
		prop_mount.add_child(propulsor_root)
		body_sprite = Sprite2D.new(); body_sprite.name = "BodySprite"
		propulsor_root.add_child(body_sprite)

	var frame_mount = $FrameMount
	if enemy_data and enemy_data.frame and enemy_data.frame.scene:
		frame_mount.add_child(enemy_data.frame.scene.instantiate())
		turret = frame_mount.get_child(0)
		turret_sprite = turret.get_node("TurretSprite") as Sprite2D
		weapon_mount = turret.get_node("RightWeaponMount") as Marker2D
	else:
		turret = Node2D.new(); turret.name = "Turret"
		frame_mount.add_child(turret)
		turret_sprite = Sprite2D.new(); turret_sprite.name = "TurretSprite"
		turret.add_child(turret_sprite)
		weapon_mount = Marker2D.new(); weapon_mount.name = "RightWeaponMount"
		turret.add_child(weapon_mount)

	if enemy_data and enemy_data.weapon_right and weapon_scene:
		current_weapon = weapon_scene.instantiate()
		weapon_mount.add_child(current_weapon)
		current_weapon.position = Vector2.ZERO
		current_weapon.weapon_data = enemy_data.weapon_right
		current_weapon.is_player_weapon = false

	var left_mount = turret.get_node_or_null("LeftWeaponMount") as Marker2D
	if left_mount and weapon_scene:
		var left_data = weapon_left if weapon_left else enemy_data.weapon_right
		if left_data:
			left_weapon = weapon_scene.instantiate()
			left_mount.add_child(left_weapon)
			left_weapon.position = Vector2.ZERO
			left_weapon.weapon_data = left_data
			left_weapon.is_player_weapon = false
			left_weapon.scale.x = -1


func _make_unshaded(node: Node) -> void:
	if node is Sprite2D:
		# Only apply unshaded material if the sprite doesn't already have one
		if node.material == null:
			var mat = CanvasItemMaterial.new()
			mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			node.material = mat
	for child in node.get_children():
		_make_unshaded(child)


func _record_original_modulates(node: Node) -> void:
	if node is Sprite2D:
		_original_modulates[node] = node.modulate
	for child in node.get_children():
		_record_original_modulates(child)


# Getters
func get_wander_speed() -> float:
	return enemy_data.wander_speed if enemy_data else fallback_wander_speed
func get_combat_speed() -> float:
	return enemy_data.combat_speed if enemy_data else fallback_combat_speed
func get_fire_rate() -> float:
	return enemy_data.fire_rate if enemy_data else fallback_fire_rate
func get_patrol_radius() -> float:
	return enemy_data.patrol_radius if enemy_data else fallback_patrol_radius
func get_combat_min_range() -> float:
	return enemy_data.combat_min_range if enemy_data else fallback_combat_min_range
func get_combat_max_range() -> float:
	return enemy_data.combat_max_range if enemy_data else fallback_combat_max_range
func get_sight_range() -> float:
	return enemy_data.sight_range if enemy_data else fallback_sight_range


func _physics_process(delta):
	_find_player()
	if player and global_position.distance_to(player.global_position) > 1500.0:
		velocity = Vector2.ZERO
		_update_propulsor(delta, Vector2.ZERO)
		return

	state_timer += delta

	var player_visible = player and global_position.distance_to(player.global_position) < get_sight_range()
	var dist_to_player = global_position.distance_to(player.global_position) if player else 9999.0

	match state:
		State.PATROL:
			if player_visible and state_timer >= 0.3: _switch_state(State.CHASE)
		State.CHASE:
			if not player_visible:
				_lost_sight_timer += delta
				if _lost_sight_timer >= 4.0 and state_timer >= 0.3: _switch_state(State.PATROL)
			else:
				_lost_sight_timer = 0.0
				if dist_to_player >= get_combat_min_range() and dist_to_player <= get_combat_max_range() and state_timer >= 0.3:
					_switch_state(State.ATTACK)
		State.ATTACK:
			if not player_visible:
				if state_timer >= 0.8: _switch_state(State.PATROL)
			else:
				if dist_to_player < get_combat_min_range() - 20 or dist_to_player > get_combat_max_range() + 30:
					if state_timer >= 0.8: _switch_state(State.CHASE)

	_calculate_separation()

	var ai_velocity = Vector2.ZERO

	if knockback_timer > 0.0:
		knockback_timer -= delta
		velocity = knockback_velocity
	else:
		match state:
			State.PATROL: ai_velocity = _patrol(delta)
			State.CHASE:  ai_velocity = _chase(delta)
			State.ATTACK: ai_velocity = _attack(delta)
		velocity = ai_velocity + _separation_push

	_turret_aim(delta)
	move_and_slide()

	_update_propulsor(delta, ai_velocity)


func _update_propulsor(delta: float, move_velocity: Vector2) -> void:
	if not propulsor_root: return
	if move_velocity.length() > 10:
		var target_angle = move_velocity.angle() + deg_to_rad(90)
		propulsor_root.rotation = lerp_angle(propulsor_root.rotation, target_angle, 8.0 * delta)

	var min_scale = 0.3; var max_scale = 2.5; var speed = 8.0
	if enemy_data and enemy_data.propulsor:
		min_scale = enemy_data.propulsor.engine_min_scale
		max_scale = enemy_data.propulsor.engine_max_scale
		speed = enemy_data.propulsor.engine_scale_speed

	var target_scale = min_scale
	if move_velocity.length() > 10: target_scale = max_scale

	for sprite in _engine_sprites:
		var current = sprite.scale.x
		sprite.scale = Vector2.ONE * lerp(current, target_scale, speed * delta)


func _switch_state(new_state: State):
	state = new_state
	state_timer = 0.0


func _patrol(delta) -> Vector2:
	if waiting:
		wait_timer -= delta
		if wait_timer <= 0.0:
			waiting = false
			_pick_waypoint()
		return Vector2.ZERO
	if global_position.distance_to(target_position) < 40.0:
		waiting = true; wait_timer = 2.0
		return Vector2.ZERO
	var desired_dir = (target_position - global_position).normalized()
	var avoid_dir = _get_avoidance_direction(desired_dir)
	return avoid_dir * get_wander_speed()


func _pick_waypoint():
	for _i in range(30):
		var offset = Vector2(randf_range(-1,1), randf_range(-1,1)).normalized() * randf() * get_patrol_radius()
		var candidate = patrol_center + offset
		if generator:
			var cell = generator.world_to_cell(candidate)
			if not generator.blocked_cells.has(cell) and not generator.safe_cells.has(cell):
				target_position = candidate
				return
	target_position = patrol_center


func _chase(_delta) -> Vector2:
	if not player: return Vector2.ZERO
	var to_player = player.global_position - global_position
	var dist = to_player.length()
	if dist < 0.01: return Vector2.ZERO
	var ideal_range = (get_combat_min_range() + get_combat_max_range()) * 0.5
	var target_point = player.global_position - to_player.normalized() * ideal_range
	var desired_dir = (target_point - global_position).normalized()
	if desired_dir.length() < 0.01: return Vector2.ZERO
	var speed = get_combat_speed()
	if to_player.length() < arrive_slowing_radius:
		speed *= (to_player.length() / arrive_slowing_radius)
		speed = max(speed, 20.0)
	var avoid_dir = _get_avoidance_direction(desired_dir)
	return avoid_dir * speed


func _attack(delta) -> Vector2:
	time_since_last_shot += delta
	if time_since_last_shot >= 1.0 / get_fire_rate():
		time_since_last_shot = 0.0
		if current_weapon: current_weapon.shoot()
		if left_weapon: left_weapon.shoot()
	return Vector2.ZERO


func _calculate_separation():
	_separation_push = Vector2.ZERO
	var enemies = get_tree().get_nodes_in_group("enemy")
	if enemies.size() <= 1: return
	for e in enemies:
		if e == self: continue
		var to_other = global_position - e.global_position
		var dist = to_other.length()
		if dist < separation_radius and dist > 0.001:
			var strength = (1.0 - dist / separation_radius)
			_separation_push += to_other.normalized() * strength * separation_strength
	_separation_push = _separation_push.limit_length(separation_strength)


func _get_avoidance_direction(desired_dir: Vector2) -> Vector2:
	if not generator: return desired_dir
	var best_dir = desired_dir
	var best_score = -1.0
	var step_angle = deg_to_rad(avoidance_angle_range * 2.0 / (avoidance_steps - 1))
	var start_angle = -deg_to_rad(avoidance_angle_range)
	for i in range(avoidance_steps):
		var angle = start_angle + step_angle * i
		var test_dir = desired_dir.rotated(angle)
		var ray_length = _cast_ray(test_dir)
		var score = ray_length + (1.0 - abs(angle) / deg_to_rad(avoidance_angle_range)) * avoidance_lookahead * 0.5
		if score > best_score:
			best_score = score
			best_dir = test_dir
	var blend = clamp(best_score / avoidance_lookahead, 0.0, 1.0)
	return desired_dir.lerp(best_dir, blend).normalized()


func _cast_ray(dir: Vector2) -> float:
	var step = _cell_size * 0.5
	var dist = 0.0
	while dist < avoidance_lookahead:
		var point = global_position + dir * dist
		var cell = generator.world_to_cell(point)
		if generator.blocked_cells.has(cell): return dist
		dist += step
	return avoidance_lookahead


# ---------- DAMAGE & DEATH ----------
func apply_knockback(direction: Vector2, strength: float):
	knockback_velocity = direction.normalized() * strength
	knockback_timer = fallback_knockback_duration
	flash_hit()


func take_damage(amount: float, damage_source: Vector2):
	if health <= 0: return
	health -= amount
	var dir = (global_position - damage_source).normalized()
	apply_knockback(dir, fallback_knockback_speed)
	if health <= 0:
		call_deferred("_deferred_die", damage_source)


func _deferred_die(damage_source: Vector2) -> void:
	# Kill any ongoing flash and reset sprites to original colors
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_reset_all_sprites(propulsor_root)
	_reset_all_sprites(turret)

	# Create wreck
	var wreck = RigidBody2D.new()
	wreck.collision_layer = 8
	wreck.collision_mask = 4
	wreck.gravity_scale = 0.0
	wreck.mass = 1.0
	wreck.linear_damp = 0.3
	wreck.angular_damp = 2.0
	wreck.position = global_position
	wreck.rotation = 0.0

	# Transfer sprites (flames are skipped; weapon parts tagged with metadata)
	_transfer_sprites(propulsor_root, wreck, false)
	_transfer_sprites(turret, wreck, false)

	# Collision shape for hook attachment
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	var tex_size = body_sprite.texture.get_size() * body_sprite.global_scale
	circle.radius = max(tex_size.x, tex_size.y) * 0.6
	shape.shape = circle
	wreck.add_child(shape)

	# Death impulse
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var push_dir = (global_position - damage_source).normalized()
	var push_strength = rng.randf_range(80.0, 150.0)
	wreck.linear_velocity = push_dir * push_strength
	wreck.angular_velocity = rng.randf_range(-5.0, 5.0)

	# Build dynamic rotation system for weapon sprites only
	var rotator = Node.new()
	rotator.name = "WreckRotator"
	var rot_script = GDScript.new()
	rot_script.source_code = """
extends Node

var weapon_data: Array = []   # each: { "sprite": Sprite2D, "offset": float, "current_angle": float }
var wobble_time: float = 0.0

func _process(delta):
	wobble_time += delta
	var hook = get_parent().get_node_or_null("Hook")
	var hook_pos = hook.position if hook else null

	for item in weapon_data:
		var sprite: Sprite2D = item.sprite
		if hook_pos:
			var dir = sprite.position - hook_pos
			if dir.length() > 0.01:
				# Target angle points away from the hook, plus personal offset
				var target_base = dir.angle() + PI + item.offset
				# Add wobble
				var wobble = sin(wobble_time * 5.0) * 0.15
				var target = target_base + wobble
				# Smoothly rotate
				item.current_angle = lerp_angle(item.current_angle, target, 10.0 * delta)
				sprite.rotation = item.current_angle
		# If no hook, rotation stays at current_angle (limp)
"""
	rot_script.reload()
	rotator.set_script(rot_script)

	# Populate weapon_data
	var weapon_data = []
	for child in wreck.get_children():
		if child is Sprite2D and child.has_meta("weapon_part"):
			var off = deg_to_rad(rng.randf_range(-10.0, 10.0))
			weapon_data.append({
				"sprite": child,
				"offset": off,
				"current_angle": child.rotation
			})
	rotator.weapon_data = weapon_data
	wreck.add_child(rotator)

	# Add to world
	var world = generator.world_container if generator and generator.world_container else get_parent()
	world.add_child(wreck)

	queue_free()
	EventBus.enemy_died.emit(wreck.position, enemy_data)


func _reset_all_sprites(node: Node) -> void:
	if node is Sprite2D and _original_modulates.has(node):
		node.modulate = _original_modulates[node]
	for child in node.get_children():
		_reset_all_sprites(child)


func _transfer_sprites(source: Node2D, target: RigidBody2D, is_weapon: bool = false) -> void:
	# If we've entered a weapon mount, all children are weapon parts
	if source.name in ["RightWeaponMount", "LeftWeaponMount"]:
		is_weapon = true

	for child in source.get_children():
		if child is Sprite2D:
			# Skip flame sprites
			if "Flame" in child.name:
				continue
			var new_sprite = Sprite2D.new()
			new_sprite.texture = child.texture
			new_sprite.scale = child.global_scale
			var rng = RandomNumberGenerator.new()
			rng.randomize()
			var random_angle = deg_to_rad(rng.randf_range(-15.0, 15.0))
			new_sprite.rotation = child.global_rotation + random_angle
			if _original_modulates.has(child):
				new_sprite.modulate = _original_modulates[child]
			else:
				new_sprite.modulate = child.modulate
			new_sprite.position = child.global_position - target.global_position
			if is_weapon:
				new_sprite.set_meta("weapon_part", true)
			target.add_child(new_sprite)
		elif child is Node2D:
			_transfer_sprites(child, target, is_weapon)


# ---------- FLASH ----------
func flash_hit():
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)

	_flash_with_original(propulsor_root)
	_flash_with_original(turret)

	_flash_tween.finished.connect(func(): _flash_tween = null)


func _flash_with_original(node: Node) -> void:
	if node is Sprite2D and _original_modulates.has(node):
		var orig = _original_modulates[node]
		node.modulate = Color(4, 4, 4, 1)
		_flash_tween.tween_property(node, "modulate", orig, flash_duration)
	for child in node.get_children():
		_flash_with_original(child)


# ---------- TURRET AIM ----------
func _turret_aim(delta):
	if not current_weapon and not left_weapon: return

	var target_pos = get_global_mouse_position()
	if player and state != State.PATROL:
		var player_vel = player.velocity if "velocity" in player else Vector2.ZERO
		var bullet_speed = 800.0
		var dist = global_position.distance_to(player.global_position)
		var lead_time = dist / bullet_speed
		target_pos = player.global_position + player_vel * lead_time * 0.5

		var aim = (target_pos - global_position).normalized()
		if aim.length() > 0.01:
			turret.global_rotation = lerp_angle(turret.global_rotation, aim.angle() + deg_to_rad(90), 5.0 * delta)
	else:
		scan_timer += delta
		if scan_timer > 2.0:
			scan_timer = 0.0
			scan_dir *= -1
		turret.global_rotation = lerp_angle(turret.global_rotation, deg_to_rad(60 * scan_dir) + body_sprite.rotation, 5.0 * delta)

	if current_weapon: current_weapon.aim_target = target_pos
	if left_weapon: left_weapon.aim_target = target_pos


func _find_player():
	if not player:
		player = get_tree().get_first_node_in_group("player")
