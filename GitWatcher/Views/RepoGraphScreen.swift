//
//  RepoGraphScreen.swift
//  GitWatcher
//
//  카드 드릴다운 화면. 좌측 커밋 그래프(네이티브) + 우측 커밋 상세/diff.
//  worktree 가 여럿이어도 .git 공유 + log --all 로 한 그래프에 통합되고, 각 worktree HEAD 는 마커.
//

import SwiftUI

struct RepoGraphScreen: View {
    let repo: RepoViewModel
    @Environment(RepoStore.self) private var store

    @State private var selection: String?

    private var layout: CommitGraphLayout {
        CommitGraphLayout.build(commits: repo.commits)
    }

    private var refsBySHA: [String: [GitRef]] {
        Dictionary(grouping: repo.refs, by: \.sha)
    }

    /// worktree HEAD sha → 브랜치 라벨들 (마커용).
    private var worktreeHeads: [String: [String]] {
        var map: [String: [String]] = [:]
        for wt in repo.worktrees {
            map[wt.headSHA, default: []].append(wt.branch)
        }
        return map
    }

    var body: some View {
        Group {
            if repo.commits.isEmpty {
                ContentUnavailableView("No commits yet",
                                       systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text("This repository has no commit history."))
            } else {
                HSplitView {
                    CommitGraphView(
                        layout: layout,
                        refsBySHA: refsBySHA,
                        worktreeHeads: worktreeHeads,
                        selection: $selection
                    )
                    .frame(minWidth: 320, idealWidth: 520)

                    detailPane
                        .frame(minWidth: 360)
                }
            }
        }
        .navigationTitle(repo.displayName)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { Task { await store.refresh(repo) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            if selection == nil { selection = repo.commits.first?.sha }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let sha = selection, let commit = repo.commits.first(where: { $0.sha == sha }) {
            CommitDetailView(context: .commit(repoPath: repo.path, commit: commit))
        } else {
            ContentUnavailableView("Select a commit",
                                   systemImage: "hand.point.up.left",
                                   description: Text("Pick a commit in the graph to see its changes."))
        }
    }
}
