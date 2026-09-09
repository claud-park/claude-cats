import AppKit
import ClaudeCatsCore
import ServiceManagement

/// 메뉴바 아이콘과 메뉴. 요약 · 일시정지 · 새로고침 · 디스플레이 · 로그인 시 시작 · 종료.
@MainActor
final class StatusMenu: NSObject {
    private let item: NSStatusItem
    private let summaryItem = NSMenuItem(title: "고양이 0마리", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "일시정지", action: #selector(togglePause), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "로그인 시 시작", action: #selector(toggleLogin), keyEquivalent: "")
    private let displayItem = NSMenuItem(title: "디스플레이", action: nil, keyEquivalent: "")
    private let displayMenu = NSMenu()
    private let hooksItem = NSMenuItem(title: "알림 연동", action: #selector(toggleHooks), keyEquivalent: "")
    private let onPauseToggle: (Bool) -> Void
    private let onRefresh: () -> Void
    private let onDisplaySelect: (String?) -> Void
    private var paused = false
    private var preferredDisplayName: String?

    init(
        onPauseToggle: @escaping (Bool) -> Void,
        onRefresh: @escaping () -> Void,
        onDisplaySelect: @escaping (String?) -> Void
    ) {
        self.onPauseToggle = onPauseToggle
        self.onRefresh = onRefresh
        self.onDisplaySelect = onDisplaySelect
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let image = NSImage(systemSymbolName: "cat", accessibilityDescription: "Claude Cats")
            ?? NSImage(systemSymbolName: "pawprint", accessibilityDescription: "Claude Cats")
        if let image {
            item.button?.image = image
        } else {
            // 두 심볼 다 없는 OS 라면 이미지 없이 빈 칸만 남는다 — 누를 수 있게 글자를 넣는다.
            item.button?.title = "🐱"
        }

        let menu = NSMenu()
        // 기본값(true)이면 AppKit 이 매번 활성 상태를 다시 계산해 summaryItem 의
        // isEnabled = false 를 덮어쓴다. 직접 관리한다.
        menu.autoenablesItems = false

        let refresh = NSMenuItem(title: "지금 새로고침", action: #selector(self.refresh), keyEquivalent: "r")
        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        summaryItem.isEnabled = false                                  // 읽기 전용 요약 줄
        for entry in [pauseItem, refresh, loginItem, quit, displayItem, hooksItem] { entry.isEnabled = true }
        for entry in [pauseItem, refresh, loginItem, hooksItem] { entry.target = self }
        // quit 은 target 없이 응답 체인을 타고 NSApp.terminate 로 간다.

        // 하위 메뉴는 열릴 때마다 menuNeedsUpdate 에서 다시 만든다(모니터가 꽂혔다 빠진다).
        displayMenu.autoenablesItems = false
        displayMenu.delegate = self
        displayItem.submenu = displayMenu
        // 훅 체크 표시는 파일이 진실이다(다른 앱·사용자가 지웠을 수 있다). 열 때마다 다시 읽는다.
        menu.delegate = self

        menu.addItem(summaryItem)
        menu.addItem(.separator())
        menu.addItem(pauseItem)
        menu.addItem(refresh)
        menu.addItem(displayItem)
        menu.addItem(hooksItem)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(quit)
        item.menu = menu
        updateLoginState()
        updateHooksState()
        rebuildDisplayMenu()
    }

    /// 현재 선택(자동 = nil)을 알려준다. 메뉴 체크 표시에만 쓴다.
    func setPreferredDisplayName(_ name: String?) {
        preferredDisplayName = name
        rebuildDisplayMenu()
    }

    private func rebuildDisplayMenu() {
        displayMenu.removeAllItems()
        for entry in DisplaySelection.menuEntries(
            preferredName: preferredDisplayName,
            available: DisplayCatalog.current()
        ) {
            let menuItem = NSMenuItem(title: entry.title, action: #selector(selectDisplay(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.isEnabled = true
            menuItem.state = entry.isSelected ? .on : .off
            menuItem.representedObject = entry.name   // 자동은 nil
            displayMenu.addItem(menuItem)
        }
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String
        preferredDisplayName = name
        rebuildDisplayMenu()
        onDisplaySelect(name)
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

    /// Claude Code 훅 설치/해제. 파일 작업은 HookSetup 이 하고 실패도 거기서 알린다.
    @objc private func toggleHooks() {
        HookSetup.setInstalled(hooksItem.state != .on)
        updateHooksState()
        onRefresh()   // 켜자마자 이벤트 디렉터리를 한 번 읽는다
    }

    private func updateHooksState() {
        hooksItem.state = HookSetup.isInstalled() ? .on : .off
    }
}

extension StatusMenu: NSMenuDelegate {
    /// 메뉴가 열리기 직전. 하위 메뉴는 지금 붙어 있는 디스플레이로 다시 만들고,
    /// 본 메뉴는 훅 체크 표시를 파일에서 다시 읽는다.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === displayMenu {
            rebuildDisplayMenu()
        } else {
            updateHooksState()
        }
    }
}
