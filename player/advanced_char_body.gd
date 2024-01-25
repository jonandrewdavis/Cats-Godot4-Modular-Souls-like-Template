extends CharacterBody3D
class_name CharacterBodySoulsBase
## A semi-smart character controller. Will detect the current camera in use
## and update control orientation to match it. Strafing will lock rotation to
## to face camera perspective, except for dodging actions.

## A LOT of actions here have signals delayed by timers. This is bad form.
## It's bad for production but handy when protoyping new animations and you don't
## want to hard bake where each trigger happens every time you change something.
## Once player animations are finalized, add the signal triggers to the animations
## and remove the timers in the functions here as needed. 

## Manages all animations generally pulling info it needs from states and substates.
@export var anim_state_tree : AnimationTree
#### When the anim_state_tree starts a new animatino, this variable updates with it's length
@onready var anim_length = .5


## default/1st camera is a follow cam.
@onready var current_camera = get_viewport().get_camera_3d()
## Aids strafe rotation when alternating between cameras
@onready var orientation_target = current_camera

## Sensing interactable objects, like ladders, doors, etc. 
@export var interact_sensor : Node3D
## The sensor that spotted the object, TOP sensor, or BOTTOM sensor.
@onready var interact_loc : String # use "TOP","BOTTOM","BOTH"
## The newly sensed interactable node.
@onready var interactable : Node3D
signal door_started
signal gate_started


## Weapons and attacking equipment system that manages moving nodes from the 
## attacking hand, to their sheathed location
@export var weapon_system : EquipmentSystem
## A helper variable, tracks the current weapon type for easier referencing fro
## the anim_state_tree
var weapon_type :String = "SLASH"
signal weapon_change_started
signal weapon_changed
signal weapon_change_ended
signal attack_started
signal attack_swing_started
signal attack_ended
## A helper variable for inputs across 2 key inputs "shift+ attack", etc.
var secondary_action

## Gadgets and guarding equipment system that manages moving nodes from the 
## off-hand, to their hip location
@export var gadget_system : EquipmentSystem
## A helper variable, tracks the current gadget type for easier referencing fro
## the anim_state_tree
var gadget_type :String = "SHIELD"
signal gadget_change_started
signal gadget_changed
signal gadget_started
signal gadget_swing_started
signal gadget_activated
signal gadget_deactivated
## When guarding this substate is true
@onready var guarding = false
## The first moments of guarding, the parry window is active, allowing to parry()
## attacks and avoid damage
@onready var can_be_hurt = true
@onready var parry_active = false
var parry_window = .3
signal parry_started
signal block_started
signal hurt_started
signal damage_taken
signal death_started

signal use_item_started
signal item_used

# Jump and Gravity
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var jump_velocity = 4.5
signal jump_started

## Dodge and Sprint Mechanics.
@export var dodge_speed = 8.0
@onready var sprint_timer = Timer.new()
@export var sprint_speed = 7.0
signal dodge_started
signal dodge_ended
signal sprint_started

# Movement Mechanics
var input_dir : Vector2
@export var default_speed = 4.0
@export var walk_speed = 1.0
@onready var speed = default_speed
var direction = Vector3.ZERO

# Strafing
var strafing :bool = false
@onready var strafe_cross_product = 0.0
@onready var move_dot_product = 0.0
signal strafe_toggled

# Climbing
@export var climb_speed = 1.0
signal ladder_started
signal ladder_finished

# State management
enum state {SPAWN,FREE,STATIC_ACTION,DYNAMIC_ACTION,DODGE,SPRINT,LADDER,ATTACK,AIRATTACK}
@onready var current_state = state.SPAWN : set = change_state
signal changed_state

