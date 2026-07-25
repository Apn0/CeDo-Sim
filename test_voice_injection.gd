extends SceneTree

func _init():
    var VoiceService = preload("res://src/autoload/VoiceService.gd").new()

    print("Testing VoiceService._is_trusted_tool_path")
    print("trusted tools/piper/piper.exe:", VoiceService._is_trusted_tool_path("user://tools/piper/piper.exe"))
    print("trusted tools/../../windows/system32/cmd.exe:", VoiceService._is_trusted_tool_path("user://tools/../../windows/system32/cmd.exe"))
    print("trusted /usr/bin/bash:", VoiceService._is_trusted_tool_path("/usr/bin/bash"))

    # We want to see how args are passed to OS.execute in _exec_tool.
    # We see: OS.execute(ProjectSettings.globalize_path(tool_path), args, output, true)

    quit()
