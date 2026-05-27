extends Resource
class_name EnemyData

@export var enemy_name: String = "Scout Drone"
@export var propulsor: PropulsorData
@export var frame: FrameData
@export var weapon_scene: PackedScene     # The weapon scene (cannon.tscn)
@export var weapon_right: WeaponData      # Stats + bullet scene
@export var patrol_radius: float = 250.0
@export var combat_min_range: float = 200.0
@export var combat_max_range: float = 350.0
@export var wander_speed: float = 80.0
@export var combat_speed: float = 150.0
@export var sight_range: float = 500.0
@export var fire_rate: float = 2.0
