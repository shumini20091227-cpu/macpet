# MacPet Windows

以 macOS v1.2.2 为功能基准的 Windows 原生版本。macOS 源码和安装包保持不变。

## 保留的功能

- 同一套 9 个 GIF 和鹦鹉图标；透明悬浮、透明区域穿透、不抢输入焦点、拖动与高 DPI 缩放。
- 单击打开 ChatGPT；右键切换、批量导入 GIF / PNG、右侧 × 删除和批量删除。
- 0.25× / 0.5× / 0.75× / 1×，默认半速，切换速度保持播放进度。
- 默认省电：最多 12 次/秒更新；系统节能状态下降为最多 6 次/秒，按 GIF 帧时长安排单次计时器。
- 隐藏、锁屏、挂起、显示器关闭、完全遮挡时停帧；静态 PNG 不创建动画计时器。
- 100–560 的大小范围、原版形象呼吸/视线反馈及高光编辑、自定义 PNG 与恢复原版。
- 已选表情、速度、大小、高光、隐藏状态和位置在重启后保留。
- 内置表情首次启动自动加入，删除后不复活；删除副本移入回收站，原素材不受影响。
- 不含已经移除的专注、番茄奖励或喂食功能。

Windows 使用系统托盘作为隐藏后的恢复入口，替代 macOS Dock。双击托盘或再次运行 EXE 恢复；同一用户只运行一个实例。

## 构建与打包

使用 Microsoft .NET 10 SDK，在 Windows PowerShell 中运行：

```powershell
./Windows/scripts/package.ps1 -Runtime win-x64
./Windows/scripts/package.ps1 -Runtime win-arm64
```

发行包为自包含 ZIP，用户完整解压后双击 `MacPet.exe`，不需要另装 .NET。全部表情和图标嵌入程序，从同一份 macOS 素材链接构建，避免两套素材漂移。

macOS/Linux 可执行 `dotnet build Windows/MacPet.Windows.csproj -c Release` 检查代码，无法运行 Windows 图形程序。GitHub Actions 的 `Build Windows` 在 Windows runner 上编译、执行隔离的资源/设置测试和真实窗口启动检查，再生成 x64/ARM64 ZIP。

Windows x64 有实际 Windows runner 启动与图形 API 检查；ARM64 在 x64 runner 交叉发布，未宣称经过 ARM64 真机验证。

## 自检

```powershell
Start-Process ./MacPet.exe -ArgumentList '--verify-release --report verify.json' -Wait
Start-Process ./MacPet.exe -ArgumentList '--smoke-test --report smoke.json' -Wait
```

测试使用 UUID 临时目录，不读取或删除用户现有表情。结果包括全部 9 个 GIF 的解码、透明背景、循环/帧调度、设置、同名导入、批量删除与删除后不复活，以及 Win32 分层窗口呈现、换帧和隐藏停帧。窗口检查会输出 `windows-preview.png`。

## 平台实现

- .NET Windows Forms + Win32 `UpdateLayeredWindow`，不嵌入浏览器引擎。
- 事件驱动处理电源、显示状态、锁屏和窗口遮挡，不为这些状态持续轮询。
- 每次选中表情预解码一次，播放时只更新需要显示的帧；最多 1000 帧、4096×4096、解码后 256 MB。
- 数据目录 `%LOCALAPPDATA%\MacPet`，使用原子替换保存 JSON；不包含遥测或后台网络请求。

许可及角色署名沿用根目录 LICENSE。