func _ready():
	if anim_state_tree:
		anim_state_tree.animation_measured.connect(_on_animation_measured)

	if interact_sensor:
		interact_sensor.interact_updated.connect(_on_interact_updated)
		
	if weapon_system:
		weapon_system.equipment_changed.connect(_on_weapon_equipment_changed)
		_on_weapon_equipment_changed(weapon_system.current_equipment)
		
	if gadget_system:
		gadget_system.equipment_changed.connect(_on_gadget_equipment_changed)
		_on_gadget_equipment_changed(gadget_system.current_equipment)
		
	add_child(sprint_timer)
	sprint_timer.one_shot = true
	
	await get_tree().create_timer(2).timeout
	current_state = state.FREE
	
## Makes variable changes for each state, primiarily used for updating movement speeds
func change_state(new_state):
	current_state = new_state
	changed_state.emit(current_state)
	
	match current_state:
		state.FREE:
			speed = default_speed
		state.LADDER:
			speed = climb_speed
		state.DODGE:
			speed = dodge_speed
		state.SPRINT:
			speed = sprint_speed
		state.DYNAMIC_ACTION:
			speed = walk_speed
		state.STATIC_ACTION:
			speed = 0.0


func _input(_event:InputEvent):
	if _event.is_action_pressed("ui_cancel"):
		get_tree().quit()
		
	# strafe toggle on/off
	if _event.is_action_pressed("strafe_target"):
		strafe_targeting()
		
	# Update current orientation to camera when nothing pressed
	if !Input.is_anything_pressed():
		current_camera = get_viewport().get_camera_3d()
	
	if Input.is_action_pressed("secondary_action"):
		secondary_action = true
	else:
		secondary_action = false
	
	if current_state == state.FREE:
		if is_on_floor():
			# if interactable exists, activate its action
			if _event.is_action_pressed("interact"):
				interact()
			
			elif _event.is_action_pressed("jump"):
				jump()
				
			elif _event.is_action_pressed("use_weapon_light"):
				if secondary_action:
					attack(secondary_action)
				else:
					attack()
					
			elif _event.is_action_pressed("use_weapon_strong"):
				attack(secondary_action)
			# dodge
			elif _event.is_action_pressed("dodge_dash"):
				dodge_or_sprint()
				
			elif _event.is_action_released("dodge_dash") \
			&& sprint_timer.time_left:
				dodge()
			
			elif _event.is_action_pressed("change_primary"):
				weapon_change()
			elif _event.is_action_pressed("change_secondary"):
				gadget_change()

			elif _event.is_action_pressed("use_gadget_strong"): 
					use_gadget()
					
			elif _event.is_action_pressed("use_gadget_light"):
				if secondary_action:
					use_gadget()
				else:
					start_guard()
			
			elif _event.is_action_pressed("use_item"): 
				use_item()
		else: # if not on floor
			if _event.is_action_pressed("use_weapon_light"):
				air_attack()
	
	elif current_state == state.SPRINT:
		
		if _event.is_action_released("dodge_dash"):
			end_sprint()
		elif _event.is_action_pressed("jump"):
				jump()
				
	elif current_state == state.LADDER:
		if _event.is_action_pressed("dodge_dash"):
			current_state = state.FREE
				
	if _event.is_action_released("use_gadget_light"):
		if not secondary_action:
			end_guard()
			
	
			
func _physics_process(_delta):
	
	match current_state:
		state.FREE:
			rotate_player()
			free_movement()

		state.SPRINT:
			rotate_player()
			free_movement()
			
		state.DODGE:
			rotate_player()
			dash_movement()
			
		state.LADDER:
			ladder_movement()
			
		state.ATTACK:
			dash_movement()
			
		state.AIRATTACK:
			air_movement()
		
		state.DYNAMIC_ACTION:
			free_movement()
			rotate_player()
			
	apply_gravity(_delta)
	
func apply_gravity(_delta):
	if !is_on_floor() \
	&& current_state != state.LADDER:
		velocity.y -= gravity * _delta
		
