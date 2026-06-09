//
//  Models.swift
//  GitWatcher
//
//  데이터 모델 — 카드 타입을 두 개 만들지 않고 Repo/Worktree 하나로 통일한다.
//  worktrees.count 에 따라 UI 가 자연스럽게 degrade 된다(1개=플랫, N개=그룹).
//

import Foundation

// MARK: - 워킹트리 상태

/// 한 워킹 디렉토리의 라이브 상태. status --porcelain=v2 + diff --numstat 에서 합성한다.
nonisolated struct WorktreeStatus: Hashable, Sendable {
    var isClean: Bool
    var changedFiles: Int        // tracked 변경 + untracked (ignored 제외)
    var insertions: Int
    var deletions: Int
    var changedPaths: [ChangedPath]

    static let clean = WorktreeStatus(isClean: true, changedFiles: 0, insertions: 0, deletions: 0, changedPaths: [])
}

/// 변경 파일 한 건. 워킹트리 diff(diff HEAD)와 커밋 diff(show)에서 공용으로 쓴다.
nonisolated struct ChangedPath: Hashable, Identifiable, Sendable {
    var path: String
    var change: ChangeKind
    var id: String { path }

    /// "src/app/main.swift" → "main.swift"
    var fileName: String { (path as NSString).lastPathComponent }
}

nonisolated enum ChangeKind: String, Hashable, Sendable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case typeChanged = "T"
    case untracked = "?"
    case unmerged = "U"

    init(porcelainCode: Character) {
        switch porcelainCode {
        case "M": self = .modified
        case "A": self = .added
        case "D": self = .deleted
        case "R": self = .renamed
        case "C": self = .copied
        case "T": self = .typeChanged
        case "U": self = .unmerged
        default:  self = .modified
        }
    }
}

/// trunk(main/master) 대비 ahead/behind. worktree 가 여럿일 때만 계산한다.
nonisolated struct Divergence: Hashable, Sendable {
    var ahead: Int
    var behind: Int
    var trunk: String

    var isDiverged: Bool { ahead > 0 || behind > 0 }
}

// MARK: - Worktree

/// 워킹 디렉토리 하나. 감시·상태조회의 최소 단위.
nonisolated struct Worktree: Identifiable, Hashable, Sendable {
    var path: String           // 워킹 디렉토리 절대경로
    var branch: String         // 현재 브랜치 (detached 면 short sha)
    var headSHA: String
    var isDetached: Bool
    var isMainWorktree: Bool    // worktree list 의 첫 항목 여부
    var status: WorktreeStatus
    var divergence: Divergence?

    var id: String { path }

    var name: String { (path as NSString).lastPathComponent }
}

// MARK: - 커밋 그래프 모델

/// 그래프 렌더용 커밋. log --all 한 줄에 대응.
nonisolated struct GraphCommit: Identifiable, Hashable, Sendable {
    var sha: String
    var parents: [String]
    var author: String
    var date: Date
    var subject: String

    var id: String { sha }

    var shortSHA: String { String(sha.prefix(7)) }
}

/// ref 매핑 (for-each-ref). 그래프의 브랜치/태그 마커.
nonisolated struct GitRef: Hashable, Sendable {
    var sha: String
    var name: String          // refname:short
    var isHead: Bool
    var kind: Kind

    enum Kind: Sendable { case branch, remote, tag, other }
}

/// git 추적 파일/디렉토리 인덱스. 파일 탐색기에서 미추적 항목을 회색 처리하는 데 쓴다.
/// 큰 Set 를 담으므로 참조 타입 — Environment 에서 reference identity 로 안정 비교(무한 무효화 방지).
nonisolated final class TrackedIndex: Sendable {
    let rootPath: String
    let files: Set<String>     // repo 루트 기준 상대경로
    let dirs: Set<String>      // tracked 파일을 가진 모든 조상 디렉토리

    init(rootPath: String, files: Set<String>, dirs: Set<String>) {
        self.rootPath = rootPath
        self.files = files
        self.dirs = dirs
    }

    /// 해당 URL(파일/폴더)이 git 추적 대상인지.
    func isTracked(_ url: URL, isDirectory: Bool) -> Bool {
        let rel = relativePath(of: url)
        return isDirectory ? dirs.contains(rel) : files.contains(rel)
    }

    private func relativePath(of url: URL) -> String {
        var p = url.path(percentEncoded: false)
        if p.hasSuffix("/") { p.removeLast() }   // 디렉토리 URL 의 끝 슬래시 제거
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return p.hasPrefix(prefix) ? String(p.dropFirst(prefix.count)) : p
    }
}
