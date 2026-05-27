extends Node2D
class_name AreaBase

# ============================================================
# Virtual helpers – override in subclasses
# ============================================================

func _get_layer_textures(_layer_name: String) -> Array[Texture2D]:
	push_error("_get_layer_textures not implemented")
	return []

func _get_layer_configs() -> Array:
	push_error("_get_layer_configs not implemented")
	return []

func _get_entry_cell() -> Vector2i:
	push_error("_get_entry_cell not implemented")
	return Vector2i.ZERO

func _get_exit_cell() -> Vector2i:
	push_error("_get_exit_cell not implemented")
	return Vector2i.ZERO

func _is_cell_safe(x: int, y: int) -> bool:
	return safe_cells.has(Vector2i(x, y))

func _scatter_physics_in_chunk(_parent: Node2D, _rect: Rect2i, _rng: RandomNumberGenerator) -> void:
	pass

# ============================================================
# Exports (world settings)
# ============================================================

@export var horizontal_screens: int = 2
@export var vertical_screens: int = 2
@export var cell_size: int = 60

@export var camera: Camera2D

@export var enable_drift: bool = true
@export var drift_speed_min: float = 0.5
@export var drift_speed_max: float = 2.0
@export var drift_update_every_frames: int = 3
@export var drift_active_distance: float = 3000.0   # only drift objects within this range of the camera

@export var chunk_size: int = 20
@export var load_radius: int = 3
@export var chunks_per_frame: int = 1
@export var world_seed: int = 0

@export var global_blur_amount: float = 2.0

@export var fog_intensity: float = 0.5
@export var fog_colors: Array[Color] = [
	Color(0.3, 0.3, 0.5),
	Color(0.4, 0.4, 0.6),
	Color(0.6, 0.6, 0.8),
	Color(0.8, 0.8, 0.9),
]

@export var parallax_factors: Array[float] = [0.9, 0.7, 0.5, 0.4]
@export var layer_rotation_range: float = 30.0

@export var spotlight_radius_x: float = 1080.0
@export var spotlight_radius_y: float = 1080.0
@export var spotlight_edge_softness: float = 0.4

@export var border_width: int = 2
@export var border_offset_strength: float = 0.4
@export var border_textures: Array[Texture2D] = []
@export var border_rotation_range: float = 5.0

@export var belt_count: int = 3
@export var belt_particle_steps: int = 150
@export var belt_width: int = 2
@export var belt_noise_scale: float = 0.02
@export var belt_gradient_strength: float = 1.0
@export var belt_object_density: float = 0.4
@export var belt_textures: Array[Texture2D] = []
@export var belt_rotation_range: float = 25.0

@export var player_scene_path: String = "res://player.tscn"

# ============================================================
# Internal state
# ============================================================

var map_width: int
var map_height: int
var entry_cell: Vector2i
var exit_cell: Vector2i
var safe_cells: Dictionary = {}
var blocked_cells: Dictionary = {}

var world_container: Node2D
var markers_layer: Node2D
var enemy_spawner: Node2D
var playfield_layer: CanvasLayer
var parallax_layers: Array[Node2D] = []
var _blur_material: ShaderMaterial

# ---------- DRIFT SYSTEM ----------
var _drift_entries: Array = []   # each: { "mmi": MultiMeshInstance2D, "velocities": Array[Vector2] }

var frame_count: int = 0

var physics_chunks: Dictionary = {}
var generation_queue: Array = []
var last_camera_chunk: Vector2i = Vector2i(-999, -999)
var _initial_physics_done: bool = false

var _shared_astar: AStarGrid2D


func _ready() -> void:
	_set_map_dimensions()
	_find_scene_nodes()
	_resize_black_background()
	_setup_blur()
	_setup_darkness()
	_load_border_and_belts()
	_compute_safe_path()
	_place_player()

	add_to_group("world_generator")

	_generate_all_visuals()

	if enable_drift:
		_build_drift_data()

	var start_chunk = world_to_chunk(cell_to_world(entry_cell))
	_generate_initial_physics(start_chunk)
	_initial_physics_done = true

	get_shared_astar()
	_set_camera_limits()

	set_process(true)


