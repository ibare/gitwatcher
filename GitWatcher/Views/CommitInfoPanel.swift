//
//  CommitInfoPanel.swift
//  GitWatcher
//
//  우측 커밋 패널. 상단에 커밋 정보(제목·본문·author·날짜·parent·변경 요약),
//  하단에 변경 파일 목록(디렉토리 경로 + 파일명). 파일 선택은 selectedPath 로 부모에
//  전달되어 좌측 그래프 영역이 diff 오버레이로 전환된다. 파일 선택과 무관하게 커밋 내용은 항상 보인다.
//

import SwiftUI

struct CommitInfoPanel: View {
    let repoPath: String
    let commit: GraphCommit
    @Binding var selectedPath: String?
    @Binding var diffSha: String?           // 파일 히스토리에서 선택된 diff 대상 커밋

    @State private var files: [ChangedPath] = []
    @State private var body_: String = ""
    @State private var history: [GraphCommit] = []
    @State private var loadingHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            commitInfo
                .padding(14)
            Divider()
            fileSummary
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            // 파일 선택 전: 파일 목록만. 선택 후: [파일 목록 | 파일 변경 히스토리] 2분할.
            if selectedPath == nil {
                fileList
            } else {
                HSplitView {
                    fileList.frame(minWidth: 180)
                    historyList.frame(minWidth: 160)
                }
            }
        }
        .task(id: commit.sha) { await load() }
        .onChange(of: selectedPath) { _, newPath in
            Task { await loadHistory(for: newPath) }
        }
    }

    // MARK: 커밋 정보

    private var commitInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(commit.subject)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !body_.isEmpty {
                Text(body_)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(commit.author).font(.callout.weight(.medium))
                    Text("authored \(commit.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Label(commit.shortSHA, systemImage: "number")
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.accent)
                if let parent = commit.parents.first {
                    Text("parent: \(String(parent.prefix(7)))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 변경 요약 ("N modified · M added")

    private var fileSummary: some View {
        HStack(spacing: 10) {
            ForEach(summaryParts, id: \.label) { part in
                HStack(spacing: 4) {
                    Image(systemName: part.symbol).font(.caption2)
                    Text("\(part.count) \(part.label)").font(.caption)
                }
                .foregroundStyle(part.tint)
            }
            Spacer()
            Text("\(files.count) \(files.count == 1 ? "file" : "files")")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private struct SummaryPart { let label: String; let count: Int; let symbol: String; let tint: Color }

    private var summaryParts: [SummaryPart] {
        // change 종류별 카운트(주요 4종만 노출)
        var counts: [ChangeKind: Int] = [:]
        for f in files { counts[f.change, default: 0] += 1 }
        let order: [ChangeKind] = [.modified, .added, .deleted, .renamed]
        return order.compactMap { kind in
            guard let c = counts[kind], c > 0 else { return nil }
            return SummaryPart(label: kind.label, count: c, symbol: kind.symbolName, tint: kind.tint)
        }
    }

    // MARK: 파일 목록 (경로 + 파일명)

    private var fileList: some View {
        Group {
            if files.isEmpty {
                Text("No changed files")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(files, selection: $selectedPath) { file in
                    HStack(spacing: 8) {
                        Image(systemName: file.change.symbolName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(file.change.tint)
                            .frame(width: 16)
                        // 디렉토리 흐리게 + 파일명 강조
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

    // MARK: 파일 변경 히스토리 (선택 파일이 변경된 커밋들)

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("File history")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if loadingHistory { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider()

            if history.isEmpty && !loadingHistory {
                Text("No history")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(history, selection: $diffSha) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.subject)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        HStack(spacing: 6) {
                            Text(Fmt.relative(c.date))
                            Text(c.shortSHA).monospaced()
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 1)
                    .tag(c.sha)
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: 로드

    private func load() async {
        selectedPath = nil
        diffSha = nil
        history = []
        files = (try? await GitService.commitFiles(repoPath: repoPath, sha: commit.sha)) ?? []
        body_ = (try? await GitService.commitBody(repoPath: repoPath, sha: commit.sha)) ?? ""
    }

    /// 파일을 선택하면 그 파일의 변경 히스토리를 로드하고 최상단(현재 커밋)을 diff 대상으로 잡는다.
    private func loadHistory(for path: String?) async {
        guard let path else { history = []; diffSha = nil; return }
        diffSha = commit.sha               // 즉시 현재 커밋 diff 표시(히스토리 로드 대기 없이)
        loadingHistory = true
        defer { loadingHistory = false }
        let h = (try? await GitService.fileHistory(repoPath: repoPath, sha: commit.sha, path: path)) ?? []
        history = h
        diffSha = h.first?.sha ?? commit.sha    // 최상단 = 현재 커밋
    }
}
