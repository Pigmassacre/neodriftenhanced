extends Node2D
## First checkpoint scaffold: shows the practice course and lets you fly the
## camera over it with the arrow keys.
##
## For automated comparison against MAME, run with
##   -- --camera=X,Y --zoom=ZX,ZY --shot=/path/out.png
## to render one frame at that camera position and zoom and quit.

const FLY_SPEED := 4

var data := GameData.new()
var camera := Vector2i(232, 15869)
## 8.8 fixed point; 0x100 is 1:1, smaller values zoom out.
var zoom := Vector2i(0x100, 0x100)
var shot_path := ""

@onready var background: ColorRect = $Background


func _ready() -> void:
	# the project leaves the window unscaled (game.gd enlarges its own picture)
	var window := get_window()
	window.content_scale_size = Vector2i(320, 224)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	if data.load_course("practice") != OK:
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camera="):
			var parts := arg.trim_prefix("--camera=").split(",")
			camera = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--zoom="):
			var parts := arg.trim_prefix("--zoom=").split(",")
			zoom = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--shot="):
			shot_path = arg.trim_prefix("--shot=")
	var material := background.material as ShaderMaterial
	material.set_shader_parameter("map_tex", data.map)
	material.set_shader_parameter("tiles_tex", data.tiles)
	material.set_shader_parameter("pal_tex", data.palette)
	material.set_shader_parameter("zoom_y_tex", data.zoom_y)
	material.set_shader_parameter("map_size", data.map_size)
	material.set_shader_parameter("raster", data.bg_raster)
	_apply_camera()
	if shot_path != "":
		_take_shot()


func _physics_process(_delta: float) -> void:
	var move := Vector2i(
			int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left")),
			int(Input.is_action_pressed("ui_down")) - int(Input.is_action_pressed("ui_up")))
	if move != Vector2i.ZERO:
		camera += move * FLY_SPEED
		_apply_camera()


func _apply_camera() -> void:
	var material := background.material as ShaderMaterial
	material.set_shader_parameter("camera", camera)
	material.set_shader_parameter("zoom", zoom)
	material.set_shader_parameter("shrink_steps", data.bg_shrink_steps[zoom.x & 15])
	material.set_shader_parameter("x_steps", data.bg_x_steps[zoom.x & 15])


func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_path)
	get_tree().quit()
