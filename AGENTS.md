# dia-zh-patch 协作规则

- 项目是 Dia 浏览器的非官方 macOS Apple Silicon 简体中文补丁。
- 运行 `./tests/run-tests.zsh` 验证词表、manifest、菜单、签名和 arm64 构建。
- `translations/zh-Hans.strings` 是唯一译文来源；菜单仅使用 `menu-keys.txt` 白名单。
- 已知 Build 的 WebUI 哈希和命中数必须严格关闭失败，不得放宽旧规则兼容新版本。
- 所有写入必须先通过官方签名、Bundle ID、结构与空间预检，并保留可验证备份。
- 恢复不得跨 Build 覆盖；官方更新后的旧状态必须标记为 superseded。
- 不提交 Dia.app、官方资源/二进制、用户数据、备份、报告、状态或预编译 dylib。
- 源码保持最小改动；公开文档不得包含个人账号、标签页、工作区名称或本机路径。
