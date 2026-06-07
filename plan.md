1. **Analyze the Problem**: 
    - The `_container_at` method in `src/scenes/world/ShredderFeedBelt.gd` is called within the `_emit_output` function, which gets called every `_process` frame when there is digested output from the shredder.
    - Inside `_container_at`, it does a `get_tree().get_nodes_in_group("waste_container")`, which traverses the scene tree to fetch all nodes in that group and creates a new Array every frame.
    - This creates significant overhead (over 2000 ms for 100k calls with 100 nodes).
    
2. **Optimize with Caching**:
    - Add a variable `var _cached_containers : Array[Node] = []` in the `ShredderFeedBelt` class to cache the containers.
    - Add `func _update_container_cache() -> void:` that will populate this list once or when necessary.
    - When does the list of containers change? They can enter/exit the tree or move. 
    - But wait, an even better option in Godot is to cache them using area signals if we just care about proximity. Since ShredderFeedBelt only needs to know about containers near `_discharge_pos()`, we could use an Area3D? No, we might not want to add new nodes.
    - Instead of group querying every frame, we can keep track of nodes in group using scene tree signals `node_added` and `node_removed`, but checking group membership might still require string matching.
    - Actually, Godot's group lists are quite optimized under the hood, but creating an Array in GDScript every frame isn't. However, caching the group array and periodically updating it, or updating it via `SceneTree.node_added` / `node_removed` would avoid querying it every frame.
    - Alternatively, Godot provides `SceneTree` signals: `tree_changed` or just caching it once a second or relying on the containers themselves to register.
    - Even simpler: Cache it and refresh it periodically (e.g. every second) since containers don't pop into existence constantly. Or use a timer.
    - Let's look at `_process` rate. It's called every frame.
    - We can use a dirty flag for the cache that resets when nodes in the group change. But `SceneTree` does not have a signal specifically for group modifications.
    - Or we can use an Area3D near the discharge to automatically detect bodies/areas, but waste containers might be simple Node3Ds.
    - A very common optimization is to fetch the group nodes in a low-frequency tick. E.g. `var _cache_timer = 0.0`. Every 1.0s, update `_cached_containers = get_tree().get_nodes_in_group("waste_container")`. During `_container_at`, iterate over `_cached_containers`.
    - Is it acceptable if a container takes up to 1 second to be recognized? Yes, in a simulation context, usually a small delay is fine, or even checking every 0.1s (10x a second instead of 60x a second).
    - Or, what if we hook into `SceneTree.node_added` and `node_removed`?
    
3. **Refined Caching Strategy**:
    - Hook into `get_tree().node_added` and `get_tree().node_removed`.
    - When a node is added, if it's in the group, append to cache.
    - When removed, remove from cache.
    - Wait, Godot allows adding to groups *after* `node_added` (e.g. in `_ready` or via code). So `node_added` might miss group additions.
    - Periodic caching is more robust. `_container_update_timer` updated in `_process`. Let's say we update it every 0.5s.
    - Or better, we can just track it manually if the number of containers isn't crazy, but updating an Array every frame vs every 0.25s is huge.
    - Let's check `ShredderFeedBelt.gd` for other things. We can just add a simple `_container_cache` Array and a `_container_cache_time` float.
    
    ```gdscript
    var _cached_containers: Array[Node] = []
    var _container_cache_time: float = 0.0

    func _container_at(pos: Vector3) -> Node:
        var now := Time.get_ticks_msec()
        if now - _container_cache_time > 250: # update every 250ms
            _cached_containers = get_tree().get_nodes_in_group("waste_container")
            _container_cache_time = now
        
        for c in _cached_containers:
            if c is Node3D and (c as Node).has_method("add"):
                if (c as Node3D).global_position.distance_to(pos) < 3.0:
                    return c
        return null
    ```
    - This provides a massive speedup by reducing `get_nodes_in_group` calls to 4 times a second, while preserving exact behavior with a tiny 250ms latency for recognizing a new or removed bin (and if it's removed, Godot handles null references safely with `is_instance_valid(c)`). We should check `is_instance_valid(c)` in the loop just in case.

4. **Verify**: Run `godot --headless --script test_shredder_belt.gd` with the new implementation.

5. **Pre-commit**: `pre_commit_instructions` tool and obey.

6. **Submit**: Create PR.
