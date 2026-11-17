@tool
extends Node
## Native editor windows can belong to separate GUI drag sections. Route only
## scene-reference drops across those windows; leave all other editor drags alone.
class DestinationInput extends Node:
	var receiver: Callable
	func _input(event: InputEvent) -> void:
		if receiver.is_valid(): receiver.call(event, get_viewport())

var source: Viewport
var destination: Window
var observer: Node
var _data: Variant
var _hover: Control

func configure(main: Viewport, window: Window) -> void:
	source = main
	destination = window
	observer = DestinationInput.new()
	observer.receiver = _receive
	destination.add_child(observer)

func _capture() -> void:
	for viewport in [source, destination]:
		if not is_instance_valid(viewport) or not viewport.gui_is_dragging(): continue
		var data: Variant = viewport.gui_get_drag_data()
		if data is Dictionary and data.get("type") == "nodes":
			_data = data
			return
	_data = null

func _process(_delta: float) -> void:
	_capture()
	if _data == null or not is_instance_valid(destination) or not destination.visible:
		_set_hover(null)
		return
	_update_hover(Vector2(DisplayServer.mouse_get_position()))

func _set_hover(target: Control) -> void:
	if is_instance_valid(_hover) and _hover != target:
		_hover.remove_meta("scene_reference_cross_hover")
		_hover._set_highlight(false)
	_hover = target
	if is_instance_valid(_hover):
		_hover.set_meta("scene_reference_cross_hover", true)
		_hover._set_highlight(true)

func _update_hover(screen_point: Vector2) -> void:
	# force_native windows in an embedding editor have their own OS origin;
	# get_screen_transform can still include the embedder's origin.
	var point := destination.get_final_transform().affine_inverse() * (screen_point - Vector2(destination.position))
	if not Rect2(Vector2.ZERO, destination.size).has_point(point): _set_hover(null); return
	for target in get_tree().get_nodes_in_group("godot_level_editor_reference_drop"):
		if target.get_viewport() != destination or not target.is_visible_in_tree() or target.is_queued_for_deletion(): continue
		if not Rect2(Vector2.ZERO, target.size).has_point(target.get_global_transform_with_canvas().affine_inverse() * point): continue
		var clipped := false
		var parent: Node = target.get_parent()
		while parent is Control:
			if parent.clip_contents and not Rect2(Vector2.ZERO, parent.size).has_point(parent.get_global_transform_with_canvas().affine_inverse() * point): clipped = true; break
			parent = parent.get_parent()
		if not clipped and target.resolve.is_valid() and not str(target.resolve.call(_data)).is_empty(): _set_hover(target); return
	_set_hover(null)

func _input(event: InputEvent) -> void:
	_receive(event, get_viewport())

func _receive(event: InputEvent, viewport: Viewport) -> void:
	if not event is InputEventMouse: return
	_capture()
	if _data == null or not is_instance_valid(destination) or not destination.visible: return
	var screen_point: Vector2 = viewport.get_screen_transform() * event.position
	if viewport is Window: screen_point = Vector2(viewport.position) + viewport.get_final_transform() * event.position
	_update_hover(screen_point)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and is_instance_valid(_hover):
		var target := _hover
		var data: Variant = _data
		_set_hover(null)
		_data = null
		target._drop_data(Vector2.ZERO, data)
		# Clear the source drag once, before native GUI fallback can interpret it as
		# a scene-tree reparent. The actual graph mutation is deferred by the field.
		for active in [source, destination]:
			if is_instance_valid(active) and active.gui_is_dragging(): active.gui_cancel_drag()
		viewport.set_input_as_handled()

func _exit_tree() -> void:
	_set_hover(null)
	if is_instance_valid(observer): observer.queue_free()
