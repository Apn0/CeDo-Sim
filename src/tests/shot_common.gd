extends RefCounted
class_name ShotCommon
## Shared PNG-content sanity check for the shot_*.gd render/screenshot tools.
##
## Audit finding C10 (docs/DETAIL_STANDARD_audit_2026-08-18.md): none of these
## tools checked that the PNG they saved actually had visible content — a
## headless/empty-scene run (missing environment, camera pointed at nothing,
## node failed to build) would still call save_png() and print a "saved"
## line, i.e. silently "succeed" on a black or blank frame.
##
## Pattern follows ConveyorSim's src/line/line_main.gd _shoot(): sample
## pixels on a stride (not every pixel — cost) and compute mean luminance.
## This adds pixel-value VARIANCE on top of that: a solid grey/fog frame with
## nothing in it has a perfectly reasonable nonzero mean luminance but zero
## variance, so mean alone would pass an empty render. Both must clear the
## floor for the frame to count as real content.
##
## This is an ADDED check only — it does not touch any caller's render,
## camera, or lighting setup. Call it right after save_png():
##   img.save_png(outp)
##   ShotCommon.check_image_content(img, outp)

const STRIDE := 8            # matches ConveyorSim's _shoot() sample stride
const MIN_MEAN_LUM := 0.02   # near-zero mean = solid black / empty frame
const MIN_VARIANCE := 0.0002 # near-zero variance = flat/uniform colour (no content)

## Samples img on STRIDE, prints one "[SHOT-CHECK] ... ok|FAIL" line with the
## measured numbers, and returns true if the image looks like real content
## (not black, not a single flat colour).
static func check_image_content(img: Image, path: String) -> bool:
	var w : int = img.get_width()
	var h : int = img.get_height()
	var sum : float = 0.0
	var sum_sq : float = 0.0
	var n : int = 0
	for y in range(0, h, STRIDE):
		for x in range(0, w, STRIDE):
			var c : Color = img.get_pixel(x, y)
			var lum : float = (c.r + c.g + c.b) / 3.0
			sum += lum
			sum_sq += lum * lum
			n += 1
	var mean : float = sum / float(maxi(n, 1))
	var variance : float = (sum_sq / float(maxi(n, 1))) - mean * mean
	var ok : bool = mean >= MIN_MEAN_LUM and variance >= MIN_VARIANCE
	print("[SHOT-CHECK] %-40s %dx%d mean_lum=%.4f variance=%.6f n=%d  %s"
			% [path.get_file(), w, h, mean, variance, n,
				("ok" if ok else "FAIL (blank/flat image — no visible content)")])
	return ok
