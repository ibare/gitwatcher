//
//  SparklineView.swift
//  GitWatcher
//
//  일자별 커밋 추이 스파크라인. 데이터 없으면 호출측에서 "No recent activity" 표시.
//

import SwiftUI

struct SparklineView: View {
    let values: [Int]          // 오래된 → 최신 순
    var color: Color = Theme.accent

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let maxV = values.max(), maxV > 0 else { return }
            let stepX = size.width / CGFloat(values.count - 1)
            let scaleY = size.height / CGFloat(maxV)

            var path = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height - CGFloat(v) * scaleY
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

            // 면 채우기(은은하게)
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(color.opacity(0.12)))
        }
    }
}

/// dailyCounts 딕셔너리 → 최근 N일 정렬 배열로 변환하는 헬퍼.
enum DailySeries {
    static func recent(_ counts: [String: Int], days: Int) -> [Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        var series: [Int] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            series.append(counts[fmt.string(from: d)] ?? 0)
        }
        return series
    }
}
