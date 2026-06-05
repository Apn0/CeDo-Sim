extends Node
## #3 — Shift-leader scan log. Every row here is a REAL bale scan: it exists only
## because the barcode gun actually read a bale in-world (BarcodeScanner._scan_in_front
## → EventBus.bale_scanned). Nothing is pre-seeded. The shift-leader's computer
## (ShiftLeaderDesk → ShiftLeaderTerminal) reads this to show the day's traceability
## list: which bale, when, by whom, which line.

const MAX_ENTRIES : int = 250

var _entries : Array[Dictionary] = []

func _ready() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("bale_scanned"):
		bus.bale_scanned.connect(_on_bale_scanned)

func _on_bale_scanned(entry: Dictionary) -> void:
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries = _entries.slice(_entries.size() - MAX_ENTRIES)
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("scanlog_changed"):
		bus.emit_signal("scanlog_changed")

## Newest-first copy for the terminal.
func entries() -> Array:
	var out := _entries.duplicate()
	out.reverse()
	return out

func count() -> int:
	return _entries.size()

## Total weighed mass scanned this session (kg) — a quick KPI for the footer.
func total_kg() -> float:
	var t := 0.0
	for e in _entries:
		t += float(e.get("weight_kg", 0))
	return t

func clear() -> void:
	_entries.clear()
