#requires -Version 5.1
<#
.SYNOPSIS
  Export every member QQ id of a QQ group chat into a txt file (one id per line).
.DESCRIPTION
  Requires the QQ NT client with the group chat open and the member panel ('Group members')
  already expanded. The script hovers each visible row, OCRs the profile card, scrolls the
  panel and merges everything it read. It does NOT log in and does NOT talk to any server.
.EXAMPLE
  .\Export-QQGroupMembers.ps1 -GroupId 100000000 -OutFile .\members.txt
#>
[CmdletBinding()]
param(
  [string]$GroupId = ''
  ,[string]$OutFile = ''
  ,[int64]$Hwnd = 0
  ,[switch]$Fast
  ,[int]$MaxPages = 60
  ,[int]$Passes = 1
  ,[int]$MinHits = 1
  ,[switch]$TailSweep
  ,[string]$PresetName = 'qq'
  ,[string]$PresetPath = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src\WinHoverOcr\WinHoverOcr.psd1') -Force
$info = Initialize-HoverOcr
Write-Host ('[i] OCR language: {0} / screen: {1}' -f $info.OcrLanguage, $info.Screen)
if (-not $OutFile) {
  $tag = if ($GroupId) { $GroupId -replace '\D', '' } else { 'group' }
  $OutFile = Join-Path (Get-Location).Path ('qq_' + $tag + '_members.txt')
}
if ($PresetPath) { $preset = Get-HoverPreset -Name $PresetPath } else { $preset = Get-HoverPreset -Name $PresetName }
if ($Hwnd -le 0) {
  $cands = @(Get-HoverWindow -TitleLike $preset.Window.TitleLike)
  $cands = @($cands | Sort-Object Width -Descending)
  if ($cands.Count -eq 0) { throw 'No matching window found. Is the app running?' }
  $Hwnd = $cands[0].Hwnd
  Write-Host ('[i] window {0} {1}x{2} ''{3}''' -f $cands[0].Hwnd, $cands[0].Width, $cands[0].Height, $cands[0].Title)
}
$preset.Window.Hwnd = $Hwnd
$anchors = @(Get-HoverRowAnchors -Preset $preset)
if ($anchors.Count -eq 0) {
  Write-Warning 'No rows detected in the panel area.'
  Write-Warning 'Check: 1) the member panel is open, 2) the window is not minimized, 3) preset geometry matches this app version (run Get-HoverGeometry.ps1).'
  Write-Warning 'Tip: adding -Notches/-Panel values from Get-HoverGeometry.ps1 usually fixes it.'
  return
}
Write-Host ('[i] detected {0} visible rows' -f $anchors.Count)
$res = Invoke-HoverFieldScan -Preset $preset -OutFile $OutFile -MaxPages $MaxPages -Passes $Passes -MinHits $MinHits -TailSweep:$TailSweep -VerifyDouble:(-not $Fast)
Write-Host ('[ok] {0} unique values written to {1}' -f $res.Count, $res.OutFile)
Write-Host ('[i] log: {0} ({1}s, raw reads {2})' -f $res.LogFile, $res.ElapsedSeconds, $res.RawCount)
Write-Host ('[i] hits: {0} (values seen once stay only if -MinHits 1)' -f $res.HitsFile)
if ($res.Count -lt 10) { Write-Warning 'Very few rows were read. Re-run Get-HoverGeometry.ps1 and adjust the preset.' }
$res
