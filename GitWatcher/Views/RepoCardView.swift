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
    var onOpenProject: () -> Void = {}
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

            // 남는 공간을 커밋 목록으로 채운다(가용 높이만큼 개수 자동 산정 → 카드별 빈공간 최소화).
            recentCommits

            Divider().opacity(0.5)
            footer
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardStroke, lineWidth: 1))
        .contentShape(Rectangle())   // 우클릭 컨텍스트 메뉴 영역(카드 탭 진입은 버튼으로만)
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

    // MARK: 최근 커밋 (상대 날짜 + 메시지, 한 줄 말줄임)
    //  카드의 남는 세로 공간을 측정해 잘리지 않을 만큼만 표시한다.

    /// 한 커밋 행이 차지하는 세로 크기(행 높이 + VStack spacing). 보수적으로 잡아 잘림 방지.
    private static let commitRowUnit: CGFloat = 18
    /// 커밋 영역의 최소 높이 — 카드 기본 높이 확보용(커밋이 적으면 그만큼만).
    private var minCommitAreaHeight: CGFloat {
        CGFloat(min(5, repo.commits.count)) * Self.commitRowUnit
    }

    private var recentCommits: some View {
        GeometryReader { geo in
            // 가용 높이로 표시 가능한 행 수 산정(spacing 보정 후 내림).
            let count = max(0, Int((geo.size.height + 5) / Self.commitRowUnit))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(repo.commits.prefix(count)) { commit in
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minHeight: minCommitAreaHeight, maxHeight: .infinity)
    }

    // MARK: 하단 — Open project / Open graph

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Project", action: onOpenProject)
                .buttonStyle(CardActionButtonStyle())
            Button("Graph", action: onOpenGraph)
                .buttonStyle(CardActionButtonStyle())
        }
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

// MARK: - 카드 액션 버튼 스타일 (hover/press 인터랙션)

struct CardActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label_(configuration: configuration)
    }

    private struct Label_: View {
        let configuration: Configuration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        Theme.accent.opacity(configuration.isPressed ? 0.22 : (hovering ? 0.12 : 0))
                    )
                )
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}
