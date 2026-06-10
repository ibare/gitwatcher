//
//  FileHistoryPanel.swift
//  GitWatcher
//
//  파일 뷰어 우측의 변경 히스토리 타임라인(GitLens 스타일).
//  선택 파일이 변경된 커밋들을 시간순으로 보여주고, 커밋을 고르면 부모 대비 diff 로
//  좌측 뷰어가 전환된다. 맨 위 "Working tree" 는 현재 디스크 버전(히스토리 해제).
//  커밋 선택 시 그 커밋의 전체 메시지(COMMIT)와 함께 변경된 파일(FILES IN COMMIT)을
//  하단에 제공 — 파일을 클릭하면 같은 커밋 컨텍스트로 점프해 탐색을 이어간다.
//

import SwiftUI

struct FileHistoryPanel: View {
    let history: [GraphCommit]
    let loading: Bool
    /// 선택된 커밋. nil = Working tree(현재 디스크 버전).
    let selectedCommit: GraphCommit?
    /// 선택 커밋의 전체 메시지 본문(제목 제외).
    let commitBody: String
    /// 선택 커밋에서 함께 변경된 파일들(연관 파일).
    let commitFiles: [ChangedPath]
    /// 현재 보고 있는 파일의 repo 상대경로 — 연관 파일 목록에서 강조용.
    let currentRelPath: String?
    /// 히스토리 행 선택 콜백. nil 이면 Working tree 로 복귀.
    let onSelect: (GraphCommit?) -> Void
    /// 연관 파일 클릭 콜백(repo 상대경로).
    let onSelectFile: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            historyContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let commit = selectedCommit {
                Divider().opacity(0.5)
                commitDetail(commit)
                if !commitFiles.isEmpty {
                    Divider().opacity(0.5)
                    commitFilesSection
                }
            }
        }
        .background(Theme.editorSidebar)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("HISTORY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.editorText.opacity(0.8))
            if loading { ProgressView().controlSize(.mini) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: 시간축 타임라인 그래프

    /// 그래프 거터 폭과 노드 중심 y(행 상단 기준).
    private static let gutter: CGFloat = 26
    private static let nodeCenterY: CGFloat = 14
    /// 이 값을 넘는 커밋 간 공백은 "큰 갭"으로 점선 + 라벨 처리.
    private static let bigGapSeconds: TimeInterval = 14 * 86400

    private var lineColor: Color { Theme.editorText.opacity(0.22) }
    /// 큰 갭 물결 밴드의 채움/윤곽 — 흰색에 가까운 밝은 톤.
    // 배경(editorSidebar ≈ 0.145)보다 어둡게 — 채움은 블랙에 가깝게, 윤곽만 약간 밝혀 물결 형태를 음각처럼.
    private static let bandFill = Color(white: 0.08)
    private static let bandStroke = Color(white: 0.30)

    @ViewBuilder
    private var historyContent: some View {
        if history.isEmpty && !loading {
            VStack(spacing: 8) {
                workingRow
                Text("No commit history for this file")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.editorText.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, Self.gutter + 6)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    workingRow
                    ForEach(Array(history.enumerated()), id: \.element.id) { idx, commit in
                        // 위 항목(더 최신)과의 시간 갭을 간격으로 표현. idx==0 의 위 항목은 Working(now).
                        gapSpacer(olderDate: commit.date,
                                  newerDate: idx == 0 ? Date() : history[idx - 1].date)
                        commitRow(commit)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .overlayScrollbars()
        }
    }

    private var isWorkingSelected: Bool { selectedCommit == nil }

    // MARK: 행

    private var workingRow: some View {
        let selected = isWorkingSelected
        return HStack(spacing: 6) {
            graphGutter(hasTop: false, hasBottom: true,
                        nodeColor: selected ? Color.accentColor : Theme.dirty,
                        selected: selected)
            HStack(spacing: 6) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? Color.white : Theme.dirty)
                Text("Working tree")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Theme.editorText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(selected))
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(nil) }
    }

    private func commitRow(_ c: GraphCommit) -> some View {
        let selected = selectedCommit?.sha == c.sha
        return HStack(spacing: 6) {
            graphGutter(hasTop: true, hasBottom: true,
                        nodeColor: selected ? Color.accentColor : Color(white: 0.46),
                        selected: selected)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.subject)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Color.white : Theme.editorText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 5) {
                    Text(c.author).lineLimit(1)
                    Text("·")
                    Text(Fmt.relative(c.date))
                    Spacer(minLength: 4)
                    Text(c.shortSHA).monospaced()
                }
                .font(.system(size: 10))
                .foregroundStyle(selected ? Color.white.opacity(0.85) : Theme.editorText.opacity(0.55))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(selected))
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(c) }
        .help(c.subject)
    }

    private func rowBackground(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(selected ? Color.accentColor : Color.clear)
    }

    // MARK: 그래프 거터(세로선 + 노드)

    private func graphGutter(hasTop: Bool, hasBottom: Bool, nodeColor: Color, selected: Bool) -> some View {
        let r: CGFloat = selected ? 8 : 6.5
        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(hasTop ? lineColor : Color.clear)
                    .frame(width: 1.5, height: Self.nodeCenterY)
                Rectangle()
                    .fill(hasBottom ? lineColor : Color.clear)
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
            Circle()
                .fill(nodeColor)
                .frame(width: r * 2, height: r * 2)
                .overlay(Circle().stroke(Theme.editorSidebar, lineWidth: 2))
                .offset(y: Self.nodeCenterY - r)
        }
        .frame(width: Self.gutter)
        .frame(maxHeight: .infinity)
    }

    // MARK: 시간 갭 스페이서

    /// 두 커밋(olderDate↓ newerDate↑) 사이 공백을 시간에 비례한 높이로 그린다.
    /// 로그 스케일로 압축해 극단값이 화면을 독점하지 않게 하고, 큰 갭은 점선+라벨로 강조.
    private func gapSpacer(olderDate: Date, newerDate: Date) -> some View {
        let dt = newerDate.timeIntervalSince(olderDate)
        let big = dt > Self.bigGapSeconds
        let bandH: CGFloat = 26
        return Group {
            if big {
                // 큰 갭: 패널 전체 폭을 가로지르는 "접혀 잘린" 밴드 — 두 물결 사이를 밝게 채우고
                // 거터 세로선은 밴드 위/아래로 이어 커밋 라인과 자연스럽게 연결한다.
                ZStack {
                    // 거터 세로선(밴드 영역만 비움) — 위/아래 커밋 라인 연결
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            VLine().stroke(lineColor, style: StrokeStyle(lineWidth: 1.5))
                                .frame(maxHeight: .infinity)
                            Color.clear.frame(height: bandH)
                            VLine().stroke(lineColor, style: StrokeStyle(lineWidth: 1.5))
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: Self.gutter)
                        Spacer(minLength: 0)
                    }
                    // 밝게 채운 물결 밴드 + 기간 라벨
                    ZStack {
                        // 물결(채움+윤곽)만 양 끝 페이드 — 왼쪽은 점점 나타나고 오른쪽은 점점 사라지게.
                        ZStack {
                            WaveBand().fill(Self.bandFill)
                            WaveBand().stroke(Self.bandStroke, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                        }
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .white, location: 0.12),
                                    .init(color: .white, location: 0.88),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        // 라벨은 박스 없이 밝은 밴드 사이에 직접 — 텍스트 좌우만 밴드색으로 덮어 물결과 분리.
                        Text(Self.gapLabel(dt))
                            .font(.system(size: 10, weight: .medium).italic())
                            .foregroundStyle(Color(white: 0.45))
                            .padding(.horizontal, 6)
                            .background(Self.bandFill)
                    }
                    .frame(height: bandH)
                }
                .frame(maxWidth: .infinity)
                .frame(height: max(Self.gapHeight(dt), 46))
            } else {
                // 작은 갭: 거터 세로선만 연속.
                HStack(spacing: 6) {
                    VLine().stroke(lineColor, style: StrokeStyle(lineWidth: 1.5))
                        .frame(width: Self.gutter)
                    Spacer(minLength: 0)
                }
                .frame(height: Self.gapHeight(dt))
            }
        }
    }

    /// 시간 갭 → 픽셀 높이. 로그 스케일 + clamp.
    static func gapHeight(_ dt: TimeInterval) -> CGFloat {
        let days = max(0, dt / 86400)
        let h = 4 + 12 * log2(1 + days)
        return min(max(h, 4), 84)
    }

    /// 시간 갭 → 풀어쓴 라벨(3 weeks, 4 months …). 상징성이 있어 축약하지 않는다.
    static func gapLabel(_ dt: TimeInterval) -> String {
        let s = max(0, dt)
        let d = s / 86400
        func unit(_ n: Int, _ name: String) -> String {
            "\(n) \(name)\(n == 1 ? "" : "s")"
        }
        if d < 1 { return unit(max(1, Int(s / 3600)), "hour") }
        if d < 7 { return unit(Int(d), "day") }
        if d < 30 { return unit(Int(d / 7), "week") }
        if d < 365 { return unit(Int(d / 30), "month") }
        return unit(Int(d / 365), "year")
    }

    // MARK: 커밋 상세 (전체 메시지 + 메타)

    private func commitDetail(_ c: GraphCommit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COMMIT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.editorText.opacity(0.6))
            Text(c.subject)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.editorText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !commitBody.isEmpty {
                ScrollView {
                    Text(commitBody)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.editorText.opacity(0.7))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
            HStack(spacing: 5) {
                Text(c.author).lineLimit(1)
                Text("·")
                Text(c.shortSHA).monospaced()
                Text("·")
                Text(c.date.formatted(date: .abbreviated, time: .shortened)).lineLimit(1)
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.editorText.opacity(0.55))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 연관 파일 (이 커밋에서 함께 변경된 파일)

    private var commitFilesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FILES IN COMMIT (\(commitFiles.count))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.editorText.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(commitFiles) { file in
                        fileRow(file)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 220)
            .overlayScrollbars()
        }
    }

    private func fileRow(_ file: ChangedPath) -> some View {
        let isCurrent = file.path == currentRelPath
        let nameColor = isCurrent ? Theme.accent : Theme.editorText
        // 디렉토리는 보조 정보 — 파일명과 확실히 구분되도록 톤다운.
        let dirColor = (isCurrent ? Theme.accent : Theme.editorText).opacity(0.45)
        return HStack(spacing: 6) {
            Image(systemName: file.change.symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(file.change.tint)
                .frame(width: 12)
            (Text(Self.directoryPrefix(file.path)).foregroundStyle(dirColor)
             + Text(file.fileName).foregroundStyle(nameColor)
                .fontWeight(isCurrent ? .semibold : .regular))
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.head)   // 앞쪽(디렉토리) 말줄임 — 파일명 보존
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isCurrent ? Theme.accent.opacity(0.14) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelectFile(file.path) }
        .help(file.path)
    }

    /// "src/app/main.swift" → "src/app/" (루트 파일이면 빈 문자열).
    static func directoryPrefix(_ path: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir + "/"
    }
}

