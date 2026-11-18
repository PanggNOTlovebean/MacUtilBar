# MacUtil · Bar 技术方案

版本：草案 v1（2026-11-15）　适用版本：1.0.0 – 1.2.x

## 1. 目标与非目标

**目标**：管理 macOS 菜单栏右侧的状态图标（status items）。

| 阶段 | 版本 | 能力 | 需要的权限 |
|---|---|---|---|
| 第一期 | 1.0 | 分隔符折叠、三段分区、点击/悬停/滚动/快捷键展开、自动收起、刘海遮挡提示、开机启动 | 无 |
| 第二期 | 1.1 | 识别每个图标属于哪个 App、可视化排序与分区、搜索并点开图标、刘海遮挡的图标一键移入隐藏区 | 辅助功能 |
| 第三期 | 1.2 | 隐藏条（菜单栏下方显示隐藏的图标）、条件规则、图标间距调节 | 录屏（可选）；间距调节不需要权限 |

**非目标**：替换菜单栏外观（染色、圆角、整条黑色菜单栏）；改造左侧 App 菜单；管理 macOS 自带的“控制中心”模块（它有系统设置入口）；联网、遥测、自动更新（沿用家族统一的更新方案，另行决定）。

## 2. 实测基线（2026-11-15，宿主 macOS 26.6.2，带刘海的 1470×956 屏）

用探测程序 [`Scripts/research/menubar-probe.swift`](../Scripts/research/menubar-probe.swift)（`CGWindowListCopyWindowInfo`，`optionOnScreenOnly`，筛选第 25 层，也就是 `kCGStatusWindowLevel`）读取窗口列表，结果如下：

| 观察 | 结论 |
|---|---|
| 11 个菜单栏窗口的 `kCGWindowOwnerName` 都是“控制中心”，PID 也相同 | macOS 26 把所有状态图标窗口都归到控制中心名下，**不能靠窗口所属进程判断图标属于哪个 App**。IceMelt 文档描述的也是同一个现象 |
| 窗口名是 `Item-0`、`Battery`、`WiFi`、`Clock`、`BentoBox-0` 等 | 第三方图标基本都叫 `Item-N`，没有区分度。另外，读取窗口名本身可能需要录屏权限，不能依赖 |
| 窗口 bounds（x、宽度、高度 33）不需要权限就能读到 | 不需要权限就能知道每个图标在哪、占多宽，这足够做“菜单栏空白区”判断和刘海遮挡判断 |
| `NSScreen.auxiliaryTopLeftArea` = x 0–646，`auxiliaryTopRightArea` = x 825–1470 | 刘海在 x 646–825 之间，可以用公开 API 算出来 |

外部信息（未在本机验证，只作风险输入）：
- Ice 原版在 Tahoe 上的隐藏条容易出错或崩溃；关掉隐藏条后，单纯的隐藏/显示仍然可用。Ice 的维护已经停滞，IceMelt 和 Thaw 是继续维护的分叉。
- IceMelt 在 macOS 26 上靠辅助功能识别图标：遍历每个 App 的 `AXExtrasMenuBar`，再按窗口 ID 或坐标对应起来。没有录屏权限时，就用 App 图标和名字代替图标截图。
- IceMelt 的 STATUS 文档称 macOS 27 重做了菜单栏：所有图标由一个 `MenuBarAgent` 统一绘制，不再是独立窗口，“推出屏幕”的隐藏方式会失效。这件事**未经证实**，但设计上必须预留降级路径（见 §9）。

## 3. 架构

