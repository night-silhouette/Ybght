@tool
extends Node2D
class_name TankMap

@export_group("Map Dimensions")
## 地图整体显示宽度（像素）
@export var map_width: float = 960.0:
	set(val):
		map_width = max(100.0, val)
		queue_redraw()
		_update_collision_shapes()
		_update_camera()

## 地图整体显示高度（像素）
@export var map_height: float = 800.0:
	set(val):
		map_height = max(100.0, val)
		queue_redraw()
		_update_collision_shapes()
		_update_camera()

## 墙体厚度（像素）
@export var wall_thickness: float = 6.0:
	set(val):
		wall_thickness = max(1.0, val)
		queue_redraw()
		_update_collision_shapes()

@export_group("Camera Settings")
## 自动摄像机：无论地图长宽如何修改、窗口如何放大/最大化，都能全程看到整张地图
@export var auto_fit_camera: bool = true:
	set(val):
		auto_fit_camera = val
		_update_camera()

## 摄像机四周留白边距（像素）
@export var camera_margin: float = 0.0:
	set(val):
		camera_margin = val
		_update_camera()

@export_group("Visual Style")
## 背景色（可通过区域，默认为原图纯白色）
@export var walkable_color: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(val):
		walkable_color = val
		queue_redraw()

## 墙壁颜色（不可通过障碍，默认为原图纯黑色）
@export var wall_color: Color = Color(0.0, 0.0, 0.0, 1.0):
	set(val):
		wall_color = val
		queue_redraw()

@export_group("Physics")
## 碰撞层（Collision Layer）
@export_flags_2d_physics var collision_layer: int = 1:
	set(val):
		collision_layer = val
		if static_body:
			static_body.collision_layer = collision_layer

## 碰撞遮罩（Collision Mask）
@export_flags_2d_physics var collision_mask: int = 1:
	set(val):
		collision_mask = val
		if static_body:
			static_body.collision_mask = collision_mask

# 静态物理碰撞体引用
var static_body: StaticBody2D
# 摄像机引用
var camera: Camera2D

# 归一化线段数据：[x1, y1, x2, y2]（基于原图 960x800 精准提取的全部障碍物墙体）
const BASE_WALLS: Array = [
	# 外边框上侧（中间开门）
	[72, 60, 408, 60],
	[408, 60, 408, 100],
	[408, 100, 444, 100],
	[516, 100, 552, 100],
	[552, 100, 552, 60],
	[552, 60, 888, 60],
	
	# 外边框下侧（中间开门）
	[72, 740, 408, 740],
	[408, 740, 408, 700],
	[408, 700, 444, 700],
	[516, 700, 552, 700],
	[552, 700, 552, 740],
	[552, 740, 888, 740],
	
	# 外边框左侧与右侧
	[72, 60, 72, 740],
	[888, 60, 888, 740],
	
	# 中间水平横线带缺口通道（Y=400）
	[72, 400, 192, 400],
	[228, 400, 300, 400],
	[356, 400, 448, 400],
	[512, 400, 604, 400],
	[660, 400, 732, 400],
	[768, 400, 888, 400],
	
	# 左上区域内部墙体
	[144, 100, 312, 100],
	[144, 100, 144, 320],
	[216, 320, 312, 320],
	[312, 160, 312, 352],
	
	# 右上区域内部墙体
	[648, 100, 816, 100],
	[816, 100, 816, 320],
	[648, 320, 744, 320],
	[648, 160, 648, 352],
	
	# 左下区域内部墙体
	[144, 700, 312, 700],
	[144, 480, 144, 700],
	[216, 480, 312, 480],
	[312, 448, 312, 640],
	
	# 右下区域内部墙体
	[648, 700, 816, 700],
	[816, 480, 816, 700],
	[648, 480, 744, 480],
	[648, 448, 648, 640],
	
	# 中心上方区域拐角墙体
	[372, 160, 492, 160],
	[492, 160, 492, 216],
	[468, 270, 590, 270],
	[468, 270, 468, 320],
	
	# 中心下方区域拐角墙体
	[468, 480, 468, 530],
	[468, 530, 590, 530],
	[372, 640, 492, 640],
	[492, 588, 492, 640]
]

