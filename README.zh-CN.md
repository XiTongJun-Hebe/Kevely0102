# WinHoverOCR

**把「只有鼠标悬停才会出现」的数据读出来。** 把光标移到列表行上，截取弹出的悬浮卡片 /
提示框，交给 Windows 自带 OCR，再滚动列表、重复，直到读完整个列表。

只依赖 Windows 10/11 自带的 PowerShell 5.1 和系统 OCR 引擎。不需要 Selenium、不需要
Python、不调云端接口、不登录、不联网。

仓库自带的示例是「导出 QQ NT 群聊的全部成员 QQ 号」——这个号码平时只能靠鼠标一个个
悬停头像去看。

---

## 为什么需要它

有些桌面软件（尤其是 Electron 的）把关键字段藏在悬停卡片里，而且对自动化全封闭。
在 QQ NT 9.9.x 上的实测结论：

| 路线 | 结果 |
| --- | --- |
| 本地消息数据库 | SQLCipher 加密，`file is not a database` |
| `qun.qq.com` 群成员接口 | `{"ec":7,"em":"require admin"}`，只有群主/管理员可用 |
| UI Automation / 无障碍树 | 只有一个不透明的 `Pane`，拿不到行 |
| 合成 `WM_MOUSEMOVE` + `PrintWindow` | 前后帧逐像素相同，悬停根本不触发 |
| **真实光标移动 + 屏幕 OCR** | **可用** |

所以本项目的做法就是「把人的操作重复 200 多次」：移动、等待、截图、识别、滚动、去重。

## 工作原理

1. 按标题匹配目标窗口，记下窗口矩形；
2. 截图列表区域，用 OCR 词框定位每一行的纵向锚点；
3. 逐行抖动光标进入该行（Chromium 需要「移动过程」，瞬间跳转无效），等待悬浮卡片出现，
   截取卡片条带、OCR、用正则取出字段；
4. 可选：同一行读两次，只有两次一致才采纳；
5. 在面板内滚动列表，连续多页无新值则停止，输出升序去重的 `.txt`，并保留逐页日志。

## 环境要求

- Windows 10 / 11（使用系统自带 `Windows.Media.Ocr`）
- Windows PowerShell 5.1（系统自带 `powershell.exe`）或 PowerShell 7
- 覆盖卡片文字的 OCR 语言包（中文卡片需要简体中文包）
- 目标窗口在物理显示器上可见、列表面板已打开、**未最小化**

## 快速开始

```powershell
git clone https://github.com/<you>/winhover-ocr.git
cd winhover-ocr

# 1. 先确认这台机器的 OCR 能用
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-HoverOcrEngine.ps1

# 2. 打开 QQ 群聊、展开「群聊成员」面板，然后：
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Export-QQGroupMembers.ps1 `
  -GroupId 100000000 -OutFile .\members.txt
```

输出一人一行、升序、无重复。

先跑一次几何校准，比跑去扫 6 分钟划算：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-HoverGeometry.ps1 -PresetName qq
```

它会打印匹配到的窗口、识别到的行锚点、推算出的行距，以及第一行读到的值。最后一项为空
就先别扫，先修预设。

## 目录结构

```
src/WinHoverOcr/
  WinHoverOcr.psm1      模块：DPI/光标/滚动/截图/OCR/行距推算/扫描主循环
  WinHoverOcr.psd1      模块清单
  presets/qq.psd1       QQ NT 的几何参数（面板矩形、行文字带、卡片条带、滚动点）
scripts/
  Export-QQGroupMembers.ps1   QQ 群成员导出脚本（开箱即用）
  Invoke-HoverScan.ps1        用任意预设跑同一套引擎
  Get-HoverGeometry.ps1       几何校准报告
  Test-HoverOcrEngine.ps1     离线 OCR 自检（自绘文字，不依赖任何软件）
```

## 预设

预设就是一个普通的 `.psd1` 哈希表，所有坐标都是**物理屏幕像素**（模块会先调
`SetProcessDPIAware()`）。

