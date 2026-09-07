import AppKit
import ClaudeCatsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        window = DesktopWindow()
        controller = AppController(collector: collector, window: window)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.screenChanged() }
        }

        menu = StatusMenu(
            onPauseToggle: { [weak self] paused in self?.power.setPaused(paused) },
            onRefresh: { [weak self] in self?.controller.pollNow() }
        )
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
