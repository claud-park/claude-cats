import AppKit
import ClaudeCatsCore
import IOKit.ps

/// 시스템 알림을 PowerState 로 모은다. 상태가 바뀔 때만 onChange 를 부른다.
///
/// 배터리↔전원 전환은 IOKit 런루프 콜백 대신 폴링 틱에서 확인한다.
/// 다만 확인 자체는 collector 큐에서 일어나고(`isOnBattery()` 는 nonisolated),
/// 값이 바뀐 틱에만 `setOnBattery(_:)` 로 메인에 넘어온다 — 틱마다 메인을 깨우지 않는다.
/// 슬립/잠금에서 복귀할 때는 폴링이 멈춰 있었으므로 `refreshPowerSource()` 로 즉시 재확인한다.
@MainActor
final class PowerMonitor {
    private(set) var state: PowerState
    var onChange: ((PowerState) -> Void)?
    private var observers: [Any] = []

    init() {
        state = PowerState(
            onBattery: Self.isOnBattery(),
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        subscribe()
    }

    func setPaused(_ paused: Bool) {
        update {
            $0.userPaused = paused
            // 일시정지 중에는 타이머가 없어 배터리 감시도 멈춘다. 재개할 때 같은 update 안에서
            // 다시 읽어, 재개 직후 한 틱 동안 옛 값으로 도는 일을 없앤다.
            if !paused { Self.applyPowerSource(to: &$0) }
        }
    }

    /// 폴링 틱에서 배터리 값이 바뀌었을 때만 호출된다(AppController.onPowerSourceChange).
    func setOnBattery(_ onBattery: Bool) {
        update { $0.onBattery = onBattery }
    }

    /// 배터리/저전력을 지금 다시 읽는다. 폴링이 멈춰 있던 구간(슬립·잠금) 복귀 직후용.
    func refreshPowerSource() {
        update { Self.applyPowerSource(to: &$0) }
    }

    /// 지금 읽은 배터리·저전력 값을 밀어넣는다. update 블록 안에서만 쓴다 —
    /// 플래그 변경과 한 번의 update 로 묶어 onChange(= setMode) 가 두 번 나가지 않게.
    private nonisolated static func applyPowerSource(to state: inout PowerState) {
        state.onBattery = isOnBattery()
        state.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// collector 큐에서도 불린다 — 메인 격리를 요구하지 않는다.
    nonisolated static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {
            return false
        }
        return (type as String) == kIOPSBatteryPowerValue
    }

    private func update(_ change: @MainActor (inout PowerState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        state = next
        onChange?(next)
    }

    private func subscribe() {
        let ws = NSWorkspace.shared.notificationCenter
        let dc = DistributedNotificationCenter.default()
        let nc = NotificationCenter.default

        // refreshPower: 폴링이 멈춰 있던 구간에서 배터리가 바뀌었을 수 있는 복귀 알림.
        // 플래그 변경과 전원 재확인을 **한 번의 update** 로 묶는다 — 따로 부르면
        // onChange 가 두 번 나가 setMode 와 콜드 스캔이 두 번씩 돈다.
        func on(
            _ center: NotificationCenter,
            _ name: Notification.Name,
            refreshPower: Bool = false,
            _ change: @escaping @MainActor (inout PowerState) -> Void
        ) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.update { state in
                        change(&state)
                        if refreshPower { Self.applyPowerSource(to: &state) }
                    }
                }
            }
            observers.append(token)
        }

        on(ws, NSWorkspace.screensDidSleepNotification) { $0.displayAsleep = true }
        on(ws, NSWorkspace.screensDidWakeNotification, refreshPower: true) { $0.displayAsleep = false }
        on(ws, NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        on(ws, NSWorkspace.didWakeNotification, refreshPower: true) { $0.systemAsleep = false }
        on(dc, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        on(dc, Notification.Name("com.apple.screenIsUnlocked"), refreshPower: true) { $0.screenLocked = false }
        on(dc, Notification.Name("com.apple.screensaver.didstart")) { $0.screenLocked = true }
        on(dc, Notification.Name("com.apple.screensaver.didstop")) { $0.screenLocked = false }
        on(nc, .NSProcessInfoPowerStateDidChange) { $0.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }
}
