# 1.0.0 UI 设计稿

在线画布：https://claude.ai/artifact/SQnrfjKQfRRmBfuXB9pkho（私有，需要分享后别人才能打开）

视觉参考是 MacUtil · Paste（1.6 基本设置、1.8.0 安静原生）和 MacUtil · Right（列表行、图标块、菜单栏模板图规范），**不参考 MacUtils（mactool）的界面**。规则以 [ui-spec.md](../../ui-spec.md) 为准，画布只用来示意。

| 画板 | 内容 |
|---|---|
| `Main.dc.html` | 菜单栏的收起、展开、全部展开、刘海遮挡状态，右键菜单，主图标模板图 |
| `SettingsGeneral.dc.html` | 设置 · 基本设置 |
| `SettingsLayout.dc.html` | 设置 · 布局（1.0，不需要权限） |
| `SettingsLayoutAX.dc.html` | 设置 · 布局（1.1，已授权辅助功能） |
| `Search.dc.html` | 搜索面板（1.1） |
| `HiddenBar.dc.html` | 隐藏条（1.2） |

`canvas-source/` 是画布源文件的备份，需要在 Design 画布里打开才能渲染。图里的 App 图标块（字母方块）是占位，实际显示各 App 自己的图标。
