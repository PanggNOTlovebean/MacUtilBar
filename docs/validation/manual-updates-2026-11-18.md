# MacUtilBar 1.0.2 / 3 手动更新机制

日期：2026-11-18。用户授权横跨同级 MacUtil 工具与 MacUtils 实现简单更新检查，并新建公开 `PanggNOTlovebean/MacUtils-Releases`，只放安装包和版本信息。源码仓库可见性保持不变。

## 行为

- 设置内显示版本、构建号和“检查更新”；只有点击才联网，无后台网络/安装/遥测，无客户端凭据。
- 独立请求 `feeds/MacUtilBar.json`。按递增 build 比较；旧版本清单不提示降级，最低 macOS 不满足时说明要求。版本清单限制 64 KiB、超时、产品身份和 schema 校验，只允许对应产品/版本的 HTTPS GitHub 发布页。
- 检查失败可重试，清除旧下载状态；检查中禁止重复请求。成功后显示本次设置视图会话内的检查时间。
- 打开发布页下载 PKG 手动安装；不会下载/执行远程脚本或直接替换应用。
- 各仓库保留独立源码副本，无跨仓库构建/运行依赖。

## 发布命令

1. 全量 `swift test`。
2. `./Scripts/build.sh build/candidate`（Right 发布时设置 `MACUTILRIGHT_ARCHS=universal`；Bar 脚本默认 universal）。
3. `python3 Scripts/package-update.py '<候选 .app>' build/releases/v1.0.2`：验证 ad-hoc 签名、版本及架构；创建不重定位、无安装脚本的 PKG，解包后严格签名与逐文件比较；生成 SHA-256。
4. 提交并推送源码，然后 `python3 Scripts/publish-update.py '<候选 .app>' '<PKG>' '<公开仓库>/feeds' --source-commit '<完整 SHA>'`。使用 Git 凭据助手，仅内存持有凭据，上传并回读逐字节验证两个附件，发布开发预发布后才生成清单。存在同版本 release 时拒绝覆盖，应先检查远端状态。
5. 提交并推送公开仓库的清单。新版本沿用格式，递增产品版本/build；不得覆盖旧资产。

## 验证边界

产物为 universal ad-hoc 签名开发候选，PKG 未签名/未公证。本次不改已安装 App、用户配置、剪贴板内容或主机隐私权限。测试使用隔离夹具；已有 opt-in 原生测试跳过不视为验收。没有执行真实安装、点击设置按钮/浏览器下载或扩展升级原生验收。MacUtilMouse 尚无 App 源码，本次仅更新其设计文档，不创建占位安装包或虚假 feed。

## 本次本地结果

- 全量 `swift test`：Executed 17 tests, with 0 failures (0 unexpected) in 0.048 (0.056) seconds
- release 构建、主应用及内嵌扩展（如有）严格签名校验退出 0。
- PKG 创建、解包后签名校验及 `diff -qr` 逐文件比较退出 0。
- 日志位于 `build/update-tests-final.log`、`build/update-build.log`、`build/update-pkg.log`。

## 发布传输恢复

首次 urllib 上传出现传输失败；保持 release 为草稿并读取实际远端附件状态，改用已有发布流程验证过的 curl 传输（凭据仅由 stdin 传入，不放命令行/日志；跨域下载重定向去除凭据）。`--resume-draft` 仅恢复同产品、同版本、同源提交的草稿，已存在附件必须完整回读且逐字节一致，公开版本禁止覆盖。额外校验候选 plist、源提交 plist、本地与远端 annotated tag 一致后才允许发布。
