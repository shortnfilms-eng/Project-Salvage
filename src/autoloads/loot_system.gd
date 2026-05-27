extends Node

func spawn_scrap(position: Vector2) -> void:
	# Placeholder – later spawn a RigidBody2D scrap item
	print("Scrap spawned at ", position)

func _on_enemy_died(enemy: Node2D) -> void:
	spawn_scrap(enemy.global_position)
	# TODO: check enemy data for possible frame/weapon drops
