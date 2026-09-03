extends SceneTree

func _init():
    var args = ["-p", "hello & whoami", "-n", "120"]
    print("Testing OS.execute")
    var output = []

    var secure_args = []
    var re = RegEx.new()
    re.compile("[&|;<>`$\n\r%\\^]")
    for arg in args:
        var s = String(arg)
        if re.search(s) != null:
            print("Refusing to exec - unsafe argument detected: ", s)
            quit(1)
            return
        secure_args.append(s)

    OS.execute("cmd.exe", ["/c", "echo"] + secure_args, output, true)
    print("Output:", output)

    var f = FileAccess.open("user://test.bat", FileAccess.WRITE)
    quit(0)
