extends Node

# The colony's stockpile: how much sand, rock, wood and so on the ants have gathered.
# This is the one place that knows the amounts. The resource panel only shows them and
# the save writes them out, so a counter can never drift from the real stock.

# One resource changed. The id is "sand", "rock", and so on.
signal changed(id: String, total: int)
# The whole stockpile was replaced at once, for example because a save was loaded
signal all_changed

var amounts: Dictionary = {}

func get_amount(id: String) -> int:
	return int(amounts.get(id, 0))

# Digging and carrying call this. A negative amount is ignored here; use spend() for that.
func add(id: String, amount: int) -> void:
	if amount <= 0:
		return
	amounts[id] = get_amount(id) + amount
	changed.emit(id, get_amount(id))

# Takes `amount` out of the stockpile. Returns false (and changes nothing) when there is
# not enough, so a room can never be built from sand that is not there.
func spend(id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	var total := get_amount(id)
	if total < amount:
		return false
	amounts[id] = total - amount
	changed.emit(id, total - amount)
	return true

func set_amount(id: String, amount: int) -> void:
	var clamped := maxi(amount, 0)
	if get_amount(id) == clamped:
		return
	amounts[id] = clamped
	changed.emit(id, clamped)

func reset() -> void:
	amounts.clear()
	all_changed.emit()

func to_dict() -> Dictionary:
	return amounts.duplicate()

func from_dict(data: Dictionary) -> void:
	amounts.clear()
	for id in data:
		amounts[str(id)] = maxi(int(data[id]), 0)
	all_changed.emit()
