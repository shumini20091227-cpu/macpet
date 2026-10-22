# 发布 v1.2.0

1. 在仓库根目录提交本次源码、9 个 GIF、README、CHANGELOG 和本目录中的发布说明。
2. 运行 `cd MacPet && ./scripts/package_release.sh --build-system native`。
3. 如有 Developer ID，设置 `CODE_SIGN_IDENTITY` 并按 Apple 流程进行公证；默认本地 ad-hoc 签名不等于 Developer ID 或 Apple 公证。
4. 将提交推送到 GitHub，再从相同提交创建 `v1.2.0` 标签与 Release。
5. Release 标题：`MacPet 1.2.0 · 动画表情版`；正文使用 `docs/releases/v1.2.0.md`。
6. 上传 `dist/MacPet-1.2.0-universal.zip` 与 `dist/SHA256SUMS.txt`。

使用 GitHub CLI（需要已登录且有仓库写入权限）：

```bash
gh release create v1.2.0 \
  --repo shumini20091227-cpu/macpet \
  --target main \
  --title 'MacPet 1.2.0 · 动画表情版' \
  --notes-file docs/releases/v1.2.0.md \
  dist/MacPet-1.2.0-universal.zip dist/SHA256SUMS.txt
```

执行前确认 `main` 已包含本次改动，避免 Release 指向旧代码。发布前在隔离目录执行 `MacPet.app/Contents/MacOS/MacPet --verify-release`，确认 9 项表情和首次安装流程正常。