func _ready() -> void:
	_setup_collision()
	_setup_tank_positions()
	_setup_camera()
	_setup_health_ui()
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _setup_tank_positions() -> void:
	var tank1 = get_node_or_null("Tank1") as Node2D
	var tank2 = get_node_or_null("Tank2") as Node2D
	
	# 根据当前地图 map_width 和 map_height 动态匹配凹槽坐标
	# 地图基准尺寸 960x800，凹槽中心 X 为 480 (map_width/2)
	# 顶部凹槽开门在 Y=60~100 之间，在当前地图中按比例换算放置
	if tank1:
		tank1.position = Vector2(map_width * 0.5, map_height * (80.0 / 800.0))
		tank1.rotation = PI # 炮口朝下面向战场
	if tank2:
		tank2.position = Vector2(map_width * 0.5, map_height * (720.0 / 800.0))
		tank2.rotation = 0.0 # 炮口朝上面向战场

func _setup_health_ui() -> void:
	var tank1 = get_node_or_null("Tank1") as Tank
	var tank2 = get_node_or_null("Tank2") as Tank
	
	# 创建固定在屏幕视口的 CanvasLayer UI
	var hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	
	var repair_texture = load("res://war of tanks/repair_kit_transparent.png")
	
	# --- 玩家 1（Tank1）血量：屏幕左下角 ---
	if tank1:
		var p1_panel = VBoxContainer.new()
		p1_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		p1_panel.position = Vector2(24, -90)
		hud.add_child(p1_panel)
		
		var p1_label = Label.new()
		p1_label.text = "P1 (AWSD + 空格)"
		p1_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1, 1.0))
		p1_panel.add_child(p1_label)
		
		var box1 = HBoxContainer.new()
		box1.name = "HealthContainerP1"
		box1.add_theme_constant_override("separation", 10)
		p1_panel.add_child(box1)
		
		var update_p1 = func(hp: int, _max_hp: int):
			for child in box1.get_children():
				child.queue_free()
			for i in range(hp):
				var icon = TextureRect.new()
				icon.texture = repair_texture
				icon.custom_minimum_size = Vector2(40, 40)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				box1.add_child(icon)
		
		tank1.health_changed.connect(update_p1)
		update_p1.call(tank1.current_health, tank1.max_health)
		
		# 监听 P1 阵亡：展示 P2 胜利画面
		tank1.died.connect(func():
			_show_game_over(hud, "res://war of tanks/game_over_p2_win.webp")
		)
	
	# --- 玩家 2（Tank2）血量：屏幕右下角 ---
	if tank2:
		var p2_panel = VBoxContainer.new()
		p2_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		# 靠右下角布局
		p2_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		p2_panel.position = Vector2(-220, -90)
		hud.add_child(p2_panel)
		
		var p2_label = Label.new()
		p2_label.text = "P2 (方向键 + 小键盘0)"
		p2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		p2_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1, 1.0))
		p2_panel.add_child(p2_label)
		
		var box2 = HBoxContainer.new()
		box2.name = "HealthContainerP2"
		box2.alignment = BoxContainer.ALIGNMENT_END
		box2.add_theme_constant_override("separation", 10)
		p2_panel.add_child(box2)
		
		var update_p2 = func(hp: int, _max_hp: int):
			for child in box2.get_children():
				child.queue_free()
			for i in range(hp):
				var icon = TextureRect.new()
				icon.texture = repair_texture
				icon.custom_minimum_size = Vector2(40, 40)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				box2.add_child(icon)
		
		tank2.health_changed.connect(update_p2)
		update_p2.call(tank2.current_health, tank2.max_health)
		
		# 监听 P2 阵亡：展示 P1 胜利画面
		tank2.died.connect(func():
			_show_game_over(hud, "res://war of tanks/game_over_p1_win.webp")
		)

var _game_over_shown: bool = false
var _can_accept_input: bool = false
var _p1_ready: bool = false
var _p2_ready: bool = false
var _p1_check_icon: Label = null
var _p2_check_icon: Label = null
var _game_over_overlay: Control = null