```
MacUtilBar.app (LSUIElement)
├─ MacUtilBar（AppKit / SwiftUI 层）
│  ├─ AppDelegate / Main            生命周期、单实例、URL scheme
│  ├─ SectionController             管理三个 NSStatusItem，负责折叠和展开
│  ├─ RevealTriggers                点击、悬停、滚动、快捷键四种展开触发
│  ├─ AutoCollapseTimer             自动收起计时
│  ├─ MenuBarObserver               无权限读取窗口坐标，输出 MenuBarSnapshot
│  ├─ NotchMonitor                  刘海几何与遮挡检测
│  ├─ HidingSelfTest                检查隐藏是否真的生效（§9）
│  ├─ [1.1] ItemIdentifier          通过辅助功能识别图标归属
│  ├─ [1.1] ItemMover               模拟 ⌘ 拖拽移动图标
│  ├─ [1.1] ItemSearchPanel         搜索面板
│  ├─ [1.2] HiddenBarPanel          隐藏条，可截取图标画面
│  ├─ [1.2] RuleEngineRunner        规则执行
│  ├─ SettingsWindow                基本设置 / 布局 / 规则
│  └─ StatusMenu                    右键菜单（设置 / 退出），鼠标离开后自动收起
└─ MacUtilBarCore（纯逻辑，可单元测试，不依赖 AppKit 窗口）
   ├─ Configuration*                TOML 读写、校验、外部修改热更新（从 Paste 改写）
   ├─ SectionLayout                 由分隔符坐标推算三个分区和各区图标
   ├─ NotchGeometry                 刘海区间与遮挡判断
   ├─ MenuBarSnapshot               图标坐标快照的数据模型与 diff
   ├─ ItemIdentity                  图标稳定身份（bundle ID + AX 标识）
   ├─ [1.2] Rule / RuleEvaluator    规则模型与求值
   └─ Localization / Version
```

`Package.swift` 照搬 Paste 的结构：`MacUtilBarCore`、`MacUtilBar`，以及两个测试 target。不引入任何远程依赖。

## 4. 第一期：分隔符折叠

### 4.1 三个状态项和三个分区

从右到左，菜单栏的排列是：

```
[系统图标 …] [常显区图标] [◉ 主图标] [隐藏区图标] [┆ 永久隐藏分隔符] [永久隐藏区图标]   ← 左边是 App 菜单
```

- **主图标**（`autosaveName = "MacUtilBar.Main"`）：本 App 的图标，兼作“隐藏分隔符”。左键点击切换折叠/展开，右键弹出菜单。
- **永久隐藏分隔符**（`"MacUtilBar.AlwaysHidden"`）：普通展开时保持收起；⌥ 点击主图标或“显示全部”时才展开。
- 常显区是“主图标右边、系统图标左边”的那一段，不需要单独的状态项。

折叠的原理：把分隔符的 `NSStatusItem.length` 设成一个很大的值，它左边的图标就会被挤到屏幕外。这是 Hidden Bar 和 Ice 都在用的公开 API 做法。

| 状态 | 主图标 | 永久隐藏分隔符 |
|---|---|---|
| 收起 | 主图标保持正常宽度，紧贴它左边插入一个隐藏分隔符 `HiddenSpacer`，长度设为 `collapseLength` | 长度设为 `collapseLength` |
| 展开 | 移除 `HiddenSpacer` | 长度设为 `collapseLength` |
| 全部展开 | 同“展开” | 长度设为图标宽度（显示 `┆`） |

> 实现说明：Hidden Bar 是让“分隔符本身”变长。我们把主图标和真正撑开的分隔符分开，是为了收起状态下主图标始终可见、可点。具体用 `HiddenSpacer` 独立状态项还是只用两个状态项，在原型阶段对比后定稿。不管选哪种，都必须保证**收起后主图标仍然在屏幕上**，这一点要写成测试。

- `collapseLength`：取 `max(所有屏幕宽度) + 200`，上限 10,000。屏幕配置变化时（`NSApplication.didChangeScreenParametersNotification`）重新计算。
- 初始位置：第一次启动、创建状态项之前，在本 App 的 defaults 里写入 `NSStatusItem Preferred Position MacUtilBar.*`，让各分隔符的初始顺序符合上面的排列。之后由用户 ⌘ 拖拽决定，系统会记住。
- **顺序检查**：每次快照都要确认 `永久隐藏分隔符.minX < 主图标.minX`。如果被拖反了，设置页和右键菜单里会出现“分隔符顺序异常 · 一键修复”。修复时重置首选位置，并重建这两个状态项。
- **故障安全**：App 退出或崩溃时，状态项会被系统移除，被隐藏的图标自然重新出现，不会让图标永久消失。正常退出前，先把所有分隔符恢复成正常宽度。

### 4.2 展开触发（RevealTriggers）