func _process(delta: float) -> void:
	if not camera: camera = get_viewport().get_camera_2d()
	if not camera: return

	var cam_center = camera.get_screen_center_position()
	var cam_chunk = world_to_chunk(cam_center)
	if cam_chunk != last_camera_chunk:
		last_camera_chunk = cam_chunk
		_update_physics_chunks(cam_chunk)

	if _initial_physics_done:
		for i in range(chunks_per_frame):
			if generation_queue.is_empty(): break
			var coord = generation_queue.pop_front()
			_generate_physics_chunk(coord)

	frame_count += 1
	if enable_drift and frame_count % drift_update_every_frames == 0:
		_update_drift(delta * drift_update_every_frames)

	_update_parallax()

	if _blur_material:
		_blur_material.set_shader_parameter("blur_amount", global_blur_amount)


# ============================================================
# DRIFT (every object drifts, frame‑skipped)
# ============================================================

func _build_drift_data() -> void:
	_drift_entries.clear()
	var configs = _get_layer_configs()
	for cfg in configs:
		var layer_node = _get_layer_container(cfg.get("name", ""))
		if not layer_node: continue
		for child in layer_node.get_children():
			if not child is MultiMeshInstance2D: continue
			var mmi = child as MultiMeshInstance2D
			var mm = mmi.multimesh
			if not mm or mm.instance_count == 0: continue

			var rng = RandomNumberGenerator.new()
			rng.seed = hash(world_seed) ^ hash(mmi.name)

			var velocities: Array[Vector2] = []
			velocities.resize(mm.instance_count)
			for i in mm.instance_count:
				var vel = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
				vel *= rng.randf_range(drift_speed_min, drift_speed_max)
				velocities[i] = vel

			_drift_entries.append({ "mmi": mmi, "velocities": velocities })


func _update_drift(delta: float) -> void:
	if not camera: return
	var cam_pos = camera.global_position
	var dist_sq = drift_active_distance * drift_active_distance

	for entry in _drift_entries:
		var mmi: MultiMeshInstance2D = entry.mmi
		# Cull: skip if the MMI's world origin is too far from the camera
		if mmi.global_position.distance_squared_to(cam_pos) > dist_sq:
			continue

		var mm: MultiMesh = mmi.multimesh
		var velocities: Array = entry.velocities
		var count = mm.instance_count
		for i in count:
			var trans = mm.get_instance_transform_2d(i)
			trans.origin += velocities[i] * delta
			mm.set_instance_transform_2d(i, trans)


# ============================================================
# Scene node lookup & setup
# ============================================================

func _find_scene_nodes() -> void:
	parallax_layers.clear()
	for name in ["DeepSpaceLayer", "FarNebulaLayer", "MidFieldLayer", "NearFieldLayer"]:
		var node = get_node_or_null(name) as Node2D
		if node:
			parallax_layers.append(node)
		else:
			push_error("Missing background layer: " + name)

	world_container = get_node_or_null("PlayfieldLayer/WorldContainer") as Node2D
	if not world_container:
		push_error("Missing PlayfieldLayer/WorldContainer")

	markers_layer = get_node_or_null("PlayfieldLayer/Markers") as Node2D
	if not markers_layer:
		push_error("Missing PlayfieldLayer/Markers")

	enemy_spawner = get_node_or_null("PlayfieldLayer/EnemySpawner")
	if not enemy_spawner:
		push_error("Missing PlayfieldLayer/EnemySpawner")

	var blur_layer = get_node_or_null("BlurLayer") as CanvasLayer
	if blur_layer:
		blur_layer.layer = 1
		blur_layer.follow_viewport_enabled = false

	var playfield_layer = get_node_or_null("PlayfieldLayer") as CanvasLayer
	if playfield_layer:
		self.playfield_layer = playfield_layer
		playfield_layer.layer = 2
		playfield_layer.follow_viewport_enabled = true
		playfield_layer.follow_viewport_scale = 1.0

	var darkness_layer = get_node_or_null("DarknessLayer") as CanvasLayer
	if darkness_layer:
		darkness_layer.layer = 3
		darkness_layer.follow_viewport_enabled = false


