# AI Agent 提示词

给 AI 编程助手（Claude Code / Cursor / Codex / DSH 等）用的 Dia 汉化配置说明。
目标是让它**一次读懂、一次做完、并且如实汇报**。

## 一句话提示词（推荐直接粘贴）

```
在 macOS 上把刚安装好的 Dia 浏览器汉化为简体中文：克隆 https://github.com/framecy/dia-zh-patch 并进入仓库，先执行 ./scripts/build-menu.zsh 生成 arm64 菜单动态库（需要 Xcode Command Line Tools），再执行 ./dia-zh.command apply；完成后用 ./dia-zh.command status 确认“补丁状态=applied”，并核对菜单栏与 ⌘, 设置窗口是否已中文化；如果 status 显示覆盖级别是 core 而不是 full，说明当前 Dia Build 尚未验证，先执行 node scripts/derive-webui-manifest.mjs --app /Applications/Dia.app --version <版本> --build <Build号> --write 生成该 Build 的 WebUI 清单、把 manifests/index.json 加上该条目、跑 ./tests/run-tests.zsh 全部通过后再重新 apply；任何一步失败或出现 Code 6 报错，立即执行 ./dia-zh.command restore 恢复官方版本并如实汇报，不要强行继续。
```

## 极简版（只需要能用的中文界面时）

```
把 Dia 浏览器汉化成简体中文：git clone https://github.com/framecy/dia-zh-patch && cd dia-zh-patch && ./scripts/build-menu.zsh && ./dia-zh.command apply && ./dia-zh.command status
```

## 变量

| 变量 | 含义 | 怎么取 |
|---|---|---|
| `<版本>` | Dia 版本号，例如 `1.53.0` | `defaults read /Applications/Dia.app/Contents/Info CFBundleShortVersionString` |
| `<Build号>` | Dia Build 号，例如 `88760` | `defaults read /Applications/Dia.app/Contents/Info CFBundleVersion` |
| `<仓库地址>` | 补丁仓库 | 默认 `https://github.com/framecy/dia-zh-patch`（上游 `AYangZi/dia-zh-patch` 只含 1.41.1 清单） |
| `<应用路径>` | Dia 位置 | 默认 `/Applications/Dia.app`；测试副本用环境变量 `DIA_APP_PATH` |

## 前置条件

```zsh
xcode-select --install        # 没有 Xcode Command Line Tools 时先装，缺它编不出菜单动态库
node --version                 # 需要 Node.js 18+（只有给新 Build 推导清单时才用得上）
```

## 验收清单

1. `./dia-zh.command status` 输出"补丁状态：applied"。
2. 覆盖级别为 `full`（已验证 Build：`1.41.1-84131`、`1.53.0-88760`）或 `core`
   （其他官方 Build，Chromium 界面 + 统一词表 + 菜单汉化，无 WebUI 替换）。
3. 菜单栏显示“文件 / 编辑 / 显示 / 标签页 / 书签 / 历史记录 / 扩展程序 / 窗口 / 帮助”。
4. `⌘,` 打开设置，账户 / 标签页 / 隐私 / 应用 / 技能 / 账单 / 快捷键 / 高级面板为中文。
5. 网页右上角 `⋯` 菜单为中文。

## 新 Build 从 core 升到 full

```zsh
# 1) 读出版本号与 Build 号
defaults read /Applications/Dia.app/Contents/Info CFBundleShortVersionString
defaults read /Applications/Dia.app/Contents/Info CFBundleVersion

# 2) 推导清单并写入仓库（需要官方 Dia.app，不能是打过补丁的副本）
node scripts/derive-webui-manifest.mjs --app /Applications/Dia.app --version <版本> --build <Build号> --write

# 3) 登记到 manifests/index.json，然后跑测试
./tests/run-tests.zsh

# 4) 重新安装
./dia-zh.command apply
```

## 故障处理

| 现象 | 处理 |
|---|---|
| `Something’s not right · Code 6` | `./dia-zh.command restore` 恢复官方版，再 `audit` 看签名一致性；不要手工混签 ArcCore 与 Helper |
| `status` 显示 `incompatible` | 官方签名身份、Bundle ID、关键资源或架构不符，写入前就会被拒绝，别绕过 |
| 双击 `dia-zh.command` 打不开 | Gatekeeper 拦截：右键打开，或 系统设置 → 隐私与安全性 →"仍要打开" |
| 缺 `lib/DiaZhMenu.dylib` | 源码安装必须先跑 `./scripts/build-menu.zsh`（Release ZIP 里已自带） |
| 官方更新后补丁失效 | 再跑一次 `./dia-zh.command apply`；旧状态会被标记 `superseded` |

## 登录态风险与恢复

补丁会 ad-hoc 重签 Dia，个别情况下 Dia 会认不出本地登录凭据，重启后出现
「What's your email?」引导页。**数据不会丢**，历史、书签、上次标签页仍在
`~/Library/Application Support/Dia`。

- 预防：执行 `apply` / `restore` 前先让用户 ⌘Q 完全退出 Dia；打完补丁核对侧栏
  spaces 是否还在。
- 恢复：用原邮箱重新登录一次即可；必要时用 Dia Recovery Kit 解密本地数据，
  或从 `ditto` 副本 / Time Machine 快照回滚整个 `Dia` 数据目录。
- 报告：如果出现引导页，先告知用户"数据未丢、需重新登录"，不要擅自删数据目录。

## 硬性约束（写给 Agent）

- 不要关闭 Dia 的自动更新。
- 不要为了"让它看起来中文"去改官方二进制里的字面量（`Profiles` / `Advanced` 这类
  verbatim 文案例外，不建议动）。
- 不要上传 `Dia.app`、用户数据、Cookie、书签、备份或审计报告到 Issue / PR。
- 不要放宽已有 Build 的哈希与命中数校验来让新版本"通过"。
- 任何一步失败，先 `restore` 再如实说明失败原因，不要连续重试超过三次。
