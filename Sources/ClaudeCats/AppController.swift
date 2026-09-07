import AppKit
import ClaudeCatsCore
import os

/// 폴링 타이머를 돌리고 Snapshot → Layout → 창 반영을 잇는다.
@MainActor
final class AppController {
    private let collector: StateCollector
    private let window: DesktopWindow
    private let queue = DispatchQueue(label: "claude-cats.collector", qos: .utility)
    private let log = Logger(subsystem: "claude-cats", category: "controller")
    private var timer: DispatchSourceTimer?
    private var mode: PollingMode = .suspended
    private var lastSnapshot: Snapshot?
    private var lastAnimationsEnabled = false

    var onSnapshot: ((Snapshot) -> Void)?

    init(collector: StateCollector, window: DesktopWindow) {
        self.collector = collector
        self.window = window
    }

    func setMode(_ newMode: PollingMode) {
        guard newMode != mode else { return }
        mode = newMode
        timer?.cancel()
        timer = nil
        log.info("polling mode: \(String(describing: newMode), privacy: .public)")

        if let snapshot = lastSnapshot, lastAnimationsEnabled != newMode.animationsEnabled {
            render(snapshot)
        }

        guard let interval = newMode.interval else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(interval * 1000 / 3))
        )
        // @Sendable 를 명시하지 않으면 클로저가 MainActor 격리를 상속받아
        // utility 큐에서 실행될 때 Swift 6 격리 검사가 트랩한다.
        source.setEventHandler { @Sendable [collector, weak self] in
            let snapshot = Self.collectTimed(collector)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(snapshot) }
            }
        }
        source.resume()
        timer = source
        pollNow()
    }

    func pollNow() {
        queue.async { @Sendable [collector, weak self] in
            let snapshot = Self.collectTimed(collector)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(snapshot) }
            }
        }
    }

    func screenChanged() {
        window.refitToScreen()
        if let snapshot = lastSnapshot { render(snapshot) }
    }

    private nonisolated static func collectTimed(_ collector: StateCollector) -> Snapshot {
        let start = ContinuousClock.now
        let snapshot = collector.collect(now: Date())
        let elapsed = ContinuousClock.now - start
        if elapsed > .milliseconds(200) {
            Logger(subsystem: "claude-cats", category: "controller")
                .warning("slow tick: \(elapsed, privacy: .public)")
        }
        return snapshot
    }

    private func handle(_ snapshot: Snapshot) {
        guard snapshot != lastSnapshot || lastAnimationsEnabled != mode.animationsEnabled else { return }
        render(snapshot)
    }

    private func render(_ snapshot: Snapshot) {
        lastSnapshot = snapshot
        lastAnimationsEnabled = mode.animationsEnabled
        let layout = Scene.layout(snapshot, screenSize: window.screenSize, animationsEnabled: mode.animationsEnabled)
        window.apply(layout)
        onSnapshot?(snapshot)
    }
}