func _resize_black_background() -> void:
	var micro_clutter = get_node_or_null("MicroClutterLayer")
	if not micro_clutter: return
	var black_rect = micro_clutter.get_node_or_null("BlackBackground") as ColorRect
	if black_rect:
		black_rect.size = Vector2(map_width * cell_size, map_height * cell_size)
		black_rect.position = Vector2.ZERO


func _setup_blur() -> void:
	var blur_rect = get_node_or_null("BlurLayer/BlurOverlay") as ColorRect
	if not blur_rect: return
	_blur_material = ShaderMaterial.new()
	_blur_material.shader = load("res://shaders/blur_layer.gdshader")
	_blur_material.set_shader_parameter("blur_amount", global_blur_amount)
	blur_rect.material = _blur_material


func _setup_darkness() -> void:
	var darkness_rect = get_node_or_null("DarknessLayer/DarknessOverlay") as ColorRect
	if not darkness_rect: return
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec2 camera_position;
uniform vec2 viewport_size;
uniform vec2 spotlight_center;
uniform float spotlight_radius_x = 1080.0;
uniform float spotlight_radius_y = 1080.0;
uniform float edge_softness = 0.4;
void fragment() {
    vec2 world_pos = camera_position - viewport_size * 0.5 + UV * viewport_size;
    vec2 offset = (world_pos - spotlight_center) / vec2(spotlight_radius_x, spotlight_radius_y);
    float dist = length(offset);
    float mask = 1.0 - smoothstep(1.0 - edge_softness, 1.0 + edge_softness, dist);
    COLOR = vec4(vec3(0.0), 1.0 - mask);
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	darkness_rect.material = mat
	darkness_rect.add_to_group("darkness_overlay")


func _place_player() -> void:
	if entry_cell.x < 0 or not ResourceLoader.exists(player_scene_path): return
	var player_scene = load(player_scene_path)
	if player_scene:
		var player = player_scene.instantiate()
		player.position = cell_to_world(entry_cell)
		if playfield_layer:
			playfield_layer.add_child(player)
		else:
			add_child(player)


# ============================================================
# Map dimensions, safe path, markers
# ============================================================

func _set_map_dimensions() -> void:
	horizontal_screens = clamp(horizontal_screens, 1, 10)
	vertical_screens = clamp(vertical_screens, 1, 10)
	map_width = 32 * horizontal_screens
	map_height = 18 * vertical_screens

func _compute_safe_path() -> void:
	var global_rng = RandomNumberGenerator.new()
	global_rng.seed = world_seed
	_place_entry_exit(global_rng)
	if entry_cell.x < 0 or exit_cell.x < 0: return
	safe_cells.clear()
	var astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, map_width, map_height)
	astar.cell_size = Vector2(cell_size, cell_size)
	astar.update()
	var raw_path = astar.get_id_path(entry_cell, exit_cell)
	var safe_path_width = 3
	for cell in raw_path:
		for dy in range(-safe_path_width, safe_path_width + 1):
			for dx in range(-safe_path_width, safe_path_width + 1):
				var nx = cell.x + dx
				var ny = cell.y + dy
				if nx >= 0 and nx < map_width and ny >= 0 and ny < map_height:
					safe_cells[Vector2i(nx, ny)] = true
	_add_clear_radius(entry_cell, 5)
	_add_clear_radius(exit_cell, 5)
	_place_markers()

func _add_clear_radius(center: Vector2i, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var nx = center.x + dx
			var ny = center.y + dy
			if nx >= 0 and nx < map_width and ny >= 0 and ny < map_height:
				safe_cells[Vector2i(nx, ny)] = true

func _place_entry_exit(_rng: RandomNumberGenerator) -> void: pass

func _place_markers() -> void:
	_clear_container(markers_layer)
	if entry_cell.x >= 0:
		var s = Sprite2D.new()
		s.texture = _get_entry_marker_texture()
		s.centered = true
		s.position = cell_to_world(entry_cell)
		markers_layer.add_child(s)
	if exit_cell.x >= 0:
		var s = Sprite2D.new()
		s.texture = _get_exit_marker_texture()
		s.centered = true
		s.position = cell_to_world(exit_cell)
		markers_layer.add_child(s)

func _get_entry_marker_texture() -> Texture2D: return null
func _get_exit_marker_texture() -> Texture2D: return null


# ============================================================
# Coordinate helpers
# ============================================================

func world_to_chunk(world_pos: Vector2) -> Vector2i:
	var cell_x = int(world_pos.x) / cell_size
	var cell_y = int(world_pos.y) / cell_size
	return Vector2i(cell_x / chunk_size, cell_y / chunk_size)

func get_chunk_cells(chunk_coord: Vector2i) -> Rect2i:
	return Rect2i(chunk_coord * chunk_size, Vector2i(chunk_size, chunk_size))

func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size + cell_size * 0.5,
				   cell.y * cell_size + cell_size * 0.5)

