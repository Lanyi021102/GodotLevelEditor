@tool
extends Resource
## Shared definition only. Runtime and editor previews always build private environments.
@export var version := 1
@export var display_name := "新天空"
@export_enum("程序天空", "HDRI", "光照模板") var sky_mode := 0
@export var base_environment: Environment
@export var hdri: Texture2D
@export var hdri_rotation := 0.0
@export var sky_energy := 1.0
@export var hdri_lighting := true
@export_enum("晴朗", "多云", "阴天", "薄雾") var weather := 0
@export_enum("手动角度", "按时刻") var sun_mode := 0
@export var hour := 12.0
@export var elevation := 48.0
@export var azimuth := 38.0
@export var north_offset := 0.0
@export var sun_energy := 2.65
@export var sun_color := Color(1.0, 0.937, 0.84)
@export var sun_size := 1.8
@export var shadows := true
@export var ambient_color := Color(0.69, 0.8, 0.92)
@export var ambient_energy := 0.32
@export var exposure := 1.08
@export var top_color := Color(0.24, 0.48, 0.76)
@export var horizon_color := Color(0.78, 0.85, 0.9)
@export var ground_color := Color(0.39, 0.43, 0.47)
@export var clouds_enabled := true
@export var cloud_coverage := 0.3
@export var cloud_height := 1200.0
@export var cloud_scale := 900.0
@export var cloud_color := Color(0.94, 0.95, 0.96)
@export var cloud_seed := 3.0
@export var fog_enabled := false
@export var fog_color := Color(0.72, 0.8, 0.87)
@export var fog_begin := 35.0
@export var fog_end := 160.0
@export var fog_density := 0.35

func copy_preset() -> Resource:
	var copy := duplicate(true)
	# Assets stay external references; runtime duplicates the Environment before editing it.
	copy.hdri = hdri
	copy.base_environment = base_environment
	return copy

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if version != 1: errors.append("不支持的天空预设版本")
	if display_name.strip_edges().is_empty(): errors.append("请填写天空名称")
	if sky_mode < 0 or sky_mode > 2 or sun_mode < 0 or sun_mode > 1 or weather < 0 or weather > 3: errors.append("天空模式无效")
	if sky_mode == 1 and hdri == null: errors.append("请选择 HDRI 素材")
	if sky_mode == 2 and base_environment == null: errors.append("光照模板缺少环境资源")
	for key in ["hour", "elevation", "azimuth", "north_offset", "hdri_rotation", "sky_energy", "sun_energy", "sun_size", "ambient_energy", "exposure", "cloud_height", "cloud_scale", "cloud_seed", "cloud_coverage", "fog_begin", "fog_end", "fog_density"]:
		if not is_finite(float(get(key))): errors.append("参数无效：" + key)
	if hour < 0 or hour > 24 or elevation < -90 or elevation > 90: errors.append("时刻或太阳高度超出范围")
	if cloud_height < 1 or cloud_scale < 1 or cloud_coverage < 0 or cloud_coverage > 1: errors.append("云层参数无效")
	if fog_begin < 0 or fog_end <= fog_begin or fog_density < 0 or fog_density > 1: errors.append("雾距离或浓度无效")
	if sun_energy < 0 or ambient_energy < 0 or sky_energy < 0 or exposure <= 0 or sun_size < 0: errors.append("光照强度无效")
	return errors

func solar_angles() -> Vector2:
	if sun_mode == 0: return Vector2(elevation, azimuth)
	# A consistent artistic day: sunrise 06:00, noon 12:00, sunset 18:00.
	var phase := (hour - 6.0) / 12.0
	return Vector2(sin(phase * PI) * 65.0, fposmod(90.0 + phase * 180.0 + north_offset, 360.0))

func summary() -> String:
	var angles := solar_angles()
	var clock := "%02d:%02d" % [int(hour) % 24, int((hour - floor(hour)) * 60.0) % 60]
	return "%s · %s · 高度 %.0f° / 方位 %.0f°" % [["程序天空", "HDRI", "光照模板"][clampi(sky_mode, 0, 2)], clock if sun_mode == 1 else "手动", angles.x, angles.y]
