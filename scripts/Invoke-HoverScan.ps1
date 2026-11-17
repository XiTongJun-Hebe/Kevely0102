#requires -Version 5.1
<#
.SYNOPSIS
  Run a hover-card scan with any preset (generic entry point).
.EXAMPLE
  .\Invoke-HoverScan.ps1 -PresetPath .\src\WinHoverOcr\presets\qq.psd1 -Hwnd 123456 -OutFile .\out.txt
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$PresetPath
  ,[Parameter(Mandatory = $true)][string]$OutFile
  ,[int64]$Hwnd = 0
  ,[switch]$Fast
  ,[int]$MaxPages = 60
  ,[int]$Passes = 1
  ,[int]$MinHits = 1
  ,[switch]$TailSweep
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src\WinHoverOcr\WinHoverOcr.psd1') -Force
$preset = Get-HoverPreset -Name $PresetPath
if ($Hwnd -gt 0) { $preset.Window.Hwnd = $Hwnd }
if ([int64]$preset.Window.Hwnd -le 0) { throw 'Pass -Hwnd (see Get-HoverWindow).' }
Invoke-HoverFieldScan -Preset $preset -OutFile $OutFile -MaxPages $MaxPages -Passes $Passes -MinHits $MinHits -TailSweep:$TailSweep -VerifyDouble:(-not $Fast)
