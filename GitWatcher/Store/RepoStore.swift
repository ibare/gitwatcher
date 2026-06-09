//
//  RepoStore.swift
//  GitWatcher
//
//  등록 리포 목록 영속화 + 라이브 상태 오케스트레이션.
//  무거운 git 질의는 nonisolated GitService 에서 돌고, 결과만 MainActor 모델에 반영한다.
//

import SwiftUI
import Observation

// MARK: - 리포 뷰모델 (런타임 상태)

enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

/// 카드 한 장의 라이브 상태. 영속화 대상이 아니며 매 새로고침마다 갱신된다.
@MainActor
@Observable
final class RepoViewModel: Identifiable {
    let id: UUID
    let path: String            // 등록된 메인 워킹 디렉토리 절대경로
    var displayName: String
    var subtitle: String?

    var worktrees: [Worktree] = []
    var commits: [GraphCommit] = []
    var refs: [GitRef] = []
    var totalCommits: Int = 0
    var lastCommitDate: Date?
    var trunk: String?


    var loadState: LoadState = .idle

    init(id: UUID = UUID(), path: String) {
        self.id = id
        self.path = path
        self.displayName = (path as NSString).lastPathComponent
    }

    /// worktree 들을 평탄화한 전체 변경 파일 수(카드 헤더 상태 dot 판정용 등).
    var isAnyDirty: Bool { worktrees.contains { !$0.status.isClean } }

    /// 단일 worktree 리포면 그 worktree, 아니면 main worktree.
    var primaryWorktree: Worktree? {
        worktrees.first(where: \.isMainWorktree) ?? worktrees.first
    }
}

// MARK: - 스토어

@MainActor
@Observable
final class RepoStore {
    private(set) var repos: [RepoViewModel] = []

    private var watchers: [UUID: RepoWatcher] = [:]
    private let defaultsKey = "GitWatcher.registeredRepos.v1"

    // 영속화 단위: 경로만 저장한다.
    private struct Registration: Codable {
        var id: UUID
        var path: String
        var subtitle: String?
    }

    init() {
        load()
    }

    // MARK: 영속화

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let regs = try? JSONDecoder().decode([Registration].self, from: data) else { return }
        for reg in regs {
            let vm = RepoViewModel(id: reg.id, path: reg.path)
            vm.subtitle = reg.subtitle
            repos.append(vm)
        }
    }

    private func persist() {
        let regs = repos.map { Registration(id: $0.id, path: $0.path, subtitle: $0.subtitle) }
        if let data = try? JSONEncoder().encode(regs) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: 등록/해제

    /// 폴더 추가. git 리포가 아니면 등록하지 않는다.
    func addRepo(url: URL) async {
        let path = url.path(percentEncoded: false)
        guard !repos.contains(where: { $0.path == path }) else { return }
        // git 리포인지 확인
        guard (try? await GitService.worktreeList(repoPath: path)) != nil else {
            return
        }
        let vm = RepoViewModel(path: path)
        repos.append(vm)
        persist()
        await refresh(vm)
        startWatching(vm)
    }

    func removeRepo(_ vm: RepoViewModel) {
        watchers[vm.id]?.stop()
        watchers[vm.id] = nil
        repos.removeAll { $0.id == vm.id }
        persist()
    }

    // MARK: 새로고침

    /// 앱 시작/포커스 시 전체 로드 + 워처 가동.
    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for vm in repos {
                group.addTask { await self.refresh(vm) }
            }
        }
        for vm in repos { startWatching(vm) }
    }

    /// 한 리포의 라이브 상태 + 그래프 + 스파크라인을 갱신한다.
    func refresh(_ vm: RepoViewModel) async {
        if vm.loadState == .idle { vm.loadState = .loading }
        do {
            let snap = try await GitService.snapshot(repoPath: vm.path)
            vm.worktrees = snap.worktrees
            vm.commits = snap.commits
            vm.refs = snap.refs
            vm.totalCommits = snap.totalCommits
            vm.lastCommitDate = snap.lastCommitDate
            vm.trunk = snap.trunk
            vm.loadState = .loaded
        } catch {
            vm.loadState = .failed("\(error)")
        }
    }

    // MARK: 워칭

    private func startWatching(_ vm: RepoViewModel) {
        guard watchers[vm.id] == nil else { return }
        // 등록 경로 + 모든 worktree 경로를 감시 대상으로.
        var paths = Set([vm.path])
        for wt in vm.worktrees { paths.insert(wt.path) }
        let id = vm.id
        let watcher = RepoWatcher(paths: Array(paths)) { [weak self] in
            // FSEvents 콜백(백그라운드) → MainActor 로 호핑해 새로고침.
            Task { @MainActor in
                guard let self, let vm = self.repos.first(where: { $0.id == id }) else { return }
                await self.refresh(vm)
            }
        }
        watcher.start()
        watchers[id] = watcher
    }
}
