extends Node2D
class_name OilPuddle

## 油迹存活时间（秒）
@export var lifetime: float = 5.0

func _ready() -> void:
	# 初始带有一点随机旋转与轻微抖动，显得更自然
	rotation = randf() * TAU
	
	# 创建生命周期补间动画：保持显示并在最后 0.8 秒淡出销毁
	var tween = create_tween()
	# 前段等待（5秒生命周期，前4.2秒完全显示）
	tween.tween_interval(max(0.0, lifetime - 0.8))
	# 后段平滑淡出
	tween.tween_property(self, "modulate:a", 0.0, 0.8)
	tween.tween_callback(queue_free)
