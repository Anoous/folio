# 大资源管理与恢复

旧工程字体和 QA 录屏只保留本地副本，不再随当前 Git 版本跟踪。它们已加入根目录 `.gitignore`；现有本地文件未删除。历史提交仍包含这些资源，因此本次整理不会缩小已有 Git 历史或完整 clone 的体积。

## 保留在 Git 中

- 当前 Demo 构建必需的字体、Asset Catalog 图片与授权文件。
- 现有设计原型 PNG：文档直接引用这些图片，暂时保留，避免丢失可查看的设计证据。后续可单独生成压缩预览，再迁移原图；本次未压缩或降低图片质量。
- 源代码、项目配置、依赖锁文件和文档。

## 不再跟踪

- 归档工程的三个 LXGWWenKaiTC 字体。运行历史工程前需恢复；当前 `ui-demo` 不依赖它们。
- `ui-demo/QA/Motion/` 中的 MP4/MOV/WebM 录屏。以后新增录屏先保留本地；如需团队访问，上传到选定附件存储后在 QA 文档登记链接，不直接加入 Git。

本次未配置外部存储，也未改写或强推历史。不要用全局 `*.ttf` 或 `*.png` 忽略规则隐藏 App 必需资源。

## 恢复现有资源

已推送的归档提交为 `2ada69001ed070d6722e43b0b0c33325ba88baed`。可在 [GitHub 历史目录](https://github.com/Anoous/folio/tree/2ada69001ed070d6722e43b0b0c33325ba88baed) 找到对应文件并下载，或在仓库根目录执行：

```bash
# 将 asset_path 换成下表所需文件；仅在该文件不存在时恢复。
asset_path='ui-demo/QA/Motion/highlight-note-search-export.mp4'
if [ ! -e "$asset_path" ]; then
  mkdir -p "$(dirname "$asset_path")"
  git show '2ada69001ed070d6722e43b0b0c33325ba88baed:'"$asset_path" > "$asset_path"
fi
```

浅克隆若不包含该提交，先获取 `git fetch origin 2ada69001ed070d6722e43b0b0c33325ba88baed`。下载后使用 `shasum -a 256` 与下表校验。本次已逐字节核对所有本地文件与历史 blob 一致。

| 相对路径 | MiB | SHA-256 |
|---|---:|---|
| `archive/legacy-code-2026-07-26/ios/Folio/Resources/Fonts/LXGWWenKaiTC-Light.ttf` | 14.89 | `dca5b82a847c7a419bfd0a9ddb97a90fa198848ef6c3f15ab72b6909738cb820` |
| `archive/legacy-code-2026-07-26/ios/Folio/Resources/Fonts/LXGWWenKaiTC-Medium.ttf` | 14.33 | `94ca2870022fb8e4f90e2887524603690598142d17b620dfae318f1818ba8e17` |
| `archive/legacy-code-2026-07-26/ios/Folio/Resources/Fonts/LXGWWenKaiTC-Regular.ttf` | 14.56 | `b1a0795862c1415bf3f393ea50b2a4ea6275012cf5bad3f94feeb1222f555731` |
| `ui-demo/QA/Motion/article-ai-ask-interaction.mp4` | 1.31 | `a53ba6ffe78d0ac729fb8016031b4ba310807616a4261daa71decd0bcd7fee3c` |
| `ui-demo/QA/Motion/article-inline-switch.mp4` | 0.88 | `c73eab99b0491c99a35907d878403acdd9da3de4d7da6741c0c5fd45bddd4951` |
| `ui-demo/QA/Motion/highlight-note-search-export.mp4` | 4.99 | `004784cd0932b17f23cb73cadb421bba6518170a447994dbd17e0dc2eaffe541` |
| `ui-demo/QA/Motion/liquid-toolbar-demo.mp4` | 0.89 | `7e595084fbde80ff2aa731ea6b7c46dd6ce1541b5406eab26270faf0b81cdb01` |
| `ui-demo/QA/Motion/reliable-capture-foundations.mp4` | 0.49 | `9e8d1e6adaefe15e618db07d7402a1631e579f9b89c2615be9709154de1b22a3` |
