# CeDo document set — duplicate analysis

**Source:** `D:/drive-download-20251124T130330Z-1-001/` — 379 PDFs (the scanned PROD-SWI
binder + EREMA docs + HMI photos + flow diagrams + training flipcharts).
**Analysed:** 2026-07-05. Read-only; nothing deleted.

## Headline

| | count |
|---|---|
| Source PDFs | 379 |
| Total pages | 389 (≈ all single-page scans) |
| **Genuinely redundant duplicate copies** | **15** |
| **Blank / failed junk scans** | **2** |
| **Removable total** | **17** |
| **Distinct documents remaining** | **362** |

"Many duplicates" turned out to be mostly an illusion of the scanning method: the operator
scanned the binder ~3 times (the `(2)` / `(3)` filename suffixes), and long procedures were
scanned **one file per page**. So what looks like a pile of copies is really (a) different
pages of multi-page procedures and (b) many unique live-HMI photographs — all correctly
distinct. The true redundancy is small and precise.

## How it was determined (and why the easy methods lied)

- **Byte hashing → 0 hits.** Every rescan differs at the byte level (scan noise), so exact
  hashing finds nothing.
- **Perceptual hashing → false-positive storm.** Every CeDo form shares one template (logo,
  border, table grid), so a downscaled image rates `FORM-007`, `FORM-008`, and
  `DIAG-blauwe-watertank` as "identical." Calibration confirmed dupe and non-dupe distance
  distributions overlap too much to threshold.
- **OCR text (tesseract, nld+eng) → the reliable fingerprint.** Only 12/389 pages had an
  embedded text layer, so all 379 were OCR'd. Grouping by the **printed document number**
  (`Cedo-PROD-SWI-034`) + `Page X of Y` marker is boilerplate-immune.
- **Extractor `swi_id` (page-precise) → authoritative shortlist**, then **vision verification**
  of every ambiguous group (agents read the actual rendered pages and compared timestamps /
  page numbers / sensor readings). This overturned the automated guess: the auto-methods
  flagged ~50 "redundant," but vision proved most were distinct pages or distinct photos.

## Verified true-duplicate groups (keep 1, the rest are redundant)

| Keep | Remove (redundant rescans) | Document | Confidence |
|---|---|---|---|
| `050_CeDo11 (2)` | `051_CeDo7 (2)`, `052_CeDo8 (2)`, `053_CeDo9 (2)`, `150_CeDo10 (2)` | SWI-034 "Lijn 3 reinigen shredder 1" — page 2 of 2 | vision |
| `158_CeDo2 (2)` | `159_CeDo6 (2)`, `163_CeDo5 (2)` | SWI-034 — page 1 of 2 | vision |
| `034_CeDo114 (2)` | `035_CeDo113 (2)` | SWI-012 — page 3 of 8 | vision |
| `245_CeDo131` | `246_CeDo136` | Lijn 3a flow diagram (basic grey-box version) | vision |
| `341_CeDo128 (2)` | `342_CeDo127 (2)` | SWI-010 "wisselen halogeenlampen NIR" — page 4 of 4 | vision |
| `115_CeDo8` | `286_CeDo78 (3)` | TRAIN water circuit 1 (La1) was 3a — flipchart | vision |
| `113_CeDo9` | `229_CeDo79 (3)` | TRAIN water circuit 2 (La2) was 3a — flipchart | vision |
| `129_CeDo97 (2)` | `130_CeDo96 (2)` | SWI-017 — page 3 | high-conf (page-precise id, ham≤17) |
| `321_CeDo51 (2)` | `322_CeDo52 (2)` | SWI-049 — page 2 | high-conf (page-precise id, ham≤17) |
| `151_CeDo40 (2)` | `152_CeDo39 (2)` | SWI-054 "Laserfilter wisselen lijn 3" — page 9 | high-conf (page-precise id) |
| `281_CeDo57 (2)` | `282_CeDo58 (2)` | SWI-062 — page 1 | high-conf (text J≥0.62) |

**15 redundant copies.** ("vision" = an agent read both pages and confirmed identical content;
"high-conf" = page-precise extractor id + tight perceptual/text match, not separately eyeballed.)

## Junk / failed scans (deletable outright — no content)

- `336_CeDo100 (2).pdf` — scan of the edge of a paper stack against a dark surface.
- `364_CeDo17 (2).pdf` — blank hole-punched sheet.

## Auto-flagged but NOT duplicates (correctly kept — recorded so the finding is auditable)

The automated pass wanted to merge these; vision proved them **distinct**:

- **EREMA BluPort HMI photos** — `lijn3C` (12 files), `lijn6` (4), `trend-graph` (2),
  `lijn3C` set 196–200 (5). Each is a unique live capture (different clock timestamps,
  dates, and sensor readings — some pairs seconds apart still differ on every value). 23
  distinct screen photos, **0 duplicates**. Valuable real operating data.
- **Multi-page procedures split one-file-per-page** — SWI-074 (pages 3/5/7/9/13 of a 24-page
  laserfilter-wissel), SWI-054 (pages 2/3/5/14 of 17), SWI-061 (pages 3/4/7/8 of 8),
  SWI-009 (pages 2/7), SWI-055 (pages 1/3), SWI-015 (pages 2/3), SWI-012 (page 7 vs the
  page-3 dupe above). Keep every page.
- **`261_CeDo130`** — a **more complete revision** of the lijn 3a flow diagram: adds the whole
  water-circuit layer (P1/P2, LA2, blauwe tank, ZSS, vers kanaalwater, koeltoren circuit,
  riool naar EOP). More valuable than the two basic copies — keep.

## Note

`src/data/plant/swi_index.json` (built by the digest pipeline) already collapses same-`swi_id`
scans into single entries, so the machine-readable index is duplicate-free regardless of the
raw digest files. Removing the 15 redundant + 2 junk **digest** files from `docs/plant/swi/`
would only tidy the human-readable folder; the source PDFs on `D:/` are the operator's scan
originals and are left untouched.
