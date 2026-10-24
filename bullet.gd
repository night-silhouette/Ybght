extends CharacterBody2D
class_name Bullet

@export_group("Bullet Settings")
## 子弹飞行线速度（像素/秒）
@export var speed: float = 380.0

## 最大反弹次数（超过后子弹销毁）
@export var max_bounces: int = 3

# 当前已反弹次数
var bounce_count: int = 0
# 发射此子弹的来源坦克，避免刚出炮口时误伤自己
var shooter: CharacterBody2D = null

func setup(initial_pos: Vector2, initial_dir: Vector2, custom_speed: float = -1.0, shooter_ref: CharacterBody2D = null) -> void:
	global_position = initial_pos
	rotation = initial_dir.angle() + PI / 2.0
	shooter = shooter_ref
	if custom_speed > 0:
		speed = custom_speed
	velocity = initial_dir.normalized() * speed

func _physics_process(delta: float) -> void:
	# 用 move_and_collide 进行精确物理步进并捕获法线碰撞
	var collision = move_and_collide(velocity * delta)
	if collision:
		var collider = collision.get_collider()
		
		# 判断是否击中了坦克
		if collider is Tank:
			# 如果是发射者自己，且子弹尚未发生过墙体反弹（刚开火从炮管出来时），不误伤
			if collider == shooter and bounce_count == 0:
				pass
			else:
				# 击中坦克，扣除血量
				if collider.has_method("take_damage"):
					collider.take_damage(1)
				queue_free()
				return
		
		var normal = collision.get_normal()
		bounce_count += 1
		if bounce_count > max_bounces:
			# 超过最大反弹次数，子弹消失
			queue_free()
			return
		
		# 根据碰撞接触点法线进行完全弹性镜面反弹
		velocity = velocity.bounce(normal)
		# 保持速度大小不变
		velocity = velocity.normalized() * speed
		# 同步子弹飞行朝向（贴图默认头朝上）
		rotation = velocity.angle() + PI / 2.0
