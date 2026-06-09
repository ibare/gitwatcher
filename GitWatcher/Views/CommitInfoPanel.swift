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

    @State private var files: [ChangedPath] = []
    @State private var body_: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            commitInfo
                .padding(14)
            Divider()
            fileSummary
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            fileList
        }
        .task(id: commit.sha) { await load() }
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

    // MARK: 로드

    private func load() async {
        selectedPath = nil
        files = (try? await GitService.commitFiles(repoPath: repoPath, sha: commit.sha)) ?? []
        body_ = (try? await GitService.commitBody(repoPath: repoPath, sha: commit.sha)) ?? ""
    }
}
