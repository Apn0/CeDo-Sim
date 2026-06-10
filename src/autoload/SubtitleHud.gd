extends CanvasLayer
##
## Lightweight subtitle overlay. Listens to Walkie signals (call_received,
## transmit_sent) and prints the line at the bottom of the screen for a few
## seconds. Reads two settings live:
##
##   Settings → Gameplay → "Subtitles"       (bool)  master enable
##   Settings → Gameplay → "Subtitle size"   (string)  small / medium / large
##
## Designed as an autoload so it doesn't depend on the HUD's lifecycle —
## subtitles still work in menus, during pause, on the main menu, etc.

const DURATION_S      := 5.0      # how long a line lingers before fading
const FADE_OUT_S      := 0.6
const SIZE_FONT_PX    := { "small": 18, "medium": 24, "large": 30 }
const MAX_VISIBLE_LINES := 3

var _container : VBoxContainer = null
var _lines     : Array         = []   # [{label: Label, dies_at: float}]
# (Each fade is its own short Tween created on demand inside push_line /
# _kill_line; no shared instance to track.)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11                    # above the HUD (which is layer 10)
	_container = VBoxContainer.new()
	_container.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_container.offset_top    = -180.0
	_container.offset_bottom = -56.0    # above interaction prompt
	_container.offset_left   = 80.0
	_container.offset_right  = -80.0
	_container.alignment     = BoxContainer.ALIGNMENT_END
	_container.add_theme_constant_override("separation", 4)
	add_child(_container)

	# Subscribe to walkie traffic — the only TTS source in v0.1.
	var walkie := get_node_or_null("/root/Walkie")
	if walkie:
		if walkie.has_signal("call_received"):
			walkie.call_received.connect(_on_walkie_call_received)
		if walkie.has_signal("transmit_sent"):
			walkie.transmit_sent.connect(_on_walkie_transmit_sent)

func _on_walkie_call_received(from_name: String, text: String, heard: bool) -> void:
	if not heard: return     # if the player can't hear it on radio, no subtitle
	push_line("%s: %s" % [from_name, text])

func _on_walkie_transmit_sent(text: String, heard: bool) -> void:
	if not heard: return
	push_line("You: %s" % text)

## Public API — any subsystem can call SubtitleHud.push_line(...) once we
## extend beyond walkie (announcements, machine alarms, etc.).
func push_line(text: String) -> void:
	if not _subtitles_enabled(): return
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", _size_px())
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.modulate = Color(1, 1, 1, 0.0)
	_container.add_child(lbl)
	_lines.append({"label": lbl, "dies_at": _now() + DURATION_S})
	# Fade in.
	var tw := create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.2)
	# Trim excess lines at the top.
	while _lines.size() > MAX_VISIBLE_LINES:
		var old : Dictionary = _lines.pop_front()
		_kill_line(old.label)
	set_process(true)

func _process(_delta: float) -> void:
	if _lines.is_empty():
		set_process(false)
		return
	var now := _now()
	while _lines.size() > 0 and now >= _lines[0]["dies_at"]:
		var entry : Dictionary = _lines.pop_front()
		_kill_line(entry["label"])

func _kill_line(lbl: Label) -> void:
	if lbl == null or not is_instance_valid(lbl): return
	var tw := create_tween()
	tw.tween_property(lbl, "modulate:a", 0.0, FADE_OUT_S)
	tw.tween_callback(lbl.queue_free)

# ── Settings glue ────────────────────────────────────────────────────────────
func _subtitles_enabled() -> bool:
	if not has_node("/root/SettingsManager"): return true
	return bool(SettingsManager.gameplay().get("subtitles", true))

func _size_px() -> int:
	if not has_node("/root/SettingsManager"): return 24
	var key := String(SettingsManager.gameplay().get("subtitle_size", "medium"))
	return int(SIZE_FONT_PX.get(key, 24))

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
