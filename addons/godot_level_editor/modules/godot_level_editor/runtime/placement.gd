@tool
extends Node3D
## Existing component adapter. Component graphs can be supplied as a PackedScene.
@export var object_id := ""
@export_enum("plate", "kinetic", "breaker", "door", "guard", "placeholder", "lever") var component_kind := "plate"
@export var component_scene: PackedScene
## Optional output endpoint inside a reusable assembly; empty means its root.
@export var component_output_path: NodePath
@export var component_definition: Resource
@export var initially_active := true
@export var source_ids := PackedStringArray()
@export var require_all_sources := true
@export_range(0.0, 10.0) var release_delay := 0.65
@export var patrol_local := PackedVector3Array([Vector3(-2, 0, 0), Vector3(2, 0, 0)])
@export_multiline var placeholder_contract := "由宿主创建并绑定玩家，加入 godot_level_editor_player 组。"
var runtime_component: Node3D
var _editor_signature: Array = []

func _enter_tree() -> void:
	if object_id.is_empty(): object_id = "object_" + Crypto.new().generate_random_bytes(10).hex_encode()

func _ready() -> void:
	if Engine.is_editor_hint():
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3.6, 2.3, 0.4) if component_kind == "door" else Vector3(1.6, 0.18, 1.6)
		if component_kind == "guard":
			box.size = Vector3(0.7, 1.8, 0.7)
		mesh.mesh = box
		mesh.position.y = box.size.y * 0.5 if component_kind != "door" else 0.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("d3925e") if component_kind == "guard" else Color("43c5b9")
		mesh.material_override = mat
		add_child(mesh)
		var label := Label3D.new()
		label.text = {"plate": "压力板", "kinetic": "动能板", "breaker": "电闸", "door": "门", "guard": "敌人", "lever": "开关", "placeholder": "自定义组件"}.get(component_kind, "组件")
		label.position.y = 2.5
		label.font_size = 32
		add_child(label)
		_editor_signature = [component_kind, object_id]
		return
	if component_scene != null:
		runtime_component = component_scene.instantiate()
	else:
		match component_kind:
			"lever": runtime_component = preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/runtime/lever.gd").new()
			"plate": runtime_component = preload("res://addons/godot_level_editor/scripts/world/pressure_plate.gd").new()
			"kinetic": runtime_component = preload("res://addons/godot_level_editor/scripts/gameplay/kinetic_plate.gd").new()
			"breaker": runtime_component = preload("res://addons/godot_level_editor/scripts/world/breaker.gd").new()
			"door": runtime_component = preload("res://addons/godot_level_editor/scripts/world/power_door.gd").new()
			"guard": runtime_component = preload("res://addons/godot_level_editor/modules/enemy_editor/runtime/npc_actor.tscn").instantiate()
			_: return # Explicit integration marker, no fabricated gameplay.
	if runtime_component == null:
		return
	runtime_component.name = "Component"
	var instance_key := (str(get_parent().get("room_id")) if get_parent().get("room_id") is String else "$world") + "/" + object_id
	var world: Node = get_parent() if get_parent().get("world_id") is String else get_parent().get_parent()
	if world != null and world.get("world_id") is String:
		instance_key = str(world.get("world_id")) + "/" + instance_key
	for property in runtime_component.get_property_list():
		if property.name == "instance_id": runtime_component.set("instance_id", instance_key)
	if component_scene == null and component_kind in ["plate", "kinetic"]:
		runtime_component.set("release_delay", release_delay)
	if component_scene == null and component_kind == "door":
		runtime_component.set("require_all_sources", require_all_sources)
		runtime_component.set("panel_size", Vector3(3.6, 2.3, 0.4))
	if component_kind == "guard":
		# Strip the removed timeline adapter when loading an old scene.
		var old_adapter := runtime_component.get_node_or_null("Rewindable")
		if old_adapter != null:
			old_adapter.free()
		var points: Array[Vector3] = []
		for point in patrol_local:
			points.append(to_global(point))
		runtime_component.set("patrol_points", points)
		if component_definition != null:
			runtime_component.set("enemy_definition", component_definition)
		for property in runtime_component.get_property_list():
			if property.name == "enemy_instance_id":
				runtime_component.set("enemy_instance_id", instance_key)
	if component_scene == null and component_kind == "breaker":
		runtime_component.set("dark_offset", global_basis * Vector3(0, 1.7, 0))
	add_child(runtime_component)
	if component_kind == "guard": runtime_component.set_physics_process(initially_active)
	if runtime_component.has_method("configure_level"):
		runtime_component.call("configure_level", {"object_id": object_id, "placement": self})

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _editor_signature != [component_kind, object_id]:
		for child in get_children():
			if child.owner == null: child.free()
		_ready()

func is_powered() -> bool:
	var output := output_component()
	return output != null and output.has_method("is_powered") and output.call("is_powered")

func output_component() -> Node:
	if runtime_component == null: return null
	return runtime_component if component_output_path.is_empty() else runtime_component.get_node_or_null(component_output_path)

func _exit_tree() -> void:
	# The legacy light service has no unregister API; at least retire our own zone.
	if not Engine.is_editor_hint() and component_kind == "breaker" and runtime_component != null:
		var id: Variant = runtime_component.get("_dark_id")
		if id is int and id >= 0:
			get_node("/root/GLELightZones").set_dynamic_enabled(id, false)
