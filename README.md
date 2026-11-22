# MacUtil · Bar

当前开发候选：**1.1.0 / build 4**（未发布）。设置界面按 MacUtil · Right 重构为侧边栏布局；新增辅助功能图标识别、在设置里移动图标、搜索面板和图标间距。见 [1.1.0 验证记录](docs/validation/1.1.0-validation.md)。

**已知阻断：** 在当前宿主上，macOS 不显示 Bundle ID 为 `local.macutilbar.app` 的任何菜单栏图标（同一程序换 ID 即正常，折叠实测通过）。请在 系统设置 › 菜单栏 › “允许在菜单栏中显示” 中打开 MacUtil Bar（已打开则关闭后再打开），再在设置里点“重新检查”。图标不可见时，再次打开 App 会直接进入设置。

**辅助功能相关功能（识别、移动、搜索）只有逻辑单元测试，尚未在授权后的真机上验证。** 隐藏条、条件规则、期望布局自动恢复未实现。

上一发布：**1.0.2 / build 3**。在设置的通用/基本设置中点击“检查更新”，联网读取公开版本信息后打开 GitHub 发布页，下载 PKG 手动安装。无后台检查、自动安装或遥测。首次需要手动安装此版本。

公开下载：[ MacUtilBar 1.0.2 ](https://github.com/PanggNOTlovebean/MacUtils-Releases/releases/tag/MacUtilBar-v1.0.2)（universal，ad-hoc 开发包，未公证）。源码仓库可见性保持不变。验证与后续发布流程见 [更新机制交付记录](docs/validation/manual-updates-2026-11-18.md)。


原生 macOS 菜单栏图标管理应用。macOS 14+，支持 Apple Silicon 和 Intel，无第三方运行时依赖。

此前交付：**1.0.1 / build 2 开发候选版**。下载见 [GitHub Releases](https://github.com/PanggNOTlovebean/MacUtilBar/releases)。PKG 安装到 `/Applications/MacUtilBar.app`。这是 ad-hoc 签名、未公证的预发布包，macOS 可能阻止直接打开；不属于 Developer ID 正式发行版。

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

URL：`macutilbar://toggle`、`show`、`hide`、`show-all`、`settings`、`search`（需辅助功能）。

## 1.1.0 新增

- 设置窗口：侧边栏（菜单栏图标 / 展开与收起 / 外观 / 通用），工具栏直接切换 收起｜展开｜全部，问题提示卡置顶。
- 辅助功能（可选，只在点击“打开系统设置…”时申请）：识别每个图标所属 App，按 常显 / 隐藏 / 永久隐藏 分组列出；分段控件换分区、↑ ↓ 调整顺序（替你按住 ⌘ 拖动，并按实际位置确认）；搜索面板（可设快捷键）回车点开图标。
- 图标间距：写系统全局偏好，应用与恢复都需确认，只对之后打开的 App 生效。
- 首次运行时 ‹‹ 放在最左，已有图标默认在“隐藏”区。

## 构建与验证

```sh
swift test
./Scripts/build.sh build/candidate
codesign --verify --deep --strict build/candidate/MacUtilBar.app
```

无需远程 SwiftPM 依赖。构建脚本产生通用 App、PKG 和 SHA256SUMS。`MACUTILBAR_SIGN_IDENTITY` 可指定应用签名身份；Installer 签名和公证尚未配置。

实测证据及未验证项目：[1.0.1 验证记录](docs/validation/1.0.1-validation.md)，[首版记录](docs/validation/1.0.0-validation.md)。**当前环境的 .app 启动路径读不到有效状态项坐标（独立二进制折叠实测通过），应用会暂停折叠并提示。2026-11-18 经用户授权将 MacUtilBar 的系统菜单栏显示开关关闭后恢复，问题仍复现。此问题、VM 交互、多显示器、完整触发器矩阵及安装/登录项流程仍待验收，不应把候选版视为可用性已确认的正式版本。**

- [技术方案](docs/technical-design.md)
- [UI 设计](docs/ui-spec.md)
- [视觉稿](docs/design/1.0.0/)

身份：`local.macutilbar.app`，可执行文件 `MacUtilBar`，URL scheme `macutilbar`。独立实现；未复制 Ice、IceMelt、Thaw 或 Hidden Bar 源码。
