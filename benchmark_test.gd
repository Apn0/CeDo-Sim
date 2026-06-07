extends SceneTree

func _init():
    var iter = 100000
    
    # Create nodes
    for i in range(100):
        var n = Node.new()
        n.add_to_group("waste_container")
        root.add_child(n)
        
    var t0 = Time.get_ticks_usec()
    for i in range(iter):
        var group = get_nodes_in_group("waste_container")
    var t1 = Time.get_ticks_usec()
    
    print("Time taken: ", (t1 - t0) / 1000.0, " ms")
    quit()
