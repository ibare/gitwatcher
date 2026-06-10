//
//  FileHistoryPanel.swift
//  GitWatcher
//
//  파일 뷰어 우측의 변경 히스토리 타임라인(GitLens 스타일).
//  선택 파일이 변경된 커밋들을 시간순으로 보여주고, 커밋을 고르면 부모 대비 diff 로
//  좌측 뷰어가 전환된다. 맨 위 "Working tree" 는 현재 디스크 버전(히스토리 해제).
//

import SwiftUI

struct FileHistoryPanel: View {
    let history: [GraphCommit]
    let loading: Bool
    /// 선택된 커밋 sha. nil = Working tree(현재 디스크 버전).
    let selectedSHA: String?
    /// 행 선택 콜백. nil 이면 Working tree 로 복귀.
    let onSelect: (GraphCommit?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            content
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

    @ViewBuilder
    private var content: some View {
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

    // MARK: 행

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
}
