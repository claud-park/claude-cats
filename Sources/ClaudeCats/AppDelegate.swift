import AppKit
import ClaudeCatsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 고양이를 그릴 디스플레이 이름. 키가 없으면 자동(메인).
    private static let preferredDisplayKey = "preferredDisplayName"
    /// 창 레벨 선택(`WindowPlacement` raw value). 키가 없으면 `.desktop`.
    private static let windowPlacementKey = "windowPlacement"
    /// 고양이 종류 선택(`CatConcept` raw value). 키가 없으면 `.team`(푹신캣).
    private static let catConceptKey = "catConcept"

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
            }
        )
        menu.setPreferredDisplayName(preferredDisplay)
        menu.setPlacement(placement)
        menu.setConcept(concept)
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
}
