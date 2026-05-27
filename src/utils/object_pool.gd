extends Node

static var bullet_pools: Dictionary = {}   # PackedScene -> Array[Node2D]

func get_bullet(scene: PackedScene) -> Node2D:
	if not bullet_pools.has(scene):
		bullet_pools[scene] = []

	var pool = bullet_pools[scene]
	for bullet in pool:
		if not is_instance_valid(bullet) or bullet.is_queued_for_deletion():
			pool.erase(bullet)
			continue
		if not bullet.visible:
			bullet.visible = true
			return bullet

	# None available – create a new one
	var new_bullet = scene.instantiate()
	pool.append(new_bullet)
	return new_bullet

static func return_bullet(bullet: Node2D) -> void:
	bullet.visible = false
	bullet.set_process(false)
	bullet.set_physics_process(false)
	# Keep it in the pool, don't free
