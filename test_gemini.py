import os
import re
import time
from concurrent.futures import ThreadPoolExecutor

# Optimization flags and regex patterns
GD_PATTERNS = {
    "print_left_in": re.compile(r'^\s*print\('),
    "empty_process": re.compile(r'func _process\(.*\):\s*pass'),
    "empty_physics": re.compile(r'func _physics_process\(.*\):\s*pass'),
    "no_static_type": re.compile(r'var\s+[a-zA-Z0-9_]+\s*='), # Catches untyped vars
}

TSCN_PATTERNS = {
    "rigid_body": re.compile(r'type="RigidBody3D"'),
    "omni_light_shadows": re.compile(r'shadow_enabled = true'),
}

def scan_gd_script(filepath):
    issues = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            for i, line in enumerate(lines):
                if GD_PATTERNS["print_left_in"].search(line):
                    issues.append(f"Line {i+1}: Leftover print() statement.")
                if GD_PATTERNS["empty_process"].search(line):
                    issues.append(f"Line {i+1}: Empty _process function (CPU waste).")
                if GD_PATTERNS["empty_physics"].search(line):
                    issues.append(f"Line {i+1}: Empty _physics_process function (CPU waste).")
    except Exception as e:
        return filepath, [f"Read error: {e}"]
    
    return filepath, issues

def scan_tscn_scene(filepath):
    issues = []
    rb_count = 0
    shadow_count = 0
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            for line in f:
                if TSCN_PATTERNS["rigid_body"].search(line):
                    rb_count += 1
                if TSCN_PATTERNS["omni_light_shadows"].search(line):
                    shadow_count += 1
                    
        if rb_count > 50:
            issues.append(f"High RigidBody3D count ({rb_count}). Migrate to PhysicsServer3D.")
        if shadow_count > 10:
            issues.append(f"High shadow-casting light count ({shadow_count}). Will bottleneck GPU.")
            
    except Exception as e:
        return filepath, [f"Read error: {e}"]

    return filepath, issues

def bot_worker(filepath):
    if filepath.endswith('.gd'):
        return scan_gd_script(filepath)
    elif filepath.endswith('.tscn'):
        return scan_tscn_scene(filepath)
    return filepath, []

def get_all_files(directory):
    target_files = []
    for root, _, files in os.walk(directory):
        if ".git" in root or "addons" in root:
            continue
        for file in files:
            if file.endswith('.gd') or file.endswith('.tscn'):
                target_files.append(os.path.join(root, file))
    return target_files

def run_swarm(directory, max_bots=24):
    print(f"Deploying swarm of {max_bots} bots to audit {directory}...")
    start_time = time.time()
    
    files_to_scan = get_all_files(directory)
    total_issues = 0
    
    with ThreadPoolExecutor(max_workers=max_bots) as executor:
        results = executor.map(bot_worker, files_to_scan)
        
        for filepath, issues in results:
            if issues:
                print(f"\n[!] {filepath}")
                for issue in issues:
                    print(f"    - {issue}")
                    total_issues += 1

    print(f"\nAudit complete in {time.time() - start_time:.2f}s. Found {total_issues} optimization issues.")

if __name__ == "__main__":
    # Run from the root of the Godot project
    project_root = os.getcwd()
    run_swarm(project_root, max_bots=32)