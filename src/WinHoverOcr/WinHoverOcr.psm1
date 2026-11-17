# WinHoverOcr.psm1
# Generic "hover card OCR" extraction for Windows desktop apps (Electron/Chromium friendly).
# Approach: DPI-aware screen capture + synthetic hover + Windows.Media.Ocr.
# Everything here is app agnostic; app specific geometry lives in presets/*.psd1.

$ErrorActionPreference = 'Continue'

if (-not ('WinHoverNative' -as [type])) {
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinHoverNative {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, int data, IntPtr extra);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
}

$script:OcrEngine = $null
$script:PresetDir = Join-Path $PSScriptRoot 'presets'
$script:TempCapture = Join-Path ([System.IO.Path]::GetTempPath()) 'winhoverocr_capture.png'

function Initialize-HoverOcr {
  [CmdletBinding()]
  param()
  if ($PSVersionTable.PSVersion.Major -ge 6) {
    throw ('WinHoverOCR needs Windows PowerShell 5.1 (powershell.exe). PowerShell ' + $PSVersionTable.PSVersion + ' / .NET Core has no WinRT projection, so [Windows.Media.Ocr.OcrEngine] cannot be resolved. Run: powershell -NoProfile -ExecutionPolicy Bypass -File <script>.ps1')
  }
  [void][WinHoverNative]::SetProcessDPIAware()
  if ($null -eq $script:OcrEngine) {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    $null = [Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
    $null = [Windows.Storage.StorageFile,Windows.Foundation,ContentType=WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder,Windows.Foundation,ContentType=WindowsRuntime]
    $script:OcrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if ($null -eq $script:OcrEngine) { throw 'No OCR language pack available. Install Settings > Time & language > Language > Optional features > OCR.' }
  }
  [pscustomobject]@{
    OcrLanguage = $script:OcrEngine.RecognizerLanguage.LanguageTag
    Screen = '{0}x{1}' -f [WinHoverNative]::GetSystemMetrics(0), [WinHoverNative]::GetSystemMetrics(1)
    DpiAware = $true
  }
}

function Invoke-WaitOcr([object]$op, [type]$type) {
  $methods = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq ('IAsyncOperation' + [char]96 + '1')
  }
  $task = $methods[0].MakeGenericMethod($type).Invoke($null, @($op))
  $task.Wait(-1) | Out-Null
  $task.Result
}

function Get-HoverWindow {
  [CmdletBinding()]
  param([string]$TitleLike = '*', [string[]]$ProcessName)
  Initialize-HoverOcr | Out-Null
  $script:Hits = New-Object System.Collections.ArrayList
  $cb = [WinHoverNative+EnumProc]{
    param($h, $p)
    if (-not [WinHoverNative]::IsWindowVisible($h)) { return $true }
    $sb = New-Object System.Text.StringBuilder 512
    [void][WinHoverNative]::GetWindowTextW($h, $sb, 512)
    $title = $sb.ToString()
    if ([string]::IsNullOrWhiteSpace($title)) { return $true }
    if ($title -notlike $TitleLike) { return $true }
    $r = New-Object WinHoverNative+RECT
    [void][WinHoverNative]::GetWindowRect($h, [ref]$r)
    $pid = 0; [void][WinHoverNative]::GetWindowThreadProcessId($h, [ref]$pid)
    $pname = ''
    try { $pname = (Get-Process -Id $pid -ErrorAction Stop).ProcessName } catch { }
    [void]$script:Hits.Add([pscustomobject]@{
      Hwnd = [int64]$h; Title = $title; ProcessName = $pname; ProcessId = $pid
      X = $r.Left; Y = $r.Top; Width = ($r.Right - $r.Left); Height = ($r.Bottom - $r.Top)
      IsIconic = [WinHoverNative]::IsIconic($h)
    })
    return $true
  }
  [void][WinHoverNative]::EnumWindows($cb, [IntPtr]::Zero)
  $all = @($script:Hits)
  if ($ProcessName) { $all = @($all | Where-Object { $ProcessName -contains $_.ProcessName }) }
  $all
}

