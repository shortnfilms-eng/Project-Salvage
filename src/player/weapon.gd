extends Node2D
class_name Weapon

@export var weapon_data: WeaponData
@export var muzzle_marker: Marker2D

# Muzzle flash
@export var muzzle_flash_duration: float = 0.05
@export var muzzle_light_energy: float = 2.0

var time_since_last_shot: float = 0.0
var recoil_offset: Vector2 = Vector2.ZERO
var base_position: Vector2

var is_player_weapon: bool = false
var aim_target: Vector2 = Vector2.INF

# Muzzle nodes
var _muzzle_sprite: Sprite2D = null
var _muzzle_light: PointLight2D = null
var _muzzle_tween: Tween = null


func _ready():
	if muzzle_marker == null:
		muzzle_marker = get_node("Muzzle") as Marker2D
	base_position = position
	time_since_last_shot = 1.0 / get_fire_rate()

	# Find muzzle flash nodes
	_muzzle_sprite = get_node_or_null("MuzzleFlash") as Sprite2D
	_muzzle_light = get_node_or_null("MuzzleLight") as PointLight2D
	if _muzzle_sprite:
		_muzzle_sprite.visible = false
	if _muzzle_light:
		_muzzle_light.energy = 0.0


func get_fire_rate() -> float:
	return weapon_data.fire_rate if weapon_data else 5.0


func shoot() -> void:
	if time_since_last_shot < 1.0 / get_fire_rate():
		return
	time_since_last_shot = 0.0

	if weapon_data == null or weapon_data.bullet_scene == null:
		return

	var bullet = weapon_data.bullet_scene.instantiate()
	bullet.global_position = muzzle_marker.global_position
	bullet.is_player_bullet = is_player_weapon
	bullet.setup_collision()

	var target_point = aim_target if aim_target != Vector2.INF else get_global_mouse_position()
	var direction_to_target = (target_point - muzzle_marker.global_position).normalized()
	var bullet_angle = direction_to_target.angle()
	bullet.rotation = bullet_angle

	if weapon_data.spread_degrees > 0:
		bullet.rotation += deg_to_rad(randf_range(-weapon_data.spread_degrees, weapon_data.spread_degrees))

	bullet.speed = weapon_data.bullet_speed
	bullet.damage = weapon_data.damage

	var parent_layer = _find_canvas_layer(get_parent())
	if parent_layer:
		parent_layer.add_child(bullet)
	else:
		get_tree().root.add_child(bullet)

	bullet.z_index = 100

	# Recoil
	var local_backward = Vector2(0, 1).rotated(global_rotation)
	local_backward = global_transform.basis_xform_inv(local_backward).normalized()
	recoil_offset = local_backward * 6.0

	# Muzzle flash
	_trigger_muzzle_flash()


func _trigger_muzzle_flash() -> void:
	# Cancel previous flash tween if still running
	if _muzzle_tween and _muzzle_tween.is_valid():
		_muzzle_tween.kill()
	_muzzle_tween = null

	if _muzzle_sprite:
		_muzzle_sprite.visible = true
	if _muzzle_light:
		_muzzle_light.energy = muzzle_light_energy

	_muzzle_tween = create_tween()
	_muzzle_tween.tween_interval(muzzle_flash_duration)
	_muzzle_tween.tween_callback(_end_muzzle_flash)


func _end_muzzle_flash() -> void:
	if _muzzle_sprite:
		_muzzle_sprite.visible = false
	if _muzzle_light:
		_muzzle_light.energy = 0.0
	_muzzle_tween = null


func _find_canvas_layer(node: Node) -> CanvasLayer:
	var current = node
	while current:
		if current is CanvasLayer:
			return current as CanvasLayer
		current = current.get_parent()
	return null


func _process(delta: float) -> void:
	time_since_last_shot += delta
	recoil_offset = recoil_offset.lerp(Vector2.ZERO, 12.0 * delta)
	position = base_position + recoil_offset

	if muzzle_marker:
		var muzzle_pos = muzzle_marker.global_position
		var target_point = aim_target if aim_target != Vector2.INF else get_global_mouse_position()
		var dir = target_point - muzzle_pos
		if dir.length() > 1.0:
			global_rotation = dir.angle() + deg_to_rad(90)
