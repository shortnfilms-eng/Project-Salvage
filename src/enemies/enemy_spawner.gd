extends Node2D

@export var enemy_scene: PackedScene               # assign your enemy_base.tscn here
@export var enemy_datas: Array[EnemyData] = []


func spawn_enemy_at(pos: Vector2, data: EnemyData = null) -> Node2D:
	if not enemy_scene:
		push_error("EnemySpawner: no enemy_scene assigned.")
		return null

	var enemy = enemy_scene.instantiate()
	enemy.position = pos
	if data:
		enemy.enemy_data = data
	add_child(enemy)
	return enemy


func spawn_in_chunk(rect: Rect2i, rng: RandomNumberGenerator, density: float, generator: Node2D) -> void:
	if enemy_datas.is_empty():
		# Without data we can still spawn basic enemies using the fallback stats inside enemy.gd
		pass

	# Use the generator’s public methods – get margin from border_width variable if it exists
	var margin = 2
	if generator.has_method("get_border_width"):   # we'll add this method
		margin = generator.get_border_width() + 2
	else:
		# fallback: try to read the property directly
		margin = generator.get("border_width") + 2 if generator.get("border_width") else 2

	for y in range(max(rect.position.y, margin), min(rect.end.y, generator.map_height - margin), 5):
		for x in range(max(rect.position.x, margin), min(rect.end.x, generator.map_width - margin), 5):
			var cell = Vector2i(x, y)
			if generator.is_cell_safe(x, y) or generator.blocked_cells.has(cell):
				continue
			if rng.randf() < density:
				# Pick a random enemy data if available, else null (enemy.gd uses fallback stats)
				var data = null
				if enemy_datas.size() > 0:
					data = enemy_datas[randi() % enemy_datas.size()]
				spawn_enemy_at(generator.cell_to_world(cell), data)