function Get-HoverPreset {
  [CmdletBinding()]
  param([string]$Name = 'qq')
  $path = $Name
  if (-not (Test-Path -LiteralPath $path)) {
    $path = Join-Path $script:PresetDir ($Name + '.psd1')
  }
  if (-not (Test-Path -LiteralPath $path)) { throw "Preset not found: $Name" }
  $p = Import-PowerShellDataFile -LiteralPath $path
  $p.Path = (Resolve-Path -LiteralPath $path).Path
  $p
}

function Move-HoverCursor {
  [CmdletBinding()]
  param([int]$X, [int]$Y)
  $w = [WinHoverNative]::GetSystemMetrics(0)
  $h = [WinHoverNative]::GetSystemMetrics(1)
  $nx = [int]([math]::Round($X * 65535 / ($w - 1)))
  $ny = [int]([math]::Round($Y * 65535 / ($h - 1)))
  [WinHoverNative]::mouse_event(0x0001 -bor 0x8000, $nx, $ny, 0, [IntPtr]::Zero)
}

function Invoke-HoverClick {
  [CmdletBinding()]
  param([int]$X, [int]$Y, [int]$SettleMs = 200)
  Move-HoverCursor -X $X -Y $Y
  Start-Sleep -Milliseconds 90
  [WinHoverNative]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 40
  [WinHoverNative]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds $SettleMs
}

function Invoke-HoverScroll {
  [CmdletBinding()]
  param([int]$X, [int]$Y, [int]$Notches, [int]$SettleMs = 1700)
  Move-HoverCursor -X $X -Y $Y
  Start-Sleep -Milliseconds 120
  [WinHoverNative]::mouse_event(0x0800, 0, 0, (-120 * $Notches), [IntPtr]::Zero)
  Start-Sleep -Milliseconds $SettleMs
}

function Get-HoverScreenshot {
  [CmdletBinding()]
  param([int]$X, [int]$Y, [int]$Width, [int]$Height, [double]$Scale = 1.0, [string]$Path)
  Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
  $src = New-Object System.Drawing.Bitmap($Width, $Height)
  $g = [System.Drawing.Graphics]::FromImage($src)
  $g.CopyFromScreen($X, $Y, 0, 0, (New-Object System.Drawing.Size($Width, $Height)))
  $g.Dispose()
  $bmp = $src
  if ($Scale -ne 1.0) {
    $bw = [int]($Width * $Scale); $bh = [int]($Height * $Scale)
    $bmp = New-Object System.Drawing.Bitmap($bw, $bh)
    $g2 = [System.Drawing.Graphics]::FromImage($bmp)
    $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g2.DrawImage($src, 0, 0, $bw, $bh)
    $g2.Dispose()
    $src.Dispose()
  }
  if (-not $Path) { $Path = $script:TempCapture }
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  $Path
}

function Get-HoverWindowScreenshot {
  [CmdletBinding()]
  param([int64]$Hwnd, [string]$Path)
  Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
  $r = New-Object WinHoverNative+RECT
  [void][WinHoverNative]::GetWindowRect([IntPtr]$Hwnd, [ref]$r)
  $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
  if ($w -le 0 -or $h -le 0) { throw 'Window has no area (minimized?)' }
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  [void][WinHoverNative]::PrintWindow([IntPtr]$Hwnd, $hdc, 2)
  $g.ReleaseHdc($hdc)
  $g.Dispose()
  if (-not $Path) { $Path = $script:TempCapture }
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  $Path
}

