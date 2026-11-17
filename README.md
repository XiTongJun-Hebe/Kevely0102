# WinHoverOCR

[![syntax](https://github.com/XiTongJun-Hebe/Kevely0102/actions/workflows/syntax.yml/badge.svg)](https://github.com/XiTongJun-Hebe/Kevely0102/actions/workflows/syntax.yml)

**Read data that only appears on hover.** Point the mouse at a list row, screenshot the
tooltip / profile card that pops up, OCR it, then scroll and repeat until the list ends.

Built for Windows 10/11 with nothing but stock PowerShell 5.1 and the OCR engine that
already ships with Windows. No Selenium, no Python, no cloud API, no login, no network calls.

The bundled example reads every member QQ id out of a QQ NT group chat — a number that is
otherwise only visible by hovering each avatar by hand.

---

## Why this exists

Some desktop apps (Electron ones especially) hide the useful field in a hover card and
expose nothing to automation:

| Route | Result on QQ NT 9.9.x |
| --- | --- |
| Local message DB | SQLCipher-encrypted, `file is not a database` |
| `qun.qq.com` member API | `{"ec":7,"em":"require admin"}` — owner/admin only |
| UI Automation / a11y tree | one opaque `Pane`, no rows |
| Synthesised `WM_MOUSEMOVE` + `PrintWindow` | pixel-identical frames, hover never fires |
| **Real cursor move + screen OCR** | **works** |

So this project does exactly what a human would do — and it does it 222 times without
complaining.

## What it does

1. Finds the target window by title and remembers its rectangle.
2. Screenshots the list area and uses the OCR word boxes to locate each row's vertical anchor.
3. For each row: jiggle the cursor onto it (Chromium needs *movement*, a single jump is ignored),
   wait for the hover card, screenshot the card band, OCR it, extract the field with a regex.
4. Optionally reads the same row twice and only keeps the value when both reads agree.
5. Scrolls the list inside the panel, repeats until N stale pages, writes a sorted
   de-duplicated `.txt`, and keeps a page-by-page log.

## Requirements

- Windows 10 / 11 (uses `Windows.Media.Ocr`, present in every modern Windows)
- **Windows PowerShell 5.1** (the built-in `powershell.exe`). PowerShell 7 cannot run this:
  .NET Core has no WinRT projection, so `[Windows.Media.Ocr.OcrEngine]` does not resolve.
  The module throws an explicit error instead of failing obscurely.
- An OCR language pack that covers the card text (Simplified Chinese pack for QQ)
- The target app visible on a physical display, list panel open, **not** minimized

## Quick start

```powershell
git clone https://github.com/<you>/Kevely0102.git
cd Kevely0102

# 1. is OCR alive on this machine?
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-HoverOcrEngine.ps1

# 2. open your QQ group chat, expand the member panel, then:
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Export-QQGroupMembers.ps1 `
  -GroupId 100000000 -OutFile .\members.txt
```

Output is one id per line, ascending, no duplicates:

```
100000001
100000002
...
```

A sanity check on the geometry first is always cheaper than a 6-minute scan:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-HoverGeometry.ps1 -PresetName qq
```

It prints the matched window, the detected row anchors, the row pitch it inferred, and the
value it read from the first row. If that last line is empty, fix the preset before scanning.

## Layout

```
src/WinHoverOcr/
  WinHoverOcr.psm1      module: DPI, cursor, scroll, screenshot, OCR, row maths, scan loop
  WinHoverOcr.psd1      manifest
  presets/qq.psd1       QQ NT geometry (panel rect, row text band, card bands, scroll point)
scripts/
  Export-QQGroupMembers.ps1   ready-made QQ exporter
  Invoke-HoverScan.ps1        same engine with any preset
  Get-HoverGeometry.ps1       calibration report
  Test-HoverOcrEngine.ps1     offline OCR smoke test (renders text, no app needed)
```

## Presets

A preset is a plain `.psd1` hashtable — everything is **physical screen pixels**, because the
module calls `SetProcessDPIAware()` before measuring anything.

```powershell
@{
  Name             = 'qq'
  EnsureForeground = $true          # QQ ignores hover while unfocused
  ReadAttempts     = 3
  Window   = @{ Hwnd = 0; TitleLike = '*QQ*' }
  Panel    = @{                     # where the list is, and how to read its row labels
    X = 2075; Y = 240; Width = 500; Height = 1200; Scale = 2
    RowTextX = @(2140, 2215)        # x band that contains the row text
    MinWordHeight = 12; MaxWordHeight = 36
  }
  Row      = @{ Pitch = 90; MinAnchorGap = 35 }
  Hover    = @{ X = 2189; Jiggle = @(@(-160,-70), @(-60,-20), @(-10,0)); SettleMs = 650 }
  Card     = @{                     # the hover card sits left of the panel
    X = 1459; Width = 600; Scale = 1.8
    Pattern      = '^(\d{6,11})$'
    LoosePattern = 'QQ(\d{6,11})'
    Bands = @(@{ OffsetY = -220; Height = 380 }, @{ OffsetY = -720; Height = 900 })
  }
  Scroll   = @{ X = 2300; Y = 900; Notches = 3; SettleMs = 1700 }
}
```

To port it to another app:

1. `Get-HoverWindow -TitleLike '*YourApp*'` → note `Hwnd`.
2. Screenshot it (`Get-HoverWindowScreenshot`) and OCR the whole image (`Get-HoverOcrText`) —
   read the word boxes to find where rows and the card live.
3. Fill in `Panel`, `Hover`, `Card`, `Scroll` and tune with `Get-HoverGeometry.ps1`.
4. `Invoke-HoverScan.ps1 -PresetPath .\mypreset.psd1 -OutFile .\out.txt`.

## How the hard parts work

**DPI.** A PowerShell host is DPI-unaware by default: it silently reports virtualised
coordinates (a 2560×1600 screen reports 1721×1033). Every rect is therefore measured after
`SetProcessDPIAware()`, which makes `GetWindowRect`, `CopyFromScreen` and the OCR boxes agree.

**Hover.** `SetCursorPos` and a single absolute `mouse_event` do **not** trigger Chromium's
hover — it needs incremental movement. The module walks a short jiggle path into the row, then
waits ~650 ms for the card to animate in.

**Scrolling.** The wheel event must land on the list, not the chat pane next to it; the row
*y* coordinates stay identical after scrolling, so progress is measured in newly discovered
values, never in geometry.

**OCR.** Ambiguous glyphs are normalised (`S→5`, `O/D→0`, `I/L→1`, `B→8`, `Z→2`, `G→6`,
`T→7`) but `Q` is deliberately left alone, otherwise the literal prefix `QQ` collapses into
`99` and every match is lost. Cards are cropped to a narrow band and upscaled before OCR —
whole-screen OCR of a 2560×1600 desktop misreads digits badly.

**Verification.** `-Fast` accepts the first successful read. Without it each row is read twice
and only a agreeing pair is kept, which is slower and much cleaner.

## Accuracy, honestly

Reading a 10-digit id off a screenshot is probabilistic. The bundled run over a 222-member
group produced 227 unique values in one pass: real short ids (6–8 digits) do exist, the member
list can contain stale entries, and a few values are OCR slips. Cross-check before you rely on
the result:

- run the scan twice and intersect the outputs;
- inspect low-digit targets by hand (search them in the member panel);
- keep the `.log` file — it records every read, per page, which makes disputes cheap to settle.

## Limitations

- **It uses the real cursor and the foreground window.** Chromium ignores synthetic hover
  messages, so there is no truly background mode. Do not touch the mouse while it runs, and do
  not expect to type in another window: keystrokes land wherever focus is.
- Coordinates are per app version and per layout; a redesign breaks the preset (recalibrate).
- One monitor, 100 %-to-200 % scaling both fine; mixed-DPI multi-monitor arrangements can
  shift coordinates.
- Slow by design: ~0.9 s per row with verification.
- Windows only.

## Privacy and ethics

This tool only reads pixels that are already on your screen. It does not log in, decrypt
databases, or contact any server.

Exported ids are personal data. Collect them only from groups you are entitled to, do not
publish or redistribute them, and respect the platform's terms and local law. The example
output in this repo is fabricated.

## License

MIT — see [LICENSE](LICENSE).