//
//  RepoWatcher.swift
//  GitWatcher
//
//  FSEvents 기반 라이브 변경 감지. 워킹트리를 raw 로 감시하면 node_modules·빌드 산출물
//  때문에 이벤트 폭풍이 나므로, FSEvents 는 300~500ms 디바운스 트리거로만 쓰고
//  실제 dirty 판정은 git status(gitignore 적용)로 한다. worktree 별 경로를 한 스트림에 묶는다.
//

import Foundation

/// 한 리포(모든 worktree 경로)를 감시하다 변경이 모이면 onChange 를 호출한다.
/// FSEvents 콜백이 백그라운드 큐에서 도므로 MainActor 격리를 받지 않는다.
/// 내부 가변 상태는 전용 직렬 큐로만 접근하므로 @unchecked Sendable.
nonisolated final class RepoWatcher: @unchecked Sendable {
    private let paths: [String]
    private let onChange: @Sendable () -> Void
    private let debounceInterval: TimeInterval

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.ibarestudio.GitWatcher.fsevents")
    private var debounceWork: DispatchWorkItem?

    init(paths: [String], debounce: TimeInterval = 0.4, onChange: @escaping @Sendable () -> Void) {
        self.paths = paths
        self.onChange = onChange
        self.debounceInterval = debounce
    }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }

        // C 콜백은 self 를 캡처할 수 없으므로 context.info 로 Unmanaged 포인터를 넘긴다.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepoWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleDebounced()
        }

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagIgnoreSelf
        )

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,                 // FSEvents 자체 latency 코얼레싱
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
        debounceWork?.cancel()
        debounceWork = nil
    }

    /// FSEvents 콜백이 몰아칠 때 마지막 한 번만 실제 새로고침을 트리거한다.
    private func scheduleDebounced() {
        queue.async { [weak self] in
            guard let self else { return }
            self.debounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onChange() }
            self.debounceWork = work
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: work)
        }
    }

    deinit { stop() }
}
