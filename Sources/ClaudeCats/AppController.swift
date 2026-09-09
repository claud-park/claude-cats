import AppKit
import ClaudeCatsCore
import os

/// 폴링 타이머를 돌리고 Snapshot → Layout → 창 반영을 잇는다.
@MainActor
final class AppController {
    private let collector: StateCollector
    private let window: DesktopWindow
    private let queue = DispatchQueue(label: "claude-cats.collector", qos: .utility)
    /// 둘 다 collector 큐에서만 만진다(ChangeGate 는 직렬 큐 전용).
    private let gate = ChangeGate<Snapshot>()
    private let powerGate = ChangeGate<Bool>()
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

    deinit {
        timer?.cancel()
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
        // 타이머가 없던 동안(슬립·잠금·일시정지) PowerMonitor 가 refreshPowerSource 로
        // 전원을 직접 고쳐 쓸 수 있다 — 게이트는 그걸 모른다. 비워두면 새 타이머의
        // 첫 틱이 무조건 권위 있는 보고가 되어, 게이트가 진짜 변화를 삼키는 일이 없다.
        queue.async { @Sendable [powerGate] in powerGate.reset() }
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
        // 타이머 취소와 메인 큐 도착 사이에 낀 틱. 정지 상태에서 다시 그리면
        // 잠금·슬립 중에 창을 건드린다. 버리면 된다 — 재개할 때 setMode 가 pollNow 를 부른다.
        guard mode != .suspended else { return }
        guard snapshot != lastSnapshot || lastAnimationsEnabled != mode.animationsEnabled else { return }
        render(snapshot)
    }

    private func render(_ snapshot: Snapshot) {
        lastSnapshot = snapshot
        lastAnimationsEnabled = mode.animationsEnabled
        // 창은 화면 전체를 덮지만 배치는 Dock 위에서 시작한다.
        var config = SceneConfig()
        config.bottomInset = window.sceneBottomInset
        let layout = Scene.layout(
            snapshot,
            screenSize: window.screenSize,
            animationsEnabled: mode.animationsEnabled,
            config: config
        )
        window.apply(layout)
        onSnapshot?(snapshot)
    }
}
