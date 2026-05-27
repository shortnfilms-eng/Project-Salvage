extends Node

func deal_damage(target: Node2D, amount: float, source: Node2D) -> void:
	if target.has_method("take_damage"):
		target.take_damage(amount, source.global_position)
	elif target.has_method("apply_knockback"):
		target.apply_knockback(source.global_position.direction_to(target.global_position), 300.0)
