//
//  DiffOverlayView.swift
//  GitWatcher
//
//  파일 선택 시 좌측 그래프 영역을 덮는 diff 오버레이. 상단 바(파일 경로 + 뷰 전환 + 닫기)와
//  웜 WKWebView 뷰어로 구성. Diff View(변경분) ↔ File View(전체 + 추가줄 강조) 전환.
//  닫으면 그래프로 복귀한다.
//

import SwiftUI

struct DiffOverlayView: View {
    /// diff 대상. 커밋(sha) 또는 워킹트리(미커밋 변경).
    enum Source: Equatable {
        case commit(sha: String)
        case working(worktreePath: String)

        var key: String {
            switch self {
            case .commit(let sha): return "c:\(sha)"
            case .working(let wt): return "w:\(wt)"
            }
        }
    }

    let repoPath: String
    let source: Source
    let path: String
    var onClose: () -> Void

    enum ViewMode: Hashable { case diff, file }

    @State private var mode: ViewMode = .diff
    @State private var diffText: String = ""
    @State private var addedLines: [Int] = []
    @State private var fileText: String = ""
    @State private var loading = false

    private var content: DiffWebView.Content {
        switch mode {
        case .diff: return .diff(diffText)
        case .file: return .file(text: fileText, added: addedLines)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            DiffWebView(content: content)
                .overlay(alignment: .center) {
                    if loading { ProgressView().controlSize(.small) }
                }
        }
        .background(Color(nsColor: .textBackgroundColor))   // 그래프를 완전히 가린다
        .task(id: "\(source.key)\u{1}\(path)") {
            // 파일/대상이 바뀌면 diff 를 로드하고(추가줄 추출), File View 면 본문도 로드.
            fileText = ""
            await loadDiff()
            if mode == .file { await loadFile() }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .file && fileText.isEmpty {
                Task { await loadFile() }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            (Text(directory).foregroundStyle(.secondary)
             + Text(fileName).foregroundStyle(.primary).fontWeight(.semibold))
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            PillSegmentedControl(
                options: [.init(value: .diff, title: "Diff"),
                          .init(value: .file, title: "File")],
                selection: $mode
            )
            .help("Diff View: 변경분만 · File View: 전체 + 변경줄 강조")

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
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
        let d: String
        switch source {
        case .commit(let sha):
            d = (try? await GitService.commitFileDiff(repoPath: repoPath, sha: sha, path: path)) ?? ""
        case .working(let wt):
            d = (try? await GitService.workingFileDiff(worktreePath: wt, path: path)) ?? ""
        }
        diffText = d
        addedLines = GitService.addedLineNumbers(inDiff: d)
    }

    private func loadFile() async {
        loading = true
        defer { loading = false }
        switch source {
        case .commit(let sha):
            fileText = (try? await GitService.commitFileContent(repoPath: repoPath, sha: sha, path: path)) ?? ""
        case .working(let wt):
            // 워킹트리 전체 파일은 디스크에서 읽는다(미커밋 변경 반영).
            let full = (wt as NSString).appendingPathComponent(path)
            fileText = (try? String(contentsOfFile: full, encoding: .utf8)) ?? ""
        }
    }
}
