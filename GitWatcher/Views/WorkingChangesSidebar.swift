//
//  WorkingChangesSidebar.swift
//  GitWatcher
//
//  파일 탐색기 사이드바 상단의 컴팩트 워킹 디렉토리 변경 섹션.
//  미커밋 변경 파일을 한눈에 보고, 클릭하면 공유 selection 으로 우측 뷰어를 열고
//  하단 파일 트리에서 해당 위치까지 펼쳐 위치를 확정한다.
//  (좁은 사이드바 폭 기준. 넓은 그래프 화면용은 WorkingChangesPanel 별도.)
//

import SwiftUI

struct WorkingChangesSidebar: View {
    let status: WorktreeStatus
    /// 변경 파일의 상대경로를 절대 URL 로 만들 때 쓰는 worktree 루트.
    let rootPath: String
    /// 트리와 공유하는 선택. 변경 파일 클릭 시 이 값이 바뀐다.
    @Binding var selection: URL?
    @Binding var collapsed: Bool

    private var files: [ChangedPath] { status.changedPaths }

    private func url(for file: ChangedPath) -> URL {
        // 트리 노드(FileNode.url)와 동일하게 표준화해야 selection 이 매칭된다.
        // file.path 는 여러 컴포넌트("a/b/c.tsx")일 수 있어 NSString 으로 안전하게 조합.
        let full = (rootPath as NSString).appendingPathComponent(file.path)
        return URL(fileURLWithPath: full).standardizedFileURL
    }

    private func isSelected(_ file: ChangedPath) -> Bool {
        guard let selection else { return false }
        return selection.standardizedFileURL.path(percentEncoded: false)
            == url(for: file).path(percentEncoded: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !collapsed {
                Divider().opacity(0.5)
                fileList
            }
        }
        .background(Theme.editorSidebar)
    }

    // MARK: - 헤더 (토글 + 통계 배지)

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.editorText.opacity(0.7))
                    .frame(width: 10)
                Text("CHANGES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.editorText.opacity(0.8))
                Spacer(minLength: 6)
                summaryBadge
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var summaryBadge: some View {
        if status.isClean {
            Text("clean")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Theme.clean.opacity(0.8))
        } else {
            HStack(spacing: 6) {
                Text("\(files.count)")
                    .foregroundStyle(Theme.dirty)
                if status.insertions > 0 {
                    Text("+\(status.insertions)").foregroundStyle(Theme.clean)
                }
                if status.deletions > 0 {
                    Text("−\(status.deletions)").foregroundStyle(.red)
                }
            }
            .font(.system(size: 10).monospacedDigit())
        }
    }

    // MARK: - 변경 파일 목록

    @ViewBuilder
    private var fileList: some View {
        if files.isEmpty {
            Text("No uncommitted changes")
                .font(.system(size: 11))
                .foregroundStyle(Theme.editorText.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        } else {
            // 트리 List 와 selection 바인딩을 공유하면 두 List 가 서로 간섭하므로,
            // 여기선 List 대신 탭 제스처로 공유 selection 을 직접 설정한다.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(files) { file in
                        row(file)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .overlayScrollbars()
        }
    }

    private func row(_ file: ChangedPath) -> some View {
        let selected = isSelected(file)
        return HStack(spacing: 6) {
            Image(systemName: file.change.symbolName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(selected ? Color.white : file.change.tint)
                .frame(width: 14)
            Text(file.fileName)
                .font(.system(size: 12))
                .foregroundStyle(selected ? Color.white : Theme.editorText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { selection = url(for: file) }
        .help(file.path)
    }
}
