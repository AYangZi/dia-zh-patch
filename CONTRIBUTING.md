# 参与贡献

欢迎修正文案、补充兼容 Build、改进测试和文档。

## 开发要求

- macOS 14+、Apple Silicon 或可交叉编译 arm64 的 macOS Runner。
- Xcode Command Line Tools。
- Node.js 18+。

提交前运行：

```zsh
./tests/run-tests.zsh
```

## 翻译与菜单

所有译文只维护在 `translations/zh-Hans.strings`。菜单范围由
`translations/menu-keys.txt` 限定，Objective-C 不得加入第二份译文表。新增菜单键
必须同时补测试，确认不会改写书签、历史记录、窗口名或网页标题。

## 新 Build

完整模式的新 Build 必须提供严格的文件清单、原版/补丁版 SHA-256、逐文件命中数
和真实设备验收，然后追加到 `manifests/index.json`。不要放宽旧规则来兼容新文件。
没有完整基线的 Build 只能使用核心模式。

清单可以用 `scripts/derive-webui-manifest.mjs` 从官方应用和统一词表推导：

```zsh
node scripts/derive-webui-manifest.mjs --app /Applications/Dia.app --version <版本> --build <Build>
node scripts/derive-webui-manifest.mjs --app /Applications/Dia.app --version <版本> --build <Build> --write
node scripts/derive-webui-manifest.mjs --app /Applications/Dia.app --check manifests/<版本>-<Build>.json
```

追加 Build 之前必须用官方应用跑一遍只读审计，确认命中数与清单完全一致：

```zsh
osascript -l JavaScript scripts/patch-webui.jxa audit /Applications/Dia.app manifests/<版本>-<Build>.json /tmp/audit.json
```

推导只覆盖统一词表里已有的译文；新增文案要先补 `translations/zh-Hans.strings`，
且不要在 `translations/zh-Hans.strings` 之外再维护第二份译文表。

## 禁止提交

不要提交 Dia.app、官方二进制或官方 JS/HTML、预编译 `.dylib`、Release ZIP、用户
数据、备份、状态目录、审计报告、账号信息或本机绝对路径。

Pull Request 请说明影响的覆盖模式、验证命令、恢复验证和已知限制。