func free_movement():
	# Get the movement orientation from the angles of the player to the camera.
	# Using only camera's basis rotation created weird speed inconsistencies at downward angles
	#dodge_movement()
	input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var new_direction = calc_direction()
	if new_direction:
		var rate : float # imiates directional change acceleration rate
		if is_on_floor():
			rate = .5
		else:
			rate = .1 # Makes it hard to change directions once in midair
		velocity.x = move_toward(velocity.x, new_direction.x * speed, rate)
		velocity.z = move_toward(velocity.z, new_direction.z * speed, rate)
	else: # Smoothly come to a stop
		velocity.x = move_toward(velocity.x, 0, .5)
		velocity.z = move_toward(velocity.z, 0, .5)
	move_and_slide()
	
func rotate_player():
	var target_rotation
	var current_rotation = global_transform.basis.get_rotation_quaternion()
	
	# StrafeCam code - Look at target, slerping current rotation to the camera's rotation.
	if strafing == true && current_state != state.DODGE: # Strafing looks at enemy
		target_rotation = current_rotation.slerp(Quaternion(Vector3.UP, orientation_target.global_rotation.y + PI), 0.4)
		global_transform.basis = Basis(target_rotation)
		# Assuming forwardVector and newMovementDirection are your vectors
		var forward_vector = global_transform.basis.z.normalized() # Example: Forward vector of the character
		
		strafe_cross_product = -forward_vector.cross(calc_direction().normalized()).y
		move_dot_product = forward_vector.dot(calc_direction().normalized())

	# Otherwise freelook, which is when not strafing or dodging, as well as, when rolling as you strafe. 
	elif (strafing == false and current_state != state.DODGE) or (strafing == true and current_state == state.DODGE): # .... else:
		# FreeCam rotation code, slerps to input oriented to the camera perspective, and only calculates when input is given
		if input_dir:
			var new_direction = calc_direction().normalized()
			# Rotate the player per the perspective of the camera
			target_rotation = current_rotation.slerp(Quaternion(Vector3.UP, atan2(new_direction.x, new_direction.z)), 0.2)
			global_transform.basis = Basis(target_rotation)
	# move_and_slide() unused here. Controlled by States and free_movement().

func strafe_targeting():
	strafing = !strafing
	strafe_toggled.emit(strafing)

## calculate and return the direction of movement oriented to the current camera
func calc_direction():
	var forward_vector = Vector3(0, 0, 1).rotated(Vector3.UP, current_camera.global_rotation.y)
	var horizontal_vector = Vector3(1, 0, 0).rotated(Vector3.UP, current_camera.global_rotation.y)
	var new_direction = (forward_vector * input_dir.y + horizontal_vector * input_dir.x)
	return new_direction

func attack(_is_special_attack : bool = false):
	current_state = state.ATTACK
	anim_length = .5
	if anim_state_tree: 
		await anim_state_tree.animation_measured
	attack_started.emit(anim_length,_is_special_attack)
	await get_tree().create_timer(anim_length *.4).timeout
	attack_swing_started.emit()
	dash(Vector3.FORWARD,.2) ## delayed dash to move forward during attack animation
	await get_tree().create_timer(anim_length *.4).timeout
	attack_ended.emit()
	if current_state == state.ATTACK:
		current_state = state.FREE

func air_attack():
	current_state = state.AIRATTACK
	if anim_state_tree: 
		await anim_state_tree.animation_measured
	attack_started.emit(anim_length)
	await get_tree().create_timer(.3).timeout
	attack_swing_started.emit()
		
func air_movement():
	move_and_slide()
	if is_on_floor():
		if current_state == state.AIRATTACK:
			attack_ended.emit()
		current_state = state.FREE
		
func jump():
	if anim_state_tree:
		jump_started.emit()
		anim_length = .5
		if anim_state_tree:
			await anim_state_tree.animation_measured
		var jump_duration = anim_length
	# After timer finishes, return to pre-dodge state
		await get_tree().create_timer(jump_duration *.7).timeout
	velocity.y = jump_velocity

func dash(_new_direction : Vector3 = Vector3.FORWARD, _duration = .2): 
	# burst of speed toward indicated direction, or forward by default
	speed = dodge_speed
	direction = (global_position - to_global(_new_direction)).normalized()
	speed = default_speed
	velocity = direction * speed
	await get_tree().create_timer(_duration).timeout
	direction = Vector3.ZERO
	