/// 거터 중앙을 세로로 잇는 실선 — 연속 커밋 사이 갭용.
private struct VLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

/// 큰 시간 갭을 가로지르는 "접혀 잘린" 물결 밴드 — 위/아래 두 sine 곡선 사이를 채운 닫힌 영역.
/// fill 로 밝은 단면을, stroke 로 곡선 윤곽을 그린다.
private struct WaveBand: Shape {
    var amplitude: CGFloat = 2.5   // 곡선이 출렁이는 정도
    var wavelength: CGFloat = 24   // 물결 주기
    var thickness: CGFloat = 19    // 위/아래 곡선 사이 두께(라벨 텍스트가 들어갈 만큼)

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        guard w > 0 else { return p }
        let steps = max(2, Int(w / 2))
        let topY = rect.midY - thickness / 2
        let botY = rect.midY + thickness / 2
        func waveY(_ baseY: CGFloat, _ x: CGFloat) -> CGFloat {
            baseY + amplitude * CGFloat(sin(Double(x / wavelength * 2 * .pi)))
        }
        // 위 곡선: 좌 → 우
        for i in 0...steps {
            let x = rect.minX + CGFloat(i) / CGFloat(steps) * w
            let y = waveY(topY, x)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        // 아래 곡선: 우 → 좌 (닫아서 영역 생성)
        for i in stride(from: steps, through: 0, by: -1) {
            let x = rect.minX + CGFloat(i) / CGFloat(steps) * w
            p.addLine(to: CGPoint(x: x, y: waveY(botY, x)))
        }
        p.closeSubpath()
        return p
    }
}
