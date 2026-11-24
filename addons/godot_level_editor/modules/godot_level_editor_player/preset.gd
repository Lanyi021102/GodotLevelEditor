@tool
extends Resource
## A level references this resource. Runtime input and movement state are per player.
const DEFAULT_MODEL := preload("res://addons/godot_level_editor/assets/characters/quaternius_base/adapted_human.tscn")
const DIRECTORY := "res://content/resources/player_presets"
const WORLD := 1
const CHARACTER := 2
const FIRST_PERSON := 1
const FIXED := 2

const TABS := ["角色", "镜头", "控制"]
const FIELDS := [
	[
		["walk", "行走", true], ["walk_speed", "走速（米/秒）", 1.8, 0.1, 25.0, 0.1],
		["run", "跑步", true], ["run_speed", "跑速（米/秒）", 4.6, 0.1, 30.0, 0.1],
		["sprint", "冲刺", false], ["sprint_speed", "冲刺速度（米/秒）", 6.2, 0.1, 40.0, 0.1],
		["acceleration", "加速度（米/秒²）", 21.0, 0.1, 120.0, 0.1],
		["deceleration", "减速度（米/秒²）", 29.0, 0.1, 120.0, 0.1],
		["turn_speed", "转身响应", 15.0, 0.1, 50.0, 0.1],
		["height", "站姿高度（米）", 1.78, 0.3, 5.0, 0.01],
		["radius", "碰撞半径（米）", 0.27, 0.05, 1.0, 0.01],
		["slope", "可走坡度（度）", 45.0, 0.0, 80.0, 1.0],
		["jump", "跳跃", true], ["jump_height", "跳高（米）", 1.7, 0.1, 8.0, 0.1],
		["extra_jump", "二段跳", false], ["extra_jump_height", "二段跳高度（米）", 1.0, 0.1, 8.0, 0.1],
		["gravity", "重力（米/秒²）", 24.0, 0.1, 80.0, 0.1],
		["air_acceleration", "空中加速度（米/秒²）", 7.0, 0.0, 80.0, 0.1],
		["crouch", "蹲行", false], ["crouch_height", "蹲姿高度（米）", 1.2, 0.25, 5.0, 0.01],
		["crouch_speed", "蹲行速度（米/秒）", 1.3, 0.1, 10.0, 0.1],
		["step", "自动上台阶", false], ["step_height", "台阶上限（米）", 0.25, 0.05, 0.6, 0.01],
		["vault", "翻越", false], ["vault_height", "翻越高度上限（米）", 1.05, 0.25, 2.5, 0.05],
		["vault_depth", "翻越厚度上限（米）", 0.6, 0.15, 2.0, 0.05],
		["vault_time", "翻越耗时（秒）", 0.45, 0.15, 2.0, 0.05],
		["mantle", "抓边上台", false], ["auto_mantle", "空中自动抓边", false],
		["mantle_height", "抓边高度上限（米）", 1.55, 0.25, 3.5, 0.05],
		["mantle_time", "上台耗时（秒）", 0.65, 0.15, 2.0, 0.05],
		["climb", "攀爬", false], ["climb_speed", "攀爬速度（米/秒）", 1.5, 0.1, 8.0, 0.1],
		["dodge", "闪避翻滚", false], ["dodge_distance", "翻滚距离（米）", 2.2, 0.2, 8.0, 0.1],
		["dodge_time", "翻滚耗时（秒）", 0.55, 0.15, 2.0, 0.05],
		["drive_vehicles", "可驾驶载具", true],
		["interact", "基础交互", true], ["interact_distance", "交互筛选上限（米）", 1.6, 0.3, 20.0, 0.1],
	],
	[
		["view", "基础视角", 0, ["第三人称越肩", "第一人称", "固定角度"]],
		["look", "自由观察", true], ["occlusion", "镜头避障", true],
		["focus", "近距观察", true], ["shoulder_swap", "换肩", true], ["recenter", "回正", true],
		["distance", "镜头距离（米）", 3.8, 0.5, 20.0, 0.1],
		["eye_height", "第一人称眼高（米）", 1.62, 0.2, 5.0, 0.01],
		["pivot_height", "第三人称观察中心高度（米）", 1.45, 0.2, 5.0, 0.01],
		["shoulder", "越肩侧向偏移（米）", 0.55, 0.0, 2.0, 0.01],
		["yaw", "起始水平角（度）", 0.0, -180.0, 360.0, 1.0],
		["pitch", "起始俯角（度）", 10.0, -85.0, 85.0, 1.0],
		["min_pitch", "最小俯角（度）", -35.0, -89.0, 89.0, 1.0],
		["max_pitch", "最大俯角（度）", 65.0, -89.0, 89.0, 1.0],
		["fov", "垂直视野角（度）", 65.0, 25.0, 125.0, 1.0],
		["focus_distance", "近距观察距离（米）", 2.3, 0.2, 20.0, 0.1],
		["focus_fov", "近距垂直视野角（度）", 50.0, 20.0, 110.0, 1.0],
		["focus_shoulder", "近距越肩偏移（米）", 0.65, 0.0, 2.0, 0.01],
		["focus_smoothing", "近距过渡响应", 12.0, 0.1, 45.0, 0.1],
		["follow_smoothing", "跟随响应", 18.0, 0.1, 45.0, 0.1],
		["collision_radius", "相机探测半径（米）", 0.18, 0.03, 1.0, 0.01],
	],
	[
		["move_reference", "移动方向参照", 0, ["相机", "世界", "角色"]],
		["face_camera", "角色朝向", 0, ["移动方向", "相机方向"]],
		["run_input", "跑步触发", 0, ["按住", "切换", "摇杆推满"]],
		["sprint_input", "冲刺触发", 0, ["按住", "切换"]],
		["crouch_input", "蹲行触发", 0, ["按住", "切换"]],
		["focus_input", "近距观察触发", 0, ["按住", "切换"]],
		["jump_buffer", "跳跃缓冲", true], ["jump_buffer_time", "跳跃缓冲（秒）", 0.12, 0.0, 0.5, 0.01],
		["coyote", "离地宽容", true], ["coyote_time", "离地宽容（秒）", 0.12, 0.0, 0.5, 0.01],
		["mouse_speed", "鼠标灵敏度（度/像素）", 0.16, 0.01, 2.0, 0.01],
		["invert_y", "反转观察纵轴", false],
		["move_deadzone", "移动摇杆死区", 0.20, 0.0, 0.8, 0.01],
		["look_deadzone", "观察摇杆死区", 0.18, 0.0, 0.8, 0.01],
		["stick_speed", "摇杆最大观察速度（度/秒）", 180.0, 10.0, 720.0, 1.0],
	],
]
# [label, old action, keyboard key, gamepad button (-1 if analogue only)]
const ACTIONS := {
	"forward": ["前进", "move_forward", KEY_W, -1], "back": ["后退", "move_back", KEY_S, -1],
	"left": ["左移", "move_left", KEY_A, -1], "right": ["右移", "move_right", KEY_D, -1],
	"run": ["跑步", "sprint", KEY_SHIFT, JOY_BUTTON_LEFT_STICK],
	"sprint": ["冲刺", "", KEY_CTRL, JOY_BUTTON_RIGHT_STICK],
	"jump": ["跳跃", "jump", KEY_SPACE, JOY_BUTTON_A],
	"crouch": ["蹲行", "", KEY_C, JOY_BUTTON_B],
	"traverse": ["翻越 / 抓边", "", KEY_E, JOY_BUTTON_Y],
	"climb": ["开始 / 停止攀爬", "", KEY_X, JOY_BUTTON_X],
	"dodge": ["闪避翻滚", "", KEY_Q, JOY_BUTTON_LEFT_SHOULDER],
	"interact": ["基础交互", "interact", KEY_F, JOY_BUTTON_DPAD_UP],
	"swap": ["换肩", "camera_swap_shoulder", KEY_V, JOY_BUTTON_DPAD_LEFT],
	"recenter": ["回正", "", KEY_R, JOY_BUTTON_DPAD_DOWN],
	"focus": ["近距观察", "", KEY_Z, JOY_BUTTON_RIGHT_SHOULDER],
}
const CLIPS := {
	"idle": ["待机", "Idle"], "walk": ["行走", "Walking_A"], "run": ["跑步", "Running_A"],
	"sprint": ["冲刺", "moves/Sprint"], "jump_start": ["起跳", "Jump_Start"],
	"air": ["空中", "Jump_Idle"], "land": ["落地", "Jump_Land"],
	"crouch_idle": ["蹲姿待机", "Crouch_Idle"], "crouch": ["蹲行", "Walking_C"],
	"step": ["上台阶（选填）", ""],
	"vault": ["翻越", "moves/Vault"],
	"mantle": ["抓边上台", "moves/Mantle"], "climb": ["攀爬", "moves/Climb"],
	"dodge": ["闪避翻滚", "moves/Roll"], "interact": ["交互（选填）", "moves/Interact"],
}

