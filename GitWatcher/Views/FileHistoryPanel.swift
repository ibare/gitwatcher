//
//  FileHistoryPanel.swift
//  GitWatcher
//
//  파일 뷰어 우측의 변경 히스토리 타임라인(GitLens 스타일).
//  선택 파일이 변경된 커밋들을 시간순으로 보여주고, 커밋을 고르면 부모 대비 diff 로
//  좌측 뷰어가 전환된다. 맨 위 "Working tree" 는 현재 디스크 버전(히스토리 해제).
//  커밋 선택 시 하단에 그 커밋에서 함께 변경된 파일 목록을 제공 — 클릭하면 같은 커밋
//  컨텍스트로 그 파일로 점프해 히스토리 탐색을 이어간다.
//

import SwiftUI

struct FileHistoryPanel: View {
    let history: [GraphCommit]
    let loading: Bool
    /// 선택된 커밋 sha. nil = Working tree(현재 디스크 버전).
    let selectedSHA: String?
    /// 선택 커밋에서 함께 변경된 파일들(연관 파일).
    let commitFiles: [ChangedPath]
    /// 현재 보고 있는 파일의 repo 상대경로 — 연관 파일 목록에서 강조용.
    let currentRelPath: String?
    /// 히스토리 행 선택 콜백. nil 이면 Working tree 로 복귀.
    let onSelect: (GraphCommit?) -> Void
    /// 연관 파일 클릭 콜백(repo 상대경로).
    let onSelectFile: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            historyContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if selectedSHA != nil && !commitFiles.isEmpty {
                Divider().opacity(0.5)
                commitFilesSection
            }
        }
        .background(Theme.editorSidebar)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("HISTORY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.editorText.opacity(0.8))
            if loading { ProgressView().controlSize(.mini) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: 히스토리 타임라인

    @ViewBuilder
    private var historyContent: some View {
        if history.isEmpty && !loading {
            VStack(spacing: 8) {
                workingRow
                Text("No commit history for this file")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.editorText.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    workingRow
                    ForEach(history) { commit in
                        commitRow(commit)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .overlayScrollbars()
        }
    }

    private var workingRow: some View {
        let selected = selectedSHA == nil
        return HStack(spacing: 6) {
            Image(systemName: "pencil.line")
                .font(.system(size: 11))
                .foregroundStyle(selected ? Color.white : Theme.dirty)
                .frame(width: 14)
            Text("Working tree")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Color.white : Theme.editorText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(selected))
        .contentShape(Rectangle())
        .onTapGesture { onSelect(nil) }
    }

    private func commitRow(_ c: GraphCommit) -> some View {
        let selected = selectedSHA == c.sha
        return VStack(alignment: .leading, spacing: 2) {
            Text(c.subject)
                .font(.system(size: 12))
                .foregroundStyle(selected ? Color.white : Theme.editorText)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 5) {
                Text(c.author)
                    .lineLimit(1)
                Text("·")
                Text(Fmt.relative(c.date))
                Spacer(minLength: 4)
                Text(c.shortSHA).monospaced()
            }
            .font(.system(size: 10))
            .foregroundStyle(selected ? Color.white.opacity(0.85) : Theme.editorText.opacity(0.55))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(selected))
        .contentShape(Rectangle())
        .onTapGesture { onSelect(c) }
        .help(c.subject)
    }

    private func rowBackground(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(selected ? Color.accentColor : Color.clear)
    }

    // MARK: 연관 파일 (이 커밋에서 함께 변경된 파일)

    private var commitFilesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FILES IN COMMIT (\(commitFiles.count))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.editorText.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(commitFiles) { file in
                        fileRow(file)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 220)
            .overlayScrollbars()
        }
    }

    private func fileRow(_ file: ChangedPath) -> some View {
        let isCurrent = file.path == currentRelPath
        return HStack(spacing: 6) {
            Image(systemName: file.change.symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(file.change.tint)
                .frame(width: 12)
            Text(file.fileName)
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Theme.accent : Theme.editorText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isCurrent ? Theme.accent.opacity(0.14) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelectFile(file.path) }
        .help(file.path)
    }
}
