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
    @State private var trackedIndex: TrackedIndex?

    private static let maxBytes = 2_000_000   // 2MB 초과 텍스트는 표시 생략

    var body: some View {
        HSplitView {
            Group {
                if let root {
                    FileTreeView(root: root, selection: $selection)
                        .environment(\.trackedIndex, trackedIndex)
                        .environment(\.repoRootPath, repo.path)
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
        trackedIndex = try? await GitService.trackedIndex(repoPath: repo.path)
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
        .overlayScrollbars()
    }
}

// 트리 전체에 tracked 인덱스를 전달(재귀 행에 매번 넘기지 않도록 Environment 사용).
private struct TrackedIndexKey: EnvironmentKey {
    static let defaultValue: TrackedIndex? = nil
}
private struct RepoRootPathKey: EnvironmentKey {
    static let defaultValue: String? = nil
}
extension EnvironmentValues {
    var trackedIndex: TrackedIndex? {
        get { self[TrackedIndexKey.self] }
        set { self[TrackedIndexKey.self] = newValue }
    }
    var repoRootPath: String? {
        get { self[RepoRootPathKey.self] }
        set { self[RepoRootPathKey.self] = newValue }
    }
}

private struct FileTreeRow: View {
    @Bindable var node: FileNode
    @Binding var selection: URL?
    @Environment(\.trackedIndex) private var trackedIndex
    @Environment(\.repoRootPath) private var repoRootPath

    @State private var isHovered = false
    @State private var justCopied = false

    /// git 미추적 항목은 레이블/아이콘을 흐리게.
    private var isUntracked: Bool {
        guard let trackedIndex else { return false }
        return !trackedIndex.isTracked(node.url, isDirectory: node.isDirectory)
    }

    /// 호버 시 노출되는 경로 복사 버튼 — 프로젝트 루트 기준 상대 경로를 클립보드에 넣는다.
    private func copyPath() {
        let abs = node.url.path(percentEncoded: false)
        let path: String
        if let root = repoRootPath {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            path = abs.hasPrefix(prefix) ? String(abs.dropFirst(prefix.count)) : abs
        } else {
            path = abs
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            justCopied = false
        }
    }

    var body: some View {
        if node.isDirectory {
            // 폴더는 selection 대상이 아니라 펼침 전용(tag 없음) — 클릭하면 펼침/접힘.
            DisclosureGroup(isExpanded: $node.isExpanded) {
                if let children = node.children {
                    ForEach(children) { child in
                        FileTreeRow(node: child, selection: $selection)
                    }
                }
            } label: {
                rowLabel(
                    iconName: MaterialIconTheme.shared.iconName(forFolder: node.name, expanded: node.isExpanded),
                    fallback: node.isExpanded ? "folder.fill" : "folder"
                )
                .contentShape(Rectangle())
                .onTapGesture { node.isExpanded.toggle() }
            }
            .onChange(of: node.isExpanded) { _, expanded in
                if expanded { Task { await node.loadChildrenIfNeeded() } }
            }
        } else {
            rowLabel(
                iconName: MaterialIconTheme.shared.iconName(forFile: node.name),
                fallback: FileIcon.symbol(for: node.name)
            )
            .tag(node.url)
        }
    }

    @ViewBuilder
    private func rowLabel(iconName: String, fallback: String) -> some View {
        let dimmed = isUntracked
        HStack(spacing: 6) {
            if let img = MaterialIconTheme.shared.image(named: iconName) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .opacity(dimmed ? 0.45 : 1)
            } else {
                Image(systemName: fallback)
                    .frame(width: 16)
                    .foregroundStyle(Theme.editorText)
            }
            Text(node.name)
                .foregroundStyle(dimmed ? Theme.editorText.opacity(0.45) : Theme.editorText)
                .lineLimit(1)

            Spacer(minLength: 4)

            if isHovered || justCopied {
                Button(action: copyPath) {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(justCopied ? Theme.clean : Theme.editorText.opacity(0.7))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("경로 복사")
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
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
