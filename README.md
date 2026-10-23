# MacPet

桌面宠物，提供 macOS 版和 Windows 原生适配版，支持透明悬浮、GIF 动画表情、省电播放和表情管理。

## 两种侧重点，按需选择

- **经典陪伴版 1.2.2**：侧重安静的桌面陪伴，支持 macOS / Windows，保留原有下载。
- **互动番外版 2.0 Beta（目前仅 Mac）**：侧重打字互动。在右键「键盘互动」里自选任意表情；打字时临时切换，停键 **0.5 秒**后恢复原表情。这是并行的衍生版本，不替代经典版。

[下载 Mac 互动版](https://github.com/shumini20091227-cpu/macpet/releases/tag/interactive-v2.0.0-beta.1) · [互动版说明](Interactive/README-互动版.md)

互动版使用独立应用身份和数据目录，可与经典版并存；内置相同 9 个 GIF，额外导入的表情需另行导入。首次启用键盘联动需允许 macOS「输入监控」权限；只检测按键活动，不记录输入内容。系统安全输入状态可能暂停联动。

## Windows 版

Windows 适配保持 macOS v1.2.2 的全部现有功能，共用同一套 9 个表情及鹦鹉图标，macOS 版保持不变。
下载入口：[Windows Release](https://github.com/shumini20091227-cpu/macpet/releases/tag/windows-v1.2.2)。选择 x64（普通 Intel/AMD 电脑）或 ARM64，完整解压后双击 `MacPet.exe`，无需另装运行环境。
隐藏后双击系统托盘中的鹦鹉图标恢复；详细说明和验证范围见 [Windows/README.md](Windows/README.md)。

## macOS 下载与安装

在 [GitHub Releases](https://github.com/shumini20091227-cpu/macpet/releases) 下载最新的 `MacPet-1.2.2-universal.zip`。

1. 解压压缩包。
2. 将 `MacPet.app` 拖入「应用程序」。
3. 双击启动。macOS 14 及以上，支持 Apple Silicon 和 Intel Mac，无需安装 Swift 或 Xcode。

此版本没有 Developer ID 签名和 Apple 公证，首次打开可能被 Gatekeeper 拦截；请先核对下载来源。系统可能提供右键「打开」，或需要在「系统设置 → 隐私与安全性」允许打开。能否直接启动取决于系统安全设置；不要关闭整个系统的安全保护。

升级前请退出旧版，再替换应用。已导入表情、删除状态及偏好保留在本机；不会覆盖现有同 ID 表情。

## v1.2.2

新增透明鹦鹉应用图标，Finder、Dock 和安装后的应用均使用该图标。

移除专注计时、番茄奖励和投喂功能及其相关菜单、动画与提示。专注于桌面陪伴与动画表情。

- 内置本次发布的全部 9 个 GIF 表情，首次启动自动加入列表。
- 右键「切换表情」选择表情；支持一次导入多个 GIF / PNG。
- 表情右侧的「×」可删除；「批量删除…」支持勾选、全选、取消全选和数量提示。
- 动画默认半速播放；右键「动画速度」可选 0.25× / 0.5× / 0.75× / 1×。
- 保留 GIF 透明背景及原始帧序，速度设置和表情选择在重启后保留。
- 修复“减少动态效果”导致 GIF 静止的问题。

完整记录见 [CHANGELOG.md](CHANGELOG.md)，发布说明见 [v1.2.2](docs/releases/v1.2.2.md)。

## 使用

- 拖动宠物：移动位置。
- 单击：打开 ChatGPT 网页。
- 右键：切换/导入/删除表情、调整速度、调整大小、隐藏或退出。
- 动画表情不叠加原版高光和呼吸摇摆；可切回「原版形象」。

默认启用右键菜单中的「省电模式（推荐）」，动画最多 12 次/秒更新，系统低电量模式下最多 6 次/秒；关闭省电模式可恢复最多 30 次/秒。按 GIF 下一帧时间安排单次计时器，同一帧不重复刷新，也不每帧重建根视图。静态 PNG 不启用动画计时器。

隐藏、被完全遮挡、锁屏或屏幕休眠时停止驱动帧。导入限制：最多 1000 帧、单帧最大 4096×4096、解码 RGBA 总量不超过 256 MB。

## 本次内置表情

- 10W_PNGTuber 加载中_2026-10-13-08-59-36
- 10W_记录 1_2026-10-13-08-58-56
- 10W_PNGTuber 闲置_2026-10-13-08-59-29
- 10W_驾驶_2026-10-13-08-53-38
- 10W_TrashTuber 闲置_2026-10-13-09-04-06
- 10W_PNGTuber 说话_2026-10-13-08-59-39
- 10W_礼物 2_2026-10-13-08-55-29
- 10W_加载(睡觉)_2026-10-13-08-57-19
- 10W_主意_2026-10-13-08-56-11

表情复制到 `~/Library/Application Support/MacPet/Expressions/`。删除只将应用管理的副本移入废纸篓，不影响导入来源。内置表情首次加入后，用户删除的内容不会在重启时自动恢复。原版形象保留作为兜底。

发行包仅包含应用与表情资源，不包含作者的窗口位置或个人偏好。

## 从源码构建

需要 macOS 14+、Swift 6 和 Command Line Tools。

```bash
cd MacPet
./scripts/test.sh
./scripts/make_app.sh
```

构建通用版并生成 ZIP：

```bash
./scripts/package_release.sh
```

如果 Swift 6.4 默认构建引擎报模块缓存错误，可传 `--build-system native`，例如 `./scripts/make_app.sh --build-system native`。该选项是当前工具链兼容方案。

发行包验证：`MacPet.app/Contents/MacOS/MacPet --verify-release`，使用隔离的临时目录和偏好，不修改现有表情。

## 许可与署名

仅供个人、非商业使用，禁止商用，详见 [LICENSE](LICENSE)。

原版形象根据哔哩哔哩 UP 主 [初风y不行](https://space.bilibili.com/651923923/) 的 Q 版形象改编,其余内置形象以及其表情来自哔哩哔哩up主[午夜Mid是150w的鹦鹉](本人），公开使用时必须保留署名。新增动画由项目维护者提供；本项目许可不额外授予第三方角色或素材的商用权利。
