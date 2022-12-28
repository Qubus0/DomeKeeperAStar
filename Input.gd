extends LineEdit


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		match event.scancode:
			KEY_ESCAPE, KEY_ENTER, KEY_W, KEY_A, KEY_S, KEY_D:
				release_focus()