@export var display_name := "默认第三人称"
@export var model_scene: PackedScene
@export var animation_scene: PackedScene
@export var values: Dictionary = {}
@export var clip_overrides: Dictionary = {}
@export var bindings: Dictionary = {}

static func defaults() -> Dictionary:
	var result := {}
	for group in FIELDS:
		for field in group:
			result[field[0]] = field[2]
	return result

func settings() -> Dictionary:
	var result := defaults()
	for group in FIELDS:
		for field in group:
			var id: String = field[0]
			var value: Variant = values.get(id, field[2])
			if field.size() == 3:
				result[id] = value if value is bool else field[2]
			elif (value is int or value is float) and is_finite(float(value)):
				result[id] = clampi(int(value), 0, field[3].size() - 1) if field.size() == 4 else clampf(float(value), field[3], field[4])
	result.radius = minf(result.radius, result.height * 0.5)
	result.crouch_height = clampf(result.crouch_height, 2.0 * result.radius, result.height)
	result.max_pitch = maxf(result.min_pitch, result.max_pitch)
	result.pitch = clampf(result.pitch, result.min_pitch, result.max_pitch)
	return result

func clip(slot: String) -> String:
	return str(clip_overrides.get(slot, "" if model_scene != null else CLIPS[slot][1]))

func update_from(other: Resource) -> void:
	display_name = other.display_name
	model_scene = other.model_scene
	animation_scene = other.animation_scene
	values = other.values.duplicate(true)
	clip_overrides = other.clip_overrides.duplicate(true)
	bindings = other.bindings.duplicate(true)
	emit_changed()

static func library_paths() -> PackedStringArray:
	var found := PackedStringArray()
	if not DirAccess.dir_exists_absolute(DIRECTORY): return found
	for file in DirAccess.get_files_at(DIRECTORY):
		if file.get_extension() == "tres":
			found.append(DIRECTORY.path_join(file))
	found.sort()
	return found
