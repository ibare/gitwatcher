//
//  CommitDetailView.swift
//  GitWatcher
//
//  커밋 정보 + 변경 파일 목록 + diff. 같은 diff 뷰가 두 맥락을 재사용한다:
//  커밋 diff(show <sha>)와 대시보드 워킹트리 diff(diff HEAD).
//

import SwiftUI

/// diff 표시 맥락. 파일 목록과 파일별 diff 를 어디서 가져올지 결정한다.
enum DiffContext: Hashable, Identifiable {
    case commit(repoPath: String, commit: GraphCommit)
    case working(repoName: String, worktreePath: String, paths: [ChangedPath])

    var id: String {
        switch self {
        case .commit(_, let c): return "commit:\(c.sha)"
        case .working(_, let path, _): return "working:\(path)"
        }
    }
}

struct CommitDetailView: View {
    let context: DiffContext

    @State private var files: [ChangedPath] = []
    @State private var selectedPath: String?
    @State private var diffText: String = ""
    @State private var loadingDiff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HSplitView {
                fileList
                    .frame(minWidth: 180, idealWidth: 230, maxWidth: 360)
                DiffWebView(diffText: diffText)
                    .frame(minWidth: 300)
                    .overlay(alignment: .topTrailing) {
                        if loadingDiff { ProgressView().controlSize(.small).padding(8) }
                    }
            }
        }
        .task(id: context) { await loadFiles() }
    }

    // MARK: 헤더 (커밋 메타 또는 워킹트리 표시)

    @ViewBuilder
    private var header: some View {
        switch context {
        case .commit(_, let commit):
            VStack(alignment: .leading, spacing: 4) {
                Text(commit.subject).font(.headline).lineLimit(2)
                HStack(spacing: 8) {
                    Text(commit.shortSHA).font(.caption.monospaced())
                        .foregroundStyle(Theme.accent)
                    Text(commit.author).font(.caption).foregroundStyle(.secondary)
                    Text(commit.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        case .working(let repoName, let path, _):
            VStack(alignment: .leading, spacing: 4) {
                Label("Working tree changes", systemImage: "pencil.and.scribble")
                    .font(.headline)
                Text("\(repoName) · \(path)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(12)
        }
    }

    // MARK: 파일 목록

    private var fileList: some View {
        Group {
            if files.isEmpty {
                Text("No changed files")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(files, selection: $selectedPath) { file in
                    HStack(spacing: 8) {
                        ChangeBadge(kind: file.change)
                        Text(file.fileName).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .help(file.path)
                    .tag(file.path)
                }
                .listStyle(.inset)
            }
        }
        .onChange(of: selectedPath) { _, _ in Task { await loadDiff() } }
    }

    // MARK: 데이터 로드

    private func loadFiles() async {
        selectedPath = nil
        diffText = ""
        switch context {
        case .commit(let repoPath, let commit):
            files = (try? await GitService.commitFiles(repoPath: repoPath, sha: commit.sha)) ?? []
        case .working(_, _, let paths):
            files = paths
        }
        selectedPath = files.first?.path     // 첫 파일 자동 선택 → onChange 가 diff 로드
    }

    private func loadDiff() async {
        guard let path = selectedPath else { diffText = ""; return }
        loadingDiff = true
        defer { loadingDiff = false }
        switch context {
        case .commit(let repoPath, let commit):
            diffText = (try? await GitService.commitFileDiff(repoPath: repoPath, sha: commit.sha, path: path)) ?? ""
        case .working(_, let wtPath, _):
            diffText = (try? await GitService.workingFileDiff(worktreePath: wtPath, path: path)) ?? ""
        }
    }
}

private struct ChangeBadge: View {
    let kind: ChangeKind
    var body: some View {
        Text(kind.rawValue)
            .font(.caption2.weight(.bold).monospaced())
            .frame(width: 16, height: 16)
            .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(color)
    }
    private var color: Color {
        switch kind {
        case .added, .untracked: return Theme.clean
        case .deleted: return .red
        case .renamed, .copied: return Theme.diverged
        default: return Theme.dirty
        }
    }
}
