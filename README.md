# MacUtil · Bar

原生 macOS 菜单栏图标管理应用。macOS 14+，支持 Apple Silicon 和 Intel，无第三方运行时依赖。

当前交付：**1.0.1 / build 2 开发候选版**。下载见 [GitHub Releases](https://github.com/PanggNOTlovebean/MacUtilBar/releases)。PKG 安装到 `/Applications/MacUtilBar.app`。这是 ad-hoc 签名、未公证的预发布包，macOS 可能阻止直接打开；不属于 Developer ID 正式发行版。

1.0.1 加强窗口身份验证、未确认状态提示和诊断证据，修正系统指示器保持可见时错误回滚折叠的问题。见 [最新验证记录](docs/validation/1.0.1-validation.md)。

已实现第一期：

- 三分区、点击切换、⌥ 点击全部展开，右键设置与退出。
- 可选悬停、滚动、可录制的全局快捷键（默认 ⌃⌥B），自动收起和切换应用收起。
- 基本设置与布局页，中英文、浅色/深色外观，登录项控制。
- TOML 配置热更新、无效配置保留旧值、外部改动冲突保护。
- 分隔符顺序检查与修复、实际窗口坐标隐藏自检、刘海遮挡提示。

**1.1 图标识别/排序/搜索和 1.2 隐藏条/条件规则/间距不包含在本次发布。** 1.0 不申请辅助功能或录屏权限，不修改其他应用或全局菜单栏偏好。

## 使用

初次启动先显示全部分区。按住 ⌘ 拖图标到主图标及其紧邻空白分隔符左侧，点击主图标即可收起；拖到 `‹‹` 左侧的图标只在 ⌥ 点击时显示。保持三个分隔符顺序；异常时在布局页修复。退出应用会恢复所有图标。

默认开机启动关闭，在设置里主动开启。系统实际注册状态为准。外部 TOML 中的 `launch_at_login` 记录请求值，不在后台自动注册登录项。

配置：`~/.config/macutilbar/config.toml`；开发时可用 `MACUTILBAR_CONFIG` 指定隔离路径。支持文件生成的 TOML 子集（分组、字符串、布尔、整数和整行注释），未知字段、重复键、转义字符串及行尾注释会报错，不会覆盖原文件。

URL：`macutilbar://toggle`、`show`、`hide`、`show-all`、`settings`。

## 构建与验证

```sh
swift test
./Scripts/build.sh build/candidate
codesign --verify --deep --strict build/candidate/MacUtilBar.app
```

无需远程 SwiftPM 依赖。构建脚本产生通用 App、PKG 和 SHA256SUMS。`MACUTILBAR_SIGN_IDENTITY` 可指定应用签名身份；Installer 签名和公证尚未配置。

实测证据及未验证项目：[1.0.1 验证记录](docs/validation/1.0.1-validation.md)，[首版记录](docs/validation/1.0.0-validation.md)。**当前环境的 .app 启动路径读不到有效状态项坐标（独立二进制折叠实测通过），应用会暂停折叠并提示。此问题、VM 交互、多显示器、完整触发器矩阵及安装/登录项流程仍待验收，不应把候选版视为可用性已确认的正式版本。**

- [技术方案](docs/technical-design.md)
- [UI 设计](docs/ui-spec.md)
- [视觉稿](docs/design/1.0.0/)

身份：`local.macutilbar.app`，可执行文件 `MacUtilBar`，URL scheme `macutilbar`。独立实现；未复制 Ice、IceMelt、Thaw 或 Hidden Bar 源码。
