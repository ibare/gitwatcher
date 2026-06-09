//
//  DiffOverlayView.swift
//  GitWatcher
//
//  파일 선택 시 좌측 그래프 영역을 덮는 diff 오버레이. 상단 바(파일 경로 + 닫기)와
//  웜 WKWebView diff 뷰어로 구성. 닫으면 그래프로 복귀한다.
//

import SwiftUI

struct DiffOverlayView: View {
    let repoPath: String
    let commit: GraphCommit
    let path: String
    var onClose: () -> Void

    @State private var diffText: String = ""
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            DiffWebView(diffText: diffText)
                .overlay(alignment: .center) {
                    if loading { ProgressView().controlSize(.small) }
                }
        }
        .background(Color(nsColor: .textBackgroundColor))   // 그래프를 완전히 가린다
        .task(id: path) { await loadDiff() }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            // 디렉토리는 흐리게, 파일명은 강조
            (Text(directory).foregroundStyle(.secondary)
             + Text(fileName).foregroundStyle(.primary).fontWeight(.semibold))
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close diff")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    private var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir + "/"
    }
    private var fileName: String { (path as NSString).lastPathComponent }

    private func loadDiff() async {
        loading = true
        defer { loading = false }
        diffText = (try? await GitService.commitFileDiff(repoPath: repoPath, sha: commit.sha, path: path)) ?? ""
    }
}
