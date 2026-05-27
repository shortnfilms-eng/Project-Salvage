extends Node

var player: Player = null
var hud: CanvasLayer = null

func _ready() -> void:
	print("GameManager: spawning HUD")
	var hud_scene = load("res://scenes/ui/hud.tscn")
	if not hud_scene:
		print("ERROR: could not load hud.tscn")
		return
	hud = hud_scene.instantiate()
	add_child(hud)
	print("HUD added as child, path: ", hud.get_path())

	call_deferred("_link_player")


func _link_player() -> void:
	player = get_tree().get_first_node_in_group("player")
	if player:
		print("Player found")
		EventBus.player_health_changed.emit(player.health, player.max_health)
	else:
		print("Player not found yet")
