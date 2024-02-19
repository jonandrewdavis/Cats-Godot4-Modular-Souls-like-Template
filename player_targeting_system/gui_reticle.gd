extends Control

@onready var reticle_image = $ReticleImage


@export var targeting_system : PlayerTargetingSystem
@export var targeting_singal_string : String = "target_found"
var targeting = false
var target : Node = null

func _ready():
	if targeting_system:
		if targeting_system.has_signal(targeting_singal_string):
			targeting_system.connect(targeting_singal_string,_on_player_targeting_system_target_found)

	
func _process(_delta):
	if targeting_system.targeting:
		show_reticle()
	else:
		hide()


func _on_player_targeting_system_target_found(_new_target):
	target = _new_target
	print(target)
	print("reticle got a target")
	
func show_reticle():
	if !is_instance_valid(target):
		target = null
	else:
		show()
		var current_camera = get_viewport().get_camera_3d()
		var screenspace = current_camera.unproject_position(target.global_position)
		position = screenspace

