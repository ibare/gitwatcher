//
//  CommitGraphView.swift
//  GitWatcher
//
//  GitKraken 스타일 커밋 그래프(네이티브 Canvas 렌더). 고정 row-height 로 hit-test 를 단순화.
//  엣지/노드는 Canvas 로, 커밋 메타/선택은 그 위에 행 오버레이로 그린다.
//

import SwiftUI
import AppKit

struct CommitGraphView: View {
    let layout: CommitGraphLayout
    let refsBySHA: [String: [GitRef]]
    let worktreeHeads: [String: [String]]    // sha → worktree 브랜치명 라벨들
    @Binding var selection: String?

    // 고정 메트릭
    private let rowH: CGFloat = 30
    private let laneW: CGFloat = 18
    private let nodeR: CGFloat = 5
    private let leftPad: CGFloat = 16

    private static let palette: [Color] = [
        .indigo, .blue, .teal, .green, .orange, .pink, .purple, .red, .cyan, .mint
    ]
    private func color(_ idx: Int) -> Color { Self.palette[idx % Self.palette.count] }

    private var graphWidth: CGFloat { leftPad + CGFloat(layout.columnCount) * laneW + leftPad }
    private var canvasHeight: CGFloat { CGFloat(layout.placed.count) * rowH }

    private func x(_ col: Int) -> CGFloat { leftPad + CGFloat(col) * laneW }
    private func y(_ row: Int) -> CGFloat { CGFloat(row) * rowH + rowH / 2 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    edgesAndNodes
                    rowsOverlay
                }
                .frame(height: canvasHeight, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .focusable()
            .onMoveCommand { direction in
                move(direction, proxy: proxy)
            }
        }
    }

    /// 위/아래 화살표로 선택 커밋을 이동하고 해당 행으로 스크롤.
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

    // MARK: 그래픽 레이어 (엣지 + 노드)

    private var edgesAndNodes: some View {
        Canvas { ctx, _ in
            // 엣지 먼저(노드 아래로)
            for pc in layout.placed {
                let fromPt = CGPoint(x: x(pc.column), y: y(pc.row))
                for edge in pc.edges {
                    let toRow = edge.toRow ?? layout.placed.count       // 범위 밖이면 바닥으로
                    var path = Path()
                    path.move(to: fromPt)
                    if edge.toColumn != pc.column {
                        // 한 행 내려가며 열 이동 후 부모까지 수직
                        path.addLine(to: CGPoint(x: x(edge.toColumn), y: y(pc.row) + rowH))
                    }
                    path.addLine(to: CGPoint(x: x(edge.toColumn), y: y(toRow)))
                    ctx.stroke(path, with: .color(color(edge.colorIndex).opacity(0.85)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            // 노드
            for pc in layout.placed {
                let c = CGPoint(x: x(pc.column), y: y(pc.row))
                let isHead = worktreeHeads[pc.commit.sha] != nil
                let r = isHead ? nodeR + 1.5 : nodeR
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                ctx.fill(Circle().path(in: rect), with: .color(color(pc.colorIndex)))
                // 노드 외곽(배경색으로 분리)
                ctx.stroke(Circle().path(in: rect),
                           with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 1.5)
                if isHead {
                    // worktree HEAD: 링 강조
                    let ring = rect.insetBy(dx: -2.5, dy: -2.5)
                    ctx.stroke(Circle().path(in: ring), with: .color(color(pc.colorIndex)), lineWidth: 1.5)
                }
            }
        }
        .frame(width: graphWidth, height: canvasHeight)
    }

    // MARK: 행 오버레이 (ref/worktree 라벨 + 커밋 메타 + 선택)

    private var rowsOverlay: some View {
        VStack(spacing: 0) {
            ForEach(layout.placed) { pc in
                CommitRow(
                    placed: pc,
                    refs: refsBySHA[pc.commit.sha] ?? [],
                    worktreeLabels: worktreeHeads[pc.commit.sha] ?? [],
                    isSelected: selection == pc.commit.sha,
                    leadingInset: graphWidth,
                    accent: color(pc.colorIndex)
                )
                .frame(height: rowH)
                .contentShape(Rectangle())
                .onTapGesture { selection = pc.commit.sha }
                .id(pc.commit.sha)
            }
        }
    }
}

private struct CommitRow: View {
    let placed: PlacedCommit
    let refs: [GitRef]
    let worktreeLabels: [String]
    let isSelected: Bool
    let leadingInset: CGFloat
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: leadingInset)

            // worktree HEAD 마커
            ForEach(worktreeLabels, id: \.self) { label in
                Label(label, systemImage: "house.fill")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(accent)
            }
            // ref 칩
            ForEach(refs.filter { $0.kind == .branch || $0.kind == .tag }, id: \.name) { ref in
                Text(ref.name)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Text(placed.commit.subject)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(placed.commit.shortSHA)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            Text(placed.commit.author)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Theme.accent.opacity(0.12) : Color.clear)
    }
}
