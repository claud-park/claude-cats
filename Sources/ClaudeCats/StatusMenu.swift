import AppKit
import ClaudeCatsCore
import ServiceManagement

/// 메뉴바 아이콘과 메뉴. 요약 · 일시정지 · 새로고침 · 디스플레이 · 로그인 시 시작 · 종료.
@MainActor
final class StatusMenu: NSObject {
    private let item: NSStatusItem
    private let summaryItem = NSMenuItem(title: "고양이 0마리", action: nil, keyEquivalent: "")
    /// 세션 파일을 못 읽었을 때만 보이는 경고 줄. 건강하면 숨긴다.
    private let healthItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "일시정지", action: #selector(togglePause), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "로그인 시 시작", action: #selector(toggleLogin), keyEquivalent: "")
    private let displayItem = NSMenuItem(title: "디스플레이", action: nil, keyEquivalent: "")
    private let displayMenu = NSMenu()
    private let placementItem = NSMenuItem(title: "표시 위치", action: nil, keyEquivalent: "")
    private let placementMenu = NSMenu()
    private let hooksItem = NSMenuItem(title: "알림 연동", action: #selector(toggleHooks), keyEquivalent: "")
    /// 읽기 전용 버전 줄. 번들에 박힌 커밋을 그대로 보여준다.
    private let versionItem = NSMenuItem(title: "버전", action: nil, keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "업데이트 확인…", action: #selector(updateAction), keyEquivalent: "")
    private let autoUpdateItem = NSMenuItem(
        title: "자동으로 업데이트 확인", action: #selector(toggleAutoUpdate), keyEquivalent: ""
    )
    private let onPauseToggle: (Bool) -> Void
    private let onRefresh: () -> Void
    private let onDisplaySelect: (String?) -> Void
    private let onPlacementSelect: (WindowPlacement) -> Void
    private let updater = Updater()
    private var paused = false
    private var preferredDisplayName: String?
    private var placement: WindowPlacement = .desktop
    /// 마지막 폴링이 만든 요약 문자열. 업데이트 중에는 이 자리를 진행 표시가 빌려 쓴다.
    private var summaryText = "고양이 0마리"
    /// 메뉴바 아이콘이 실제 이미지인지. 배지(`•`)를 어디에 붙일지가 달라진다.
    private var hasIconImage = false

    init(
        onPauseToggle: @escaping (Bool) -> Void,
        onRefresh: @escaping () -> Void,
        onDisplaySelect: @escaping (String?) -> Void,
        onPlacementSelect: @escaping (WindowPlacement) -> Void
    ) {
        self.onPauseToggle = onPauseToggle
        self.onRefresh = onRefresh
        self.onDisplaySelect = onDisplaySelect
        self.onPlacementSelect = onPlacementSelect
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let image = NSImage(systemSymbolName: "cat", accessibilityDescription: "Claude Cats")
            ?? NSImage(systemSymbolName: "pawprint", accessibilityDescription: "Claude Cats")
        if let image {
            item.button?.image = image
            hasIconImage = true
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
        healthItem.isEnabled = false                                   // 읽기 전용 경고 줄
        healthItem.isHidden = true                                     // 문제가 있을 때만 보인다
        versionItem.isEnabled = false                                  // 읽기 전용 버전 줄
        for entry in [pauseItem, refresh, loginItem, quit, displayItem, placementItem, hooksItem] {
            entry.isEnabled = true
        }
        for entry in [pauseItem, refresh, loginItem, hooksItem, updateItem, autoUpdateItem] {
            entry.target = self
        }
        // quit 은 target 없이 응답 체인을 타고 NSApp.terminate 로 간다.

        // 하위 메뉴는 열릴 때마다 menuNeedsUpdate 에서 다시 만든다(모니터가 꽂혔다 빠진다).
        displayMenu.autoenablesItems = false
        displayMenu.delegate = self
        displayItem.submenu = displayMenu
        // 표시 위치는 세 개로 고정이라 한 번만 만들고 체크 표시만 갈아 끼운다.
        placementMenu.autoenablesItems = false
        placementItem.submenu = placementMenu
        // 훅 체크 표시는 파일이 진실이다(다른 앱·사용자가 지웠을 수 있다). 열 때마다 다시 읽는다.
        menu.delegate = self

        menu.addItem(summaryItem)
        menu.addItem(healthItem)
        menu.addItem(.separator())
        menu.addItem(pauseItem)
        menu.addItem(refresh)
        menu.addItem(.separator())
        menu.addItem(versionItem)
        menu.addItem(updateItem)
        menu.addItem(autoUpdateItem)
        menu.addItem(.separator())
        menu.addItem(displayItem)
        menu.addItem(placementItem)
        menu.addItem(hooksItem)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(quit)
        item.menu = menu
        updateLoginState()
        updateHooksState()
        rebuildDisplayMenu()
        rebuildPlacementMenu()

        updater.onChange = { [weak self] in self?.renderUpdate() }
        renderUpdate()
        updater.scheduleFirstCheck()
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

    /// 현재 창 레벨 선택을 알려준다. 메뉴 체크 표시에만 쓴다.
    func setPlacement(_ new: WindowPlacement) {
        placement = new
        rebuildPlacementMenu()
    }

    private func rebuildPlacementMenu() {
        placementMenu.removeAllItems()
        for entry in WindowPlacement.menuEntries(selected: placement) {
            let menuItem = NSMenuItem(title: entry.title, action: #selector(selectPlacement(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.isEnabled = true
            menuItem.state = entry.isSelected ? .on : .off
            menuItem.representedObject = entry.placement.rawValue
            placementMenu.addItem(menuItem)
        }
    }

    @objc private func selectPlacement(_ sender: NSMenuItem) {
        let new = WindowPlacement.stored(sender.representedObject as? String)
        placement = new
        rebuildPlacementMenu()
        onPlacementSelect(new)
    }

    func update(with snapshot: Snapshot) {
        let busy = snapshot.sessions.filter { $0.status == .busy }.count
        let kittens = snapshot.sessions.reduce(0) { $0 + $1.subagents.count }
        var text = "고양이 \(snapshot.sessions.count)마리 · 작업 중 \(busy)"
        if kittens > 0 { text += " · 새끼 \(kittens)" }
        summaryText = text
        renderSummary()

        if let warning = Self.healthWarning(snapshot.health) {
            healthItem.title = warning
            healthItem.isHidden = false
        } else {
            healthItem.isHidden = true
        }
    }

    /// 세션 수집 상태를 한 줄로. 정상이면 nil(줄을 숨긴다).
    ///
    /// 이 앱은 `~/.claude` 의 문서화되지 않은 구조에 기대므로 Claude Code 업데이트로 조용히
    /// 깨질 수 있다. 그때 "정말 세션이 없다"와 "파일은 있는데 못 읽었다"가 똑같이
    /// "고양이 0마리"로 보이면 사용자가 알아차릴 방법이 없다.
    ///
    /// 반대로 죽은 pid·비대화형만 있어서 0마리인 건 정상이라 아무것도 띄우지 않는다 —
    /// 늘 떠 있는 경고는 아무도 안 읽는다.
    static func healthWarning(_ health: CollectorHealth) -> String? {
        if health.readNothing {
            return "⚠️ 세션 파일 \(health.sessionFiles)개를 읽지 못함 — Claude Code 구조가 바뀌었을 수 있음"
        }
        if health.failures > 0 {
            return "⚠️ 세션 파일 \(health.failures)개 읽기 실패"
        }
        return nil
    }

    // MARK: - 업데이트

    /// `Updater` 상태를 메뉴에 그대로 옮긴다. 상태가 바뀔 때마다 불린다.
    private func renderUpdate() {
        versionItem.title = updater.stamp.summary
        updateItem.title = updater.menuTitle
        updateItem.isEnabled = updater.isActionable
        autoUpdateItem.state = updater.autoCheckEnabled ? .on : .off
        // 도는 중에 자동 확인을 껐다 켜 봐야 지금 도는 일을 못 멈춘다 — 끝날 때까지 잠근다.
        autoUpdateItem.isEnabled = !updater.isInstalling
        setBadge(updater.hasUpdate)
        renderSummary()
    }

    /// 업데이트 중에는 요약 줄이 진행 표시를 맡는다(빌드가 분 단위라 아무 말도 없으면 멈춘 줄 안다).
    private func renderSummary() {
        summaryItem.title = updater.isInstalling ? "업데이트 중… (빌드)" : summaryText
    }

    /// 받을 게 있다는 표시. 커스텀 이미지 대신 아이콘 옆에 점 하나를 붙인다.
    /// 글자를 붙이면 `squareLength` 로는 잘리므로 길이도 같이 바꾼다.
    private func setBadge(_ show: Bool) {
        guard let button = item.button else { return }
        if hasIconImage {
            button.title = show ? "•" : ""
            button.imagePosition = show ? .imageLeading : .imageOnly
        } else {
            button.title = show ? "🐱•" : "🐱"
        }
        item.length = show ? NSStatusItem.variableLength : NSStatusItem.squareLength
    }

    /// 확인 결과가 있으면 설치, 없으면 확인. 제목이 그때그때 무엇을 할지 말해 준다.
    @objc private func updateAction() {
        if updater.hasUpdate {
            updater.install()
        } else {
            updater.check(userInitiated: true)
        }
    }

    @objc private func toggleAutoUpdate() {
        updater.autoCheckEnabled = !updater.autoCheckEnabled
        renderUpdate()
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
            // 자동 확인은 반복 타이머 대신 여기에 얹는다 — 앱이 며칠 떠 있어도 폴링 틱에는
            // 비용이 0이고, 메뉴를 열었을 때 마지막 확인이 하루보다 오래됐으면 그때 한 번 본다.
            updater.checkIfDue()
        }
    }
}
