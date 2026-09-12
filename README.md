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
| `MacPet/` | Swift 源码、默认立绘、构建脚本 |

当前专注由 MacPet 自己记录。右键可开始/停止专注、完成一个番茄、喂番茄、调整大小与眼睛高光。

## 许可

本项目仅供**个人、非商业使用**，禁止商用。详见 [LICENSE](LICENSE)。

默认宠物形象根据哔哩哔哩 UP 主 [初风y不行](https://space.bilibili.com/651923923/) 的 Q 版形象改编，使用时须保留署名。
