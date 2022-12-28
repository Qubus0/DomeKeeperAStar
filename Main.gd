extends Node2D
class_name AstarTileMap

const DIRECTIONS := [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]
const PAIRING_LIMIT := int(pow(2, 30))
const CELL_SIZE = Vector2(24, 24)
enum pairing_methods {
	CANTOR_UNSIGNED,	# positive values only
	CANTOR_SIGNED,		# both positive and negative values
	SZUDZIK_UNSIGNED,	# more efficient than cantor
	SZUDZIK_SIGNED,		# both positive and negative values
	SZUDZIK_IMPROVED,	# improved version (best option)
}
export(pairing_methods) var current_pairing_method = pairing_methods.SZUDZIK_IMPROVED
export var density_colors: Gradient

var astar := AStar2D.new()
var obstacles := []
var units := []


var tile_data: TileData setget set_tile_data
var biomes: TileMap
var hardness: TileMap
var resources: TileMap
var drill_power := get_drillpower(0)
var ignore_relic := true

var all_paths := {
	"customPath": []
}

var dome_entrance: int
var switch_blocks: PoolIntArray = []
var relic: int

var custom_goal: int
var custom_start: int
var closest_point: int
var targeted_cell: Vector2

onready var stats := $CanvasLayer/MarginContainer/HBoxContainer/ScrollContainer/Stats
var game_saves_dir := "res://GameSaves/"
var game_save_paths: PoolStringArray = []


func _ready() -> void:
	OS.low_processor_usage_mode = true
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	get_tree().connect("files_dropped", self, "_on_files_dropped")

	stats.update_statbox("PointedCell")

	self.tile_data = load_new_tile_data(game_saves_dir + "/small/savegame_0_map.scn")
	if not tile_data:
		return

	find_map_goals(tile_data)
	recalculate_total_map_paths()
#	recalculate_custom_path()


func read_game_saves():
	var dir = Directory.new()
	var f = File.new()
	if dir.open(game_saves_dir) != OK:
		print("An error occurred when trying to access the path.")
		return

	dir.list_dir_begin()
	var dir_name = dir.get_next()
	while dir_name != "":
		if dir.current_is_dir():
			var path := "%s/%s/savegame_0_map.tscn" % [game_saves_dir, dir_name]
			if f.file_exists():
				game_save_paths.append(path)


func load_new_tile_data(path: String):
	if tile_data:
		remove_child(tile_data)
		tile_data.queue_free()

	var new_tile_data: TileData = load(path).instance()
	if not new_tile_data:
		stats.update_statbox("LoadingError", { "-": "File could not be loaded" })
		return
	stats.remove_statbox("LoadingError")
	new_tile_data.position = Vector2.ZERO
	new_tile_data.z_index = 0
	new_tile_data.show()
	add_child(new_tile_data)
	move_child(new_tile_data, 0)
	return new_tile_data


func set_tile_data(data: TileData) -> void:
	tile_data = data
	biomes = tile_data.biomes_map
	hardness = tile_data.hardness_map
	resources = tile_data.resources_map


func _on_files_dropped(file_paths: PoolStringArray, _screen: int):
	if file_paths.size() > 1:
		stats.update_statbox("FileDropError", {"-": "Only drop a single file"})
		return
	var file_path := file_paths[0]
	var f := File.new()
	if not f.file_exists(file_path):
		stats.update_statbox("FileDropError", {"-": "Dropped item is not a file"})
		return
	if not "savegame_0_map.tscn" in file_path and not "savegame_0_map.scn" in file_path:
		stats.update_statbox("FileDropError", {
				"-": "Dropped file is not a valid save",
				"tip:": "named savegame_0_map .scn or .tscn"
			})
		return
	stats.remove_statbox("FileDropError")
	self.tile_data = load_new_tile_data(file_path)
	find_map_goals(tile_data)
	recalculate_total_map_paths()