function Invoke-HoverOcrRegion {
  [CmdletBinding()]
  param([int]$X, [int]$Y, [int]$Width, [int]$Height, [double]$Scale = 1.8, [string]$TextPath)
  if ($null -eq $script:OcrEngine) { Initialize-HoverOcr | Out-Null }
  $png = Get-HoverScreenshot -X $X -Y $Y -Width $Width -Height $Height -Scale $Scale -Path $TextPath
  $file = Invoke-WaitOcr ([Windows.Storage.StorageFile]::GetFileFromPathAsync($png)) ([Windows.Storage.StorageFile])
  $stream = Invoke-WaitOcr ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Invoke-WaitOcr ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $sb = Invoke-WaitOcr ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $res = Invoke-WaitOcr ($script:OcrEngine.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
  $stream.Dispose()
  $lines = New-Object System.Collections.ArrayList
  foreach ($line in @($res.Lines)) {
    $words = New-Object System.Collections.ArrayList
    foreach ($w in @($line.Words)) {
      [void]$words.Add([pscustomobject]@{
        Text = $w.Text
        X = [int]($X + $w.BoundingRect.X / $Scale)
        Y = [int]($Y + $w.BoundingRect.Y / $Scale)
        Width = [int]($w.BoundingRect.Width / $Scale)
        Height = [int]($w.BoundingRect.Height / $Scale)
      })
    }
    [void]$lines.Add([pscustomobject]@{ Text = $line.Text; Words = $words })
  }
  $lines
}

function ConvertTo-HoverDigits {
  [CmdletBinding()]
  param([string]$Text)
  $map = @{ 'S' = '5'; 'O' = '0'; 'D' = '0'; 'I' = '1'; 'L' = '1'; 'B' = '8'; 'Z' = '2'; 'G' = '6'; 'T' = '7' }
  $chars = $Text.ToCharArray()
  $out = New-Object System.Text.StringBuilder
  foreach ($c in $chars) {
    $k = ([string]$c).ToUpper()
    if ($c -match '[0-9]') { [void]$out.Append($c) }
    elseif ($map.ContainsKey($k)) { [void]$out.Append($map[$k]) }
  }
  $out.ToString()
}

function Get-HoverPanelState {
  [CmdletBinding()]
  param([hashtable]$Preset)
  $panel = $Preset.Panel
  $lines = Invoke-HoverOcrRegion -X $panel.X -Y $panel.Y -Width $panel.Width -Height $panel.Height -Scale $panel.Scale
  $ys = New-Object System.Collections.ArrayList
  $names = New-Object System.Collections.ArrayList
  $colX = $panel.RowTextX
  $minH = $panel.MinWordHeight
  $maxH = $panel.MaxWordHeight
  foreach ($line in $lines) {
    foreach ($w in $line.Words) {
      if ($w.X -ge $colX[0] -and $w.X -le $colX[1] -and $w.Height -ge $minH -and $w.Height -le $maxH) {
        [void]$ys.Add($w.Y)
        [void]$names.Add($w.Text)
      }
    }
  }
  $sorted = @($ys | Sort-Object)
  $anchors = New-Object System.Collections.ArrayList
  $last = -999999
  foreach ($y in $sorted) {
    if (($y - $last) -gt $Preset.Row.MinAnchorGap) { [void]$anchors.Add($y); $last = $y }
  }
  [pscustomobject]@{ Anchors = $anchors; Signature = (($names | Sort-Object) -join '|') }
}

function Get-HoverRowAnchors {
  [CmdletBinding()]
  param([hashtable]$Preset)
  (Get-HoverPanelState -Preset $Preset).Anchors
}

function Complete-HoverRowAnchors {
  [CmdletBinding()]
  param([int[]]$Anchors, [int]$TopY, [int]$BottomY, [int]$Pitch)
  $out = New-Object System.Collections.ArrayList
  $prev = $TopY
  foreach ($y in @($Anchors | Sort-Object)) { [void]$out.Add($y); $prev = $y }
  if ($out.Count -eq 0) { return ,$out }
  $filled = New-Object System.Collections.ArrayList
  $cursor = $out[0]
  foreach ($y in $out) {
    while (($y - $cursor) -gt ($Pitch * 1.6)) { $cursor = $cursor + $Pitch; if ($cursor -lt $BottomY) { [void]$filled.Add($cursor) } }
    [void]$filled.Add($y)
    $cursor = $y
  }
  $filled | Sort-Object -Unique
}

function Read-HoverCardValue {
  [CmdletBinding()]
  param([hashtable]$Preset, [int]$RowCenterY)
  $card = $Preset.Card
  $hover = $Preset.Hover
  $attempt = 0
  while ($attempt -lt $Preset.ReadAttempts) {
    $attempt++
    $jy = $RowCenterY
    foreach ($pt in $hover.Jiggle) {
      Move-HoverCursor -X ($hover.X + $pt[0]) -Y ([math]::Max(20, $jy + $pt[1]))
      Start-Sleep -Milliseconds 70
    }
    Move-HoverCursor -X $hover.X -Y ($jy + 1)
    Start-Sleep -Milliseconds ($hover.SettleMs + 200 * $attempt)
    foreach ($band in $card.Bands) {
      $bx = $card.X
      $by = [math]::Max(0, $RowCenterY + $band.OffsetY)
      $lines = Invoke-HoverOcrRegion -X $bx -Y $by -Width $card.Width -Height $band.Height -Scale $card.Scale
      foreach ($line in $lines) {
        $raw = ($line.Text -replace '\s', '')
        $digits = ConvertTo-HoverDigits $raw
        $m = [regex]::Match($digits, $card.Pattern)
        if (-not $m.Success) { $m = [regex]::Match($raw, $card.LoosePattern) }
        if ($m.Success) { return $m.Groups[1].Value }
      }
    }
  }
  ''
}

function Read-HoverCardValueVerified {
  [CmdletBinding()]
  param([hashtable]$Preset, [int]$RowCenterY, [switch]$Double)
  $first = Read-HoverCardValue -Preset $Preset -RowCenterY $RowCenterY
  if (-not $Double) { return $first }
  $second = Read-HoverCardValue -Preset $Preset -RowCenterY $RowCenterY
  if ($first -eq $second -and $first -ne '') { return $first }
  $third = Read-HoverCardValue -Preset $Preset -RowCenterY $RowCenterY
  if ($first -eq $third -and $first -ne '') { return $first }
  if ($second -eq $third -and $second -ne '') { return $second }
  ''
}

function Write-HoverResult {
  [CmdletBinding()]
  param([string[]]$Values, [string]$Path, [string]$CsvPath)
  $uniq = @($Values | Where-Object { $_ } | Sort-Object -Unique)
  $allNumeric = $true
  foreach ($v in $uniq) { if ($v -notmatch '^\d+$') { $allNumeric = $false; break } }
  if ($allNumeric) { $uniq = @($uniq | Sort-Object { [double]$_ }) }
  $text = ($uniq -join [Environment]::NewLine) + [Environment]::NewLine
  [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($false)))
  if ($CsvPath) {
    $rows = for ($i = 0; $i -lt $uniq.Count; $i++) { '{0},{1}' -f ($i + 1), $uniq[$i] }
    [System.IO.File]::WriteAllLines($CsvPath, (@('index,value') + $rows), (New-Object System.Text.UTF8Encoding($false)))
  }
  $uniq.Count
}