| 触发方式 | 实现 | 权限 |
|---|---|---|
| 点击主图标 | `NSStatusBarButton` 的点击事件；用 `NSEvent.modifierFlags` 区分 ⌥（全部展开）和右键/⌃（菜单） | 无 |
| 悬停在菜单栏空白处 | 用 `NSEvent.addGlobalMonitorForEvents(.mouseMoved)` 监听；指针停在菜单栏高度内、且不在任何图标窗口里，持续 `hoverDelay`（默认 0.3 秒） | 无（全局鼠标监听不需要辅助功能权限，键盘监听才需要） |
| 在菜单栏上滚动 | 全局 `.scrollWheel` 监听，指针在菜单栏范围内时，向下滚展开、向上滚收起 | 无 |
| 快捷键 | Carbon `RegisterEventHotKey`，从 Paste 的 `Hotkeys.swift` 改写；注册失败时在设置页显示 | 无 |
| URL | `macutilbar://toggle`、`macutilbar://show`、`macutilbar://hide`、`macutilbar://show-all`、`macutilbar://settings` | 无 |

- 只有开启了悬停或滚动时才安装全局监听。关闭对应开关、锁屏、睡眠时都要移除监听。
- “空白处”的判断用 `MenuBarSnapshot`：菜单栏范围内，减去所有第 25 层窗口占的区间，再减去左侧 App 菜单的区间（取前台 App 菜单栏的宽度；拿不到时只把系统图标左侧 40pt 以外的区域算作空白）。
- 多显示器：用 `NSScreen` 判断指针所在的屏幕。每块屏幕都有自己的菜单栏，只有主图标所在的屏幕才响应。“在所有显示器上显示菜单栏”的情况，到 VM 里验证。

### 4.3 自动收起（AutoCollapseTimer）

- 可选：关闭 / 5 / 10 / 15 / 30 / 60 秒，默认 10 秒。
- 指针在菜单栏范围内，或任意图标的菜单正开着时，暂停计时。判断菜单开着的方法：`NSMenu` 通知，加上检查第 101 层（菜单层）的窗口快照。
- 前台 App 切换时可以选择立即收起（默认关）。

### 4.4 刘海检测（NotchMonitor，无权限）

- 刘海区间：`[auxiliaryTopLeftArea.maxX, auxiliaryTopRightArea.minX]`。没有刘海的屏幕上两者都为 nil，直接跳过。
- 遮挡判断：在**展开**状态下，有窗口的 `minX < auxiliaryTopRightArea.minX`（也就是越过了刘海右边沿），或者 `optionAll` 列表里有、`optionOnScreenOnly` 列表里没有的第 25 层窗口，都计为被遮挡。这两条规则都要在本机刘海屏上验证（M1）。
- 表现：主图标右上角显示一个小圆点；设置页提示“有 N 个图标被刘海挡住”，并给出两个解决办法：①把它们 ⌘ 拖到主图标左边，放进隐藏区（第一期给文字说明，第二期一键完成）；②减小图标间距（第三期）。
- `Core.NotchGeometry` 接受注入的屏幕几何，可以在单元测试里覆盖：有刘海、无刘海、外接屏、多屏错位。

### 4.5 开机启动

用 `SMAppService.mainApp.register()` / `unregister()`。设置页显示的状态以 `SMAppService.mainApp.status` 为准，包括“需要在系统设置中批准”的状态。

## 5. 第二期：图标识别、排序与搜索（辅助功能）

### 5.1 ItemIdentifier

1. 遍历 `NSWorkspace.shared.runningApplications`（包括没有界面的 agent App，以及控制中心本身）。
2. 对每个 App 调用 `AXUIElementCreateApplication(pid)`，读取 `"AXExtrasMenuBar"` 属性，再读取它的子元素（`AXMenuBarItem`）的 `AXPosition`、`AXSize`、`AXTitle`、`AXDescription`、`AXIdentifier`。
3. 和 `MenuBarSnapshot` 里的窗口按坐标对应（误差 ≤ 2pt）。对不上的窗口标记为“未识别”，显示成通用图标。
4. 稳定身份 `ItemIdentity`：`bundleID + (AXIdentifier ?? AXDescription ?? AXTitle ?? 同一 App 内的序号)`。同一个 App 有多个图标时用这个序号兜底，界面上提示“同一 App 的多个图标”。
5. AX 调用放在后台串行队列执行，每次调用设置 `AXUIElementSetMessagingTimeout` 为 0.25 秒，避免卡死的 App 拖住整个流程。快照间隔 1 秒，只在设置页、搜索面板或隐藏条可见时才运行；其他时候只在菜单栏变化时触发。

