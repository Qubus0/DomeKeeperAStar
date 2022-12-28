extends VBoxContainer

var statbox_scene := preload("res://StatBox.tscn")


func _ready() -> void:
	pass


func add_statbox(box_name: String, data: Dictionary):
	var statbox := statbox_scene.instance()
	statbox.name = box_name
	statbox.get_node("Flex/Title").text = box_name.capitalize()
	add_child(statbox)
	for stat_key in data.keys():
		add_stat(statbox, String(stat_key), String(data[stat_key]))


func remove_statbox(box_name: String):
	var statbox := get_node_or_null(box_name)
	if statbox:
		statbox.queue_free()


func update_statbox(box_name: String, data: Dictionary = {}):
	var statbox := get_node_or_null(box_name)
	if not statbox:
		add_statbox(box_name, data)
		return

	for child in statbox.get_node("Flex/Grid").get_children():
		statbox.get_node("Flex/Grid").remove_child(child)
	for stat_key in data.keys():
		add_stat(statbox, String(stat_key), String(data[stat_key]))


func add_stat(statbox: Node, key: String, value: String):
	var key_label := Label.new()
	key_label.text = key.capitalize()
	statbox.get_node("Flex/Grid").add_child(key_label)
	var value_label := Label.new()
	value_label.text = value
	value_label.align = Label.ALIGN_RIGHT
	statbox.get_node("Flex/Grid").add_child(value_label)

