//
//  RepoGraphScreen.swift
//  GitWatcher
//
//  카드 드릴다운 화면. 좌측 커밋 그래프(네이티브) + 우측 커밋 패널(정보 + 파일 목록).
//  파일을 선택하면 좌측 그래프 영역이 diff 오버레이로 전환된다.
//  worktree 가 여럿이어도 .git 공유 + log --all 로 한 그래프에 통합되고, 각 worktree HEAD 는 마커.
//

import SwiftUI

struct RepoGraphScreen: View {
    let repo: RepoViewModel
    @Environment(RepoStore.self) private var store

    @State private var selection: String?           // 선택된 커밋 sha
    @State private var selectedFilePath: String?     // 선택된 파일 → diff 오버레이
    @State private var diffSha: String?              // diff 대상 커밋(파일 히스토리 선택)

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

    private var selectedCommit: GraphCommit? {
        guard let selection else { return nil }
        return repo.commits.first { $0.sha == selection }
    }

    var body: some View {
        Group {
            if repo.commits.isEmpty {
                ContentUnavailableView("No commits yet",
                                       systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text("This repository has no commit history."))
            } else {
                HSplitView {
                    // 좌측: 그래프 (+ 파일 선택 시 diff 오버레이)
                    ZStack {
                        CommitGraphView(
                            layout: layout,
                            refsBySHA: refsBySHA,
                            worktreeHeads: worktreeHeads,
                            selection: $selection
                        )
                        if let path = selectedFilePath, let sha = diffSha {
                            DiffOverlayView(repoPath: repo.path, sha: sha, path: path) {
                                selectedFilePath = nil
                                diffSha = nil
                            }
                            .transition(.opacity)
                        }
                    }
                    .frame(minWidth: 360, idealWidth: 560)

                    // 우측: 커밋 패널 (정보 + 파일 목록 + 파일 히스토리)
                    detailPane
                        .frame(minWidth: 340, idealWidth: 480)
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
        // 커밋을 바꾸면 열려 있던 diff 오버레이를 닫는다.
        .onChange(of: selection) { _, _ in selectedFilePath = nil; diffSha = nil }
        .animation(.easeOut(duration: 0.15), value: selectedFilePath)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let commit = selectedCommit {
            CommitInfoPanel(repoPath: repo.path, commit: commit,
                            selectedPath: $selectedFilePath, diffSha: $diffSha)
        } else {
            ContentUnavailableView("Select a commit",
                                   systemImage: "hand.point.up.left",
                                   description: Text("Pick a commit in the graph to see its changes."))
        }
    }
}