### 5.2 ItemMover（模拟 ⌘ 拖拽）

1. 记住当前指针位置，用 `CGDisplayHideCursor` 隐藏指针。
2. 构造一组 `CGEvent`：在源图标中心按下（带 `.maskCommand` 标志）→ 分几段拖到目标位置 → 松开，每步之间等 10–20 毫秒。事件发到 `.cghidEventTap`。
3. 等菜单栏动画结束，重新识别，确认图标真的到了目标分区。没到就最多重试 2 次；还不行就报错，说明哪个图标移动失败。
4. 恢复指针位置并重新显示指针。移动过程中检测到用户真实的鼠标或键盘输入，就立刻中止。
5. 移动前先把相关分区展开，否则拖不到屏幕外的位置。
6. 发送事件需要辅助功能权限，用 `AXIsProcessTrusted()` 检查。

> 不能把“事件发出去了”当作移动成功，必须以重新识别出的新坐标为准（和 MacUtils 截图项目的验证原则一致）。

### 5.3 布局持久化

- `config.toml` 里保存 `[[items]]`：`identity`、`section`（visible / hidden / alwaysHidden）、`order`。这是**期望布局**。
- 启动时和识别到新图标时，对比实际布局和期望布局。默认只提示“与保存的布局不一致”，开启“自动恢复布局”后才自动移动，这个开关默认关闭，避免启动时乱拖用户的图标。
- 新出现的图标：放进用户设置的默认分区（默认放常显区，也就是不动它）。

### 5.4 搜索面板（ItemSearchPanel）

- 快捷键（默认不设置）或 `macutilbar://search` 打开。界面是居中的 `NSPanel`，风格和 Paste 的选择框一致。
- 列表显示所有已识别的图标：App 图标、名称、所在分区。可以按 App 名、AX 标题或描述做模糊匹配。
- 回车时：①如果目标在隐藏区，先展开；②优先对目标调用 `AXUIElementPerformAction(kAXPressAction)`，不移动指针；如果失败，再在图标中心模拟一次点击；③图标的菜单关闭后，按自动收起的规则恢复。

## 6. 第三期：隐藏条、规则、间距

### 6.1 隐藏条（HiddenBarPanel）

- 一个非激活的 `NSPanel`，窗口层级在菜单栏之上，从主图标下方弹出，右对齐。在刘海机型上是找回被遮挡图标的主要入口。
- 图标画面：有录屏权限时，用 ScreenCaptureKit（`SCShareableContent` 找到对应窗口 ID 的 `SCWindow`，再用 `SCScreenshotManager.captureImage`）。不用 `CGWindowListCreateImage`，它在新 SDK 里已经弃用。没有权限时显示 App 图标加名称（参考 IceMelt 的降级方式）。
- 截图前，图标得先被临时展开到屏幕上才能截到。截完立刻收起，并缓存截图（按 identity 存，最多 64 张）。菜单栏外观变化、切换深色模式时让缓存失效。
- 点击隐藏条里的图标，执行和 §5.4 一样的按下流程。
- 开启录屏权限后，系统可能在菜单栏显示紫色的录屏提示。设置页要提前说明这一点。录屏权限只用于截取菜单栏区域，截图不落盘。

### 6.2 条件规则

- 规则 = 条件 + 动作。条件：某 App 在前台、使用电池或电量低于 X%、接了外接显示器、连上某个 Wi-Fi（读 SSID 需要定位权限，**不做**，改为“网络已连接 / 断开”）、时间段。动作：临时显示某个图标（在 1.2 版里实现为“临时展开隐藏区”）；或者把某个图标移到常显区，条件不满足时再移回去（依赖 ItemMover，需要辅助功能）。
- `RuleEvaluator` 是纯函数：输入环境快照，输出期望的图标状态。用单元测试覆盖。

### 6.3 图标间距

- 写全局 currentHost 偏好 `NSStatusItemSpacing`（默认约 16）和 `NSStatusItemSelectionPadding`（默认约 16），用 `CFPreferencesSetValue(..., kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)`。“恢复默认”就是删除这两个键。
- 修改只对之后启动的 App 生效。界面上要说明“需要注销重新登录，或重新打开相关 App”。**不自动退出其他 App。**
- 修改前把原值记到配置里，方便撤销。这是第三期唯一会改动全局偏好的功能，要用一个单独的确认对话框。