```powershell
@{
  Name             = 'qq'
  EnsureForeground = $true          # QQ 失焦时不响应悬停
  ReadAttempts     = 3
  Window   = @{ Hwnd = 0; TitleLike = '*QQ*' }
  Panel    = @{
    X = 2075; Y = 240; Width = 500; Height = 1200; Scale = 2
    RowTextX = @(2140, 2215)
    MinWordHeight = 12; MaxWordHeight = 36
  }
  Row      = @{ Pitch = 90; MinAnchorGap = 35 }
  Hover    = @{ X = 2189; Jiggle = @(@(-160,-70), @(-60,-20), @(-10,0)); SettleMs = 650 }
  Card     = @{
    X = 1459; Width = 600; Scale = 1.8
    Pattern      = '^(\d{6,11})$'
    LoosePattern = 'QQ(\d{6,11})'
    Bands = @(@{ OffsetY = -220; Height = 380 }, @{ OffsetY = -720; Height = 900 })
  }
  Scroll   = @{ X = 2300; Y = 900; Notches = 3; SettleMs = 1700 }
}
```

换到别的软件：

1. `Get-HoverWindow -TitleLike '*你的软件*'` 拿到 `Hwnd`；
2. `Get-HoverWindowScreenshot` 截图，再用 `Get-HoverOcrText` 对整图 OCR，看词框坐标，
   确定行与卡片的位置；
3. 填好 `Panel` / `Hover` / `Card` / `Scroll`，用 `Get-HoverGeometry.ps1` 反复微调；
4. `Invoke-HoverScan.ps1 -PresetPath .\mypreset.psd1 -OutFile .\out.txt`。

## 几个关键实现点

**DPI**：PowerShell 宿主默认是 DPI 虚拟化的，2560×1600 的屏幕会报成 1721×1033。所有矩形
都在 `SetProcessDPIAware()` 之后测量，这样 `GetWindowRect`、`CopyFromScreen` 和 OCR 词框
才在同一坐标系里。

**悬停**：`SetCursorPos` 和单次绝对 `mouse_event` 都**不会**触发 Chromium 的 hover，它需要
连续的移动轨迹。模块会走一小段抖动路径进入该行，再等约 650 ms 让卡片动画结束。

**滚动**：滚轮必须落在列表上，而不是旁边的聊天区；滚动之后各行的 *y* 坐标不变，所以进度
只能按「新读到的值」统计，不能靠几何位置判断。

**OCR**：易混字符会归一化（`S→5`、`O/D→0`、`I/L→1`、`B→8`、`Z→2`、`G→6`、`T→7`），
但 `Q` 故意不动——否则 `QQ` 前缀会变成 `99`，正则全废。卡片要裁成窄条并放大再识别；
对 2560×1600 整屏直接 OCR 会读错位数。

**校验**：`-Fast` 只取第一次成功读数；不加则每行读两次，只有一致才采纳，慢但干净。

## 准确率（实话实说）

从截图读 10 位数字是概率性的。仓库自带的实测：222 人的群一轮读出 227 个唯一值——里面
既有真实的老号（6~8 位号确实存在），也有列表里残留的退群成员，还混着少量 OCR 误读。
所以要交叉验证：

- 扫两轮取交集；
- 位数异常的号，去成员面板搜索框里手工核对；
- 保留 `.log`：它逐页记录每一次读数，事后追责成本很低。

## 限制

- **它占用真实光标和前台窗口**。Chromium 忽略合成悬停消息，因此不存在真正的后台模式：
  运行期间别动鼠标，也别以为能在别的窗口打字——按键会落到当前焦点窗口。
- 坐标与软件版本、布局强绑定；界面改版就要重新校准。
- 单显示器 100%~200% 缩放均可；混合 DPI 的多屏可能坐标偏移。
- 慢是设计使然：带校验约每行 0.9 秒。
- 仅 Windows。

## 隐私与合规

本工具只读取你屏幕上原本就显示出来的像素，不登录、不解密数据库、不发送任何网络请求。

导出的号码属于个人信息：只在你被授权的群里采集，不要公开或转售，遵守平台条款与当地
法律。仓库里的示例输出是编造的假数据。

## 许可证

MIT，见 [LICENSE](LICENSE)。
