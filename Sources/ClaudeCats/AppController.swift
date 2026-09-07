import AppKit
import ClaudeCatsCore
import os

/// 변화 없는 폴링이 메인 큐를 깨우지 않게 막는 문지기.
/// 모든 접근은 AppController 의 collector 큐 위에서만 일어난다 — 그래서 `@unchecked Sendable`.
private final class SnapshotGate: @unchecked Sendable {
    private var last: Snapshot?

    /// 직전에 보낸 것과 다를 때만 true. collector 큐에서만 호출할 것.
    func shouldSend(_ snapshot: Snapshot) -> Bool {
        guard snapshot != last else { return false }
        last = snapshot
        return true
    }

    /// 게이트를 우회해 보낼 때 상태만 맞춰둔다. collector 큐에서만 호출할 것.
    func record(_ snapshot: Snapshot) {
        last = snapshot
    }
}

/// 전원 소스(배터리/AC)가 바뀐 틱만 골라내는 문지기.
/// SnapshotGate 와 같은 규칙 — collector 큐에서만 접근한다.
private final class PowerSourceGate: @unchecked Sendable {
    private var last: Bool?

    /// 직전 틱과 다를 때만 true. collector 큐에서만 호출할 것.
    func shouldSend(_ onBattery: Bool) -> Bool {
        guard onBattery != last else { return false }
        last = onBattery
        return true
    }
}

/// 폴링 타이머를 돌리고 Snapshot → Layout → 창 반영을 잇는다.
@MainActor
final class AppController {
    private let collector: StateCollector
    private let window: DesktopWindow
    private let queue = DispatchQueue(label: "claude-cats.collector", qos: .utility)
    private let gate = SnapshotGate()
    private let powerGate = PowerSourceGate()
    private let log = Logger(subsystem: "claude-cats", category: "controller")
    private var timer: DispatchSourceTimer?
    private var mode: PollingMode = .suspended
    private var lastSnapshot: Snapshot?
    private var lastAnimationsEnabled = false

    var onSnapshot: ((Snapshot) -> Void)?

    /// 폴링 틱마다 collector 큐에서 호출된다. true = 배터리 구동.
    /// setMode 시점의 값이 타이머에 캡처되므로 setMode 전에 넣어둘 것.
    var powerSourceCheck: (@Sendable () -> Bool)?

    /// 배터리 여부가 **바뀐** 틱에만 메인 큐에서 호출된다.
    var onPowerSourceChange: ((Bool) -> Void)?

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
        let powerCheck = powerSourceCheck
        source.setEventHandler { @Sendable [collector, gate, powerGate, weak self] in
            let snapshot = Self.collectTimed(collector)
            // 배터리도 collector 큐에서 확인하고, 바뀐 틱에만 메인으로 올린다.
            if let powerCheck {
                let onBattery = powerCheck()
                if powerGate.shouldSend(onBattery) {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.onPowerSourceChange?(onBattery) }
                    }
                }
            }
            // 변화 판정을 collector 큐에서 끝내서, 안 바뀌었으면 메인 큐를 아예 깨우지 않는다.
            guard gate.shouldSend(snapshot) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(snapshot) }
            }
        }
        source.resume()
        timer = source
        pollNow()
    }

    /// 수동 갱신. 게이트를 우회해 항상 메인으로 넘긴다(모드 전환·"지금 새로고침" 용).
    /// 최종 렌더 여부는 메인의 `handle(_:)` 이 판단한다.
    func pollNow() {
        queue.async { @Sendable [collector, gate, weak self] in
            let snapshot = Self.collectTimed(collector)
            gate.record(snapshot)   // 우회하더라도 게이트 상태는 맞춰둔다
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
