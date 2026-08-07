# CeDo Audio Placer

Preprocessing web app for the CeDo Simulator. Upload a long video or audio
recording from a plant walkthrough; the app auto-splits it into segments at
silence gaps; you click each segment on the map; export a JSON manifest
with WGS84 + Dutch RD coordinates that the simulator's `AudioManager`
ingests.

## Usage

1. Open `index.html` in Chrome/Edge/Firefox (no install).
2. **Drag a video or audio file** into the upload zone (mp4, mov, webm, wav,
   mp3, m4a, ogg, flac). The app decodes the audio track and shows a
   waveform.
3. Adjust the **Min silence** and **Threshold** sliders if needed, then
   click **Auto-segment**. Each non-silent stretch becomes one segment.
   * `Min silence` (default 0.8 s): how long a quiet stretch must be to
     count as a segment boundary. Raise it if recordings have brief lulls
     inside a single machine clip.
   * `Threshold` (default −40 dB): RMS level below which is treated as
     silence. Lower it (more negative) if ambient hum is masking real
     gaps.
4. The waveform shows segments as green rectangles. Click a rectangle in
   the waveform (or a row in the segments list) to seek the video to
   that segment.
5. **Place a segment**: select it in the list, then click on the map. Drag
   the marker afterwards to refine. Right-click a marker to delete.
6. **Tune manually**: scrub the video, then **Split at playhead** to split
   a segment in two, or to start a new 5-second segment outside any existing
   one. **Clear segments** removes all unplaced segments for the selected
   source.
7. **Click a segment** → audio auto-loops in the background, "Selected clip"
   panel appears in the sidebar with:
   * Editable clip name
   * Machine checklist (grouped by category, loaded from `machines.json`
     which mirrors the simulator's `PlaceableCatalog`)
   * Free-form tags input
   * Live filename preview (`<name>__<machine1-machine2>__<tags>`)
   Tick the machines this clip applies to. A clip can be tagged with
   multiple machines (and a machine can be the tag for multiple clips).
8. **Export JSON** writes `audio_layout.json` to your downloads:
   ```json
   [
     {
       "clip_name":     "extruder_1B_idle",
       "filename_stem": "extruder_1B_idle__extruder_1__idle-shift_a",
       "source_file":   "shift_walkthrough_2026_05_12.mp4",
       "start_s": 142.30, "end_s": 168.70,
       "lat": 50.96952, "lon": 5.81941,
       "rd_x": 190234.5, "rd_y": 332701.2,
       "machines": ["extruder_1"],
       "tags":     ["idle", "shift_a"],
       "notes": "captured 2026-05-12"
     }
   ]
   ```
   `extract_segments.py` uses `filename_stem` when present, falling back to
   `clip_name` for older exports.
8. **Import JSON** restores segments — re-upload the matching source file(s)
   first; segments are bound to their source by `source_file`.

## Persistence

* Source blobs go to **IndexedDB** (survives reload).
* Metadata + waveforms go to **localStorage**.
* **The exported JSON is the authoritative record.** Browser data wipes
  remove the cache; keep the JSON.

## Codec notes

* MP4 (H.264 + AAC), WebM, MP3, WAV, M4A, OGG, FLAC all decode in modern
  browsers.
* MOV with unusual codecs may fail to decode. If you see "Couldn't
  decode…", convert to MP4 with ffmpeg first:
  `ffmpeg -i input.mov -c:v libx264 -c:a aac output.mp4`
* Big files (~50 MB / 5 min) work but use a lot of memory during decode.
  If decode hangs, downsample or trim with ffmpeg first.

## Extracting per-segment WAVs

After exporting `audio_layout.json` from the web app, run:

```bash
python extract_segments.py --source-dir <where the source video lives>
```

ffmpeg slices each entry into its own mono 44.1 kHz WAV under
`audio_clips/`, named after `clip_name` (sanitised for the filesystem).
Flags:

| Flag                  | Default          | Notes                                              |
|-----------------------|------------------|----------------------------------------------------|
| `--manifest`          | `audio_layout.json` | Input JSON                                      |
| `--source-dir`        | `.`              | Where the original video/audio files live          |
| `--out`               | `audio_clips`    | Output folder                                      |
| `--format`            | `wav`            | `wav` / `mp3` / `ogg` / `flac`                     |
| `--mono` / `--stereo` | mono             | AudioStreamPlayer3D is positional — mono is enough |
| `--sample-rate`       | `44100`          | Hz                                                 |
| `--overwrite`         | off              | Replace files that already exist                   |
| `--dry-run`           | off              | Print commands without running ffmpeg              |

Requires `ffmpeg` on PATH (`winget install Gyan.FFmpeg`) and Python 3.

## Make each clip a seamless loop (Godot-ready)

After running `extract_segments.py`, run:

```bash
python loopify_wavs.py --in-place
```

For every WAV it:

* Applies a **head-to-tail equal-power crossfade** so the loop point is
  between two originally-adjacent samples — no click, thump, or break in
  the noise when playback wraps. Output is shorter than the input by the
  fade duration (default 100 ms).
* Re-encodes to **16-bit PCM stereo @ 44.1 kHz** (Godot's preferred WAV
  format).
* Writes a `smpl` chunk marking the whole file as a forward loop. Godot
  4's WAV importer reads this and auto-sets `loop_mode = LOOP_FORWARD`,
  so the imported `AudioStreamWAV` resource loops with zero clicks in the
  import inspector.

| Flag             | Default              | Notes                                         |
|------------------|----------------------|-----------------------------------------------|
| `--in`           | `audio_clips`        | Input folder                                  |
| `--out`          | `audio_clips_loop`   | Output folder (ignored if `--in-place`)       |
| `--in-place`     | off                  | Overwrite the input WAVs                      |
| `--fade-ms`      | `100`                | Crossfade duration (loop becomes this shorter)|
| `--sample-rate`  | `44100`              | Output sample rate                            |

Verify the `smpl` chunk:

```bash
python -c "import sys, struct
data = open(sys.argv[1],'rb').read()
i = 12
while i + 8 <= len(data):
    cid = data[i:i+4].decode('latin1')
    csz = struct.unpack('<I', data[i+4:i+8])[0]
    print(cid, csz)
    i += 8 + csz + (csz % 2)" audio_clips/your_clip.wav
```

You should see `fmt `, `data`, and `smpl` chunks.

## Coordinate systems

Markers are stored in WGS84 and exported with matching RD New
(EPSG:28992) metres. The simulator's building shell is in RD, so
`rd_x` / `rd_y` plug straight into world XYZ (`world_z = -rd_y` because
Godot is right-handed).
