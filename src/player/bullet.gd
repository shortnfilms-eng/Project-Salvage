extends Area2D

@export var speed: float = 800.0
@export var damage: float = 10.0
@export var lifetime: float = 3.0
@export var is_player_bullet: bool = true

var velocity: Vector2


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	velocity = Vector2.RIGHT.rotated(rotation) * speed
	await get_tree().create_timer(lifetime).timeout
	queue_free()


func setup_collision() -> void:
	# Clear any old shapes
	for child in get_children():
		if child is CollisionShape2D:
			child.queue_free()

	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	add_child(shape)

	if is_player_bullet:
		collision_layer = 16
		collision_mask = 2         # should hit enemies (layer 2)
	else:
		collision_layer = 16
		collision_mask = 1         # should hit player (layer 1)


func _physics_process(delta: float) -> void:
	position += velocity * delta

	# ---------- DIAGNOSTIC PRINTS ----------
	var enemies = get_tree().get_nodes_in_group("enemy")
	if enemies.size() > 0:
		var _e = enemies[0]


func _on_body_entered(body: Node2D) -> void:
	if is_player_bullet:
		CombatSystem.deal_damage(body, damage, self)
	else:
		CombatSystem.deal_damage(body, damage, self)
	queue_free()
