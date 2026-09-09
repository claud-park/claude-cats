import Foundation

/// 외부 명령 하나를 돌리고 결과를 모은다. **백그라운드 큐에서만** 부를 것.
///
/// 예전 구현(`Updater` 안의 사설 `Shell`)은 파이프를 직접 `availableData` 로 EOF 까지 읽고
/// **그다음에** `waitUntilExit()` 를 불렀다. 문제는 EOF 가 **모든** 쓰기 끝이 닫혀야 온다는
/// 것이다 — `git` 이 뒤에 남긴 손자(ssh 멀티플렉스 마스터, `gc --auto`/`maintenance` 등)가
/// 합쳐진 파이프의 쓰기 끝을 붙들고 있으면, 정작 `git` 은 끝났는데도 읽기 루프가 EOF 를 못 봐서
/// 감시 타임아웃까지 매달렸다(설치는 15분).
///
/// 그래서 여기서는 **자식 프로세스의 종료**에 걸고 기다린다(파이프 EOF 가 아니라). 출력은
/// non-blocking + `DispatchSource` 로 흘려 읽어서, 자식이 끝나면 손자가 파이프를 계속 붙들고
/// 있어도 곧바로 결과를 낸다. 설치 로그 실시간 흘리기(`onOutput`)도 그대로 된다.
public enum ProcessRunner {
    public struct Result: Sendable {
        public var status: Int32
        /// stdout·stderr 합본(끝에서 `outputLimit` 까지). 순서 보존을 위해 파이프 하나를 같이 쓴다.
        public var output: String
        public var timedOut: Bool

        public init(status: Int32, output: String, timedOut: Bool) {
            self.status = status
            self.output = output
            self.timedOut = timedOut
        }
    }

    /// 크기 상한이 걸린 스레드 안전 출력 버퍼.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private let limit: Int
        init(limit: Int) { self.limit = limit }
        func append(_ chunk: Data) {
            lock.withLock {
                data.append(chunk)
                if data.count > limit { data = Data(data.suffix(limit)) }
            }
        }
        var string: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
    }

    /// - Parameters:
    ///   - executable: 절대 경로가 아니면 `PATH`(environment 의 것)에서 찾는다(`/usr/bin/env`).
    ///   - environment: 자식에게 그대로 넘길 환경 전체.
    ///   - timeout: 이 시간이 지나도 자식이 안 끝나면 프로세스 그룹째 SIGTERM.
    ///   - onOutput: 읽는 족족 불린다(설치 로그용). 내부 IO 큐에서 실행된다.
    public static func run(
        executable: String,
        arguments: [String],
        cwd: String?,
        environment: [String: String],
        timeout: TimeInterval,
        outputLimit: Int = 64 * 1024,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) -> Result {
        let process = Process()
        // 절대 경로가 아니면 PATH 에서 찾는다(`/usr/bin/env` 가 그 일을 한다).
        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        // 종료 신호. terminationHandler 는 파이프와 무관하게 자식이 죽으면 온다.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return Result(status: -1, output: "\(executable) 실행 실패: \(error.localizedDescription)", timedOut: false)
        }

        // 자식을 자기 프로세스 그룹의 리더로 만든다. 그래야 타임아웃에서 **손자까지** 같이
        // 내릴 수 있다. 부모·자식 양쪽이 부르는 표준 관용구라 어느 쪽이 먼저 도착해도 된다.
        let childPid = process.processIdentifier
        _ = setpgid(childPid, childPid)

        // 읽기 끝을 dup 해서 DispatchSource 에 준다. 원본 FileHandle 은 Pipe 가 dealloc 때
        // 닫고, dup 한 fd 는 우리가 cancel handler 에서 닫는다 — 같은 fd 를 두 번 닫지 않는다.
        let readFD = dup(pipe.fileHandleForReading.fileDescriptor)
        let existingFlags = fcntl(readFD, F_GETFL)
        _ = fcntl(readFD, F_SETFL, existingFlags | O_NONBLOCK)

        let collector = Collector(limit: outputLimit)
        let ioQueue = DispatchQueue(label: "claude-cats.process-runner.io")

        @Sendable func drain() {
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let n = buffer.withUnsafeMutableBytes { read(readFD, $0.baseAddress, $0.count) }
                if n > 0 {
                    let chunk = Data(buffer[0..<n])
                    onOutput?(String(decoding: chunk, as: UTF8.self))
                    collector.append(chunk)
                } else {
                    break // 0(EOF) 또는 -1(EAGAIN) — 지금 읽을 게 없다.
                }
            }
        }

        let readSource = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: ioQueue)
        readSource.setEventHandler(handler: drain)
        readSource.setCancelHandler { close(readFD) }
        readSource.resume()

        // 자식 **종료**에 건다(파이프 EOF 가 아니라). 시간이 넘으면 그룹째 SIGTERM.
        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            // 리더가 된 게 확인될 때만 그룹째 내린다. setpgid 가 실패했다면 자식은 아직 우리
            // 그룹에 있고, 그때 kill(-그룹) 은 앱 자신을 죽인다.
            if getpgid(childPid) == childPid {
                kill(-childPid, SIGTERM)
            } else {
                process.terminate()
            }
            timedOut = true
            exited.wait() // SIGTERM 뒤 곧 끝난다.
        }

        // 자식은 끝났다. 파이프에 남아 있던 출력을 한 번 더 훑어 담고 소스를 닫는다.
        // 손자가 파이프를 붙들고 있어도 EOF 를 기다리지 않는다 — 이게 이 클래스 버그의 핵심 수정.
        ioQueue.sync { drain() }
        readSource.cancel()

        return Result(
            status: process.terminationStatus,
            output: collector.string,
            // 우리가 죽인 것 말고 시그널로 죽을 일은 거의 없다.
            timedOut: timedOut || process.terminationReason == .uncaughtSignal
        )
    }
}
