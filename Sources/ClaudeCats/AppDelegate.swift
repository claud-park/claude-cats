import AppKit
import ClaudeCatsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 고양이를 그릴 디스플레이 이름. 키가 없으면 자동(메인).
    private static let preferredDisplayKey = "preferredDisplayName"
    /// 창 레벨 선택(`WindowPlacement` raw value). 키가 없으면 `.desktop`.
    private static let windowPlacementKey = "windowPlacement"
    /// 동물 종류 선택(`CatConcept` raw value). 키가 없으면 `.team`(푹신캣).
    private static let catConceptKey = "catConcept"
    /// Dock 아이콘 표시 여부. 키가 없으면 false(원래대로 메뉴바 전용 accessory).
    /// 노치 MacBook 등 메뉴바가 꽉 차 아이콘이 숨는 환경에서 켜면 Dock 으로 조작한다.
    static let showDockIconKey = "showDockIcon"

    private var window: DesktopWindow!
    private var controller: AppController!
    private var power: PowerMonitor!
    private var menu: StatusMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let collector = StateCollector(
            fileSystem: RealFileSystem(),
            claudeDir: home.appendingPathComponent(".claude")
        )
        let defaults = UserDefaults.standard
        let preferredDisplay = defaults.string(forKey: Self.preferredDisplayKey)
        let placement = WindowPlacement.stored(defaults.string(forKey: Self.windowPlacementKey))
        let concept = CatConcept.stored(defaults.string(forKey: Self.catConceptKey))
        // 첫 렌더 전에 화면을 정해야 Scene 이 그 화면 크기로 배치된다.
        window = DesktopWindow(preferredDisplayName: preferredDisplay, placement: placement, concept: concept)
        controller = AppController(collector: collector, window: window)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.screenChanged() }
        }

        menu = StatusMenu(
            onPauseToggle: { [weak self] paused in self?.power.setPaused(paused) },
            onRefresh: { [weak self] in self?.controller.pollNow() },
            onDisplaySelect: { [weak self] name in
                guard let self else { return }
                if let name {
                    defaults.set(name, forKey: Self.preferredDisplayKey)
                } else {
                    defaults.removeObject(forKey: Self.preferredDisplayKey)
                }
                self.window.setPreferredDisplay(name)
                self.menu.setPreferredDisplayName(name)
                // 화면 크기가 달라졌을 수 있으니 배치를 다시 계산한다.
                self.controller.screenChanged()
            },
            onPlacementSelect: { [weak self] placement in
                guard let self else { return }
                defaults.set(placement.rawValue, forKey: Self.windowPlacementKey)
                self.window.setPlacement(placement)
            },
            onConceptSelect: { [weak self] concept in
                guard let self else { return }
                defaults.set(concept.rawValue, forKey: Self.catConceptKey)
                self.window.setConcept(concept)
            },
            onToggleDockIcon: { [weak self] visible in
                guard let self else { return }
                defaults.set(visible, forKey: Self.showDockIconKey)
                // 런타임에 정책을 바꾸면 Dock 아이콘이 즉시 붙거나 사라진다.
                NSApp.setActivationPolicy(visible ? .regular : .accessory)
                self.menu.setDockIconVisible(visible)
            }
        )
        menu.setPreferredDisplayName(preferredDisplay)
        menu.setPlacement(placement)
        menu.setConcept(concept)
        menu.setDockIconVisible(defaults.bool(forKey: Self.showDockIconKey))
        controller.onSnapshot = { [weak self] snapshot in self?.menu.update(with: snapshot) }

        power = PowerMonitor()
        power.onChange = { [weak self] state in
            self?.controller.setMode(PowerPolicy.mode(for: state))
        }
        // 배터리 확인은 collector 큐에서, 반영은 바뀐 틱에만 메인에서.
        controller.powerSourceCheck = { PowerMonitor.isOnBattery() }
        controller.onPowerSourceChange = { [weak self] onBattery in
            self?.power.setOnBattery(onBattery)
        }
        controller.setMode(PowerPolicy.mode(for: power.state))
    }

    /// Dock 아이콘 우클릭 메뉴. 메뉴바 아이콘이 노치 뒤로 숨어도 여기서 같은 조작을 한다.
    /// `menu` 는 IUO 라 `applicationDidFinishLaunching` 전에 Dock 이 물으면 nil 일 수 있다
    /// (이전에 Dock 을 켠 사용자는 시작 직후 아이콘이 뜬다). nil 이면 기본 Dock 메뉴로 폴백.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        menu?.dockMenu
    }
}