func _show_game_over(hud: CanvasLayer, image_res_path: String) -> void:
	if _game_over_shown:
		return
	_game_over_shown = true
	_can_accept_input = false
	_p1_ready = false
	_p2_ready = false
	
	# 整个窗口全覆盖容器（无黑边、无留白完全铺满）
	var overlay = Control.new()
	overlay.name = "GameOverOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(overlay)
	_game_over_overlay = overlay
	
	# 结算图本体（设置拉伸模式为铺满整个屏幕，忽略比例直接拉满或自适应充满）
	var tex_rect = TextureRect.new()
	tex_rect.name = "GameOverImage"
	tex_rect.texture = load(image_res_path)
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex_rect.anchor_right = 1.0
	tex_rect.anchor_bottom = 1.0
	tex_rect.offset_left = 0
	tex_rect.offset_top = 0
	tex_rect.offset_right = 0
	tex_rect.offset_bottom = 0
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE # 完全铺满整个视口，无黑边无留白
	overlay.add_child(tex_rect)
	
	# 绿色对勾：按比例绑定到按钮相对坐标（原图 512x512 下按钮位置：P1=(190, 395), P2=(455, 395)）
	_p1_check_icon = Label.new()
	_p1_check_icon.text = ""
	_p1_check_icon.add_theme_color_override("font_color", Color(0.1, 0.75, 0.2, 1.0))
	overlay.add_child(_p1_check_icon)
	
	_p2_check_icon = Label.new()
	_p2_check_icon.text = ""
	_p2_check_icon.add_theme_color_override("font_color", Color(0.1, 0.75, 0.2, 1.0))
	overlay.add_child(_p2_check_icon)
	
	_resize_game_over_ui()
	
	# 入场弹出微动效
	overlay.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(overlay, "modulate", Color(1, 1, 1, 1), 0.25)
	
	# 延迟 1 秒后才允许接收 Space 和 0 的按键输入
	get_tree().create_timer(1.0).timeout.connect(func():
		_can_accept_input = true
	)

func _resize_game_over_ui() -> void:
	if not _game_over_overlay or not is_instance_valid(_game_over_overlay):
		return
	
	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return
	
	# 保持 overlay 和图片铺满视口
	_game_over_overlay.size = vp_size
	var tex = _game_over_overlay.get_node_or_null("GameOverImage") as TextureRect
	if tex:
		tex.size = vp_size
	
	# 对勾大小和位置根据当前窗口分辨率（宽/高）进行等比精准定位
	# 原基准图尺寸为 512 x 512:
	# P1 按钮框约位于相对位置 (190/512 = 37.1%, 395/512 = 77.1%)
	# P2 按钮框约位于相对位置 (455/512 = 88.8%, 395/512 = 77.1%)
	var font_sz = int(round(clamp(vp_size.y * 0.08, 24, 120)))
	
	if _p1_check_icon:
		_p1_check_icon.add_theme_font_size_override("font_size", font_sz)
		_p1_check_icon.position = Vector2(vp_size.x * (190.0 / 512.0), vp_size.y * (395.0 / 512.0))
	
	if _p2_check_icon:
		_p2_check_icon.add_theme_font_size_override("font_size", font_sz)
		_p2_check_icon.position = Vector2(vp_size.x * (455.0 / 512.0), vp_size.y * (395.0 / 512.0))

func _unhandled_input(event: InputEvent) -> void:
	if not _game_over_shown or not _can_accept_input:
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		# P1 按 Space 切换对勾
		if event.keycode == KEY_SPACE:
			_p1_ready = not _p1_ready
			_update_check_icons()
			_check_both_ready()
			get_viewport().set_input_as_handled()
		# P2 按 小键盘 0 / Insert 切换对勾
		elif event.keycode == KEY_KP_0 or event.key_label == KEY_KP_0 or event.keycode == KEY_INSERT:
			_p2_ready = not _p2_ready
			_update_check_icons()
			_check_both_ready()
			get_viewport().set_input_as_handled()

