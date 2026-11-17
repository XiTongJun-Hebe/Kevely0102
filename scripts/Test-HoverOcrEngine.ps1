#requires -Version 5.1
<#
.SYNOPSIS
  Offline smoke test: renders sample text to a bitmap, OCRs it and prints what was read.
  Proves the OCR engine works without touching any target application.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src\WinHoverOcr\WinHoverOcr.psd1') -Force
Add-Type -AssemblyName System.Drawing
$info = Initialize-HoverOcr
Write-Host ('OCR language: ' + $info.OcrLanguage)
$w = 900; $h = 220
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::White)
$font = New-Object System.Drawing.Font('Segoe UI', 28)
$g.DrawString('QQ 123456789', $font, [System.Drawing.Brushes]::Black, 20, 30)
$g.DrawString('Hover OCR smoke test', $font, [System.Drawing.Brushes]::Black, 20, 110)
$g.Dispose(); $font.Dispose()
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'winhoverocr_smoke.png'
$bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$lines = Get-HoverOcrText -Path $tmp
$joined = ($lines | ForEach-Object { $_.Text }) -join ' | '
Write-Host ('OCR text: ' + $joined)
$digits = ConvertTo-HoverDigits ($joined -replace '\s', '')
if ($digits -match '123456789') { Write-Host '[ok] digits survived OCR'; exit 0 }
Write-Warning 'Digits were not read as expected - OCR quality problem on this machine.'
exit 1