extends Node
## Deprecated compatibility facade. Gameplay has no energy resource or costs.
signal changed(energy: float)
var energy_max := 100.0
var cumulative := 0.0
var energy := 100.0
func spend(_amount: float) -> void: pass
func spend_per_second(_rate: float, _delta: float) -> void: pass
func restore_cumulative(_value: float) -> void: pass
func reset() -> void: pass
func is_empty() -> bool: return false
func spent_total() -> float: return 0.0
