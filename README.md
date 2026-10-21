# Dia 简体中文补丁

[English](README.en.md) · [更新记录](CHANGELOG.md) · [安全说明](SECURITY.md) ·
[AI Agent 提示词](docs/AI_AGENT_PROMPT.md)

面向 macOS Apple Silicon 的非官方 Dia 浏览器简体中文补丁。它会先验证官方
应用和资源、创建完整备份，再汉化 Chromium 界面、原生界面和菜单；对已验证的
Build 额外执行严格限定的 WebUI 替换。

当前版本为 `v0.2.0-rc.1` 预发布版。完整模式已验证 Dia `1.41.1`（Build `84131`）
与 `1.53.0`（Build `88760`）；核心模式另已实测 Dia `1.44.1`（Build `85212`）。
原生设置窗口（账户 / 标签页 / 隐私 / 个人资料 / 应用 / 技能 / 账单 / 快捷键 /
高级）已逐面板中文化。系统要求 macOS 14 或更高版本。

> 本项目与 The Browser Company、Dia 或 Atlassian 没有隶属或授权关系。
> 补丁会把应用改为本机 ad-hoc 签名；请理解风险并保留补丁创建的官方备份。

## 在新电脑上安装（刚装完 Dia Browser）

适用场景：Mac 上刚装好 Dia，想让浏览器界面、右键菜单和设置面板变成简体中文。

前置条件：macOS 14+、Apple Silicon、Dia 已从官方渠道安装并至少启动过一次。
补丁只改应用包本身，不碰账号、书签、密码、标签页和浏览记录。

### 1. 先完全退出 Dia

⌘Q 退出（不是关窗口），终端确认：

```zsh
pgrep -fl "/Applications/Dia.app/Contents/MacOS/Dia"   # 没有输出即已退出
```

### 2. 选一种安装方式

**方式 A：下载 Release 压缩包（推荐，普通用户选这个）**

```zsh
cd ~/Downloads
curl -LO https://github.com/framecy/dia-zh-patch/releases/download/v0.2.0-rc.1/dia-zh-patch-0.2.0-rc.1-macos-arm64.zip
curl -LO https://github.com/framecy/dia-zh-patch/releases/download/v0.2.0-rc.1/dia-zh-patch-0.2.0-rc.1-macos-arm64.zip.sha256
shasum -a 256 -c dia-zh-patch-0.2.0-rc.1-macos-arm64.zip.sha256
unzip dia-zh-patch-0.2.0-rc.1-macos-arm64.zip
cd dia-zh-patch-0.2.0-rc.1-macos-arm64
./dia-zh.command audit     # 只读体检：签名、结构、覆盖模式
./dia-zh.command apply     # 备份 → 安装 → 签名 → 验证
```

也可以直接双击 `dia-zh.command` 选择"安装补丁"。若被 Gatekeeper 拦，右键 →
打开，或到 系统设置 → 隐私与安全性 →"仍要打开"；仍然不行就去掉隔离标记：

```zsh
xattr -d com.apple.quarantine dia-zh.command
```

**方式 B：从源码安装（想改译文、或需要自己打包时用）**

```zsh
git clone https://github.com/framecy/dia-zh-patch.git
cd dia-zh-patch
./scripts/build-menu.zsh     # 需要 Xcode Command Line Tools，产出 lib/DiaZhMenu.dylib
./dia-zh.command apply
```

Release 压缩包里的 arm64 菜单动态库，就是 GitHub Actions 用同一条命令构建的。
想自己打一个包：`./scripts/package-release.zsh dist`。

### 3. 装完 30 秒自检

| 检查 | 期望结果 |
|---|---|
| `./dia-zh.command status` | 补丁状态 `applied`；覆盖级别 `full`（已验证 Build）或 `core`（未验证 Build） |
| 菜单栏 | 显示为“Dia / 文件 / 编辑 / 显示 / 标签页 / 书签 / 历史记录 / 扩展程序 / 窗口 / 帮助” |
| ⌘, 打开设置 | 账户、标签页、隐私、应用、技能、账单、快捷键、高级等面板为中文 |
| 任意网页右上角 ⋯ | 菜单为中文 |

### 4. 换电脑时不要做的事

