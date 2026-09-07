import AppKit
import ClaudeCatsCore
import ServiceManagement

/// 메뉴바 아이콘과 메뉴. 요약 · 일시정지 · 새로고침 · 로그인 시 시작 · 종료.
@MainActor
final class StatusMenu: NSObject {
    private let item: NSStatusItem
    private let summaryItem = NSMenuItem(title: "고양이 0마리", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "일시정지", action: #selector(togglePause), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "로그인 시 시작", action: #selector(toggleLogin), keyEquivalent: "")
    private let onPauseToggle: (Bool) -> Void
    private let onRefresh: () -> Void
    private var paused = false

    init(onPauseToggle: @escaping (Bool) -> Void, onRefresh: @escaping () -> Void) {
        self.onPauseToggle = onPauseToggle
        self.onRefresh = onRefresh
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let image = NSImage(systemSymbolName: "cat", accessibilityDescription: "Claude Cats")
            ?? NSImage(systemSymbolName: "pawprint", accessibilityDescription: "Claude Cats")
        item.button?.image = image

        let menu = NSMenu()
        summaryItem.isEnabled = false
        menu.addItem(summaryItem)
        menu.addItem(.separator())
        menu.addItem(pauseItem)
        let refresh = NSMenuItem(title: "지금 새로고침", action: #selector(self.refresh), keyEquivalent: "r")
        menu.addItem(refresh)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for entry in [pauseItem, refresh, loginItem] { entry.target = self }
        item.menu = menu
        updateLoginState()
    }

    func update(with snapshot: Snapshot) {
        let busy = snapshot.sessions.filter { $0.status == .busy }.count
        let kittens = snapshot.sessions.reduce(0) { $0 + $1.subagents.count }
        var text = "고양이 \(snapshot.sessions.count)마리 · 작업 중 \(busy)"
        if kittens > 0 { text += " · 새끼 \(kittens)" }
        summaryItem.title = text
    }

    @objc private func togglePause() {
        paused.toggle()
        pauseItem.title = paused ? "재개" : "일시정지"
        onPauseToggle(paused)
    }

    @objc private func refresh() {
        onRefresh()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "로그인 시 시작 설정 실패"
            alert.informativeText = "앱 번들(.app)로 실행 중일 때만 등록할 수 있습니다.\n\(error.localizedDescription)"
            alert.runModal()
        }
        updateLoginState()
    }

    private func updateLoginState() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
