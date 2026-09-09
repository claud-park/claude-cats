import Foundation

/// 업데이트 확인 결과 한 가지.
public enum UpdateStatus: Equatable, Sendable {
    /// origin 과 같거나 우리가 앞서 있다. 할 일 없음.
    case upToDate
    /// origin 이 `commits` 개 앞서 있고 그대로 당길 수 있다. `latestSubject` 는 origin 최신 커밋 제목.
    case behind(commits: Int, latestSubject: String)
    /// 번들에 소스 저장소가 안 박혀 있거나 그 자리에 `.git` 이 없다(tarball 로 받았거나 저장소를 옮겼다).
    case notAGitRepo
    /// 브랜치 없이(detached HEAD) 빌드된 번들. 어느 브랜치를 따라갈지 알 수 없다.
    case detachedHead
    /// git 이 실패했다 — 네트워크·인증·저장소 문제. 사람이 읽을 이유 한 줄.
    case offline(String)
    /// 뒤처져 있는데 작업 트리가 더럽다. `--ff-only` pull 이 로컬 변경을 밟을 수 있어 손대지 않는다.
    case dirtyTree
}

/// 소스에서 자기 자신을 업데이트할 때 필요한 **순수 판정**들.
///
/// 프로세스 실행(`git fetch` 등)은 앱 타깃(`Updater`)이 하고, 여기서는 그 출력만 읽는다 —
/// 그래야 "3개 뒤처졌는데 트리가 더럽다" 같은 조합을 네트워크 없이 테스트할 수 있다.
public enum UpdateCheck {
    /// `scripts/bundle.sh` 가 못 알아낸 값에 박아 두는 표시.
    public static let unknown = "unknown"

    /// 번들 스탬프만 보고 "업데이트를 시도해도 되는가"를 정한다. 안 되면 그 이유, 되면 nil.
    ///
    /// 여기서 걸러야 없는 저장소에 대고 `fetch` 하거나, 어느 브랜치를 따라갈지도 모르는 채
    /// `pull` 을 부르는 일이 없다.
    public static func stampProblem(
        repoRoot: String,
        branch: String,
        gitDirExists: Bool
    ) -> UpdateStatus? {
        let root = repoRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty, root != unknown, gitDirExists else { return .notAGitRepo }
        let name = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        // 빌드 당시 detached HEAD 였으면 bundle.sh 가 `HEAD` 를 박는다.
        guard !name.isEmpty, name != unknown, name != "HEAD" else { return .detachedHead }
        return nil
    }

    /// `git rev-list --count` 에 넘길 구간.
    ///
    /// 기준은 저장소 HEAD 가 아니라 **지금 도는 번들의 커밋**이다. 둘은 갈라질 수 있다 —
    /// pull 은 됐는데 빌드가 깨져서 앱이 옛 커밋 그대로인 경우가 그렇다. HEAD 를 기준으로
    /// 세면 그때 "최신"이라고 말해 버리고, 사용자는 낡은 앱을 든 채 다시는 안내를 못 받는다.
    /// 스탬프를 모르는 번들(개발 빌드)일 때만 HEAD 로 물러선다.
    public static func revListRange(bundleCommit: String, branch: String) -> String {
        let commit = bundleCommit.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = commit.isEmpty || commit == unknown ? "HEAD" : commit
        return "\(base)..origin/\(branch)"
    }

    /// `git rev-list --count HEAD..origin/<branch>` · `git log -1 --format=%s origin/<branch>` ·
    /// `git status --porcelain` 의 출력을 상태 하나로 접는다.
    ///
    /// 판정 순서에 뜻이 있다.
    /// 1. 개수를 못 읽으면 `.offline` — git 이 뭔가 다른 말을 했다는 뜻이라 그 말을 그대로 올린다.
    /// 2. 0개면 `.upToDate` — **트리가 더러워도** 그렇다. 당길 게 없는데 "로컬 변경 있음"을
    ///    띄우면 평소 작업 중인 저장소에서 늘 켜져 있는 경고가 된다.
    /// 3. 당길 게 있는데 더러우면 `.dirtyTree`. 로컬 변경 위로 pull 하는 일은 없다.
    public static func status(
        revListCount: String,
        logLine: String?,
        statusPorcelain: String
    ) -> UpdateStatus {
        let countText = revListCount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let commits = Int(countText) else {
            return .offline(countText.isEmpty ? "git rev-list 가 아무것도 내놓지 않았다" : countText)
        }
        guard commits > 0 else { return .upToDate }
        guard statusPorcelain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .dirtyTree
        }
        let subject = (logLine ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return .behind(commits: commits, latestSubject: subject)
    }

    /// 새로 빌드한 번들을 어디에 놓을지. **지금 돌고 있는 자리**가 답이다 —
    /// `/Applications` 에서 돌고 있으면 `/Applications`, `<repo>/dist` 에서 돌고 있으면 그 `dist`.
    ///
    /// 번들이 아닌 채로 돌고 있으면(`.build/debug/ClaudeCats` 직접 실행) 놓을 "자리"가 없다.
    /// 그때는 `<repo>/dist` 로 보낸다 — 어차피 빌드가 거기에 만든다.
    public static func targetInstallDir(runningBundlePath: String, repoRoot: String) -> String {
        let bundle = normalized(runningBundlePath)
        let fallback = normalized(repoRoot) + "/dist"
        guard bundle.hasSuffix(".app") else { return fallback }
        let parent = (bundle as NSString).deletingLastPathComponent
        return parent.isEmpty || parent == "/" ? fallback : parent
    }

    /// 뒤에 붙은 `/` 만 뗀다. `standardizingPath` 는 안 쓴다 — `/private` 접두사를 멋대로
    /// 접었다 폈다 해서 임시 디렉터리 경로를 없는 경로로 바꿔 놓는다.
    private static func normalized(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }
}