function Invoke-HoverFieldScan {
  [CmdletBinding()]
  param(
    [hashtable]$Preset,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [string]$LogPath,
    [int]$MaxPages = 60,
    [switch]$VerifyDouble,
    [int]$StaleLimit = 3,
    [switch]$NoScroll,
    [int]$Passes = 1,
    [switch]$TailSweep,
    [int]$MinHits = 1,
    [int]$SweepNotches = 0,
    [int]$TopNotches = 220
  )
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $hits = @{}
  $log = New-Object System.Collections.ArrayList
  if (-not $LogPath) { $LogPath = [System.IO.Path]::ChangeExtension($OutFile, '.log') }
  $hwnd = [int64]$Preset.Window.Hwnd
  if ($hwnd -le 0) { throw 'Preset has no Window.Hwnd. Run Get-HoverWindow and set it.' }
  if ($Passes -lt 1) { $Passes = 1 }
  $scroll = $Preset.Scroll
  if ($SweepNotches -le 0) { $SweepNotches = [int]$scroll.Notches }
  $panelTop = [int]$Preset.Panel.Y
  $panelBottom = [int]$Preset.Panel.Y + [int]$Preset.Panel.Height

  # Reads the current viewport: hovers every row, OCRs the card, counts hits per value.
  $readViewport = {
    param([string]$Tag)
    if ($Preset.EnsureForeground -and [WinHoverNative]::GetForegroundWindow() -ne [IntPtr]$hwnd) {
      [void][WinHoverNative]::SetForegroundWindow([IntPtr]$hwnd)
      Start-Sleep -Milliseconds 350
    }
    $state = Get-HoverPanelState -Preset $Preset
    if ($state.Anchors.Count -eq 0) {
      [void]$log.Add(('{0} NO_ROWS (panel closed, occluded, or preset mismatch)' -f $Tag))
      return [pscustomobject]@{ Done = $true; Added = 0; Signature = ''; Rows = 0; Pitch = 0 }
    }
    $pitch = $Preset.Row.Pitch
    if ($state.Anchors.Count -ge 2) {
      $diffs = for ($i = 1; $i -lt $state.Anchors.Count; $i++) { $state.Anchors[$i] - $state.Anchors[$i - 1] }
      $pitch = [int](($diffs | Measure-Object -Average).Average)
    }
    $rows = @(Complete-HoverRowAnchors -Anchors $state.Anchors -TopY $panelTop -BottomY $panelBottom -Pitch $pitch)
    $added = 0
    $detail = New-Object System.Collections.ArrayList
    foreach ($y in $rows) {
      $v = Read-HoverCardValueVerified -Preset $Preset -RowCenterY $y -Double:$VerifyDouble
      if ($v) {
        $n = 0
        if ($hits.ContainsKey($v)) { $n = [int]$hits[$v] }
        $hits[$v] = $n + 1
        if ($n -eq 0) { $added++ }
      }
      [void]$detail.Add(('{0}:{1}' -f $y, $v))
    }
    [void]$log.Add(('{0} rows={1} pitch={2} added={3} total={4} :: {5}' -f $Tag, $rows.Count, $pitch, $added, $hits.Count, ($detail -join ' ')))
    [pscustomobject]@{ Done = $false; Added = $added; Signature = $state.Signature; Rows = $rows.Count; Pitch = $pitch }
  }

  for ($pass = 1; $pass -le $Passes; $pass++) {
    if ($pass -gt 1 -and -not $NoScroll) {
      Invoke-HoverScroll -X $scroll.X -Y $scroll.Y -Notches (-$TopNotches) -SettleMs $scroll.SettleMs
      Start-Sleep -Milliseconds 250
    }
    $lastSig = ''
    $stale = 0
    for ($page = 0; $page -lt $MaxPages; $page++) {
      $r = & $readViewport ('PASS {0} PAGE {1}' -f $pass, $page)
      if ($r.Done) { break }
      if ($lastSig -and $r.Signature -and $r.Signature -eq $lastSig) {
        [void]$log.Add(('PASS {0} NO_PROGRESS at page {1} (viewport did not change)' -f $pass, $page))
        break
      }
      if ($r.Added -lt 1) { $stale++ } else { $stale = 0 }
      if ($stale -ge $StaleLimit) { [void]$log.Add(('PASS {0} STOP stale at page {1}' -f $pass, $page)); break }
      if ($NoScroll) { break }
      Invoke-HoverScroll -X $scroll.X -Y $scroll.Y -Notches $SweepNotches -SettleMs $scroll.SettleMs
      $lastSig = $r.Signature
    }
  }

  # Optional tail sweep: jump to the very bottom, then walk upwards to catch the last rows.
  if ($TailSweep -and -not $NoScroll) {
    [void]$log.Add('TAIL jump to bottom')
    Invoke-HoverScroll -X $scroll.X -Y $scroll.Y -Notches $TopNotches -SettleMs $scroll.SettleMs
    Start-Sleep -Milliseconds 400
    $lastSig = ''
    $stale = 0
    $tailPages = [math]::Min($MaxPages, 45)
    for ($page = 0; $page -lt $tailPages; $page++) {
      $r = & $readViewport ('TAIL PAGE {0}' -f $page)
      if ($r.Done) { break }
      if ($lastSig -and $r.Signature -and $r.Signature -eq $lastSig) {
        [void]$log.Add(('TAIL NO_PROGRESS at page {0}' -f $page))
        break
      }
      if ($r.Added -lt 1) { $stale++ } else { $stale = 0 }
      if ($stale -ge $StaleLimit) { [void]$log.Add(('TAIL STOP stale at page {0}' -f $page)); break }
      Invoke-HoverScroll -X $scroll.X -Y $scroll.Y -Notches (-$SweepNotches) -SettleMs $scroll.SettleMs
      $lastSig = $r.Signature
    }
  }

  $values = @($hits.Keys | Where-Object { [int]$hits[$_] -ge $MinHits })
  $count = Write-HoverResult -Values $values -Path $OutFile
  $hitsFile = [System.IO.Path]::ChangeExtension($OutFile, '.hits.txt')
  $hitLines = New-Object System.Collections.ArrayList
  [void]$hitLines.Add('value' + [char]9 + 'hits')
  foreach ($k in ($hits.Keys | Sort-Object { [double]$_ })) { [void]$hitLines.Add(([string]$k) + [char]9 + ([string]$hits[$k])) }
  [System.IO.File]::WriteAllLines($hitsFile, $hitLines, (New-Object System.Text.UTF8Encoding($false)))
  [void]$log.Add(('DONE values={0} (minHits={1}) raw={2} passes={3} tail={4}' -f $count, $MinHits, $hits.Count, $Passes, $TailSweep.IsPresent))
  $sw.Stop()
  [void]$log.Add(('ELAPSED {0:n1}s' -f $sw.Elapsed.TotalSeconds))
  [System.IO.File]::WriteAllLines($LogPath, $log, (New-Object System.Text.UTF8Encoding($false)))
  [pscustomobject]@{
    OutFile = $OutFile
    HitsFile = $hitsFile
    LogFile = $LogPath
    Count = $count
    RawCount = $hits.Count
    Passes = $Passes
    TailSweep = $TailSweep.IsPresent
    ElapsedSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  }
}

