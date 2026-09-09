import Testing
@testable import ClaudeCatsCore

@Suite struct UpdateCheckTests {
    // MARK: - status

    @Test func zeroCommitsIsUpToDate() {
        #expect(UpdateCheck.status(revListCount: "0", logLine: "무슨 커밋", statusPorcelain: "") == .upToDate)
    }

    @Test func trailingNewlineIsIgnored() {
        #expect(UpdateCheck.status(revListCount: "0\n", logLine: nil, statusPorcelain: "\n") == .upToDate)
    }

    @Test func commitsAheadAreReported() {
        let status = UpdateCheck.status(
            revListCount: "3\n",
            logLine: "feat(menu): 업데이트 항목을 붙인다\n",
            statusPorcelain: ""
        )
        #expect(status == .behind(commits: 3, latestSubject: "feat(menu): 업데이트 항목을 붙인다"))
    }

    @Test func missingSubjectStillCountsAsBehind() {
        #expect(UpdateCheck.status(revListCount: "1", logLine: nil, statusPorcelain: "") == .behind(commits: 1, latestSubject: ""))
    }

    /// 로컬 변경 위로 pull 하지 않는다 — 뒤처졌어도 트리가 더러우면 손을 뗀다.
    @Test func dirtyTreeBlocksAnUpdate() {
        let status = UpdateCheck.status(
            revListCount: "2",
            logLine: "무슨 커밋",
            statusPorcelain: " M Sources/ClaudeCats/StatusMenu.swift\n?? 새파일.txt\n"
        )
        #expect(status == .dirtyTree)
    }

    /// 당길 게 없으면 더러워도 조용하다. 안 그러면 작업 중인 저장소에서 경고가 늘 켜져 있다.
    @Test func dirtyTreeIsQuietWhenNothingToPull() {
        let status = UpdateCheck.status(
            revListCount: "0",
            logLine: nil,
            statusPorcelain: " M Sources/ClaudeCats/StatusMenu.swift\n"
        )
        #expect(status == .upToDate)
    }

    @Test func unreadableCountIsOffline() {
        let status = UpdateCheck.status(
            revListCount: "fatal: bad revision 'HEAD..origin/없는브랜치'",
            logLine: nil,
            statusPorcelain: ""
        )
        #expect(status == .offline("fatal: bad revision 'HEAD..origin/없는브랜치'"))
    }

    @Test func emptyCountIsOfflineWithOurOwnReason() {
        #expect(UpdateCheck.status(revListCount: "  \n", logLine: nil, statusPorcelain: "") == .offline("git rev-list 가 아무것도 내놓지 않았다"))
    }

    // MARK: - stampProblem

    @Test func stampedRepoWithGitDirIsUsable() {
        #expect(UpdateCheck.stampProblem(repoRoot: "/Users/nobody/claude-cats", branch: "main", gitDirExists: true) == nil)
    }

    @Test func unstampedRepoIsNotAGitRepo() {
        #expect(UpdateCheck.stampProblem(repoRoot: "unknown", branch: "main", gitDirExists: true) == .notAGitRepo)
        #expect(UpdateCheck.stampProblem(repoRoot: "  ", branch: "main", gitDirExists: true) == .notAGitRepo)
    }

    /// 저장소를 옮기거나 지웠다. 없는 자리에 대고 fetch 하지 않는다.
    @Test func missingGitDirIsNotAGitRepo() {
        #expect(UpdateCheck.stampProblem(repoRoot: "/Users/nobody/claude-cats", branch: "main", gitDirExists: false) == .notAGitRepo)
    }

    /// bundle.sh 는 detached HEAD 에서 브랜치 이름 대신 `HEAD` 를 박는다.
    @Test func detachedHeadStampCannotBeFollowed() {
        #expect(UpdateCheck.stampProblem(repoRoot: "/Users/nobody/claude-cats", branch: "HEAD", gitDirExists: true) == .detachedHead)
        #expect(UpdateCheck.stampProblem(repoRoot: "/Users/nobody/claude-cats", branch: "unknown", gitDirExists: true) == .detachedHead)
        #expect(UpdateCheck.stampProblem(repoRoot: "/Users/nobody/claude-cats", branch: "", gitDirExists: true) == .detachedHead)
    }

    /// 저장소부터 본다 — 저장소를 모르면 브랜치가 뭐든 상관없다.
    @Test func repoProblemWinsOverBranchProblem() {
        #expect(UpdateCheck.stampProblem(repoRoot: "unknown", branch: "HEAD", gitDirExists: false) == .notAGitRepo)
    }

    // MARK: - revListRange

    /// 기준은 저장소 HEAD 가 아니라 **번들이 박고 나온 커밋**이다. pull 은 됐는데 빌드가
    /// 깨진 뒤에도 다음 확인에서 다시 "뒤처짐"이 나와야 한다.
    @Test func rangeIsMeasuredFromTheRunningBundlesCommit() {
        #expect(UpdateCheck.revListRange(bundleCommit: "a315cac", branch: "main") == "a315cac..origin/main")
    }

    @Test func unknownCommitFallsBackToHead() {
        #expect(UpdateCheck.revListRange(bundleCommit: "unknown", branch: "main") == "HEAD..origin/main")
        #expect(UpdateCheck.revListRange(bundleCommit: "", branch: "main") == "HEAD..origin/main")
    }

    @Test func branchWithSlashesSurvives() {
        #expect(UpdateCheck.revListRange(bundleCommit: "88a6fa4", branch: "feat/self-update") == "88a6fa4..origin/feat/self-update")
    }

    // MARK: - targetInstallDir

    @Test func installedAppUpdatesInPlace() {
        let dir = UpdateCheck.targetInstallDir(
            runningBundlePath: "/Applications/ClaudeCats.app",
            repoRoot: "/Users/nobody/claude-cats"
        )
        #expect(dir == "/Applications")
    }

    @Test func distBundleUpdatesInPlace() {
        let dir = UpdateCheck.targetInstallDir(
            runningBundlePath: "/Users/nobody/claude-cats/dist/ClaudeCats.app",
            repoRoot: "/Users/nobody/claude-cats"
        )
        #expect(dir == "/Users/nobody/claude-cats/dist")
    }

    @Test func anyOtherBundleUpdatesInItsOwnFolder() {
        let dir = UpdateCheck.targetInstallDir(
            runningBundlePath: "/Users/nobody/Desktop/도구/ClaudeCats.app/",
            repoRoot: "/Users/nobody/claude-cats"
        )
        #expect(dir == "/Users/nobody/Desktop/도구")
    }

    /// 번들 없이 도는 개발 빌드(`.build/debug/ClaudeCats`)에는 "제자리"가 없다 — dist 로 보낸다.
    @Test func nonBundleFallsBackToDist() {
        let dir = UpdateCheck.targetInstallDir(
            runningBundlePath: "/Users/nobody/claude-cats/.build/debug",
            repoRoot: "/Users/nobody/claude-cats/"
        )
        #expect(dir == "/Users/nobody/claude-cats/dist")
    }

    @Test func rootLevelBundleFallsBackToDist() {
        let dir = UpdateCheck.targetInstallDir(
            runningBundlePath: "/ClaudeCats.app",
            repoRoot: "/Users/nobody/claude-cats"
        )
        #expect(dir == "/Users/nobody/claude-cats/dist")
    }
}
