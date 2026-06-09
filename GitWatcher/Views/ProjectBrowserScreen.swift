//
//  ProjectBrowserScreen.swift
//  GitWatcher
//
//  리포 파일 탐색기. 좌측 디스크 트리(lazy) + 우측 파일 뷰어.
//  "현재 상태" = 워킹 디렉토리(미커밋 포함)를 디스크 기준으로 본다. 읽기 전용.
//

import SwiftUI

/// 선택 파일의 로드 결과.
nonisolated enum LoadedFile: Equatable {
    case text(String, language: String?)
    case image(URL)
    case binary
    case tooLarge(bytes: Int)
    case unreadable
}

struct ProjectBrowserScreen: View {
    let repo: RepoViewModel

    @State private var root: FileNode?
    @State private var selection: URL?
    @State private var content: LoadedFile?

    private static let maxBytes = 2_000_000   // 2MB 초과 텍스트는 표시 생략

    var body: some View {
        HSplitView {
            Group {
                if let root {
                    FileTreeView(root: root, selection: $selection)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 220, idealWidth: 300, maxHeight: .infinity)

            VStack(spacing: 0) {
                if let url = selection, !isDirectory(url) {
                    fileHeader(url)
                    Divider()
                }
                fileViewer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 360, maxHeight: .infinity)
            .background(Theme.editorBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.editorBackground)
        .environment(\.colorScheme, .dark)   // 코드 에디터처럼 화면 전체 다크 고정
        .navigationTitle(repo.displayName)
        .task { await loadRoot() }
        .task(id: selection) { await loadFile() }
    }

    private func fileHeader(_ url: URL) -> some View {
        let rel = url.path(percentEncoded: false)
            .replacingOccurrences(of: repo.path + "/", with: "")
        return HStack(spacing: 6) {
            Image(systemName: FileIcon.symbol(for: url.lastPathComponent))
                .foregroundStyle(.secondary)
            Text(rel).font(.callout).lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private var fileViewer: some View {
        switch content {
        case .text(let code, let lang):
            FileViewerWebView(code: code, language: lang)
        case .image(let url):
            ScrollView([.horizontal, .vertical]) {
                if let img = NSImage(contentsOf: url) {
                    Image(nsImage: img).padding()
                } else {
                    ContentUnavailableView("Cannot display image", systemImage: "photo")
                }
            }
        case .binary:
            ContentUnavailableView("Binary file", systemImage: "doc.zipper",
                                   description: Text("This file isn't text and can't be previewed."))
        case .tooLarge(let bytes):
            ContentUnavailableView("File too large", systemImage: "exclamationmark.triangle",
                                   description: Text("\(bytes / 1_000_000) MB — too large to preview."))
        case .unreadable:
            ContentUnavailableView("Cannot read file", systemImage: "xmark.octagon")
        case nil:
            ContentUnavailableView("Select a file", systemImage: "sidebar.left",
                                   description: Text("Pick a file in the tree to view it."))
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]

    private func loadRoot() async {
        guard root == nil else { return }
        let r = FileNode(url: URL(fileURLWithPath: repo.path), isDirectory: true)
        await r.loadChildrenIfNeeded()
        r.isExpanded = true
        root = r
    }

    private func loadFile() async {
        guard let url = selection, !isDirectory(url) else { content = nil; return }
        let maxBytes = Self.maxBytes
        let imageExts = Self.imageExts
        let loaded = await Task.detached(priority: .userInitiated) { () -> LoadedFile in
            let ext = url.pathExtension.lowercased()
            if imageExts.contains(ext) { return .image(url) }

            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
            let size = (attrs?[.size] as? Int) ?? 0
            if size > maxBytes { return .tooLarge(bytes: size) }

            guard let data = try? Data(contentsOf: url) else { return .unreadable }
            // NUL 바이트가 있으면 바이너리로 간주.
            if data.prefix(8000).contains(0) { return .binary }
            guard let text = String(data: data, encoding: .utf8) else { return .binary }
            return .text(text, language: CodeLanguage.hljsName(for: url.lastPathComponent))
        }.value
        content = loaded
    }
}

// MARK: - 파일 트리

struct FileTreeView: View {
    let root: FileNode
    @Binding var selection: URL?

    var body: some View {
        List(selection: $selection) {
            ForEach(root.children ?? []) { node in
                FileTreeRow(node: node, selection: $selection)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.editorSidebar)
    }
}

private struct FileTreeRow: View {
    @Bindable var node: FileNode
    @Binding var selection: URL?

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $node.isExpanded) {
                if let children = node.children {
                    ForEach(children) { child in
                        FileTreeRow(node: child, selection: $selection)
                    }
                }
            } label: {
                Label(node.name, systemImage: node.isExpanded ? "folder.fill" : "folder")
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
            }
            .tag(node.url)
            .onChange(of: node.isExpanded) { _, expanded in
                if expanded { Task { await node.loadChildrenIfNeeded() } }
            }
        } else {
            Label(node.name, systemImage: FileIcon.symbol(for: node.name))
                .lineLimit(1)
                .tag(node.url)
        }
    }
}

// MARK: - 파일 아이콘 (확장자 기반)

enum FileIcon {
    static func symbol(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx", "mjs", "cjs": return "curlybraces"
        case "json": return "curlybraces.square"
        case "md", "markdown", "txt": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic": return "photo"
        case "html", "css", "scss": return "chevron.left.forwardslash.chevron.right"
        case "sh", "zsh", "bash": return "terminal"
        case "yml", "yaml", "toml", "xml", "plist": return "doc.badge.gearshape"
        case "lock": return "lock.doc"
        default: return "doc"
        }
    }
}
