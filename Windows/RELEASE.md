# MacPet Windows 1.2.2

Windows 原生适配版，以 macOS v1.2.2 为基准，保留全部 9 个动画表情、鹦鹉图标和现有桌宠功能。macOS 版保持不变。

## 下载

- 普通 Intel / AMD 64 位电脑：`MacPet-1.2.2-windows-x64.zip`
- Windows on ARM：`MacPet-1.2.2-windows-arm64.zip`

完整解压后双击 `MacPet.exe`，无需安装 .NET 或开发工具。未进行商业代码签名，首次运行可能出现未知发布者提示，请核对下载来源。

## 功能

透明悬浮、拖动/缩放、右键切换/导入/单项和批量删除、动画速度、省电模式、原版形象高光编辑、单击 ChatGPT 均保留。无专注或喂番茄功能。

系统托盘用于隐藏后恢复；再次运行 EXE 也会显示已有实例。设置存储在 `%LOCALAPPDATA%\MacPet`，删除副本进回收站，原素材不受影响。

Windows x64 在 Windows runner 中执行编译、资源与设置自检、真实分层窗口呈现和换帧检查；ARM64 为交叉发布，尚未做 ARM64 真机验证。

个人非商业使用，保留原版形象作者「初风y不行」署名，详见安装包内 LICENSE。
