class_name MachineSoundBank
extends RefCounted
## Attaches a MachineSound to a placed machine, tool or panel — the audio
## sibling of MachineBrains. Called from the tail of PlaceableCatalog.build_node
## (every non-ghost placeable), from LeafBlower._ready, HoseReel._ready,
## WasteContainer (IBC valve) and Hmi._ready.
##
## Which machines have a sound is decided by DATA: a placeable id has a sound
## iff `src/audio/machine_sounds/<id>.tres` exists. Adding a sound for a new
## machine is one .tres + the baked WAV it points at; no code changes.
##
## Idempotent: a body that already carries a "MachineSound" child is left alone,
## so BuildMode.rebuild_in_place() cannot stack two players on one machine.

const SPEC_DIR  : String = "res://src/audio/machine_sounds/"
const NODE_NAME : String = "MachineSound"
const SoundScript := preload("res://src/audio/MachineSound.gd")

static var _specs : Dictionary = {}     # id -> Resource or null (cached miss)


static func spec_path(id: String) -> String:
	return SPEC_DIR + id + ".tres"


## True iff a sound spec exists for this placeable id.
static func has_spec(id: String) -> bool:
	if _specs.has(id):
		return _specs[id] != null
	return ResourceLoader.exists(spec_path(id))


## The spec resource (cached; the same instance for every machine of the type).
static func spec_for(id: String) -> Resource:
	if _specs.has(id):
		return _specs[id]
	var s : Resource = null
	if ResourceLoader.exists(spec_path(id)):
		s = load(spec_path(id)) as Resource
		if s != null and not ("gain_db" in s):
			push_warning("[MachineSoundBank] %s is not a MachineSoundSpec — ignored" % spec_path(id))
			s = null
	_specs[id] = s
	return s


## Attach the sound to `body` for placeable `id`. Returns the MachineSound (new
## or existing) or null when the id has no spec. Safe on a body that is not in
## the tree yet (build_node calls this before the caller add_child()s the model).
static func attach(body: Node, id: String) -> Node:
	if body == null:
		return null
	var existing := body.get_node_or_null(NODE_NAME)
	if existing != null:
		return existing
	var s := spec_for(id)
	if s == null:
		return null
	var snd : Node3D = SoundScript.new()
	snd.name = NODE_NAME
	snd.call("setup", s)
	body.add_child(snd)
	return snd


## The MachineSound on a body, or null.
static func find(body: Node) -> Node:
	return body.get_node_or_null(NODE_NAME) if body != null else null


## The PLACED body above `n`: the nearest ancestor (or `n` itself) carrying the
## catalog's `placeable_id` meta. A controller script that lives under the
## model subtree (HoseReel.gd under the reel's model node) attaches its sound
## here, so LineFlow, tests and the bank all find one MachineSound in one place.
## Falls back to `n` when nothing above carries the meta.
static func placed_body_of(n: Node) -> Node:
	var cur := n
	while cur != null:
		if cur.has_meta("placeable_id"):
			return cur
		cur = cur.get_parent()
	return n


## Every placeable id that has a spec on disk (sorted). Reads the directory, so
## it sees a .tres the moment it is added.
static func spec_ids() -> Array[String]:
	var out : Array[String] = []
	var d := DirAccess.open(SPEC_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir():
			if f.ends_with(".tres"):
				out.append(f.trim_suffix(".tres"))
			elif f.ends_with(".tres.remap"):
				out.append(f.trim_suffix(".tres.remap"))
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


## Drop the cache (tests that edit a spec, or a hot-reload).
static func reset_cache() -> void:
	_specs.clear()
