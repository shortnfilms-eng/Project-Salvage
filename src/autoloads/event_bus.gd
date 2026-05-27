extends Node

signal player_hit(damage: float, source: Node2D)
signal enemy_hit(enemy: Node2D, damage: float, source: Node2D)
signal enemy_died(wreck_position: Vector2, enemy_data: EnemyData)
signal scrap_spawned(scrap: Node2D)
signal player_damaged(flash_color: Color)
signal player_health_changed(current_health: float, max_health: float)