func _unhandled_input(event):
	if not tile_data:
		return

	if event is InputEventMouse:
		var mouse_pos = get_global_mouse_position()
		targeted_cell = tile_data.world_to_map(mouse_pos)
		closest_point = astar.get_closest_point(mouse_pos - CELL_SIZE/2)
		if closest_point == -1:
			return

		var cell_type := tile_data.get_resourcev(targeted_cell)
		$CanvasLayer/Tooltip.visible = not cell_type == -1 and not cell_type == 21
		$CanvasLayer/Tooltip.rect_position = event.position + Vector2(20, -$CanvasLayer/Tooltip.rect_size.y/2)
		var astar_weight := astar.get_point_weight_scale(closest_point)
		var needed_hits := astar_weight -1
		$CanvasLayer/Tooltip/Label.text = ("Hits: %s" % needed_hits)
		var cell_type_mapped := 0
		stats.update_statbox("PointedCell", {
			"tile:": targeted_cell,
			"type": tile_data.get_resource_name_v(targeted_cell),
			"biome:": tile_data.get_biomev(targeted_cell),
			"hardness:": tile_data.get_hardnessv(targeted_cell),
		})


		if Input.is_mouse_button_pressed(BUTTON_LEFT):
			custom_goal = closest_point
			recalculate_custom_path()

		if Input.is_mouse_button_pressed(BUTTON_RIGHT):
			custom_start = closest_point
			recalculate_custom_path()

		if event is InputEventMouseButton:
			$CanvasLayer/MarginContainer/HBoxContainer/VBoxContainer/HBoxContainer/DrillPower.release_focus()

	if event is InputEventKey:
		if event.scancode == KEY_T and event.pressed:
			$CanvasLayer/Tooltip.visible = not $CanvasLayer/Tooltip.visible


func find_map_goals(data: TileData) -> void:
	switch_blocks = []
	create_pathfinding_points(data)

	for block in data.switch_blocks:
		switch_blocks.append(tile_to_astar_point(block))

	dome_entrance = tile_to_astar_point(data.dome_entrance)
	relic = tile_to_astar_point(data.relic)

	custom_start = tile_to_astar_point(data.dome_entrance)
	custom_goal = tile_to_astar_point(data.relic)


func recalculate_custom_path():
	all_paths.custom = astar.get_id_path(custom_start, custom_goal)
	stats.update_statbox("customPath", { "cost": "%8s" % get_path_cost(all_paths.custom) })


func recalculate_total_map_paths() -> void:
	var path_key: String
	var new_path: PoolIntArray
	var new_path_cost: float
	var current_shortest_path: PoolIntArray
	var current_shortest_path_cost := INF
	var remaining_switch_blocks := switch_blocks
	var last_switch: int
	var last_goal: int
	var path_index := 1

	# go to the closest switch to the entrance first
	for switch in remaining_switch_blocks:
		new_path = astar.get_id_path(dome_entrance, switch)
		new_path_cost = get_path_cost(new_path)
		if new_path_cost < current_shortest_path_cost:
			current_shortest_path = new_path
			current_shortest_path_cost = new_path_cost
			last_goal = switch

	path_key = "%sDomeToSwitch" % path_index
	all_paths[path_key] = current_shortest_path
	stats.update_statbox(path_key, {"cost": "%8s" % get_path_cost(current_shortest_path) })

	remove_astar_points_from_map(current_shortest_path)
	create_pathfinding_points(tile_data)
	remaining_switch_blocks = erase_from_pool_int_array(remaining_switch_blocks, last_switch)
	path_index +=1

	# connect all switches in the shortest way possible
	remaining_switch_blocks = erase_from_pool_int_array(remaining_switch_blocks, last_goal)
	while remaining_switch_blocks.size() > 0:
		current_shortest_path_cost = INF
		for switch in remaining_switch_blocks:
			new_path = astar.get_id_path(last_goal, switch)
			new_path_cost = get_path_cost(new_path)
			if new_path_cost < current_shortest_path_cost:
				current_shortest_path = new_path
				current_shortest_path_cost = new_path_cost
				last_switch = switch

		last_goal = last_switch
		path_key = "%sSwitchToSwitch" % path_index
		all_paths[path_key] = current_shortest_path
		stats.update_statbox(path_key, {"cost": "%8s" % get_path_cost(current_shortest_path) })

		remove_astar_points_from_map(current_shortest_path)
		create_pathfinding_points(tile_data)
		remaining_switch_blocks = erase_from_pool_int_array(remaining_switch_blocks, last_goal)
		path_index +=1


	# connect the last switch to the relic
	new_path = astar.get_id_path(last_goal, relic)

	path_key = "%sSwitchToRelic" % path_index
	all_paths[path_key] = new_path
	stats.update_statbox(path_key, {"cost": "%8s" % get_path_cost(new_path) })

	remove_astar_points_from_map(new_path)
	create_pathfinding_points(tile_data)
	path_index +=1

	# get back to the entrance from the relic
	new_path = astar.get_id_path(relic, dome_entrance)

	path_key = "%sRelicToDome" % path_index
	all_paths[path_key] = new_path
	stats.update_statbox(path_key, {"cost": "%8s" % get_path_cost(new_path) })

	remove_astar_points_from_map(new_path)
	create_pathfinding_points(tile_data)

	$Debug.update_pathfinding_map()