## 7. 配置文件

路径 `~/.config/macutilbar/config.toml`（测试时可以用 `MACUTILBAR_CONFIG` 指向别的文件）。界面和外部编辑双向同步：从 Paste 的 `ConfigurationStore` 改写，格式错误时保留上一次的有效状态，有冲突时拒绝覆盖。

```toml
[core]
language = "system"          # system | zh-Hans | en
appearance = "system"        # system | light | dark
launch_at_login = true

[reveal]
click = true                 # 固定开启，界面不提供关闭
hover = false
hover_delay_ms = 300
scroll = true
toggle_shortcut = "ctrl+option+b"
search_shortcut = ""         # 1.1
auto_collapse_seconds = 10   # 0 = 关闭
collapse_on_app_switch = false

[appearance_items]
divider_style = "chevron"    # chevron | line | dot
show_notch_badge = true

[layout]                     # 1.1
restore_on_launch = false
new_item_section = "visible"

[[items]]                    # 1.1，期望布局
identity = "com.example.app#AXIdentifier=status"
section = "hidden"           # visible | hidden | alwaysHidden
order = 0

[spacing]                    # 1.2
enabled = false
item_spacing = 16
selection_padding = 16
```

## 8. 权限矩阵

| 功能 | 无权限 | 辅助功能 | 录屏 |
|---|---|---|---|
| 折叠、分区、展开触发、自动收起、刘海提示 | ✅ | | |
| 识别图标归属、可视化排序、自动恢复布局 | | ✅ | |
| 搜索并点开图标 | | ✅ | |
| 隐藏条（图标截图） | 显示 App 图标代替 | ✅ 点开图标 | ✅ 截图 |
| 规则（临时展开） | ✅ | | |
| 规则（移动图标） | | ✅ | |
| 图标间距 | ✅（写全局偏好，单独确认） | | |

- 只在用户点击“启用…”按钮时才申请权限：用 `AXIsProcessTrustedWithOptions(prompt: true)`，或打开对应的系统设置页面。
- 设置页可见期间，每秒检查一次授权状态，授权后自动刷新界面，不需要重启。
- 拿不到权限时功能降级，不能弹窗打断用户。

## 9. 风险与降级

| 风险 | 应对 |
|---|---|
| macOS 版本改变隐藏机制（据报 macOS 27 已改） | `HidingSelfTest`：每次折叠后检查隐藏区图标窗口的 `maxX` 是否已经小于 0（或者已经不在屏幕上）。连续 2 次失败，就进入“隐藏不可用”状态：主图标显示警告，设置页解释原因，并引导用户去“系统设置 > 菜单栏 > 允许在菜单栏中显示”。隐藏逻辑封装在 `MenuBarHidingBackend` 协议后面，方便日后替换实现 |
| macOS 26 的图标窗口全部归属控制中心 | 第一期不依赖图标归属；第二期改用辅助功能识别 |
| 左侧 App 菜单很长时，系统会遮住部分图标 | 展开时检测图标窗口有没有被 App 菜单盖住（`minX` 小于 App 菜单的 `maxX`），给出提示 |
| 用户把分隔符拖反、或拖到系统图标中间 | 顺序检查加一键修复（§4.1） |
| 卡死的 App 拖慢 AX 调用 | 后台队列、每次调用 0.25 秒超时、只在需要时运行 |
| 模拟拖拽打断用户操作 | 隐藏指针、检测到用户输入就中止、移动后恢复指针；只在用户主动操作时触发 |
| GPL 代码污染 | 只参考 Ice、IceMelt、Thaw 的行为，不复制代码 |

## 10. 测试与验证

- **Core 单元测试**：分区推算（各种分隔符坐标）、顺序检查与修复建议、刘海几何（注入屏幕参数）、快照 diff、配置解析与往返、规则求值、`collapseLength` 计算。
- **App 测试**：状态项创建、销毁与位置种子；折叠后主图标仍在屏幕上；全局监听按开关、锁屏、睡眠正确安装和移除；自动收起在悬停或菜单打开时暂停；URL 路由；快捷键注册失败时的界面状态。
- **真机和 VM 验证**（不能用“API 返回成功”代替）：
  - 宿主刘海屏（macOS 26.6.2）：折叠和展开后，隐藏区窗口真实坐标的变化；被刘海遮挡时的检测；悬停、滚动触发。宿主上只读观察，不改宿主权限。
  - `MacUtils Screenshot Lab` VM：多显示器错位、辅助功能授权、识别和移动、隐藏条截图权限的完整流程。
