extends SceneTree
func _init():
    var path = "user://tools/..\\..\\Windows\\System32\\cmd.exe"
    var p1 = ProjectSettings.globalize_path(path)
    print("p1:", p1)
    var p2 = p1.simplify_path()
    print("p2:", p2)
    quit()
