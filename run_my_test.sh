#!/bin/bash
./godot --headless --script test_crew.gd 2>&1 | grep "error"