- **不要拷贝旧机器上打过补丁的 `Dia.app`**：它带着旧 Build 和本机 ad-hoc 签名。新机器装官方版再打补丁。
- **不要拷贝 `~/Library/Application Support/DiaZhPatch/`**：里面是旧机器的备份和状态，会和官方签名校验冲突。
- 书签、密码、标签页本来就在 `~/Library/Application Support/Dia`，随账号同步，不需要手动搬。

### 5. 官方更新之后

Dia 的自动更新不会关闭，它会用官方包覆盖补丁。重跑一次即可：

```zsh
cd ~/Downloads/dia-zh-patch-0.2.0-rc.1-macos-arm64   # 或你的源码目录
./dia-zh.command apply
```

未在清单里的新 Build 会自动降级为 `core` 模式（Chromium 界面 + 统一词表 + 菜单
汉化），不会套用旧版 WebUI 替换规则。想把新 Build 升级为 `full`，见文末
"新增一个 Build"。

## 重新签名与登录态（重要）

补丁会把 Dia 改成本机 ad-hoc 签名。**在少数情况下，Dia 会因此认不出本地保存的
登录凭据**，表现为重新打开时出现「What's your email?」引导页。

这不是数据丢失：历史记录、书签、上次会话的标签页都还在
`~/Library/Application Support/Dia`（实测：历史 4391 条、书签 661 个、54 个标签页
URL 全部可读）。处理办法是用原邮箱重新登录一次，spaces 和标签页会随之回来；如果
你导出过 Dia 的 Recovery Kit，也可以用它解密本地数据。

三条预防措施：

1. 执行 `apply` 或 `restore` 之前，先手动 ⌘Q **完全退出 Dia**，不要让它边跑边改；
2. 打完补丁先确认仍是登录态（侧栏 spaces 在、没有出现邮箱引导页），再用；
3. 数据重要时先留一份副本：`ditto ~/Library/Application\ Support/Dia ~/Dia-data-snapshot`，
   或依赖 Time Machine 本地快照。

## 命令

| 命令 | 作用 |
|---|---|
| `apply` | 备份、安装、签名并验证补丁 |
| `audit` | 只读检查签名、结构、覆盖模式和资源 |
| `status` | 显示版本、签名、状态 schema、备份与覆盖模式 |
| `restore` | 恢复本次安装前的官方版本 |

默认应用路径为 `/Applications/Dia.app`。测试副本可设置 `DIA_APP_PATH`，备份和
状态默认位于 `~/Library/Application Support/DiaZhPatch/`。

## 自动兼容模式

补丁自动选择以下覆盖级别，并在 `audit` 与 `status` 中明确显示：

- `full`：已验证的 `1.41.1 (84131)` 与 `1.53.0 (88760)`，启用 Chromium、
  统一词表、菜单动态库和 WebUI 精确替换。
- `core`：其他结构兼容的官方 Build，只启用 Chromium、统一词表和菜单汉化，
  不套用旧 WebUI 规则。`1.44.1 (85212)` 已完成本机核心模式验收。
- `incompatible`：Bundle ID、官方签名身份、关键资源或架构不兼容，写入前拒绝。

已知 Build 也可以主动使用核心模式：

```zsh
DIA_ZH_MODE=core ./dia-zh.command apply
```

项目刻意不提供"强制对未知 Build 执行完整替换"的选项。

## 覆盖与边界

补丁包含四层：

1. 使用 Dia 自带的 `zh_CN.lproj/locale.pak` 汉化 Chromium 界面。
2. 向主程序及 Dia 资源 Bundle 注入统一的 `zh-Hans.strings`，覆盖原生设置窗口
   与应用内文案。
3. 通过源码构建的 arm64 动态库汉化 macOS 静态和动态菜单。
4. 仅对清单已验证的 Build 执行文件级 WebUI 精确替换。

当前统一词表有 513 个键，其中菜单白名单 156 个。菜单翻译器会保护书签、历史、
窗口名和网页标题等用户内容；普通网页、AI 实时回答、第三方扩展、prompt、agent
spec 和服务端临时文案不在范围内。

已知未覆盖（实测确认，非译文问题）：侧栏与页头的 `Profiles`、`Advanced` 两个
标题是 verbatim 文案，不查字符串表；`Chat events`、`Daily report` 在官方包内
不存在，应为运行时/服务端下发。

