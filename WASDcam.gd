extends Camera2D

export var speed := 10
export var zoom_speed := 0.1


func _process(_delta: float) -> void:
	if Input.is_key_pressed(KEY_W):
		position += Vector2.UP * speed
	if Input.is_key_pressed(KEY_A):
		position += Vector2.LEFT * speed
	if Input.is_key_pressed(KEY_D):
		position += Vector2.RIGHT * speed
	if Input.is_key_pressed(KEY_S):
		position += Vector2.DOWN * speed


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			BUTTON_WHEEL_DOWN: zoom += Vector2.ONE * zoom_speed
			BUTTON_WHEEL_UP: zoom -= Vector2.ONE * zoom_speed
	if event is InputEventKey:
		if not event.pressed:
			return
		match event.scancode:
			KEY_MINUS: zoom += Vector2.ONE * zoom_speed
			KEY_PLUS: zoom -= Vector2.ONE * zoom_speed





