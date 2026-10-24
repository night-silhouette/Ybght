extends CharacterBody2D
class_name Tank

@export_group("Player Controls")
## 玩家编号（1: AWSD + 空格开火； 2: 左右下箭头 + 小键盘0/Insert 开火）
@export_enum("Player 1 (AWSD)", "Player 2 (Arrows)") var player_id: int = 0

## 允许自定义按键绑定（如留空则按照 player_id 自动分配）
@export var key_left: Key = KEY_NONE
@export var key_right: Key = KEY_NONE
@export var key_backward: Key = KEY_NONE
@export var key_fire: Key = KEY_NONE

@export_group("Speed Settings")
## 逆时针旋转角速度（弧度/秒，例如 2.5 约 143 度/秒）
@export var rotate_ccw_speed: float = 2.5

## 顺时针旋转角速度（弧度/秒）
@export var rotate_cw_speed: float = 2.5

## 前进线速度（像素/秒）
@export var forward_speed: float = 160.0

## 后退线速度（像素/秒）
@export var backward_speed: float = 120.0

@export_group("Shooting Settings")
## 子弹发射速度（像素/秒，可直接在检查器中调节）
@export var bullet_speed: float = 380.0

## 子弹最大反弹次数
@export var bullet_max_bounces: int = 3

## 子弹预制体场景
@export var bullet_scene: PackedScene = preload("res://bullet.tscn")

@onready var muzzle: Marker2D = $Muzzle

## 最大生命值（承受子弹命中次数）
@export var max_health: int = 3
var current_health: int = 3
var is_dead: bool = false

## 贴图引用（普通与护盾形态）
@export var normal_texture: Texture2D = preload("res://war of tanks/tank_circle_thick.png")
@export var shielded_texture: Texture2D = preload("res://war of tanks/tank_shielded_transparent.png")

## 护盾无敌与加速状态
var is_invulnerable: bool = false
var speed_multiplier: float = 1.0
var _shield_timer: SceneTreeTimer = null

## 油迹生成设置
@export var oil_puddle_scene: PackedScene = preload("res://oil_puddle.tscn")
var _oil_timer: float = 0.0
var _is_leaking_oil: bool = false

signal health_changed(new_health: int, max_health: int)
signal died()

func _ready() -> void:
	# 根据玩家编号初始化默认按键
	if key_left == KEY_NONE or key_right == KEY_NONE or key_backward == KEY_NONE or key_fire == KEY_NONE:
		if player_id == 0:
			# Player 1
			key_left = KEY_A
			key_right = KEY_D
			key_backward = KEY_S
			key_fire = KEY_SPACE
		else:
			# Player 2
			key_left = KEY_LEFT
			key_right = KEY_RIGHT
			key_backward = KEY_DOWN
			key_fire = KEY_KP_0
	
	current_health = max_health
	emit_signal("health_changed", current_health, max_health)

func take_damage(amount: int = 1) -> void:
	if is_dead or is_invulnerable:
		return
	current_health = max(0, current_health - amount)
	emit_signal("health_changed", current_health, max_health)
	
	# 受击轻微震动或变红提示
	var sprite = $Sprite2D
	if sprite:
		var tween = create_tween()
		sprite.modulate = Color(1.0, 0.2, 0.2, 1.0)
		tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)
	
	if current_health <= 0:
		die()
	elif current_health == 1:
		# 触发只剩一滴血时的油迹泄漏
		_is_leaking_oil = true
		_oil_timer = 0.0
		_spawn_oil_puddle() # 受到致命伤剩1滴血瞬间立即留下第一处油迹
		
		# 触发只剩一滴血时的护盾效果：5s 无敌、+50% 前进后退线速度、切换贴图
		activate_last_stand_shield()

func activate_last_stand_shield() -> void:
	is_invulnerable = true
	speed_multiplier = 1.5 # 50% 加速（线速度乘 1.5）
	
	# 更换为护盾形态贴图
	var sprite = $Sprite2D as Sprite2D
	if sprite and shielded_texture:
		sprite.texture = shielded_texture
	
	# 启动 5 秒计时器
	var timer = get_tree().create_timer(5.0)
	_shield_timer = timer
	timer.timeout.connect(func():
		# 仅当依然存活时恢复
		if not is_dead and _shield_timer == timer:
			deactivate_last_stand_shield()
	)

