extends AreaBase

# ============================================================
# Exports specific to the Asteroid Field
# ============================================================

@export_dir var area_folder: String = "res://assets/space/areas/asteroid_field/"

# Asteroid‑specific densities
@export var playfield_asteroid_density: float = 0.08
@export var attractable_density: float = 0.03
@export var station_density: float = 0.02
@export var enemy_density: float = 0.02

# Asteroid spacing
@export var asteroid_min_spacing: int = 2
@export var station_min_spacing: int = 4

# Internal texture storage
var deep_space_textures: Array[Texture2D] = []
var far_nebula_textures: Array[Texture2D] = []
var mid_field_textures: Array[Texture2D] = []
var near_field_textures: Array[Texture2D] = []
var playfield_textures: Array[Texture2D] = []
var station_textures: Array[Texture2D] = []
var attractable_textures: Array[Texture2D] = []
var entry_marker_texture: Texture2D = null
var exit_marker_texture: Texture2D = null


# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	_load_area_assets()
	super._ready()          # builds scene, generates visuals & physics


func _load_area_assets() -> void:
	deep_space_textures   = _load_folder(area_folder + "deep_space/")
	far_nebula_textures   = _load_folder(area_folder + "far_nebula/")
	mid_field_textures    = _load_folder(area_folder + "mid_field/")
	near_field_textures   = _load_folder(area_folder + "near_field/")
	playfield_textures    = _load_folder(area_folder + "playfield/")
	station_textures      = _load_folder(area_folder + "stations/")
	attractable_textures  = _load_folder(area_folder + "attractable/")
	border_textures       = _load_folder(area_folder + "border/")
	belt_textures         = _load_folder(area_folder + "belts/")
	entry_marker_texture  = _load_texture(area_folder + "entry_marker.png")
	exit_marker_texture   = _load_texture(area_folder + "exit_marker.png")

func _load_texture(file_path: String) -> Texture2D:
	if ResourceLoader.exists(file_path): return load(file_path)
	return null

func _load_folder(folder_path: String) -> Array[Texture2D]:
	var arr: Array[Texture2D] = []
	var dir = DirAccess.open(folder_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".png") and not file_name.begins_with("."):
				var full_path = folder_path + file_name
				var tex = load(full_path)
				if tex: arr.append(tex)
			file_name = dir.get_next()
		dir.list_dir_end()
	return arr


# ============================================================
# Virtual overrides – supply area‑specific data
# ============================================================

func _get_layer_textures(layer_name: String) -> Array[Texture2D]:
	match layer_name:
		"DeepSpace": return deep_space_textures
		"FarNebula": return far_nebula_textures
		"MidField":  return mid_field_textures
		"NearField": return near_field_textures
	return []


func _get_layer_configs() -> Array:
	return [
		{ "name": "DeepSpace", "scale": Vector2(0.3, 0.5), "density": 0.075, "parallax": parallax_factors[0] },
		{ "name": "FarNebula", "scale": Vector2(0.5, 0.8), "density": 0.075, "parallax": parallax_factors[1] },
		{ "name": "MidField",  "scale": Vector2(0.8, 1.0), "density": 0.075, "parallax": parallax_factors[2] },
		{ "name": "NearField", "scale": Vector2(1.0, 1.2), "density": 0.075, "parallax": parallax_factors[3] },
	]


func _get_entry_cell() -> Vector2i: return entry_cell
func _get_exit_cell()  -> Vector2i: return exit_cell


func _place_entry_exit(rng: RandomNumberGenerator) -> void:
	var valid_cells: Array[Vector2i] = []
	var margin = border_width + 2
	for y in range(margin, map_height - margin):
		for x in range(margin, map_width - margin):
			valid_cells.append(Vector2i(x, y))

	if valid_cells.size() < 2: return

	var found = false
	for _attempt in range(100):
		var idx1 = rng.randi_range(0, valid_cells.size() - 1)
		var idx2 = rng.randi_range(0, valid_cells.size() - 1)
		if idx1 == idx2: continue
		var c1 = valid_cells[idx1]
		var c2 = valid_cells[idx2]
		var dist = abs(c1.x - c2.x) + abs(c1.y - c2.y)
		if dist >= 15 and dist <= 50:
			entry_cell = c1; exit_cell = c2; found = true; break
	if not found:
		entry_cell = valid_cells[0]; exit_cell = valid_cells[valid_cells.size() - 1]


func _get_entry_marker_texture() -> Texture2D: return entry_marker_texture
func _get_exit_marker_texture()  -> Texture2D: return exit_marker_texture


# ============================================================
# Physics spawning
# ============================================================

