// 一次性调研工具：列出菜单栏（第 25 层）窗口的所属进程、窗口名和坐标，以及屏幕刘海区域。
// 不需要任何权限；结论记录在 docs/technical-design.md §2。
// 用法：swiftc -O Scripts/research/menubar-probe.swift -o build/menubar-probe && build/menubar-probe
import CoreGraphics
import AppKit
let opts: CGWindowListOption = [.optionOnScreenOnly]
let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as! [[String: Any]]
let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
print("statusLevel", statusLevel, "screens", NSScreen.screens.map{($0.frame, $0.safeAreaInsets.top, $0.auxiliaryTopLeftArea ?? .zero, $0.auxiliaryTopRightArea ?? .zero)})
var owners: [String:Int] = [:]
for w in list where (w[kCGWindowLayer as String] as? Int) == statusLevel {
  let o = w[kCGWindowOwnerName as String] as? String ?? "?"
  owners[o, default: 0] += 1
  let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
  print(o, w[kCGWindowOwnerPID as String] ?? "", w[kCGWindowName as String] ?? "<noname>", b["X"] ?? "", b["Y"] ?? "", b["Width"] ?? "", b["Height"] ?? "")
}
print(owners)