仓库只保存补丁源码、翻译和哈希清单。它不包含 Dia.app、官方 JS/HTML、用户数据、
备份、审计报告或官方二进制。预编译 `DiaZhMenu.dylib` 只由 GitHub Actions 放入
Release ZIP。

## AI Agent 一句话提示词

给 AI Agent 直接粘贴这一句即可完成配置（`<版本>`、`<Build号>` 替换成实际值）：

```
在 macOS 上把刚安装好的 Dia 浏览器汉化为简体中文：克隆 https://github.com/framecy/dia-zh-patch 并进入仓库，先执行 ./scripts/build-menu.zsh 生成 arm64 菜单动态库（需要 Xcode Command Line Tools），再执行 ./dia-zh.command apply；完成后用 ./dia-zh.command status 确认“补丁状态=applied”，并核对菜单栏与 ⌘, 设置窗口是否已中文化；如果 status 显示覆盖级别是 core 而不是 full，说明当前 Dia Build 尚未验证，先执行 node scripts/derive-webui-manifest.mjs --app /Applications/Dia.app --version <版本> --build <Build号> --write 生成该 Build 的 WebUI 清单、把 manifests/index.json 加上该条目、跑 ./tests/run-tests.zsh 全部通过后再重新 apply；任何一步失败或出现 Code 6 报错，立即执行 ./dia-zh.command restore 恢复官方版本并如实汇报，不要强行继续。
```

变量替换、极简版和验收清单见 [docs/AI_AGENT_PROMPT.md](docs/AI_AGENT_PROMPT.md)。

## 签名、Code 6 与恢复

安装后应用使用统一的 ad-hoc 签名。签名器会读取原组件权限，移除 ad-hoc 无法
保留的 Team ID、application identifier 和 keychain 字段，保留 Renderer/GPU
的 JIT 权限，并为相关组件加入 Library Validation 兼容设置。签名顺序为内部
Mach-O、嵌套 Bundle、Framework，最后 Dia.app，并执行严格深度验证。

若出现 "Something’s not right · Code 6"，请依次运行：

```zsh
./dia-zh.command status
./dia-zh.command audit
./dia-zh.command restore
```

不要手工混签 ArcCore 与 Helper。若 `audit` 报签名身份不一致，先恢复官方版本再
重新安装，并在 Issue 中附上已脱敏的命令输出，切勿上传用户数据或完整应用包。

安装中任一步失败都会尝试恢复官方备份。`restore` 会验证官方 Team ID 和严格
签名；如果 Dia 已升级到不同 Build，它会拒绝用旧备份覆盖。

## 官方自动更新

补丁不会关闭 Dia 的自动更新。官方更新通常会替换已修改的应用包；再次运行
`status` 或 `apply` 时，若检测到有效官方签名和新 Build，旧状态会被标记为
`superseded`，新 Build 最多进入 `core` 模式。旧备份永远不会覆盖更高 Build。

## 开发与验证

本机需要 Xcode Command Line Tools 和 Node.js 18+：

```zsh
./tests/run-tests.zsh
./scripts/build-menu.zsh
```

测试覆盖词表、占位符、菜单冲突、manifest 索引、全部已知 Build 的 WebUI 规则与
文件哈希、Zsh/JXA/plist、arm64 编译，以及嵌套签名/JIT Fixture。发布验收与已知
基线见 [QA_CHECKLIST.md](docs/QA_CHECKLIST.md) 和
[BUILD_PROVENANCE.md](docs/BUILD_PROVENANCE.md)。

新增一个 Build 时，先用官方应用推导清单，再人工复核规则与译文：

```zsh
node scripts/derive-webui-manifest.mjs --app /Applications/Dia.app --version 1.53.0 --build 88760
node scripts/derive-webui-manifest.mjs --app /Applications/Dia.app --version 1.53.0 --build 88760 --write
node scripts/derive-webui-manifest.mjs --app /Applications/Dia.app --check manifests/1.53.0-88760.json
```

`--write` 会同时写出 `manifests/<版本>-<Build>.json` 与两份 SHA-256 清单；还要
把新条目登记到 `manifests/index.json`，然后跑 `./tests/run-tests.zsh`，通过后
提交。推导脚本只从 `translations/zh-Hans.strings` 取译文，命中次数对不上时会在
`apply` 前被 `patch-webui.jxa` 拦住，不会静默改坏文件。

## 许可证

[MIT](LICENSE)，版权署名为 `dia-zh-patch contributors`。
