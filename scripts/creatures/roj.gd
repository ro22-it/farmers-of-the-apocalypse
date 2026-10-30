class_name Roj
extends Gryadochnik

## Рой: стая мелких тёмных волчат. Каждый ведёт себя как Грядочник — бежит
## к грядке, ест, уносит добычу, боится света, — но падает с одного удара
## и приходит толпой с одной стороны леса.


func _animate(_delta: float) -> void:
	_loot.visible = carrying != ""
	match state:
		State.FLEE, State.SCARED:
			_look.play("Gallop", 1.5)
		State.APPROACH:
			_look.play("Gallop", 1.1)
		State.CHEW, State.EAT:
			_look.play("Eating", 1.6)
		State.TRAPPED:
			_look.play("Idle_HitReact1", 1.2)
		_:
			_look.play("Idle")
