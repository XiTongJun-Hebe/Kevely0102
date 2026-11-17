@{
  RootModule = 'WinHoverOcr.psm1'
  ModuleVersion = '0.1.0'
  GUID = 'b1e0a8f2-6d3c-4f4b-9a57-2f3c8d9e6a10'
  Author = 'Kevely0102 contributors'
  Description = 'Hover-card OCR extraction for Windows desktop apps (QQ member list preset included).'
  PowerShellVersion = '5.1'
  FunctionsToExport = @('Initialize-HoverOcr','Get-HoverOcrText','Get-HoverWindow','Get-HoverPreset','Move-HoverCursor','Invoke-HoverClick','Invoke-HoverScroll','Get-HoverScreenshot','Get-HoverWindowScreenshot','Invoke-HoverOcrRegion','ConvertTo-HoverDigits','Get-HoverRowAnchors','Complete-HoverRowAnchors','Read-HoverCardValue','Read-HoverCardValueVerified','Write-HoverResult','Invoke-HoverFieldScan','Set-HoverPresetWindow')
  CmdletsToExport = @()
  VariablesToExport = @()
  AliasesToExport = @()
  PrivateData = @{ PSData = @{ Tags = @('windows','ocr','automation','uia','qq'); LicenseUri = 'https://opensource.org/licenses/MIT' } }
}