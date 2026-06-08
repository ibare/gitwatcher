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

/// 모노레포 변경 분포 바의 한 조각.
nonisolated struct PackageChange: Identifiable, Hashable, Sendable {
    var name: String
    var changedFiles: Int
    var id: String { name }
}
