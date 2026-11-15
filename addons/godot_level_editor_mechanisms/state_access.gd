@tool
extends RefCounted
## Stable world-object + local-component references. Never use display names or NodePaths as IDs.
const SEPARATOR := "::"

static func _walk(node: Node, prefix: String, result: Dictionary) -> void:
	if node.has_method("get_state") and node.has_method("state_names"):
		result[prefix + str(node.get("object_id"))] = node
		return
	for child in node.get_children():
		var scope := prefix
		if child.has_method("configure") and child.get("instance_id") is String:
			scope += str(child.get("instance_id")) + "/"
		_walk(child, scope, result)

static func components(anchor: Node) -> Dictionary:
	var result := {}
	if not is_instance_valid(anchor): return result
	var source: Node = anchor
	if anchor.get("runtime_component") is Node: source = anchor.get("runtime_component")
	_walk(source, "", result)
	return result

static func resolve_anchor(anchor: Node, local: String = "") -> Node:
	var found := components(anchor)
	if not local.is_empty(): return found.get(local)
	if found.size() == 1: return found.values()[0]
	if is_instance_valid(anchor) and anchor.has_method("output_component"):
		var output: Node = anchor.output_component()
		if is_instance_valid(output) and output.has_method("get_state"): return output
	return null

static func resolve_with(lookup: Callable, reference: String) -> Node:
	if not lookup.is_valid(): return null
	var parts := reference.split(SEPARATOR, true, 1)
	return resolve_anchor(lookup.call(parts[0]), str(parts[1]) if parts.size() > 1 else "")

static func resolve(world: Node, reference: String) -> Node:
	return resolve_with(world.object_by_id, reference) if is_instance_valid(world) else null

static func targets(world: Node) -> Dictionary:
	var result := {}
	if not is_instance_valid(world): return result
	for reference in world.objects():
		var found := components(world.object_by_id(reference))
		for local in found: result[str(reference) + SEPARATOR + str(local)] = found[local]
	return result

static func descriptions(world: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(world): return result
	for reference in world.objects():
		var anchor: Node = world.object_by_id(reference)
		var temporary: Node
		var found := components(anchor)
		if found.is_empty() and anchor.get("component_scene") is PackedScene:
			temporary = anchor.component_scene.instantiate(); found = components(temporary)
		for local in found:
			var component: Node = found[local]
			var title := str(component.get("display_name"))
			if title.is_empty(): title = str(component.name)
			result.append({"reference": str(reference) + SEPARATOR + str(local), "title": str(anchor.name) + " / " + title, "states": component.state_names(), "requestable": component.requestable_states(), "actions": component.action_names()})
		if temporary != null: temporary.free()
	result.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.reference) < str(b.reference))
	return result
