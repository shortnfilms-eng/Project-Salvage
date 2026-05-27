extends CanvasLayer

@onready var screen_flash: ColorRect = $ScreenFlash
@onready var health_bar: TextureProgressBar = $HealthBar

var _flash_tween: Tween = null


func _ready() -> void:
	EventBus.player_damaged.connect(_flash)
	EventBus.player_health_changed.connect(_on_health_changed)
	screen_flash.modulate.a = 0.0


func _flash(flash_color: Color) -> void:
	# Kill any existing tween
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	screen_flash.modulate = flash_color          # full color with alpha=1
	_flash_tween.tween_property(screen_flash, "modulate:a", 0.0, 0.2)


func _on_health_changed(current: float, max_hp: float) -> void:
	health_bar.max_value = max_hp
	health_bar.value = current