func erase_from_pool_int_array(array: PoolIntArray, value: int) -> PoolIntArray:
	var new_array: PoolIntArray = []
	for array_value in array:
		if not array_value == value:
			new_array.append(array_value)
	return new_array


func remove_astar_points_from_map(points: PoolIntArray):
	for point in points:
		tile_data.clear_resourcev(tile_data.world_to_map(astar.get_point_position(point)))


func get_path_cost(_path: PoolIntArray) -> float:
	var cost := 0.0
	for point in _path:
		var pscale = astar.get_point_weight_scale(point)
		if pscale > 1: # empty tiles have weight 1, everything else 2+
			cost += pscale
	return cost


func tile_to_astar_point(tile: Vector2) -> int:
	return astar.get_closest_point(tile_data.map_to_world(tile))


func create_pathfinding_points(tiles: TileData) -> void:
	astar.clear()
	var used_cell_positions := tiles.get_used_cells()
	for cell_position in used_cell_positions:
		var density := tiles.get_tile_density_for_drill_v(cell_position, drill_power, ignore_relic)
		var world_cell := tiles.map_to_world(cell_position)
		var id := get_point(world_cell)

		# walls (invalid tile)
		if density < -1:
			astar.add_point(id, world_cell, INF)
			astar.set_point_disabled(id, true)
			continue

		var astar_adjusted_density = density +1 if density > 0 else 1
		astar.add_point(id, world_cell, astar_adjusted_density)


	for cell_position in used_cell_positions:
		var world_cell := tiles.map_to_world(cell_position)
		connect_cardinals(world_cell)
	$Debug.update_density_map()


#func get_astar_path(start_position: Vector2, end_position: Vector2, max_distance := -1) -> Array:
#	var astar_path := astar.get_point_path(get_point(start_position), get_point(end_position))
##	return set_path_length(astar_path, max_distance)
#
#
#func set_path_length(point_path: Array, max_distance: int) -> Array:
#	if max_distance < 0: return point_path
#	point_path.resize(min(point_path.size(), max_distance))
#	return point_path


func path_directions(_path: Array) -> Array:
	# Convert a path into directional vectors whose sum would be path[length-1]
	var directions := []
	for p in range(1, _path.size()):
		directions.append(_path[p] - _path[p - 1])
	return directions