func _update_check_icons() -> void:
	if _p1_check_icon:
		_p1_check_icon.text = "√" if _p1_ready else ""
	if _p2_check_icon:
		_p2_check_icon.text = "√" if _p2_ready else ""

func _check_both_ready() -> void:
	# 双方都有对勾时，重置游戏状态并让结算图消失
	if _p1_ready and _p2_ready:
		_restart_game()

func _restart_game() -> void:
	# 1. 结算图与对勾淡出并销毁消失
	var overlay = get_node_or_null("HUD/GameOverOverlay")
	if overlay:
		overlay.queue_free()
	
	_game_over_shown = false
	_p1_ready = false
	_p2_ready = false
	_p1_check_icon = null
	_p2_check_icon = null
	
	# 2. 清理场上残留的所有子弹和残留油迹
	for child in get_children():
		if child is Bullet or child is OilPuddle:
			child.queue_free()
	
	# 3. 复位双方坦克状态、血量和位置
	_setup_tank_positions()
	
	var tank1 = get_node_or_null("Tank1") as Tank
	var tank2 = get_node_or_null("Tank2") as Tank
	
	if tank1:
		tank1.reset_state()
		
	if tank2:
		tank2.reset_state()

func _on_viewport_size_changed() -> void:
	_update_camera()
	_resize_game_over_ui()

func _setup_camera() -> void:
	camera = get_node_or_null("MapCamera") as Camera2D
	if not camera:
		camera = Camera2D.new()
		camera.name = "MapCamera"
		add_child(camera)
	camera.enabled = true
	_update_camera()

func _update_camera() -> void:
	if not camera or not auto_fit_camera:
		return
	
	# 将摄像机对准地图中心
	camera.position = Vector2(map_width / 2.0, map_height / 2.0)
	
	# 获取当前视口显示区域大小
	var vp = get_viewport()
	var vp_size = vp.get_visible_rect().size if vp else Vector2.ZERO
	if vp_size.x <= 0 or vp_size.y <= 0:
		vp_size = Vector2(960, 800)
	
	var target_w = max(1.0, map_width + camera_margin * 2.0)
	var target_h = max(1.0, map_height + camera_margin * 2.0)
	
	# 自适应缩放系数：根据当前地图的实际尺寸（如您设置的 1800x1500）与视口大小计算
	# 确保无论地图改为多大多小，整个地图都 100% 完整呈现在视野中
	camera.zoom = Vector2(vp_size.x / target_w, vp_size.y / target_h)

func _input(event: InputEvent) -> void:
	# 支持按 F11 或 Alt+Enter 随时切换全屏 / 窗口化
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			toggle_fullscreen()

func toggle_fullscreen() -> void:
	var mode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _setup_collision() -> void:
	if not static_body:
		static_body = StaticBody2D.new()
		static_body.name = "MapWallsStaticBody"
		static_body.collision_layer = collision_layer
		static_body.collision_mask = collision_mask
		add_child(static_body)
	_update_collision_shapes()

func _update_collision_shapes() -> void:
	if not static_body:
		return
	# 清除现有碰撞形状
	for child in static_body.get_children():
		child.queue_free()
	
	var scale_x = map_width / 960.0
	var scale_y = map_height / 800.0
	
	for wall in BASE_WALLS:
		var p1 = Vector2(wall[0] * scale_x, wall[1] * scale_y)
		var p2 = Vector2(wall[2] * scale_x, wall[3] * scale_y)
		
		var col_shape = CollisionShape2D.new()
		var segment = SegmentShape2D.new()
		segment.a = p1
		segment.b = p2
		col_shape.shape = segment
		static_body.add_child(col_shape)

func _draw() -> void:
	# 绘制可通过的白色底板
	draw_rect(Rect2(0, 0, map_width, map_height), walkable_color, true)
	
	var scale_x = map_width / 960.0
	var scale_y = map_height / 800.0
	
	# 绘制不可通过的黑色阻挡墙体
	for wall in BASE_WALLS:
		var p1 = Vector2(wall[0] * scale_x, wall[1] * scale_y)
		var p2 = Vector2(wall[2] * scale_x, wall[3] * scale_y)
		draw_line(p1, p2, wall_color, wall_thickness, true)
