//
//  CommitGraphLayout.swift
//  GitWatcher
//
//  커밋 그래프 레인 배치. 커밋을 date-order 로 위→아래 훑으며 활성 레인을 관리한다.
//  methii 처럼 worktree 가 여럿이어도 .git 공유 + log --all 로 한 그래프에 통합된다.
//

import Foundation

/// 레인 배치 결과의 한 커밋.
nonisolated struct PlacedCommit: Identifiable {
    let commit: GraphCommit
    let row: Int
    let column: Int
    let colorIndex: Int      // 노드가 놓인 레인의 색
    /// 이 커밋에서 부모로 향하는 엣지.
    let edges: [GraphEdge]
    var id: String { commit.sha }
}

nonisolated struct GraphEdge {
    let toColumn: Int
    let toRow: Int?          // nil = 로드된 범위 밖(화면 아래로 흘려보냄)
    let colorIndex: Int      // 색 팔레트 인덱스
}

nonisolated struct CommitGraphLayout {
    let placed: [PlacedCommit]
    let columnCount: Int

    /// date-order 커밋 배열을 받아 column/edge 를 배치한다.
    static func build(commits: [GraphCommit]) -> CommitGraphLayout {
        // sha → row index
        var rowOf: [String: Int] = [:]
        for (i, c) in commits.enumerated() { rowOf[c.sha] = i }

        var lanes: [String?] = []          // 각 레인이 다음에 기다리는 부모 sha
        var laneColor: [Int] = []          // 레인별 색 인덱스(분기마다 증가)
        var nextColor = 0
        var placed: [PlacedCommit] = []
        var maxColumns = 0

        func allocLane(for sha: String) -> Int {
            if let empty = lanes.firstIndex(where: { $0 == nil }) {
                lanes[empty] = sha
                return empty
            }
            lanes.append(sha)
            laneColor.append(0)
            return lanes.count - 1
        }

        for (i, commit) in commits.enumerated() {
            // 이 커밋을 기다리던 레인들(여러 자식이 같은 커밋을 가리키면 다수)
            let waiting = lanes.indices.filter { lanes[$0] == commit.sha }
            let col: Int
            if let first = waiting.first {
                col = first
            } else {
                // 분기 tip: 새 레인 + 새 색
                col = allocLane(for: commit.sha)
                laneColor[col] = nextColor
                nextColor += 1
            }
            let myColor = laneColor.indices.contains(col) ? laneColor[col] : 0

            // 합류: 같은 커밋을 기다리던 다른 레인들은 비운다
            for w in waiting where w != col { lanes[w] = nil }

            // 부모 배치 + 엣지
            var edges: [GraphEdge] = []
            if commit.parents.isEmpty {
                lanes[col] = nil          // 루트
            } else {
                // 첫 부모: 현재 레인 계승(색 유지)
                lanes[col] = commit.parents[0]
                edges.append(GraphEdge(toColumn: col, toRow: rowOf[commit.parents[0]], colorIndex: myColor))

                // 나머지 부모(머지): 기존 레인에 합류하거나 새 레인
                for p in commit.parents.dropFirst() {
                    let pcol: Int
                    let pcolor: Int
                    if let existing = lanes.firstIndex(where: { $0 == p }) {
                        pcol = existing
                        pcolor = laneColor.indices.contains(existing) ? laneColor[existing] : myColor
                    } else {
                        pcol = allocLane(for: p)
                        pcolor = nextColor
                        laneColor[pcol] = nextColor
                        nextColor += 1
                    }
                    edges.append(GraphEdge(toColumn: pcol, toRow: rowOf[p], colorIndex: pcolor))
                }
            }

            placed.append(PlacedCommit(commit: commit, row: i, column: col, colorIndex: myColor, edges: edges))
            maxColumns = max(maxColumns, lanes.count)
        }

        return CommitGraphLayout(placed: placed, columnCount: max(maxColumns, 1))
    }
}
