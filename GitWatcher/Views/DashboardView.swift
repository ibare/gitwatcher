//
//  DashboardView.swift
//  GitWatcher
//
//  첫 화면. 상단 히트맵 + 카드 그리드. 카드 클릭 → 커밋 그래프 드릴다운.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DashboardView: View {
    @Environment(RepoStore.self) private var store
    @State private var path: [UUID] = []
    @State private var showImporter = false
    @State private var workingContext: DiffContext?

    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 460), spacing: 16)]

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.repos.isEmpty {
                        emptyState
                    } else {
                        HeatmapView(repos: store.repos, range: $store.heatmapRange)
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(store.repos) { repo in
                                RepoCardView(repo: repo, onOpenGraph: { path.append(repo.id) },
                                             onViewChanges: { wt in
                                    workingContext = .working(repoName: repo.displayName,
                                                              worktreePath: wt.path,
                                                              paths: wt.status.changedPaths)
                                })
                                    .contextMenu {
                                        Button("Reveal in Finder") { revealInFinder(repo.path) }
                                        Button("Refresh") { Task { await store.refresh(repo) } }
                                        Divider()
                                        Button("Remove", role: .destructive) { store.removeRepo(repo) }
                                    }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Git Watcher")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Add Repo", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let repo = store.repos.first(where: { $0.id == id }) {
                    RepoGraphScreen(repo: repo)
                } else {
                    Text("Repository not found").foregroundStyle(.secondary)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    Task {
                        for url in urls {
                            let needsScope = url.startAccessingSecurityScopedResource()
                            await store.addRepo(url: url)
                            if needsScope { url.stopAccessingSecurityScopedResource() }
                        }
                    }
                }
            }
        }
        .sheet(item: $workingContext) { ctx in
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") { workingContext = nil }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(10)
                Divider()
                CommitDetailView(context: ctx)
            }
            .frame(minWidth: 720, minHeight: 480)
        }
        .task { await store.refreshAll() }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No repositories yet")
                .font(.title3.weight(.semibold))
            Text("Add local git repositories to monitor their live status.\nGit Watcher is read-only — it never modifies your repos.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showImporter = true
            } label: {
                Label("Add Repository", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
