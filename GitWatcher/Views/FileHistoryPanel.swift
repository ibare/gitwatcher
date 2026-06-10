//
//  FileHistoryPanel.swift
//  GitWatcher
//
//  파일 뷰어 우측의 변경 히스토리 타임라인(GitLens 스타일).
//  선택 파일이 변경된 커밋들을 시간순으로 보여주고, 커밋을 고르면 부모 대비 diff 로
//  좌측 뷰어가 전환된다. 맨 위 "Working tree" 는 현재 디스크 버전(히스토리 해제).
//  커밋 선택 시 그 커밋의 전체 메시지(COMMIT)와 함께 변경된 파일(FILES IN COMMIT)을
//  하단에 제공 — 파일을 클릭하면 같은 커밋 컨텍스트로 점프해 탐색을 이어간다.
//

import SwiftUI

struct FileHistoryPanel: View {
    let history: [GraphCommit]
    let loading: Bool
    /// 선택된 커밋. nil = Working tree(현재 디스크 버전).
    let selectedCommit: GraphCommit?
    /// 선택 커밋의 전체 메시지 본문(제목 제외).
    let commitBody: String
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
            if let commit = selectedCommit {
                Divider().opacity(0.5)
                commitDetail(commit)
                if !commitFiles.isEmpty {
                    Divider().opacity(0.5)
                    commitFilesSection
                }
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

    private var isWorkingSelected: Bool { selectedCommit == nil }

    private var workingRow: some View {
        let selected = isWorkingSelected
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
        let selected = selectedCommit?.sha == c.sha
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

    // MARK: 커밋 상세 (전체 메시지 + 메타)

    private func commitDetail(_ c: GraphCommit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COMMIT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.editorText.opacity(0.6))
            Text(c.subject)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.editorText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !commitBody.isEmpty {
                ScrollView {
                    Text(commitBody)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.editorText.opacity(0.7))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
            HStack(spacing: 5) {
                Text(c.author).lineLimit(1)
                Text("·")
                Text(c.shortSHA).monospaced()
                Text("·")
                Text(c.date.formatted(date: .abbreviated, time: .shortened)).lineLimit(1)
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.editorText.opacity(0.55))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        let nameColor = isCurrent ? Theme.accent : Theme.editorText
        // 디렉토리는 보조 정보 — 파일명과 확실히 구분되도록 톤다운.
        let dirColor = (isCurrent ? Theme.accent : Theme.editorText).opacity(0.45)
        return HStack(spacing: 6) {
            Image(systemName: file.change.symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(file.change.tint)
                .frame(width: 12)
            (Text(Self.directoryPrefix(file.path)).foregroundStyle(dirColor)
             + Text(file.fileName).foregroundStyle(nameColor)
                .fontWeight(isCurrent ? .semibold : .regular))
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.head)   // 앞쪽(디렉토리) 말줄임 — 파일명 보존
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

    /// "src/app/main.swift" → "src/app/" (루트 파일이면 빈 문자열).
    static func directoryPrefix(_ path: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir + "/"
    }
}
