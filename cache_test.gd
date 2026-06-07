extends SceneTree

func _init():
    var iter = 100000
    
    var root_node = Node3D.new()
    root.add_child(root_node)
    
    var belt = preload("res://src/scenes/world/ShredderFeedBelt.gd").new()
    root_node.add_child(belt)
    
    var containers = []
    for i in range(100):
        var c = Node3D.new()
        c.add_to_group("waste_container")
        root_node.add_child(c)
        c.set_script(load("res://benchmark_mock_container.gd"))
        containers.append(c)

    var target_pos = Vector3(0, 0, 0)
        
    var t0 = Time.get_ticks_usec()
    for i in range(iter):
        # SIMULATING CACHED BEHAVIOR
        var best = null
        for c in containers:
            if c is Node3D and (c as Node).has_method("add"):
                if (c as Node3D).global_position.distance_to(target_pos) < 3.0:
                    best = c
                    break
    var t1 = Time.get_ticks_usec()
    
    print("Cached Time taken: ", (t1 - t0) / 1000.0, " ms")
    quit()
