//
//  WorkingChangesPanel.swift
//  GitWatcher
//
//  그래프 최상단 WIP 노드 선택 시 우측에 표시. 워킹트리의 미커밋 변경 정보 + 파일 목록.
//  파일 선택은 selectedPath 로 부모에 전달되어 좌측이 working diff 오버레이로 전환된다.
//  (커밋이 아니므로 변경 히스토리는 없다.)
//

import SwiftUI

struct WorkingChangesPanel: View {
    let repoName: String
    let worktree: Worktree
    @Binding var selectedPath: String?

    private var files: [ChangedPath] { worktree.status.changedPaths }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(14)
            Divider()
            fileSummary
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            fileList
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Uncommitted changes", systemImage: "pencil.line")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.dirty)
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch").font(.caption)
                Text(worktree.branch).font(.callout.weight(.medium))
                Spacer()
            }
            Text(worktree.path)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    private var fileSummary: some View {
        HStack(spacing: 10) {
            if worktree.status.insertions > 0 || worktree.status.deletions > 0 {
                Text("+\(worktree.status.insertions)").foregroundStyle(Theme.clean)
                Text("−\(worktree.status.deletions)").foregroundStyle(.red)
            }
            Spacer()
            Text("\(files.count) \(files.count == 1 ? "file" : "files")")
                .foregroundStyle(.tertiary)
        }
        .font(.caption.monospacedDigit())
    }

    private var fileList: some View {
        Group {
            if files.isEmpty {
                Text("No changes")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(files, selection: $selectedPath) { file in
                    HStack(spacing: 8) {
                        Image(systemName: file.change.symbolName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(file.change.tint)
                            .frame(width: 16)
                        (Text(directory(of: file.path)).foregroundStyle(.secondary)
                         + Text(file.fileName).foregroundStyle(.primary).fontWeight(.medium))
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .help(file.path)
                    .tag(file.path)
                }
                .listStyle(.inset)
            }
        }
    }

    private func directory(of path: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir + "/"
    }
}