func chunk_origin(chunk_coord: Vector2i) -> Vector2:
	return Vector2(chunk_coord.x * chunk_size * cell_size,
				   chunk_coord.y * chunk_size * cell_size)

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / cell_size), int(world_pos.y / cell_size))

func is_cell_safe(x: int, y: int) -> bool:
	return _is_cell_safe(x, y)

func get_shared_astar() -> AStarGrid2D:
	if _shared_astar: return _shared_astar
	_shared_astar = AStarGrid2D.new()
	_shared_astar.region = Rect2i(0, 0, map_width, map_height)
	_shared_astar.cell_size = Vector2(cell_size, cell_size)
	_shared_astar.update()
	for cell in blocked_cells: _shared_astar.set_point_solid(cell, true)
	return _shared_astar

func _set_camera_limits() -> void:
	if not camera: camera = get_viewport().get_camera_2d()
	if not camera: return
	var margin = int(cell_size * 0.5)
	camera.limit_left = -border_width * cell_size - margin
	camera.limit_top = -border_width * cell_size - margin
	camera.limit_right = (map_width + border_width) * cell_size + margin
	camera.limit_bottom = (map_height + border_width) * cell_size + margin


# ============================================================
# Visual generation
# ============================================================

func _generate_all_visuals():
	var chunks_x = ceil(float(map_width) / chunk_size)
	var chunks_y = ceil(float(map_height) / chunk_size)
	for cy in range(chunks_y):
		for cx in range(chunks_x):
			_generate_visuals_for_chunk(Vector2i(cx, cy))

func _generate_visuals_for_chunk(chunk_coord: Vector2i):
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(world_seed) ^ hash(chunk_coord.x) ^ hash(chunk_coord.y)
	var rect = get_chunk_cells(chunk_coord)
	var origin = chunk_origin(chunk_coord)
	var configs = _get_layer_configs()
	for cfg in configs:
		var textures = _get_layer_textures(cfg.get("name", ""))
		if textures.is_empty(): continue
		_populate_layer(chunk_coord, rect, origin, rng, cfg, textures)

func _create_texture_quad(tex: Texture2D) -> QuadMesh:
	var quad = QuadMesh.new()
	quad.size = tex.get_size() * Vector2(1, -1)
	return quad

