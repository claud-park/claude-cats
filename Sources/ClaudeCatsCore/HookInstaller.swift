import Foundation

/// `~/.claude/settings.json` 의 `hooks` 트리에 우리 훅을 넣고 빼는 순수 함수 모음.
///
/// 사용자 파일을 다루므로 규칙은 하나다 — **우리가 넣은 것 말고는 아무것도 건드리지 않는다.**
/// 그래서 `[String: Any]`(JSONSerialization 결과) 위에서 그대로 일하고, 모르는 키·값은
/// 읽지도 고치지도 않고 통과시킨다. 파일 입출력은 앱 쪽 `HookSetup` 이 한다.
public enum HookInstaller {
    /// 설정에서 우리가 만지는 자리가 JSON 스펙과 다르게 생겼을 때. 이때는 아무것도 고치지 않는다.
    public struct MalformedSettings: Error, Equatable {
        /// 문제가 난 자리 (예: `hooks`, `hooks.Notification[0].hooks`).
        public let path: String
        public init(path: String) { self.path = path }
    }

    /// 우리가 심는 훅 (이벤트, matcher). matcher 는 `notification_type` 에 걸리는 정규식이고,
    /// 빈 문자열은 "모두"다.
    public static let entries: [(event: String, matcher: String)] = [
        ("Notification", "permission_prompt|idle_prompt|agent_needs_input"),
        ("SubagentStart", ""),
        ("SubagentStop", ""),
        ("UserPromptSubmit", ""),
    ]

    /// 훅 실행 제한. 기본값 600초를 그대로 두면 훅이 멈췄을 때 Claude 가 오래 붙잡힌다.
    public static let timeout = 5

    // MARK: - 조회

    /// 네 이벤트 **모두**에 우리 command 가 들어 있으면 설치된 것으로 본다.
    /// 형식이 이상하면(우리가 못 읽는 설정) false — 켜기를 다시 시도할 수 있게.
    public static func isInstalled(in settings: [String: Any], command: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return entries.allSatisfy { entry in
            guard let groups = hooks[entry.event] as? [[String: Any]] else { return false }
            return groups.contains { group in commands(of: group).contains(command) }
        }
    }

    // MARK: - 설치

    /// 없는 이벤트만 채운다(멱등). 같은 command 가 이미 어느 그룹에든 있으면 그 이벤트는 건너뛴다.
    ///
    /// **matcher 는 판정에 안 쓴다.** 사용자가 우리 스크립트를 직접 다른 matcher 로 걸어 뒀거나,
    /// 예전 버전이 다른 matcher 로 심어 뒀다면 그 항목을 그대로 인정하고 새로 넣지 않는다.
    /// 같은 command 를 두 번 걸면 이벤트마다 파일이 두 개씩 생겨서(중복 이벤트) 손해만 크다 —
    /// matcher 가 우리 기본값과 달라 알림을 좀 덜 받는 쪽이 훨씬 낫다. 기본 matcher 로 되돌리려면
    /// 껐다가 다시 켜면 된다(`remove` 는 matcher 와 무관하게 우리 command 를 전부 걷어낸다).
    public static func install(into settings: [String: Any], command: String) throws -> [String: Any] {
        var result = settings
        var hooks = try hooksTree(settings)

        for entry in entries {
            var groups = try groupList(hooks, event: entry.event)
            // 규격 검사를 먼저 한다 — 못 읽는 그룹이 섞여 있으면 우리 훅이 이미 있는지 알 수
            // 없고, 그대로 넣으면 조용히 중복이 된다.
            for (index, group) in groups.enumerated() {
                _ = try hookList(group, event: entry.event, index: index)
            }
            if groups.contains(where: { commands(of: $0).contains(command) }) { continue }
            groups.append([
                "matcher": entry.matcher,
                "hooks": [["type": "command", "command": command, "timeout": timeout]],
            ])
            hooks[entry.event] = groups
        }
        result["hooks"] = hooks
        return result
    }

    // MARK: - 제거

    /// 우리 command 만 걷어낸다. 다른 훅과 섞인 그룹은 그 훅만 빼고 남기고,
    /// 우리 것만 있던 그룹은 통째로 지운다. 비게 된 이벤트 키도 지운다.
    /// (`hooks` 자체가 비면 키를 지워, 켜기 전 파일과 같은 모양으로 되돌아간다.)
    public static func remove(from settings: [String: Any], command: String) throws -> [String: Any] {
        guard settings["hooks"] != nil else { return settings }
        var result = settings
        var hooks = try hooksTree(settings)

        for entry in entries {
            guard hooks[entry.event] != nil else { continue }
            let groups = try groupList(hooks, event: entry.event)
            var kept: [[String: Any]] = []
            for (index, group) in groups.enumerated() {
                let list = try hookList(group, event: entry.event, index: index)
                let survivors = list.filter { ($0["command"] as? String) != command }
                if survivors.count == list.count {
                    kept.append(group)                 // 우리 것이 없다 — 그대로 둔다
                } else if !survivors.isEmpty {
                    var trimmed = group                // 섞여 있다 — 우리 훅만 뺀다
                    trimmed["hooks"] = survivors
                    kept.append(trimmed)
                }
            }
            if kept.isEmpty {
                hooks[entry.event] = nil
            } else {
                hooks[entry.event] = kept
            }
        }
        if hooks.isEmpty {
            result["hooks"] = nil
        } else {
            result["hooks"] = hooks
        }
        return result
    }

    // MARK: - 뜯어보기

    private static func hooksTree(_ settings: [String: Any]) throws -> [String: Any] {
        guard let raw = settings["hooks"] else { return [:] }
        guard let hooks = raw as? [String: Any] else { throw MalformedSettings(path: "hooks") }
        return hooks
    }

    private static func groupList(_ hooks: [String: Any], event: String) throws -> [[String: Any]] {
        guard let raw = hooks[event] else { return [] }
        guard let groups = raw as? [[String: Any]] else {
            throw MalformedSettings(path: "hooks.\(event)")
        }
        return groups
    }

    private static func hookList(
        _ group: [String: Any], event: String, index: Int
    ) throws -> [[String: Any]] {
        guard let raw = group["hooks"] else { return [] }
        guard let list = raw as? [[String: Any]] else {
            throw MalformedSettings(path: "hooks.\(event)[\(index)].hooks")
        }
        return list
    }

    /// 그룹 안 훅들의 command 문자열. 형식이 이상하면 빈 배열 — 조회는 절대 던지지 않는다.
    private static func commands(of group: [String: Any]) -> [String] {
        guard let list = group["hooks"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["command"] as? String }
    }
}
