extends Node2D

class_name TileData

onready var biomes_map: TileMap = $Biomes
onready var resources_map: TileMap = $Resources
onready var hardness_map: TileMap = $Hardness

var dome_entrance := Vector2(0, -1)
var switch_blocks: PoolVector2Array = []
var relic: Vector2

enum cell_types { IRON, WATER, COBALT, GADGET, RELIC, N, RELIC_SWITCH, EMPTY = 9, BLOCK = 10, WALL = 21 }

func _ready():
	biomes_map.set_owner(self)
	resources_map.set_owner(self)
	hardness_map.set_owner(self)

	relic = get_closest_relic_block(dome_entrance)
	preprocess_switches()
	switch_blocks = get_switch_blocks()


#map:
#	tileBaseHealth: 3.0
#	ironAdditionalHealth: 2.0
#	sandAdditionalHealth: 3.0
#	waterAdditionalHealth: 1.0
#	gadgetAdditionalHealth: 6.0
#	relicAdditionalHealth: 8.0
#	tileHealthBaseMultiplier: 1.0
#	hardnessMultiplier0: 0.5
#	hardnessMultiplier1: 1.0
#	hardnessMultiplier2: 2.0
#	hardnessMultiplier3: 4.0
#	hardnessMultiplier4: 10.0
#	tileHealthMultiplierPerLayer: 2.1

# round((baseHealth + resourceHealth) * hardnessLevel * (2.1 ^ biomeLevel))
# round((baseHealth + resourceHealth) * (2.1 ^ biomeLevel))

# todo take values from games yaml
func get_tile_density_for_drill_v(cell_position: Vector2, drill_power: int, igore_relic: bool) -> int:
	if cell_position.y < -1: return -2 # ignore the biome tiles above the entrance
	var density := 3.0
	var resource = get_resourcev(cell_position)
	match resource:
		TileMap.INVALID_CELL: return -1 # already mined cell
		0: density += 2.0 	# iron
		1: density += 1.0 	# water
		2: density += 3.0 	# sand (cobalt)
		3: density += 6.0 	# gadget/switch
		9: return -1			# caves
		10: pass 			# normal block
		21: return -2 		# walls
		4:
			if igore_relic:
				# so the optimal relic entry spot is always chosen no matter the targeted block
				return 0
			else:
				density += 8.0

	# relic and gadget are not affected by hardness
	if not (resource == 3 or resource == 4):
		match get_hardnessv(cell_position):
			0: density *= 0.5
			1: density *= 1.0
			2: density *= 2.0
			3: density *= 4.0
			4: density *= 10.0

	density = density * pow(2.1, float(get_biomev(cell_position)))
	density = round(density)
	return int(ceil( density/float(drill_power) ))


func get_closest_relic_block(other_block: Vector2) -> Vector2:
	var shortest_dist: float = INF
	var closest_cell: Vector2
	for cell in resources_map.get_used_cells_by_id(cell_types.RELIC):
		var dist = other_block.distance_to(cell)
		if dist < shortest_dist:
			shortest_dist = dist
			closest_cell = cell
	return closest_cell


func get_switch_blocks() -> PoolVector2Array:
	return PoolVector2Array(resources_map.get_used_cells_by_id(cell_types.RELIC_SWITCH))


func preprocess_switches():
	for switch in get_guessed_switch_blocks():
		resources_map.set_cellv(switch, cell_types.RELIC_SWITCH)


func get_guessed_switch_blocks() -> PoolVector2Array:
	var switches: PoolVector2Array = []
	var gadget_blocks := resources_map.get_used_cells_by_id(cell_types.GADGET)
	for block in gadget_blocks:
		if is_switch_block(block):
			switches.append(block)
	return switches


func is_switch_block(block: Vector2) -> bool:
	return get_adjacent_cell_count_by_type(resources_map, block, cell_types.GADGET) < 3


func get_adjacent_cell_count_by_type(tilemap: TileMap, cell: Vector2, type: int) -> int:
	var directions = [
		Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT,
		Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)
	 ]
	var count := 0
	for direction in directions:
		if tilemap.get_cellv(cell + direction) == type:
			count += 1

	return count


func get_biome(x:int, y:int)->int:
	var biome = biomes_map.get_cell(x, y) - 10
	if biome <= 0:biome = 0
	return biome

func get_biomev(coord:Vector2)->int:
	var biome = biomes_map.get_cellv(coord) - 10
	if biome <= 0:biome = 0
	return biome

func get_hardness(x:int, y:int)->int:
	return hardness_map.get_cell(x, y) - 13

func get_hardnessv(v:Vector2)->int:
	return hardness_map.get_cellv(v) - 13

func get_resource(x:int, y:int)->int:
	return resources_map.get_cell(x, y)

func get_resourcev(v:Vector2)->int:
	return resources_map.get_cellv(v)

func get_resource_name_v(v: Vector2) -> String:
	var res := get_resourcev(v)
	match res:
		-1: return "Out of bounds"
		0, 1, 2, 3, 4, 6: return cell_types.keys()[res].capitalize()
		9: return "Empty"
		10: return "Block"
		21: return "Wall"
		_: return ""

func is_area_free(start:Vector2, offsets:Array)->bool:
	for c in offsets:
		var absCoord = start + c
		if get_resourcev(absCoord) != 10:
			return false
	return true

func clear_cell(x:int, y:int):
	biomes_map.set_cell(x, y, cell_types.EMPTY)
	resources_map.set_cell(x, y, cell_types.EMPTY)

func clear_resourcev(v: Vector2):
	resources_map.set_cellv(v, cell_types.EMPTY)

func getRevealedCells()->Array:
	var cells: = []
	for cell in hardness_map.get_used_cells():
		if resources_map.get_cellv(cell) == cell_types.EMPTY:
			cells.append(cell)
	return cells

func get_biome_cells_by_index(index:int)->Array:
	return biomes_map.get_used_cells_by_id(10 + index)

func get_resource_cells_by_id(id:int)->Array:
	return resources_map.get_used_cells_by_id(id)

func get_hardness_cells_by_grade(grade:int)->Array:
	return hardness_map.get_used_cells_by_id(grade + 13)

func get_tile_count()->int:
	return biomes_map.get_used_cells().size()

func get_mineable_tile_count()->int:
	var all = resources_map.get_used_cells().size()
	return all - resources_map.get_used_cells_by_id(cell_types.WALL).size()

func getSize()->Vector2:
	return resources_map.get_used_rect().size

func getMaxSize()->Vector2:
	var resource_rect:Rect2 = resources_map.get_used_rect()
	var x = max(abs(resource_rect.position.x), resource_rect.size.x - abs(resource_rect.position.x))
	var padding = Vector2(2, 2)
	return Vector2(x * 2, resource_rect.size.y) + padding

func getMapSizePx()->Vector2:
	return - biomes_map.get_used_rect().position + biomes_map.get_used_rect().size * 24 #GameWorld.TILE_SIZE

func get_used_cells() -> Array:
	return biomes_map.get_used_cells()

func world_to_map(pos:Vector2)->Vector2:
	return biomes_map.world_to_map(pos)

func map_to_world(pos:Vector2)->Vector2:
	return biomes_map.map_to_world(pos)

func pack()->PackedScene:
	var packed_scene = PackedScene.new()
	packed_scene.pack(self)
	return packed_scene
