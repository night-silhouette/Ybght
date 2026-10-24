extends Area2D
class_name RepairKit

## 医疗包预制体脚本：无阻挡物理体积，坦克不满血时可自由穿过并拾取，可被子弹拆毁，30s自动消失
@export var health: int = 1
## 医疗包存在时长（秒）
@export var lifetime: float = 30.0
var is_destroyed: bool = false
var _lifetime_tween: Tween = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	
	# 存在 30s 自动消失逻辑：前 28s 正常显示，最后 2s 平滑淡出并自动清理
	_lifetime_tween = create_tween()
	_lifetime_tween.tween_interval(max(0.0, lifetime - 2.0))
	_lifetime_tween.tween_property(self, "modulate:a", 0.0, 2.0)
	_lifetime_tween.tween_callback(queue_free)

func _on_body_entered(body: Node2D) -> void:
	if is_destroyed:
		return
	if body is Bullet:
		body.queue_free()
		destroy_kit()
	elif body is Tank:
		# 只有当坦克确实不满血时才触发拾取回血，满血时穿过不消耗医疗包
		if body.current_health < body.max_health:
			body.current_health = min(body.max_health, body.current_health + 1)
			body.emit_signal("health_changed", body.current_health, body.max_health)
			destroy_kit()

func destroy_kit() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	if _lifetime_tween and _lifetime_tween.is_valid():
		_lifetime_tween.kill()
	var col = $CollisionShape2D
	if col:
		col.set_deferred("disabled", true)
	set_deferred("monitoring", false)
	# 销毁时的轻微渐隐动画
	var tween = create_tween()
	tween.tween_property(self, "scale", scale * 1.25, 0.15)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_callback(queue_free)