func dodge_or_sprint():
	if sprint_timer.is_stopped():
		sprint_timer.start(.3)
		await sprint_timer.timeout
		if current_state == state.FREE \
			&& input_dir:
				current_state = state.SPRINT
				sprint_started.emit()
		
func end_sprint():
	if current_state == state.SPRINT:
		current_state = state.FREE
		
func dodge(): 
	# Burst of speed toward an input direction, or backwards
	current_state = state.DODGE
	can_be_hurt = false
	sprint_timer.stop()
	var dodge_duration : float = .5
	if input_dir: # Dodge toward direction of input_dir 
		direction = calc_direction()
		dodge_started.emit()

	else: # Dodge toward the 'BACK' of your global position
		direction = (global_position - to_global(Vector3.BACK)).normalized()
		dodge_started.emit()
	if anim_state_tree:
		await anim_state_tree.animation_measured
		dodge_duration = anim_length
	# After timer finishes, return to pre-dodge state
	await get_tree().create_timer(dodge_duration).timeout
	dodge_ended.emit()
	current_state = state.FREE
	can_be_hurt = true
	speed = default_speed
	direction = Vector3.ZERO
		
func dash_movement():
	# required in the process function states for dodges/dashes
	velocity = direction * speed
	move_and_slide()
	
func ladder_movement():
	# move up and down ladders per the indicated direction
	input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = (Vector3.DOWN * input_dir.y) * speed
	# exiting ladder state triggers:
	if interact_loc == "BOTTOM":
		exit_ladder("TOP") 
	if is_on_floor():
		exit_ladder("BOTTOM")
	move_and_slide()

func start_ladder(top_or_bottom,mount_transform):
	ladder_started.emit(top_or_bottom)
	var wait_time = .4
	# After timer finishes, return to pre-dodge state
	var tween = create_tween()
	tween.tween_property(self,"global_transform", mount_transform, wait_time)
	await tween.finished
	current_state = state.LADDER
	
func exit_ladder(exit_loc):
	current_state = state.STATIC_ACTION
	ladder_finished.emit(exit_loc)
	var dismount_pos
	var dismount_time = .3
	if anim_state_tree:
		await anim_state_tree.animation_measured
		dismount_time = anim_length *.6
	match exit_loc:
		"TOP":
			dismount_pos = to_global(Vector3(0,1.5,.5))
		"BOTTOM":
			dismount_pos = global_position
	var tween = create_tween()
	tween.tween_property(self,"global_position", dismount_pos,dismount_time)
	await tween.finished
	current_state = state.FREE

func _on_animation_measured(_new_length):
	anim_length = _new_length - .05 # offset slightly for the process frame
	#print("Anim Length: " + str(anim_length))

func _on_interact_updated(_int_bottom, _int_top):
	## This updates the interactable objects and
	## which sensor spotted it if you have an 
	## if an interact sensor added to the export.
	if _int_bottom && _int_top:
		interactable = _int_bottom
		interact_loc = "BOTH"
	elif _int_bottom && _int_top == null:
		interactable = _int_bottom
		interact_loc = "BOTTOM"
	elif _int_bottom == null && _int_top:
		interactable = _int_top
		interact_loc = "TOP"
	else:
		interactable = null
		interact_loc = ""
	print(str(interactable) + " at " + interact_loc)
	
func interact():
	## interactions are a handshake. The interactable will reply back with more
	## info or actions if needed.
	if interactable:
		interactable.activate(self,interact_loc)
	
func start_door(door_transform, move_time):
	current_state = state.STATIC_ACTION
	# After timer finishes, return to pre-dodge state
	var tween = create_tween()
	tween.tween_property(self,"global_transform", door_transform, move_time)
	await tween.finished
	door_started.emit()
	await get_tree().create_timer(1.5).timeout
	current_state = state.FREE

