extends Node

onready var board: AstarTileMap = get_parent()
onready var astar = board.astar if board else null

onready var density_map: TileMap = $Density
onready var path_map: TileMap = $Paths
onready var interaction_map: TileMap = $Interaction

enum cell_type { EMPTY = -1, HIGHLIGHT, HIGHLIGHT_WEAK, START, GOAL, PATH,
				PATH_1, PATH_2, PATH_3, PATH_4, PATH_5,
				PATH_6, PATH_7, PATH_8, PATH_9, PATH_10,
				PATH_11, PATH_12, PATH_13, PATH_14, PATH_15, PATH_16,
				 }

func _ready() -> void:
	for index in 300:
		density_map.tile_set.tile_set_modulate(index, board.density_colors.interpolate(float(index)/300.0))

	# empty tiles
	density_map.tile_set.tile_set_modulate(300, board.density_colors.get_color(0))


func _process(_delta: float) -> void:
	update_interaction_map()


func _unhandled_key_input(event: InputEventKey) -> void:
	if not event.pressed: return
	match event.scancode:
		KEY_U: density_map.visible = not density_map.visible
		KEY_I: board.resources.visible = not board.resources.visible
		KEY_O: board.hardness.visible = not board.hardness.visible
		KEY_P: board.biomes.visible = not board.biomes.visible


func update_density_map():
	density_map.clear()
	if not astar is AStar2D: return
	for point in astar.get_points():
		var point_position = astar.get_point_position(point)

		var weight: float = astar.get_point_weight_scale(point)
		if astar.is_point_disabled(point):
			continue
		if weight == 1:
			density_map.set_cellv(world_to_map(point_position), 300) # empty tile
			continue


		var tile_index = weight-1 if weight < 300 else 299 # 0 to 299

		density_map.set_cellv(world_to_map(point_position), tile_index)


func update_interaction_map():
	interaction_map.clear()
	interaction_map.set_cellv(board.targeted_cell, cell_type.HIGHLIGHT_WEAK)

	var point_cell = world_to_map(board.astar.get_point_position(board.closest_point))
	interaction_map.set_cellv(point_cell, cell_type.HIGHLIGHT)


func update_pathfinding_map():
	path_map.clear()
	for map in path_map.get_children():
		map.clear()

	if not astar is AStar2D: return
	for point in astar.get_points():
		var point_cell = world_to_map(astar.get_point_position(point))

		for path_key in board.all_paths.keys():
			var path_index = int(path_key)
			if not path_index > 0:
				continue
			if point in board.all_paths[path_key]:
				path_map.get_node("Paths%s" % path_index).set_cellv(point_cell, cell_type["PATH_%s" % path_index])

		if point == board.custom_start or point == board.dome_entrance:
			path_map.set_cellv(point_cell, cell_type.START)
		elif point == board.custom_goal or point in board.switch_blocks or point == board.relic:
			path_map.set_cellv(point_cell, cell_type.GOAL)
		elif point in board.all_paths.customPath:
			path_map.set_cellv(point_cell, cell_type.PATH)


func world_to_map(world_position: Vector2) -> Vector2:
	return density_map.world_to_map(world_position)

