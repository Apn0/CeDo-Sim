find src/tests -name "test_*.gd" -exec ./godot --headless --quit-after 5 --script {} \; 2>/dev/null | grep -i "fail" || echo "No failures found"
