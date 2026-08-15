# 1.41.1（84131）资源基线

本清单来自 Dia 官方 Sparkle 更新源提供的：

```text
https://releases.diabrowser.com/release/Dia-1.41.1-84131.zip
```

归档长度为 `779397717` bytes，共 `2861` 个 ZIP 条目。已从官方归档直接
解压四个 WebUI 资源根中的全部 180 个运行时 JS/HTML（解压后共
`6940236` bytes），生成原版和补丁版的逐文件 SHA-256 清单。

补丁器同时核对版本号、关键文件长度、WebUI 文件数量、180 个原始
SHA-256、87 条规则的逐文件精确命中数，以及写入后的 180 个 SHA-256。

## 关键文件

| 相对路径 | 原始长度 | ZIP CRC32 |
|---|---:|---:|
| `Contents/MacOS/Dia` | 118037776 | 779517e3 |
| `Contents/Info.plist` | 6792 | abedd0af |
| `Contents/Frameworks/ArcCore.framework/Versions/A/Resources/en.lproj/locale.pak` | 587145 | 5cb772f4 |
| `Contents/Frameworks/ArcCore.framework/Versions/A/Resources/zh_CN.lproj/locale.pak` | 591310 | 0cae2f01 |
| `Contents/Resources/web-chat-resources/dist/index.html` | 849 | f8547638 |
| `Contents/Resources/web-chat-resources/dist/background.js` | 207406 | 49ba3c70 |
| `Contents/Resources/web-chat-resources/dist/manifest.json` | 1059 | 569a3274 |
| `Contents/Resources/BoostBrowser_WelcomePostcardBundle.bundle/Contents/Resources/site/index.html` | 89399 | f3074053 |
| `Contents/Resources/BoostBrowser_MorningBriefTeaserBundle.bundle/Contents/Resources/site/index.html` | 50330 | 26537335 |

## WebUI 文本文件计数

计数只包含运行时 `.js` 和 `.html`，排除 source map、agent spec 和 prompt。

| 资源根目录 | 文件数 |
|---|---:|
| `web-chat-resources/dist` | 98 |
| `BoostBrowser_HomeWebBundle.bundle/.../Bundle` | 79 |
| `BoostBrowser_WelcomePostcardBundle.bundle/.../site` | 1 |
| `BoostBrowser_MorningBriefTeaserBundle.bundle/.../site` | 2 |

这些值必须随支持版本更新，不能把旧值放宽后继续套用。

## 身份与签名基线

- Bundle ID：`company.thebrowser.dia`
- Developer Team ID：`S6N382Y83G`
- Developer ID 名称：`The Browser Company of New York Inc.`

补丁器在写入前同时验证严格签名、Bundle ID、Team ID 和 Developer ID
发布者。签名身份可与公开的
[Dia code requirement](https://appcatalog.cloud/apps/dia) 交叉核对。

公开仓库不保存上述官方归档或其中任何文件；只保存由基线生成的长度、命中数和
SHA-256 清单。

## WebUI 精确清单

- 原版 SHA-256：`manifests/1.41.1-84131.webui-original.sha256`
- 补丁版 SHA-256：`manifests/1.41.1-84131.webui-patched.sha256`
- 文件限定规则：`manifests/1.41.1-84131.json`
- 规则数：87
- 已验证替换位置：215

匹配范围只包含清单明确列出的文件。规则不会对普通网页、prompt、agent
spec、source map、测试文件、第三方扩展或未列入清单的任意文本做全局替换。

## 菜单与签名构建

- 菜单源码：`native/DiaZhMenu.m`
- 唯一译文来源：`translations/zh-Hans.strings`
- 菜单白名单：`translations/menu-keys.txt`
- arm64 构建入口：`scripts/build-menu.zsh`
- 嵌套签名入口：`scripts/sign-app.zsh`

Git 历史不保存预编译动态库。Release 工作流在 macOS Runner 上从源码构建，签名
Fixture 验证 Renderer/GPU 的 JIT 权限与 Library Validation 设置，然后把产物放入
Release ZIP。