function Set-HoverPresetWindow {
  [CmdletBinding()]
  param([hashtable]$Preset, [int64]$Hwnd, [string]$OutPath)
  $Preset.Window.Hwnd = $Hwnd
  if ($OutPath) {
    $txt = Get-Content -LiteralPath $Preset.Path -Raw
    $txt = [regex]::Replace($txt, "Hwnd\s*=\s*-?\d+", ("Hwnd = " + $Hwnd))
    [System.IO.File]::WriteAllText($OutPath, $txt, (New-Object System.Text.UTF8Encoding($false)))
  }
  $Preset
}

function Get-HoverOcrText {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path)
  if ($null -eq $script:OcrEngine) { Initialize-HoverOcr | Out-Null }
  $file = Invoke-WaitOcr ([Windows.Storage.StorageFile]::GetFileFromPathAsync((Resolve-Path -LiteralPath $Path).Path)) ([Windows.Storage.StorageFile])
  $stream = Invoke-WaitOcr ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Invoke-WaitOcr ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $sb = Invoke-WaitOcr ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $res = Invoke-WaitOcr ($script:OcrEngine.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
  $stream.Dispose()
  $lines = New-Object System.Collections.ArrayList
  foreach ($line in @($res.Lines)) {
    $words = New-Object System.Collections.ArrayList
    foreach ($w in @($line.Words)) {
      [void]$words.Add([pscustomobject]@{ Text = $w.Text; X = [int]$w.BoundingRect.X; Y = [int]$w.BoundingRect.Y; Width = [int]$w.BoundingRect.Width; Height = [int]$w.BoundingRect.Height })
    }
    [void]$lines.Add([pscustomobject]@{ Text = $line.Text; Words = $words })
  }
  $lines
}
Export-ModuleMember -Function Initialize-HoverOcr, Get-HoverOcrText, Get-HoverWindow, Get-HoverPreset, Move-HoverCursor, Invoke-HoverClick, Invoke-HoverScroll, Get-HoverScreenshot, Get-HoverWindowScreenshot, Invoke-HoverOcrRegion, ConvertTo-HoverDigits, Get-HoverPanelState, Get-HoverRowAnchors, Complete-HoverRowAnchors, Read-HoverCardValue, Read-HoverCardValueVerified, Write-HoverResult, Invoke-HoverFieldScan, Set-HoverPresetWindow