//
//  RepoCardView.swift
//  GitWatcher
//
//  리포 카드. 계층은 "지금" 우선 — 누적 스탯이 아니라 라이브 워킹트리 상태가 맨 위.
//  worktrees.count 에 따라 degrade: 1개=플랫, N개=worktree 서브로우.
//

import SwiftUI

struct RepoCardView: View {
    let repo: RepoViewModel
    var onOpenGraph: () -> Void
    /// dirty worktree 의 변경 파일 diff 를 보기 위한 진입.
    var onViewChanges: (Worktree) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            liveStatus
            secondaryStats

            if repo.worktrees.count > 1 {
                Divider().opacity(0.5)
                ForEach(repo.worktrees) { wt in
                    WorktreeRow(worktree: wt) {
                        if !wt.status.isClean { onViewChanges(wt) }
                    }
                }
            }

            recentCommits

            // 같은 행의 카드를 가장 큰 카드 높이로 맞추고 footer 를 바닥에 정렬한다.
            Spacer(minLength: 0)

            Divider().opacity(0.5)
            footer
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardStroke, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenGraph)
    }

    // MARK: 헤더 — 폴더 아이콘 + 리포명 / 브랜치 pill + 상태 dot

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.displayName)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle = repo.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if case .failed = repo.loadState {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help("Failed to read this repository")
            } else if let wt = repo.primaryWorktree {
                BranchPill(branch: wt.branch, detached: wt.isDetached)
            }
            StatusDot(isDirty: repo.isAnyDirty)
        }
    }

    // MARK: 라이브 상태 (가장 크게)

    @ViewBuilder
    private var liveStatus: some View {
        // 단일 worktree 면 그 상태를, 여럿이면 합산을 크게 보여준다.
        let totals = aggregateStatus
        if totals.changedFiles == 0 {
            Label("clean", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.clean)
        } else {
            HStack(spacing: 10) {
                Text("\(totals.changedFiles) \(totals.changedFiles == 1 ? "file" : "files") changed")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.dirty)
                if totals.insertions > 0 || totals.deletions > 0 {
                    HStack(spacing: 6) {
                        Text("+\(totals.insertions)").foregroundStyle(Theme.clean)
                        Text("−\(totals.deletions)").foregroundStyle(.red)
                    }
                    .font(.subheadline.monospacedDigit())
                }
                Spacer()
                // 단일 worktree 면 카드 라이브 상태에서 바로 변경 diff 진입(여럿이면 서브로우에서).
                if repo.worktrees.count == 1, let wt = repo.primaryWorktree {
                    Button("View changes") { onViewChanges(wt) }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var aggregateStatus: (changedFiles: Int, insertions: Int, deletions: Int) {
        repo.worktrees.reduce(into: (0, 0, 0)) { acc, wt in
            acc.0 += wt.status.changedFiles
            acc.1 += wt.status.insertions
            acc.2 += wt.status.deletions
        }
    }

    // MARK: 보조 스탯(muted)

    private var secondaryStats: some View {
        HStack(spacing: 6) {
            Text("\(Fmt.compact(repo.totalCommits)) commits")
            Text("·")
            Text("last commit \(Fmt.relative(repo.lastCommitDate))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: 최근 커밋 10개 (상대 날짜 + 메시지, 한 줄 말줄임)

    @ViewBuilder
    private var recentCommits: some View {
        if !repo.commits.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(repo.commits.prefix(10)) { commit in
                    HStack(spacing: 8) {
                        Text(Fmt.relative(commit.date))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        Text(commit.subject)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: 하단 — 플래그 pill + Open graph

    private var footer: some View {
        HStack {
            ForEach(flagPills, id: \.self) { flag in
                Text(flag)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.dirty.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.dirty)
            }
            Spacer()
            Button(action: onOpenGraph) {
                HStack(spacing: 3) {
                    Text("Open graph")
                    Image(systemName: "arrow.right")
                }
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
    }

    /// 예: "web: 3 uncommitted" — worktree 가 여럿이면 dirty 한 것만 플래그로.
    private var flagPills: [String] {
        guard repo.worktrees.count > 1 else { return [] }
        return repo.worktrees
            .filter { !$0.status.isClean }
            .map { "\($0.branch): \($0.status.changedFiles) uncommitted" }
    }
}

// MARK: - 서브 컴포넌트

private struct BranchPill: View {
    let branch: String
    let detached: Bool
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: detached ? "scissors" : "arrow.triangle.branch")
                .font(.caption2)
            Text(branch).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Theme.accent.opacity(0.12), in: Capsule())
        .foregroundStyle(Theme.accent)
    }
}

private struct StatusDot: View {
    let isDirty: Bool
    var body: some View {
        Circle()
            .fill(isDirty ? Theme.dirty : Theme.clean)
            .frame(width: 9, height: 9)
            .help(isDirty ? "dirty" : "clean")
    }
}

private struct WorktreeRow: View {
    let worktree: Worktree
    var onTap: () -> Void = {}
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: worktree.isMainWorktree ? "house" : "arrow.triangle.branch")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(worktree.branch)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            if worktree.status.isClean {
                Text("clean").font(.caption2).foregroundStyle(Theme.clean)
            } else {
                Text("\(worktree.status.changedFiles) changed")
                    .font(.caption2).foregroundStyle(Theme.dirty)
            }

            Spacer()

            if let d = worktree.divergence, d.isDiverged {
                Text("\(d.ahead)↑ \(d.behind)↓ vs \(d.trunk)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.diverged)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .help(worktree.status.isClean ? worktree.path : "Click to view changes")
    }
}
