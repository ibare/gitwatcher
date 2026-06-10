//
//  FileNode.swift
//  GitWatcher
//
//  파일 탐색기용 lazy 디스크 트리 노드. 폴더를 펼칠 때만 그 디렉토리의 직속 항목을
//  백그라운드에서 읽는다(node_modules 등 대형 디렉토리도 펼치기 전엔 비용 0).
//  읽기 전용 — FileManager 로 디스크를 순회만 한다.
//

import Foundation
import Observation

@MainActor
@Observable
final class FileNode: Identifiable {
    let url: URL
    let name: String
    let isDirectory: Bool

    var isExpanded = false
    var children: [FileNode]? = nil      // nil = 아직 로드 안 함
    var isLoading = false

    nonisolated var id: URL { url }

    init(url: URL, isDirectory: Bool) {
        // 변경 섹션 등 다른 경로로 만든 URL 과 == 매칭되도록 표현을 표준화한다
        // (List selection/scrollTo 는 URL 객체 동등성에 의존).
        self.url = url.standardizedFileURL
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
    }

    /// 직속 자식을 백그라운드에서 읽어 채운다(이미 로드됐으면 스킵).
    func loadChildrenIfNeeded() async {
        guard isDirectory, children == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let entries = await Task.detached(priority: .userInitiated) { [url] in
            FileNode.read(url)
        }.value
        children = entries.map { FileNode(url: $0.url, isDirectory: $0.isDir) }
    }

    /// 대상 파일 URL 까지 경로상의 조상 디렉토리를 루트부터 lazy 로드하며 펼친다.
    /// 변경 파일을 트리에서 빠르게 위치 확정하는 용도. 대상 파일 노드를 찾으면 반환.
    @discardableResult
    func reveal(to target: URL) async -> FileNode? {
        let targetPath = Self.normalizedPath(target)
        let selfPath = Self.normalizedPath(url)
        if selfPath == targetPath { return self }
        // 대상이 이 디렉토리 하위가 아니면 탐색 중단.
        guard isDirectory, targetPath.hasPrefix(selfPath + "/") else { return nil }

        await loadChildrenIfNeeded()
        guard let children else { return nil }
        for child in children {
            let childPath = Self.normalizedPath(child.url)
            if targetPath == childPath || targetPath.hasPrefix(childPath + "/") {
                if child.isDirectory { child.isExpanded = true }
                return await child.reveal(to: target)
            }
        }
        return nil
    }

    /// 경로 비교용 정규화 — 디렉토리 URL 의 trailing slash 를 제거해 prefix 비교를 안정화한다.
    /// (standardizedFileURL.path 는 디렉토리에 "/" 를 남겨 "a/b/" + "/" 같은 이중 슬래시가 생긴다.)
    private nonisolated static func normalizedPath(_ u: URL) -> String {
        var p = u.standardizedFileURL.path(percentEncoded: false)
        if p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    // MARK: - 디스크 읽기 (백그라운드)

    private struct RawEntry: Sendable { let url: URL; let isDir: Bool }

    /// 디렉토리의 직속 항목을 읽어 폴더 먼저 · 이름순 정렬. .git 은 기본 숨김.
    private nonisolated static func read(_ dir: URL) -> [RawEntry] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []

        var entries: [RawEntry] = []
        for u in urls {
            if hiddenNames.contains(u.lastPathComponent) { continue }
            let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            entries.append(RawEntry(url: u, isDir: isDir))
        }
        let sorted = entries.sorted { a, b in
            if a.isDir != b.isDir { return a.isDir }   // 폴더 먼저
            return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
        // node_modules/.pnpm 등 초대형 디렉토리에서 트리가 멈추지 않도록 상한.
        return sorted.count > maxChildren ? Array(sorted.prefix(maxChildren)) : sorted
    }

    /// 한 디렉토리에 표시할 최대 자식 수(성능 가드).
    private nonisolated static let maxChildren = 1000

    /// 트리에서 숨길 항목(코드 에디터 관행). 추후 토글 옵션으로 노출 가능.
    private nonisolated static let hiddenNames: Set<String> = [".git", ".DS_Store"]
}
