# MacPet

macOS 桌面宠物：透明常驻窗口、专注、投喂番茄、点击打开 ChatGPT网页版。

设计规格见 [MacBook_桌面宠物开发文档_v1.0.md](MacBook_桌面宠物开发文档_v1.0.md)。

## 要求

- macOS 14+
- Swift 6 / SwiftPM（Command Line Tools 即可，不必装完整 Xcode）

## 运行

```bash
cd MacPet
./scripts/run.sh
```

测试：

```bash
cd MacPet
./scripts/test.sh
```

## 仓库内容

| 路径 | 说明 |
|---|---|
| `MacBook_桌面宠物开发文档_v1.0.md` | 产品与技术规格 |
| `ChatGPT Image Sep 10, 2026, 07_10_40 PM.png` | 角色原图 |
| `MacPet/` | Swift 源码、角色透明 PNG、构建脚本 |

当前专注由 MacPet 自己记录。右键可开始/停止专注、完成一个番茄、喂番茄、调整大小与眼睛高光。
