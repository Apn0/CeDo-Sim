extends SceneTree

func _init():
    var iter = 100000
    
    var root_node = Node3D.new()
    root.add_child(root_node)
    
    var belt = preload("res://src/scenes/world/ShredderFeedBelt.gd").new()
    root_node.add_child(belt)
    
    for i in range(100):
        var c = Node3D.new()
        c.add_to_group("waste_container")
        root_node.add_child(c)
        c.set_script(load("res://benchmark_mock_container.gd"))

    var target_pos = Vector3(0, 0, 0)
        
    var t0 = Time.get_ticks_usec()
    for i in range(iter):
        belt._container_at(target_pos)
    var t1 = Time.get_ticks_usec()
    
    print("Baseline Time taken: ", (t1 - t0) / 1000.0, " ms")
    quit()
