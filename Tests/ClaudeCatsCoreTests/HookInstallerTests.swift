import Testing
import Foundation
@testable import ClaudeCatsCore

@Suite struct HookInstallerTests {
    let command = "'/Users/me/Library/Application Support/ClaudeCats/claude-cats-hook.sh'"

    /// 사용자가 이미 쓰고 있는 훅. 우리 손이 여기 닿으면 안 된다.
    var otherHooks: [String: Any] {
        [
            "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "lint.sh"]]]],
            "SubagentStop": [["hooks": [["type": "command", "command": "notify.sh", "timeout": 30]]]],
            "Notification": [["matcher": "auth_success",
                              "hooks": [["type": "command", "command": "say hi"]]]],
        ]
    }

    /// 딕셔너리 두 개를 정렬된 JSON 으로 직렬화해 바이트로 비교한다(`[String: Any]` 는 Equatable 이 아니다).
    /// 문자열 같은 조각도 비교할 수 있게 한 겹 싸서 직렬화한다(JSON 최상위는 객체여야 한다).
    func bytes(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["v": value], options: [.sortedKeys])) ?? Data()
    }

    func same(_ lhs: Any, _ rhs: Any) -> Bool {
        bytes(lhs) == bytes(rhs) && !bytes(lhs).isEmpty
    }

    /// 이벤트 하나에서 우리 command 를 가진 그룹들.
    func ourGroups(_ settings: [String: Any], _ event: String) -> [[String: Any]] {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        let groups = hooks[event] as? [[String: Any]] ?? []
        return groups.filter { group in
            (group["hooks"] as? [[String: Any]] ?? [])
                .contains { ($0["command"] as? String) == command }
        }
    }

    // MARK: - 설치

    @Test func installOnFreshSettingsAddsAllFourEvents() throws {
        let out = try HookInstaller.install(into: [:], command: command)
        let hooks = try #require(out["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == ["Notification", "SubagentStart", "SubagentStop", "UserPromptSubmit"])
        for entry in HookInstaller.entries {
            let group = try #require(ourGroups(out, entry.event).first)
            #expect(group["matcher"] as? String == entry.matcher)
            let hook = try #require((group["hooks"] as? [[String: Any]])?.first)
            #expect(hook["type"] as? String == "command")
            #expect(hook["command"] as? String == command)
            #expect(hook["timeout"] as? Int == 5)
        }
    }

    @Test func installKeepsOtherKeysAndOtherHooksByteForByte() throws {
        let settings: [String: Any] = ["model": "opus", "permissions": ["allow": ["Bash"]],
                                       "hooks": otherHooks]
        let out = try HookInstaller.install(into: settings, command: command)
        #expect(same(out["model"]!, "opus"))
        #expect(same(out["permissions"]!, settings["permissions"]!))
        let hooks = try #require(out["hooks"] as? [String: Any])
        // 우리가 안 건드리는 이벤트는 통째로 그대로다.
        #expect(same(hooks["PreToolUse"]!, otherHooks["PreToolUse"]!))
        // 우리가 항목을 더한 이벤트도 **기존 그룹은** 그대로 앞에 남는다.
        for event in ["SubagentStop", "Notification"] {
            let groups = try #require(hooks[event] as? [[String: Any]])
            let original = otherHooks[event] as! [[String: Any]]
            #expect(groups.count == 2)
            #expect(same(groups[0], original[0]))
        }
    }

    @Test func installIsIdempotent() throws {
        let once = try HookInstaller.install(into: ["hooks": otherHooks], command: command)
        let twice = try HookInstaller.install(into: once, command: command)
        #expect(same(once, twice))
        #expect(ourGroups(twice, "Notification").count == 1)
    }

    @Test func isInstalledNeedsEveryEvent() throws {
        #expect(HookInstaller.isInstalled(in: [:], command: command) == false)
        #expect(HookInstaller.isInstalled(in: ["hooks": otherHooks], command: command) == false)
        var out = try HookInstaller.install(into: [:], command: command)
        #expect(HookInstaller.isInstalled(in: out, command: command))
        // 한 이벤트만 빠져도 "설치 안 됨" 이다.
        var hooks = out["hooks"] as! [String: Any]
        hooks["UserPromptSubmit"] = nil
        out["hooks"] = hooks
        #expect(HookInstaller.isInstalled(in: out, command: command) == false)
        // 다른 command 로는 우리 것이 아니다.
        #expect(HookInstaller.isInstalled(in: out, command: "other.sh") == false)
    }

    @Test func isInstalledOnMalformedSettingsIsFalseAndDoesNotThrow() {
        #expect(HookInstaller.isInstalled(in: ["hooks": "nope"], command: command) == false)
        #expect(HookInstaller.isInstalled(in: ["hooks": ["Notification": 3]], command: command) == false)
    }

    // MARK: - 제거

    @Test func removeLeavesOtherHooksAlone() throws {
        let settings: [String: Any] = ["model": "opus", "hooks": otherHooks]
        let installed = try HookInstaller.install(into: settings, command: command)
        let out = try HookInstaller.remove(from: installed, command: command)
        #expect(same(out, settings))
    }

    @Test func removeDropsOnlyOurHookFromAMixedGroup() throws {
        // 한 그룹 안에 남의 훅과 우리 훅이 같이 있는 경우.
        let mixed: [String: Any] = ["hooks": [
            "UserPromptSubmit": [[
                "matcher": "",
                "hooks": [["type": "command", "command": "theirs.sh"],
                          ["type": "command", "command": command, "timeout": 5]],
            ]],
        ]]
        let out = try HookInstaller.remove(from: mixed, command: command)
        let groups = try #require((out["hooks"] as? [String: Any])?["UserPromptSubmit"] as? [[String: Any]])
        #expect(groups.count == 1)
        let list = try #require(groups[0]["hooks"] as? [[String: Any]])
        #expect(list.count == 1)
        #expect(list[0]["command"] as? String == "theirs.sh")
        #expect(groups[0]["matcher"] as? String == "")
    }

    @Test func removeWhenNotInstalledIsNoOp() throws {
        let settings: [String: Any] = ["model": "opus", "hooks": otherHooks]
        #expect(same(try HookInstaller.remove(from: settings, command: command), settings))
        #expect(same(try HookInstaller.remove(from: [:], command: command), [:]))
        #expect(same(try HookInstaller.remove(from: ["model": "opus"], command: command),
                     ["model": "opus"]))
    }

    /// 우리가 만든 항목만 있던 설정은 켜기 전 모습(= hooks 키 없음)으로 돌아간다.
    @Test func removeCleansUpEmptyEventsAndHooksKey() throws {
        let installed = try HookInstaller.install(into: ["model": "opus"], command: command)
        let out = try HookInstaller.remove(from: installed, command: command)
        #expect(out["hooks"] == nil)
        #expect(same(out, ["model": "opus"]))
    }

    // MARK: - 이상한 설정

    @Test func malformedHooksTreeThrowsAndChangesNothing() {
        let broken: [String: Any] = ["hooks": "nope"]
        #expect(throws: HookInstaller.MalformedSettings(path: "hooks")) {
            _ = try HookInstaller.install(into: broken, command: command)
        }
        #expect(throws: HookInstaller.MalformedSettings(path: "hooks")) {
            _ = try HookInstaller.remove(from: broken, command: command)
        }
    }

    @Test func malformedEventListThrows() {
        let broken: [String: Any] = ["hooks": ["Notification": ["not", "groups"]]]
        #expect(throws: HookInstaller.MalformedSettings(path: "hooks.Notification")) {
            _ = try HookInstaller.install(into: broken, command: command)
        }
    }

    @Test func malformedInnerHookListThrowsOnRemove() {
        let broken: [String: Any] = ["hooks": ["SubagentStart": [["matcher": "", "hooks": "nope"]]]]
        #expect(throws: HookInstaller.MalformedSettings(path: "hooks.SubagentStart[0].hooks")) {
            _ = try HookInstaller.remove(from: broken, command: command)
        }
    }

    /// 우리가 안 건드리는 이벤트가 망가져 있어도 설치는 된다 — 남의 설정을 판정하지 않는다.
    @Test func malformedUnrelatedEventDoesNotBlockInstall() throws {
        let out = try HookInstaller.install(into: ["hooks": ["PreToolUse": "weird"]], command: command)
        #expect(HookInstaller.isInstalled(in: out, command: command))
        #expect((out["hooks"] as? [String: Any])?["PreToolUse"] as? String == "weird")
    }
}
