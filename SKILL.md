---
name: kevely0102
description: Read values that only appear in a hover tooltip/profile card on Windows (e.g. export every QQ group member's QQ id to a txt file). Uses the real cursor, Windows.Media.Ocr and stock PowerShell — no Selenium, no Python, no login, no network.
---

# Kevely0102

Extract a field that a Windows desktop app only shows on hover: move the real cursor onto each
list row, OCR the popup card, scroll, repeat, and write a sorted de-duplicated list.

Canonical use: **"export all member QQ ids of QQ group <number> into a txt file"**.

## When to use

- The value is visible on screen but missing from the app's API, local DB, and UI Automation tree.
- You can enumerate the list by hovering rows and scrolling.
- Example targets: QQ NT group member panel (QQ id in the hover card), chat apps with profile
  cards, admin dashboards whose tooltips carry the id.

Do **not** use it when the data is available from a documented API, an unencrypted local file,
or an export button — those are cheaper and exact.

## Ground rules

1. It drives the **real cursor and the foreground window**. Tell the user before running and
   keep hands off during the run; keystrokes go to whatever holds focus.
2. Coordinates are physical screen pixels; the module calls `SetProcessDPIAware()` first.
   Never mix it with DPI-virtualised measurements.
3. Never guess a preset. Calibrate: `Get-HoverGeometry.ps1` must print a window, row anchors,
   a plausible pitch, **and a non-empty first-row value** before a scan is worth launching.
4. Treat OCR output as probabilistic. Prefer two agreeing reads; cross-check suspicious values
   (wrong digit count, duplicated patterns) before delivering.
5. Exported identifiers are personal data: no upload, no publishing, no redistribution.

## Quick start (QQ NT)

```powershell
# 0. once per machine: prove the OCR engine works
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-HoverOcrEngine.ps1

# 1. ask the user to open the group chat and expand the member panel
#    ("群聊成员" toolbar button / double-click the group title area)

# 2. calibrate
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-HoverGeometry.ps1 -PresetName qq

# 3. scan (long; run it in the background and poll the log)
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Export-QQGroupMembers.ps1 `
  -GroupId 100000000 -OutFile .\members.txt

# 4. authoritative roster: 3 sweeps + a bottom-up sweep, keep ids seen >= 2 times
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Export-QQGroupMembers.ps1 `
  -GroupId 100000000 -OutFile .\members.txt -Passes 3 -MinHits 2 -TailSweep
```

Expect roughly 1 s per row with verification; a 200-row list plus scrolling takes about 4-6 min,
longer on slow machines. Read the generated `.log`: every page reports
`PAGE n rows= pitch= added= total=`, and `STOP stale` means no new values for several pages.

One sweep is not a roster. Viewport edges and OCR slips both cost rows, so a single pass can be
short *and* polluted. For delivery-grade output run `-Passes 3 -MinHits 2 -TailSweep`: three
sweeps from the top plus one sweep upwards from the bottom, keeping only ids that were read in at
least two sweeps. `<out>.hits.txt` then lists every id with its vote count — values with one vote
are the ones you check by hand (search them in the member panel) instead of shipping them blind.

## Adapting to a new app

```powershell
Import-Module .\src\WinHoverOcr\WinHoverOcr.psd1 -Force
Initialize-HoverOcr
Get-HoverWindow -TitleLike '*App*'          # find the hwnd
Get-HoverWindowScreenshot -Preset $p -Path .\win.png
Get-HoverOcrText -Path .\win.png           # word boxes -> where rows/cards are
```

Copy `presets/qq.psd1`, then adjust:

| Key | Meaning |
| --- | --- |
| `Window.TitleLike` / `Hwnd` | how the target is located |
| `Panel.X/Y/Width/Height/Scale` | list screenshot rect, OCR upscale factor |
| `Panel.RowTextX`, `MinWordHeight`, `MaxWordHeight` | which OCR words are row anchors |
| `Row.Pitch` | row spacing (px); `Get-HoverGeometry.ps1` suggests it |
| `Hover.X`, `Hover.Jiggle`, `Hover.SettleMs` | where to hover and how to approach it |
| `Card.X/Width/Scale`, `Card.Bands` | the popup card and the bands to OCR |
| `Card.Pattern` / `LoosePattern` | strict / fallback extraction |
| `Scroll.X/Y/Notches/SettleMs` | where the wheel goes and how far |

Then `Invoke-HoverScan.ps1 -PresetPath .\mypreset.psd1 -OutFile .\out.txt`.

## Failure playbook

| Symptom | Cause | Fix |
| --- | --- | --- |
| 0 rows detected | panel closed, window minimized, wrong rect | reopen panel, `Get-HoverGeometry.ps1` |
| rows detected, all values empty | card never appears | window unfocused (`EnsureForeground`), or hover point off the row |
| card appears, value empty | OCR band misses the field | move `Card.Bands` offsets; raise `Card.Scale` |
| `QQ` prefix never matches | digit normalisation eating the prefix | never map `Q`/`q` |
| duplicated pages, no progress | wheel landed outside the list | set `Scroll.X/Y` inside the panel |
| gap in the list | scroll step larger than the viewport | reduce `Notches` |
| coordinates all scaled | DPI virtualisation | call `SetProcessDPIAware()` (module does) |

## Notes on the QQ preset

- Hover point `X = 2189` sits on the member name; card occupies `x 1459..2059`, and the
  `QQ <id>` line is ~`cursor y + 34`.
- Row pitch is 90 px at 100 % layout; 13 rows are visible at a time.
- `Notches = 3` advances ~4-5 rows, so 8 rows always overlap between pages — never silent gaps.
- Sorted output; `-Fast` disables the double read.
- A 222-member group produced 227 unique ids in one sweep: real 5-to-8 digit ids exist, the panel
  can still list ex-members, and a handful of ids were OCR slips. The vote file is what separates
  those three cases.
- If File Explorer freezes while you clean up the output folder, it is the shell, not this tool:
  killing that `explorer.exe`, deleting `%LOCALAPPDATA%\Microsoft\Windows\Explorer\*.db` and
  restarting Explorer fixes it.
