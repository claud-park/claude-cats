import Foundation
import Testing
@testable import ClaudeCatsCore

/// `ProcessRunner` 의 핵심 계약: **자식 프로세스가 끝나면** 곧바로 돌아온다 — 파이프 EOF 를
/// 기다리지 않는다. 손자가 파이프를 붙들고 있어도, 시간이 넘으면 그룹째 죽이고도.
@Suite struct ProcessRunnerTests {
    private static let env: [String: String] = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

    @Test func capturesOutputAndStatus() {
        let r = ProcessRunner.run(
            executable: "/bin/sh", arguments: ["-c", "printf hello; exit 3"],
            cwd: nil, environment: Self.env, timeout: 10
        )
        #expect(r.status == 3)
        #expect(r.output == "hello")
        #expect(r.timedOut == false)
    }

    /// 회귀 테스트(이 버그의 핵심): 자식이 **손자에게 파이프를 물려주고** 곧바로 끝난다.
    /// 예전 구현은 `availableData` 로 EOF 까지 읽어서 손자가 파이프를 놓을 때까지(여기선 5초)
    /// 매달렸다. 새 구현은 자식 종료에 걸므로 즉시 돌아와야 한다.
    @Test func returnsWhenChildExitsEvenIfGrandchildHoldsPipe() {
        let start = Date()
        let r = ProcessRunner.run(
            executable: "/bin/sh",
            // 손자 `sleep 5` 가 stdout(합쳐진 파이프)을 물려받은 채 백그라운드로 남고,
            // 부모 sh 는 바로 끝난다. 파이프의 쓰기 끝은 손자가 5초간 붙들고 있다.
            arguments: ["-c", "printf done; sleep 5 & exit 0"],
            cwd: nil, environment: Self.env, timeout: 30
        )
        let elapsed = Date().timeIntervalSince(start)
        #expect(r.status == 0)
        #expect(r.output == "done")
        #expect(r.timedOut == false)
        // 손자가 5초를 붙들어도 자식이 끝나는 즉시(≈0초) 돌아와야 한다. 넉넉히 3초로 본다.
        #expect(elapsed < 3.0, "자식 종료 뒤 손자의 파이프 때문에 매달렸다: \(elapsed)s")
    }

    @Test func timesOutAndKillsHangingChild() {
        let start = Date()
        let r = ProcessRunner.run(
            executable: "/bin/sh", arguments: ["-c", "sleep 30"],
            cwd: nil, environment: Self.env, timeout: 1
        )
        let elapsed = Date().timeIntervalSince(start)
        #expect(r.timedOut == true)
        #expect(elapsed < 5.0, "타임아웃이 제때 안 걸렸다: \(elapsed)s")
    }

    @Test func streamsOutputLive() {
        let box = LockedText()
        let r = ProcessRunner.run(
            executable: "/bin/sh", arguments: ["-c", "printf a; printf b; printf c"],
            cwd: nil, environment: Self.env, timeout: 10,
            onOutput: { chunk in box.append(chunk) }
        )
        #expect(r.status == 0)
        #expect(box.value == "abc")
    }
}

/// onOutput 이 IO 스레드에서 불리므로 스레드 안전하게 모은다.
private final class LockedText: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ s: String) { lock.withLock { text += s } }
    var value: String { lock.withLock { text } }
}
