# Dia 简体中文补丁

[English](README.en.md) · [更新记录](CHANGELOG.md) · [安全说明](SECURITY.md)

面向 macOS Apple Silicon 的非官方 Dia 浏览器简体中文补丁。它会先验证官方
应用和资源、创建完整备份，再汉化 Chromium 界面、原生界面和菜单；对已验证的
Build 额外执行严格限定的 WebUI 替换。

当前版本为 `v0.1.0-rc.2` 预发布版。完整模式仅验证过 Dia `1.41.1`
（Build `84131`）；核心模式另已实测 Dia `1.44.1`（Build `85212`）。系统要求
macOS 14 或更高版本。

> 本项目与 The Browser Company、Dia 或 Atlassian 没有隶属或授权关系。
> 补丁会把应用改为本机 ad-hoc 签名；请理解风险并保留补丁创建的官方备份。

## 下载与安装

1. 从 GitHub Releases 下载
   `dia-zh-patch-0.1.0-rc.2-macos-arm64.zip`，并核对同名 `.sha256`。
2. 解压后退出 Dia。
3. 双击 `dia-zh.command`，选择“安装补丁”。

也可以在终端执行：

```zsh
./dia-zh.command audit
./dia-zh.command apply
```

脚本提供四个稳定命令：

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

- `full`：已验证的 `1.41.1 (84131)`，启用 Chromium、统一词表、菜单动态库和
  WebUI 精确替换。
- `core`：其他结构兼容的官方 Build，只启用 Chromium、统一词表和菜单汉化，
  不套用旧 WebUI 规则。`1.44.1 (85212)` 已完成本机核心模式验收。
- `incompatible`：Bundle ID、官方签名身份、关键资源或架构不兼容，写入前拒绝。

已知 Build 也可以主动使用核心模式：

```zsh
DIA_ZH_MODE=core ./dia-zh.command apply
```

项目刻意不提供“强制对未知 Build 执行完整替换”的选项。

## 覆盖与边界

补丁包含四层：

1. 使用 Dia 自带的 `zh_CN.lproj/locale.pak` 汉化 Chromium 界面。
2. 向主程序及 Dia 资源 Bundle 注入统一的 `zh-Hans.strings`。
3. 通过源码构建的 arm64 动态库汉化 macOS 静态和动态菜单。
4. 仅对清单已验证的 Build 执行文件级 WebUI 精确替换。

当前统一词表有 408 个键，其中菜单白名单 156 个。菜单翻译器会保护书签、历史、
窗口名和网页标题等用户内容；普通网页、AI 实时回答、第三方扩展、prompt、agent
spec 和服务端临时文案不在范围内。

仓库只保存补丁源码、翻译和哈希清单。它不包含 Dia.app、官方 JS/HTML、用户数据、
备份、审计报告或官方二进制。预编译 `DiaZhMenu.dylib` 只由 GitHub Actions 放入
Release ZIP。

## 签名、Code 6 与恢复

安装后应用使用统一的 ad-hoc 签名。签名器会读取原组件权限，移除 ad-hoc 无法
保留的 Team ID、application identifier 和 keychain 字段，保留 Renderer/GPU
的 JIT 权限，并为相关组件加入 Library Validation 兼容设置。签名顺序为内部
Mach-O、嵌套 Bundle、Framework，最后 Dia.app，并执行严格深度验证。

若出现 “Something’s not right · Code 6”，请依次运行：

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

测试覆盖词表、占位符、菜单冲突、manifest 索引、87 条 WebUI 规则、180 个文件
哈希、Zsh/JXA/plist、arm64 编译，以及嵌套签名/JIT Fixture。发布验收与已知基线
见 [QA_CHECKLIST.md](docs/QA_CHECKLIST.md) 和
[BUILD_PROVENANCE.md](docs/BUILD_PROVENANCE.md)。

## 许可证

[MIT](LICENSE)，版权署名为 `dia-zh-patch contributors`。
