//
//  HeatmapView.swift
//  GitWatcher
//
//  커밋 활동 히트맵. 행 = 리포, 열 = 날짜, 셀 강도 = 일자별 커밋 수.
//  Last 30 days / All time 토글.
//

import SwiftUI

struct HeatmapView: View {
    let repos: [RepoViewModel]
    @Binding var range: RepoStore.HeatmapRange

    private let cell: CGFloat = 11
    private let gap: CGFloat = 2
    private let labelWidth: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Commit activity")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("", selection: $range) {
                    ForEach(RepoStore.HeatmapRange.allCases) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .labelsHidden()
            }

            let columns = dateColumns
            if columns.isEmpty || repos.isEmpty {
                Text("No activity yet")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: gap) {
                        ForEach(repos) { repo in
                            HStack(spacing: gap) {
                                Text(repo.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: labelWidth, alignment: .leading)

                                ForEach(columns, id: \.self) { day in
                                    let count = repo.dailyCounts[day] ?? 0
                                    let intensity = intensityFor(count: count, repo: repo)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Theme.heatColor(intensity: intensity))
                                        .frame(width: cell, height: cell)
                                        .help("\(repo.displayName) · \(day): \(count) commits")
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardStroke, lineWidth: 1))
    }

    /// 표시할 날짜 컬럼(오래된→최신). 30일 모드는 고정 30칸, all time 은 데이터 범위.
    private var dateColumns: [String] {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        if range == .last30Days {
            return (0..<30).reversed().compactMap { offset in
                cal.date(byAdding: .day, value: -offset, to: today).map { fmt.string(from: $0) }
            }
        }

        // all time: 모든 리포 통틀어 가장 이른 날짜 ~ 오늘
        let allDays = repos.flatMap { $0.dailyCounts.keys }
        guard let earliest = allDays.min(), let start = fmt.date(from: earliest) else { return [] }
        var cols: [String] = []
        var d = cal.startOfDay(for: start)
        // 너무 많아지지 않게 일 단위(최대 약 2년) — 더 길면 주 단위로 떨어뜨릴 수 있으나 일단 일 단위 캡.
        let maxDays = 730
        var guardCount = 0
        while d <= today && guardCount < maxDays {
            cols.append(fmt.string(from: d))
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
            guardCount += 1
        }
        return cols
    }

    /// 리포별 최댓값 기준으로 정규화한 강도.
    private func intensityFor(count: Int, repo: RepoViewModel) -> Double {
        guard count > 0 else { return 0 }
        let maxV = repo.dailyCounts.values.max() ?? 1
        return Double(count) / Double(max(maxV, 1))
    }
}
