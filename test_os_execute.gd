extends SceneTree

func _init():
    var args = ["-p", "hello & whoami", "-n", "120"]
    print("Testing OS.execute")
    var output = []
    OS.execute("cmd.exe", ["/c", "echo"] + args, output, true)
    print("Output:", output)

    # Test if it runs .bat files implicitly or something
    var f = FileAccess.open("user://test.bat", FileAccess.WRITE)
    f.store_string("@echo off\necho Args: %*\n")
    f.close()

    var bat_path = ProjectSettings.globalize_path("user://test.bat")
    var output2 = []
    OS.execute(bat_path, args, output2, true)
    print("Output bat:", output2)
    quit()