func start_gate(gate_transform, move_time):
	current_state = state.STATIC_ACTION
	# After timer finishes, return to pre-dodge state
	var tween = create_tween()
	tween.tween_property(self,"global_transform", gate_transform, move_time)
	await tween.finished
	gate_started.emit()
	await get_tree().create_timer(1.5).timeout
	current_state = state.FREE

func weapon_change():
	current_state = state.DYNAMIC_ACTION
	weapon_change_started.emit()
	var change_duration = .5
	if anim_state_tree:
		await anim_state_tree.animation_measured
		change_duration = anim_length
	await get_tree().create_timer(change_duration*.5).timeout
	weapon_changed.emit()
	if weapon_system:
		await weapon_system.equipment_changed
	print(weapon_type)
	weapon_change_ended.emit(weapon_type)
	await get_tree().create_timer(change_duration*.5).timeout
	current_state = state.FREE
	
func _on_weapon_equipment_changed(_new_weapon:EquipmentObject):
	weapon_type = _new_weapon.equipment_info.object_type

func _on_gadget_equipment_changed(_new_gadget:EquipmentObject):
	gadget_type = _new_gadget.equipment_info.object_type

func gadget_change():
	current_state = state.DYNAMIC_ACTION
	gadget_change_started.emit()
	var change_duration = .5
	if anim_state_tree:
		await anim_state_tree.animation_measured
		change_duration = anim_length
	await get_tree().create_timer(change_duration*.5).timeout
	gadget_changed.emit()
	await get_tree().create_timer(change_duration*.5).timeout
	current_state = state.FREE

func start_guard(): # Guarding, and for a short window, parring is possible
	guarding = true
	parry_active = true
	current_state = state.DYNAMIC_ACTION
	await get_tree().create_timer(parry_window).timeout
	parry_active = false
	
func end_guard():
	guarding = false
	parry_active = false
	current_state = state.FREE

func use_gadget(): # emits to start the gadget, and runs some timers before stopping the gadget
	current_state = state.STATIC_ACTION
	gadget_started.emit()
	if anim_state_tree:
		await anim_state_tree.animation_started
		var attack_duration = anim_length
		gadget_activated.emit(anim_length)
		await get_tree().create_timer(attack_duration *.45).timeout
		dash()
		gadget_swing_started.emit()
		await get_tree().create_timer(attack_duration *.3).timeout
		gadget_deactivated.emit()
	else:
		gadget_activated.emit(.1)
		await get_tree().create_timer(.3).timeout
		dash()
		gadget_swing_started
		gadget_deactivated.emit()
	if current_state == state.STATIC_ACTION:
		current_state = state.FREE

func hit(_who, _by_what):
	if can_be_hurt:
		if parry_active:
			parry()
			if _who.has_method("parried"):
				_who.parried()
			return
		elif guarding:
			block()
		else:
			damage_taken.emit(_by_what)
			hurt()

func block():
	current_state = state.STATIC_ACTION
	block_started.emit()
	anim_length = .4
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	if current_state == state.STATIC_ACTION:
		current_state = state.FREE

func parry():
	current_state = state.STATIC_ACTION
	can_be_hurt = false
	parry_started.emit()
	anim_length = .4
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	if current_state == state.STATIC_ACTION:
		current_state = state.FREE
	can_be_hurt = true

func hurt():
	current_state = state.STATIC_ACTION
	can_be_hurt = false
	hurt_started.emit()
	anim_length = .4
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	if current_state == state.STATIC_ACTION:
		current_state = state.FREE
	can_be_hurt = true

func use_item():
	current_state = state.DYNAMIC_ACTION
	use_item_started.emit()
	anim_length = 1.0
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length * .5).timeout
	item_used.emit()
	await get_tree().create_timer(anim_length * .5).timeout
	if current_state == state.DYNAMIC_ACTION:
		current_state = state.FREE

func death():
	current_state = state.STATIC_ACTION
	can_be_hurt = false
	death_started.emit()
	await get_tree().create_timer(3).timeout
	
