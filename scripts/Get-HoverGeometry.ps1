#requires -Version 5.1
<#
.SYNOPSIS
  Print the geometry the hover-OCR pipeline currently sees, so a preset can be calibrated.
.EXAMPLE
  .\Get-HoverGeometry.ps1 -PresetName qq -Hwnd 123456
#>
[CmdletBinding()]
param([string]$PresetName = 'qq', [string]$PresetPath = '', [int64]$Hwnd = 0)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src\WinHoverOcr\WinHoverOcr.psd1') -Force
$info = Initialize-HoverOcr
Write-Host ('OCR language : ' + $info.OcrLanguage)
Write-Host ('Screen       : ' + $info.Screen)
if ($PresetPath) { $preset = Get-HoverPreset -Name $PresetPath } else { $preset = Get-HoverPreset -Name $PresetName }
Write-Host ''
Write-Host 'Visible windows matching the preset title pattern:'
$cands = @(Get-HoverWindow -TitleLike $preset.Window.TitleLike)
foreach ($c in $cands) {
  Write-Host ('  hwnd={0} pid={1} {2}x{3} iconic={4} ''{5}''' -f $c.Hwnd, $c.ProcessId, $c.Width, $c.Height, $c.IsIconic, $c.Title)
}
if ($Hwnd -le 0) {
  $best = @($cands | Sort-Object Width -Descending) | Select-Object -First 1
  if ($null -eq $best) { throw 'No window matched. Pass -Hwnd explicitly.' }
  $Hwnd = $best.Hwnd
}
Write-Host ''
Write-Host ('Using hwnd {0}' -f $Hwnd)
$preset.Window.Hwnd = $Hwnd
$anchors = @(Get-HoverRowAnchors -Preset $preset)
Write-Host ('Row anchors found: {0}' -f $anchors.Count)
if ($anchors.Count -ge 2) {
  $pitch = [int](($anchors[1] - $anchors[0]))
  Write-Host ('  first y={0}, pitch={1}, last y={2}' -f $anchors[0], $pitch, $anchors[$anchors.Count - 1])
  Write-Host ('  => suggested Row.Pitch = {0}' -f $pitch)
}
elseif ($anchors.Count -eq 1) {
  Write-Host ('  only one anchor y={0}' -f $anchors[0])
}
else {
  Write-Host '  none. Panel closed? preset Panel.X/Y/Width/Height wrong? RowTextX wrong?'
}
if ($anchors.Count -gt 0) {
  Write-Host ''
  Write-Host 'Probing the first row (hover + OCR):'
  $v = Read-HoverCardValue -Preset $preset -RowCenterY ([int]$anchors[0])
  Write-Host ('  value = ''' + $v + '''')
  if (-not $v) {
    Write-Host '  Nothing read. Adjust Card.X / Card.Bands offsets so the ''id'' line of the card.'
    Write-Host '  falls into one of the bands, then try again.'
  }
}
Write-Host ''
Write-Host 'Panel rect used : X={0} Y={1} {2}x{3} scale={4}' -f $preset.Panel.X, $preset.Panel.Y, $preset.Panel.Width, $preset.Panel.Height, $preset.Panel.Scale
Write-Host 'Scroll point    : X={0} Y={1} notches={2}' -f $preset.Scroll.X, $preset.Scroll.Y, $preset.Scroll.Notches