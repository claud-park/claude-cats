import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 기본은 메뉴바 전용(accessory). `showDockIcon` 을 켠 환경(노치로 메뉴바 아이콘이
// 숨는 Mac 등)에서는 Dock 아이콘을 띄워 조작 창구를 확보한다.
let showDockIcon = UserDefaults.standard.bool(forKey: AppDelegate.showDockIconKey)
app.setActivationPolicy(showDockIcon ? .regular : .accessory)
app.run()
