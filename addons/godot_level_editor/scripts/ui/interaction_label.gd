@tool
extends Label3D
## World-space caption and anchor for the selected screen-space hint.
var endpoint: Node3D
var caption := ""
var action_hint := ""
var focus_only := false
const WORLD_PIXEL_SIZE := 0.005
const FOCUS_LABEL := &"_gle_interaction_label"
var _player: Node3D

func configure(source: Node3D, title: String, action: String, only_on_focus := false) -> void:
	endpoint = source
	caption = title
	action_hint = action
	focus_only = only_on_focus
	font_size = 36
	outline_size = 6
	alpha_cut = Label3D.ALPHA_CUT_DISCARD
	pixel_size = WORLD_PIXEL_SIZE
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text = "" if focus_only else caption
	if Engine.is_editor_hint(): set_process(false)
	else: endpoint.set_meta(FOCUS_LABEL, self)

func _process(_delta: float) -> void:
	if not is_instance_valid(endpoint): return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("godot_level_editor_player") as Node3D
	var target: Variant = _player.get("interaction_target") if is_instance_valid(_player) else null
	var selected := target as Node3D if is_instance_valid(target) else null
	var content := caption
	if focus_only or selected == endpoint or (is_instance_valid(selected) and selected.global_position.distance_squared_to(endpoint.global_position) <= 12.25):
		content = ""
	if text != content: text = content
	if content.is_empty() or not is_visible_in_tree(): return
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d()
	if camera == null: return
	var depth := -camera.to_local(global_position).z
	if depth <= camera.near: return
	var center := viewport.get_visible_rect().get_center()
	var world_pixel := camera.project_position(center, depth).distance_to(camera.project_position(center + Vector2.RIGHT, depth))
	var axes := global_basis.get_scale().abs()
	var parent_scale := maxf(axes[axes.max_axis_index()], 0.001)
	var effective_size := minf(WORLD_PIXEL_SIZE, 21.0 * world_pixel / (font_size * parent_scale))
	if not is_equal_approx(pixel_size, effective_size): pixel_size = effective_size
