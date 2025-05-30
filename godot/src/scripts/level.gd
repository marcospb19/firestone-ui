extends Node3D

const DIMENSIONS := Vector3i(16, 1, 16)
const BLOCK_WIDTH := 1.0
const CUT_OFF := 0.0

@onready var player = $Player
@onready var player_initial_position = player.position

func _ready():
	var random = FastNoiseLite.new()
	random.noise_type = FastNoiseLite.TYPE_SIMPLEX

	for x in DIMENSIONS.x:
		for y in DIMENSIONS.y:
			for z in DIMENSIONS.z:
				# if random.get_noise_3d(x, y, z) > CUT_OFF:
				if randf() > CUT_OFF:
					var coordinate = Vector3i(x, y, z)
					coordinate -= DIMENSIONS / 2 # centralize
					coordinate.y -= 2
					add_block_at(coordinate, VoxelWorld.BlockKind.STONE)

func add_block_at(coordinate: Vector3i, block_kind: VoxelWorld.BlockKind, look_direction: Vector3 = Vector3.FORWARD):
	# Don't place a block if it collides with the player
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = BoxShape3D.new()
	params.shape.size = Vector3.ONE * 0.99
	params.transform = Transform3D(Basis.IDENTITY, coordinate_to_position(coordinate))
	var collisions = self.get_world_3d().get_direct_space_state().intersect_shape(params, 2)
	for collision in collisions:
		if collision["rid"] == $Player.get_rid():
			return

	$VoxelWorld.disable_updates = true
	$VoxelWorld.add_block(coordinate, block_kind)

	if VoxelWorld.is_block_gate(block_kind):
		var input_face = look_direction_to_face(-look_direction)
		var output_face = look_direction_to_face(look_direction)
		$VoxelWorld.update_face_uv($VoxelWorld.block_positions[-1], input_face, VoxelWorld.block_input_face(block_kind))
		$VoxelWorld.update_face_uv($VoxelWorld.block_positions[-1], output_face, VoxelWorld.block_output_face(block_kind))
		$VoxelWorld.blocks[Vector3i($VoxelWorld.block_positions[-1])].input_face = input_face
		$VoxelWorld.blocks[Vector3i($VoxelWorld.block_positions[-1])].output_face = output_face
	$VoxelWorld.disable_updates = false
	$VoxelWorld.enqueue_mesh_update()

func remove_block_at(coordinate: Vector3i):
	$VoxelWorld.remove_block(coordinate)

# Snaps the look to which horizontal direction the user was looking to
func snapped_look_direction(look: Vector3) -> Vector3i:
	look.y = 0.0 # Blocks can't face up or down
	look = look.normalized() # Compensate the zeroed `y`
	var direction = look.snappedf(sqrt(2.0))
	if not is_equal_approx(absf(direction.x) + absf(direction.y) + absf(direction.z), 1.0):
		# If you're perfectly aiming at Vector3(sqrt(2.0), 0.0, sqrt(2.0)), you'll be in-between
		# two directions, pick one of them by rotating a little to the right.
		# (since look can't be UP or DOWN, that sum can only be 1.0 or sqrt(2.0)
		direction = look.rotated(Vector3.UP, deg_to_rad(1)).snappedf(sqrt(2.0))
	return direction

func look_direction_to_face(look: Vector3) -> VoxelWorld.Face:
	return VoxelWorld.FACE_NORMALS_REVERSED[snapped_look_direction(look)]

func _on_voxel_world_updated() -> void:
	$StaticBody3D/CollisionShape3D.shape = $VoxelWorld.mesh.create_trimesh_shape()

func _on_player_connect_faces(from: Vector3, from_face: VoxelWorld.Face, to: Vector3, to_face: VoxelWorld.Face):
	var from_coords = position_to_coordinate(from)
	var to_coords = position_to_coordinate(to)

	if from_coords == to_coords:
		printerr('cant connect block to itself')
		return

	var from_block = $VoxelWorld.blocks[from_coords]
	var to_block = $VoxelWorld.blocks[to_coords]
	if not VoxelWorld.is_block_gate(from_block.block_kind):
		printerr('first block is not valid gate, cancelling connection')
		return
	if not VoxelWorld.is_block_gate(to_block.block_kind):
		printerr('second block is not valid gate, cancelling connection')
		return

	var from_output_offset = VoxelWorld.FACE_NORMALS[from_block.output_face] * (0.5 + Cable.CABLE_WIDTH / 2.0)
	var to_input_offset = VoxelWorld.FACE_NORMALS[to_block.input_face] * (0.5 + Cable.CABLE_WIDTH / 2.0)

	var success = $CircuitSimulation.connect_blocks(from_coords, to_coords, from_block.block_kind == VoxelWorld.BlockKind.AND, to_block.block_kind == VoxelWorld.BlockKind.AND)
	if not success:
		printerr('connection would create an illegal cycle, cancelling connection')
		return

	var cable_start = coordinate_to_position(from_coords) + from_output_offset
	var cable_end = coordinate_to_position(to_coords) + to_input_offset
	var cable = Cable.new(cable_start, cable_end)
	self.add_child(cable)

# Only works cause BLOCK_WIDTH == 1.0, TODO: maybe use Vector3.snapped?
func position_to_coordinate(pos: Vector3) -> Vector3i:
	return pos.floor()

func coordinate_to_position(coord: Vector3i) -> Vector3:
	return Vector3(coord) + Vector3.ONE * 0.5

func _on_player_reset_position():
	player.position = player_initial_position
	player.velocity = Vector3.ZERO

func add_block_at_world_offset(pos: Vector3, block_kind: VoxelWorld.BlockKind, look_direction: Vector3):
	add_block_at(position_to_coordinate(pos), block_kind, look_direction)

func remove_block_at_world_offset(pos: Vector3):
	remove_block_at(position_to_coordinate(pos))
