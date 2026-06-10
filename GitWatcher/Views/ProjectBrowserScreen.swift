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
    /// 워킹 디렉토리 변경 상태(상단 변경 섹션 표시용). nil = 아직 로드 전.
    @State private var status: WorktreeStatus?
    /// 변경 파일 선택 시 트리를 해당 위치로 스크롤하기 위한 트리거.
    @State private var scrollTarget: URL?
    /// 탐색 대상 worktree 경로. nil 이면 메인 worktree.
    @State private var selectedWorktreePath: String?
    /// 트리 사이드바 폭 — 마지막 조정값을 유지(앱 재시작에도 보존).
    @AppStorage("ProjectBrowser.sidebarWidth") private var sidebarWidth: Double = 300
    /// 상단 변경 섹션 높이 — 영속화.
    @AppStorage("ProjectBrowser.changesHeight") private var changesHeight: Double = 220
    /// 상단 변경 섹션 접힘 상태 — 영속화.
    @AppStorage("ProjectBrowser.changesCollapsed") private var changesCollapsed = false
    /// 마크다운 파일을 렌더링 프리뷰로 볼지(코드 보기와 토글). 기본 프리뷰.
    @State private var markdownPreview = true

    /// 우측에 파일 변경 히스토리 타임라인을 표시할지 — 영속화.
    @AppStorage("ProjectBrowser.showHistory") private var showHistory = false
    /// 히스토리 패널 폭 — 영속화.
    @AppStorage("ProjectBrowser.historyWidth") private var historyWidth: Double = 280
    /// 선택 파일의 변경 커밋 목록(log --follow).
    @State private var fileHistory: [GraphCommit] = []
    /// 히스토리에서 선택된 커밋. nil = 현재 워킹 버전(디스크).
    @State private var historyCommit: GraphCommit?
    /// 선택 커밋의 부모 대비 diff.
    @State private var commitDiff: String?
    /// 선택 커밋에서 함께 변경된 파일(연관 파일).
    @State private var commitFiles: [ChangedPath] = []
    /// 연관 파일 점프 시 유지할 커밋(selection 변경에도 커밋 컨텍스트 보존).
    @State private var pendingKeepCommit: GraphCommit?
    @State private var loadingHistory = false

    private static let sidebarMinWidth: Double = 180
    private static let sidebarMaxWidth: Double = 640
    private static let changesMinHeight: Double = 80
    private static let changesMaxHeight: Double = 600
    private static let historyMinWidth: Double = 200
    private static let historyMaxWidth: Double = 480

    private static let maxBytes = 2_000_000   // 2MB 초과 텍스트는 표시 생략

    /// worktree 선택 메뉴에 표시할 목록 — 메인 먼저, 그다음 이름순.
    private var worktrees: [Worktree] {
        repo.worktrees.sorted { a, b in
            if a.isMainWorktree != b.isMainWorktree { return a.isMainWorktree }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// 현재 트리 루트로 쓰는 worktree 경로.
    private var currentPath: String {
        selectedWorktreePath ?? repo.primaryWorktree?.path ?? repo.path
    }

    /// 현재 선택된 worktree 모델(있으면).
    private var currentWorktree: Worktree? {
        repo.worktrees.first { $0.path == currentPath }
    }

    /// 타이틀바 서브타이틀에 표시할 현재 브랜치(⎇ main 형태).
    private var branchSubtitle: String {
        guard let branch = currentWorktree?.branch ?? repo.primaryWorktree?.branch,
              !branch.isEmpty else { return "" }
        return "⎇ \(branch)"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarColumn

            ResizableDivider(
                width: $sidebarWidth,
                minWidth: Self.sidebarMinWidth,
                maxWidth: Self.sidebarMaxWidth
            )

            VStack(spacing: 0) {
                if let url = selection, !isDirectory(url) {
                    fileHeader(url)
                    Divider()
                }
                rightContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.editorBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.editorBackground)
        .environment(\.colorScheme, .dark)   // 코드 에디터처럼 화면 전체 다크 고정
        .navigationTitle(repo.displayName)
        .navigationSubtitle(branchSubtitle)
        .toolbar {
            if worktrees.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    // 대시보드 정렬과 동일한 네이티브 세그먼트 Picker(toolbar 에서 시스템 렌더).
                    Picker("Worktree", selection: worktreeSelection) {
                        ForEach(worktrees) { wt in
                            Text(wt.name).tag(wt.path)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }
        .task(id: currentPath) { await loadRoot() }
        .task(id: selection) { await loadFile() }
        .onChange(of: selection) { _, newValue in
            // 연관 파일 점프면 커밋 컨텍스트를 유지(같은 커밋의 그 파일 diff), 아니면 워킹 버전으로 리셋.
            if let keep = pendingKeepCommit {
                pendingKeepCommit = nil
                selectHistoryCommit(keep)
            } else {
                historyCommit = nil
                commitDiff = nil
                commitFiles = []
            }
            Task { await loadHistoryIfNeeded() }
            // 변경 파일/트리에서 선택된 파일을 트리에서 펼쳐 위치를 확정하고 스크롤.
            guard let url = newValue, let root, !isDirectory(url) else { return }
            Task {
                guard let node = await root.reveal(to: url) else { return }
                // reveal 이 찾은 실제 트리 노드의 URL 로 맞춰 List 하이라이트·스크롤이 동작하게 한다.
                if node.url != url { selection = node.url }
                // 방금 펼친 행이 List 에 렌더·레이아웃될 시간을 준 뒤 스크롤(즉시 호출하면 대상 id 가 없음).
                try? await Task.sleep(for: .milliseconds(250))
                scrollTarget = node.url
            }
        }
        .onChange(of: showHistory) { _, on in
            if on { Task { await loadHistoryIfNeeded() } }
        }
    }

    /// 좌측 사이드바: 상단 워킹 디렉토리 변경 섹션 + (수직 분할) + 하단 파일 트리.
    @ViewBuilder
    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            if let status {
                WorkingChangesSidebar(
                    status: status,
                    rootPath: currentPath,
                    selection: $selection,
                    collapsed: $changesCollapsed
                )
                .frame(height: changesCollapsed ? nil : changesHeight)

                if changesCollapsed {
                    Divider().opacity(0.5)
                } else {
                    ResizableDivider(
                        width: $changesHeight,
                        minWidth: Self.changesMinHeight,
                        maxWidth: Self.changesMaxHeight,
                        orientation: .vertical
                    )
                }
            }

            Group {
                if let root {
                    FileTreeView(root: root, selection: $selection, scrollTarget: scrollTarget)
                        .environment(\.trackedIndex, trackedIndex)
                        .environment(\.repoRootPath, currentPath)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.editorSidebar)
    }

    /// 세그먼트 선택 바인딩 — 바뀌면 트리 루트 worktree 를 교체하고 파일 선택을 초기화.
    private var worktreeSelection: Binding<String> {
        Binding(
            get: { currentPath },
            set: { newPath in
                guard newPath != currentPath else { return }
                selectedWorktreePath = newPath
                selection = nil
            }
        )
    }

    private func fileHeader(_ url: URL) -> some View {
        let rel = url.path(percentEncoded: false)
            .replacingOccurrences(of: currentPath + "/", with: "")
        return HStack(spacing: 6) {
            Image(systemName: FileIcon.symbol(for: url.lastPathComponent))
                .foregroundStyle(.secondary)
            Text(rel).font(.callout).lineLimit(1).truncationMode(.middle)
            Spacer()
            if Self.isMarkdown(url) {
                PillSegmentedControl(
                    options: [.init(value: false, title: "Code"),
                              .init(value: true, title: "Preview")],
                    selection: $markdownPreview
                )
            }
            Button {
                showHistory.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13))
                    .foregroundStyle(showHistory ? Theme.accent : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle file history")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    private static let markdownExts: Set<String> = ["md", "markdown", "mdown", "mkd", "markdn"]
    private static func isMarkdown(_ url: URL) -> Bool {
        markdownExts.contains(url.pathExtension.lowercased())
    }

    @ViewBuilder
    private var fileViewer: some View {
        switch content {
        case .text(let code, let lang):
            if let url = selection, Self.isMarkdown(url), markdownPreview {
                MarkdownWebView(markdown: code)
            } else {
                FileViewerWebView(code: code, language: lang)
            }
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

    /// 우측 영역 — 히스토리 토글이 켜져 있고 파일이 선택돼 있으면 [뷰어 | 타임라인] 으로 분할.
    @ViewBuilder
    private var rightContent: some View {
        if showHistory, let url = selection, !isDirectory(url) {
            HStack(spacing: 0) {
                mainViewer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ResizableDivider(
                    width: $historyWidth,
                    minWidth: Self.historyMinWidth,
                    maxWidth: Self.historyMaxWidth,
                    reversed: true   // 패널이 분할선의 오른쪽 → 드래그 부호 반전
                )
                FileHistoryPanel(
                    history: fileHistory,
                    loading: loadingHistory,
                    selectedSHA: historyCommit?.sha,
                    commitFiles: commitFiles,
                    currentRelPath: selection.map { relativePath($0) },
                    onSelect: { selectHistoryCommit($0) },
                    onSelectFile: { jumpToRelatedFile($0) }
                )
                .frame(width: historyWidth)
            }
        } else {
            mainViewer
        }
    }

    /// 좌측 뷰어 — 히스토리 커밋이 선택돼 있으면 그 커밋 diff, 아니면 현재 워킹 버전.
    @ViewBuilder
    private var mainViewer: some View {
        if historyCommit != nil {
            if let diff = commitDiff {
                DiffWebView(content: .diff(diff))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            fileViewer
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    /// 선택 파일의 repo 루트(worktree) 기준 상대경로 — git 명령에 넘길 경로.
    private func relativePath(_ url: URL) -> String {
        let abs = url.path(percentEncoded: false)
        let prefix = currentPath.hasSuffix("/") ? currentPath : currentPath + "/"
        return abs.hasPrefix(prefix) ? String(abs.dropFirst(prefix.count)) : abs
    }

    /// 히스토리 토글이 켜져 있을 때만 선택 파일의 변경 커밋 목록을 로드.
    private func loadHistoryIfNeeded() async {
        guard showHistory, let url = selection, !isDirectory(url) else {
            fileHistory = []
            return
        }
        let path = currentPath
        let rel = relativePath(url)
        loadingHistory = true
        defer { loadingHistory = false }
        let h = (try? await GitService.fileHistory(repoPath: path, sha: "HEAD", path: rel)) ?? []
        // 로드 도중 선택이 또 바뀌었으면 결과 폐기.
        guard url == selection else { return }
        fileHistory = h
    }

    /// 히스토리에서 커밋 선택 → 부모 대비 diff + 그 커밋의 연관 파일 로드. nil 이면 워킹 버전으로 복귀.
    private func selectHistoryCommit(_ commit: GraphCommit?) {
        historyCommit = commit
        commitDiff = nil
        commitFiles = []
        guard let commit, let url = selection else { return }
        let path = currentPath
        let rel = relativePath(url)
        Task {
            async let diffTask = (try? await GitService.commitFileDiff(repoPath: path, sha: commit.sha, path: rel)) ?? ""
            async let filesTask = (try? await GitService.commitFiles(repoPath: path, sha: commit.sha)) ?? []
            let (d, f) = await (diffTask, filesTask)
            // 로드 도중 다른 커밋을 골랐으면 폐기.
            guard historyCommit?.sha == commit.sha else { return }
            commitDiff = d
            commitFiles = f
        }
    }

    /// 연관 파일 클릭 → 같은 커밋 컨텍스트를 유지한 채 그 파일로 selection 전환(트리 reveal 도 함께).
    private func jumpToRelatedFile(_ relPath: String) {
        let full = (currentPath as NSString).appendingPathComponent(relPath)
        let url = URL(fileURLWithPath: full).standardizedFileURL
        guard url != selection else { return }
        pendingKeepCommit = historyCommit
        selection = url
    }

    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]

    private func loadRoot() async {
        let path = currentPath
        // worktree 전환 시 즉시 스피너를 보이도록 트리를 비운다.
        root = nil
        trackedIndex = nil
        status = nil
        selection = nil
        let r = FileNode(url: URL(fileURLWithPath: path), isDirectory: true)
        await r.loadChildrenIfNeeded()
        r.isExpanded = true
        // 로드 도중 worktree 가 또 바뀌었으면 결과 폐기.
        guard path == currentPath else { return }
        root = r
        trackedIndex = try? await GitService.trackedIndex(repoPath: path)
        guard path == currentPath else { return }
        status = (try? await GitService.worktreeStatus(worktreePath: path)) ?? .clean
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
    /// 변경 파일 선택 시 이 경로로 스크롤(상단 변경 섹션에서 위치 확정).
    var scrollTarget: URL? = nil

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(root.children ?? []) { node in
                    FileTreeRow(node: node, selection: $selection)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Theme.editorSidebar)
            .overlayScrollbars()
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
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