func deactivate_last_stand_shield() -> void:
	is_invulnerable = false
	speed_multiplier = 1.0
	
	# 恢复原来的普通形态贴图
	var sprite = $Sprite2D as Sprite2D
	if sprite and normal_texture:
		sprite.texture = normal_texture

func reset_state() -> void:
	is_dead = false
	is_invulnerable = false
	speed_multiplier = 1.0
	_shield_timer = null
	_is_leaking_oil = false
	_oil_timer = 0.0
	current_health = max_health
	modulate = Color(1, 1, 1, 1)
	set_physics_process(true)
	var col = $CollisionShape2D
	if col:
		col.set_deferred("disabled", false)
	var sprite = $Sprite2D as Sprite2D
	if sprite and normal_texture:
		sprite.texture = normal_texture
	emit_signal("health_changed", current_health, max_health)

func die() -> void:
	if is_dead:
		return
	is_dead = true
	_is_leaking_oil = false
	emit_signal("died")
	# 坦克阵亡效果：半透明并禁用物理碰撞与控制
	modulate = Color(0.4, 0.4, 0.4, 0.5)
	set_physics_process(false)
	var col = $CollisionShape2D
	if col:
		col.set_deferred("disabled", true)

func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == key_fire:
			fire()
		# 针对小键盘0在部分键盘上映射为 Keypad 0 或 Insert 的兼容
		elif player_id == 1 and (event.keycode == KEY_KP_0 or event.key_label == KEY_KP_0 or event.keycode == KEY_INSERT):
			fire()

func fire() -> void:
	# 阵亡或处于护盾无敌期（5s内）禁止射击
	if is_dead or is_invulnerable or not bullet_scene:
		return
	
	var bullet = bullet_scene.instantiate() as Bullet
	if not bullet:
		return
	
	# 获取炮管前端在世界坐标中的位置与前进朝向
	var spawn_pos: Vector2 = muzzle.global_position if muzzle else global_position
	var forward_dir: Vector2 = Vector2.UP.rotated(rotation)
	
	# 配置子弹速度与反弹参数
	bullet.max_bounces = bullet_max_bounces
	bullet.speed = bullet_speed
	
	# 将子弹加入当前场景树
	get_parent().add_child(bullet)
	bullet.setup(spawn_pos, forward_dir, bullet_speed, self)

func _spawn_oil_puddle() -> void:
	if not oil_puddle_scene:
		return
	var puddle = oil_puddle_scene.instantiate() as Node2D
	if not puddle:
		return
	puddle.global_position = global_position
	# 放置在地图层中（坦克下方显示）
	get_parent().add_child(puddle)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	# 从只剩一滴血开始，每隔 1s 在坦克当前坐标产生一个油迹
	if _is_leaking_oil and current_health == 1:
		_oil_timer += delta
		if _oil_timer >= 1.0:
			_oil_timer -= 1.0
			_spawn_oil_puddle()
	
	# 获取玩家配置按键状态
	var press_left: bool = Input.is_key_pressed(key_left)
	var press_right: bool = Input.is_key_pressed(key_right)
	var press_back: bool = Input.is_key_pressed(key_backward)
	
	velocity = Vector2.ZERO
	
	# 规则判断：
	# 1. 如果按了后退键（S 或 下箭头），同时还按了任意其他转向键，则无反应
	if press_back:
		if press_left or press_right:
			move_and_slide()
			return
		else:
			# 仅按后退键：向后移动（沿坦克朝向的后方，受 50% 加速影响）
			var forward_dir = Vector2.UP.rotated(rotation)
			velocity = -forward_dir * (backward_speed * speed_multiplier)
			move_and_slide()
			return
	
	# 2. 同时按左右键（A+D 或 左箭头+右箭头）：向前移动（受 50% 加速影响）
	if press_left and press_right:
		var forward_dir = Vector2.UP.rotated(rotation)
		velocity = forward_dir * (forward_speed * speed_multiplier)
		move_and_slide()
		return
	
	# 3. 仅按左键：逆时针旋转（角速度不受加速影响）
	if press_left:
		rotation -= rotate_ccw_speed * delta
	
	# 4. 仅按右键：顺时针旋转（角速度不受加速影响）
	elif press_right:
		rotation += rotate_cw_speed * delta
	
	move_and_slide()