- 每个阶段都要记录 `docs/validation/<版本>-*.md`，写清实际执行过的命令和交互，并列出没有验证的项。

## 11. 里程碑

| 版本 | 内容 | 验收 |
|---|---|---|
| M0 原型（不发版） | 两种分隔符方案对比、在宿主 26.6.2 上跑 `HidingSelfTest`、刘海遮挡判断规则验证 | 选定方案，并把实测结果写进本文 §2 |
| 1.0.0 | 第一期全部 + 设置页（基本设置、布局说明）+ 配置文件 | §10 第一期的测试和验证全部通过 |
| 1.1.0 | 图标识别、可视化布局、搜索面板、刘海图标一键移入隐藏区 | VM 中真实移动 3 个以上图标并重启后保持；拒绝授权时能正确降级 |
| 1.2.0 | 隐藏条、规则、间距 | 有和没有录屏权限两条路径都验证过；间距修改后能撤销 |

## 12. 参考

- Hidden Bar（MIT）：dwarvesf/hidden，分隔符变长的基本做法
- Ice（GPL-3.0）：jordanbaird/Ice，三段分区、Ice Bar、⌘ 拖拽移动，只参考行为
- IceMelt（GPL-3.0）：pnikolaidis/icemelt，macOS 26 上用 AX 识别图标、无录屏时的降级，只参考行为
- Bartender 官方权限说明：录屏用于看到菜单栏内容，辅助功能用于移动图标

## 13. 1.0.0 开发候选实现记录（2026-11-15）

本次只交付第一期开发候选，不将 1.1/1.2 的计划当作已实现。

- 选用三个常驻状态项：Main 固定长度 26、HiddenSpacer 展开长度 8、AlwaysHidden 展开长度 22；macOS 26 会额外增加左右 padding。常驻 spacer 保持用户排序位置，避免每次重新插入漂移。用户应将隐藏图标放到紧邻主图标的空白 spacer 左侧。
- 首次启动全部展开；开机启动默认关闭，只从设置按钮操作 SMAppService。配置的 launch_at_login 是请求值，界面显示实际系统状态。避免启动时未经交互修改登录项。
- 只读 CG 窗口信息。额外用自身状态项临时增加 11pt 宽度的前后唯一匹配辅助定位自身窗口，不能识别其他应用，也不把匹配成功视为隐藏成功。匹配不唯一时回退本地窗口；无有效屏幕坐标则暂停隐藏并提示重试。
- TOML 只实现生成格式的严格子集，详见 README。坏配置和冲突拒绝覆盖。
- 悬停使用靠近状态区的 40pt 保守空白范围，排除大宽度折叠分隔符、其他图标、刘海及屏幕左半区。仍需实际触发器矩阵验收。
- 当前缺少 Developer ID / Installer 身份，只允许 ad-hoc 开发候选预发布。
- 同一最终通用二进制作为独立进程运行时，宿主窗口坐标验证折叠成立；在当前自动化环境启动 .app 时出现 0,-22 占位坐标。此差异未解决，不认定应用包端到端验收通过。详情见验证记录。

### 1.0.1 候选的证据约束

自身窗口身份必须通过同一窗口 ID 的“增宽—恢复”唯一匹配；初始固有宽度未稳定时只重试一次。校准期间不执行折叠。无法得到 CG Window Server 证据时，设置与诊断保留未知状态，不以零矩形或本地占位窗口充当真实位置。详情见 [1.0.1 验证记录](validation/1.0.1-validation.md)。

自检需区分完全隐藏、部分窗口保持显示、整体机制无效。已观察到系统音视频指示器在其他图标隐藏后主动右移，不能据此宣称整个后端失效，也不能强行隐藏该系统指示器；部分未隐藏窗口必须向用户显示剩余数量。所有待隐藏窗口都仍可见或主图标消失时，保留连续两次失败后恢复展开的策略。

## 2026-11-18 更新机制

按用户最新要求，允许仅在设置中点击“检查更新”时请求公开 GitHub 版本清单；有新版则打开发布页下载 PKG 手动安装。无后台联网、遥测或自动安装。此项覆盖此前联网/更新非目标。
