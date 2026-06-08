//
//  GitRunner.swift
//  GitWatcher
//
//  읽기 전용 git 러너. 화이트리스트에 없는 서브커맨드는 타입 레벨에서 표현 불가하고,
//  진입점에서 한 번 더 검증한다. 모든 호출은 인자 배열로만 — 셸 문자열 보간 없음(인젝션 방지).
//

import Foundation

/// 허용된 읽기 전용 서브커맨드 화이트리스트.
/// write/state-changing 명령(checkout/commit/add/push/pull/fetch/merge/rebase/reset/
/// stash/clean/gc/worktree add|remove/branch -d 등)은 이 enum 에 존재하지 않는다.
nonisolated enum GitSubcommand: Sendable {
    case log
    case status
    case show
    case diff
    case diffTree
    case worktreeList     // `worktree list` 만 허용 (add/remove/prune 불가)
    case forEachRef
    case revList
    case revParse
    case catFile

    /// 실제 argv. worktreeList 는 두 토큰(`worktree`, `list`)으로 펼친다.
    var tokens: [String] {
        switch self {
        case .log:          return ["log"]
        case .status:       return ["status"]
        case .show:         return ["show"]
        case .diff:         return ["diff"]
        case .diffTree:     return ["diff-tree"]
        case .worktreeList: return ["worktree", "list"]
        case .forEachRef:   return ["for-each-ref"]
        case .revList:      return ["rev-list"]
        case .revParse:     return ["rev-parse"]
        case .catFile:      return ["cat-file"]
        }
    }
}

nonisolated enum GitError: Error, CustomStringConvertible {
    case launchFailed(String)
    case nonZeroExit(code: Int32, stderr: String)
    case notUTF8

    var description: String {
        switch self {
        case .launchFailed(let m): return "git 실행 실패: \(m)"
        case .nonZeroExit(let code, let stderr):
            return "git 종료 코드 \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .notUTF8: return "git 출력이 UTF-8 이 아님"
        }
    }
}

/// git 바이너리를 읽기 전용으로 셸아웃하는 진입점.
nonisolated enum GitRunner {
    /// 시스템 git. Command Line Tools / Xcode 모두 여기로 심볼릭된다.
    static let gitPath = "/usr/bin/git"

    /// `git -C <repoPath> <subcommand tokens...> <args...>` 를 실행하고 stdout 을 돌려준다.
    /// - Note: 인자는 전부 배열로 전달되어 셸을 거치지 않는다.
    nonisolated static func run(
        _ subcommand: GitSubcommand,
        _ args: [String] = [],
        in repoPath: String
    ) async throws -> String {
        let argv = ["-C", repoPath] + subcommand.tokens + args
        return try await runRaw(argv)
    }

    /// 실제 Process 실행. 백그라운드 스레드에서 동기 실행 후 continuation 으로 복귀.
    nonisolated private static func runRaw(_ argv: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: gitPath)
                process.arguments = argv

                // git 이 사용자 설정/시그닝/pager 등에 의존하지 않도록 환경을 최소화한다.
                var env = ProcessInfo.processInfo.environment
                env["GIT_PAGER"] = "cat"
                env["GIT_TERMINAL_PROMPT"] = "0"   // 자격증명 프롬프트 차단(로컬 전용)
                env["GIT_OPTIONAL_LOCKS"] = "0"     // 읽기 명령이 인덱스 락을 잡지 않게
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: GitError.launchFailed(error.localizedDescription))
                    return
                }

                // stdout 을 끝까지 읽은 뒤 종료를 기다린다(파이프 버퍼 데드락 방지).
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if process.terminationStatus != 0 {
                    let stderr = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: GitError.nonZeroExit(code: process.terminationStatus, stderr: stderr))
                    return
                }

                guard let out = String(data: outData, encoding: .utf8) else {
                    continuation.resume(throwing: GitError.notUTF8)
                    return
                }
                continuation.resume(returning: out)
            }
        }
    }
}
