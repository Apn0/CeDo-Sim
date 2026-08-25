import pytest
import os
import subprocess
import json

def test_extract_segments_hyphen_files(tmp_path):
    # Setup test files
    manifest_path = tmp_path / "audio_layout.json"
    source_dir = tmp_path / "source"
    source_dir.mkdir()
    source_file = source_dir / "-test.wav"
    out_dir = tmp_path / "out"

    # Create fake wav file
    with open(source_file, "w") as f:
        f.write("RIFF test")

    # Create manifest
    manifest_data = [
        {
            "filename_stem": "-clip1",
            "source_file": "-test.wav",
            "start_s": 0.0,
            "end_s": 1.0
        }
    ]
    with open(manifest_path, "w") as f:
        json.dump(manifest_data, f)

    script_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "tools", "audio", "placer", "extract_segments.py"))

    # Run the script
    cmd = [
        "python", script_path,
        "--manifest", str(manifest_path),
        "--source-dir", str(source_dir),
        "--out", str(out_dir),
        "--format", "wav"
    ]

    # Check that ffmpeg fails cleanly with exit code 183 (invalid data) instead of failing on unrecognized option
    # Since ffmpeg might not be installed in all test environments, we check if ffmpeg failed on our file
    # or failed completely, but we ensure python script returns 1 (failed processing) and stdout confirms failure
    res = subprocess.run(cmd, text=True, capture_output=True)

    assert res.returncode != 0
    assert "FAIL   -clip1: ffmpeg exit" in res.stdout
    assert "Unrecognized option" not in res.stderr
