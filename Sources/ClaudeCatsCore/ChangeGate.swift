import Foundation

/// 값이 바뀐 틱만 통과시키는 문지기. 변화 없는 폴링이 하류(메인 큐)를 깨우지 않게 막는다.
///
/// **스레드 안전하지 않다.** 내부 상태를 잠금 없이 들고 있으므로 하나의 직렬 큐에서만
/// 만지고, 그 큐 밖에서는 절대 건드리지 않는다 — 그 전제로 `@unchecked Sendable` 이다.
public final class ChangeGate<Value: Equatable & Sendable>: @unchecked Sendable {
    private var last: Value?

    public init() {}

    /// 직전에 통과시킨 값과 다르면(또는 아직 아무것도 없으면) 기록하고 true.
    public func shouldSend(_ value: Value) -> Bool {
        guard value != last else { return false }
        last = value
        return true
    }

    /// 게이트를 우회해 보낼 때 기준값만 맞춰둔다.
    public func record(_ value: Value) {
        last = value
    }

    /// 기억을 비워 다음 값을 무조건 통과시킨다.
    public func reset() {
        last = nil
    }
}
