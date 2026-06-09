//
//  CommitGraphView.swift
//  GitWatcher
//
//  GitKraken 스타일 커밋 그래프(네이티브 Canvas 렌더). 3컬럼 레이아웃:
//  [BRANCH / TAG] [GRAPH] [COMMIT MESSAGE]. 브랜치·태그·worktree HEAD 라벨은
//  왼쪽 컬럼으로 빼고, 라벨에서 해당 노드까지 연결선을 그어 소속을 명확히 한다.
//  고정 row-height 로 hit-test 를 단순화.
//

import SwiftUI
import AppKit

struct CommitGraphView: View {
    let layout: CommitGraphLayout
    let refsBySHA: [String: [GitRef]]
    let worktreeHeads: [String: [String]]    // sha → worktree 브랜치명 라벨들
    var wipStatus: [String: WorktreeStatus] = [:]   // "wip:<path>" → 워킹트리 상태
    @Binding var selection: String?
    var isLoadingMore = false                        // 다음 페이지 로딩 중
    var onReachEnd: () -> Void = {}                  // 끝 근처 도달 → 추가 로드 요청

    /// 가상 WIP(미커밋 변경) 노드 식별.
    private func isWip(_ sha: String) -> Bool { sha.hasPrefix("wip:") }

    // 고정 메트릭
    private let leftColWidth: CGFloat = 210     // BRANCH / TAG 컬럼
    private let rowH: CGFloat = 32
    private let laneW: CGFloat = 18
    private let nodeR: CGFloat = 5
    private let graphLead: CGFloat = 16         // 그래프 영역 내부 좌우 패딩

    private static let palette: [Color] = [
        .indigo, .blue, .teal, .green, .orange, .pink, .purple, .red, .cyan, .mint
    ]
    private func color(_ idx: Int) -> Color { Self.palette[idx % Self.palette.count] }

    private var graphWidth: CGFloat { graphLead * 2 + CGFloat(max(layout.columnCount, 1)) * laneW }
    private var canvasHeight: CGFloat { CGFloat(layout.placed.count) * rowH }

    private func x(_ col: Int) -> CGFloat { leftColWidth + graphLead + CGFloat(col) * laneW }
    private func y(_ row: Int) -> CGFloat { CGFloat(row) * rowH + rowH / 2 }