func _scatter_physics_in_chunk(parent: Node2D, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	_scatter_asteroids(parent, rect, rng)
	_scatter_attractable(parent, rect, rng)
	_scatter_enemies(parent, rect, rng)
	_place_stations(parent, rect, rng)


func _scatter_asteroids(parent: Node2D, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	if playfield_textures.is_empty() or playfield_asteroid_density <= 0.0: return
	var margin = border_width + 2
	for y in range(max(rect.position.y, margin), min(rect.end.y, map_height - margin)):
		for x in range(max(rect.position.x, margin), min(rect.end.x, map_width - margin)):
			var cell = Vector2i(x, y)
			if _is_cell_safe(x, y) or blocked_cells.has(cell): continue
			if rng.randf() < playfield_asteroid_density:
				var tex = playfield_textures[rng.randi() % playfield_textures.size()]
				var s = Sprite2D.new(); s.texture = tex; s.centered = true
				var off_x = rng.randf_range(-cell_size * 0.4, cell_size * 0.4)
				var off_y = rng.randf_range(-cell_size * 0.4, cell_size * 0.4)
				s.position = Vector2(x * cell_size + cell_size * 0.5 + off_x, y * cell_size + cell_size * 0.5 + off_y)
				s.scale = Vector2(rng.randf_range(1.0, 1.2), rng.randf_range(1.0, 1.2))
				parent.add_child(s)

				var body = StaticBody2D.new()
				body.collision_layer = 4; body.position = s.position
				var collision = CollisionShape2D.new()
				var circle = CircleShape2D.new()
				circle.radius = tex.get_width() * s.scale.x * 0.5
				collision.shape = circle
				body.add_child(collision)
				parent.add_child(body)

				var radius_cells = ceil(circle.radius / float(cell_size))
				for dy in range(-radius_cells, radius_cells + 1):
					for dx in range(-radius_cells, radius_cells + 1):
						var bx = x + dx; var by = y + dy
						if bx >= 0 and bx < map_width and by >= 0 and by < map_height:
							blocked_cells[Vector2i(bx, by)] = true


func _scatter_attractable(parent: Node2D, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	if attractable_textures.is_empty() or attractable_density <= 0.0: return
	var margin = border_width + 2
	for y in range(max(rect.position.y, margin), min(rect.end.y, map_height - margin)):
		for x in range(max(rect.position.x, margin), min(rect.end.x, map_width - margin)):
			var cell = Vector2i(x, y)
			if _is_cell_safe(x, y) or blocked_cells.has(cell): continue
			if rng.randf() < attractable_density:
				var tex = attractable_textures[rng.randi() % attractable_textures.size()]
				var body = RigidBody2D.new()
				body.collision_layer = 8; body.collision_mask = 7
				body.gravity_scale = 0.0; body.mass = 0.1; body.linear_damp = 0.2; body.angular_damp = 3.0
				body.position = Vector2(x * cell_size + cell_size * 0.5, y * cell_size + cell_size * 0.5)

				var sprite = Sprite2D.new(); sprite.texture = tex; sprite.centered = true
				var sc = rng.randf_range(0.3, 0.7)
				sprite.scale = Vector2(sc, sc)
				body.add_child(sprite)

				var shape = CircleShape2D.new()
				shape.radius = tex.get_width() * sc * 0.5
				var collision = CollisionShape2D.new(); collision.shape = shape
				body.add_child(collision)

				parent.add_child(body)
				blocked_cells[cell] = true


func _scatter_enemies(parent: Node2D, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	if enemy_density <= 0.0 or not enemy_spawner: return
	# Use the enemy spawner node
	enemy_spawner.spawn_in_chunk(rect, rng, enemy_density, self)


func _place_stations(parent: Node2D, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	if station_textures.is_empty(): return
	var margin = border_width + 2
	for y in range(max(rect.position.y, margin), min(rect.end.y, map_height - margin)):
		for x in range(max(rect.position.x, margin), min(rect.end.x, map_width - margin)):
			var cell = Vector2i(x, y)
			if _is_cell_safe(x, y) or blocked_cells.has(cell): continue
			if rng.randf() < station_density:
				var tex = station_textures[rng.randi() % station_textures.size()]
				var s = Sprite2D.new(); s.texture = tex; s.centered = true
				s.position = Vector2(x * cell_size + cell_size * 0.5, y * cell_size + cell_size * 0.5)
				parent.add_child(s)

				var radius_x = ceil(tex.get_width() / (2.0 * cell_size))
				var radius_y = ceil(tex.get_height() / (2.0 * cell_size))
				for dy in range(-radius_y, radius_y + 1):
					for dx in range(-radius_x, radius_x + 1):
						var bx = x + dx; var by = y + dy
						if bx >= 0 and bx < map_width and by >= 0 and by < map_height:
							blocked_cells[Vector2i(bx, by)] = true


# ============================================================
# Border and asteroid belts (visual only, added once)
# ============================================================

func _load_border_and_belts() -> void:
	_generate_border()
	_generate_asteroid_belts()


func _generate_border() -> void:
	if border_textures.is_empty() or border_width <= 0: return

	var border_layer = Node2D.new()
	border_layer.name = "BorderLayer"
	border_layer.z_index = -1

	# Add to PLAYFIELD layer so it stays sharp
	if playfield_layer:
		playfield_layer.add_child(border_layer)
	else:
		add_child(border_layer)

	var rng = RandomNumberGenerator.new(); rng.seed = world_seed + 1
	var per_texture = {}
	var max_offset = cell_size * border_offset_strength * 0.5
	for y in range(-border_width, map_height + border_width):
		for x in range(-border_width, map_width + border_width):
			if x >= 0 and x < map_width and y >= 0 and y < map_height: continue
			var tex = border_textures[rng.randi() % border_textures.size()]
			var pos = Vector2(x * cell_size + cell_size * 0.5 + rng.randf_range(-max_offset, max_offset),
							  y * cell_size + cell_size * 0.5 + rng.randf_range(-max_offset, max_offset))
			if not per_texture.has(tex): per_texture[tex] = []
			per_texture[tex].append(pos)

	for tex in per_texture:
		var mmi = MultiMeshInstance2D.new()
		mmi.name = "Border_%s" % tex.resource_path.get_file().get_basename()
		border_layer.add_child(mmi)
		mmi.texture = tex
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.instance_count = per_texture[tex].size()
		mm.visible_instance_count = per_texture[tex].size()
		mm.mesh = _create_texture_quad(tex)
		mmi.multimesh = mm
		for i in range(per_texture[tex].size()):
			var pos = per_texture[tex][i]
			var rot = deg_to_rad(rng.randf_range(-border_rotation_range, border_rotation_range))
			mm.set_instance_transform_2d(i, Transform2D(rot, pos))
		if per_texture[tex].size() > 0:
			mm.set_instance_transform_2d(0, mm.get_instance_transform_2d(0))


func _generate_asteroid_belts() -> void:
	if belt_count <= 0 or belt_particle_steps <= 0 or belt_textures.is_empty(): return

	# Belts belong to the mid‑field layer (third parallax layer)
	var target_layer = parallax_layers[2] if parallax_layers.size() > 2 else null
	if not target_layer: return

	var rng = RandomNumberGenerator.new(); rng.seed = world_seed + 2
	var flow_noise = FastNoiseLite.new(); flow_noise.seed = world_seed + 3
	flow_noise.frequency = belt_noise_scale; flow_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	var per_texture = {}
	for _belt_idx in range(belt_count):
		var px = rng.randf_range(0, map_width - 1); var py = rng.randf_range(0, map_height - 1)
		var last_cell = Vector2i(-1, -1)
		for _step in range(belt_particle_steps):
			var cell = Vector2i(int(px), int(py))
			if cell.x < 0 or cell.x >= map_width or cell.y < 0 or cell.y >= map_height: break
			if cell != last_cell:
				last_cell = cell
				for dy in range(-belt_width, belt_width+1):
					for dx in range(-belt_width, belt_width+1):
						var nx = cell.x + dx; var ny = cell.y + dy
						if nx >= 0 and nx < map_width and ny >= 0 and ny < map_height:
							if rng.randf() < belt_object_density:
								var tex = belt_textures[rng.randi() % belt_textures.size()]
								var pos = Vector2(nx * cell_size + cell_size * 0.5 + rng.randf_range(-cell_size*0.5, cell_size*0.5),
												  ny * cell_size + cell_size * 0.5 + rng.randf_range(-cell_size*0.5, cell_size*0.5))
								if not per_texture.has(tex): per_texture[tex] = []
								per_texture[tex].append(pos)
			var h = flow_noise.get_noise_2d(px, py)
			var hx = flow_noise.get_noise_2d(px+0.5, py); var hy = flow_noise.get_noise_2d(px, py+0.5)
			var gradient = Vector2(hx-h, hy-h) * belt_gradient_strength / 0.5
			var dir = gradient.normalized() if gradient.length() > 0.001 else Vector2.DOWN
			px -= dir.x * 0.8; py -= dir.y * 0.8
			px += rng.randf_range(-0.3, 0.3); py += rng.randf_range(-0.3, 0.3)
	for tex in per_texture:
		var mmi = MultiMeshInstance2D.new()
		mmi.name = "Belt_%s" % tex.resource_path.get_file().get_basename()
		target_layer.add_child(mmi)
		mmi.texture = tex
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.instance_count = per_texture[tex].size()
		mm.visible_instance_count = per_texture[tex].size()
		mm.mesh = _create_texture_quad(tex)
		mmi.multimesh = mm
		for i in range(per_texture[tex].size()):
			var pos = per_texture[tex][i]
			var rot = deg_to_rad(rng.randf_range(-belt_rotation_range, belt_rotation_range))
			mm.set_instance_transform_2d(i, Transform2D(rot, pos))
		if per_texture[tex].size() > 0:
			mm.set_instance_transform_2d(0, mm.get_instance_transform_2d(0))
