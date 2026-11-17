# QQ NT (9.9.x, Electron) member-panel preset.
# All coordinates are PHYSICAL screen pixels (the module calls SetProcessDPIAware).
# If the app layout changes, run scripts/Get-HoverGeometry.ps1 and update the values below.
@{
  Name = 'qq'
  Description = 'QQ NT group member panel: hover an avatar row, OCR the QQ id from the profile card.'
  EnsureForeground = $true
  ReadAttempts = 3
  Window = @{ Hwnd = 0; TitleLike = '*QQ*' }
  Panel = @{
    X = 2075; Y = 240; Width = 500; Height = 1200; Scale = 2
    RowTextX = @(2140, 2215)
    MinWordHeight = 12; MaxWordHeight = 36
  }
  Row = @{ Pitch = 90; MinAnchorGap = 35 }
  Hover = @{ X = 2189; Jiggle = @(@(-160,-70), @(-60,-20), @(-10,0)); SettleMs = 650 }
  Card = @{
    X = 1459; Width = 600; Scale = 1.8
    Pattern = '^(\d{6,11})$'
    LoosePattern = 'QQ(\d{6,11})'
    Bands = @(@{ OffsetY = -220; Height = 380 }, @{ OffsetY = -720; Height = 900 })
  }
  Scroll = @{ X = 2300; Y = 900; Notches = 3; SettleMs = 1700 }
}