    /// 한 커밋에 붙은 라벨(worktree HEAD + local branch + remote-tracking + tag).
    private func labels(for sha: String) -> (worktrees: [String], branches: [GitRef], remotes: [GitRef], tags: [GitRef]) {
        let all = refsBySHA[sha] ?? []
        return (worktreeHeads[sha] ?? [],
                all.filter { $0.kind == .branch },
                all.filter { $0.kind == .remote },
                all.filter { $0.kind == .tag })
    }
    private func hasLabel(_ sha: String) -> Bool {
        let l = labels(for: sha)
        return !l.worktrees.isEmpty || !l.branches.isEmpty || !l.remotes.isEmpty || !l.tags.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            graphCanvas
                            rowsOverlay
                        }
                        .frame(height: canvasHeight, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        if isLoadingMore {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                    }
                }
                .overlayScrollbars()
                .focusable()
                .focusEffectDisabled()   // 키보드 이동은 유지, 파란 포커스 링만 제거
                .onMoveCommand { move($0, proxy: proxy) }
            }
        }
    }

    // MARK: 헤더 (컬럼 타이틀)

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("BRANCH / TAG")
                .frame(width: leftColWidth, alignment: .leading)
                .padding(.leading, 14)
            Text("GRAPH")
                .frame(width: graphWidth, alignment: .leading)
            Text("COMMIT MESSAGE")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: 그래픽 레이어 (연결선 + 엣지 + 노드)

    private var graphCanvas: some View {
        Canvas { ctx, _ in
            // 1) 라벨 → 노드 연결선 (가장 아래 레이어)
            for pc in layout.placed where hasLabel(pc.commit.sha) {
                let yy = y(pc.row)
                var path = Path()
                path.move(to: CGPoint(x: leftColWidth - 8, y: yy))
                path.addLine(to: CGPoint(x: x(pc.column), y: yy))
                ctx.stroke(path, with: .color(color(pc.colorIndex).opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 3]))
            }

            // 2) 엣지 (WIP 에서 나가는 엣지는 점선)
            for pc in layout.placed {
                let fromPt = CGPoint(x: x(pc.column), y: y(pc.row))
                let wip = isWip(pc.commit.sha)
                for edge in pc.edges {
                    let toRow = edge.toRow ?? layout.placed.count
                    var path = Path()
                    path.move(to: fromPt)
                    if edge.toColumn != pc.column {
                        path.addLine(to: CGPoint(x: x(edge.toColumn), y: y(pc.row) + rowH))
                    }
                    path.addLine(to: CGPoint(x: x(edge.toColumn), y: y(toRow)))
                    let style = wip
                        ? StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [3, 3])
                        : StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    let col = wip ? Theme.dirty : color(edge.colorIndex)
                    ctx.stroke(path, with: .color(col.opacity(0.85)), style: style)
                }
            }

            // 3) 노드 (WIP 는 채우지 않은 점선 원)
            for pc in layout.placed {
                let c = CGPoint(x: x(pc.column), y: y(pc.row))
                if isWip(pc.commit.sha) {
                    let r = nodeR + 0.5
                    let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Circle().path(in: rect), with: .color(Color(nsColor: .windowBackgroundColor)))
                    ctx.stroke(Circle().path(in: rect), with: .color(Theme.dirty),
                               style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                    continue
                }
                let isHead = worktreeHeads[pc.commit.sha] != nil
                let r = isHead ? nodeR + 1.5 : nodeR
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                ctx.fill(Circle().path(in: rect), with: .color(color(pc.colorIndex)))
                ctx.stroke(Circle().path(in: rect),
                           with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 1.5)
                if isHead {
                    let ring = rect.insetBy(dx: -2.5, dy: -2.5)
                    ctx.stroke(Circle().path(in: ring), with: .color(color(pc.colorIndex)), lineWidth: 1.5)
                }
            }
        }
        .frame(width: leftColWidth + graphWidth, height: canvasHeight)
    }

    // MARK: 행 오버레이 (라벨 칩 + 커밋 메타 + 선택)

    private var rowsOverlay: some View {
        // LazyVStack: 가시 영역의 행만 렌더 → onAppear 가 실제 스크롤 가시성을 반영(무한 prefetch 방지).
        LazyVStack(spacing: 0) {
            ForEach(layout.placed) { pc in
                let l = labels(for: pc.commit.sha)
                HStack(spacing: 0) {
                    // BRANCH / TAG 컬럼 (우측정렬 → 노드 쪽으로)
                    HStack(spacing: 5) {
                        Spacer(minLength: 0)
                        ForEach(l.worktrees, id: \.self) { name in
                            LabelChip(text: name, kind: .worktree, color: color(pc.colorIndex))
                        }
                        ForEach(l.branches, id: \.name) { ref in
                            LabelChip(text: ref.name, kind: .branch, color: color(pc.colorIndex))
                        }
                        ForEach(l.remotes, id: \.name) { ref in
                            LabelChip(text: ref.name, kind: .remote, color: color(pc.colorIndex))
                        }
                        ForEach(l.tags, id: \.name) { ref in
                            LabelChip(text: ref.name, kind: .tag, color: color(pc.colorIndex))
                        }
                    }
                    .frame(width: leftColWidth, alignment: .trailing)
                    .padding(.trailing, 8)

                    // GRAPH 컬럼 (Canvas 가 그림 — 여기선 클릭 영역만)
                    Color.clear.frame(width: graphWidth)

                    // COMMIT MESSAGE 컬럼
                    messageCell(pc.commit)
                }
                .frame(height: rowH)
                .background(selection == pc.commit.sha ? Theme.accent.opacity(0.12) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { selection = pc.commit.sha }
                .id(pc.commit.sha)
                .onAppear {
                    // 끝에서 약간 앞 행이 보이면 미리 다음 페이지를 당겨온다.
                    if pc.id == prefetchTriggerID { onReachEnd() }
                }
            }
        }
    }

    /// 무한 스크롤 prefetch 를 트리거할 행(끝에서 12번째쯤).
    private var prefetchTriggerID: String? {
        let placed = layout.placed
        guard !placed.isEmpty else { return nil }
        return placed[max(0, placed.count - 12)].id
    }

    @ViewBuilder
    private func messageCell(_ commit: GraphCommit) -> some View {
        if isWip(commit.sha), let st = wipStatus[commit.sha] {
            // WIP 행: 미커밋 변경 요약
            HStack(spacing: 8) {
                Image(systemName: "pencil.line").font(.caption2)
                Text("Uncommitted changes")
                    .font(.callout.weight(.medium))
                Text("·").foregroundStyle(.secondary)
                Text("\(st.changedFiles) \(st.changedFiles == 1 ? "file" : "files")")
                    .font(.caption)
                if st.insertions > 0 || st.deletions > 0 {
                    Text("+\(st.insertions)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.clean)
                    Text("−\(st.deletions)").font(.caption2.monospacedDigit()).foregroundStyle(.red)
                }
                Spacer(minLength: 8)
            }
            .foregroundStyle(Theme.dirty)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                Text(commit.subject)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(commit.shortSHA)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                Text(commit.author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 키보드 내비

    private func move(_ direction: MoveCommandDirection, proxy: ScrollViewProxy) {
        guard !layout.placed.isEmpty else { return }
        let currentRow = layout.placed.first(where: { $0.commit.sha == selection })?.row ?? 0
        let nextRow: Int
        switch direction {
        case .up:   nextRow = max(currentRow - 1, 0)
        case .down: nextRow = min(currentRow + 1, layout.placed.count - 1)
        default:    return
        }
        let sha = layout.placed[nextRow].commit.sha
        selection = sha
        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(sha, anchor: .center) }
    }
}

// MARK: - 라벨 칩

private struct LabelChip: View {
    enum Kind { case worktree, branch, remote, tag }
    let text: String
    let kind: Kind
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).lineLimit(1).truncationMode(.middle)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(background, in: Capsule())
        .foregroundStyle(foreground)
        .overlay(Capsule().stroke(strokeColor, lineWidth: 1))
    }

    private var icon: String {
        switch kind {
        case .worktree: return "house.fill"
        case .branch:   return "arrow.triangle.branch"
        case .remote:   return "cloud.fill"
        case .tag:      return "tag.fill"
        }
    }
    private var background: Color {
        switch kind {
        case .worktree: return color.opacity(0.18)
        case .branch:   return Color.secondary.opacity(0.12)
        case .remote:   return Theme.diverged.opacity(0.14)
        case .tag:      return Color.orange.opacity(0.15)
        }
    }
    private var foreground: Color {
        switch kind {
        case .worktree: return color
        case .branch:   return .secondary
        case .remote:   return Theme.diverged
        case .tag:      return .orange
        }
    }
    private var strokeColor: Color {
        switch kind {
        case .worktree: return color.opacity(0.35)
        default:        return .clear
        }
    }
}
