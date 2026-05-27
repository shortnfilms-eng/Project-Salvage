extends Node2D

signal anchored(global_pos: Vector2, body: Node2D)
signal returned_to_player

@export var speed: float = 600.0
@export var return_speed: float = 400.0
@export var return_rotation_speed: float = 10.0

var direction: Vector2 = Vector2.ZERO
var max_distance: float = 500.0      # will be set by the player
var travelled: float = 0.0
var is_returning: bool = false
var is_anchored: bool = false
var is_stored: bool = true

@onready var area: Area2D = $HitBox
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	if area:
		if not area.body_entered.is_connected(_on_body_entered):
			area.body_entered.connect(_on_body_entered)
		area.collision_layer = 0
		area.collision_mask = 12          # detect layers 3 (asteroid) and 4 (attractable)
		area.monitoring = false
	sprite.show()


func launch(dir: Vector2, max_dist: float) -> void:
	is_stored = false
	direction = dir.normalized()
	max_distance = max_dist
	rotation = direction.angle()
	is_returning = false
	is_anchored = false
	travelled = 0.0
	if area:
		area.monitoring = true


func start_returning() -> void:
	is_anchored = false
	is_returning = true
	if area:
		area.set_deferred("monitoring", false)


func _physics_process(delta: float) -> void:
	if is_stored or is_anchored:
		return

	if not is_returning:
		var step = speed * delta
		position += direction * step
		travelled += step
		if travelled >= max_distance:
			is_returning = true
			if area:
				area.set_deferred("monitoring", false)
	else:
		var player = get_tree().get_first_node_in_group("player")
		if player:
			var to_player = player.global_position - global_position
			var dist = to_player.length()
			if dist < 10.0:
				emit_signal("returned_to_player")
				return
			position += to_player.normalized() * return_speed * delta
			var target_angle = to_player.angle() + PI
			rotation = lerp_angle(rotation, target_angle, return_rotation_speed * delta)


func _on_body_entered(body: Node2D) -> void:
	if is_anchored or is_returning or is_stored:
		return

	if body is RigidBody2D:
		call_deferred("_attach", body, global_position)
	else:
		call_deferred("_bounce")


func _attach(body: Node2D, hit_pos: Vector2) -> void:
	if is_anchored:
		return
	is_anchored = true
	if area:
		area.set_deferred("monitoring", false)

	var current_global_rot = global_rotation
	get_parent().remove_child(self)
	body.add_child(self)
	position = body.to_local(hit_pos)
	rotation = current_global_rot - body.global_rotation

	emit_signal("anchored", global_position, body)


func _bounce() -> void:
	is_returning = true
	if area:
		area.set_deferred("monitoring", false)