func _populate_layer(chunk_coord: Vector2i, rect: Rect2i, origin: Vector2,
					  rng: RandomNumberGenerator, cfg: Dictionary, textures: Array[Texture2D]) -> void:
	var density: float = cfg.get("density", 0.1)
	var scale_range: Vector2 = cfg.get("scale", Vector2(1, 1))
	var target = _get_layer_container(cfg.get("name", ""))
	if not target: return

	var per_texture = {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if safe_cells.has(Vector2i(x, y)): continue
			if rng.randf() > density: continue
			var tex = textures[rng.randi() % textures.size()]
			var world_x = x * cell_size + cell_size * 0.5 + rng.randf_range(-cell_size * 0.4, cell_size * 0.4)
			var world_y = y * cell_size + cell_size * 0.5 + rng.randf_range(-cell_size * 0.4, cell_size * 0.4)
			var local_pos = Vector2(world_x, world_y) - origin
			var scale_val = rng.randf_range(scale_range.x, scale_range.y)
			var col = Color.WHITE
			var rot = deg_to_rad(rng.randf_range(-layer_rotation_range, layer_rotation_range))
			var final_scale = Vector2(scale_val, scale_val)
			var t = Transform2D(rot, local_pos).scaled(final_scale)
			if not per_texture.has(tex): per_texture[tex] = { "transforms": [], "colors": [] }
			per_texture[tex].transforms.append(t)
			per_texture[tex].colors.append(col)

	for tex in per_texture:
		var data = per_texture[tex]
		var instance_count = data.transforms.size()
		if instance_count == 0: continue
		var mmi = MultiMeshInstance2D.new()
		mmi.name = "%s_%s" % [cfg.get("name", "layer"), tex.resource_path.get_file().get_basename()]
		mmi.position = origin
		target.add_child(mmi)
		mmi.texture = tex
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.instance_count = instance_count
		mm.visible_instance_count = instance_count
		mm.mesh = _create_texture_quad(tex)
		mmi.multimesh = mm
		for i in instance_count:
			mm.set_instance_transform_2d(i, data.transforms[i])
			mm.set_instance_color(i, data.colors[i])
		if instance_count > 0:
			mm.set_instance_transform_2d(0, mm.get_instance_transform_2d(0))

func _get_layer_container(layer_name: String) -> Node2D:
	for group in parallax_layers:
		if group.name.begins_with(layer_name):
			return group
	return null


# ============================================================
# Border & asteroid belts (visual only, added once)
# ============================================================

func _load_border_and_belts() -> void:
	_generate_border()
	_generate_asteroid_belts()

func _generate_border() -> void:
	if border_textures.is_empty() or border_width <= 0: return

	var border_layer = Node2D.new()
	border_layer.name = "BorderLayer"
	border_layer.z_index = -1

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


# ============================================================
# Physics chunks (loading / unloading)
# ============================================================

func _generate_initial_physics(center: Vector2i):
	var wanted = {}
	for dx in range(-load_radius, load_radius + 1):
		for dy in range(-load_radius, load_radius + 1):
			var coord = center + Vector2i(dx, dy)
			wanted[coord] = true
	for coord in wanted.keys():
		if not physics_chunks.has(coord):
			_generate_physics_chunk(coord)

func _update_physics_chunks(center_chunk: Vector2i):
	var wanted = {}
	for dx in range(-load_radius, load_radius + 1):
		for dy in range(-load_radius, load_radius + 1):
			var coord = center_chunk + Vector2i(dx, dy)
			wanted[coord] = true
	for coord in physics_chunks.keys():
		if not wanted.has(coord): _unload_physics_chunk(coord)
	for coord in wanted.keys():
		if not physics_chunks.has(coord) and coord not in generation_queue:
			generation_queue.append(coord)

func _generate_physics_chunk(chunk_coord: Vector2i):
	var container = Node2D.new()
	container.name = "PhysicsChunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	world_container.add_child(container)
	physics_chunks[chunk_coord] = container
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(world_seed) ^ hash(chunk_coord.x) ^ hash(chunk_coord.y)
	var rect = get_chunk_cells(chunk_coord)
	_scatter_physics_in_chunk(container, rect, rng)
	_clear_safe_cells_from_container(container)

func _unload_physics_chunk(chunk_coord: Vector2i):
	var container = physics_chunks.get(chunk_coord)
	if not container: return
	var keep = []
	for child in container.get_children():
		if child is RigidBody2D and child.has_meta("hooked") and child.get_meta("hooked"):
			keep.append(child)
	for body in keep:
		container.remove_child(body)
		world_container.add_child(body)
	container.queue_free()
	physics_chunks.erase(chunk_coord)

func _clear_safe_cells_from_container(container: Node2D) -> void:
	var to_remove = []
	for child in container.get_children():
		if child is Sprite2D or child is StaticBody2D or child is RigidBody2D or child is CharacterBody2D:
			var cell = world_to_cell(child.global_position)
			if _is_cell_safe(cell.x, cell.y):
				to_remove.append(child)
	for node in to_remove: node.queue_free()


# ============================================================
# Parallax & cleanup
# ============================================================

func _update_parallax():
	if not camera: return
	var cam_pos = camera.global_position
	for i in range(parallax_layers.size()):
		if i < parallax_factors.size():
			parallax_layers[i].position = cam_pos * parallax_factors[i]

func _clear_container(container: Node) -> void:
	for child in container.get_children(): child.queue_free()
