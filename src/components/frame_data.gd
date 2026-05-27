extends Resource
class_name FrameData

@export var frame_name: String = "Standard Frame"
@export var scene: PackedScene
@export var turret_rotation_speed: float = 15.0
@export var hook_frame_rotation_speed: float = 10.0
@export var max_health: float = 100.0

# Movement stats (used by the player)
@export var max_speed: float = 300.0
@export var dash_speed: float = 900.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 1.5