func get_point(point_position: Vector2) -> int:
	var a := int(point_position.x)
	var b := int(point_position.y)
	match current_pairing_method:
		pairing_methods.CANTOR_UNSIGNED:
			assert(a >= 0 and b >= 0, "Board: pairing method has failed. Choose method that supports negative values.")
			return cantor_pair(a, b)
		pairing_methods.SZUDZIK_UNSIGNED:
			assert(a >= 0 and b >= 0, "Board: pairing method has failed. Choose method that supports negative values.")
			return szudzik_pair(a, b)
		pairing_methods.CANTOR_SIGNED:
			return cantor_pair_signed(a, b)
		pairing_methods.SZUDZIK_SIGNED:
			return szudzik_pair_signed(a, b)
		pairing_methods.SZUDZIK_IMPROVED:
			return szudzik_pair_improved(a, b)
	return szudzik_pair_improved(a, b)


func cantor_pair(a:int, b:int) -> int:
	var result := 0.5 * (a + b) * (a + b + 1) + b
	return int(result)

func cantor_pair_signed(a:int, b:int) -> int:
	if a >= 0:
		a = a * 2
	else:
		a = (a * -2) - 1
	if b >= 0:
		b = b * 2
	else:
		b = (b * -2) - 1
	return cantor_pair(a, b)

func szudzik_pair(a:int, b:int) -> int:
	if a >= b:
		return (a * a) + a + b
	else:
		return (b * b) + a

func szudzik_pair_signed(a: int, b: int) -> int:
	if a >= 0:
		a = a * 2
	else:
		a = (a * -2) - 1
	if b >= 0:
		b = b * 2
	else:
		b = (b * -2) - 1
	return int((szudzik_pair(a, b) * 0.5))

func szudzik_pair_improved(x:int, y:int) -> int:
	var a: int
	var b: int
	if x >= 0:
		a = x * 2
	else:
		a = (x * -2) - 1
	if y >= 0:
		b = y * 2
	else:
		b = (y * -2) - 1
	var c = szudzik_pair(a,b) * 0.5
	if a >= 0 and b < 0 or b >= 0 and a < 0:
		return -c - 1
	return c

func has_point(point_position: Vector2) -> bool:
	var point_id := get_point(point_position)
	return astar.has_point(point_id)

func get_used_cell_global_positions() -> Array:
	var cells = tile_data.get_used_cells()
	var cell_positions := []
	for cell in cells:
		var cell_position := global_position + tile_data.map_to_world(cell)
		cell_positions.append(cell_position)
	return cell_positions

func connect_cardinals(point_position) -> void:
	var center := get_point(point_position)
	for direction in DIRECTIONS:
		var cardinal_point := get_point(point_position + tile_data.map_to_world(direction))
		if cardinal_point != center and astar.has_point(cardinal_point):
			astar.connect_points(center, cardinal_point, true)

func get_grid_distance(distance: Vector2) -> float:
	var vec := tile_data.world_to_map(distance).abs().floor()
	return vec.x + vec.y

#keeper1:
#  propertyChanges:
#    - keeper1.drillStrength = 2
#drill1:
#  propertyChanges:
#    - keeper1.drillStrength += 4
#drill2:
#  propertyChanges:
#    - keeper1.drillStrength += 8
#drill3:
#  propertyChanges:
#    - keeper1.drillStrength += 20
#drill4:
#  repeatable:
#    - property.keeper1.drillStrength *= 2.2
#  propertyChanges:
#    - keeper1.drillStrength += 40

# todo get from yaml
func _on_DrillPower_text_changed(new_text: String) -> void:
	if not new_text:
		return
	var level = abs(int(new_text))

	drill_power = get_drillpower(level)

	create_pathfinding_points(tile_data)
	recalculate_custom_path()
	recalculate_total_map_paths()


func get_drillpower(drill_level: int) -> int:
	var power := 2.0
	if drill_level >= 1:
		power += 4.0
	if drill_level >= 2:
		power += 8.0
	if drill_level >= 3:
		power += 20.0
	if drill_level >= 4:
		for repeatable_level in drill_level-3:
			power += 40.0 * pow(2.2, repeatable_level)

	power = round(power)
	return int(power)


func _on_CheckBox_toggled(button_pressed: bool) -> void:
	ignore_relic = button_pressed
	create_pathfinding_points(tile_data)
	recalculate_custom_path()
	recalculate_total_map_paths()


