extends SceneTree
func _init():
    var path = "user://tools/..\\..\\Windows\\System32\\cmd.exe"
    var p1 = ProjectSettings.globalize_path(path)
    print("p1:", p1)
    var p2 = p1.simplify_path()
    print("p2:", p2)

    var root = ProjectSettings.globalize_path("user://tools/").simplify_path()
    print("root:", root)
    if not root.ends_with("/"):
        root += "/"
    print("root:", root)
    print("starts with root:", p2.begins_with(root))

    quit()
