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
    /// 좌측 그래프 패널 폭 — 마지막 조정값을 유지(앱 재시작에도 보존).
    @AppStorage("RepoGraph.graphPaneWidth") private var graphPaneWidth: Double = 560

    private static let graphPaneMinWidth: Double = 360
    private static let graphPaneMaxWidth: Double = 1000

    /// dirty 한 worktree 들 — 그래프 최상단에 WIP 노드로 표시.
    private var dirtyWorktrees: [Worktree] {
        repo.worktrees.filter { !$0.status.isClean }
    }

    /// WIP 가상 커밋(미커밋 변경). parents 를 worktree HEAD 로 두면 레이아웃이 HEAD 위에 매단다.
    private var wipCommits: [GraphCommit] {
        dirtyWorktrees.map { wt in
            GraphCommit(sha: "wip:\(wt.path)", parents: [wt.headSHA],
                        author: "", date: .distantFuture, subject: "Uncommitted changes")
        }
    }

    /// "wip:<path>" → 워킹트리 상태 (그래프 메시지 셀용).
    private var wipStatus: [String: WorktreeStatus] {
        Dictionary(uniqueKeysWithValues: dirtyWorktrees.map { ("wip:\($0.path)", $0.status) })
    }

    private var graphCommits: [GraphCommit] { wipCommits + repo.commits }

    private var layout: CommitGraphLayout {
        CommitGraphLayout.build(commits: graphCommits)
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
        guard let selection, !selection.hasPrefix("wip:") else { return nil }
        return repo.commits.first { $0.sha == selection }
    }

    /// WIP 노드가 선택됐으면 해당 worktree.
    private var selectedWorktree: Worktree? {
        guard let selection, selection.hasPrefix("wip:") else { return nil }
        let path = String(selection.dropFirst("wip:".count))
        return repo.worktrees.first { $0.path == path }
    }

    var body: some View {
        Group {
            if repo.commits.isEmpty {
                ContentUnavailableView("No commits yet",
                                       systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text("This repository has no commit history."))
            } else {
                HStack(spacing: 0) {
                    // 좌측: 그래프 (+ 파일 선택 시 diff 오버레이)
                    ZStack {
                        CommitGraphView(
                            layout: layout,
                            refsBySHA: refsBySHA,
                            worktreeHeads: worktreeHeads,
                            wipStatus: wipStatus,
                            selection: $selection,
                            isLoadingMore: repo.isLoadingMoreCommits,
                            onReachEnd: { Task { await store.loadMoreCommits(repo) } }
                        )
                        if let path = selectedFilePath, let src = diffSource {
                            DiffOverlayView(repoPath: repo.path, source: src, path: path) {
                                selectedFilePath = nil
                                diffSha = nil
                            }
                            .transition(.opacity)
                        }
                    }
                    .frame(width: graphPaneWidth)
                    .frame(maxHeight: .infinity)

                    ResizableDivider(
                        width: $graphPaneWidth,
                        minWidth: Self.graphPaneMinWidth,
                        maxWidth: Self.graphPaneMaxWidth
                    )

                    // 우측: 커밋 패널 (정보 + 파일 목록 + 파일 히스토리)
                    detailPane
                        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
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

    /// 현재 diff 오버레이가 가져올 소스(워킹트리 우선, 아니면 커밋).
    private var diffSource: DiffOverlayView.Source? {
        if let wt = selectedWorktree { return .working(worktreePath: wt.path) }
        if let sha = diffSha { return .commit(sha: sha) }
        return nil
    }

    @ViewBuilder
    private var detailPane: some View {
        if let wt = selectedWorktree {
            WorkingChangesPanel(repoName: repo.displayName, worktree: wt,
                                selectedPath: $selectedFilePath)
        } else if let commit = selectedCommit {
            CommitInfoPanel(repoPath: repo.path, commit: commit,
                            selectedPath: $selectedFilePath, diffSha: $diffSha)
        } else {
            ContentUnavailableView("Select a commit",
                                   systemImage: "hand.point.up.left",
                                   description: Text("Pick a commit in the graph to see its changes."))
        }
    }
}
