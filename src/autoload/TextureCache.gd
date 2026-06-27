## Async PBR texture fetch + disk cache backed by the Polyhaven API.
##
## Textures are stored in a shared system-wide folder (AppData\Roaming\SharedTextures\polyhaven\)
## so downloads are reused across all projects, not re-fetched per Godot app.
## A manifest.json in that folder records which project first fetched each asset and when.
##
## Call request_pbr_set("beige_wall_001") and listen for pbr_set_ready — the node
## downloads the albedo (Diffuse), normal (nor_gl) and roughness (Rough) maps,
## caches each to the shared folder, and emits the assembled set. All network work
## is fire-and-forget: callers never block, they just get a signal when maps land.
extends Node

const POLYHAVEN_FILES := "https://api.polyhaven.com/files/"

# Our role -> Polyhaven file-list key.
const MAP_KEYS := {
	"albedo":    "Diffuse",
	"normal":    "nor_gl",
	"roughness": "Rough",
}

signal pbr_set_ready(asset_id: String, maps: Dictionary)

var _cache_dir: String      = ""
var _manifest_path: String  = ""
var _manifest: Dictionary   = {}   # asset_id -> { first_fetched, last_used, resolutions, projects }

var _sets: Dictionary    = {}   # asset_id -> { role -> ImageTexture }
var _pending: Dictionary = {}   # asset_id -> { resolution, maps, remaining }

func _ready() -> void:
	# Use the AppData\Roaming shared folder — persists across Windows sessions,
	# never touched by Disk Cleanup / Storage Sense / CCleaner.
	var appdata: String = OS.get_environment("APPDATA").replace("\\", "/")
	_cache_dir     = appdata + "/SharedTextures/polyhaven/"
	_manifest_path = _cache_dir + "manifest.json"
	DirAccess.make_dir_recursive_absolute(_cache_dir)
	_load_manifest()

## Public entry point. Idempotent: re-requesting a finished asset just re-emits.
func request_pbr_set(asset_id: String, resolution: String = "2k") -> void:
	if _sets.has(asset_id):
		_touch_manifest(asset_id, resolution)
		pbr_set_ready.emit(asset_id, _sets[asset_id])
		return
	if _pending.has(asset_id):
		return

	# Try to satisfy entirely from the on-disk cache first.
	var have := {}
	for role in MAP_KEYS:
		var p := _map_path(asset_id, resolution, role)
		if FileAccess.file_exists(p):
			var tex := _load_texture(p)
			if tex != null:
				have[role] = tex
	if have.size() == MAP_KEYS.size():
		_sets[asset_id] = have
		_touch_manifest(asset_id, resolution)
		pbr_set_ready.emit(asset_id, have)
		return

	# At least one map is missing — fetch the asset's file list from the API.
	_pending[asset_id] = {"resolution": resolution, "maps": have, "remaining": 0}
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_file_list.bind(http, asset_id))
	if http.request(POLYHAVEN_FILES + asset_id) != OK:
		http.queue_free()
		_pending.erase(asset_id)

func _on_file_list(_result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest, asset_id: String) -> void:
	http.queue_free()
	if not _pending.has(asset_id):
		return
	var state: Dictionary = _pending[asset_id]
	var resolution: String = state["resolution"]

	if code != 200:
		push_warning("TextureCache: file list for '%s' failed (%d)" % [asset_id, code])
		_pending.erase(asset_id)
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.get_data() is Dictionary):
		_pending.erase(asset_id)
		return
	var files: Dictionary = json.get_data()

	var to_get := {}
	for role in MAP_KEYS:
		if state["maps"].has(role):
			continue
		var url := _extract_url(files, MAP_KEYS[role], resolution)
		if not url.is_empty():
			to_get[role] = url
	if to_get.is_empty():
		_finalize(asset_id)
		return
	state["remaining"] = to_get.size()
	for role in to_get:
		_download_map(asset_id, resolution, role, to_get[role])

func _download_map(asset_id: String, resolution: String, role: String, url: String) -> void:
	var path := _map_path(asset_id, resolution, role)
	var http := HTTPRequest.new()
	http.use_threads = true
	http.download_file = path
	add_child(http)
	http.request_completed.connect(
		_on_map_downloaded.bind(http, asset_id, role, path))
	if http.request(url) != OK:
		http.queue_free()
		_one_done(asset_id, role, null)

func _on_map_downloaded(_result: int, code: int, _headers: PackedStringArray,
		_body: PackedByteArray, http: HTTPRequest,
		asset_id: String, role: String, path: String) -> void:
	http.queue_free()
	var tex: ImageTexture = null
	if code == 200:
		tex = _load_texture(path)
	_one_done(asset_id, role, tex)

func _one_done(asset_id: String, role: String, tex: ImageTexture) -> void:
	if not _pending.has(asset_id):
		return
	var state: Dictionary = _pending[asset_id]
	if tex != null:
		state["maps"][role] = tex
	state["remaining"] = maxi(0, int(state["remaining"]) - 1)
	if state["remaining"] == 0:
		_finalize(asset_id)

func _finalize(asset_id: String) -> void:
	var state: Dictionary = _pending[asset_id]
	var maps: Dictionary  = state["maps"]
	var resolution: String = state["resolution"]
	_pending.erase(asset_id)
	if maps.is_empty():
		return
	_sets[asset_id] = maps
	_touch_manifest(asset_id, resolution)
	pbr_set_ready.emit(asset_id, maps)

# --- manifest -----------------------------------------------------------------

func _load_manifest() -> void:
	if not FileAccess.file_exists(_manifest_path):
		return
	var f := FileAccess.open(_manifest_path, FileAccess.READ)
	if f == null:
		return
	var j := JSON.new()
	if j.parse(f.get_as_text()) == OK and j.get_data() is Dictionary:
		_manifest = j.get_data()

func _touch_manifest(asset_id: String, resolution: String) -> void:
	var project: String = ProjectSettings.get_setting("application/config/name", "unknown")
	var today: String   = Time.get_date_string_from_system()
	if not _manifest.has(asset_id):
		_manifest[asset_id] = {
			"first_fetched": today,
			"last_used":     today,
			"resolutions":   [resolution],
			"projects":      [project],
		}
	else:
		var entry: Dictionary = _manifest[asset_id]
		entry["last_used"] = today
		if not (entry["resolutions"] as Array).has(resolution):
			(entry["resolutions"] as Array).append(resolution)
		if not (entry["projects"] as Array).has(project):
			(entry["projects"] as Array).append(project)
	_save_manifest()

func _save_manifest() -> void:
	var f := FileAccess.open(_manifest_path, FileAccess.WRITE)
	if f == null:
		push_warning("TextureCache: cannot write manifest to " + _manifest_path)
		return
	f.store_string(JSON.stringify(_manifest, "\t"))

# --- helpers ------------------------------------------------------------------

func _map_path(asset_id: String, resolution: String, role: String) -> String:
	return _cache_dir + "%s_%s_%s.png" % [asset_id, resolution, role]

func _load_texture(path: String) -> ImageTexture:
	var img := Image.load_from_file(path)
	if img == null:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _extract_url(files: Dictionary, ph_key: String, resolution: String) -> String:
	if not files.has(ph_key) or not (files[ph_key] is Dictionary):
		return ""
	var by_res: Dictionary = files[ph_key]
	if not by_res.has(resolution) or not (by_res[resolution] is Dictionary):
		return ""
	var fmts: Dictionary = by_res[resolution]
	for ext in ["png", "jpg"]:
		if fmts.has(ext) and fmts[ext] is Dictionary and fmts[ext].has("url"):
			return str(fmts[ext]["url"])
	return ""
