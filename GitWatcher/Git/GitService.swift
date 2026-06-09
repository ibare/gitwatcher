//
//  GitService.swift
//  GitWatcher
//
//  읽기 전용 질의 레이어. GitRunner 위에서 plumbing 명령을 호출하고 결과를 파싱한다.
//  전부 nonisolated — 무거운 작업은 MainActor 밖에서 돈다.
//

import Foundation

/// 한 리포를 새로고침해 얻은 결과 묶음.
nonisolated struct RepoSnapshot: Sendable {
    var worktrees: [Worktree]
    var commits: [GraphCommit]
    var refs: [GitRef]
    var totalCommits: Int
    var lastCommitDate: Date?
    var trunk: String?
}

nonisolated enum GitService {

    // US(0x1F) 필드 구분자. 제목에 '|' 가 들어가도 안전하게 파싱한다.
    private static let unit = "\u{1f}"

    // MARK: - 리포 전체 스냅샷

    /// 카드 한 장을 채우는 데 필요한 모든 질의를 모아 실행한다.
    nonisolated static func snapshot(repoPath: String) async throws -> RepoSnapshot {
        // worktree 열거 (어떤 리포에서든 ≥1개)
        let wtInfos = try await worktreeList(repoPath: repoPath)
        let trunk = try? await detectTrunk(repoPath: repoPath)

        // 각 worktree 의 라이브 상태를 평탄화 순회
        var worktrees: [Worktree] = []
        for info in wtInfos {
            let status = try await worktreeStatus(worktreePath: info.path)
            var divergence: Divergence? = nil
            // worktree 가 여럿일 때만 divergence 계산 (단일 리포는 의미 적음)
            if wtInfos.count > 1, let trunk, !info.isDetached, info.branch != trunk {
                divergence = try? await self.divergence(repoPath: repoPath, trunk: trunk, branch: info.branch)
            }
            worktrees.append(Worktree(
                path: info.path,
                branch: info.isDetached ? String(info.headSHA.prefix(7)) : info.branch,
                headSHA: info.headSHA,
                isDetached: info.isDetached,
                isMainWorktree: info.isMain,
                status: status,
                divergence: divergence
            ))
        }

        let (commits, total, last) = try await commitLog(repoPath: repoPath)
        let refs = try await refList(repoPath: repoPath)

        return RepoSnapshot(
            worktrees: worktrees,
            commits: commits,
            refs: refs,
            totalCommits: total,
            lastCommitDate: last,
            trunk: trunk
        )
    }

    // MARK: - worktree 열거

    struct WorktreeInfo: Sendable {
        var path: String
        var headSHA: String
        var branch: String
        var isDetached: Bool
        var isMain: Bool
    }

    nonisolated static func worktreeList(repoPath: String) async throws -> [WorktreeInfo] {
        let out = try await GitRunner.run(.worktreeList, ["--porcelain"], in: repoPath)
        var result: [WorktreeInfo] = []
        var cur: (path: String, sha: String, branch: String, detached: Bool)?

        func flush() {
            guard let c = cur else { return }
            result.append(WorktreeInfo(
                path: c.path, headSHA: c.sha, branch: c.branch,
                isDetached: c.detached, isMain: result.isEmpty
            ))
            cur = nil
        }

        for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("worktree ") {
                flush()
                cur = (String(line.dropFirst("worktree ".count)), "", "", false)
            } else if line.hasPrefix("HEAD ") {
                cur?.sha = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                // refs/heads/main → main
                let ref = String(line.dropFirst("branch ".count))
                cur?.branch = ref.replacingOccurrences(of: "refs/heads/", with: "")
            } else if line == "detached" {
                cur?.detached = true
            } else if line.isEmpty {
                flush()
            }
        }
        flush()
        return result
    }

    // MARK: - 워킹트리 상태

    /// status --porcelain=v2 --branch (+ numstat) 로 dirty/변경파일/ins·del 합성.
    nonisolated static func worktreeStatus(worktreePath: String) async throws -> WorktreeStatus {
        let out = try await GitRunner.run(.status, ["--porcelain=v2", "--branch"], in: worktreePath)
        var changed: [ChangedPath] = []

        for raw in out.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if line.hasPrefix("# ") { continue } // 브랜치 헤더는 worktreeList 에서 다룸
            guard let first = line.first else { continue }
            switch first {
            case "1":
                // 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
                if let p = pathAfter(fields: 8, in: line) {
                    changed.append(ChangedPath(path: p, change: changeKind(xy: line)))
                }
            case "2":
                // 2 <XY> ... <X><score> <path>\t<origPath>  → 새 path 사용
                if let p = pathAfter(fields: 9, in: line) {
                    let newPath = p.components(separatedBy: "\t").first ?? p
                    changed.append(ChangedPath(path: newPath, change: .renamed))
                }
            case "u":
                if let p = pathAfter(fields: 10, in: line) {
                    changed.append(ChangedPath(path: p, change: .unmerged))
                }
            case "?":
                let p = String(line.dropFirst(2))
                changed.append(ChangedPath(path: p, change: .untracked))
            default:
                break
            }
        }

        if changed.isEmpty {
            return .clean
        }

        // ins/del 은 numstat 합산(tracked 변경 한정). untracked 는 라인 수 반영 어려워 0 처리.
        let (ins, del) = (try? await numstat(worktreePath: worktreePath)) ?? (0, 0)
        return WorktreeStatus(
            isClean: false,
            changedFiles: changed.count,
            insertions: ins,
            deletions: del,
            changedPaths: changed
        )
    }

    /// porcelain=v2 의 1 라인에서 XY 코드를 읽어 대표 변경 종류를 고른다.
    private nonisolated static func changeKind(xy line: String) -> ChangeKind {
        // "1 .M ..." → 두 번째 토큰이 XY
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return .modified }
        let xy = Array(parts[1])
        // staged(X) 가 의미있으면 우선, 아니면 unstaged(Y)
        let code = (xy.first.map { $0 != "." } ?? false) ? xy[0] : (xy.count > 1 ? xy[1] : xy[0])
        return ChangeKind(porcelainCode: code)
    }

    /// 공백으로 N개 필드를 건너뛴 뒤 남은 문자열(=경로). 경로 내 공백을 보존한다.
    private nonisolated static func pathAfter(fields: Int, in line: String) -> String? {
        var remaining = Substring(line)
        for _ in 0..<fields {
            guard let space = remaining.firstIndex(of: " ") else { return nil }
            remaining = remaining[remaining.index(after: space)...]
        }
        let path = String(remaining)
        return path.isEmpty ? nil : path
    }

    /// diff HEAD --numstat → (insertions, deletions) 합산.
    nonisolated static func numstat(worktreePath: String) async throws -> (Int, Int) {
        let out = try await GitRunner.run(.diff, ["HEAD", "--numstat"], in: worktreePath)
        var ins = 0, del = 0
        for line in out.split(separator: "\n") {
            let cols = line.split(separator: "\t")
            guard cols.count >= 2 else { continue }
            ins += Int(cols[0]) ?? 0   // 바이너리는 '-' → 0
            del += Int(cols[1]) ?? 0
        }
        return (ins, del)
    }

    // MARK: - trunk 감지 / divergence

    /// main 또는 master 중 존재하는 브랜치를 trunk 로 본다.
    nonisolated static func detectTrunk(repoPath: String) async throws -> String? {
        for candidate in ["main", "master"] {
            if (try? await GitRunner.run(.revParse, ["--verify", "--quiet", "refs/heads/\(candidate)"], in: repoPath)) != nil {
                return candidate
            }
        }
        return nil
    }

    /// rev-list --left-right --count <trunk>...<branch> → "<behind> <ahead>".
    /// 좌(trunk) 쪽 = behind, 우(branch) 쪽 = ahead.
    nonisolated static func divergence(repoPath: String, trunk: String, branch: String) async throws -> Divergence {
        let out = try await GitRunner.run(.revList, ["--left-right", "--count", "\(trunk)...\(branch)"], in: repoPath)
        let nums = out.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).compactMap { Int($0) }
        let behind = nums.first ?? 0
        let ahead = nums.count > 1 ? nums[1] : 0
        return Divergence(ahead: ahead, behind: behind, trunk: trunk)
    }

    // MARK: - 커밋 로그 (그래프 + 스파크라인 + 스탯)

    /// log --all. (그래프 커밋, 총 커밋 수, 마지막 커밋 시각)
    nonisolated static func commitLog(repoPath: String, limit: Int? = nil) async throws -> ([GraphCommit], Int, Date?) {
        var args = ["--all", "--date-order",
                    "--pretty=format:%H\(unit)%P\(unit)%an\(unit)%aI\(unit)%s"]
        if let limit { args.append("--max-count=\(limit)") }

        let out: String
        do {
            out = try await GitRunner.run(.log, args, in: repoPath)
        } catch GitError.nonZeroExit {
            // 커밋이 하나도 없는 리포(unborn HEAD)는 log 가 실패한다 → 빈 결과.
            return ([], 0, nil)
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var commits: [GraphCommit] = []
        for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.components(separatedBy: unit)
            guard f.count >= 5 else { continue }
            let parents = f[1].isEmpty ? [] : f[1].split(separator: " ").map(String.init)
            let date = iso.date(from: f[3]) ?? Date(timeIntervalSince1970: 0)
            commits.append(GraphCommit(
                sha: f[0], parents: parents, author: f[2], date: date, subject: f[4]
            ))
        }
        let last = commits.map(\.date).max()
        return (commits, commits.count, last)
    }

    // MARK: - ref 매핑

    nonisolated static func refList(repoPath: String) async throws -> [GitRef] {
        let out = try await GitRunner.run(
            .forEachRef,
            ["--format=%(objectname)\(unit)%(refname)\(unit)%(HEAD)"],
            in: repoPath
        )
        var refs: [GitRef] = []
        for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.components(separatedBy: unit)
            guard f.count >= 2 else { continue }
            let fullName = f[1]
            let isHead = f.count > 2 && f[2] == "*"
            let (short, kind) = classify(ref: fullName)
            refs.append(GitRef(sha: f[0], name: short, isHead: isHead, kind: kind))
        }
        return refs
    }

    private nonisolated static func classify(ref: String) -> (String, GitRef.Kind) {
        if ref.hasPrefix("refs/heads/") {
            return (String(ref.dropFirst("refs/heads/".count)), .branch)
        } else if ref.hasPrefix("refs/remotes/") {
            return (String(ref.dropFirst("refs/remotes/".count)), .remote)
        } else if ref.hasPrefix("refs/tags/") {
            return (String(ref.dropFirst("refs/tags/".count)), .tag)
        }
        return (ref, .other)
    }

    // MARK: - 커밋 상세 / diff

    /// 커밋 본문(제목 제외): show -s --format=%b <sha>
    nonisolated static func commitBody(repoPath: String, sha: String) async throws -> String {
        let out = try await GitRunner.run(.show, ["-s", "--format=%b", sha], in: repoPath)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// diff-tree --no-commit-id --name-status -r <sha> → 변경 파일 목록.
    nonisolated static func commitFiles(repoPath: String, sha: String) async throws -> [ChangedPath] {
        let out = try await GitRunner.run(.diffTree, ["--no-commit-id", "--name-status", "-r", sha], in: repoPath)
        var files: [ChangedPath] = []
        for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
            let cols = line.split(separator: "\t").map(String.init)
            guard let statusCol = cols.first, let code = statusCol.first else { continue }
            // rename/copy 는 R100\told\tnew 형태 → 마지막 경로 사용
            let path = cols.count >= 3 ? cols[2] : (cols.count >= 2 ? cols[1] : "")
            guard !path.isEmpty else { continue }
            files.append(ChangedPath(path: path, change: ChangeKind(porcelainCode: code)))
        }
        return files
    }

    /// 커밋 내 한 파일 diff: diff-tree -p --no-commit-id <sha> -- <path>
    /// (show 와 달리 커밋 메타/메시지 헤더 없이 patch 만 출력 — 우측 커밋 패널과 중복 제거)
    nonisolated static func commitFileDiff(repoPath: String, sha: String, path: String) async throws -> String {
        try await GitRunner.run(.diffTree, ["-p", "--no-commit-id", sha, "--", path], in: repoPath)
    }

    /// 커밋 시점의 파일 전체 내용: show <sha>:<path> (blob). File View 용.
    nonisolated static func commitFileContent(repoPath: String, sha: String, path: String) async throws -> String {
        try await GitRunner.run(.show, ["\(sha):\(path)"], in: repoPath)
    }

    /// unified diff 에서 추가/수정된 줄의 "새 파일 기준" 라인 번호 집합.
    /// File View 에서 해당 줄 배경을 강조하는 데 쓴다.
    nonisolated static func addedLineNumbers(inDiff diff: String) -> [Int] {
        var result: [Int] = []
        var newLine = 0
        for raw in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("@@") {
                // @@ -a,b +c,d @@ → 새 파일 시작 줄 c
                if let plus = line.firstIndex(of: "+") {
                    let after = line[line.index(after: plus)...]
                    let digits = after.prefix { $0.isNumber }
                    newLine = Int(digits) ?? newLine
                }
                continue
            }
            if line.hasPrefix("+++") || line.hasPrefix("---")
                || line.hasPrefix("diff ") || line.hasPrefix("index ")
                || line.hasPrefix("\\") {   // "\ No newline at end of file"
                continue
            }
            if line.hasPrefix("+") {
                result.append(newLine); newLine += 1
            } else if line.hasPrefix("-") {
                // 삭제 줄은 새 파일에 존재하지 않으므로 라인 번호 증가 없음
            } else {
                newLine += 1   // context
            }
        }
        return result
    }

    /// 워킹트리 한 파일 diff: diff HEAD -- <path>
    nonisolated static func workingFileDiff(worktreePath: String, path: String) async throws -> String {
        try await GitRunner.run(.diff, ["HEAD", "--", path], in: worktreePath)
    }
}
