extends Resource
class_name WeaponData

@export var weapon_name: String = "Basic Cannon"
@export var bullet_scene: PackedScene   # assign the bullet scene here
@export var fire_rate: float = 5.0
@export var bullet_speed: float = 800.0
@export var spread_degrees: float = 5.0
@export var damage: float = 10.0
@export var is_player_weapon: bool = true
